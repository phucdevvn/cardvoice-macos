import Foundation

enum ElevenLabsError: LocalizedError {
    case invalidResponse
    case api(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "ElevenLabs returned an invalid response."
        case let .api(status, message):
            return "ElevenLabs error \(status): \(message)"
        }
    }
}

struct ElevenLabsClient {
    private let baseURL = URL(string: "https://api.elevenlabs.io")!

    func generateSpeech(
        text: String,
        apiKey: String,
        voiceID: String,
        modelID: String = "eleven_multilingual_v2",
        outputFormat: String = "mp3_44100_128"
    ) async throws -> Data {
        let encodedVoice = voiceID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? voiceID
        let url = baseURL.appending(path: "/v1/text-to-speech/\(encodedVoice)")
            .appending(queryItems: [URLQueryItem(name: "output_format", value: outputFormat)])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text,
            "model_id": modelID,
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75,
                "style": 0.0,
                "use_speaker_boost": true,
                "speed": 1.0
            ]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    func voices(apiKey: String, search: String = "") async throws -> [ElevenVoice] {
        var items = [URLQueryItem(name: "page_size", value: "100")]
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "search", value: search))
        }
        let url = baseURL.appending(path: "/v2/voices").appending(queryItems: items)
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(VoiceSearchResponse.self, from: data).voices
    }

    func subscription(apiKey: String) async throws -> ElevenSubscription {
        let url = baseURL.appending(path: "/v1/user/subscription")
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ElevenSubscription.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ElevenLabsError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message: String
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let detail = object["detail"] as? [String: Any] {
                    message = (detail["message"] as? String) ?? String(describing: detail)
                } else if let detail = object["detail"] as? String {
                    message = detail
                } else {
                    message = String(data: data, encoding: .utf8) ?? "Unknown API error"
                }
            } else {
                message = String(data: data, encoding: .utf8) ?? "Unknown API error"
            }
            throw ElevenLabsError.api(status: http.statusCode, message: message)
        }
    }
}

private extension URL {
    func appending(queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        return components.url!
    }
}
