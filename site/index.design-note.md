# Stowmark landing — WDI-010 design note

Page file: `index.html`

## Classification

```text
Project/topic: Stowmark public-alpha landing
Page or site type: software-product
Primary audience: Mac evaluators who already have or will receive the private GitHub release
Primary user action: download Stowmark-1.0.0-alpha.10.dmg and open it with Gatekeeper
Secondary user action: understand the save → keep → find → export loop, then drop in a walkthrough film later
Emotional tone: precise, trustworthy, warm
Content density: editorial; operational facts over adjectives
Device priority: desktop first (the product is a Mac app), tablet then phone as composed stacks
Interaction level: low — one download, in-page anchors, optional film when the file exists
Motion level: 1 — focus and color only; film uses native controls
Trust requirement: high — local-first, no account, named limits, SHA-256, evaluation license
Conversion pressure: medium — get the DMG; do not manufacture urgency
Implementation stack: static HTML + CSS + one progressive-enhancement script; no framework
```

## Experience thesis

A visitor should **understand** that Stowmark is a local visual library on their Mac, **feel** the paper desk of the app rather than a SaaS dashboard, **believe** the limits because they are designed in, and **do** download alpha.10.

## Creative concept

**Desk blotter.** The page is a ruled-paper desk: one green action, operational receipts in ink, a film plate waiting for the walkthrough Charles is cutting. It would collapse if transplanted onto a chat app or a fintech console.

## Subject-specific cues

1. Capture bar language from the shipping app: “Paste a link or drop a file.”
2. Paper / ink / forest green tokens from `Sources/Stowmark/Theme.swift` (`#F3EDE4`, `#1F1A16`, `#1B5E3B`). The shipping name is Stowmark; My Mind remains only as a former-name honesty line.
3. Kind inventory the library actually stores: links, images, excerpts, PDFs — plus the real layout names Cards, Rows & Columns, Covers.

## Selected composition

**Product walkthrough** (gate primary). A numbered spine `01–04` maps the actual loop: save, keep, find, carry. The opening viewport is a single split (claim + film plate), used once, not a zig-zag. The walkthrough is the system map.

Why it fits: evaluators need the sequence they will perform after the DMG, not a feature grid.

## Visual grammar

- **Type:** display is Iowan Old Style / Palatino (catalog serif on a Mac); body is Avenir Next / system-ui; receipts are SF Mono. No remote webfonts (WDI-014 fails closed on remote CSS).
- **Color:** paper canvas, ink text, one forest accent on the download and current nav. Paper rules are `#E4D9CC` lines from the app, not a decorative blob.
- **Composition:** left-aligned claim, one film plate, then a ledger spine. Max measure ~62ch for prose.
- **Imagery:** app icon still-life as identity only (`data-wdi-media-role="identity"`). No product screenshots.
- **Surfaces:** cream insets, 12px card radius / 14px bar radius matching Theme.Radius. Hairline `#DDD3C7`.
- **Motion:** 160ms color/focus. `prefers-reduced-motion: reduce` zeros duration. No entrance choreography.
- **Density:** sparse hero, denser receipts, compact honesty band.

## Section narrative

| Section | Job | Visitor question | Evidence | Treatment | Transition | Mobile |
| --- | --- | --- | --- | --- | --- | --- |
| Stamp | Date the build | Which alpha? | `VERSION` 1.0.0-alpha.10 | Hairline stamp, not a banner ad | into hero | wraps to two lines |
| Hero | Name the product and download | What is this / how do I get it? | DMG URL, SHA-256 | Left type + one CTA; film plate on the right | into spine | type, CTA, then plate |
| Film plate | Hold the forthcoming recording | Where is the demo? | Honest “being cut” copy; `assets/demo.mp4` upgrade path | Identity still-life on ruled paper; not a fake Mac window | into 01 | full width under type |
| 01–04 spine | Map the loop | What happens after install? | Capture paths, local SQLite, Cmd-F layouts, `.mymind` export | Numbered ledger rows, each with a real artifact | into install | stacked rows, numbers stay |
| Install | Get it open | Why won’t it launch? | Gatekeeper right-click Open | Numbered procedure | into limits | same order |
| Limits | Design the constraint | What is missing? | ALPHA-NOTES known limits | Honesty band | footer | stacked facts |

## Signature conformance (product-walkthrough)

- **Must — stepped spine with a real per-step artifact:** 01 capture origins; 02 what is actually on disk; 03 search + layout names; 04 export archive name and SHA-256 of this DMG.
- **Must — numbered so it reads as a system map:** visible `01`–`04`.
- **Must not — one static image standing for all steps:** no product still; film plate is identity + honest absence.

## Borrowed reference principles (max 3)

1. **Output.com** — cream paper as the page material, then a large type band. Solves “SaaS white void.” Fails if we overlay lime marketing on photography we do not own.
2. **Alma.food** — one download object on warm paper, quiet nav. Solves “too many CTAs.” Fails if we fake a phone mockup; Stowmark is a Mac app.
3. **Lookback.com** — type-led feature stack, no card wall. Solves equal-weight feature tiles. Fails if we add pastel blobs or a hand-swoosh gimmick.

## Card budget

Site type budget: **1**. Cards used: **0**. Walkthrough rows are a numbered spine, not a card wall.

## Forbidden defaults rejected

1. Equal-height card wall — unused.
2. Three columns under a centered hero — hero is a two-pane split, left-aligned, not a 3-col icon row.
3. Fake dashboard screenshot / invented product UI — none; identity icon only.
4. Pointless KPI strip — no user counts.
5. Stock-icon feature grid — unused.
6. Repeated two-column zig-zag — one split in the opening, then a ledger.
7. Unearned gradient blob — paper rules are the product’s `paperRule` lines, justified here as material, not a mesh blob; hero is not centered over them as the sole visual.
8. Giant testimonial card row — unused.

## Product media (WDI-014)

Product imagery provenance: none
Visitor-facing product proof: none — honest text/provenance only
Static product screenshots in visitor-facing content: none

The walkthrough film is being cut. `site/assets/demo.mp4` plus `site/assets/demo.en.vtt` will become a `source-bound recording @ v1.0.0-alpha.10` in a later pass. Until that file exists, the plate is identity media and honest copy. A progressive script may promote the plate only when the file is present; the shipped HTML does not contain a `<video>` proof node.

## Motion / responsive / accessibility / performance

- Motion: focus ring and button color; reduced-motion disables transitions; no autoplay.
- Responsive: at ≤720px the hero stacks claim → download → plate. Touch targets ≥44px. Nav collapses to a compact row with the download control remaining visible.
- Accessibility: skip link, landmarks, visible focus, 4.5:1 ink on paper, `aria-current` on in-page targets, SHA-256 in a selectable `<code>`.
- Performance: one PNG identity asset, no webfonts, no analytics.

## Authorship review plan

- Interchangeability: replace name/colors — the capture origins, Gatekeeper steps, `.mymind` archive, and SHA-256 still describe this Mac library, not a generic app.
- Screenshot: three crops (hero, spine, honesty band) share paper/ink/green and differ in composition.
- Explanation: every major decision maps to Theme.swift, ALPHA-NOTES, or a WDI signature.
