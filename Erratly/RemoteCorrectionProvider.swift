import Foundation

enum RemoteAPIError: Error, LocalizedError {
    case missingSettings
    case invalidURL
    case httpError(Int)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .missingSettings: return "Remote API settings are incomplete"
        case .invalidURL: return "Remote API base URL is invalid"
        case .httpError(let code): return "Remote API returned HTTP \(code)"
        case .malformedResponse: return "Remote API returned an unexpected response"
        }
    }
}

nonisolated enum RemoteAPIFormat {
    static func buildRequestBody(model: String, systemPrompt: String, userText: String) -> [String: Any] {
        [
            "model": model,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userText]
            ]
        ]
    }

    static func parseContent(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw RemoteAPIError.malformedResponse
        }
        return content
    }
}

actor RemoteCorrectionProvider: CorrectionProvider {
    func prepare() async throws {
        let settings = AppSettings.shared
        guard !settings.remoteBaseURL.isEmpty,
              !settings.remoteModelName.isEmpty,
              let key = settings.remoteAPIKey, !key.isEmpty else {
            throw RemoteAPIError.missingSettings
        }
    }

    func correctText(_ text: String, language: String?, examples: [CorrectionPair]) async throws -> String {
        let settings = AppSettings.shared
        guard let apiKey = settings.remoteAPIKey, !apiKey.isEmpty else {
            throw RemoteAPIError.missingSettings
        }
        guard let url = URL(string: "\(settings.remoteBaseURL)/chat/completions"),
              url.scheme != nil, url.host != nil else {
            throw RemoteAPIError.invalidURL
        }

        let systemPrompt = buildCorrectionSystemPrompt(language: language, examples: examples)
        let body = RemoteAPIFormat.buildRequestBody(model: settings.remoteModelName, systemPrompt: systemPrompt, userText: text)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw RemoteAPIError.httpError(code)
        }

        let content = try RemoteAPIFormat.parseContent(from: data)
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
