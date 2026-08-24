import Foundation

struct ElevenLabsEnvironmentImport {
    let apiKeys: [(name: String, value: String)]
    let voiceID: String?
    let modelID: String?
    let outputFormat: String?

    static func parse(_ text: String) -> ElevenLabsEnvironmentImport {
        var values: [String: String] = [:]

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            let payload: Substring
            if line.hasPrefix("export ") {
                payload = line.dropFirst("export ".count)
            } else {
                payload = Substring(line)
            }

            guard let equals = payload.firstIndex(of: "=") else { continue }
            let rawKey = payload[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
            var rawValue = payload[payload.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawKey.isEmpty else { continue }

            if rawValue.count >= 2,
               ((rawValue.hasPrefix("\"") && rawValue.hasSuffix("\"")) ||
                (rawValue.hasPrefix("'") && rawValue.hasSuffix("'"))) {
                rawValue.removeFirst()
                rawValue.removeLast()
            }

            values[rawKey] = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let apiKeys = values
            .filter { $0.key.hasPrefix("ELEVENLABS_API_KEY") && !$0.value.isEmpty }
            .sorted { lhs, rhs in
                naturalKeyIndex(lhs.key) < naturalKeyIndex(rhs.key)
            }
            .map { (name: $0.key, value: $0.value) }

        return ElevenLabsEnvironmentImport(
            apiKeys: apiKeys,
            voiceID: nonEmpty(values["ELEVENLABS_VOICE_ID"]),
            modelID: nonEmpty(values["ELEVENLABS_MODEL_ID"]),
            outputFormat: nonEmpty(values["ELEVENLABS_OUTPUT_FORMAT"])
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func naturalKeyIndex(_ key: String) -> Int {
        let suffix = key.split(separator: "_").last.flatMap { Int($0) }
        return suffix ?? Int.max
    }
}
