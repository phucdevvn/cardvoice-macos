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

    func testManifestlessAnkiExportCanBeRecovered() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sampleURL = repositoryRoot.appending(path: "Samples/User_Sentences_CardVoice_v1.apkg")

        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "CardVoice-Manifestless-Test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let unpacked = tempRoot.appending(path: "unpacked", directoryHint: .isDirectory)
        let manifestlessURL = tempRoot.appending(path: "English-Sentences-Anki-Export.apkg")
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try run("/usr/bin/unzip", ["-qq", sampleURL.path, "-d", unpacked.path])
        try FileManager.default.removeItem(at: unpacked.appending(path: "cardvoice.json"))
        try run("/usr/bin/zip", ["-q", "-r", manifestlessURL.path, "."], currentDirectory: unpacked)

        let package = try APKGService.load(url: manifestlessURL)

        XCTAssertEqual(package.manifest.deckName, "English Sentences")
        XCTAssertEqual(package.manifest.noteType, "CardVoice Cloze")
        XCTAssertEqual(package.manifest.notes.count, 7)
        XCTAssertEqual(package.manifest.notes.first?.sentence, "When I try to think and speak in English, my mind suddenly goes blank. I can't help but remain silent.")
        XCTAssertEqual(package.manifest.notes.first?.targets, ["my mind goes blank"])
        XCTAssertTrue(package.manifest.notes.allSatisfy { note in
            note.fieldCount == 3 && note.audioFieldIndex == 2 && note.clozeNumbers == [1]
        })
    }

    @discardableResult
    private func run(_ executable: String, _ arguments: [String], currentDirectory: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "SamplePackageTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: error.isEmpty ? "Command failed: \(executable)" : error]
            )
        }
        return output
    }
}
