# SSvid Landing CTO Baseline

Date: 2026-04-24

Purpose: lock the decision framework for `ssvid.app` before any further visual or copy changes. This document is the source of truth for what the landing page should optimize for, what references are worth learning from, and what patterns should be rejected.

## Scope

This baseline is based on:

- Current `ssvid.app` live production
- Current `website/` codebase in this repo
- Reference repo `/Users/macos/development/download-apps/desktop-apps/vidcombo-landingpage`
- Current reference sites:
  - `https://vidcombo.com/`
  - `https://www.apple.com/mac/`
  - `https://www.raycast.com/`
  - `https://obsproject.com/`
  - `https://1password.com/`
  - `https://www.figma.com/`

## Core Goal

`ssvid.app` is not trying to be an entertainment-heavy marketing site. It should behave like a serious product acquisition surface:

- immediately understandable
- operationally trustworthy
- explicit about where to download
- explicit about what the product does
- careful not to overclaim
- stable enough that future edits do not reintroduce drift

## What Industry-Standard Sites Consistently Do

Across Apple, Raycast, OBS, 1Password, and Figma, the common pattern is not "more sections" or "more visuals". The consistent pattern is tighter system discipline:

- one primary promise in the hero
- one obvious primary action
- product taxonomy kept clean
- platform taxonomy kept clean
- support, pricing, trust, and downloads each have a clear place
- proof is used to reinforce the promise, not replace it
- copy is narrower and more precise than the product team's internal understanding

## Current SSvid Assessment

### What is already strong

- Strong trust direction: no tracking, no cloud, native app framing
- Good route coverage and localization depth
- Good release synchronization and generated artifact discipline
- Product has meaningful differentiators beyond "basic downloader": native app, built-in browser, library, player, Rust engine, pause/resume

### What is currently unstable

- Message spine is inconsistent:
  - `Save Any Video`
  - `Save Videos on Desktop and Mobile`
  - `native video downloader`
  - `download from 1000+ platforms`
- Product taxonomy and platform taxonomy are mixed together:
  - operating systems
  - source platforms
  - device types
  - product surfaces
- Hero is trying to say too many things at once:
  - desktop app
  - mobile support
  - full quality
  - no tracking
  - 1000+ sites
  - open source
  - native stack
- CTA architecture is still desktop-first in behavior while the copy sometimes reads as if all five platforms are equal entry points.
- Social preview and metadata have improved, but the site still needs one canonical message that every surface repeats.

## Direct Comparison: SSvid vs Vidcombo

### What SSvid should learn from Vidcombo

- First-class download IA. `Vidcombo` treats download as a route, not only as a button.
- Coverage model. There is a clearer surface area for support, contact, install, and platform-specific entry points.
- Utility pages are treated as part of the acquisition system, not random leftovers.

### What SSvid should not copy from Vidcombo

- SEO-first copy repetition like `YouTube Downloader for PC` repeated across every layer
- Generic feature marketing language that sounds broader than the product truth
- "2M+ users", "30x faster", or similar proof claims unless SSvid can substantiate them
- Visuals or copy that imply cloud sync or cross-device continuity if SSvid does not actually center that workflow
- Hero copy that narrows the product too early to one source platform if SSvid is intentionally broader than YouTube

## What To Learn From Each Reference

### Apple

- Product ladder clarity
- "Compare" and "Help me choose" as decision-reduction tools
- Strong separation between hero promise, lineup explanation, and ecosystem reinforcement

### Raycast

- Excellent desktop product positioning
- Hero is extremely tight
- Download surface is explicit, versioned, and operationally useful
- Site repeatedly reinforces native performance without bloating the hero

### OBS

- Download-first architecture
- Release info and OS support are immediate
- Strong open-source trust without trying to romanticize it

### 1Password

- Trust and governance copy is precise and calm
- Multi-surface product story still stays coherent because the top-level message is narrow

### Figma

- IA discipline
- Product segmentation is explicit
- Downloads are treated as a utility surface, not buried inside marketing

## Decisions To Lock

These decisions should be treated as guardrails for every later implementation pass.

### 1. Canonical verb system

Use:

- `Save` for the user outcome
- `Download` for the user action

