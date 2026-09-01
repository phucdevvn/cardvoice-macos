import Foundation

enum APKGError: LocalizedError {
    case missingManifest
    case unsupportedManifest
    case invalidAudioMapping(String)
    case unsupportedFieldLayout(fieldCount: Int, audioFieldIndex: Int)
    case missingCollection
    case missingAudio(String)
    case invalidCollectionMetadata(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest: return "This deck does not contain cardvoice.json. Import a CardVoice-ready .apkg generated for this app."
        case .unsupportedManifest: return "Unsupported CardVoice manifest version."
        case let .invalidAudioMapping(message): return message
        case let .unsupportedFieldLayout(fieldCount, audioFieldIndex):
            return "Unsupported Anki field layout: \(fieldCount) fields with audio at index \(audioFieldIndex)."
        case .missingCollection: return "The Anki package does not contain collection.anki2."
        case let .missingAudio(name): return "Missing generated audio: \(name)"
        case let .invalidCollectionMetadata(message): return "Invalid Anki collection metadata: \(message)"
        case let .commandFailed(message): return message
        }
    }
}

enum APKGService {
    static func load(url: URL) throws -> LoadedPackage {
        let dir = try extract(url: url)
        defer { try? FileManager.default.removeItem(at: dir) }
        let manifestURL = dir.appending(path: "cardvoice.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw APKGError.missingManifest }
        let manifest = try JSONDecoder().decode(CardVoiceManifest.self, from: Data(contentsOf: manifestURL))
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
        let db = dir.appending(path: "collection.anki2")
        guard FileManager.default.fileExists(atPath: db.path) else { throw APKGError.missingCollection }
        try normalizeLegacyAnkiMetadata(in: db)

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
            let mediaKey: String
            if let existing = media.first(where: { $0.value == filename })?.key {
                mediaKey = existing
            } else {
                while media[String(nextMedia)] != nil { nextMedia += 1 }
                mediaKey = String(nextMedia)
                media[mediaKey] = filename
                nextMedia += 1
            }
            let embeddedAudio = dir.appending(path: mediaKey)
            if FileManager.default.fileExists(atPath: embeddedAudio.path) {
                try FileManager.default.removeItem(at: embeddedAudio)
            }
            try FileManager.default.copyItem(at: audio, to: embeddedAudio)

            let fields = try ankiFields(for: note, audioMarkup: "[sound:\(filename)]")
                .joined(separator: "\u{001F}")
            let escapedFields = sqlEscape(fields)
            let escapedGuid = sqlEscape(note.guid)
            sql.append("UPDATE notes SET flds='\(escapedFields)', mod=strftime('%s','now'), usn=-1 WHERE guid='\(escapedGuid)';")
        }
        sql.insert("BEGIN IMMEDIATE;", at: 0)
        sql.append("UPDATE col SET mod=(strftime('%s','now') * 1000);")
        sql.append("COMMIT;")
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

    static func normalizeLegacyAnkiMetadata(in database: URL) throws {
        var decks = try readJSONObject(column: "decks", from: database)
        for key in decks.keys {
            guard var deck = decks[key] as? [String: Any] else {
                throw APKGError.invalidCollectionMetadata("deck \(key) is not an object")
            }
            setDefault(&deck, key: "lrnToday", value: [0, 0])
            setDefault(&deck, key: "revToday", value: [0, 0])
            setDefault(&deck, key: "newToday", value: [0, 0])
            setDefault(&deck, key: "timeToday", value: [0, 0])
            setDefault(&deck, key: "collapsed", value: false)
            setDefault(&deck, key: "desc", value: "")
            setDefault(&deck, key: "dyn", value: 0)
            setDefault(&deck, key: "extendNew", value: 0)
            setDefault(&deck, key: "extendRev", value: 50)
            setDefault(&deck, key: "conf", value: 1)
            decks[key] = deck
        }

        var models = try readJSONObject(column: "models", from: database)
        for key in models.keys {
            guard var model = models[key] as? [String: Any] else {
                throw APKGError.invalidCollectionMetadata("note type \(key) is not an object")
            }
            setDefault(&model, key: "latexPre", value: "")
            setDefault(&model, key: "latexPost", value: "")
            setDefault(&model, key: "latexsvg", value: false)
            setDefault(&model, key: "req", value: [])
            setDefault(&model, key: "tags", value: [])
            setDefault(&model, key: "vers", value: [])

            if var templates = model["tmpls"] as? [[String: Any]] {
                for index in templates.indices {
                    setDefault(&templates[index], key: "did", value: NSNull())
                    setDefault(&templates[index], key: "bqfmt", value: "")
                    setDefault(&templates[index], key: "bafmt", value: "")
                    setDefault(&templates[index], key: "bfont", value: "")
                    setDefault(&templates[index], key: "bsize", value: 0)
                }
                model["tmpls"] = templates
            }
            models[key] = model
        }

        var configuration = try readJSONObject(column: "conf", from: database)
        setDefault(&configuration, key: "collapseTime", value: 1200)
        setDefault(&configuration, key: "newBury", value: true)

        var deckConfigurations = try readJSONObject(column: "dconf", from: database)
        for key in deckConfigurations.keys {
            guard var deckConfiguration = deckConfigurations[key] as? [String: Any] else {
                throw APKGError.invalidCollectionMetadata("deck configuration \(key) is not an object")
            }
            if var newCards = deckConfiguration["new"] as? [String: Any] {
                setDefault(&newCards, key: "separate", value: true)
                deckConfiguration["new"] = newCards
            }
            if var reviews = deckConfiguration["rev"] as? [String: Any] {
                setDefault(&reviews, key: "minSpace", value: 1)
                deckConfiguration["rev"] = reviews
            }
            deckConfigurations[key] = deckConfiguration
        }

        let values = try [decks, models, configuration, deckConfigurations].map(jsonString)
        let sql = """
        UPDATE col SET
          decks='\(sqlEscape(values[0]))',
          models='\(sqlEscape(values[1]))',
          conf='\(sqlEscape(values[2]))',
          dconf='\(sqlEscape(values[3]))';
        """
        try run("/usr/bin/sqlite3", [database.path, sql])
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

    private static func readJSONObject(column: String, from database: URL) throws -> [String: Any] {
        let text = try run("/usr/bin/sqlite3", [database.path, "SELECT \(column) FROM col;"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            throw APKGError.invalidCollectionMetadata("\(column) is not a JSON object")
        }
        return dictionary
    }

    private static func jsonString(_ object: [String: Any]) throws -> String {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw APKGError.invalidCollectionMetadata("could not encode normalized JSON")
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw APKGError.invalidCollectionMetadata("normalized JSON is not UTF-8")
        }
        return text
    }

    private static func setDefault(_ dictionary: inout [String: Any], key: String, value: Any) {
        if dictionary[key] == nil { dictionary[key] = value }
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
