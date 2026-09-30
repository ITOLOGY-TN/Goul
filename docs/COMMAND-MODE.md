# Command Mode, the cancel window, and AI cleanup

Added 2026-09-30. All three run on the Mac only; nothing leaves it.

## Command Mode

Select text in any app, hold **Right ⌘** (configurable in Settings → Command mode), say
what to do, release. The selection is replaced by the result. With nothing selected, the
instruction is a writing prompt and the result is inserted at the caret.

Examples that work well in French and English: "rends ça plus formel", "translate to
English", "make this a bulleted list", "écris une réponse pour dire que je serai en retard".

How it works, in order:
1. Key down: `TextInjector.captureTarget()` as for dictation, then
   `captureSelection(in:)` — Accessibility's selected-text attribute first; if the app
   doesn't expose it (terminals, Electron), a synthetic ⌘C with the pasteboard saved and
   restored around it. The selection itself survives, which is what lets the paste replace it.
2. The instruction is transcribed by the current speech engine, language detected as usual.
3. `CommandRewriter` asks Apple's on-device Foundation model to apply the instruction
   (12 s timeout, chatty answers rejected). No "invented words" guard here, unlike cleanup:
   rewriting is supposed to invent words.
4. The result goes through the same cancel window and `TextInjector.insert` as dictation.
   ⌘Z in the target app undoes it, like any paste.

Requires Apple Intelligence to be on. When it isn't, Settings says why and the key does nothing.

Trade-off to know: Right ⌘ is consumed while Command Mode is on, so Right ⌘ + key no longer
triggers that app's shortcut. Left ⌘ is untouched. Pick `fn` in Settings if that matters.

## Cancel window

After the final text is ready, the HUD shows it for 0.7 s with an `esc` tag before it is
inserted. Escape during that window discards it; nothing is typed and nothing is logged.
The delay is `DictationController.cancelWindow`. Test-mode recordings skip it.

## AI cleanup

When "Clean up fillers and punctuation" is on and Apple Intelligence is available,
`FoundationModelFormatter` cleans the transcript in the detected language (punctuation,
capitals, fillers, self-corrections such as "jeudi, non plutôt vendredi"). Measured warm
latency on this Mac: 0.4–1.4 s. It falls back to `RuleBasedFormatter` when it exceeds 4 s
or when its output adds words that weren't spoken — the guard that stops it from answering
a dictated question. French function words were added to the guard's stop list so
re-punctuated French isn't rejected for a moved "le" or "d'".

The rule-based pass also gained unambiguous spoken punctuation: `virgule`, `point
d'interrogation`, `point d'exclamation`, `deux points`, `point-virgule`, `nouvelle ligne`,
and `comma`, `question mark`, `exclamation mark`, `semicolon`. `point` and `period` are
deliberately not recognised: they are ordinary words far more often than punctuation.

## Not verified by hand yet

- Selection capture via ⌘C in Warp and other terminals.
- Command Mode on a multi-paragraph selection.
- The AI cleanup's rejection rate on real fast French.
