# V2 Campaign — CTO Decisions Log

**Date locked**: 2026-05-05
**Authority**: Desktop CTO (autonomous per Chairman empowerment)
**Reaction window**: Chairman + CEO Kỳ are user voice — they review output, flag if not matching expectation. Decisions stand unless explicitly vetoed.

This document is the source-of-truth for V2 implementation decisions. Conflict with spec → this doc wins. Conflict with mockup → this doc wins.

---

## Resolved decisions (8 from research Pass 2A-2F + 7 from prior CTO autonomous)

### Spec interpretation

| ID | Decision | Source | Rationale |
|---|---|---|---|
| Q1 | **DELETE** Tailwind blue token tables in `Design_Spec.md` §2.1 / §2.2 / §2.4 | Pass 2A | v1.2 changelog L10 explicitly deprecate them. Tables are reference cruft that confuses engineers. Em will remove when touching the spec. |
| Q2 | **Code wins** type scale conflict (`displayLarge 48` not `display.xl 32`) | Pass 2A | Design Spec §3.0 already states "use existing classes". §3.2 is design intent reference, not engineer source-of-truth. |
| Q3 | **Keep DM Sans** for VidCombo (don't unify Inter) | Pass 2A | Brand differentiation: Nocturne humanist (Inter) vs Arctic Command geometric (DM Sans). Bundle DM Sans separately in v2.1 cycle. |
| Q4 | **Svid V2 default theme = dark** (Nocturne) | Pass 2A | Mockup is 1-mode demo only. Both light + dark must be supported, but default stays dark per BrandConfig.SvidBrand.defaultThemeMode. |
| Q5 | **Brand wins for card radius**: Svid 3px (angular), VidCombo 12px (frosted) | Pass 2A | Brand-defining components honor BrandConfig.cardRadius/buttonRadius. Spec default 8px applies only to generic NEW components without brand identity. |
| Q6 | **Preserve** Mission Briefing (35 call sites) + Home Dark Operator (69 call sites) tokens | Pass 2A | Pre-existing production investment. V2 ADDS, never rewrites. Add inline doc comment "// Mission Briefing — operator-grade, pre-V2 investment". |

### Implementation strategy

| ID | Decision | Source | Rationale |
|---|---|---|---|
| Q7 | **Schema rename**: spec `v15→v16` migration → actual `v18→v19` | Pass 2B | `app_database.dart:180 schemaVersion = 18`. Spec was authored before v17/v18 shipped. Em sync 6 places (5 in docs, 1 in code). |
| Q8 | **i18n: 2 langs (vi/en) for V2 ship** | Pass 2B | Code reality is `assets/translations/{vi,en}.json` only. Spec 5-lang (vi/en/ja/pt/es) is aspirational. ja/pt/es defer to v2.1+ when needed. Saves Polish 0.5d. |
| Q9 | **F3 player queue = 1.5d** (was spec 2d) | Pass 2B | PlaybackQueueService 263 lines already has setQueue/playNext/next/previous/repeat/shuffle/hasNext/hasPrevious. Just need PlayerNotifier.playlistContext field + UI Next/Prev. Saves Phase §10 0.5d. |
| Q10 | **Add v2→v1 rollback test to Buffer phase** | Pass 2B | Forward-compat needed: v1.x users with v2.0 data should not crash if rollback. Add test (~0.5d within existing Buffer slack). |
| Q11 | **2-dev parallel execution model** for Svid V2 cycle | Pass 2C | Track A (UI/UX 1A→1B→1C) + Track B (data §5+§10) overlap saves ~12d. Em uses parent-orchestrator + agents pattern → effectively parallel within 1 session. |
| Q12 | **Phase 1C drops "Thêm vào playlist" stub**, ship in §10.5 dialogs sub-phase | Pass 2C | Cleaner UX than stub. 4 bulk actions in 1C (Phát/Xoá/Khác/Huỷ). 5th action ships when §10 is complete. |
| Q13 | **Multi-brand HYBRID strategy**: Svid v2.0 first, VidCombo v2.1 +1 cycle | Pass 2E | Spec author intent Svid-first. VidCombo 50k devices — too big for regression risk. Code path identical, only feature flag toggles. |
| Q14 | **Timeline accept reality**: 36-37d single-dev / 25-28d 2-dev parallel | Pass 2C | Spec 28.5-31.5d underestimated by hidden Phase 0 work + Inter font phantom + 9-state row tokens. Truth respected over optimism. |

### Implicit decisions (CTO autonomous, embedded in plan)

| ID | Decision |
|---|---|
| D-A | **Phase 0 (1.5d) injected** before Phase 1A — foundation tokens + Inter bundle + window min size + 4 row state tokens. |
| D-B | **Mockup overrides for spec hidden defaults** kept where mockup UX is better (e.g., Tip card visible despite spec §6 hidden-default). |
| D-C | **All hardcoded copy literals refactored to BrandConfig getters** (e.g., "15 lượt" → `BrandConfig.freeDailyDownloads`). New `int get freeDailyDownloads` getter added to BrandConfig. |
| D-D | **CI dual-brand build gate** in Phase 0 + Buffer (`flutter build --dart-define=BRAND=svid|vidcombo` smoke). |
| D-E | **Feature flag pattern** brand-conditional: `homeV2Enabled` returns `false` for VidCombo until v2.1 cycle. |
| D-F | **Migration discipline**: single commit renames v15→v19 cascade in 6 places + CHANGELOG entry. |

---

## Implementation pivot — V2 augments v1 (not replaces)

Recorded after the runtime sessions on 2026-05-05.

The original Pass 2F hyper-plan called for `SmartInputBar` to replace
`GlassmorphismHeader` behind a `FeatureFlags.homeV2Enabled` gate. After
testing the gate-off pattern (Chairman couldn't see V2 changes; "code
ẩn" trap), the executable strategy shifted to:

- **V2 features ship unconditionally** by augmenting
  `glassmorphism_header.dart` (smart classify routing, adaptive CTA
  label, sheet routing, validator simplification).
- **Right-rail rewrite** drops Session Pulse / Storage / Commands and
  rebuilds the QuickStartPanel per V2 mockup (3-card layout —
  onboarding + platform shortcuts grid + tip).
- **Clipboard auto-extract** removed (perf bug — double yt-dlp).
- **`SmartInputBar` + 4 sub-widgets + `customize_preferences_provider`**
  kept as dormant scaffold (annotated in source). Re-attached if the
  team revives the full-replacement V2 home in a future cycle.
- **`FeatureFlags.homeV2Enabled`** kept as rollback safety net + the
  brand-conditional contract for VidCombo (which stays on v1.x until
  v2.1 — Q13 HYBRID strategy).

Do NOT reflex-delete the dormant scaffold or feature_flags. If the
team explicitly abandons the SmartInputBar path, update this section
before deletion.

## Corrections (post-locking)

| ID | Original | Correction | Source |
|---|---|---|---|
| Q-D-C(VidCombo) | "BrandConfig.freeDailyDownloads VidCombo=10 per CLAUDE.md" | **VidCombo=15 to match production reality.** `PremiumLimits.freeDailyDownloads = 15` was deliberately unified across both brands (see entity comment line 13). CLAUDE.md flutter-frontend rule "VidCombo=10" is stale doc. Code wins. | Phase 1A audit, commit f54... |

---

## Decisions explicitly NOT made (would be premature)

- VidCombo v2.1 visual design choices (defer to that cycle)
- Specific telemetry analytics provider (existing Sentry — no choice needed)
- Drag-reorder library choice for §10.4 (`flutter_reorderable_list` mentioned, will validate at impl time)
- Rollback rate threshold for "rollback alarm" (defer to release readiness review)

---

## Rules of engagement (going forward)

1. **CTO decides**, Chairman + CEO Kỳ react as user voice.
2. **No options spinning** — em chooses, ships, gets feedback.
3. **No "should I X or Y" questions** to Chairman unless decision impacts product strategy or business commitment.
4. **Veto path**: Chairman can override any CTO decision; em update this doc + adjust plan.
5. **Spec conflicts** with this doc → this doc wins (CEO Kỳ's spec is reference, CTO is execution authority).
