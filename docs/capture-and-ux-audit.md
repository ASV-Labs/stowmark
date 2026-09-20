# Stowmark — Capture, Browser Integration, and UX Audit

Date: 2026-09-19 · Basis: `cursor/visual-library-app` @ alpha.9 source, installed `/Applications/Stowmark.app` (bundle 9, appex registered), blueprint `Visual_Library_Product_Blueprint.docx` (concept reference only).

This file has two parts. **Part A** is the audit (what exists, what is partial, what is missing or broken). **Part B** is the builder guide: prioritized work items with files, steps, and acceptance tests. A builder agent should work Part B top to bottom, one item per PR, and update the status column as it goes.

---

## Part A — Audit

### A1. Capture entry points (how something gets into the library)

| Entry point | Status | Notes |
|---|---|---|
| Capture bar paste (URL) | Shipped | `LibraryShell.captureBar` → `LibraryModel.captureDraftLink`. Return saves. Draft is cleared before save; failure does not restore it. |
| Clipboard button / ⌘⇧V | Shipped | `captureFromClipboard` handles file URLs, web URLs, images, plain-text URLs. |
| Drop **files** on window | Shipped | `.dropDestination(for: URL.self)` → `importDropped` → `importFile`. JPEG/PNG/HEIC/PDF/webloc/bookmark-HTML only. |
| Drop **web link** on window | **Broken** | Same drop path treats an `https://` URL as a file: `importFile` runs `Data(contentsOf:)` synchronously (blocks UI, downloads HTML), then fails with "can copy JPEG, PNG, HEIC, and PDF". Dragging a link from Safari's address bar or a page therefore fails. `LibraryModel.importFile` L515. |
| Drop **image from a web page** | Missing | Browsers offer image data + source URL; only `URL.self` is accepted, so nothing lands. |
| Drop **text selection** | Missing | No `String` / rich-text drop → excerpt. |
| Drop on **Dock icon** | Missing | `CFBundleDocumentTypes` only declares `.mymind`; Finder won't allow dropping images/PDFs/URLs onto the icon. |
| Import bookmarks HTML | Shipped | Plan → sheet → commit, with shelves from folders. |
| Safari toolbar popup | Shipped (alpha.9) | Explicit Save Page / Save selection; pending → receipt polling; Undo; View in Library. |
| Safari context menus | Shipped | Page, selection, link, "Save image link" (bookmark of the image URL, not bytes). |
| Safari keyboard shortcut | Missing | No `commands` block in `extension-manifest.json`. |
| Safari toolbar badge/feedback | Missing | No `action.setBadgeText`; the only feedback is inside the popup. |
| `mymind://save?…` URL scheme | Shipped | `handleIncomingURL` accepts url/title/text/note/shelf/tags/requestId. Works from any browser via bookmarklet. |
| Bookmarklets | Dead code | `safariPageBookmarklet` / `safariExcerptBookmarklet` in `LibraryModel` are never shown in the UI. |
| Chrome / Arc / Edge / Brave / Firefox | Missing | Blueprint gates it. No extension, no native-messaging host, no loopback server. |
| macOS **Share** extension | Missing | Blueprint lists Share menu as a first-class entry. Would cover every browser plus Preview, Photos, Mail, Notes, Finder. |
| macOS **Services** menu | Missing | No `NSServices`. "Save to Stowmark" for selected text or URL in any app. |
| Global hotkey / quick-capture panel | Missing | No menu-bar extra, no hotkey, no frontmost-browser URL read. |
| Apple Shortcuts / App Intents | Missing | No `AppIntent`. Would give Spotlight, Shortcuts, and Siri capture cheaply. |
| Clipboard watcher (opt-in) | Missing | Copying a URL anywhere could surface a one-key "Save?" affordance. |
| CLI (`StowmarkTool save`) | Shipped | Dev/test only; hidden in `Contents/Helpers`. |

### A2. Browser integration — where we actually are

