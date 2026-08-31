import XCTest
@testable import CardVoice

final class CardVoiceNoteTests: XCTestCase {
    func testSinglePatternAndMeaningBecomeOneNote() {
        let note = makeNote(pattern: "the prospect of + noun/-ing", meaning: "viễn cảnh / khả năng sẽ làm gì")

        XCTAssertEqual(
            note.combinedNotes,
            "the prospect of + noun/-ing — viễn cảnh / khả năng sẽ làm gì"
        )
    }

    func testMultiplePatternsArePairedWithTheirMeanings() {
        let note = makeNote(
            pattern: "hit a bump · figure something out · have nothing to do with",
            meaning: "gặp trở ngại; tìm ra cách giải quyết; không liên quan đến"
        )

        XCTAssertEqual(note.combinedNotesLines, [
            "hit a bump — gặp trở ngại",
            "figure something out — tìm ra cách giải quyết",
            "have nothing to do with — không liên quan đến"
        ])
        XCTAssertEqual(
            note.combinedNotesHTML,
            "hit a bump — gặp trở ngại<br>figure something out — tìm ra cách giải quyết<br>have nothing to do with — không liên quan đến"
        )
    }

    func testNotesAreEscapedBeforeBeingWrittenAsAnkiHTML() {
        let note = makeNote(pattern: "A < B & C", meaning: "say \"yes\"")

        XCTAssertEqual(note.combinedNotesHTML, "A &lt; B &amp; C — say &quot;yes&quot;")
    }

    func testThreeFieldLayoutOmitsVisibleCardVoiceID() throws {
        let note = makeNote(fieldCount: 3, audioFieldIndex: 2)

        XCTAssertEqual(
            try APKGService.ankiFields(for: note, audioMarkup: "[sound:cardvoice_cv007.mp3]"),
            [
                note.clozeText,
                "the prospect of + noun/-ing — viễn cảnh / khả năng sẽ làm gì",
                "[sound:cardvoice_cv007.mp3]"
            ]
        )
    }

    func testLegacyFiveFieldLayoutRemainsSupported() throws {
        let note = makeNote(fieldCount: 5, audioFieldIndex: 3)

        XCTAssertEqual(
            try APKGService.ankiFields(for: note, audioMarkup: "[sound:cardvoice_cv007.mp3]"),
            [note.clozeText, note.pattern, note.meaning, "[sound:cardvoice_cv007.mp3]", note.id]
        )
    }

    func testEmptyAudioFilenameUsesTheCardVoiceID() {
        let note = makeNote(id: "cv026", audioFilename: "")

        XCTAssertEqual(note.resolvedAudioFilename, "cardvoice_cv026_kokoro.wav")
    }

    func testUnsafeAudioFilenameUsesASafeFallback() {
        let note = makeNote(id: "cv/026", audioFilename: "../shared.mp3")

        XCTAssertEqual(note.resolvedAudioFilename, "cardvoice_cv_026_kokoro.wav")
    }

    func testValidAudioFilenameIsPreserved() {
        let note = makeNote(id: "cv026", audioFilename: "lesson-026.mp3")

        XCTAssertEqual(note.resolvedAudioFilename, "lesson-026_kokoro.wav")
    }

    func testVoiceSpecificFilenamePreservesTheAssignedKokoroSpeaker() {
        let note = makeNote(id: "cv026", audioFilename: "lesson-026.mp3")

        XCTAssertEqual(note.kokoroAudioFilename(voiceID: 7), "lesson-026_kokoro_v7.wav")
    }

    func testEmptyFilenameNeverCountsTheAudioDirectoryAsGeneratedAudio() {
        XCTAssertNil(AudioStore.existingURL(filename: ""))
    }

    private func makeNote(
        id: String = "cv007",
        pattern: String = "the prospect of + noun/-ing",
        meaning: String = "viễn cảnh / khả năng sẽ làm gì",
        fieldCount: Int = 3,
        audioFieldIndex: Int = 2,
        audioFilename: String = "cardvoice_cv007.mp3"
    ) -> CardVoiceNote {
        CardVoiceNote(
            id: id,
            guid: "6kgrOVZcuSc",
            sentence: "The prospect of becoming a teacher sends chills down my spine.",
            clozeText: "{{c1::The prospect of becoming a teacher}} sends chills down my spine.",
            targets: ["the prospect of + noun/-ing"],
            pattern: pattern,
            meaning: meaning,
            audioFilename: audioFilename,
            audioFieldIndex: audioFieldIndex,
            fieldCount: fieldCount,
            clozeNumbers: [1]
        )
    }
}
