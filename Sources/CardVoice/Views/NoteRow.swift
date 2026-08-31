import SwiftUI

struct NoteRow: View {
    let note: CardVoiceNote
    let voice: KokoroVoice
    let audioFilename: String
    let hasAudio: Bool
    let isWorking: Bool
    let generate: () -> Void
    let play: () -> Void
    let systemSpeak: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(note.targets.joined(separator: " · ")).font(.headline)
                Spacer()
                Text(voice.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(hasAudio ? "Ready" : "Missing", systemImage: hasAudio ? "checkmark.circle.fill" : "waveform.badge.exclamationmark")
                    .font(.caption).foregroundStyle(hasAudio ? .green : .secondary)
            }
            Text(note.sentence).font(.body).textSelection(.enabled)
            HStack(alignment: .top, spacing: 8) {
                Text("Notes:").font(.caption.bold())
                Text(note.combinedNotes).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(hasAudio ? "Regenerate" : "Generate Offline", action: generate).disabled(isWorking)
                Button("Play", action: play).disabled(!hasAudio)
                Button("macOS Preview", action: systemSpeak)
                Spacer()
                Text(audioFilename).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