**Safari**
- The appex is embedded, signed, and registered (`pluginkit` lists `com.charlesbonetti.stowmark.extension 1.0.0`). `/Applications/Stowmark.app` is bundle 9 with the appex.
- Storage: app writes Application Support; a verified SQLite snapshot is replicated to the App Group container; the extension reads/writes the group copy only when fingerprints match. Diverged copies set a marker and the extension hands off via `mymind://` and returns `pending` until a receipt exists. This is honest but the **replica can lag** (only replicated at app launch), so a Safari save while the app is closed lands in the group copy and the app must re-sync on next launch. Verify `openLive` handles "group has newer items than support" — today it only copies support→group when group is empty, and group→support when support is missing. **A save made in Safari with the app closed may be stranded in the group container after the next app launch if support already has items.** This is the biggest remaining correctness risk in browser capture.
- Popup UX: fields for shelf/note/tags are always visible; no shelf picker (free text); no tag suggestions; no keyboard shortcut; no "auto-save on click" option; no image bytes.
- Not notarized (`spctl`: "Unnotarized Developer ID"). Users must right-click → Open.
- Extension version string is `1.0.0` while the app is `1.0.0 (9)`; keep them in step.

**Everything else (Chrome, Arc, Edge, Brave, Firefox, Orion)**
- Nothing. Copy/paste or a bookmarklet that nobody can find.
- Native messaging (Chrome's equivalent of Safari's handler) needs a host manifest written into `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`, which a sandboxed App Store app cannot write. Two viable transports:
  1. **URL scheme** — extension opens `mymind://save?…`. Zero server, sandbox-safe, App Store-safe. Downside: the extension cannot get a receipt back; the app must show the confirmation instead (toast + badge), and Chrome shows a one-time "Open Stowmark?" prompt.
  2. **Loopback HTTP** — app listens on `127.0.0.1:<random>` with a per-install token written to a file the extension user pastes once (or discovered via URL scheme handshake). Needs `com.apple.security.network.server` (App Store allowed). Gives real receipts. More code, more attack surface.
- Recommendation: ship (1) first behind a "Other browsers" section in Settings with install instructions and the bookmarklet as a fallback; evaluate (2) only if users demand in-extension confirmation.

**Universal, non-browser-specific paths that are cheaper than any second extension**
- macOS **Share extension** (Safari, Chrome, Arc, Firefox all populate the system Share menu with URL + title; Preview/Photos share images; Mail shares text). One appex covers every browser and most apps.
- **Services** menu for selected text/URLs.
- **Drag & drop** (fixed) — dragging a link or image from any browser onto the window or Dock icon.
- **App Intent** — "Save to Stowmark" in Shortcuts/Spotlight.

### A3. Library, storage, trust

| Area | Status | Notes |
|---|---|---|
| SQLite + FTS5, receipts, idempotent replay | Shipped | 16/16 unit tests; 10k-item pressure passes. |
| Pagination | Partial | `loadMore()` + "Show N more" button exists; no infinite scroll. |
| Replication safety | Shipped (alpha.9) | Refuses to overwrite a library with items; verified snapshot. See A2 lag risk. |
| Export / restore | Shipped | Replace requires confirmation. No automatic backup schedule or reminder. |
| Preview fetch off | Shipped (alpha.9) | Skips all network. Streaming size limit enforced. |
| Third-party descriptions labeled | Missing | DDG-derived descriptions are not marked as such in the card/preview. |
| Retention truth | Shipped | Bookmark / Image copied / PDF copied / Excerpt saved. |
| Supported formats | Narrow | JPEG, PNG, HEIC, PDF only. No GIF, WebP, SVG, TIFF, MOV/MP4, TXT/MD, EPUB. `FileSignature.sniff`. |
| Content kinds | Narrow | article, image, research, book, social, excerpt, document, link. No video, audio, product, recipe. |
| PDF thumbnail on capture | Missing | `Thumbnail.pdfCover` exists but `insertFile` never writes a preview asset, so PDFs render a placeholder. |
| Image cache | Missing | `NSImage(contentsOf:)` runs on every card render (`ItemCard.photo`, `CoverTile.coverImage`, `ItemPreview.object`). At 400 items this is hundreds of synchronous disk reads per layout pass → scroll jank. |
| Notarization | Missing | Gatekeeper rejects; alpha only. |
| Build system | Fragile | Hand-assembled bundle via zsh scripts; no Xcode project; appex embedding is scripted. |

