import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: AppViewModel
    @State private var newLabel = "Personal"
    @State private var newSecret = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            configurationSection
            apiKeysSection
            voiceSection
        }
        .formStyle(.grouped)
        .frame(width: 760, height: 660)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    vm.persist()
                    dismiss()
                }
            }
        }
    }

    private var configurationSection: some View {
        Section("ElevenLabs configuration") {
            HStack {
                Button("Import .env…") {
                    vm.importElevenLabsEnvironment()
                }
                Text("Imports ELEVENLABS_API_KEY_*, voice ID, model ID, and output format.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("The selected file is read once. Secrets are stored in macOS Keychain; CardVoice does not copy the .env file into the app or repository.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var apiKeysSection: some View {
        Section("ElevenLabs API keys") {
            if vm.keyProfiles.isEmpty {
                Text("No API keys saved.")
                    .foregroundStyle(.secondary)
            }

            ForEach(vm.keyProfiles) { profile in
                keyRow(profile)
            }

            HStack {
                TextField("Label", text: $newLabel)
                SecureField("xi-api-key", text: $newSecret)
                Button("Add") {
                    addCurrentKey()
                }
                .disabled(trimmedSecret.isEmpty)
            }

            Text("Secrets stay in macOS Keychain. You can store multiple authorized keys and select one manually. CardVoice does not auto-rotate free-tier keys to evade provider quotas.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var voiceSection: some View {
        Section("Voice") {
            HStack {
                TextField("Search voices", text: $vm.voiceSearch)
                Button("Load") {
                    Task { await vm.fetchVoices() }
                }
            }

            voicePicker
            TextField("Model", text: $vm.modelID)
            TextField("Output format", text: $vm.outputFormat)

            HStack {
                Button("Check usage") {
                    Task { await vm.refreshUsage() }
                }
                Text(vm.subscriptionDescription)
                    .foregroundStyle(.secondary)
            }

            Text("Generation uses the imported/output format value, speed 1.0, style 0, speaker boost on. You can override voice/model/format after importing .env.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var voicePicker: some View {
        if vm.voices.isEmpty {
            TextField("Voice ID", text: $vm.selectedVoiceID)
        } else {
            Picker("Voice", selection: $vm.selectedVoiceID) {
                ForEach(vm.voices) { voice in
                    voiceLabel(voice)
                        .tag(voice.voice_id)
                }
            }
        }
    }

    private func keyRow(_ profile: APIKeyProfile) -> some View {
        HStack {
            Toggle(profile.label, isOn: selectionBinding(for: profile))
                .toggleStyle(.radio)
            Spacer()
            Button(role: .destructive) {
                vm.deleteKey(profile)
            } label: {
                Image(systemName: "trash")
            }
        }
    }

    private func voiceLabel(_ voice: ElevenVoice) -> some View {
        VStack(alignment: .leading) {
            Text(voice.displayName)
            if !voice.subtitle.isEmpty {
                Text(voice.subtitle)
                    .font(.caption)
            }
        }
    }

    private func selectionBinding(for profile: APIKeyProfile) -> Binding<Bool> {
        Binding(
            get: { vm.selectedKeyID == profile.id },
            set: { isSelected in
                guard isSelected else { return }
                vm.selectedKeyID = profile.id
                vm.persist()
            }
        )
    }

    private var trimmedSecret: String {
        newSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addCurrentKey() {
        do {
            try vm.addKey(label: newLabel, secret: trimmedSecret)
            newSecret = ""
        } catch {
            vm.status = error.localizedDescription
        }
    }
}
