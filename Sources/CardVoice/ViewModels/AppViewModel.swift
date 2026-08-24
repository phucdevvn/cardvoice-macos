import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    @Published var package: LoadedPackage?
    @Published var keyProfiles: [APIKeyProfile] = []
    @Published var selectedKeyID: UUID?
    @Published var voices: [ElevenVoice] = []
    @Published var selectedVoiceID: String = ""
    @Published var voiceSearch: String = "Lawrence"
    @Published var modelID: String = "eleven_multilingual_v2"
    @Published var outputFormat: String = "mp3_44100_128"
    @Published var status: String = "Import a CardVoice-ready Anki deck to begin."
    @Published var isWorking = false
    @Published var subscriptionDescription: String = ""
    @Published var completedCount = 0

    private let client = ElevenLabsClient()
    private let audioPlayer = AudioPlayerService()
    let systemSpeech = SystemSpeechService()

    private enum Keys {
        static let profiles = "cardvoice.keys.profiles.v2"
        static let selectedKey = "cardvoice.keys.selected.v2"
        static let selectedVoice = "cardvoice.voice.selected.v2"
        static let modelID = "cardvoice.model.selected.v2"
        static let outputFormat = "cardvoice.output.format.v1"
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Keys.profiles),
           let decoded = try? JSONDecoder().decode([APIKeyProfile].self, from: data) { keyProfiles = decoded }
        if let raw = UserDefaults.standard.string(forKey: Keys.selectedKey) { selectedKeyID = UUID(uuidString: raw) }
        selectedVoiceID = UserDefaults.standard.string(forKey: Keys.selectedVoice) ?? ""
        modelID = UserDefaults.standard.string(forKey: Keys.modelID) ?? "eleven_multilingual_v2"
        outputFormat = UserDefaults.standard.string(forKey: Keys.outputFormat) ?? "mp3_44100_128"
        refreshCompletedCount()
    }

    var notes: [CardVoiceNote] { package?.manifest.notes ?? [] }
    var selectedProfile: APIKeyProfile? {
        guard let selectedKeyID else { return keyProfiles.first }
        return keyProfiles.first { $0.id == selectedKeyID }
    }
    var activeAPIKey: String? {
        guard let profile = selectedProfile else { return nil }
        return KeychainStore.read(account: profile.keychainAccount)
    }

    func persist() {
        if let data = try? JSONEncoder().encode(keyProfiles) { UserDefaults.standard.set(data, forKey: Keys.profiles) }
        UserDefaults.standard.set(selectedKeyID?.uuidString, forKey: Keys.selectedKey)
        UserDefaults.standard.set(selectedVoiceID, forKey: Keys.selectedVoice)
        UserDefaults.standard.set(modelID, forKey: Keys.modelID)
        UserDefaults.standard.set(outputFormat, forKey: Keys.outputFormat)
    }

    func addKey(label: String, secret: String) throws {
        let profile = APIKeyProfile(label: label.isEmpty ? "ElevenLabs" : label)
        try KeychainStore.save(secret, account: profile.keychainAccount)
        keyProfiles.append(profile); selectedKeyID = profile.id; persist()
    }

    func importElevenLabsEnvironment() {
        let panel = NSOpenPanel()
        panel.title = "Import ElevenLabs .env"
        panel.message = "API keys will be copied into macOS Keychain. CardVoice does not keep a plaintext copy of the file."
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["env", "txt"]
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let imported = ElevenLabsEnvironmentImport.parse(text)
            guard !imported.apiKeys.isEmpty || imported.voiceID != nil || imported.modelID != nil || imported.outputFormat != nil else {
                status = "No supported ElevenLabs settings were found in that file."
                return
            }

            let existingSecrets = Set(keyProfiles.compactMap { KeychainStore.read(account: $0.keychainAccount) })
            var added = 0
            for (index, pair) in imported.apiKeys.enumerated() where !existingSecrets.contains(pair.value) {
                let suffix = pair.name.split(separator: "_").last.flatMap { Int($0) }
                let label = suffix.map { "API Key \($0)" } ?? "API Key \(index + 1)"
                try addKey(label: label, secret: pair.value)
                added += 1
            }

            if let voiceID = imported.voiceID { selectedVoiceID = voiceID }
            if let modelID = imported.modelID { self.modelID = modelID }
            if let outputFormat = imported.outputFormat { self.outputFormat = outputFormat }
            if selectedKeyID == nil { selectedKeyID = keyProfiles.first?.id }
            persist()

            let duplicateCount = imported.apiKeys.count - added
            var summary = "Imported \(added) new API key\(added == 1 ? "" : "s")"
            if duplicateCount > 0 { summary += "; skipped \(duplicateCount) duplicate\(duplicateCount == 1 ? "" : "s")" }
            if imported.voiceID != nil || imported.modelID != nil || imported.outputFormat != nil { summary += "; applied voice/model/output settings" }
            status = summary + "."
        } catch {
            status = "Could not import .env: \(error.localizedDescription)"
        }
    }

    func deleteKey(_ profile: APIKeyProfile) {
        KeychainStore.delete(account: profile.keychainAccount)
        keyProfiles.removeAll { $0.id == profile.id }
        if selectedKeyID == profile.id { selectedKeyID = keyProfiles.first?.id }
        persist()
    }

    func importAPKG() {
        let panel = NSOpenPanel()
        panel.title = "Import CardVoice-ready Anki deck"
        panel.allowedFileTypes = ["apkg"]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            package = try APKGService.load(url: url)
            refreshCompletedCount()
            status = "Loaded \(notes.count) notes from \(url.lastPathComponent)."
        } catch { status = error.localizedDescription }
    }

    func fetchVoices() async {
        guard let key = activeAPIKey else { status = "Add an ElevenLabs API key first."; return }
        isWorking = true; defer { isWorking = false }
        do {
            voices = try await client.voices(apiKey: key, search: voiceSearch)
            if selectedVoiceID.isEmpty, let first = voices.first { selectedVoiceID = first.voice_id }
            status = voices.isEmpty ? "No voices found." : "Loaded \(voices.count) voices."
            persist()
        } catch { status = error.localizedDescription }
    }

    func refreshUsage() async {
        guard let key = activeAPIKey else { status = "Add an ElevenLabs API key first."; return }
        do {
            let sub = try await client.subscription(apiKey: key)
            subscriptionDescription = sub.usageDescription
            status = "Usage refreshed."
        } catch { status = error.localizedDescription }
    }

    func hasAudio(_ note: CardVoiceNote) -> Bool { AudioStore.existingURL(filename: note.audioFilename) != nil }

    func generateAudio(for note: CardVoiceNote) async -> Bool {
        guard let key = activeAPIKey else { status = "Add an ElevenLabs API key first."; return false }
        guard !selectedVoiceID.isEmpty else { status = "Choose a voice first."; return false }
        isWorking = true; defer { isWorking = false }
        do {
            status = "Generating \(note.audioFilename)…"
            let data = try await client.generateSpeech(text: note.sentence, apiKey: key, voiceID: selectedVoiceID, modelID: modelID, outputFormat: outputFormat)
            _ = try AudioStore.save(data, filename: note.audioFilename)
            refreshCompletedCount()
            status = "Generated \(note.audioFilename)."
            return true
        } catch {
            status = error.localizedDescription + " Select another authorized key manually if appropriate, then resume."
            return false
        }
    }

    func generateMissingAudio() async {
        guard package != nil else { status = "Import an .apkg first."; return }
        for note in notes where !hasAudio(note) {
            let ok = await generateAudio(for: note)
            if !ok { break }
        }
        refreshCompletedCount()
        if completedCount == notes.count && !notes.isEmpty { status = "All sentence audio is ready." }
    }

    func playAudio(_ note: CardVoiceNote) {
        guard let url = AudioStore.existingURL(filename: note.audioFilename) else { return }
        do { try audioPlayer.play(url: url) } catch { status = error.localizedDescription }
    }

    func exportAudioZip() {
        guard let package else { status = "Import an .apkg first."; return }
        guard completedCount == notes.count else { status = "Generate all audio before exporting."; return }
        let panel = NSSavePanel(); panel.title = "Export generated audio ZIP"; panel.nameFieldStringValue = "CardVoice-Audio.zip"; panel.allowedFileTypes = ["zip"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try APKGService.exportAudioZip(package: package, destination: url); status = "Exported \(url.lastPathComponent)." }
        catch { status = error.localizedDescription }
    }

    func exportAnkiWithAudio() {
        guard let package else { status = "Import an .apkg first."; return }
        guard completedCount == notes.count else { status = "Generate all audio before exporting."; return }
        let panel = NSSavePanel(); panel.title = "Export Anki deck with audio"; panel.nameFieldStringValue = package.sourceURL.deletingPathExtension().lastPathComponent + "-audio.apkg"; panel.allowedFileTypes = ["apkg"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try APKGService.exportAnkiWithAudio(package: package, destination: url); status = "Exported Anki deck with embedded audio." }
        catch { status = error.localizedDescription }
    }

    private func refreshCompletedCount() {
        completedCount = notes.filter { AudioStore.existingURL(filename: $0.audioFilename) != nil }.count
    }
}