### A4. UX / UI

**Shell & navigation**
- Sidebar is a fixed 232pt `HStack`, not `NavigationSplitView`; not collapsible (blueprint asks for collapsible). The independent ADI review cites `NavigationSplitView` — that is inaccurate; correct the review or the code.
- Shelves: create and delete only. No rename, reorder, nesting, or drag-to-shelf from a card.
- No tag browser (tags only reachable via card chips and preview).
- Search is a custom header field; ⌘F focuses it. No `.searchable`, no recent searches, no saved searches.
- Scope picker ("This shelf / Entire library") is now always visible. Good.
- No sort control in Cards/Covers (only Settings default sort). Table sorts via `String(describing: KeyPathComparator)` — fragile; replace with explicit column identifiers.
- Keyboard: ↑/↓ move selection linearly; no ←/→ in grids, no Home/End, no ⌘A, no multi-select, no ⌘C copy link, no ⌘↩ open original.

**Cards / Covers / Table**
- Uniform geometry landed. Preview zone letterboxes originals. Footer pinned. Trash icon bottom-right (no confirm by design).
- Hover reveals nothing; no quick actions (open original, favorite) without right-click.
- Covers: selected-state overlay is the only place title shows; fine, but no hover tooltip on unselected tiles.
- No "Undo" toast after card trash (Undo Last Save exists only for captures).

**Preview**
- 420pt right overlay; feels like an edit form. Title editing moved under "Edit details" (alpha.9). No ←/→ to move between items while open. No Quick Look for PDFs/images. No "Copy link". Note field saves on disappear only.

**Capture bar**
- Save button `minHeight 44` after alpha.9 but Clipboard button is text-only. No inline shelf/tag entry. Draft not restored on failure. No progress for enrichment ("Saving…" only covers the DB insert).

**Settings**
- General (layout, size, appearance, behaviour) and Library (Safari, previews, trash, export, diagnostics). No **Capture** tab for Share/Services/hotkey/clipboard-watcher/other browsers. Bookmarklets not surfaced.

**Accessibility**
- Labels and selected traits present. Gaps vs. design-note claims: several targets < 44pt (card trash 28pt, Clipboard, Add tag), no `AccessibilityNotification.Announcement` when result count changes or a save completes, table rows lack composite labels.

**Onboarding / first run**
- Empty state is good. No guided "turn on Safari" step beyond the Settings button; no detection of whether the extension is enabled.

### A5. Blueprint gaps still open (labels from the blueprint)

- Share menu capture (Agreed direction) — missing.
- Collapsible shelf sidebar (Agreed) — missing.
- Explicit support matrix published in-app (Proposed) — missing.
- Image bytes from browser (Validation gate) — missing; currently "Save image link".
- Chrome transport (Validation gate) — unresolved; recommendation above.
- Third-party metadata labeled (Trust) — missing.

---

## Part B — Builder guide

Rules for the builder agent:
1. One work item per branch/PR, named `cursor/<id>-<slug>`. Base `main`.
2. Do not change storage schema without a migration + test. Do not touch `LibraryReplica` semantics without adding a test that proves a non-empty destination is never overwritten.
3. Every item ships with its acceptance test executed and noted in the PR body. UI items include a screenshot.
4. Keep `App/Info.plist` `CFBundleVersion` and `SafariExtension/Info.plist` `CFBundleVersion` and `extension-manifest.json` `version` in step; bump per DMG.
5. Never say "Saved" before `LibraryStore.capture` (or a receipt) confirms.
6. Update the Status column here when done.

### Phase 0 — Correctness (do first)

