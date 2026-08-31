import Foundation
import XCTest
@testable import CardVoice

final class KokoroOfflineTests: XCTestCase {
    func testBundledVoiceChoicesMatchTheModelSpeakers() {
        XCTAssertEqual(KokoroVoice.all.count, 11)
        XCTAssertEqual(Set(KokoroVoice.all.map(\.id)), Set(0...10))
        XCTAssertEqual(KokoroVoice.all.first { $0.id == 4 }?.name, "Sky")
    }

    func testModelValidationRequiresAllRuntimeFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "CardVoice-Model-Test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(
            at: directory.appending(path: "espeak-ng-data", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        for relativePath in ["model.onnx", "voices.bin", "tokens.txt", "espeak-ng-data/phontab"] {
            let url = directory.appending(path: relativePath)
            try Data([0x01]).write(to: url)
        }

        XCTAssertTrue(KokoroModelStore.isInstalled(at: directory))
        try FileManager.default.removeItem(at: directory.appending(path: "voices.bin"))
        XCTAssertFalse(KokoroModelStore.isInstalled(at: directory))
    }

    func testRealKokoroSentenceBecomesWAVWhenModelPathIsProvided() async throws {
        let modelPath = try realModelPath()

        let data = try await KokoroOfflineService.generateWAV(
            text: "The prospect of becoming a teacher sends chills down my spine.",
            voiceID: 4,
            speed: 0.95,
            modelDirectory: URL(fileURLWithPath: modelPath, isDirectory: true)
        )

        XCTAssertGreaterThan(data.count, 10_000)
        XCTAssertTrue(data.starts(with: Data("RIFF".utf8)), "Generated data should be a WAV file.")
        XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
    }

    func testRealKokoroAudioIsEmbeddedInExportedAnkiPackage() async throws {
        let modelPath = try realModelPath()
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let package = try APKGService.load(
            url: repositoryRoot.appending(path: "Samples/User_Sentences_CardVoice_v1.apkg")
        )
        let wav = try await KokoroOfflineService.generateWAV(
            text: package.manifest.notes[0].sentence,
            voiceID: 4,
            speed: 0.95,
            modelDirectory: URL(fileURLWithPath: modelPath, isDirectory: true)
        )

        let temporary = FileManager.default.temporaryDirectory
            .appending(path: "CardVoice-Export-Test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let audioDirectory = temporary.appending(path: "Audio", directoryHint: .isDirectory)
        let extracted = temporary.appending(path: "Extracted", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)

        for note in package.manifest.notes {
            try wav.write(to: audioDirectory.appending(path: note.resolvedAudioFilename))
        }

        let output = temporary.appending(path: "CardVoice-Kokoro.apkg")
        try APKGService.exportAnkiWithAudio(
            package: package,
            destination: output,
            audioURL: { filename in audioDirectory.appending(path: filename) }
        )
        try run("/usr/bin/unzip", ["-qq", output.path, "-d", extracted.path])

        let media = try JSONDecoder().decode(
            [String: String].self,
            from: Data(contentsOf: extracted.appending(path: "media"))
        )
        let expected = Set(package.manifest.notes.map(\.resolvedAudioFilename))
        XCTAssertTrue(expected.isSubset(of: Set(media.values)))
        XCTAssertTrue(expected.allSatisfy { $0.hasSuffix("_kokoro.wav") })

        let fields = try run(
            "/usr/bin/sqlite3",
            [extracted.appending(path: "collection.anki2").path, "SELECT flds FROM notes;"]
        )
        for filename in expected {
            XCTAssertTrue(fields.contains("[sound:\(filename)]"))
        }
    }

    private func realModelPath() throws -> String {
        guard let modelPath = ProcessInfo.processInfo.environment["CARDVOICE_KOKORO_MODEL_DIR"] else {
            throw XCTSkip("Set CARDVOICE_KOKORO_MODEL_DIR to run the real offline synthesis check.")
        }
        return modelPath
    }

    @discardableResult
    private func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let stdout = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: errors.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
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
