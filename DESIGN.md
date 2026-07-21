# DESIGN.md — Svid Design System

> Persistent design tokens for all AI-generated UI. Every Claude session reads this to maintain visual consistency.
> Direction: **Nocturne Cinematic** — "Obsidian Wine Cellar" (Svid) | "Arctic Obsidian Command" (VidCombo)
> Updated: 2026-04-13 (Multi-Brand Visual Identity v2.0 — typography, shape, elevation, card borders)
> Source of truth: `lib/core/config/brand_config.dart` + `COLOR_RESEARCH.md`

## Design Constitution — 5 Pillars

1. **4-Tier Layering Law** — L0 in `#0A0A0A`–`#14171D` zone; L1 in `#141416`–`#16181A` (Spotify/Figma consensus band). Non-linear Δ L\* rhythm (tight early, looser late). No `#000000`, no muddy `#121212`.
2. **Brand-Tinting Purity** — Svid warm rose (chroma 3-6), VidCombo cool arctic (chroma 3-8). Zero cross-contamination.
3. **Brand-Shaped Identity** — Svid: 3px angular (sharp terminals match Inter). VidCombo: 12px rounded cards, 999px pill buttons (geometric-friendly match DM Sans). Radius tokens delegated via `BrandConfig`.
4. **Elevation Strategy** — Svid: flat + visible border (defined edges, tonal layering). VidCombo: elevated + borderless (shadow defines edges, floating cards). `hasCardBorder` + `cardElevation` in BrandConfig.
5. **WCAG 7:1 on textPrimary** — `onSurface` = `#F5F2F3` (Svid) / `#F2F4F7` (VidCombo). Never pure `#FFFFFF`.

## Svid — Obsidian Wine Cellar (Dark, Primary)

Brand-tinted warm rose. 5-tier elevation ladder built on the M3 surface container roles.

| Tier | Token | Hex | L\* | Usage |
|------|-------|-----|-----|-------|
| L0 | `surfaceContainerLowest` / `darkSurfaceLowest` | `#0A0809` | 0.28% | Deep inset well, thumbnail backdrop |
| L1 | `surface` / `darkBase` | `#151214` | 0.60% | App body, main content |
| L2 | `surfaceContainerLow` | `#1D1819` | 0.88% | Sidebar, sub-panel |
| L3 | `surfaceContainer` / `darkElevated` | `#2A2225` | 1.50% | Default card, list row, download item |
| L4 | `surfaceContainerHigh` | `#352B2F` | 2.00% | Hover, elevated card, dropdown |
| L5 | `surfaceContainerHighest` | `#40353A` | 2.70% | Pressed state, modal, dialog |

| Token | Hex | Contrast on L1 | Usage |
|-------|-----|----------------|-------|
| `onSurface` / `darkLightText` | `#F5F2F3` | 15.2:1 ✅ AAA | Headings, primary body |
| `onSurfaceVariant` / `darkMetaText` | `#B5B0B2` | 8.1:1 AA | Secondary text, captions |
| `outline` | `#4D4046` | — | Default input border |
| `outlineVariant` / `darkMuted` | `#3C2F32` | — | Hairline divider |
| `primary` (M3 role) | `#F48B9B` | — | Light rose on dark |
| `primaryContainer` | `#6B0118` | — | Dark wine container |
| `brand` | `#8D021F` | — | Wine red brand constant |
| `brandLight` | `#BF2D4A` | — | Mid rose |
| `brandDark` | `#5E0115` | — | Deep wine |
| `accentHighlight` | `#C41E3A` | — | Crimson CTA background (use AppColors.accentHighlight, NOT cs.primary) |
| `accentMuted` | `#5C0114` | — | Subtle badge background |

## Svid — Architectural Gallery Morning (Light)

Warm cream base. Brand accents stay constant across modes.

| Tier | Token | Hex | Usage |
|------|-------|-----|-------|
| L0 | `surfaceContainerLowest` / `lightElevated` | `#FFFFFF` | Most elevated card |
| L1 | `surface` / `lightBase` | `#FCF9F7` | App body cream |
| L2 | `surfaceContainerLow` | `#F6F3F1` | Sidebar, sub-panel |
| L3 | `surfaceContainer` / `lightSurfaceLowest` | `#F0EDEB` | Default card, inset well |
| L4 | `surfaceContainerHigh` | `#EAE8E6` | Hover, elevated card |
| L5 | `surfaceContainerHighest` | `#E5E2E0` | Pressed, modal |

