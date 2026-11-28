"""Keyless, model-directed Commons image search with bounded, verified downloads.

Only public-domain/CC0 images are offered for automatic insertion. Sources and
license metadata travel with the preview and the picture's alternative text.
"""
import io
import json
import re
import time
from html import unescape
from pathlib import Path
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, HTTPRedirectHandler, build_opener

USER_AGENT = "PPTCursor/0.1 (https://github.com/genalyu/ppt-cursor)"
HOSTS = {"commons.wikimedia.org", "upload.wikimedia.org"}


def allowed_url(url):
    try:
        parts = urlsplit(url)
        return (parts.scheme == "https" and parts.hostname in HOSTS and parts.port is None
                and parts.username is None and parts.password is None and not parts.fragment)
    except (TypeError, ValueError):
        return False


class VerifiedRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not allowed_url(newurl):
            raise ValueError("素材地址重定向至不支持的来源")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch(url, limit):
    if not allowed_url(url):
        raise ValueError("素材来源地址无效")
    request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json,image/*"})
    with build_opener(VerifiedRedirect()).open(request, timeout=12) as response:
        payload = response.read(limit + 1)
    if len(payload) > limit:
        raise ValueError("素材文件超出大小限制")
    return payload


def plain(value):
    return unescape(re.sub(r"<[^>]*>", "", str(value)))[:500].strip()


def candidates(payload):
    pages = payload.get("query", {}).get("pages", [])
    if not isinstance(pages, list):
        return []
    result = []
    for page in sorted((p for p in pages if isinstance(p, dict)), key=lambda p: p.get("index", 999)):
        info = page.get("imageinfo")
        if not isinstance(info, list) or not info or not isinstance(info[0], dict):
            continue
        info = info[0]
        metadata = info.get("extmetadata", {})
        def value(key):
            entry = metadata.get(key, {})
            return plain(entry.get("value", "")) if isinstance(entry, dict) else ""
        license_name = value("LicenseShortName")
        if license_name.lower() not in {"public domain", "cc0", "cc0 1.0"}:
            continue
        image_url = info.get("thumburl") or info.get("url")
        page_url = info.get("descriptionurl")
        if not allowed_url(image_url) or not allowed_url(page_url):
            continue
        if urlsplit(image_url).hostname != "upload.wikimedia.org":
            continue
        if not str(info.get("mime", "")).startswith("image/"):
            continue
        result.append({"title": plain(page.get("title", "Image")).removeprefix("File:"),
                       "sourceURL": page_url, "imageURL": image_url, "license": license_name,
                       "creator": value("Artist"), "credit": value("Credit")})
    return result


def search_images(query, directory, check_current=None):
    """Return at most three normalized local images and their trusted provenance."""
    from PIL import Image, ImageOps, UnidentifiedImageError
    if not isinstance(query, str) or not 1 <= len(query.strip()) <= 160:
        raise ValueError("素材搜索关键词无效")
    if any(ord(char) < 32 for char in query):
        raise ValueError("素材搜索关键词包含控制字符")
    if check_current:
        check_current()
    params = {"action": "query", "format": "json", "formatversion": 2,
              "generator": "search", "gsrsearch": query.strip(), "gsrnamespace": 6,
              "gsrlimit": 20, "prop": "imageinfo", "iiprop": "url|mime|extmetadata", "iiurlwidth": 1200}
    payload = json.loads(fetch("https://commons.wikimedia.org/w/api.php?" + urlencode(params), 2_000_000))
    if not isinstance(payload, dict):
        raise ValueError("素材搜索返回格式无效")
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    assets = []
    deadline = time.monotonic() + 35
    for item in candidates(payload):
        if len(assets) == 3 or time.monotonic() >= deadline:
            break
        if check_current:
            check_current()
        try:
            data = fetch(item["imageURL"], 8_000_000)
            with Image.open(io.BytesIO(data)) as original:
                if original.format not in {"PNG", "JPEG", "WEBP"} or original.width * original.height > 30_000_000:
                    continue
                image = ImageOps.exif_transpose(original)
                image.thumbnail((1600, 1600), Image.Resampling.LANCZOS)
                path = directory / f"web-{len(assets)}.png"
                image.convert("RGBA").save(path)
            assets.append({**item, "path": path})
        except (OSError, ValueError, UnidentifiedImageError, Image.DecompressionBombError):
            continue
    if check_current:
        check_current()
    return assets
