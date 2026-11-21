import Foundation

/// Self-contained vector artwork suitable for an AppKit preview and insertion into PowerPoint.
enum VectorAsset {
    static func accepts(_ svg: String) -> Bool {
        guard svg.utf8.count <= 200_000,
              svg.range(of: "<!", options: .caseInsensitive) == nil,
              svg.range(of: "<?", options: .caseInsensitive) == nil else { return false }
        let checker = VectorChecker()
        let parser = XMLParser(data: Data(svg.utf8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = checker
        return parser.parse() && checker.valid && checker.count > 0
    }
}

private final class VectorChecker: NSObject, XMLParserDelegate {
    var valid = true
    var count = 0
    private let elements: Set<String> = [
        "svg", "g", "defs", "path", "rect", "circle", "ellipse", "polygon", "polyline", "line",
        "text", "tspan", "title", "desc", "linearGradient", "radialGradient", "stop", "clipPath"
    ]
    private let attributes: Set<String> = [
        "xmlns", "viewBox", "width", "height", "id", "x", "y", "dx", "dy", "x1", "x2", "y1", "y2",
        "cx", "cy", "rx", "ry", "r", "fx", "fy", "d", "points", "transform", "fill", "fill-rule",
        "fill-opacity", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin", "stroke-opacity",
        "stroke-dasharray", "opacity", "text-anchor", "font-family", "font-size", "font-weight",
        "dominant-baseline", "offset", "stop-color", "stop-opacity", "gradientUnits",
        "gradientTransform", "clip-path", "preserveAspectRatio"
    ]

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes values: [String: String]) {
        count += 1
        guard count <= 4096, elements.contains(name), count > 1 || name == "svg",
              values.allSatisfy({ key, value in
                  guard attributes.contains(key) else { return false }
                  if key == "xmlns" { return value == "http://www.w3.org/2000/svg" }
                  if value.localizedCaseInsensitiveContains("url") {
                      return value.range(of: #"^url\(#[a-zA-Z_][a-zA-Z0-9_.-]*\)$"#, options: .regularExpression) != nil
                  }
                  return !value.contains("\\")
              }) else {
            valid = false
            parser.abortParsing()
            return
        }
    }
}