#### C-01 Fix web-link and image drops onto the window
Status: done · Priority: P0 · Files: `Sources/Stowmark/LibraryShell.swift` (`.dropDestination`), `Sources/Stowmark/LibraryModel.swift` (`importDropped`, `importFile`)
- Replace `.dropDestination(for: URL.self)` with `.onDrop(of: [.fileURL, .url, .image, .png, .jpeg, .pdf, .plainText, .utf8PlainText, .html], isTargeted:)` using `NSItemProvider`, or add a `DropPayload: Transferable` enum with representations for `URL`, `Data` (image/PDF), and `String`.
- Routing: `isFileURL` → `importFile`; http(s) URL → `captureLink(origin: "drop")`; image data → `captureImageData(filename: "Dropped.png")` (convert to PNG via `NSBitmapImageRep`); PDF data → `runCapture(.pdf)`; string that parses as URL → `captureLink`; other non-empty string → `captureExcerpt(pageURL: <source URL if provided, else fail with "Drop text from a web page so the source is kept">)`.
- Guard: `importFile` must early-return with `captureLink` if `!url.isFileURL`. Never call `Data(contentsOf:)` on a remote URL on the main thread.
- Accept: drag a link from Safari's address bar → card appears with "Saved."; drag an image from a web page → "Image copied." card with fitted preview; drag a PDF from Finder → "PDF copied."; drop a paragraph of selected text from Safari → excerpt (or clear failure message). No UI freeze in any case.

#### C-02 Re-sync Safari saves made while the app was closed
Status: done · Priority: P0 · Files: `Sources/LibraryCore/LibraryStore.swift` (`openLive`), `Models.swift` (`LibraryReplica`), tests
- Today `openLive` only replicates support→group (group empty) or group→support (support missing). If both have items and fingerprints differ, the group copy is marked diverged and ignored — any Safari-only saves are stranded.
- Implement `LibraryReplica.mergeNewReceipts(from: group, into: support)`: read `capture_receipts` in the group DB whose `request_id` is absent in support; for each, re-run `capture` in support from the stored request fields (add a `capture_requests` table if the receipt lacks enough fields — store the original `CaptureRequest` JSON alongside the receipt going forward). Then re-replicate support→group so fingerprints match and clear the diverged marker.
- Accept (test): create support store with 1 item; create group store as a copy plus 1 extra Safari receipt; call `openLive` equivalent; support now has 2 items; group fingerprint == support fingerprint; no item lost; a third run is a no-op.

#### C-03 Restore the capture draft on failure and show enrichment progress
Status: partial (draft already stays on failure; cards now say “Fetching preview…”. Retry button still todo) · Priority: P1 · Files: `LibraryModel.runCapture`, `LibraryShell.captureBar`
- Keep the draft text until `result.status != .failed`. On failure show inline "Not saved — Retry" button that re-runs the same `requestID`.
- Show a subtle "Fetching preview…" state on the card (`previewState == .pending`) instead of the empty preview zone.
- Accept: paste `javascript:alert(1)` → draft remains, Retry visible; paste a valid link → card shows a pending shimmer/label until the preview arrives.

#### C-04 Image cache for card thumbnails
Status: todo · Priority: P1 · Files: new `Sources/Stowmark/ImageCache.swift`, `ItemViews.swift`
- `final class ImageCache { static let shared; NSCache<NSString, NSImage>; func image(for asset: AssetRecord, root: URL) async -> NSImage? }` keyed by `sha256`. Decode off-main via `Task.detached`, downsample to ≤ 2× the preview zone with `CGImageSourceCreateThumbnailAtIndex`.
- Replace `NSImage(contentsOf:)` in `ItemCard.photo`, `CoverTile.coverImage`, `ItemPreview.object` with an `AsyncThumbnail` view.
- Accept: `StowmarkTool seed 2000`, scroll Cards at Large size — no dropped frames in Instruments; memory stays bounded (NSCache limit ~150 MB).

