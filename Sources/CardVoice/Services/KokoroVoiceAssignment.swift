import Foundation

enum KokoroVoiceAssignment {
    static func key(for note: CardVoiceNote) -> String {
        "\(note.guid)\u{001F}\(note.id)"
    }

    static func make(
        notes: [CardVoiceNote],
        existingVoiceID: (CardVoiceNote) -> Int?
    ) -> [String: Int] {
        let voiceIDs = KokoroVoice.all.map(\.id)
        var counts = Dictionary(uniqueKeysWithValues: voiceIDs.map { ($0, 0) })
        var result: [String: Int] = [:]
        var missing: [CardVoiceNote] = []

        for note in notes {
            if let voiceID = existingVoiceID(note), counts[voiceID] != nil {
                result[key(for: note)] = voiceID
                counts[voiceID, default: 0] += 1
            } else {
                missing.append(note)
            }
        }

        // Hash-sort the unassigned cards so their visible deck order does not
        // produce a repetitive four-voice pattern. Choosing from the least-used
        // voices after each assignment keeps new decks balanced within one card.
        missing.sort {
            let left = stableHash(key(for: $0))
            let right = stableHash(key(for: $1))
            return left == right ? key(for: $0) < key(for: $1) : left < right
        }

        for note in missing {
            let minimum = voiceIDs.map { counts[$0, default: 0] }.min() ?? 0
            let candidates = voiceIDs.filter { counts[$0, default: 0] == minimum }
            let hash = stableHash("voice\u{001F}\(key(for: note))")
            let voiceID = candidates[Int(hash % UInt64(candidates.count))]
            result[key(for: note)] = voiceID
            counts[voiceID, default: 0] += 1
        }

        return result
    }

    private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}
