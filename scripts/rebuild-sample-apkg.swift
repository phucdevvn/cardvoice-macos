#!/usr/bin/env swift

import Foundation

struct Manifest: Decodable {
    struct Note: Decodable {
        let guid: String
        let clozeText: String
        let audioFieldIndex: Int
        let fieldCount: Int
        let clozeNumbers: [Int]
    }

    let deckName: String
    let noteType: String
    let notes: [Note]
}

enum RebuildError: LocalizedError {
    case usage
    case invalidPackage(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: swift scripts/rebuild-sample-apkg.swift INPUT.apkg MANIFEST.json SOURCE.tsv OUTPUT.apkg"
        case let .invalidPackage(message), let .commandFailed(message):
            return message
        }
    }
}

@discardableResult
func run(_ executable: String, _ arguments: [String], currentDirectory: URL? = nil) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory
    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    process.waitUntilExit()

    let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
        throw RebuildError.commandFailed(stderr.isEmpty ? "Command failed: \(executable)" : stderr)
    }
    return stdout
}

func sqlEscaped(_ value: String) -> String {
    value.replacingOccurrences(of: "'", with: "''")
}

func jsonString(_ object: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    guard let value = String(data: data, encoding: .utf8) else {
        throw RebuildError.invalidPackage("Could not encode Anki metadata as UTF-8 JSON.")
    }
    return value
}