#### C-05 Generate PDF cover on capture
Status: done · Priority: P2 · Files: `LibraryStore+Records.insertFile`, `Thumbnail.swift`
- After staging a PDF, call `Thumbnail.pdfCover(data)` and write a `preview` asset row (same pattern as `completeEnrichment`). Keep it synchronous only if < 200 ms; otherwise enqueue an `enrichment_jobs` row of type `pdf_cover`.
- Accept: drop a PDF → card shows first page in the preview zone; `documentPreview` placeholder only when generation fails.

### Phase 1 — Make saving easier than copy & paste

#### B-01 Safari: keyboard shortcut, badge, one-click mode, image bytes
Status: done · Priority: P0 · Files: `SafariExtension/Resources/extension-manifest.json`, `background.js`, `popup.js`, `SafariWebExtensionHandler.swift`, `SettingsView.swift`
- Manifest: add `"commands": { "save-page": { "suggested_key": { "default": "Ctrl+Shift+S", "mac": "Command+Shift+S" }, "description": "Save page to Stowmark" } }`. In `background.js`, `browser.commands.onCommand` → `native({action:"savePage",…})` then `browser.action.setBadgeText({text:"✓", tabId})` for 3 s (or "…" while pending, "!" on failure).
- Setting "Safari toolbar click saves immediately (no popup)": store in the group container as `settings` row; `background.js` reads via a `getSettings` native message on startup; when true, set `action.default_popup` to none via `browser.action.setPopup({popup:""})` and handle `browser.action.onClicked` → save + badge. Popup remains reachable via right-click → "Save with details…" context item.
- Image bytes: for `contexts:["image"]`, fetch `info.srcUrl` **in the extension** (`fetch(srcUrl)` inherits page cookies/referrer), base64 the bytes (cap `Limits.maxAttachmentBytes`), send `{action:"saveImage", bytes, filename, pageURL}`; handler decodes and builds a `CaptureRequest(.image, file:)`. Rename menu item to "Save image to Stowmark"; keep "Save image link" as a second item.
- Accept: ⌘⇧S on a page → badge ✓ and item in library with app closed (through pending → receipt); image context save → "Image copied." with original bytes; toggling one-click mode changes toolbar behaviour without reinstalling.

#### B-02 macOS Share extension
Status: todo · Priority: P0 · Files: new target `Sources/StowmarkShare/ShareViewController.swift`, `ShareExtension/Info.plist` (`com.apple.share-services`, `NSExtensionActivationRule` for `NSExtensionActivationSupportsWebURLWithMaxCount=1`, `…ImageWithMaxCount=10`, `…FileWithMaxCount=10`, `…Text=true`), `ShareExtension/StowmarkShare.entitlements` (App Group), `Package.swift` (new executableTarget with `-application-extension`), `scripts/assemble-share-appex.sh`, `make-alpha-dmg.sh`
- UI: compact SwiftUI sheet — title (editable), shelf picker (from group DB), tags, note, **Save** (default) / Cancel. Show retention line before saving ("Bookmark" / "Image will be copied").
- Save through `LibraryStore.openForExtension()`; if unavailable, hand off via `mymind://save` with `requestId` and show "Opening Stowmark to finish…" (never "Saved").
- Accept: Share from Safari, Chrome, Preview (image), Finder (PDF), and Notes (text) → correct kind and retention each time, with app closed; duplicate share → "Already in your library."

#### B-03 Services menu: "Save to Stowmark"
Status: done · Priority: P1 · Files: `App/Info.plist` (`NSServices`), `StowmarkApp.swift` (`NSApp.servicesProvider`), new `ServicesProvider.swift`
- Two services: text/URL selection → `saveSelection:userData:error:` (URL → link; other text → excerpt, source unknown → store as excerpt with `On this Mac` source and a "no source" warning). `NSSendTypes: public.utf8-plain-text, public.url`.
- Accept: select a URL in Mail → right-click → Services → Save to Stowmark → item saved; works when app is not running (LaunchServices starts it).

