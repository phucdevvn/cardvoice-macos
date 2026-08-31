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
}
