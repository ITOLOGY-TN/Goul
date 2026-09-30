# Goul

Push-to-talk dictation for macOS, entirely on-device. Hold a key, talk, release: clean text
lands in whatever text field has focus. English and French are detected automatically.
Select text and hold a second key to rewrite it by voice. Nothing ever leaves the Mac.

A personal project by Ahmed Bengarali, with a One Piece crew on board.

---

## What it does

- **Dictation.** Hold Right ⌥ (configurable), speak, release. The text is pasted at the caret
  of the app you were in. Escape cancels, including during a short 0.7 s review moment
  after release.
- **English / French, no setting.** Every utterance is transcribed in the language you spoke.
  Apple Speech runs an English and a French recogniser side by side and keeps the one that
  reads right; Parakeet v3 is natively multilingual. The pill and the log show `EN` / `FR`.
- **Command Mode.** Select text anywhere, hold Right ⌘, say *« rends ça plus formel »* or
  *"translate to English"*, release. The selection is replaced. With nothing selected, the
  instruction is a writing prompt. Runs on Apple Intelligence, locally.
- **Cleanup.** Optional: Apple Intelligence fixes punctuation, capitals, fillers and spoken
  self-corrections in the detected language, with a rule-based fallback. Spoken punctuation
  (*virgule*, *point d'interrogation*, *comma*, *new line*…) is understood.
- **Personal dictionary.** Names and jargon the engines keep missing, applied on every
  transcript and fed to Apple's recogniser as hints. The correction behaviour is a shared,
  tested contract (`shared/dictionary-test-vectors.json`).
- **A floating pill, not a window.** A small Wispr-Flow-sized capsule above the Dock with a
  gold waveform while you speak and Brook sitting on its right end. Solid colour, tinted
  Liquid Glass or native glass, your colour, optional live text: all in Settings.
- **History.** Off by default. When on, the Captain's log keeps transcripts on this Mac only.

## Privacy

Audio is processed in memory and never written to disk. Speech models, language detection
and the Apple Intelligence passes run on the Mac. There is no account, no analytics and no
network traffic after the one-time model downloads. See Settings → Privacy & data.

---

## Requirements

- macOS 26 (Tahoe) on Apple silicon.
- Xcode 26 command line tools (Swift 6.2) to build.
- Apple Intelligence enabled, for cleanup and Command Mode (dictation works without it).

## Quick start

```bash
make install     # builds, bundles, signs, copies to /Applications, launches
```

Then grant two permissions. Neither is optional and neither can be requested silently:

| Permission | Where | Needed for |
|---|---|---|
| **Accessibility** | System Settings ▸ Privacy & Security ▸ Accessibility | The event tap that sees the hotkey, and the paste |
| **Microphone** | Prompted on first dictation | Audio capture |

Then hold **Right ⌥** and talk. Settings → Speech → *Prepare* downloads the speech assets
ahead of time (Apple language packs, or ~470 MB for Parakeet v3).

### Signing and permissions

TCC keys the Accessibility grant to the app's code signature. The `Makefile` signs with a
Developer ID if one is present, otherwise with an Apple Development identity, otherwise
ad-hoc. Only the ad-hoc case changes on every build and resets the grant. If a grant ever
looks on but doesn't work, reset that one row and re-add it:

```bash
tccutil reset Accessibility app.goul.dictation
```

Never run a bare `tccutil reset Accessibility`: it wipes every app on the machine.

---

## Speech engines

| | Apple Speech (default) | Parakeet v3 |
|---|---|---|
| Model | macOS 26 `SpeechAnalyzer` | NVIDIA Parakeet TDT 0.6B v3 via FluidAudio (CoreML) |
| Download | OS-managed language packs | ~470 MB once |
| Live text | Yes | No, one pass on release |
| Language detection | Two locked recognisers arbitrated by text + confidence | Native multilingual; language read off the text |
| Observed | Better on fast French | Very fast (~50× realtime), weaker on fast French |

Details and measurements: `docs/LANGUAGE-DETECTION.md`.

---

## Architecture

```
 hold key ─► HotkeyMonitor ──► DictationController ◄── Settings
                                │
                     ┌──────────┼──────────┐
                     ▼          ▼          ▼
              AudioCapture  HUDPanel   TranscriptionEngine
                     │                  (Apple auto-language | Parakeet)
                (AudioChunk)                │
                                       (transcript + language)
                                            ▼
                         TextFormatter (rules | Apple Intelligence)
                         CommandRewriter (Command Mode)
                                            ▼
                                   DictionaryCorrector
                                            ▼
                                      TextInjector ─► focused app
```

**Decisions worth knowing**

- **The HUD never takes focus.** `HUDPanel` is a `.nonactivatingPanel` with
  `canBecomeKey == false`. If the overlay took key status, the user's text field would lose
  focus and there would be nothing to paste into.
- **The hotkey is a `CGEventTap`.** `fn` and left/right modifier discrimination don't surface
  through `NSEvent`. That is why Accessibility is a hard requirement.
- **Modifier state is read from the HID system state**, not the session state: the
  injector's own synthetic ⌘V used to leave ⌘ "held" in the session state and silently
  drop every second dictation.
- **Language detection lives in `GoulCore`** and is unit-tested (English, French, missing
  accents, decomposed strings, loanwords, mixed utterances, arbitration).
- **No literal values in views.** Every colour, size and duration is a token in
  `GoulTheme` / `DesignSystem`.

### Layout

```
Sources/
├── Goul/                       the app
│   ├── Core/                   DictationController, HotkeyMonitor, AudioCapture, TextInjector
│   ├── Transcription/          TranscriptionEngine, AppleSpeechEngine, AutoLanguageAppleEngine, ParakeetEngine
│   ├── Formatting/             TextFormatter, FoundationModelFormatter, CommandRewriter
│   ├── Dictionary/             DictionaryStore
│   ├── UI/                     MainWindow, SettingsWindow, ShortcutRecorder, HUDPanel, HUDView, GoulTheme, DesignSystem
│   └── Support/                Settings, Permissions, RunLog, Log
├── GoulCore/                   pure logic: SpokenLanguage, LanguageDetector, LanguageRules, SessionGate
└── MurmurDictionary/           the dictionary engine, shared contract with the Windows port
Tests/                          GoulCoreTests, MurmurDictionaryTests (shared vectors)
shared/                         dictionary-test-vectors.json, the correction contract
Resources/                      icon, artwork, Brook, entitlements, Info.plist
docs/                           LANGUAGE-DETECTION, COMMAND-MODE, HUD, THEME-ASSET-PROMPT, PARAKEET-WINDOWS
Tools/                          language-probe.swift, makeicon.swift
windows/                        an earlier C# / Avalonia port of the dictation core (builds in CI, never run on hardware)
```

## Building and testing

```bash
make build        # Swift build, scratch path outside the (iCloud-synced) tree
make app          # + bundle and sign into /private/tmp/goul-build/Goul.app
make install      # + copy to /Applications and launch
swift test --scratch-path /private/tmp/goul-build/scratch
```

Always build with `make`: a bare `swift build` writes into the synced tree and hits
"input file was modified during the build".

Layout checks without a microphone:

```bash
GOUL_HUD_SNAPSHOT=/tmp/hud.png /private/tmp/goul-build/Goul.app/Contents/MacOS/Goul
GOUL_SETTINGS_SNAPSHOT=/tmp/settings.png /private/tmp/goul-build/Goul.app/Contents/MacOS/Goul
```

`AGENTS.md` lists the things that look like bugs and aren't. Read it before changing anything.

## Roadmap

- Themes: generated asset packs (`docs/THEME-ASSET-PROMPT.md`), a Night Deck theme first.
- Onboarding for the two permissions.
- Notarization for distribution.

## License

MIT. See `LICENSE`. Brook and the One Piece imagery are not covered by it.

## Credits

Apple `SpeechAnalyzer`, NaturalLanguage and Foundation Models; NVIDIA Parakeet TDT v3 through
[FluidAudio](https://github.com/FluidInference/FluidAudio). Brook belongs to Eiichiro Oda's
*One Piece*; the artwork here is fan-made for personal use.
