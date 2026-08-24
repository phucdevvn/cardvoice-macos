# CardVoice

Native macOS SwiftUI utility for this workflow:

**Corrected/self-written Cloze cards → CardVoice-ready `.apkg` → ElevenLabs full-sentence audio → `.apkg` with audio**

If direct Anki repackaging is ever inconvenient, CardVoice can instead export a deterministic ZIP containing the MP3 files plus a manifest, so the audio can be attached later without guessing which file belongs to which note.

## Current scope

- Import a CardVoice-ready `.apkg` containing `cardvoice.json`.
- Support up to **3 Cloze targets in one note** (`c1`, `c2`, `c3`).
- Generate **one full-sentence MP3 per note** with ElevenLabs.
- Put audio on the **back** of the Anki Cloze card.
- Preview generated audio or use the macOS English voice as a free local preview.
- Export a new `.apkg` with `[sound:...]` attached.
- Export an **Audio ZIP + manifest** fallback.
- Store API keys in **macOS Keychain**.
- Import multiple authorized API keys from a local `.env` file and select the active one manually.
- Read `ELEVENLABS_VOICE_ID`, `ELEVENLABS_MODEL_ID`, and `ELEVENLABS_OUTPUT_FORMAT` from the same `.env` file.
- Search ElevenLabs voices, check current-key usage, and override voice/model/output settings in the UI.

## `.env` import

Use **Settings → Import .env…**. A supported file can contain:

```dotenv
ELEVENLABS_API_KEY_1=
ELEVENLABS_API_KEY_2=
ELEVENLABS_VOICE_ID=
ELEVENLABS_MODEL_ID=eleven_v3
ELEVENLABS_OUTPUT_FORMAT=mp3_44100_128
```

The app reads the selected file once. API-key values are copied to macOS Keychain; CardVoice does **not** keep a plaintext copy of the `.env` file. Whitespace around values is trimmed, so `ELEVENLABS_VOICE_ID= abc123` is accepted.

Real `.env` files are ignored by git. `elevenlabs.env.example` contains empty placeholders only.

CardVoice does **not** automatically rotate keys to bypass provider/free-tier quotas. If a request fails because the selected key has no usable quota, choose another authorized key manually and resume; already-generated notes are skipped by **Generate Missing**.

## CardVoice-ready `.apkg`

A supported package contains normal Anki package files plus:

- `collection.anki2`
- `media`
- `cardvoice.json`

The manifest maps each Anki note GUID to its corrected sentence, target(s), and deterministic MP3 filename. Restricting direct modification to packages carrying this manifest avoids guessing field layouts in arbitrary Anki decks.

## ElevenLabs

CardVoice uses:

- `POST /v1/text-to-speech/{voice_id}`
- `GET /v2/voices`
- `GET /v1/user/subscription`

The model and output format are configurable and can be imported from `.env`. Voice settings currently use speed `1.0`, style `0`, speaker boost on, stability `0.5`, and similarity `0.75`.

## Build — Apple Silicon

Requirements:

- macOS 14+
- Apple Silicon
- Xcode Command Line Tools / Swift toolchain

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
```

The build script creates the `.icns` from `AppIcon-Source.jpg`, builds arm64 release, ad-hoc signs the app, and outputs:

- `dist/CardVoice.app`
- `dist/CardVoice-macOS-arm64.zip`

For distribution outside your own Mac, use a Developer ID certificate and notarization instead of ad-hoc signing.

## Security

Never commit a real ElevenLabs key. The repository ignores `.env`/`*.env`, and the app stores imported secrets in Keychain under the CardVoice service identifier.