Do not keep alternating between `save`, `download`, and `keep` as if they are interchangeable in the same hierarchy.

Rules:

- Hero headline uses the outcome language
- Primary CTA uses the action language
- Supporting copy can bridge them, but should not invent a third framing

### 2. Platform taxonomy

Never mix these into one undifferentiated sentence again:

- Where SSvid runs: `macOS`, `Windows`, `Linux`, `iPhone/iPad`, `Android`
- Where SSvid downloads from: `YouTube`, `TikTok`, `Instagram`, `Facebook`, `X`, and others

If these appear together, they must be visually or grammatically separated.

### 3. Hero contract

The hero should answer only four things:

- what SSvid is
- who it is for
- where it runs
- what to click next

The hero should not try to fully explain:

- pricing nuance
- AI assistant depth
- all product modules
- all trust/legal detail
- the entire competitive comparison

### 4. Download architecture

`Download` must be a first-class information architecture surface.

Required behavior:

- top-nav path to download
- OS-specific download pages remain explicit
- hero CTA resolves to the right default for the current platform
- mobile availability must not be visually implied beyond the actual install path that exists today

### 5. Trust architecture

Trust claims must be auditable.

Safe recurring claims:

- native app
- files stay on your device
- no ads
- no tracking
- no cloud upload
- Stripe for payments
- Apple notarization where applicable

Claims that require extra scrutiny before reuse:

- "virus-free"
- "open-source engine" unless the exact scope is clear
- anything quantitative that is not directly measurable on the site or product

### 6. Metadata discipline

Every preview surface should tell the same story:

- page title
- meta description
- OG title
- OG description
- Twitter title
- Twitter description
- favicon/app labels

If the homepage says `desktop + mobile`, the preview image and metadata cannot look desktop-only or mock-mobile.

### 7. Proof hierarchy

Proof should appear in this order:

1. product reality
2. install clarity
3. privacy/trust clarity
4. release/version clarity
5. comparisons and secondary proof

Fake confidence signals are worse than having fewer signals.

## Recommended Message Spine For SSvid

This is the current recommended direction, not final copy:

- Category: native video downloader
- Outcome: save videos to your device
- Platform scope: desktop and mobile apps
- Source scope: YouTube, TikTok, Instagram, Facebook, X, and many more
- Trust clause: no ads, no tracking, no cloud upload

Working formula:

`SSvid is a native video downloader for desktop and mobile. Save videos from major platforms in full quality, directly to your device.`

Operational rule:

- hero headline should stay short
- hero subcopy can expand source platforms and trust
- CTA should stay operational, not conceptual

## Recommended IA Direction

Top-level IA should stay small and useful.

Recommended primary nav model:

- `Features`
- `Download`
- `Pricing`
- `FAQ`

Secondary utility surfaces:

- `Account`
- `Restore`
- `Privacy`
- `Terms`
- `Changelog`
- `Support`

Do not keep acquisition-critical flows hidden behind footer-only discovery.

## Anti-Patterns To Reject

- Hero copy that tries to describe the whole company
- Desktop mockup plus mobile chips plus mobile-sounding copy without clear install logic
- Source platforms and OS platforms blended into the same proof unit
- Preview assets that imply app states not central to the product truth
- Generic "best downloader" marketing language
- Claims that sound like SEO or affiliate copy
- Testimonials, user counts, or speed multipliers without a real evidence pipeline
- Reintroducing analytics or any trust contradiction into privacy-facing surfaces

## Next Implementation Order

Future implementation should happen in this order:

1. lock homepage message spine and metadata
2. elevate `Download` as a first-class nav and route system
3. tighten hero contract and supported-platform presentation
4. align proof sections to the new hierarchy
5. harmonize locale surfaces after English is fully locked

Do not resume visual experimentation until steps 1 and 2 are complete.

## Acceptance Checklist

Before any future homepage copy or visual change is accepted, it must pass all of these:

- one primary promise only
- CTA destination is unambiguous
- OS support and source-platform support are separated clearly
- metadata and hero tell the same story
- trust claims are literally true
- no new section exists only because it "looks nice"
- the edit improves clarity, trust, or conversion, not just density
