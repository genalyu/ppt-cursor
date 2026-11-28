#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build --target CursorCore
bin=$(swift build --show-bin-path)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
import CursorCore

final class MockAPI: URLProtocol {
    static var unchanged = false
    static var overrideSuggestion: String?
    static var malformed = false
    static var code = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        precondition(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only")
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = stream.read(&buffer, maxLength: buffer.count)
                precondition(n >= 0)
                if n == 0 { break }
                data.append(contentsOf: buffer.prefix(n))
            }
        }
        let body = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        precondition(body["store"] as? Bool == false)
        precondition(body["model"] as? String == "test-model")
        let input = body["input"] as! [[String: Any]]
        let content = input[0]["content"] as! [[String: String]]
        let prompt = content[0]["text"]!
        precondition(content.count == 3 && prompt.contains("transitions") && !prompt.contains("fixture"))
        precondition(content[1]["image_url"] == "data:image/png;base64,AQ==")
        precondition(content[2]["image_url"] == "data:image/png;base64,Ag==")
        let suggestion = #"{"summary":"Align","edits":[{"id":"a","placement":{"x":5,"y":5,"width":10,"height":10},"rotation":0,"text":null}],"artwork":[]}"#
        let output = Self.unchanged ? suggestion.replacingOccurrences(of: #""x":5,"y":5"#, with: #""x":2,"y":0"#) : suggestion
        let payload: [String: Any] = ["status": "completed", "output": [["type": "message", "content": [["type":"output_text","text":Self.malformed ? "broken" : (Self.overrideSuggestion ?? output)]]]]]
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: payload))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func state(_ x: Int, multiline: Bool = false) throws -> SlideSnapshot {
    let object = #"{"document":"fixture","slideID":1,"width":100,"height":100,"objects":[{"id":"a","name":"A","kind":"rect","x":X,"y":0,"width":10,"height":10,"rotation":0}]}"#
    let page = multiline ? object.replacingOccurrences(of: #""kind":"rect""#, with: #""kind":"rect","text":"A\rB""#) : object
    return try JSONDecoder().decode(SlideSnapshot.self, from: Data(page.replacingOccurrences(of:"X",with:String(x)).utf8))
}
var history = EditHistory()
_ = try history.observe(state(0))
let context = try history.observe(state(2))!
let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [MockAPI.self]
let session = URLSession(configuration: config)
let model = APIPredictor(settings: APISettings(model: "previous-model", key: "test-only").selecting(model: "test-model"), session: session)
let image = ReferenceImage(name: "card", png: Data([3]), thumbnail: Data([2]))
let result = try model.predict(context, images: [image], currentPage: Data([1]))
precondition(result.edits.first?.id == "a")
MockAPI.unchanged = true
let unchanged = try model.predict(context, images: [image], currentPage: Data([1]))
precondition(unchanged.edits.isEmpty && unchanged.artwork.isEmpty)
MockAPI.unchanged = false
var textHistory = EditHistory()
_ = try textHistory.observe(state(0, multiline: true))
let textContext = try textHistory.observe(state(2, multiline: true))!
for separator in [#"\n"#, #"\r\n"#] {
    MockAPI.overrideSuggestion = #"{"summary":"Text","edits":[{"id":"a","placement":{"x":2,"y":0,"width":10,"height":10},"rotation":0,"text":"A"# + separator + #"B"}],"artwork":[]}"#
    let same = try model.predict(textContext, images: [image], currentPage: Data([1]))
    precondition(same.edits.isEmpty)
}
for angle in [360, -720, -90] {
    MockAPI.overrideSuggestion = #"{"summary":"Rotate","edits":[{"id":"a","placement":{"x":2,"y":0,"width":10,"height":10},"rotation":"# + String(angle) + #"}],"artwork":[]}"#
    let rotation = try model.predict(context, images: [image], currentPage: Data([1]))
    if angle == -90 { precondition(rotation.edits.map(\.rotation) == [270]) }
    else { precondition(rotation.edits.isEmpty) }
}
for x in [2.01, 2.03] {
    MockAPI.overrideSuggestion = #"{"summary":"Move","edits":[{"id":"a","placement":{"x":"# + String(x) + #","y":0,"width":10,"height":10},"rotation":0}],"artwork":[]}"#
    let move = try model.predict(context, images: [image], currentPage: Data([1]))
    precondition(move.edits.count == (x == 2.01 ? 0 : 1))
}
// Style-only changes must survive normalization; unknown/mixed styles are rejected.
for field in ["textBold", "textItalic"] {
    let raw = try JSONEncoder().encode(try state(2, multiline: true))
    var page = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
    var objects = page["objects"] as! [[String: Any]]
    objects[0][field] = false
    page["objects"] = objects
    let styled = try JSONDecoder().decode(SlideSnapshot.self, from: JSONSerialization.data(withJSONObject: page))
    var styleHistory = EditHistory()
    _ = styleHistory.observe(styled)
    let styleContext = styleHistory.currentContext!
    for flag in [true, false] {
        MockAPI.overrideSuggestion = #"{"summary":"Style","edits":[{"id":"a","placement":{"x":2,"y":0,"width":10,"height":10},"rotation":0,""# + field + #"":"# + String(flag) + #"}],"artwork":[]}"#
        let style = try model.predict(styleContext, images: [image], currentPage: Data([1]))
        precondition(style.edits.count == (flag ? 1 : 0))
        if flag {
            precondition(field == "textBold" ? style.edits[0].textBold == true : style.edits[0].textItalic == true)
            do { try style.validate(for: textContext.current); fatalError("Allowed an unknown/mixed style") }
            catch PredictionError.invalidSuggestion { }
        }
    }
}
MockAPI.overrideSuggestion = nil
do {
    try result.validate(for: context.current, images: [image, image])
    fatalError("Accepted ambiguous reference IDs")
} catch PredictionError.invalidSuggestion { }
let invalidCombination = #"{"summary":"Move and label","edits":[{"id":"a","placement":{"x":5,"y":5,"width":10,"height":10},"rotation":0},{"id":"a","duplicate":true,"placement":{"x":20,"y":5,"width":10,"height":10},"rotation":0,"text":"Label"}],"artwork":[]}"#
let combination = try JSONDecoder().decode(Prediction.self, from: Data(invalidCombination.utf8))
do { try combination.validate(for: context.current); fatalError("Accepted text on a non-text object") }
catch PredictionError.invalidSuggestion { }
MockAPI.malformed = true
do { _ = try model.predict(context, images: [image], currentPage: Data([1])); fatalError("Unexpected success") }
catch PredictionError.invalidResponse { }
MockAPI.malformed = false
for code in [401,429,500] {
    MockAPI.code = code
    do { _ = try model.predict(context, images: [image], currentPage: Data([1])); fatalError("Unexpected success") }
    catch { precondition(!error.localizedDescription.contains("test-only")) }
}
print("API request, image order, structured response and HTTP errors passed")
SWIFT
swiftc -I "$bin/Modules" "$tmp/main.swift" "$bin"/CursorCore.build/*.swift.o -o "$tmp/check"
"$tmp/check"
