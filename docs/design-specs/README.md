# Design Specs — Svid Desktop App

> Implementation blueprints derived from Stitch MCP designs.
> Each spec maps Stitch HTML → Flutter widgets with exact token values.
> CTO reads spec → implements → verifies against checklist.
> Updated: 2026-03-25

## Stitch Project

- **Active**: `Svid Desktop — Final UI Design` (ID: `10022260214920217805`)
- **Design System**: Nocturne Cinematic (DESIGN.md)
- **Pipeline**: Stitch MCP → Spec Doc → Flutter Implementation → Visual Verification
- **Screen registry**: See `STITCH.md` for full screen IDs and status

## Screen Specs

### Core App Screens

| # | Screen | Spec File | Stitch ID (full) | Status |
|---|--------|-----------|-----------------|--------|
| 1 | First-Time Setup | [first-time-setup.md](first-time-setup.md) | `348c739741514417823e166bc9cb4a27` | **Implemented** |
| 2 | Home Dashboard | — | `a9e49dc6235941b7b7cacc9009fc591b` | Pending |
| 3 | Settings | — | `996478f1821d42b49b5ffdf95d3416d8` | Pending |
| 4 | AI Assistant | — | `871de3ebf1844dbb971f893686e91d99` | Pending |
| 5 | Premium Management | — | `e27d2d04a5d348c5bbd504997b8d782a` | Pending |
| 6 | Premium Upgrade | — | `13a120d3889c4a2b89479136989dbf0c` | Pending |
| 7 | Notification Center | — | `e629b606fa99411f9a7420977e1a1572` | Pending |
| 8 | Support Center | — | `47374b6627c04c2db63cc1e3e445a024` | Design Ready |

### YouTube Explore (Implemented 2026-03-25)

| # | Screen | Spec File | Stitch ID (full) | Status |
|---|--------|-----------|-----------------|--------|
| Y1 | YouTube Explore — Discovery | [youtube-explore-discovery.md](youtube-explore-discovery.md) | `1b679801cd0949d89f6541ac1a9cbbb6` | **Implemented** |
| Y2 | YouTube Search Results | [youtube-search-results.md](youtube-search-results.md) | `341a9953abfd4f84ae45d5e29ba3e70d` | **Implemented** |
| Y3 | YouTube Autocomplete State | [youtube-autocomplete.md](youtube-autocomplete.md) | `123a3a9c23154ef88586bc4384775059` | **Implemented** |

### Premium Flow (from Archive project `9746799973876268727`)

> Note: These screens are in the ARCHIVE Stitch project. Verify screen IDs still exist before implementing.

| # | Screen | Spec File | Stitch Screen ID | Status |
|---|--------|-----------|-----------------|--------|
| P1 | Grand Invitation (Pricing) | [premium-grand-invitation.md](premium-grand-invitation.md) | `5ead0daf` | **DRAFT** — Review |
| P2 | Crypto Payment (Modal) | [premium-crypto-payment.md](premium-crypto-payment.md) | `5a9661b3` | **DRAFT** — Review |
| P3 | Welcome Home (Celebration) | [premium-welcome-home.md](premium-welcome-home.md) | `631d2228` | **DRAFT** — Review |
| P4 | Velvet Rope (Upgrade Prompt) | [premium-velvet-rope.md](premium-velvet-rope.md) | `351adcfd` | **DRAFT** — Review |
| P5 | Member's Lounge (Management) | [premium-members-lounge.md](premium-members-lounge.md) | `83c98c6a` | **DRAFT** — Review |
| P6 | Glass Wall (Feature Gate) | [premium-glass-wall.md](premium-glass-wall.md) | `ac7c1235` | **DRAFT** — Review |

## Spec Structure (per screen)

1. **Design Intent** — Purpose and mood
2. **Visual Structure** — ASCII layout + dimensions
3. **Token Extraction** — Exact colors, typography, spacing from Stitch HTML
4. **Gap Analysis** — Design vs current code differences
5. **Widget Spec** — Flutter widget tree with code snippets
6. **State Flow** — States, transitions, text changes
7. **Token Changes** — Any new tokens needed in app_colors/spacing/typography
8. **Platform Considerations** — macOS/Windows/Linux differences
9. **Animation Spec** — Durations, curves, triggers
10. **Verification Checklist** — Post-implementation QA

## Workflow

```
1. Fetch Stitch HTML (get_screen → download URL → curl)
2. Read current Flutter code for the screen
3. Create spec doc (this directory)
4. Chairman reviews spec (optional)
5. Implement Flutter changes
6. Verify against checklist
7. Mark spec status as "Implemented"
```

## Reference: Model Spec (first-time-setup.md)

The First-Time Setup spec is the gold standard for spec quality. New specs should follow its structure: ASCII layout diagram, exact token-to-widget mapping, gap analysis table, verification checklist.
