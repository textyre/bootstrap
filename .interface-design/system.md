# ctOS Greeter — Design System

## Direction

Monochrome operations terminal. Cold surveillance infrastructure aesthetic inspired by Watch Dogs ctOS (Blume Corporation). The machine doesn't welcome — it verifies. Elements float on void like a HUD. The screen IS the terminal.

## Intent

Operator at a restricted surveillance terminal. Authenticate and enter. The machine was running before you arrived. You're interfacing with infrastructure.

## Palette

```css
--void:        #000000                   /* CRT off — true black */
--phosphor:    #e8e6e3                   /* aged CRT phosphor — not pure white */
--phosphor-hi: #ffffff                   /* bright elements — clock, active input */
--ghost:       rgba(255, 255, 255, 0.06) /* scan-line traces, grid */
--grid:        rgba(255, 255, 255, 0.03) /* background grid infrastructure */
--ink:         rgba(255, 255, 255, 0.12) /* borders, separators */
--muted:       rgba(255, 255, 255, 0.4)  /* secondary text, labels */
--fail:        #ff3b30                   /* auth failure — the ONLY color */
```

Strictly monochrome. Color absence is the design. The single red is a system alert — jarring against the void.

## Depth

No shadows. No elevation. Borders only (thin, rgba at `--ink` opacity). Surveillance terminals don't have depth. Everything is flat on the glass.

## Surfaces

Single surface — void black. No cards, no containers, no panels. The screen IS the terminal. Elements float on the void like HUD data.

## Typography

JetBrains Mono — monospace mandatory for terminal aesthetic. Bundled via `@fontsource/jetbrains-mono` (greeter can't access system fonts). Weights: 300 (clock, thin labels), 400 (body), 700 (OS in logo, buttons).

## Spacing

8px base unit: 4px (micro) / 8px / 16px / 24px / 32px / 48px

## Border

`1px solid var(--ink)` — visible if you look, invisible if you don't.

## Signature

Typewriter terminal log — lines of system initialization appearing character-by-character with randomized hex addresses and UUIDs. The heartbeat of the interface.

## Key Patterns

- **HUD layout**: CSS Grid with 4 corners + center. No containers.
- **Machine vocabulary**: `PROFIL:`, `ENV:`, `NODE:`, `>>` — not human-friendly labels
- **Scan-lines**: `repeating-linear-gradient` overlay, barely visible
- **Grid**: 80px interval lines at `--grid` opacity
- **Barcodes**: JsBarcode CODE128, white on transparent
- **3D cube**: Pure CSS transforms, slow 12s rotation, one bright face
- **Auth feedback**: Red flash on failure, hard cut — no friendly animations

## Component Files

- `greeter/styles/_variables.css` — all tokens
- `greeter/styles/_layout.css` — HUD grid
- `greeter/styles/_grid-overlay.css` — scan-lines + grid + background blur
- `greeter/styles/_cube.css` — 3D rotating cube
- `greeter/styles/_form.css` — ctOS logo, login form, license
- `greeter/styles/_typewriter.css` — terminal log + version line
- `greeter/styles/_barcode.css` — username barcode, security sig, env block, clock
