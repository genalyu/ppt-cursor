#!/bin/sh
# Read-only local diagnostics. Does not read credentials or send network requests.
set -u
failed=0
check() {
    if command -v "$1" >/dev/null 2>&1; then
        printf 'OK   %s\n' "$1"
    else
        printf '缺少 %s\n' "$1"
        failed=1
    fi
}
check swift
check python3
if python3 -c 'from PIL import Image' >/dev/null 2>&1; then
    printf 'OK   Pillow\n'
else
    printf '缺少 Pillow：在 Python 虚拟环境中运行 pip install -r requirements.txt\n'
    failed=1
fi
for app in 'Microsoft PowerPoint' LibreOffice; do
    if [ -d "/Applications/$app.app" ]; then
        printf 'OK   %s\n' "$app"
    elif [ "$app" = LibreOffice ] && command -v soffice >/dev/null 2>&1; then
        printf 'OK   LibreOffice (PATH)\n'
    else
        printf '缺少 %s：请安装桌面应用\n' "$app"
        failed=1
    fi
done
if command -v codex >/dev/null 2>&1; then
    printf 'OK   Codex CLI（也可在应用内选择 API）\n'
else
    printf '提示 Codex CLI 未在 PATH 中；可在应用内配置 API\n'
fi
exit "$failed"
