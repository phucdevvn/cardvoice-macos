import Foundation

struct CardVoiceManifest: Codable, Hashable {
    let format: String
    let deckName: String
    let noteType: String
    let createdAt: Int
    let audioPolicy: String
    let notes: [CardVoiceNote]
}

struct CardVoiceNote: Codable, Identifiable, Hashable {
    let id: String
    let guid: String
    let sentence: String
    let clozeText: String
    let targets: [String]
    let pattern: String
    let meaning: String
    let audioFilename: String
    let audioFieldIndex: Int
    let fieldCount: Int
    let clozeNumbers: [Int]
}

struct LoadedPackage: Hashable {
    let sourceURL: URL
    let manifest: CardVoiceManifest
}

struct APIKeyProfile: Identifiable, Codable, Hashable {
    var id: UUID
    var label: String
    var keychainAccount: String

    init(id: UUID = UUID(), label: String, keychainAccount: String? = nil) {
        self.id = id
        self.label = label
        self.keychainAccount = keychainAccount ?? "elevenlabs-\(id.uuidString)"
    }
}

struct ElevenVoice: Codable, Identifiable, Hashable {
    let voice_id: String
    let name: String?
    let category: String?
    let labels: [String: String]?
    let preview_url: String?

    var id: String { voice_id }
    var displayName: String { name ?? voice_id }
    var subtitle: String {
        [labels?["accent"], labels?["gender"], labels?["description"]]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

struct VoiceSearchResponse: Codable {
    let voices: [ElevenVoice]
    let has_more: Bool?
    let total_count: Int?
    let next_page_token: String?
}

struct ElevenSubscription: Codable {
    let tier: String?
    let character_count: Int?
    let character_limit: Int?
    let next_character_count_reset_unix: Int?

    var usageDescription: String {
        guard let used = character_count, let limit = character_limit else {
            return tier ?? "Unknown plan"
        }
        return "\(tier ?? "plan"): \(used) / \(limit) characters"
    }
}
