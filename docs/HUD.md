# The HUD

The floating pill shown while a key is held. Reworked 2026-09-30 to match the Wispr Flow
footprint after the first One Piece pass was judged too large: a 132×34 pt navy capsule
with an ocean-blue hairline, a gold **waveform** (17 bars mirrored about the centre line,
envelope driven by the mic level) while you speak, quiet dots and a spinner while Goul
works, and a small seated Brook (64 pt) on its right end with his legs in front of it.

**No text by default.** Settings → "Show live text in the floating pill" widens the pill
to 380 pt and shows the tail of the sentence (Apple Speech streams it; Parakeet only has
text on release). Errors always show, in red. The `esc` tag appears during the 0.7 s
cancel window; the language tag only appears alongside live text.

## Files

- `Sources/Goul/UI/HUDView.swift` — `HUDModel` (plain values), `HUDView` (binds the
  controller and the live-text setting), `HUDContent` (drawing), `LevelBars`, `IdleDots`,
  `Spinner`, `BrookMascot`.
- `Sources/Goul/UI/GoulTheme.swift` → `GoulTheme.HUD` — every size, colour and timing.
  Views contain no literal values; change the tokens.
- `Sources/Goul/UI/HUDPanel.swift` — the `NSPanel`, sized from the tokens.
- `Resources/BrookSeated.png` — 155×240, generated 2026-09-30 for this pose (seated on
  a ledge, leaning left, singing), cropped to its opaque bounds and pre-downsampled with
  high-quality interpolation. `Resources/BrookSeated-source.png` is the 1024×1536
  original, kept for re-cropping and not copied into the bundle. To swap the figure:
  keep a transparent background, regenerate the small file the same way, and update
  `GoulTheme.HUD.mascotAspect` (width/height) and `mascotSeat` (fraction of his height
  above the pill's edge, i.e. where his hips are).

## Geometry

The panel window is wider and taller than the pill: room for the wide state, the shadow,
and the 55 % of Brook that rises above the edge. He is drawn in front of the pill so his
legs dangle over it; 25 % of his width hangs past the right end. `mascotClearance` keeps
the waveform clear of his legs.

## Focus and input

Unchanged and load-bearing: `.nonactivatingPanel`, `canBecomeKey == false`,
`ignoresMouseEvents = true`. The user's text field keeps focus, which is what lets
`TextInjector` paste into it. Brook is `allowsHitTesting(false)` as well.

## Settings that drive the pill

Settings → Appearance: style (Solid colour, the default; Tinted Liquid Glass with a
strength slider; Native Liquid Glass), colour, ocean-blue outline, Brook on/off, live
text. Stored in `UserDefaults` by `Settings`; `HUDModel` reads them on every draw, so a
change applies to the next dictation without a relaunch.

## Checking the layout without a microphone

```bash
make app
GOUL_HUD_SNAPSHOT=/tmp/hud.png /private/tmp/goul-build/Goul.app/Contents/MacOS/Goul
open /tmp/hud.listening.png   # also .working, .reviewing, .livetext
```

The app renders `HUDContent` for four fixed states at 2× and quits. Every geometry change
above was made against these renders. Note that `ImageRenderer` cannot draw Liquid Glass
(no backdrop), so glass styles look empty in snapshots; judge those live.

`GOUL_SETTINGS_SNAPSHOT=/tmp/settings.png` does the same for each settings section
(`.shortcuts`, `.speech`, `.appearance`, `.privacydata`, `.permissions`, `.about`). It shows
the structure — rail, titles, groups — but not AppKit-backed controls (toggles, pickers,
sliders), which the renderer skips.
