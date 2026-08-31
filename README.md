# CardVoice

Native Apple Silicon macOS utility for this workflow:

**Corrected/self-written Cloze cards → CardVoice-ready `.apkg` → offline Kokoro full-sentence audio → `.apkg` with audio**

Speech generation runs locally on the Mac. No account, cloud speech service, secret, subscription, or per-card fee is required.

## Current scope

- Import a CardVoice-ready `.apkg` containing `cardvoice.json`.
- Support any number of notes and up to **3 Cloze targets in one note**.
- Generate **one full-sentence WAV per note** with the local Kokoro model.
- Generate only missing audio, regenerate one note, or regenerate every audio file in one confirmed batch.
- Recover safely when a manifest omits an audio filename by deriving a deterministic filename from `CardVoiceID`.
- Put audio on the **back** of the Anki Cloze card.
- Preview generated audio or use the built-in macOS voice as a quick fallback preview.
- Export a new `.apkg` with `[sound:...]` attached.
- Export an **Audio ZIP + manifest** fallback.

## First use

1. Open Settings and choose **Install Offline Voice**. CardVoice downloads the English Kokoro model once (about 305 MB; about 340 MB installed).
2. Choose one of the included American or British voices and optionally adjust speaking speed.
3. Import a CardVoice-ready `.apkg`.
4. Choose **Generate Missing**.
5. Export the Anki deck with audio.

After the model is installed, generation does not need internet access. The model is stored under the current user's Application Support folder and is shared across imported decks.

Use **Regenerate All** when you intentionally want to replace every cached audio file after changing the voice or speed. You do not need to delete or reimport the Anki package first.

## Simplified Anki layout

The current sample imports as one flat deck named **English Sentences**. Its note type exposes only three learner-facing fields:

- `Sentence` — corrected self-written text with one or more `c1` targets.
- `Notes` — pattern and Vietnamese meaning combined, one target per line.
- `Audio` — full-sentence offline audio on the back.

`CardVoiceID` remains internal to `cardvoice.json`; it is not shown as an editable Anki field. Pattern and meaning remain separate inside the manifest for reliable content preparation, while CardVoice combines them for the app and exported Anki note.

## CardVoice-ready `.apkg`

A supported package contains normal Anki package files plus:

- `collection.anki2`
- `media`
- `cardvoice.json`

The manifest maps each Anki note GUID to its corrected sentence, target(s), and deterministic audio filename. Restricting direct modification to packages carrying this manifest avoids guessing field layouts in arbitrary Anki decks.

## Offline speech engine

CardVoice embeds the native Swift package from [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) and installs the English `kokoro-en-v0_19` model on demand. The app verifies the downloaded archive's SHA-256 checksum before installing it.

The app includes 11 selectable voices. Sentence generation uses a bounded number of CPU threads and creates standard PCM WAV files supported by Anki. WAV avoids relying on a system MP3 encoder or an additional conversion tool.

## Build — Apple Silicon

Requirements:

- macOS 14+
- Apple Silicon
- Xcode Command Line Tools / Swift toolchain
- Internet access during the first build so Swift Package Manager can fetch `sherpa-onnx`

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
```

The build script creates the `.icns` from `AppIcon-Source.jpg`, builds an arm64 release, ad-hoc signs the app, and outputs:

- `dist/CardVoice.app`
- `dist/CardVoice-macOS-arm64.zip`

For distribution outside your own Mac, use a Developer ID certificate and notarization instead of ad-hoc signing.

## Privacy and storage

Card text is processed locally. CardVoice does not ask for or store speech-service credentials. Generated WAV files remain in CardVoice's Application Support audio folder so they can be reused and exported.
