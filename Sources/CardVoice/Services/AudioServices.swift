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
    static func folder() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "CardVoice/Audio", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func save(_ data: Data, filename: String) throws -> URL {
        let url = try folder().appending(path: filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func existingURL(filename: String) -> URL? {
        guard let base = try? folder() else { return nil }
        let url = base.appending(path: filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