| Token | Hex | Contrast | Usage |
|-------|-----|----------|-------|
| `onSurface` | `#1B1C1B` | 15.3:1 ✅ AAA | Headings |
| `onSurfaceVariant` / `lightMetaText` | `#594140` | 9.2:1 AAA | Secondary |
| `outline` | `#C4A9A8` | — | Default |
| `outlineVariant` / `lightMuted` | `#E1BEBD` | — | Hairline |
| `primary` / `brand` | `#8D021F` | — | Wine constant |
| `primaryContainer` | `#FCDDE3` | — | Light rose container |
| `accentHighlight` | `#C41E3A` | — | Crimson CTA |

## VidCombo — Arctic Obsidian Command (Dark)

Cool slate arctic. Brand-locked cyan/blue accents.

| Tier | Token | Hex | Usage |
|------|-------|-----|-------|
| L0 | `surfaceContainerLowest` / `darkSurfaceLowest` | `#0D0E10` | Deep inset well |
| L1 | `surface` / `darkBase` | `#141618` | App body |
| L2 | `surfaceContainerLow` | `#1E2023` | Sidebar, sub-panel |
| L3 | `surfaceContainer` / `darkElevated` | `#282A2E` | Default card |
| L4 | `surfaceContainerHigh` | `#32353A` | Hover, elevated |
| L5 | `surfaceContainerHighest` | `#3D4045` | Pressed, modal |

| Token | Hex | Contrast on L1 | Usage |
|-------|-----|----------------|-------|
| `onSurface` / `darkLightText` | `#F2F4F7` | 14.8:1 ✅ AAA | Headings |
| `onSurfaceVariant` / `darkMetaText` | `#BCC8D1` | 9.4:1 AAA | Secondary |
| `outline` | `#5A6169` | — | Default |
| `outlineVariant` / `darkMuted` | `#3D4850` | — | Hairline |
| `primary` (M3 role) | `#8DD6FF` | — | Bright sky on dark |
| `primaryContainer` | `#004A99` | — | Dark blue container |
| `brand` | `#0066CC` | — | Blue brand constant |
| `brandLight` | `#03BEFE` | — | Arctic cyan |
| `brandDark` | `#0041CC` | — | Deep blue |
| `accentHighlight` | `#03BEFE` | — | Cyan CTA |

## VidCombo — Nordic Studio Noon (Light)

Pale ice base. Brand stays constant.

| Tier | Token | Hex | Usage |
|------|-------|-----|-------|
| L0 | `surfaceContainerLowest` / `lightElevated` | `#FFFFFF` | Most elevated |
| L1 | `surface` / `lightBase` | `#F7FAFD` | App body ice |
| L2 | `surfaceContainerLow` | `#F1F4F7` | Sidebar |
| L3 | `surfaceContainer` / `lightSurfaceLowest` | `#EBEEF1` | Default card |
| L4 | `surfaceContainerHigh` | `#E5E8EB` | Hover |
| L5 | `surfaceContainerHighest` | `#E0E3E6` | Pressed, modal |

| Token | Hex | Contrast | Usage |
|-------|-----|----------|-------|
| `onSurface` | `#181C1E` | 16.1:1 ✅ AAA | Headings |
| `onSurfaceVariant` / `lightMetaText` | `#414753` | 9.8:1 AAA | Secondary |
| `outline` | `#A2A9B0` | — | Default |
| `outlineVariant` / `lightMuted` | `#C1C6D5` | — | Hairline |
| `primary` / `brand` | `#0066CC` | — | Blue constant |
| `primaryContainer` | `#D6E8FF` | — | Light blue container |
| `accentHighlight` | `#03BEFE` | — | Cyan CTA |

## Semantic Colors (Shared, Brand-Agnostic)

| Token | Dark Hex | Light Hex | Usage |
|-------|----------|-----------|-------|
| `success` | `#22C55E` | `#16A34A` | Download complete |
| `warning` | `#F59E0B` | `#D97706` | Slow connection, retry |
| `error` | `#EF4444` / `#FCA5A5` | `#DC2626` | Failed downloads |
| `info` | `#3B82F6` / `#60A5FA` | `#2563EB` | Informational |

## Typography — Brand-Aware Fonts

Single font per brand, all contexts. Selected for maximum opposition + personality match.

| Brand | Font | Personality | Why |
|-------|------|-------------|-----|
| Svid | **Inter** | Humanist, sharp terminals | Matches angular 3px shape. Professional, precise, Nocturne cinematic feel |
| VidCombo | **DM Sans** | Geometric, clear bold strokes | Matches rounded 12px shape. Friendly, approachable, Arctic command clarity |

