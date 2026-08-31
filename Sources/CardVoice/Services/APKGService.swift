import Foundation

enum APKGError: LocalizedError {
    case missingManifest
    case unsupportedManifest
    case invalidAudioMapping(String)
    case unsupportedFieldLayout(fieldCount: Int, audioFieldIndex: Int)
    case unsupportedPackage(String)
    case missingCollection
    case missingAudio(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest: return "This deck does not contain cardvoice.json. Import a CardVoice-ready .apkg generated for this app."
        case .unsupportedManifest: return "Unsupported CardVoice manifest version."
        case let .invalidAudioMapping(message): return message
        case let .unsupportedFieldLayout(fieldCount, audioFieldIndex):
            return "Unsupported Anki field layout: \(fieldCount) fields with audio at index \(audioFieldIndex)."
        case let .unsupportedPackage(message): return message
        case .missingCollection: return "The Anki package does not contain a supported collection database."
        case let .missingAudio(name): return "Missing generated audio: \(name)"
        case let .commandFailed(message): return message
        }
    }
}

enum APKGService {
    static func load(url: URL) throws -> LoadedPackage {
        let dir = try extract(url: url)
        defer { try? FileManager.default.removeItem(at: dir) }
        let manifestURL = dir.appending(path: "cardvoice.json")

        let manifest: CardVoiceManifest
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            manifest = try JSONDecoder().decode(CardVoiceManifest.self, from: Data(contentsOf: manifestURL))
        } else {
            manifest = try synthesizedManifest(from: dir)
        }

