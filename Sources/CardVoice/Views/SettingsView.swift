import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            modelSection
            voiceSection
        }
        .formStyle(.grouped)
        .frame(width: 660, height: 560)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    vm.persist()
                    dismiss()
                }
            }
        }
    }

    private var modelSection: some View {
        Section("Offline Kokoro model") {
            HStack {
                Label(
                    vm.kokoroModelInstalled ? "Installed" : "Not installed",
                    systemImage: vm.kokoroModelInstalled ? "checkmark.circle.fill" : "arrow.down.circle"
                )
                .foregroundStyle(vm.kokoroModelInstalled ? .green : .secondary)
                Spacer()
                if vm.isInstallingModel {
                    ProgressView().controlSize(.small)
                    Text("Downloading…").foregroundStyle(.secondary)
                } else {
                    Button(vm.kokoroModelInstalled ? "Reinstall Model" : "Install Offline Voice") {
                        Task { await vm.installKokoroModel() }
                    }
                    .disabled(vm.isWorking)
                }
            }

            Text("Downloads about 305 MB once and uses about 340 MB on disk. After installation, sentence generation stays on this Mac and needs no account, API key, billing, or internet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var voiceSection: some View {
        Section("Automatic four-voice mix") {
            Text("Cards are distributed pseudo-randomly and as evenly as possible across these fixed voices. Existing voice-specific audio keeps its assignment.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(KokoroVoice.all) { voice in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.name).fontWeight(.medium)
                        Text(voice.roleLabel).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Preview") {
                        vm.persist()
                        Task { await vm.previewKokoroVoice(voice) }
                    }
                    .disabled(!vm.kokoroModelInstalled || vm.isWorking)
                }
            }

            HStack {
                Text("Speaking speed")
                Slider(value: $vm.kokoroSpeed, in: 0.75...1.25, step: 0.05)
                Text("\(vm.kokoroSpeed.formatted(.number.precision(.fractionLength(2))))×")
                    .monospacedDigit()
                    .frame(width: 46, alignment: .trailing)
            }

        }
    }
}
