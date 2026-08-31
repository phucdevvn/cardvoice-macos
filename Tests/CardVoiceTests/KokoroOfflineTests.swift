import Foundation
import XCTest
@testable import CardVoice

final class KokoroOfflineTests: XCTestCase {
    func testBundledVoiceChoicesMatchTheModelSpeakers() {
        XCTAssertEqual(KokoroVoice.all.map { "\($0.id)|\($0.name)|\($0.roleLabel)" }, [
            "4|Sky|US female",
            "6|Michael|US male",
            "7|Emma|UK female",
            "9|George|UK male"
        ])
    }

    func testVoiceAssignmentsAreDeterministicPseudoRandomAndBalanced() {
        let notes = (1...35).map(makeAssignmentNote)
        let first = KokoroVoiceAssignment.make(notes: notes) { _ in nil }
        let second = KokoroVoiceAssignment.make(notes: notes) { _ in nil }
        let sequence = notes.compactMap { first[KokoroVoiceAssignment.key(for: $0)] }
        let simpleCycle = notes.indices.map { KokoroVoice.all[$0 % KokoroVoice.all.count].id }
        let counts = Dictionary(grouping: sequence, by: { $0 }).mapValues(\.count)

        XCTAssertEqual(first, second)
        XCTAssertEqual(sequence.count, notes.count)
        XCTAssertNotEqual(sequence, simpleCycle)
        XCTAssertEqual(Set(counts.keys), Set(KokoroVoice.all.map(\.id)))
        XCTAssertLessThanOrEqual((counts.values.max() ?? 0) - (counts.values.min() ?? 0), 1)
    }

    func testExistingVoiceSpecificAudioKeepsItsAssignment() {
        let notes = (1...8).map(makeAssignmentNote)
        let preserved: [String: Int] = [
            KokoroVoiceAssignment.key(for: notes[0]): 9,
            KokoroVoiceAssignment.key(for: notes[1]): 4
        ]
        let assignments = KokoroVoiceAssignment.make(notes: notes) { note in
            preserved[KokoroVoiceAssignment.key(for: note)]
        }

        XCTAssertEqual(assignments[KokoroVoiceAssignment.key(for: notes[0])], 9)
        XCTAssertEqual(assignments[KokoroVoiceAssignment.key(for: notes[1])], 4)
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
        let temporary = FileManager.default.temporaryDirectory
            .appending(path: "CardVoice-Export-Test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let audioDirectory = temporary.appending(path: "Audio", directoryHint: .isDirectory)
        let extracted = temporary.appending(path: "Extracted", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)

        let assignments = KokoroVoiceAssignment.make(notes: package.manifest.notes) { _ in nil }
        let assignmentCounts = Dictionary(grouping: assignments.values, by: { $0 }).mapValues(\.count)
        XCTAssertEqual(Set(assignmentCounts.keys), Set(KokoroVoice.all.map(\.id)))
        XCTAssertEqual(assignmentCounts.values.sorted(), [1, 2, 2, 2])
        let filename: (CardVoiceNote) -> String = { note in
            let voiceID = assignments[KokoroVoiceAssignment.key(for: note)]!
            return note.kokoroAudioFilename(voiceID: voiceID)
        }
        for note in package.manifest.notes {
            let voiceID = assignments[KokoroVoiceAssignment.key(for: note)]!
            let wav = try await KokoroOfflineService.generateWAV(
                text: note.sentence,
                voiceID: voiceID,
                speed: 0.95,
                modelDirectory: URL(fileURLWithPath: modelPath, isDirectory: true)
            )
            try wav.write(to: audioDirectory.appending(path: filename(note)))
        }

        let output = temporary.appending(path: "CardVoice-Kokoro.apkg")
        try APKGService.exportAnkiWithAudio(
            package: package,
            destination: output,
            audioFilename: filename,
            audioURL: { filename in audioDirectory.appending(path: filename) }
        )
        try run("/usr/bin/unzip", ["-qq", output.path, "-d", extracted.path])

        let media = try JSONDecoder().decode(
            [String: String].self,
            from: Data(contentsOf: extracted.appending(path: "media"))
        )
        let expected = Set(package.manifest.notes.map(filename))
        XCTAssertTrue(expected.isSubset(of: Set(media.values)))
        XCTAssertTrue(expected.allSatisfy { value in
            KokoroVoice.all.contains { value.hasSuffix("_kokoro_v\($0.id).wav") }
        })

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

    private func makeAssignmentNote(_ number: Int) -> CardVoiceNote {
        CardVoiceNote(
            id: String(format: "cv%03d", number),
            guid: "guid-\(number)",
            sentence: "Sentence number \(number).",
            clozeText: "{{c1::Sentence}} number \(number).",
            targets: ["sentence"],
            pattern: "sentence",
            meaning: "câu",
            audioFilename: String(format: "cardvoice_cv%03d_kokoro.wav", number),
            audioFieldIndex: 2,
            fieldCount: 3,
            clozeNumbers: [1]
        )
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
