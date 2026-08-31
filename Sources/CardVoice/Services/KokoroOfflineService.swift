import Foundation
import SherpaOnnx

enum KokoroOfflineService {
    enum SynthesisError: LocalizedError {
        case modelNotInstalled
        case engineInitializationFailed
        case wavWriteFailed
        case emptyAudio

        var errorDescription: String? {
            switch self {
            case .modelNotInstalled:
                return "Install the offline Kokoro voice model in Settings first."
            case .engineInitializationFailed:
                return "Kokoro could not initialize its offline speech engine."
            case .wavWriteFailed:
                return "Kokoro generated audio, but CardVoice could not save the temporary WAV file."
            case .emptyAudio:
                return "Kokoro returned an empty audio file."
            }
        }
    }

    static func generateWAV(
        text: String,
        voiceID: Int,
        speed: Double,
        modelDirectory: URL? = nil
    ) async throws -> Data {
        let directory = try modelDirectory ?? KokoroModelStore.modelDirectory()
        guard KokoroModelStore.isInstalled(at: directory) else {
            throw SynthesisError.modelNotInstalled
        }

        return try await Task.detached(priority: .userInitiated) {
            let kokoro = sherpaOnnxOfflineTtsKokoroModelConfig(
                model: directory.appending(path: "model.onnx").path,
                voices: directory.appending(path: "voices.bin").path,
                tokens: directory.appending(path: "tokens.txt").path,
                dataDir: directory.appending(path: "espeak-ng-data", directoryHint: .isDirectory).path
            )
            let model = sherpaOnnxOfflineTtsModelConfig(
                kokoro: kokoro,
                numThreads: max(2, min(ProcessInfo.processInfo.activeProcessorCount / 2, 6))
            )
            var config = sherpaOnnxOfflineTtsConfig(model: model, maxNumSentences: 1)
            let engine = SherpaOnnxOfflineTtsWrapper(config: &config)
            guard engine.tts != nil else { throw SynthesisError.engineInitializationFailed }

            let generated = engine.generate(
                text: text,
                sid: voiceID,
                speed: Float(speed)
            )
            let temporary = FileManager.default.temporaryDirectory
                .appending(path: "CardVoice-Kokoro-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporary) }

            let wav = temporary.appending(path: "speech.wav")
            guard generated.save(filename: wav.path) == 1 else {
                throw SynthesisError.wavWriteFailed
            }
            let data = try Data(contentsOf: wav)
            guard !data.isEmpty else { throw SynthesisError.emptyAudio }
            return data
        }.value
    }
}
