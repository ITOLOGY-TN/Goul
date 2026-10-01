# Themes

Goul has a theme system with two kinds of theme:

- **Colour-only.** The built-in *Captain's logbook*: a palette and a display font, drawn
  with the classic rail-and-parchment layout. Needs no files.
- **Illustrated.** A generated asset pack in `Resources/Themes/<slug>/` (14 files plus
  `theme.json`, produced from `docs/THEME-ASSET-PROMPT.md`). Switches the main window to
  the scene layout: full-bleed background, sidebar art with the theme's logo, a 9-slice
  panel hosting every section, and the mascot in its own column on wide windows.

Pick one in Settings → Appearance → Theme. It applies immediately, everywhere: palette,
display font, HUD level-meter colour.

## How a pack is loaded

`ThemeManager` scans `Contents/Resources/Themes/*/` at launch. A folder is a theme only if
`theme.json` parses and all 12 PNGs exist; anything else is skipped and the reason logged
under `app.goul.dictation` / `app`. `make app` copies `Resources/Themes` into the bundle,
minus `reference.png` and `*-source.png`.

`theme.json` drives the palette (`GoulTheme.ocean`, `.paper`, `.ink`, `.muted`, `.gold`,
`.red`, `.inkOnChrome`, `.instrument` all read the active theme), the display font family
(`serif` → Baskerville, `sans`, `mono`, `rounded`), the 9-slice border thickness in source
pixels (`panelInsets`, rendered at `GoulTheme.Scene.frameBorder` points whatever the source
resolution), and the watermark opacity.

## The scene layout

`IllustratedScene` (`Sources/Goul/UI/IllustratedScene.swift`). Sizes live in
`GoulTheme.Scene`. The dictation page inside the panel: `logo-light`, divider, the red
record button (`record-idle` / `record-active`, an SF Symbol glyph on top; it runs the test
recording), the hold-to-speak line, divider, the non-interactive *Auto-detect · English /
Français* pill, the setup message, and the Captain's log card. Dictionary and Settings render
inside the same panel with a transparent background. Below 1180 pt of window width the
mascot column is dropped.

## Night Deck

First illustrated theme, generated 2026-09-30 from the mockup kept as
`Resources/Themes/night-deck/reference.png`. Two values were tuned against the artwork:
`panelInsets` 210 (the corner ropes and rings of the regenerated frame, so they never stretch) and `watermarkOpacity` 0.14. The frame was regenerated once: the first render had a massive wood frame; the second, prompted from the reference alone, matched it.

## Checking a theme without launching the app

```bash
make app
GOUL_THEME_SNAPSHOT=night-deck /private/tmp/goul-build/Goul.app/Contents/MacOS/Goul
open /tmp/goul-theme-night-deck.png
```

Renders the main window at 1280×820 with that theme, at 2×, and quits. It's how every
number in `GoulTheme.Scene` was set. Run it with the fresh build: an older binary ignores the
variable and simply starts the app.
