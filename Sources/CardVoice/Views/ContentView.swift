import SwiftUI

struct ContentView: View {
    @StateObject private var vm = AppViewModel()
    @State private var showingSettings = false
    @State private var showingRegenerateAllConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CardVoice").font(.title2.bold())
                    Text("Anki → Offline Kokoro → Anki with audio").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !vm.kokoroModelInstalled {
                    Button("Install Offline Voice") { Task { await vm.installKokoroModel() } }
                        .disabled(vm.isWorking)
                }
                Button("Import Anki…") { vm.importAPKG() }.keyboardShortcut("o", modifiers: .command)
                Button("Generate Missing") { Task { await vm.generateMissingAudio() } }
                    .disabled(vm.isWorking || vm.package == nil || !vm.kokoroModelInstalled)
                Button("Regenerate All") { showingRegenerateAllConfirmation = true }
                    .disabled(vm.isWorking || vm.notes.isEmpty || !vm.kokoroModelInstalled)
                    .help("Replace every generated audio file for the imported deck")
                Menu("Export") {
                    Button("Anki deck with audio…") { vm.exportAnkiWithAudio() }
                    Button("Audio ZIP only…") { vm.exportAudioZip() }
                }.disabled(vm.package == nil)
                Button { showingSettings = true } label: { Image(systemName: "gearshape") }
            }.padding(16)

            Divider()

            if vm.package == nil {
                ContentUnavailableView(
                    "Import your Anki deck",
                    systemImage: "rectangle.stack.badge.play",
                    description: Text("Install the offline voice once, then import a CardVoice-ready .apkg. CardVoice generates one full-sentence audio file per note entirely on this Mac.")
                )
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text(vm.package?.manifest.deckName ?? "").font(.headline)
                        Spacer()
                        ProgressView(value: Double(vm.completedCount), total: Double(max(vm.notes.count, 1))).frame(width: 180)
                        Text("\(vm.completedCount)/\(vm.notes.count) audio").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }.padding(.horizontal, 16).padding(.vertical, 10)
                    Divider()
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(vm.notes) { note in
                                NoteRow(
                                    note: note,
                                    hasAudio: vm.hasAudio(note),
                                    isWorking: vm.isWorking || !vm.kokoroModelInstalled,
                                    generate: { Task { _ = await vm.generateAudio(for: note) } },
                                    play: { vm.playAudio(note) },
                                    systemSpeak: { vm.systemSpeech.speak(note.sentence) }
                                )
                            }
                        }.padding(16)
                    }
                }
            }

            Divider()
            HStack {
                Text(vm.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Text("Kokoro offline · \(vm.selectedKokoroVoice.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(minWidth: 920, minHeight: 680)
        .sheet(isPresented: $showingSettings) { SettingsView(vm: vm) }
        .confirmationDialog(
            "Regenerate all audio?",
            isPresented: $showingRegenerateAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Regenerate All Audio", role: .destructive) {
                Task { await vm.regenerateAllAudio() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces all \(vm.notes.count) generated audio files locally using Kokoro. No API credits are used.")
        }
    }
}
