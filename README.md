# Cardfile

Local-first Mac visual library for links, images, excerpts, and PDFs.

Formerly developed as “My Mind.” Rebranded to avoid collision with [mymind.com](https://mymind.com). Same product: your library stays on your Mac, with honest retention labels for what was actually kept.

Public alpha **1.0.0-alpha.11**. Proprietary evaluation license — see [`LICENSE`](LICENSE). Not App Store, not notarized: first launch is right-click → Open.

## Install

Download the DMG from the [latest GitHub release](https://github.com/P0GL0L/my-mind/releases/latest), drag **Cardfile** into Applications, then right-click → Open.

- Paste a link into the capture bar, or use Safari / Share / Services / Dock / Shortcuts / Chrome / the menu bar icon
- Search with Command-F
- Layout switcher: Cards, Rows & Columns, Covers
- Gear → Settings (Appearance, Capture, library export/restore)

## Build from source

```bash
swift test --filter 'LibraryCoreTests|PressureTests'
./scripts/make-alpha-dmg.sh
open dist/Cardfile-$(cat VERSION).dmg
```

Version is the single line in `VERSION`. Packaging stamps every nested bundle before signing.

Alpha notes land in `dist/ALPHA-NOTES.md` after a DMG build.

Chrome extension (developer-mode load):

```bash
./scripts/make-chrome-extension.sh
```

## Privacy

No account. No cloud library. Saving a public web link may still contact that site for metadata and a preview image unless you turn previews off in Settings. Private and loopback addresses are stored as bookmarks and are not fetched.

## Design gate

See `design-note.md`, `adi-011-score-sheet.md`, and `gate-receipts/`.
