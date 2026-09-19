# My Mind

Local-first Mac app for saving links, images, excerpts, and PDFs into a searchable visual library.

Working title from the product blueprint was “Visual Library.” The shipping product name for this project is **My Mind**.

## What works in this vertical slice

- Paste or drop a link, image, PDF, or `.webloc`
- Import Netscape bookmark HTML with a preview before commit
- Kind-specific cards, gallery and list, optional shelves and tags
- Focused preview with editable title, note, kind, tags, and shelves
- Local SQLite + FTS5 search over saved fields only
- Honest retention states (`Bookmark`, `Image copied`, `PDF copied`, `Excerpt saved`)
- Export / restore of a versioned `.mymind` archive
- Safari web-extension sources and native handler that write the same store (needs Xcode packaging into an `.appex` for Safari to load)

## Build / package

```bash
swift test --filter 'LibraryCoreTests|PressureTests'
./scripts/make-alpha-dmg.sh
open dist/MyMind-1.0.0-alpha.9.dmg
```

Alpha notes: `dist/ALPHA-NOTES.md`

## Design gate

See `design-note.md`, `adi-011-score-sheet.md`, and `gate-receipts/`.

## Privacy posture

No account. No cloud library. Saving a public web link may still contact that site for metadata and a preview image unless you turn previews off in Settings. Private and loopback addresses are stored as bookmarks and are not fetched.
