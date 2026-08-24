import Foundation

enum APKGError: LocalizedError {
    case missingManifest
    case unsupportedManifest
    case missingCollection
    case missingAudio(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest: return "This deck does not contain cardvoice.json. Import a CardVoice-ready .apkg generated for this app."
        case .unsupportedManifest: return "Unsupported CardVoice manifest version."
        case .missingCollection: return "The Anki package does not contain collection.anki2."
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
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw APKGError.missingManifest }
        let manifest = try JSONDecoder().decode(CardVoiceManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.format == "cardvoice-apkg-manifest-v1" else { throw APKGError.unsupportedManifest }
        return LoadedPackage(sourceURL: url, manifest: manifest)
    }

    static func exportAudioZip(package: LoadedPackage, destination: URL) throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: "CardVoice-Audio-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        var exported: [[String: String]] = []
        for note in package.manifest.notes {
            guard let source = AudioStore.existingURL(filename: note.audioFilename) else { throw APKGError.missingAudio(note.audioFilename) }
            try FileManager.default.copyItem(at: source, to: temp.appending(path: note.audioFilename))
            exported.append(["cardVoiceID": note.id, "guid": note.guid, "filename": note.audioFilename, "sentence": note.sentence])
        }
        let manifestData = try JSONSerialization.data(withJSONObject: ["format": "cardvoice-audio-zip-v1", "items": exported], options: [.prettyPrinted, .sortedKeys])
        try manifestData.write(to: temp.appending(path: "cardvoice-audio-manifest.json"))
        try zipDirectory(temp, to: destination)
    }

    static func exportAnkiWithAudio(package: LoadedPackage, destination: URL) throws {
        let dir = try extract(url: package.sourceURL)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appending(path: "collection.anki2")
        guard FileManager.default.fileExists(atPath: db.path) else { throw APKGError.missingCollection }

        let mediaURL = dir.appending(path: "media")
        var media: [String: String] = [:]
        if FileManager.default.fileExists(atPath: mediaURL.path),
           let decoded = try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: mediaURL)) {
            media = decoded
        }
        var nextMedia = (media.keys.compactMap(Int.init).max() ?? -1) + 1

        var sql: [String] = []
        for note in package.manifest.notes {
            guard let audio = AudioStore.existingURL(filename: note.audioFilename) else { throw APKGError.missingAudio(note.audioFilename) }
            while media[String(nextMedia)] != nil { nextMedia += 1 }
            try FileManager.default.copyItem(at: audio, to: dir.appending(path: String(nextMedia)))
            media[String(nextMedia)] = note.audioFilename
            nextMedia += 1

            let fields = [note.clozeText, note.pattern, note.meaning, "[sound:\(note.audioFilename)]", note.id]
                .joined(separator: "\u{001F}")
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
