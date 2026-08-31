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

    var resolvedAudioFilename: String {
        let supplied = audioFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: String
        if AudioStore.isSafeFilename(supplied) {
            base = URL(fileURLWithPath: supplied).deletingPathExtension().lastPathComponent
        } else {
            let safeID = id.unicodeScalars
                .map { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" ? Character(String($0)) : "_" }
            let identifier = String(safeID).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            base = "cardvoice_\(identifier.isEmpty ? "note" : identifier)"
        }

        // A distinct offline filename prevents old cloud-generated cache entries
        // from being mistaken for current Kokoro audio after upgrading CardVoice.
        return "\(base.hasSuffix("_kokoro") ? base : base + "_kokoro").wav"
    }

    var combinedNotesLines: [String] {
        let patterns = pattern.components(separatedBy: " · ").map(trimmed).filter { !$0.isEmpty }
        let meanings = meaning.components(separatedBy: "; ").map(trimmed).filter { !$0.isEmpty }

        guard patterns.count == meanings.count, !patterns.isEmpty else {
            let fallback = [pattern, meaning].map(trimmed).filter { !$0.isEmpty }.joined(separator: " — ")
            return fallback.isEmpty ? [] : [fallback]
        }

        return zip(patterns, meanings).map { "\($0) — \($1)" }
    }

    var combinedNotes: String {
        combinedNotesLines.joined(separator: "\n")
    }

    var combinedNotesHTML: String {
        combinedNotesLines.map(htmlEscaped).joined(separator: "<br>")
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

struct LoadedPackage: Hashable {
    let sourceURL: URL
    let manifest: CardVoiceManifest
}