#### B-04 Drop onto the Dock icon
Status: done · Priority: P1 · Files: `App/Info.plist` `CFBundleDocumentTypes` (public.image, com.adobe.pdf, public.url, com.apple.web-internet-location), `StowmarkApp.swift` (`.onOpenURL` already exists; add `NSApplicationDelegateAdaptor` `application(_:open:)`)
- Accept: drag a `.webloc`, a PNG, and a PDF onto the Dock icon → three items.

#### B-05 Quick-capture: menu bar extra + global hotkey
Status: todo · Priority: P1 · Files: `StowmarkApp.swift` (`MenuBarExtra`), new `QuickCapturePanel.swift`, `HotkeyMonitor.swift` (Carbon `RegisterEventHotKey` or `NSEvent.addGlobalMonitorForEvents` + Input Monitoring prompt), `App/Stowmark.entitlements` (`com.apple.security.automation.apple-events`), `Info.plist` (`NSAppleEventsUsageDescription`)
- Hotkey (default ⌃⌥⌘S) opens a floating panel prefilled with the frontmost browser's URL/title via AppleScript (`tell application "Safari" to get URL of front document`; same for Google Chrome/Arc/Brave/Edge which share Chrome's suite). Fallback to clipboard URL. Panel: URL, title, shelf, tags, note, Save. Panel never steals focus for more than the save.
- Setting toggle + hotkey recorder in a new **Capture** Settings tab. Menu bar extra shows last save status and "Open Library".
- Accept: with Chrome frontmost, press hotkey → panel shows the Chrome tab URL → ⏎ saves → menu bar shows "Saved · <title>". Denying Apple Events permission degrades to clipboard prefill with a clear note.

#### B-06 Clipboard watcher (opt-in)
Status: todo · Priority: P2 · Files: `LibraryModel.swift` (`NSPasteboard.general.changeCount` timer ~1 s while enabled), `LibraryShell.swift` (non-modal banner "Save copied link? ⏎"), Settings Capture tab
- Only fires for http(s) URLs not already in the library. Banner auto-dismisses in 8 s. Never saves without a keypress/click.
- Accept: copy a URL in any app → banner appears in Stowmark → ⏎ saves; copying the same URL again does nothing.

#### B-07 App Intent: "Save to Stowmark"
Status: done · Priority: P2 · Files: new `Sources/Stowmark/SaveIntent.swift` (`AppIntent` with `@Parameter url: URL`, optional `shelf`, `tags`, `note`; `AppShortcutsProvider`)
- Accept: Shortcuts → "Save to Stowmark" with a URL → item saved; Spotlight "Save to Stowmark" appears.

#### B-08 Other browsers via URL scheme + bookmarklet surface
Status: partial (Settings shows bookmarklets and `mymind://save`; no Chrome extension in this slice) · Priority: P2 · Files: `SettingsView.swift` (Capture tab → "Other browsers"), new `BrowserExtension/chrome/` (MV3: `manifest.json`, `background.js` with `chrome.action.onClicked` → `chrome.tabs.create({url:"stowmark://save?…"})` then close the tab, `commands` shortcut, context menus)
- Settings shows: two bookmarklets (copyable, with a "drag this to your bookmarks bar" link), and a "Load unpacked extension" folder path for Chrome/Arc/Edge/Brave. The app shows a toast + badge when a `mymind://save` arrives so the user gets confirmation somewhere.
- Accept: Chrome bookmarklet → item saved, app toast; unpacked extension ⌘⇧S → same; duplicate → "Already in your library."

#### B-09 (Later) Loopback receipt channel for non-Safari extensions
Status: parked · Priority: P3 · Only if B-08 users need in-extension confirmation. `Network.framework` listener on 127.0.0.1, random port + token in `~/Library/Group Containers/.../loopback.json`, `com.apple.security.network.server`. Extension reads token via a one-time `mymind://pair` round-trip that opens the extension's options page with the token in the fragment.

### Phase 2 — UX / UI