func rebuild() throws {
    guard CommandLine.arguments.count == 5 else { throw RebuildError.usage }

    let input = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    let manifestURL = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
    let sourceURL = URL(fileURLWithPath: CommandLine.arguments[3]).standardizedFileURL
    let output = URL(fileURLWithPath: CommandLine.arguments[4]).standardizedFileURL
    let fileManager = FileManager.default

    let manifestData = try Data(contentsOf: manifestURL)
    let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
    guard manifest.notes.allSatisfy({ $0.fieldCount == 3 && $0.audioFieldIndex == 2 && $0.clozeNumbers == [1] }) else {
        throw RebuildError.invalidPackage("The simplified manifest must use three fields, audio index 2, and c1-only notes.")
    }

    let sourceText = try String(contentsOf: sourceURL, encoding: .utf8)
    let sourceRows = sourceText.components(separatedBy: .newlines)
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    guard sourceRows.count == manifest.notes.count, sourceRows.allSatisfy({ $0.count == 3 }) else {
        throw RebuildError.invalidPackage("The TSV must contain one three-field row for every manifest note.")
    }

    let workDirectory = fileManager.temporaryDirectory
        .appending(path: "CardVoice-Sample-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: workDirectory) }

    try run("/usr/bin/unzip", ["-qq", input.path, "-d", workDirectory.path])
    let databaseURL = workDirectory.appending(path: "collection.anki2")
    let mediaURL = workDirectory.appending(path: "media")
    guard fileManager.fileExists(atPath: databaseURL.path), fileManager.fileExists(atPath: mediaURL.path) else {
        throw RebuildError.invalidPackage("The input package must contain collection.anki2 and media.")
    }

    let modelsText = try run("/usr/bin/sqlite3", [databaseURL.path, "SELECT models FROM col;"])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let decksText = try run("/usr/bin/sqlite3", [databaseURL.path, "SELECT decks FROM col;"])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard var models = try JSONSerialization.jsonObject(with: Data(modelsText.utf8)) as? [String: Any],
          let modelKey = models.keys.first,
          var model = models[modelKey] as? [String: Any],
          let existingFields = model["flds"] as? [[String: Any]], existingFields.count >= 3,
          var templates = model["tmpls"] as? [[String: Any]], !templates.isEmpty,
          var decks = try JSONSerialization.jsonObject(with: Data(decksText.utf8)) as? [String: Any],
          let deckKey = decks.keys.first,
          var deck = decks[deckKey] as? [String: Any] else {
        throw RebuildError.invalidPackage("Could not decode the existing Anki note type or deck metadata.")
    }

    var sentenceField = existingFields[0]
    sentenceField["name"] = "Sentence"
    sentenceField["ord"] = 0
    var notesField = existingFields[1]
    notesField["name"] = "Notes"
    notesField["ord"] = 1
    var audioField = existingFields.first(where: { ($0["name"] as? String) == "Audio" })
        ?? existingFields[min(2, existingFields.count - 1)]
    audioField["name"] = "Audio"
    audioField["ord"] = 2

    model["name"] = manifest.noteType
    model["sortf"] = 0
    model["mod"] = manifest.notes.isEmpty ? 0 : Int(Date().timeIntervalSince1970)
    model["flds"] = [sentenceField, notesField, audioField]
    templates[0]["qfmt"] = "{{cloze:Sentence}}"
    templates[0]["afmt"] = "{{cloze:Sentence}}{{#Notes}}<div class=notes>{{Notes}}</div>{{/Notes}}{{#Audio}}<div class=audio>{{Audio}}</div>{{/Audio}}"
    model["tmpls"] = templates
    model["css"] = ".card { font-family: -apple-system, BlinkMacSystemFont, Arial, sans-serif; font-size: 22px; text-align: left; color: #111; background: #fff; line-height: 1.5; padding: 22px; max-width: 760px; margin: 0 auto; } .cloze { font-weight: 700; color: #4f46e5; } .notes { margin-top: 18px; padding-top: 14px; border-top: 1px solid #ddd; font-size: 16px; color: #444; } .audio { margin-top: 12px; } .nightMode .card { color: #eee; background: #18181b; } .nightMode .notes { color: #ccc; border-color: #444; } .nightMode .cloze { color: #93c5fd; }"
    models[modelKey] = model

    deck["name"] = manifest.deckName
    deck["desc"] = "Corrected self-written English Cloze sentences with full-sentence audio on the back."
    deck["mod"] = Int(Date().timeIntervalSince1970)
    decks[deckKey] = deck

    let now = Int(Date().timeIntervalSince1970)
    var statements = [
        "UPDATE col SET models='\(sqlEscaped(try jsonString(models)))', decks='\(sqlEscaped(try jsonString(decks)))', mod=\(now * 1000), scm=\(now * 1000), usn=-1;"
    ]

    for (index, note) in manifest.notes.enumerated() {
        let fields = sourceRows[index].map(\.precomposedStringWithCanonicalMapping)
        guard fields[0] == note.clozeText.precomposedStringWithCanonicalMapping else {
            throw RebuildError.invalidPackage("TSV and manifest sentence mismatch for note \(index + 1).")
        }
        let joinedFields = fields.joined(separator: "\u{001F}")
        statements.append(
            "UPDATE notes SET flds='\(sqlEscaped(joinedFields))', sfld='\(sqlEscaped(fields[0]))', csum=0, mod=\(now), usn=-1 WHERE guid='\(sqlEscaped(note.guid))';"
        )
    }
    statements.append("DELETE FROM cards WHERE ord <> 0;")
    statements.append("UPDATE cards SET ord=0, mod=\(now), usn=-1;")
    statements.append("VACUUM;")
    try run("/usr/bin/sqlite3", [databaseURL.path, statements.joined(separator: "\n")])

    let noteCount = Int(try run("/usr/bin/sqlite3", [databaseURL.path, "SELECT count(*) FROM notes;"])
        .trimmingCharacters(in: .whitespacesAndNewlines))
    let cardCount = Int(try run("/usr/bin/sqlite3", [databaseURL.path, "SELECT count(*) FROM cards;"])
        .trimmingCharacters(in: .whitespacesAndNewlines))
    guard noteCount == manifest.notes.count, cardCount == manifest.notes.count else {
        throw RebuildError.invalidPackage("Expected \(manifest.notes.count) notes and cards, found \(noteCount ?? -1) notes and \(cardCount ?? -1) cards.")
    }

    try manifestData.write(to: workDirectory.appending(path: "cardvoice.json"), options: .atomic)
    let rebuilt = workDirectory.appending(path: "rebuilt.apkg")
    try run(
        "/usr/bin/zip",
        ["-q", rebuilt.path, "collection.anki2", "media", "cardvoice.json"],
        currentDirectory: workDirectory
    )

    if fileManager.fileExists(atPath: output.path) {
        try fileManager.removeItem(at: output)
    }
    try fileManager.moveItem(at: rebuilt, to: output)
    print("Rebuilt: \(output.path)")
}

do {
    try rebuild()
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
