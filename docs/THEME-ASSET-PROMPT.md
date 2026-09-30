# Générer un thème Goul : prompt réutilisable

Copiez le bloc **PROMPT** ci-dessous dans Codex (ou tout générateur d'images), remplacez
les trois champs entre `{{ }}`, joignez une image de référence si vous en avez une, et
demandez la génération de **tous** les fichiers listés. Déposez le résultat dans
`Resources/Themes/{{slug}}/`. Goul découvre le dossier au lancement ; rien d'autre à faire.

Champs à remplir :

| Champ | Exemple | Règle |
|---|---|---|
| `{{theme_name}}` | `Night Deck`, `Jujutsu Kaisen`, `Garage GT` | Nom affiché dans Réglages |
| `{{slug}}` | `night-deck`, `jujutsu-kaisen`, `garage-gt` | minuscules, tirets, pas d'espace : c'est le nom du dossier |
| `{{universe}}` | *« le pont d'un navire pirate de nuit, style One Piece, aquarelle et encre, lanternes chaudes, mer bleu profond »* | Deux ou trois phrases : univers, style graphique, ambiance lumineuse, palette dominante, un personnage mascotte si le thème en a un |

Le reste du prompt ne change **jamais**. Il décrit des rôles (fond, panneau, barre latérale,
mascotte, bouton…) et non des objets : c'est le générateur qui traduit chaque rôle dans
l'univers demandé.

---

## PROMPT

```
REFERENCE IMAGE — READ FIRST
If an image is attached, it is the approved design of this theme, not an inspiration.
Every file you produce must look like it was cut out of that exact image: same palette,
same lighting, same rendering technique, same line weight, same level of detail, same
character design, same materials and lettering. Do not restyle, modernise, simplify or
reinterpret. Where a file asks for an element that appears in the reference, reproduce
that element from the reference. Only invent what the reference does not show, and keep
it in the same style. When in doubt, copy the reference.
If no image is attached, follow the art direction below strictly and keep every file
consistent with the first one you produce.

You are producing the complete asset pack for a theme of "Goul", a macOS dictation app.
Theme name: {{theme_name}}
Folder slug: {{slug}}
Universe and art direction: {{universe}}

Produce EVERY file below, with these exact file names, sizes and backgrounds. All PNG.
"transparent" means a real alpha channel, no halo, no drop shadow, no baked background.
No text anywhere except in the two logo files. Consistent lighting direction across all
files. The app draws its own text, icons and controls on top, so leave room and keep
surfaces calm where indicated.

STRUCTURE
1. background.png — 3840 x 2400, opaque.
   The full scene of the universe, seen as the backdrop of the app window. The centre-left
   two thirds must be calm, low-contrast and darker than the rest: a large panel will sit
   there. Rich detail may live on the right third and along the bottom edge.
2. panel-frame.png — 2048 x 2048, transparent outside the panel.
   The main content panel of the universe (a parchment, a screen, a plaque, a card, a
   chassis panel… whatever the universe suggests). Its border/frame must be of UNIFORM
   thickness, about 160 px on all four sides, and the interior must be a flat, uniform
   surface with no drawing: the app stretches this image as a 9-slice and writes on it.
   Interior surface must give good contrast to dark text.
3. sidebar.png — 800 x 2400, opaque.
   A vertical navigation column in the universe's darker tone with very subtle decorative
   line work (max 15 % contrast). No logo, no text, no focal object; it is a background.

CHARACTER AND LOGO
4. mascot.png — 1024 x 1536, transparent.
   The theme's mascot (a character, creature, vehicle or object of the universe), full
   figure, seated or standing at rest, facing slightly LEFT, lit from the right. It will be
   shown on the right side of the window at about one third of the window height.
5. logo-dark.png — 1024 x 512, transparent.
   The word "GOUL" in a lettering style of the universe, in a light colour for use on dark
   surfaces, with one small emblem of the universe above or beside it.
6. logo-light.png — 1024 x 512, transparent.
   The same logo in a dark ink colour for use on the light panel surface.

BUTTON AND ORNAMENTS
7. record-idle.png — 512 x 512, transparent.
   A round push button of the universe, RED dominant (red means recording in this app),
   with a rim or bezel. NO icon on it; the app overlays a microphone glyph.
8. record-active.png — 512 x 512, transparent.
   The same button lit up / pressed, with a soft red glow: the recording state.
9. ornament-divider.png — 1024 x 96, transparent.
   A horizontal decorative rule of the universe, single dark tone, thin.
10. watermark-1.png, watermark-2.png, watermark-3.png — 1024 x 1024 each, transparent.
    Three emblems of the universe drawn as single-tone line art (no fill, no colour), for
    use as faint watermarks on the panel. The app sets their opacity.

MANIFEST
11. theme.json — a text file with this exact shape, values chosen from the artwork:
{
  "name": "{{theme_name}}",
  "colors": {
    "chrome":        "#RRGGBB",   // sidebar / dark surfaces
    "panel":         "#RRGGBB",   // the panel interior surface
    "ink":           "#RRGGBB",   // text on the panel
    "inkMuted":      "#RRGGBB",   // secondary text on the panel
    "inkOnChrome":   "#RRGGBB",   // text on the sidebar
    "accent":        "#RRGGBB",   // highlights, selected item, hairlines
    "record":        "#RRGGBB",   // the red of the record button
    "instrument":    "#RRGGBB"    // level meter / waveform colour
  },
  "font": { "display": "serif" | "sans" | "mono" | "rounded" },
  "panelInsets": 160,             // border thickness of panel-frame.png in px
  "watermarkOpacity": 0.08
}

DELIVERY
Return the 14 files named exactly as above, nothing else, ready to drop into a folder
named "{{slug}}".
```

---

## Ce que Goul fait de chaque fichier

| Fichier | Usage dans l'app |
|---|---|
| `background.png` | Fond de la fenêtre principale, recadré au centre, jamais déformé |
| `panel-frame.png` | Panneau central en 9 tranches (`panelInsets`) : recorder, journal, réglages |
| `sidebar.png` | Fond de la colonne de navigation |
| `mascot.png` | À droite du panneau, hauteur ≈ 1/3 de la fenêtre ; masqué sous 900 pt de large |
| `logo-dark.png` / `logo-light.png` | Haut de la barre latérale / haut du panneau |
| `record-idle.png` / `record-active.png` | Bouton « Test microphone », glyphe micro SF Symbol par-dessus |
| `ornament-divider.png` | Séparateurs de sections |
| `watermark-*.png` | Filigranes du panneau, opacité `watermarkOpacity` |
| `theme.json` | Couleurs et police ; le HUD reprend `record` et `instrument` |

Un thème incomplet est ignoré au lancement et la raison est écrite dans le log
(`app.goul.dictation`, catégorie `app`) : fichier manquant, taille inattendue, JSON invalide.

## Vérifier un thème sans lancer de dictée

```bash
make app
GOUL_THEME_SNAPSHOT={{slug}} /private/tmp/goul-build/Goul.app/Contents/MacOS/Goul
open /tmp/goul-theme-{{slug}}.png
```

Rend la fenêtre principale avec le thème à 2× et quitte. (Disponible une fois le système de
thèmes livré ; voir `docs/THEMES.md`.)
