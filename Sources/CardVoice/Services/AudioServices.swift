import AppKit
import AVFoundation
import Foundation

final class AudioPlayerService {
    private var player: AVAudioPlayer?
    func play(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        player?.play()
    }
}

@MainActor
final class SystemSpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }
}

enum AudioStore {
    enum StoreError: LocalizedError {
        case invalidFilename

        var errorDescription: String? {
            "The audio filename is empty or unsafe. Reimport a CardVoice-ready deck."
        }
    }

    static func folder() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
            .appending(path: "CardVoice", directoryHint: .isDirectory)
            .appending(path: "Audio", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func save(_ data: Data, filename: String) throws -> URL {
        guard isSafeFilename(filename) else { throw StoreError.invalidFilename }
        let url = try folder().appending(path: filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func existingURL(filename: String) -> URL? {
        guard isSafeFilename(filename) else { return nil }
        guard let base = try? folder() else { return nil }
        let url = base.appending(path: filename)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true else {
            return nil
        }
        return url
    }

    static func isSafeFilename(_ filename: String) -> Bool {
        guard !filename.isEmpty,
              filename == URL(fileURLWithPath: filename).lastPathComponent,
              filename != ".",
              filename != "..",
              ["mp3", "wav"].contains(URL(fileURLWithPath: filename).pathExtension.lowercased()) else {
            return false
        }
        return true
    }
}