#### U-01 NavigationSplitView with collapsible sidebar
Status: todo · Priority: P1 · Files: `LibraryShell.swift`
- Replace the `HStack` with `NavigationSplitView(columnVisibility:)`; sidebar min 200 / ideal 232 / max 320; ⌘⌥S toggles; remember visibility in `UserDefaults`. Keep the custom search header in detail. Update `adi-011-independent-review.md` A1 evidence to match reality.
- Accept: sidebar collapses/expands with toolbar button and shortcut; selection persists.

#### U-02 Shelf management
Status: todo · Priority: P1 · Files: `LibraryShell.sidebar`, `LibraryModel`, `LibraryStore` (`renameShelf`, `reorderShelves`)
- Rename (double-click / context), drag to reorder (`.onMove`), drag a card onto a shelf row to add membership (`.dropDestination(for: SavedItem.ID)`), shelf item counts already exist.
- Accept: rename persists after relaunch; dragging a card onto "Reading" adds it without leaving the current place.

#### U-03 Sort control + tag browser
Status: todo · Priority: P1 · Files: `LibraryShell.header`, new `TagBrowser.swift`, `LibraryStore` (`allTags(withCounts:)`)
- Sort menu in header (Recent, Title, Source, Kind, Kept) that drives `listOrder` for all three layouts. Tag list in sidebar under Shelves (top 20 + "All tags…" sheet); click adds a tag filter.
- Accept: sort persists across layouts; clicking a tag filters and shows a chip.

#### U-04 Keyboard model
Status: todo · Priority: P1 · Files: `LibraryShell.swift` (`onKeyPress`), `StowmarkApp.swift` commands
- ←/→ in grids (compute columns from width via `GeometryReader`), Home/End, ⌘↩ open original, ⌘C copy link, ⌫ (no ⌘) moves to Stowmark Trash with the confirm setting, ⌘Z undo last trash (add `undoLastTrash` using the trashed id), ←/→ inside preview moves to prev/next item, Space toggles preview.
- Accept: full loop with mouse unplugged: search → arrow to a card → Space → ← → Esc → ⌫ → ⌘Z.

#### U-05 Preview polish
Status: todo · Priority: P2 · Files: `ItemViews.ItemPreview`
- Add Quick Look button for copied files (`QLPreviewPanel`), "Copy link", prev/next arrows, autosave note on 600 ms debounce, label DDG-derived descriptions "Description from DuckDuckGo, not the page".
- Accept: PDF → Quick Look opens; description label appears only when `description_origin == 'metadata'` and the source was the search fallback (add `metadata_source` column or reuse `description_origin = 'thirdparty'`).

#### U-06 Card hover quick actions + trash undo
Status: todo · Priority: P2 · Files: `ItemViews.ItemCard`, `LibraryShell`, `LibraryModel`
- On hover (`.onHover`), show favorite + open-original glyphs beside the trash icon (same 28pt style; hidden otherwise; always visible to VoiceOver). After card-trash, show a 6 s toast "Moved to Stowmark Trash · Undo".
- Accept: hover reveals; VoiceOver rotor lists all three; Undo restores the item to the same position.

#### U-07 Settings → Capture tab + support matrix
Status: todo · Priority: P1 · Files: `SettingsView.swift`
- New tab: Safari (status detection via `SFSafariExtensionManager.getStateOfSafariExtension` — show "On / Off / Not found"), one-click toggle (B-01), Share/Services notes, hotkey recorder (B-05), clipboard watcher (B-06), other browsers (B-08). Add a read-only "What Stowmark can keep" matrix: link → Bookmark; selection → Excerpt; JPEG/PNG/HEIC → Image copied; PDF → PDF copied; everything else → not yet.
- Accept: Safari state reflects reality after toggling in Safari; matrix matches `FileSignature.sniff`.

