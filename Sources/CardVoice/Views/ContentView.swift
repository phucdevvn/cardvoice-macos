import SwiftUI

struct ContentView: View {
    @StateObject private var vm = AppViewModel()
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CardVoice").font(.title2.bold())
                    Text("Anki → ElevenLabs → Anki with audio").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Import Anki…") { vm.importAPKG() }.keyboardShortcut("o", modifiers: .command)
                Button("Generate Missing") { Task { await vm.generateMissingAudio() } }.disabled(vm.isWorking || vm.package == nil)
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
                    description: Text("Use the .apkg exported for CardVoice. The app reads its cardvoice.json manifest and generates one full-sentence MP3 per note.")
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
                                    isWorking: vm.isWorking,
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
                if let p = vm.selectedProfile { Text(p.label).font(.caption).foregroundStyle(.secondary) }
            }.padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(minWidth: 920, minHeight: 680)
        .sheet(isPresented: $showingSettings) { SettingsView(vm: vm) }
    }
}
