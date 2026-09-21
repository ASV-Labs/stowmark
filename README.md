# Stowmark

**Your visual library. On your Mac.**

Collect links, images, PDFs, and excerpts in one place. Browse visually, organize with shelves and tags, and find the useful things again. No account required.

A home for what you find.

Public alpha **1.0.0-alpha.13**. Proprietary evaluation license — see [`LICENSE`](LICENSE). Not App Store, not notarized: first launch is right-click → Open.

The library is local. Each item shows what was actually saved — a bookmark, a copied file, or an excerpt — so links are not advertised as full offline page archives.

## Install

Download [Stowmark-1.0.0-alpha.13.dmg](https://github.com/P0GL0L/my-mind/releases/download/v1.0.0-alpha.13/Stowmark-1.0.0-alpha.13.dmg) from the [v1.0.0-alpha.13 release](https://github.com/P0GL0L/my-mind/releases/tag/v1.0.0-alpha.13), drag **Stowmark** into Applications, then right-click → Open.

- Paste a link into the capture bar, or use Share / Services / Dock / Shortcuts / the menu bar (browser extensions are Coming soon)
- Search with Command-F (“Search your library”)
- Layout switcher: Cards, Rows & Columns, Covers
- Settings (⌘,) — General, Library, Capture, Help. Help → Stowmark Help (⇧⌘/) opens the in-app guide.

Export writes a **Stowmark Library** (`.stowmark`). Older `.cardfile` and `.mymind` archives still restore.

## Build from source

```bash
swift test --filter 'LibraryCoreTests|PressureTests'
./scripts/make-alpha-dmg.sh
open dist/Stowmark-$(cat VERSION).dmg
```

Version is the single line in `VERSION`. Packaging stamps every nested bundle before signing.

## Privacy

No account. No cloud library. Saving a public web link may still contact that site for metadata and a preview image unless you turn previews off in Settings. Private and loopback addresses are stored as bookmarks and are not fetched.

## Design gate

See `design-note.md`, `adi-011-score-sheet.md`, and `gate-receipts/`.
