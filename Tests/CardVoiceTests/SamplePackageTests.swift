import Foundation
import XCTest
@testable import CardVoice

final class SamplePackageTests: XCTestCase {
    func testSamplePackageUsesTheSimplifiedLayout() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sampleURL = repositoryRoot.appending(path: "Samples/User_Sentences_CardVoice_v1.apkg")

        let package = try APKGService.load(url: sampleURL)

        XCTAssertEqual(package.manifest.deckName, "English Sentences")
        XCTAssertEqual(package.manifest.noteType, "CardVoice Cloze")
        XCTAssertEqual(package.manifest.notes.count, 7)
        XCTAssertTrue(package.manifest.notes.allSatisfy { note in
            note.fieldCount == 3 && note.audioFieldIndex == 2 && note.clozeNumbers == [1]
        })
    }

    func testExportRepairsDeckMetadataAndReusesMediaWhenReexported() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sampleURL = repositoryRoot.appending(path: "Samples/User_Sentences_CardVoice_v1.apkg")
        let temporary = FileManager.default.temporaryDirectory
            .appending(path: "CardVoice-Reexport-Test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let malformedDirectory = temporary.appending(path: "Malformed", directoryHint: .isDirectory)
        let firstExtracted = temporary.appending(path: "First", directoryHint: .isDirectory)
        let secondExtracted = temporary.appending(path: "Second", directoryHint: .isDirectory)
        let audioDirectory = temporary.appending(path: "Audio", directoryHint: .isDirectory)
        for directory in [malformedDirectory, firstExtracted, secondExtracted, audioDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try run("/usr/bin/unzip", ["-qq", sampleURL.path, "-d", malformedDirectory.path])

        let database = malformedDirectory.appending(path: "collection.anki2")
        let originalDecks = try readJSONObject(column: "decks", from: database)
        var malformedDecks = originalDecks
        for key in malformedDecks.keys {
            var deck = try XCTUnwrap(malformedDecks[key] as? [String: Any])
            for missingKey in ["lrnToday", "revToday", "newToday", "timeToday"] {
                deck.removeValue(forKey: missingKey)
            }
            malformedDecks[key] = deck
        }
        let malformedDeckText = try jsonString(malformedDecks).replacingOccurrences(of: "'", with: "''")
        try run("/usr/bin/sqlite3", [database.path, "UPDATE col SET decks='\(malformedDeckText)';"])

        let malformedPackage = temporary.appending(path: "Malformed.apkg")
        try run("/usr/bin/zip", ["-q", "-r", malformedPackage.path, "."], currentDirectory: malformedDirectory)
        let package = try APKGService.load(url: malformedPackage)
        for note in package.manifest.notes {
            try Data("RIFF CardVoice regression audio".utf8)
                .write(to: audioDirectory.appending(path: note.resolvedAudioFilename))
        }

        let firstExport = temporary.appending(path: "First.apkg")
        try APKGService.exportAnkiWithAudio(
            package: package,
            destination: firstExport,
            audioURL: { audioDirectory.appending(path: $0) }
        )
        try run("/usr/bin/unzip", ["-qq", firstExport.path, "-d", firstExtracted.path])
        try assertRequiredDeckFields(in: firstExtracted.appending(path: "collection.anki2"))
        let firstMedia = try readMedia(from: firstExtracted)
        XCTAssertEqual(firstMedia.count, package.manifest.notes.count)

        let secondExport = temporary.appending(path: "Second.apkg")
        try APKGService.exportAnkiWithAudio(
            package: APKGService.load(url: firstExport),
            destination: secondExport,
            audioURL: { audioDirectory.appending(path: $0) }
        )
        try run("/usr/bin/unzip", ["-qq", secondExport.path, "-d", secondExtracted.path])
        let secondMedia = try readMedia(from: secondExtracted)
        XCTAssertEqual(secondMedia, firstMedia)
        XCTAssertEqual(secondMedia.count, package.manifest.notes.count)
    }

    private func assertRequiredDeckFields(in database: URL) throws {
        let decks = try readJSONObject(column: "decks", from: database)
        for value in decks.values {
            let deck = try XCTUnwrap(value as? [String: Any])
            for key in ["lrnToday", "revToday", "newToday", "timeToday"] {
                XCTAssertEqual(deck[key] as? [Int], [0, 0], "Missing or invalid \(key)")
            }
        }
    }

    private func readMedia(from directory: URL) throws -> [String: String] {
        try JSONDecoder().decode(
            [String: String].self,
            from: Data(contentsOf: directory.appending(path: "media"))
        )
    }

    private func readJSONObject(column: String, from database: URL) throws -> [String: Any] {
        let text = try run("/usr/bin/sqlite3", [database.path, "SELECT \(column) FROM col;"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
    }

    private func jsonString(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    @discardableResult
    private func run(
        _ executable: String,
        _ arguments: [String],
        currentDirectory: URL? = nil
    ) throws -> String {
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
        let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "CardVoiceTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: stderr]
            )
        }
        return stdout
    }
}
