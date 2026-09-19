# ADI-011 independent review — My Mind

Reviewer: independent agent (not the builder)
Rubric: ADI-011 rev 1.3 (weights A1.20 A2.20 A3.15 A4.10 A5.15 A6.10 A7.10)
Basis: `design-note.md`, `Sources/MyMind/{LibraryShell,Theme,LibraryModel,MyMindApp,SettingsView}.swift`, `Sources/LibraryCore/LibraryStore+Records.swift`, `gate-receipts/verify.json` (static heuristics, exit 0). Builder draft in `adi-011-score-sheet.md` is superseded by this file.

Screen/flow: Library shell (sidebar + gallery/list + preview overlay)
Platform(s): macOS (SwiftUI; design-note checker token ios)
A1 Navigation fit:          5/5  (evidence: LibraryShell.swift NavigationSplitView + sidebar place List for All/Favorites/Shelves; preview is a trailing overlay closed by Escape/Close — not a third column or tab bar)
A2 Platform conformance:    4/5  (evidence: MyMindApp.swift Settings scene + CommandGroup shortcuts; App/Info.plist LSMinimumSystemVersion/NSApplication; no phone tab chrome. Deducted from 5: search lives in a custom detail header rather than `.searchable`/toolbar, and verify.json still declares platform token ios while shipping Mac)
A3 State completeness:      4/5  (evidence: LibraryShell empty / noResults / recovery; ItemCard fallbackLine for pending/unavailable previews; ItemPreview unavailable copy. Deducted from 5: design-note “retry” is not a control — captureDraft is cleared before save in LibraryModel.captureDraftLink, and failed saves do not restore the draft)
A4 Template justification:  5/5  (evidence: design-note template budget 0; no TabView/tab bar, no FAB, no onboarding pager; shelves are place rows; ItemCard visual switches by ContentKind)
A5 Visual identity system:  4/5  (evidence: Theme.swift warm paper/sidebar/card/ink + green accent/danger + Radius chip/card/bar/panel; ItemCard kind silhouettes excerpt/book/image/document. Deducted from 5: identity is coherent utility paper, but type roles stay default system fonts with only serif excerpts — not a 5-band signature system)
A6 Motion & haptics:        4/5  (evidence: LibraryShell.previewLayer uses .opacity only when accessibilityReduceMotion is false, else .identity; no decorative loops; no phone haptics)
A7 Accessibility floor:     3/5  (evidence: placeRow/ItemCard/list accessibilityLabel + isSelected traits; contrast-aware Theme.line; context menus for secondary actions. Below 4: design-note claims 44pt primary targets and result-count announcements after typing pauses — Save uses minHeight 32, Open saved file minHeight 36, and no AccessibilityNotification/live announcement on query reload)
Weighted overall:           4.20/5.0
Hard-fails triggered:       none
Verdict:                    PASS

Screen/flow: Capture and retrieval loop
Platform(s): macOS (SwiftUI; design-note checker token ios)
A1 Navigation fit:          5/5  (evidence: LibraryModel.captureLink / captureDraftLink write through LibraryStore.capture; captureBar shows captureDestination for current shelf vs All items; paste/drop/fileImporter stay on the library detail surface)
A2 Platform conformance:    4/5  (evidence: LibraryShell.dropDestination + capture bar paste; SafariWebExtensionHandler shares LibraryStore; SettingsView explains optional Safari without gating paste/drop. Same Mac-token/checker mismatch as shell — not a phone-wrapped UI)
A3 State completeness:      4/5  (evidence: LibraryModel.runCapture sets Saving… then CaptureResult messages Saved / Already in your library / Not saved…; blocked hosts return usable bookmarks via LibraryStore+Records insertLink. Deducted from 5: failure path clears the field with no Retry affordance, and import success is a header string only)
A4 Template justification:  5/5  (evidence: captureBar is detail-local, not a global FAB or tab-chassis action; import is a sheet with ready/duplicate/unsupported counts — LibraryShell.importSheet)
A5 Visual identity system:  3/5  (evidence: captureMessage uses Theme.accent vs Theme.danger; bar uses Theme.card + Radius.bar. Thin reuse of shell tokens without a capture-specific silhouette or ownable element — below the 4-band identity bar)
A6 Motion & haptics:        4/5  (evidence: isSaving / “Saving…” text only; no bounce/spinner chrome; reduce-motion path inherited from shell preview only)
A7 Accessibility floor:     3/5  (evidence: capture message accessibilityLabel; Capture container label; Save keyboardShortcut.defaultAction. Below 4: Save minHeight 32 vs claimed 44pt floor; no announced capture outcome beyond labeling the same Text)
Weighted overall:           4.05/5.0
Hard-fails triggered:       none
Verdict:                    PASS