#### U-08 Accessibility floor
Status: todo · Priority: P1 · Files: `LibraryShell`, `ItemViews`
- All interactive targets ≥ 32×32 with ≥ 44pt hit area via `.contentShape`; `AccessibilityNotification.Announcement("\(n) items")` after debounced reload; announce capture outcomes; table rows `accessibilityLabel` = "kind, title, source, kept". Re-run `adi.py verify` and update the score sheet honestly.
- Accept: VoiceOver reads result counts after typing pauses; every control passes the Accessibility Inspector target-size audit.

#### U-09 Table sort without string matching
Status: todo · Priority: P2 · Files: `LibraryShell.itemList`, `applyTableSort`
- Give `SavedItem` stable comparators via an enum `TableColumnID` and map `KeyPathComparator.keyPath` to it with a dictionary; drop `String(describing:)`.

### Phase 3 — Formats and kinds

#### F-01 Broader file support
Status: todo · Priority: P2 · Files: `URLSafety.FileSignature`, `LibraryStore+Records.insertFile`, `Thumbnail`, `LibraryShell.importTypes`
- Add GIF (`47 49 46 38`), WebP (`RIFF….WEBP`), TIFF, SVG (text sniff `<svg`), plain text / Markdown (→ excerpt with filename source), MP4/MOV (→ kind `video`, retention `videoCopied`, thumbnail via `AVAssetImageGenerator`). Update the support matrix (U-07) and `Limits`.
- Accept: each type drops in with the right card and thumbnail; unsupported types still fail clearly.

#### F-02 New content kinds: video, audio, product
Status: todo · Priority: P3 · Files: `Models.ContentKind`, `Classification.swift`, `ItemViews` preview zones
- YouTube/Vimeo → video (play glyph + duration if oEmbed allowed); Spotify/Apple Podcasts → audio; Amazon/Etsy `/dp/` non-book → product. Each gets a distinct preview-zone treatment inside the shared card geometry.

### Phase 4 — Release hygiene

#### R-01 Notarize the DMG
Status: todo · Priority: P0 for beta · Files: `scripts/make-alpha-dmg.sh`
- `xcrun notarytool submit "$DMG" --keychain-profile mymind-notary --wait && xcrun stapler staple "$APP" && xcrun stapler staple "$DMG"`. Store credentials with `notarytool store-credentials`. Accept: `spctl --assess --type open --context context:primarySignature` → accepted; fresh Mac opens without right-click.

#### R-02 Xcode project for the appex targets
Status: todo · Priority: P1 · Generate with `xcodegen` (`project.yml`) so Safari and Share appexes embed via standard build phases; keep SwiftPM for LibraryCore. Accept: `xcodebuild -scheme Stowmark archive` produces a bundle identical in layout to the scripted one.

#### R-03 Version lockstep + changelog
Status: todo · Priority: P2 · Single `VERSION` file read by `make-alpha-dmg.sh`, both Info.plists, and `extension-manifest.json`; append `dist/ALPHA-NOTES.md` per build.

#### R-04 End-to-end capture journey test
Status: todo · Priority: P1 · Scripted (`scripts/e2e-capture.sh` + `StowmarkTool`) on a clean `MYMIND_ROOT`: install build → quit app → simulate Safari save via handler (call `StowmarkExtension` handler through a small harness or `StowmarkTool save --origin safari --group`) → launch app → assert item present, receipt `saved`, fingerprints equal → export → restore into empty root → compare ids/notes/tags/hashes. This is the alpha acceptance bar from the audit.

---

## Suggested order for the builder

1. C-01, C-02 (correctness; unblock drag & drop and Safari-closed saves)
2. B-01, B-02 (Safari shortcut/badge/image bytes; Share extension — biggest "easier than paste" wins, covers every browser)
3. U-07, U-01, U-04, U-08 (Capture settings, collapsible sidebar, keyboard, a11y)
4. C-03, C-04, C-05 (draft restore, image cache, PDF covers)
5. B-03, B-04, B-05 (Services, Dock drop, hotkey panel)
6. U-02, U-03, U-05, U-06, U-09
7. B-06, B-07, B-08, F-01
8. R-01 before any build goes to someone other than Charles; R-02/R-03/R-04 alongside.
