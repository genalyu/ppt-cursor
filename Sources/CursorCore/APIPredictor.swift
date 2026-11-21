import Foundation

public struct APISettings: Sendable {
    public let model: String
    let key: String
    public func selecting(model: String) -> APISettings {
        APISettings(model: model, key: key)
    }

    public init(model: String, key: String) {
        self.model = model
        self.key = key
    }
}

private struct APIError: LocalizedError {
    let errorDescription: String?
    init(_ description: String) { errorDescription = description }
}

private struct ResponseEnvelope: Decodable {
    struct Output: Decodable {
        struct Content: Decodable { let type: String; let text: String? }
        let content: [Content]?
    }
    let status: String
    let output: [Output]
}

private final class ResponseResult: @unchecked Sendable {
    // The completion is the sole writer. The caller reads only after the semaphore signals.
    var value: Result<Data, Error>?
    let ready = DispatchSemaphore(value: 0)
}

public struct APIPredictor {
    private let settings: APISettings
    private let session: URLSession
    public init(settings: APISettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    public func predict(_ context: EditContext, images: [ReferenceImage] = [], currentPage: Data? = nil,
                        run: PredictionRun = PredictionRun()) throws -> Prediction {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer " + settings.key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let text = try PredictionInput.context(context, images: images, hasPage: currentPage != nil)
        var content = [["type": "input_text", "text": text]]
        for bytes in [currentPage].compactMap({ $0 }) + images.map(\.thumbnail) {
            content.append(["type": "input_image", "image_url": "data:image/png;base64," + bytes.base64EncodedString()])
        }
        let schema = try JSONSerialization.jsonObject(with: Data(contentsOf: PredictionInput.schema))
        let format: [String: Any] = ["type": "json_schema", "name": "slide_prediction", "strict": true, "schema": schema]
        let body: [String: Any] = ["model": settings.model, "instructions": try PredictionInput.instructions(),
                                   "input": [["role": "user", "content": content]], "text": ["format": format], "store": false]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let response = ResponseResult()
        let task = session.dataTask(with: request) { data, reply, error in
            defer { response.ready.signal() }
            response.value = Result {
                if let error { throw error }
                guard let http = reply as? HTTPURLResponse, let data else { throw APIError("模型服务没有返回响应") }
                switch http.statusCode {
                case 200..<300: return data
                case 401, 403: throw APIError("请检查 API 密钥和模型访问权限")
                case 429: throw APIError("模型服务达到速率或额度限制")
                default: throw APIError("模型服务返回 HTTP \(http.statusCode)，请检查模型名称或稍后再试")
                }
            }
        }
        try run.resume(task)
        response.ready.wait()
        guard let result = response.value else { throw PredictionError.missingResult }
        let responseData = try result.get()
        guard let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: responseData) else {
            throw PredictionError.invalidResponse
        }
        guard envelope.status == "completed",
              let text = envelope.output.flatMap({ $0.content ?? [] }).first(where: { $0.type == "output_text" })?.text else {
            throw PredictionError.missingResult
        }
        return try Prediction.read(Data(text.utf8), for: context.current, images: images)
    }
}
