import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    @Published var package: LoadedPackage?
    @Published var status: String = "Install the offline Kokoro voice model, then import an Anki deck."
    @Published var isWorking = false
    @Published var isInstallingModel = false
    @Published var completedCount = 0
    @Published var kokoroSpeed = 0.95
    @Published var kokoroModelInstalled = false
    @Published private(set) var voiceAssignments: [String: Int] = [:]

    private let audioPlayer = AudioPlayerService()
    let systemSpeech = SystemSpeechService()

    private enum Keys {
        static let speed = "cardvoice.kokoro.speed.v1"
    }

    init() {
        let savedSpeed = UserDefaults.standard.object(forKey: Keys.speed) as? Double
        kokoroSpeed = savedSpeed.map { min(max($0, 0.75), 1.25) } ?? 0.95
        kokoroModelInstalled = KokoroModelStore.isInstalled()
        refreshCompletedCount()
        if kokoroModelInstalled {
            status = "Kokoro is installed. Import a CardVoice-ready Anki deck to begin."
        }
    }

    var notes: [CardVoiceNote] { package?.manifest.notes ?? [] }

    func assignedKokoroVoice(for note: CardVoiceNote) -> KokoroVoice {
        let voiceID = voiceAssignments[KokoroVoiceAssignment.key(for: note)] ?? KokoroVoice.all[0].id
        return KokoroVoice.all.first { $0.id == voiceID } ?? KokoroVoice.all[0]
    }

    func audioFilename(for note: CardVoiceNote) -> String {
        note.kokoroAudioFilename(voiceID: assignedKokoroVoice(for: note).id)
    }

    func persist() {
        UserDefaults.standard.set(kokoroSpeed, forKey: Keys.speed)
    }

    func installKokoroModel() async {
        guard !isWorking else { return }
        isWorking = true
        isInstallingModel = true
        status = "Downloading the Kokoro offline model (about 305 MB)…"
        defer {
            isWorking = false
            isInstallingModel = false
        }

        do {
            _ = try await KokoroModelStore.install()
            kokoroModelInstalled = true
            status = "Kokoro installed. Voice generation is now fully offline."
        } catch {
            kokoroModelInstalled = KokoroModelStore.isInstalled()
            status = error.localizedDescription
        }
    }

    func previewKokoroVoice(_ voice: KokoroVoice) async {
        guard kokoroModelInstalled else {
            status = "Install the offline Kokoro model first."
            return
        }
        guard !isWorking else { return }
        isWorking = true
        status = "Generating a local preview with \(voice.name)…"
        defer { isWorking = false }

        do {
            let data = try await KokoroOfflineService.generateWAV(
                text: "When I speak English, I want my voice to sound clear, calm, and natural.",
                voiceID: voice.id,
                speed: kokoroSpeed
            )
            let url = try AudioStore.save(data, filename: "cardvoice_kokoro_preview_v\(voice.id).wav")
            try audioPlayer.play(url: url)
            status = "Playing \(voice.displayName) at \(kokoroSpeed.formatted(.number.precision(.fractionLength(2))))×."
        } catch {
            status = error.localizedDescription
        }
    }

    func importAPKG() {
        let panel = NSOpenPanel()
        panel.title = "Import CardVoice-ready Anki deck"
        if let type = UTType(filenameExtension: "apkg") { panel.allowedContentTypes = [type] }
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            package = try APKGService.load(url: url)
            refreshVoiceAssignments()
            refreshCompletedCount()
            status = "Loaded \(notes.count) notes with a balanced four-voice mix from \(url.lastPathComponent)."
        } catch {
            status = error.localizedDescription
        }
    }

    func hasAudio(_ note: CardVoiceNote) -> Bool {
        AudioStore.existingURL(filename: audioFilename(for: note)) != nil
    }

    func generateAudio(for note: CardVoiceNote) async -> Bool {
        guard kokoroModelInstalled else {
            status = "Install the offline Kokoro model in Settings first."
            return false
        }
        guard !isWorking else { return false }
        isWorking = true
        let voice = assignedKokoroVoice(for: note)
        let filename = audioFilename(for: note)
        status = "Generating \(filename) locally with \(voice.name)…"
        defer { isWorking = false }

        do {
            let data = try await KokoroOfflineService.generateWAV(
                text: note.sentence,
                voiceID: voice.id,
                speed: kokoroSpeed
            )
            _ = try AudioStore.save(data, filename: filename)
            refreshCompletedCount()
            status = "Generated \(filename) with \(voice.displayName)."
            return true
        } catch {
            status = error.localizedDescription
            return false
        }
    }

    func generateMissingAudio() async {
        guard package != nil else { status = "Import an .apkg first."; return }
        guard kokoroModelInstalled else { status = "Install the offline Kokoro model first."; return }
        for note in notes where !hasAudio(note) {
            let ok = await generateAudio(for: note)
            if !ok { break }
        }
        refreshCompletedCount()
        if completedCount == notes.count, !notes.isEmpty {
            status = "All sentence audio is ready."
        }
    }

    func regenerateAllAudio() async {
        guard package != nil else { status = "Import an .apkg first."; return }
        guard kokoroModelInstalled else { status = "Install the offline Kokoro model first."; return }
        guard !notes.isEmpty else { status = "The imported deck has no notes."; return }

        let total = notes.count
        var regenerated = 0
        for note in notes {
            let ok = await generateAudio(for: note)
            guard ok else {
                let failure = status
                refreshCompletedCount()
                status = "Regeneration stopped after \(regenerated)/\(total) audio files. \(failure)"
                return
            }
            regenerated += 1
        }

        refreshCompletedCount()
        status = "Regenerated all \(total) sentence audio files locally."
    }

    func playAudio(_ note: CardVoiceNote) {
        guard let url = AudioStore.existingURL(filename: audioFilename(for: note)) else { return }
        do { try audioPlayer.play(url: url) }
        catch { status = error.localizedDescription }
    }

    func exportAudioZip() {
        guard let package else { status = "Import an .apkg first."; return }
        guard completedCount == notes.count else { status = "Generate all audio before exporting."; return }
        let panel = NSSavePanel()
        panel.title = "Export generated audio ZIP"
        panel.nameFieldStringValue = "CardVoice-Audio.zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try APKGService.exportAudioZip(
                package: package,
                destination: url,
                audioFilename: audioFilename(for:)
            )
            status = "Exported \(url.lastPathComponent)."
        } catch {
            status = error.localizedDescription
        }
    }

    func exportAnkiWithAudio() {
        guard let package else { status = "Import an .apkg first."; return }
        guard completedCount == notes.count else { status = "Generate all audio before exporting."; return }
        let panel = NSSavePanel()
        panel.title = "Export Anki deck with audio"
        panel.nameFieldStringValue = package.sourceURL.deletingPathExtension().lastPathComponent + "-audio.apkg"
        if let type = UTType(filenameExtension: "apkg") { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try APKGService.exportAnkiWithAudio(
                package: package,
                destination: url,
                audioFilename: audioFilename(for:)
            )
            status = "Exported Anki deck with embedded offline audio."
        } catch {
            status = error.localizedDescription
        }
    }

    private func refreshCompletedCount() {
        completedCount = notes.filter { AudioStore.existingURL(filename: audioFilename(for: $0)) != nil }.count
    }

    private func refreshVoiceAssignments() {
        voiceAssignments = KokoroVoiceAssignment.make(notes: notes) { note in
            KokoroVoice.all.first { voice in
                AudioStore.existingURL(filename: note.kokoroAudioFilename(voiceID: voice.id)) != nil
            }?.id
        }
    }
}