Loaded via `google_fonts` package. `AppTypography._font()` dispatches per brand. `AppTypography.fontFamily` returns brand font family.

| Token | Value |
|-------|-------|
| `heading-xl` | 28px / 700 / -0.02em |
| `heading-lg` | 22px / 600 / -0.01em |
| `heading-md` | 18px / 600 / 0 |
| `body-lg` | 16px / 400 / 0 |
| `body-md` | 14px / 400 / 0.01em |
| `body-sm` | 12px / 400 / 0.02em |
| `caption` | 11px / 500 / 0.03em / uppercase |

## Spacing

| Token | Value |
|-------|-------|
| `space-xs` | 4px |
| `space-sm` | 8px |
| `space-md` | 12px |
| `space-lg` | 16px |
| `space-xl` | 24px |
| `space-2xl` | 32px |
| `space-3xl` | 48px |

## Radius — Brand-Shaped Identity

Semantic tokens delegated from `BrandConfig`. All widget code uses `AppRadius.card`, `.button`, etc.

| Token | Svid | VidCombo | Usage |
|-------|-------|----------|-------|
| `AppRadius.card` | 3px | 12px | Cards, containers, list items |
| `AppRadius.button` | 3px | 999px (pill) | Buttons, action chips |
| `AppRadius.input` | 3px | 8px | Text fields, dropdowns |
| `AppRadius.dialog` | 3px | 12px | Dialogs, modals, sheets |
| `AppRadius.chip` | 3px | 999px (pill) | Filter chips, tags |
| `AppRadius.popup` | 3px | 8px | Tooltips, menus, popups |
| `AppRadius.full` | 999px | 999px | Avatars, circular indicators |

## Card Surface Strategy

| Axis | Svid | VidCombo |
|------|-------|----------|
| **Border** | ✅ Visible hairline (`outlineVariant`) | ❌ No border |
| **Elevation** | 0 (flat) | 2 (floating) |
| **Edge definition** | Border defines edge | Shadow defines edge |
| **Feel** | Precise, engraved, architectural | Floating, soft, approachable |

Controlled by `BrandConfig.current.hasCardBorder` and `BrandConfig.current.cardElevation`. Theme-level `CardTheme` and widget-level `Border.all` both check `hasCardBorder`.

## Design Principles

1. **Brand-dependent borders** — Svid: visible hairline borders define card edges (flat + bordered). VidCombo: no card borders, shadow defines edges (elevated + borderless). Both: input/focus borders always present.
2. **Brand-dependent elevation** — Svid: zero shadow, tonal layering only. VidCombo: subtle elevation (2dp) for floating card feel.
3. **Density over whitespace** — Desktop power-user app, not a landing page. Maximize information density.
4. **Animation: subtle** — 150-200ms ease-out transitions. No bouncy, no spring physics.
5. **Icons: outlined** — 1.5px stroke, 24px default. Match `text-secondary` color.
6. **Dark-first** — Design dark mode first, derive light mode. Brand accents stay constant across both.

## Component Patterns

### Top Navigation Bar
- Height: 52px, fixed top, full width
- Background: `surface-raised` (dark) / white with backdrop-blur (light)
- Layout: Svid logo (crimson, left) → tab links (center-left) → action icons (right)
- Active tab: `accent-highlight` text + 2px bottom border `accent-highlight`
- Inactive tab: `text-primary` at 60% opacity
- NO sidebar, NO left rail, NO bottom navigation

### Download Item Card
- Background: `surface-raised`
- Thumbnail: 16:9 ratio, `radius-md`
- Progress bar: `accent-highlight` fill on `surface-subtle` track, 4px height
- Status badges: pill shape, `radius-xl`, `caption` text

### URL Input Bar
- Full width, prominent placement
- Background: `surface-overlay`
- Border: 2px `accent-primary` on focus
- Placeholder: `text-tertiary`
- Paste button: `accent-highlight` background

### Empty States
- Centered layout
- Subtle illustration or icon (64px, `text-tertiary`)
- Heading: `heading-md`, `text-primary`
- Description: `body-md`, `text-secondary`
- CTA: `accent-highlight` button

## Stitch Prompt Template

When generating new screens, include this prefix for consistency:

### Svid — Obsidian Wine Cellar (Dark)
```
Svid desktop video downloader. Design system: Obsidian Wine Cellar.
Dark theme — warm rose undertone:
  L0 deep well #0A0809 → L1 body #151214 → L3 cards #2A2225 → L5 modals #40353A
  Text: #F5F2F3 headings (15:1 contrast), #B5B0B2 secondary.
  Accent: #8D021F wine, #C41E3A crimson CTAs, #F48B9B primary role.
  Borders: #3C2F32 hairline, #4D4046 default.
Inter font. 3px sharp corners. No shadows — tonal elevation only.
Dense power-user layout. Desktop app (not website). TopNavigationBar: 52px fixed.
CRITICAL: NO sidebar. NO left rail. NO bottom navigation. Top bar only.
Nav: Svid logo (crimson) left → tab links center → action icons right.
[SCREEN-SPECIFIC PROMPT HERE]
```

### Svid — Architectural Gallery Morning (Light)
```
Light mode: warm cream base.
  L0 white #FFFFFF → L1 body #FCF9F7 → L3 cards #F0EDEB → L5 modals #E5E2E0
  Text: #1B1C1B headings, #594140 secondary (9:1).
  Accent: #8D021F wine constant, #C41E3A crimson CTAs.
  Borders: #E1BEBD hairline, #C4A9A8 default.
Same layout and components as dark. TopNavigationBar: white/frosted 52px.
```

### VidCombo — Arctic Obsidian Command (Dark)
```
VidCombo desktop video downloader. Design system: Arctic Obsidian Command.
Dark theme — cool arctic slate undertone:
  L0 deep well #0D0E10 → L1 body #141618 → L3 cards #282A2E → L5 modals #3D4045
  Text: #F2F4F7 headings (15:1), #BCC8D1 secondary.
  Accent: #0066CC blue brand, #03BEFE cyan CTAs, #8DD6FF primary role.
DM Sans font. 12px rounded cards, pill-shaped buttons. Floating cards with subtle
shadow (elevation 2) — NO visible borders. Soft, approachable, geometric.
```

### VidCombo — Nordic Studio Noon (Light)
```
Light mode: pale ice base.
  L0 white #FFFFFF → L1 body #F7FAFD → L3 cards #EBEEF1 → L5 modals #E0E3E6
  Text: #181C1E headings, #414753 secondary (10:1).
  Accent: #0066CC blue constant, #03BEFE cyan CTAs.
DM Sans font. Same rounded/floating card style as dark. Subtle shadow defines edges.
```

## Stitch Prompting Philosophy

> Accumulated through 3 rounds of learning (2026-03-23 → 2026-03-24). Chairman-approved.

**Stitch = MOOD / VISION tool, not pixel-perfect spec converter.**

### The Value Chain
```
Opus 4.6 deep thinking (app understanding + design theory + UX psychology + cinematic vision)
    → Creative brief prompt (emotion, story, metaphor, aesthetic)
    → Stitch AI (free to interpret, surprise, be creative)
    → Chairman reviews vision/mood (not pixels)
```

### Prompt Style: Creative Director, NOT Engineer
- BAD: "Notification list: 8 items, leading icon 28px, trailing time bodySmall alpha 0.5"
- GOOD: "Notification center feels like reading credits at the end of a noir film. Each notification is a moment, not a data row."
- Include mood, metaphor, cinematic references, emotional tone
- Do NOT include pixel dimensions, padding values, exact widget specs
- Let Stitch surprise — unexpected layouts are features, not bugs

### Successful Prompt Patterns (scored 9+/10)
1. **YouTube Autocomplete** — "Search command center overlay. Background: blurred Explore Landing. Pill-shaped search bar with text cursor blinking crimson. Dropdown panel with 8 suggestions like a command palette. Footer: keyboard shortcuts ↑↓ Enter. Quick Search Mode."
   - Why it worked: Gave Stitch a metaphor ("command center"), emotional tone ("precision"), and functional structure without pixel specs.

2. **Search Results V2** — Full DESIGN.md tokens provided + "Cinema-grade dark UI. Netflix/Spotify caliber density. Featured card should feel premium and immersive. Results list should be scannable and efficient."
   - Why it worked: Balanced exact color tokens (for consistency) with cinematic vision (for creativity).

3. **Explore Light** — "Unlock the world's cinematic library. Hero search with category cards — full-bleed images, gradient overlays. Subscriptions as circular avatars with live indicators."
   - Why it worked: Led with a tagline/vision, gave Stitch freedom on category card execution.

### Failed Prompt Patterns (avoid)
1. **Round 3 pixel specs** — Fed every widget dimension, padding value, exact icon size from Flutter code. Result: technically accurate reskin, zero creative value. "Càng lúc tôi càng thấy chán."
2. **Round 2 batch generation** — Generated 64 screens at once. Result: canvas chaos, no quality control, inconsistent design language.
3. **Round 1 narrative** — Too abstract, no design system grounding. "Inspired by cyberpunk aesthetics" → generic, no brand identity.
