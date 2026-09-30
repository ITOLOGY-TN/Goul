# Automatic English / French detection

Goul transcribes English and French without a language setting. There is nothing to
choose in Settings and nothing to confirm in the HUD; the detected language is shown as
an `EN` / `FR` badge and recorded in the log, and that is all it does.

Everything below runs on the Mac. No audio, text or metadata leaves the machine.

## How each engine detects the language

| | Parakeet v3 | Apple Speech (default) |
|---|---|---|
| Model | NVIDIA Parakeet TDT 0.6B v3, CoreML via FluidAudio | macOS 26 `SpeechAnalyzer` / `SpeechTranscriber` |
| Multilingual | Yes — 25 European languages, no language parameter. It writes what it hears. | No — one locale per transcriber, no language ID API. |
| How Goul detects | `LanguageDetector` (Apple `NLLanguageRecognizer`, constrained to en/fr) classifies the final text. | `AutoLanguageAppleEngine` runs an `en-US` and an `fr-FR` transcriber on the same microphone stream. `LanguageDetector.choose` picks the transcript that reads as its own engine's language, weighted by the engine's per-token confidence. |
| Live text | No (batch on release, as before). | Yes; the HUD shows the currently leading candidate. |
| Cost of detection | None beyond a text pass (< 1 ms). | Two recognisers while the key is held. |
| First run | One ~470 MB download (FluidAudio, Hugging Face). | Language packs via `AssetInventory`; both already installed on this Mac. |
| Offline afterwards | Yes — `AsrModels.downloadAndLoad` checks the on-disk models first. | Yes. |
| Mixed-language utterance | Transcribed as heard, in both languages; badge shows the dominant one. | Only the winning transcriber's text is kept, so the minority-language part comes out phonetically. |

Which is the default, and why it changed: Parakeet was the initial choice because detection
is free there. In real use on 2026-09-30, Parakeet v3 (int8 encoder) mis-heard several words
in fast French while Apple Speech handled the same speech well, so **Apple Speech is the
default**. Parakeet remains selectable. Untried levers if Parakeet is wanted later: the fp32
encoder, feeding dictionary phrases as keyword hints, or FluidAudio's Canary 1B model.

## What was measured

`Tools/language-probe.swift` runs both Apple transcribers over synthesised speech. On
macOS 26, 2026-09-30:

| Audio | en-US transcriber | fr-FR transcriber |
|---|---|---|
| English sentence | conf 0.99, correct | conf 0.86, code-switched into English |
| French sentence | conf 0.23, phonetic soup | conf 0.98, correct |
| French with anglicism | conf 0.37, soup | conf 1.00, correct |

The arbiter multiplies "does the text read as the engine's language" by the engine's
confidence, so all three cases resolve correctly, including the code-switch case where
text alone would tie.

Parakeet v3 was exercised on this Mac the same day: three French dictations, all detected
as FR (confidence 1.00), 11 s of audio transcribed in 0.24 s. Accuracy on fast French was
the weak point, not detection.

## What follows the detected language

- **Cleanup pass** (`RuleBasedFormatter`, opt-in): fillers and spoken punctuation come
  from `LanguageRules` — `um` / `new line` in English, `euh` / `à la ligne` in French.
- **History**: each run stores `language` (`EN`/`FR`). Older runs decode with it absent.
- **UI**: badge in the recorder, the log entry and the HUD.

The dictionary, text insertion and push-to-talk are untouched by language.

## Tests

`Tests/GoulCoreTests/LanguageDetectionTests.swift` — English, French, French without
accents, ligatures, decomposed (NFD) accents as macOS returns them, English with French
loanwords, texts too short to classify, mixed utterances, consecutive language switches,
and the arbiter with and without engine confidence.

```bash
swift test --scratch-path /private/tmp/goul-build/scratch --filter LanguageDetectionTests
```

## Known limits

- **Text-based**, not acoustic. A very short utterance (under three letters, or "ok" /
  "oui") returns no language; the badge stays empty and cleanup defaults to English.
- **Two languages only.** Parakeet will happily transcribe Spanish or German, but the
  badge will show whichever of EN/FR the recogniser finds closer.
- **Apple mode doubles recogniser load** and keeps only one transcript, so a sentence that
  switches language mid-way loses the minority part. Parakeet handles that case better.
- **Parakeet has no live text.** Unchanged from before.
- **Parakeet v3 int8 mis-hears fast French** more than Apple does; see above for levers.
