# ctOS Greeter — Design Notes

## Reference

Screenshot: Watch Dogs ctOS login screen (Blume Corporation).

## Visual Elements

### Top-left
- **3D cube logo** (rotating/static diamond with white face)
- **Clock** — `00:09`, large monospace
- **Date** — `Wednesday 11 February` in a thin border box

### Top-right
- **Info block** in a border:
  - `ENV: Workstation`
  - `NODE: 109.389.013.301`

### Center
- **ctOS logo** — "ct" thin font, "OS" bold, white rectangle block to the left
- **Username label** — `PROFIL: TOMTOM`
- **Password input field**
- **LOGIN button** — right-aligned below the input

### Below form
- Blume icon (gear/shield) + text: *"Property of Blume Corp. All usage is subject to Sentinel Active Monitoring."*

### Bottom — terminal log
Monospace text, lines prefixed with `>>`:
```
>> REGION_LINK_ESTABLISHED : AU-SOUTH-EAST-2
>> LOG_STREAM_CONNECTED // 1B7C5296-469D-459S-AD5D-4E31349CF13F
>> WL_OUTPUT_FOUND: DP-3 <-> ADDR_PTR: 0xF3ED68D1
---------- GREETER_UI_INITIALIZING ----------
>> * [BLUME_IDP] Using Protocol::TEST
>> [SENTINEL ] CIPHER_NEGOTIATED <-> bnet://0x8D2A4F1B:1443
>> [BLUME_IDP] Opened session for user(tomtom)
```
Status line at bottom: `blume-krn-1.0.8 <> ctOS-1.0.0-a`

### Right edge
- **Vertical barcode/QR** — decorative, with small text (UUID, coordinates like `SYD-AU-NSW-02`)

### Overall style
- **Background** — black with subtle noise/grid (scanlines or dot matrix)
- **Palette** — strictly monochrome: white text on black
- **Fonts** — monospace, terminal aesthetic
- **Atmosphere** — corporate surveillance system, cyberpunk

## Technology Decision

### Chosen: LightDM + web-greeter

A web-greeter theme (HTML/CSS/JS) running on LightDM. The greeter is essentially a single-page app that calls `lightdm.authenticate()` / `lightdm.login()` via the JavaScript API.

### Why web-greeter over alternatives

| | SDDM + QML | LightDM + Web |
|---|---|---|
| Language | QML (niche) | HTML/CSS/JS |
| Animations | yes | yes |
| Scanlines, noise | hard | CSS filters, trivial |
| Terminal log | possible | easier (DOM manipulation) |
| Barcode | Canvas drawing | JS library or SVG |
| Debugging | weak | Browser DevTools |

### Why NOT ewwii
- Greeter runs **before** user session — ewwii is not available
- No PAM integration
- Would require hacky system-level setup

### Packages (Arch Linux)
- `lightdm` — official repos
- `web-greeter` or `nody-greeter` — AUR
- Theme is a folder with HTML/CSS/JS + `index.theme` metadata

## Implementation Notes (TODO)

- [ ] Install lightdm + web-greeter on remote VM
- [ ] Scaffold theme directory structure
- [ ] Implement HTML/CSS layout matching reference
- [ ] Add terminal log animation (typewriter effect)
- [ ] Add scanline/noise CSS overlay
- [ ] Wire up lightdm JS API for authentication
- [ ] Add 3D cube logo (CSS 3D transforms or SVG animation)
- [ ] Generate decorative barcode (SVG)
- [ ] Test on VM