        guard manifest.format == "cardvoice-apkg-manifest-v1" else { throw APKGError.unsupportedManifest }
        let filenames = manifest.notes.map(\.resolvedAudioFilename)
        guard Set(filenames.map { $0.lowercased() }).count == filenames.count else {
            throw APKGError.invalidAudioMapping("The CardVoice manifest resolves multiple notes to the same audio filename.")
        }
        return LoadedPackage(sourceURL: url, manifest: manifest)
    }

    static func exportAudioZip(
        package: LoadedPackage,
        destination: URL,
        audioFilename: (CardVoiceNote) -> String = { $0.resolvedAudioFilename },
        audioURL: (String) -> URL? = AudioStore.existingURL
    ) throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: "CardVoice-Audio-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        var exported: [[String: String]] = []
        for note in package.manifest.notes {
            let filename = audioFilename(note)
            guard let source = audioURL(filename) else { throw APKGError.missingAudio(filename) }
            try FileManager.default.copyItem(at: source, to: temp.appending(path: filename))
            exported.append(["cardVoiceID": note.id, "guid": note.guid, "filename": filename, "sentence": note.sentence])
        }
        let manifestData = try JSONSerialization.data(withJSONObject: ["format": "cardvoice-audio-zip-v1", "items": exported], options: [.prettyPrinted, .sortedKeys])
        try manifestData.write(to: temp.appending(path: "cardvoice-audio-manifest.json"))
        try zipDirectory(temp, to: destination)
    }

    static func exportAnkiWithAudio(
        package: LoadedPackage,
        destination: URL,
        audioFilename: (CardVoiceNote) -> String = { $0.resolvedAudioFilename },
        audioURL: (String) -> URL? = AudioStore.existingURL
    ) throws {
        let dir = try extract(url: package.sourceURL)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try collectionURL(in: dir)

        let mediaURL = dir.appending(path: "media")
        var media: [String: String] = [:]
        if FileManager.default.fileExists(atPath: mediaURL.path),
           let decoded = try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: mediaURL)) {
            media = decoded
        }
        var nextMedia = (media.keys.compactMap(Int.init).max() ?? -1) + 1

        var sql: [String] = []
        for note in package.manifest.notes {
            let filename = audioFilename(note)
            guard let audio = audioURL(filename) else { throw APKGError.missingAudio(filename) }
            while media[String(nextMedia)] != nil { nextMedia += 1 }
            try FileManager.default.copyItem(at: audio, to: dir.appending(path: String(nextMedia)))
            media[String(nextMedia)] = filename
            nextMedia += 1

            var noteFields = try existingFields(in: db, guid: note.guid)
            guard noteFields.count == note.fieldCount, note.audioFieldIndex < noteFields.count else {
                throw APKGError.unsupportedFieldLayout(
                    fieldCount: noteFields.count,
                    audioFieldIndex: note.audioFieldIndex
                )
            }
            noteFields[note.audioFieldIndex] = "[sound:\(filename)]"
            let fields = noteFields.joined(separator: "\u{001F}")
            let escapedFields = sqlEscape(fields)
            let escapedGuid = sqlEscape(note.guid)
            sql.append("UPDATE notes SET flds='\(escapedFields)', mod=strftime('%s','now'), usn=-1 WHERE guid='\(escapedGuid)';")
        }
        sql.append("UPDATE col SET mod=(strftime('%s','now') * 1000);")
        try run("/usr/bin/sqlite3", [db.path, sql.joined(separator: "\n")])
        let mediaData = try JSONEncoder().encode(media)
        try mediaData.write(to: mediaURL, options: .atomic)
        try zipDirectory(dir, to: destination)
    }

    static func ankiFields(for note: CardVoiceNote, audioMarkup: String) throws -> [String] {
        switch (note.fieldCount, note.audioFieldIndex) {
        case (3, 2):
            return [note.clozeText, note.combinedNotesHTML, audioMarkup]
        case (5, 3):
            return [note.clozeText, note.pattern, note.meaning, audioMarkup, note.id]
        default:
            throw APKGError.unsupportedFieldLayout(
                fieldCount: note.fieldCount,
                audioFieldIndex: note.audioFieldIndex
            )
        }
    }

    private static func synthesizedManifest(from directory: URL) throws -> CardVoiceManifest {
        let db = try collectionURL(in: directory)

        let modelsText = try run("/usr/bin/sqlite3", [db.path, "SELECT models FROM col;"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let decksText = try run("/usr/bin/sqlite3", [db.path, "SELECT decks FROM col;"])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let models = try JSONSerialization.jsonObject(with: Data(modelsText.utf8)) as? [String: Any],
              !models.isEmpty else {
            throw APKGError.unsupportedPackage("CardVoice could not read the Anki note type metadata in this deck.")
        }
        let decks = (try? JSONSerialization.jsonObject(with: Data(decksText.utf8)) as? [String: Any]) ?? [:]

        let rowsText = try run(
            "/usr/bin/sqlite3",
            [db.path, "SELECT hex(guid), mid, hex(flds) FROM notes ORDER BY id;"]
        )
        let rows = rowsText.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !rows.isEmpty else {
            throw APKGError.unsupportedPackage("This Anki package does not contain any notes.")
        }

        let dominantDeckText = try run(
            "/usr/bin/sqlite3",
            [db.path, "SELECT did FROM cards GROUP BY did ORDER BY count(*) DESC LIMIT 1;"]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let deckName = (decks[dominantDeckText] as? [String: Any])?["name"] as? String ?? "Imported Anki Deck"

        var notes: [CardVoiceNote] = []
        var firstNoteType: String?

        for (offset, row) in rows.enumerated() {
            let parts = row.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3,
                  let guid = decodeHexUTF8(parts[0]),
                  let fieldsText = decodeHexUTF8(parts[2]) else {
                throw APKGError.unsupportedPackage("CardVoice could not decode one of the notes in this Anki package.")
            }

            let modelKey = parts[1]
            guard let model = models[modelKey] as? [String: Any],
                  let rawFieldDefs = model["flds"] as? [[String: Any]] else {
                throw APKGError.unsupportedPackage("CardVoice could not match a note to its Anki note type.")
            }
            let fieldDefs = rawFieldDefs.sorted {
                (($0["ord"] as? Int) ?? 0) < (($1["ord"] as? Int) ?? 0)
            }
            let fieldNames = fieldDefs.map { ($0["name"] as? String) ?? "" }
            let fields = fieldsText.components(separatedBy: "\u{001F}")
            guard fields.count == fieldNames.count else {
                throw APKGError.unsupportedPackage("A note's field count does not match its Anki note type metadata.")
            }

            let fieldCount = fields.count
            let audioFieldIndex: Int
            if let namedAudio = fieldNames.firstIndex(where: { $0.caseInsensitiveCompare("Audio") == .orderedSame }) {
                audioFieldIndex = namedAudio
            } else if fieldCount == 3 {
                audioFieldIndex = 2
            } else if fieldCount == 5 {
                audioFieldIndex = 3
            } else {
                throw APKGError.unsupportedPackage(
                    "This deck has \(fieldCount) fields and no field named Audio. CardVoice can automatically recover 3-field or 5-field CardVoice decks."
                )
            }
            guard (fieldCount == 3 && audioFieldIndex == 2) || (fieldCount == 5 && audioFieldIndex == 3) else {
                throw APKGError.unsupportedFieldLayout(fieldCount: fieldCount, audioFieldIndex: audioFieldIndex)
            }

            let sentenceIndex = fieldNames.firstIndex(where: { $0.caseInsensitiveCompare("Sentence") == .orderedSame }) ?? 0
            let clozeText = fields[sentenceIndex]
            let cloze = clozeData(from: clozeText)
            let sentence = spokenSentence(from: clozeText)

            let pattern: String
            let meaning: String
            if let patternIndex = fieldNames.firstIndex(where: { $0.caseInsensitiveCompare("Pattern") == .orderedSame }),
               let meaningIndex = fieldNames.firstIndex(where: { $0.caseInsensitiveCompare("Meaning") == .orderedSame }) {
                pattern = fields[patternIndex]
                meaning = fields[meaningIndex]
            } else if let notesIndex = fieldNames.firstIndex(where: { $0.caseInsensitiveCompare("Notes") == .orderedSame }) {
                let parsed = parseCombinedNotes(fields[notesIndex])
                pattern = parsed.pattern
                meaning = parsed.meaning
            } else {
                pattern = cloze.targets.joined(separator: " · ")
                meaning = ""
            }

            let cardVoiceID: String
            if let idIndex = fieldNames.firstIndex(where: {
                $0.caseInsensitiveCompare("CardVoice ID") == .orderedSame || $0.caseInsensitiveCompare("ID") == .orderedSame
            }), !fields[idIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cardVoiceID = fields[idIndex]
            } else {
                cardVoiceID = String(format: "cv%03d", offset + 1)
            }

            if firstNoteType == nil {
                firstNoteType = model["name"] as? String
            }

            notes.append(
                CardVoiceNote(
                    id: cardVoiceID,
                    guid: guid,
                    sentence: sentence,
                    clozeText: clozeText,
                    targets: cloze.targets,
                    pattern: pattern,
                    meaning: meaning,
                    audioFilename: "",
                    audioFieldIndex: audioFieldIndex,
                    fieldCount: fieldCount,
                    clozeNumbers: cloze.numbers.isEmpty ? [1] : cloze.numbers
                )
            )
        }

        return CardVoiceManifest(
            format: "cardvoice-apkg-manifest-v1",
            deckName: deckName,
            noteType: firstNoteType ?? "Imported Anki Note Type",
            createdAt: Int(Date().timeIntervalSince1970),
            audioPolicy: "full-sentence-back-only",
            notes: notes
        )
    }

    private static func existingFields(in db: URL, guid: String) throws -> [String] {
        let escapedGuid = sqlEscape(guid)
        let hex = try run(
            "/usr/bin/sqlite3",
            [db.path, "SELECT hex(flds) FROM notes WHERE guid='\(escapedGuid)' LIMIT 1;"]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hex.isEmpty, let fieldsText = decodeHexUTF8(hex) else {
            throw APKGError.unsupportedPackage("CardVoice could not find the source Anki note for GUID \(guid).")
        }
        return fieldsText.components(separatedBy: "\u{001F}")
    }

    private static func collectionURL(in directory: URL) throws -> URL {
        for name in ["collection.anki2", "collection.anki21"] {
            let url = directory.appending(path: name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        if FileManager.default.fileExists(atPath: directory.appending(path: "collection.anki21b").path) {
            throw APKGError.unsupportedPackage(
                "This Anki export uses the compressed collection.anki21b format. Re-export the deck with legacy/older-Anki compatibility, then import it into CardVoice."
            )
        }
        throw APKGError.missingCollection
    }

    private static func decodeHexUTF8(_ hex: String) -> String? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return String(data: data, encoding: .utf8)
    }

    private static func clozeData(from text: String) -> (targets: [String], numbers: [Int]) {
        guard let regex = try? NSRegularExpression(
            pattern: #"\{\{c(\d+)::(.*?)(?:::(.*?))?\}\}"#,
            options: [.dotMatchesLineSeparators]
        ) else { return ([], []) }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        var targets: [String] = []
        var numbers: [Int] = []
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match else { return }
            if match.numberOfRanges > 2 {
                let target = nsText.substring(with: match.range(at: 2))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !target.isEmpty { targets.append(stripHTML(target)) }
            }
            if match.numberOfRanges > 1,
               let number = Int(nsText.substring(with: match.range(at: 1))),
               !numbers.contains(number) {
                numbers.append(number)
            }
        }
        return (targets, numbers.sorted())
    }

    private static func spokenSentence(from clozeText: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"\{\{c\d+::(.*?)(?:::(.*?))?\}\}"#,
            options: [.dotMatchesLineSeparators]
        ) else { return stripHTML(clozeText) }
        let range = NSRange(location: 0, length: (clozeText as NSString).length)
        let replaced = regex.stringByReplacingMatches(in: clozeText, range: range, withTemplate: "$1")
        return stripHTML(replaced)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseCombinedNotes(_ html: String) -> (pattern: String, meaning: String) {
        let withBreaks = html
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        let plain = stripHTML(withBreaks)
        let lines = plain.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var patterns: [String] = []
        var meanings: [String] = []
        for line in lines {
            if let range = line.range(of: " — ") {
                patterns.append(String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces))
                meanings.append(String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces))
            }
        }
        if !patterns.isEmpty, patterns.count == meanings.count {
            return (patterns.joined(separator: " · "), meanings.joined(separator: "; "))
        }
        return (plain.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    private static func stripHTML(_ value: String) -> String {
        var text = value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
        if let regex = try? NSRegularExpression(pattern: #"<[^>]+>"#) {
            let range = NSRange(location: 0, length: (text as NSString).length)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }
        return text
    }

    private static func extract(url: URL) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "CardVoice-APKG-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            try run("/usr/bin/unzip", ["-qq", url.path, "-d", dir.path])
            return dir
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw error
        }
    }

    private static func zipDirectory(_ directory: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try run("/usr/bin/zip", ["-q", "-r", destination.path, "."], currentDirectory: directory)
    }

    private static func sqlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String], currentDirectory: URL? = nil) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        p.currentDirectoryURL = currentDirectory
        let output = Pipe(); let errors = Pipe()
        p.standardOutput = output; p.standardError = errors
        try p.run(); p.waitUntilExit()
        let out = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else {
            throw APKGError.commandFailed(err.isEmpty ? "Command failed: \(executable)" : err)
        }
        return out
    }
}
