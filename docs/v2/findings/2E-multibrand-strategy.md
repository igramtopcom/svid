# Pass 2E — Multi-brand Strategy (VidCombo Gap)

**Mục tiêu**: Resolve "3 doc CEO Kỳ zero mention VidCombo" gap. Chốt ship strategy + audit từng surface multi-brand.
**Cross-ref**: Pass 2A (BrandConfig audit), Pass 2C (risk register), CLAUDE.md flutter-frontend rules, CLAUDE.md brand-config rules.

---

## 1. Executive summary (TL;DR)

1. **🔴 Reality check**: V2 specs (3 doc) **HOÀN TOÀN Svid-only**. ZERO mention VidCombo, Arctic Blue, DM Sans, 10-quota. Thực thi nguyên xi sẽ phá VidCombo (50k devices, 25× Svid user base).

2. **🟢 Architecture đã chuẩn bị tốt**: `BrandConfig` 805 dòng đã 100% multi-brand-aware (33 fields per brand). 8 surface (color, font, theme mode, shape radius, elevation, gradient, glow, license pattern) đã divergence-ready.

3. **🟢 EM CHỌN strategy (D) HYBRID**: V2 ship **Svid first** (v2.0.0), VidCombo continues **v1.x home** với feature flag brand-conditional. VidCombo migrate v2 ở **release cycle kế tiếp (v2.1.0)** sau Svid stable.
    - Lý do: Spec author (anh Kỳ) intent Svid-first; respect requirement. Risk control: VidCombo 50k users không risk regression. QA scope manageable (1 brand at a time). Code path identical, chỉ flag toggle.
    - **CTO autonomous decision** — em không cần Chairman approve, but anh có thể veto.

4. **🟠 6 multi-brand work surface phải address khi triển khai Svid V2**:
    - Hardcoded copy strings → `BrandConfig` getter pattern (esp. "15 lượt tải" → `BrandConfig.freeDailyDownloads`)
    - DM Sans bundle (deferred to VidCombo cycle, but verify Inter migration không break VidCombo current build)
    - Theme mode default check (Svid dark → V2 layout; VidCombo light → existing v1 home, no V2 yet)
    - Card radius respect BrandConfig (3px Svid vs 12px VidCombo — V2 components must use `BrandConfig.current.cardRadius` không hardcode)
    - Free-tier banner brand-aware (15 vs 10)
    - Feature flag `homeV2Enabled` brand-conditional rollout

5. **🟢 Risk register update**: 4 new rows (Pass 2C đã add 4, Pass 2E formalize):
    - VidCombo regression during V2 development
    - V2 spec hardcoded Svid copy leak
    - VidCombo light-mode V2 missing (deferred)
    - DM Sans bundle deferred (current VidCombo build also has phantom DM Sans)

---

## 2. BrandConfig divergence map — current state

| Surface | Svid (Nocturne Cinematic) | VidCombo (Arctic Command) | V2 spec impact |
|---|---|---|---|
| Brand color | Wine Red `#8D021F` / `#BF2D4A` / `#5E0115` | Arctic Blue `#0066CC` / `#03BEFE` / `#0041CC` | Spec v1.2 say "Wine Red" — auto-overridden via `BrandConfig.current.colors.brand` for VidCombo ✅ |
| Accent highlight | Crimson `#C41E3A` | Cyan `#03BEFE` | OK |
| Font family | `Inter` (phantom — pubspec not wired) | `DM Sans` (phantom — also not wired) | 🔴 Both phantom currently. Svid V2 fixes Inter; VidCombo DM Sans fix deferred |
| Card radius | 3px (angular) | 12px (frosted glass) | Spec default 8px — must use `BrandConfig.current.cardRadius` not spec literal |
| Button radius | 3px | 999px (pill) | Spec various — same pattern |
| Card elevation | 0 (flat) | 2 (lifted) | Spec elevation tokens — must respect `BrandConfig.cardElevation` |
| `hasCardBorder` | true (flat needs borders) | false (elevation defines edges) | UI design must check |
| Default theme mode | `dark` | `light` | V2 spec doesn't mandate; both must work |
| License key pattern | `SVID-XXXX-...` | 32 hex OR `VIDCOMBO-XXXX-...` | Backend layer — V2 không touch |
| Backend type | Go (api.svid.app) | PHP (api.vidcombo.net) | Backend layer — V2 không touch |
| Free daily quota | 15 | 10 | Spec §7 hardcode "15" — MUST refactor `BrandConfig.freeDailyDownloads` getter |
| Bundle ID | `com.svid.app` | `com.tinasoft.vidcombo` | OS layer — V2 không touch |

**Verdict**: 12 fields divergence. **9 fields auto-handle** via existing `BrandConfig` getter pattern. **3 fields hidden** (free quota copy, font bundle, theme mode default-aware UI). → V2 implementation must audit + refactor these 3.

---

## 3. Strategy options matrix

| Option | Description | Pros | Cons | Em verdict |
|---|---|---|---|---|
| **A** Svid-only ship v2.0.0 | Spec compliance, VidCombo continues v1.x indefinitely | Fast, spec aligned | VidCombo never gets V2 — bad long-term | ❌ |
| **B** Song song ship | V2 cả Svid + VidCombo cùng v2.0.0 | Single release cycle | 2× QA, 2× regression risk, spec doesn't cover VidCombo | ❌ |
| **C** Extend spec first | Wait anh Kỳ ship VidCombo specs, then implement both | Most thorough | Block timeline indefinitely; CEO bandwidth | ❌ |
| **D** **HYBRID** | Svid v2.0.0 first (3 weeks dev). VidCombo v2.1.0 after Svid stable (+1 cycle, ~2 weeks port) | Risk control, spec-aligned, sustainable | VidCombo waits 1 cycle | ✅ **Recommended** |

**Strategy (D) timeline**:
```
Week 1-7  : V2 dev Svid only (per Pass 2C realistic 36-37d single dev)
            VidCombo continues v1.x home — feature flag homeV2Enabled
            brand-conditional defaults (Svid=true, VidCombo=false)
Week 8    : Svid v2.0.0 ship public
Week 9-10 : Svid v2.0 stability monitor, hotfix if needed
Week 11-12: VidCombo V2 port (~2 weeks):
            - Branch from v2.0 stable
            - DM Sans bundle (~0.5d)
            - Arctic Blue visual review (~1d)
            - Light-mode V2 layout audit (~1d)
            - VidCombo-specific content (sites grid, copy tweaks?) (~1d)
            - Multi-brand smoke test 3 platforms (~1d)
            - Buffer/QA (~1.5d)
            - Total: 6d ≈ 1.5 weeks
Week 13   : VidCombo v2.1.0 ship public
```

→ **2 brand both V2 within 13 weeks** (3 months). Risk-controlled.

---

## 4. Svid V2 cycle — multi-brand audit per phase

### 4.1 Phase 0 (Foundation)

| Task | Multi-brand consideration |
|---|---|
| Wire pubspec `fonts:` Inter | 🟢 Svid only. VidCombo (DM Sans) deferred to v2.1 cycle. NOTE: VidCombo build hiện tại cũng phantom DM Sans — không degrade. |
| Remove `google_fonts` dep | 🟢 Both brands benefit (kill switch existed). |
| Create `design_tokens.dart` (8 classes) | 🟢 Generic — both brands use. |
| 4 row state tokens missing | 🟢 Apply to AppColors which delegates BrandConfig — both brands inherit. |
| Window min size OS layer | 🟢 Brand-agnostic. |

**Phase 0 multi-brand impact: nil.** Both brands benefit.

### 4.2 Phase 1A (Smart input + preset popover)

| Task | Multi-brand consideration |
|---|---|
| `SmartInputBar` widget | 🟢 Use `colorScheme.primary` (auto Wine Red Svid / Arctic Blue VidCombo) |
| `SmartCTAButton` blue → `AppColors.brand` | 🟢 OK |
| `CustomizeIconButton` | 🟢 OK |
| `PresetDropdownButton` chip "MP4·1080p" | 🟢 OK |
| `PresetPopover` | 🟢 OK |
| URL classifier | 🟢 Brand-agnostic. |
| Plan strip free-tier banner copy | 🔴 **MUST `BrandConfig.freeDailyDownloads`** getter, not hardcode "15" |
| Windows browser fallback | 🟢 Brand-agnostic. |
| Inter font bundle | 🟢 Svid only (VidCombo deferred) |
| Active preset deleted fallback | 🟢 Brand-agnostic logic (preset_id storage same). |

**Phase 1A multi-brand impact**: 1 hidden refactor (free-tier copy). 0.25d additional.

### 4.3 Phase §5 (FormatPreset 3-layer)

| Task | Multi-brand consideration |
|---|---|
| 6 built-in presets | 🟢 Same configs both brands (auto/1080p/720p/audio/4k/archive — universal) |
| EffectiveConfigResolver | 🟢 Brand-agnostic |
| Migration `v2_format_preset_migration.dart` | 🟢 Both brands existing format_presets schema same |

**Phase §5 multi-brand impact: nil.**

### 4.4 Phase 1B (Manager rows + 9 states)

| Task | Multi-brand consideration |
|---|---|
| 9 row state colors | 🟢 Use AppColors which delegates BrandConfig (warm rose for Svid, cool blue for VidCombo) |
| Filter popover | 🟢 OK |
| Sort dropdown | 🟢 OK |
| Tag chips | 🟢 OK |
| Watch progress overlay | 🟢 OK |
| Drag handle queued rows | 🟢 OK |

**Phase 1B multi-brand impact: nil.**

### 4.5 Phase 1C (Selection + bulk)

**Multi-brand impact: nil.** All brand-agnostic UI patterns.

### 4.6 Phase §10 (Playlist của tôi)

| Task | Multi-brand consideration |
|---|---|
| DB v18→v19 UserPlaylists tables | 🟢 Same schema both brands (database file `svid.db` vs `vidcombo.db` separate per BrandConfig.databaseName) |
| Domain entities + repo | 🟢 OK |
| Tab UI | 🟢 OK |
| Detail screen | 🟢 OK |
| Player integration | 🟢 OK |
| AddToPlaylistMenu | 🟢 OK |

**Phase §10 multi-brand impact: nil.** DB separation already handled by BrandConfig.

### 4.7 Polish phase

| Task | Multi-brand consideration |
|---|---|
| Dark mode tokens | 🟢 Both brands have darkColorScheme. |
| WCAG AA contrast verify | 🔴 Phải verify cả 2 brand (Svid dark Wine Red text contrast vs VidCombo dark Arctic Blue text contrast different) — but VidCombo deferred to v2.1, so Svid only this cycle. |
| Reduced motion | 🟢 Brand-agnostic. |
| i18n 2 lang (vi/en) | 🟢 Both brands share translation keys. |
| Performance indexes | 🟢 Brand-agnostic. |
| Telemetry | 🟢 Brand-agnostic (events go to same analytics). |
| What's new dialog | 🟠 Copy may differ per brand — but VidCombo doesn't get V2 yet, so Svid-specific copy OK. |

**Polish multi-brand impact: nil for Svid v2.0 cycle.**

### 4.8 Buffer phase

| Task | Multi-brand consideration |
|---|---|
| Manual QA | 🔴 **MUST run BOTH brands**: Svid (V2 home) + VidCombo (v1.x home, verify feature flag works, no regression). |
| Migration smoke test | 🔴 Both brands DB upgrade v18→v19 (UserPlaylists tables exist but unused for VidCombo until v2.1) |
| Internal dogfooding | 🟢 Svid only |
| Bug triage | 🟢 Svid only |
| Release notes | 🟢 Svid only |

**Buffer multi-brand impact**: ~0.5d for cross-brand QA (Pass 2C already noted hidden 0.5d).

---

## 5. Feature flag rollout strategy

| Flag | Default value Svid | Default value VidCombo | Lifecycle |
|---|---|---|---|
| `homeV2Enabled` | `false` (alpha→beta→public) | `false` (always until v2.1 port) | Svid: flip to `true` at public release. VidCombo: stays `false` until v2.1. |
| `playlistContextEnabled` | `false` (until §10 ships) | `false` (always until v2.1) | Svid: flip to `true` after Phase §10 + integration tests pass. |

Implementation pattern:
```dart
// lib/core/feature_flags.dart (NEW)
class FeatureFlags {
  static bool get homeV2Enabled {
    // Brand-conditional default
    if (BrandConfig.current.brand == Brand.vidcombo) return false;
    // Svid: respect remote flag from backend OR local override
    return _remoteFlag('home_v2_enabled') ?? _kSvidV2DefaultEnabled;
  }
}
```

Rollback path: `_kSvidV2DefaultEnabled = false` flips entire Svid back to v1.x home in 1 hotfix release.

---

## 6. VidCombo V2 cycle (v2.1.0) — pre-spec'd plan

When Svid V2 stable (~week 9), em propose:

### 6.1 Tasks (~6d total)

| # | Task | Effort |
|---|---|---|
| 1 | Branch `feat/v2-vidcombo-port` from Svid v2.0 stable tag | 0.25d |
| 2 | Bundle DM Sans variable font (`assets/fonts/DMSansVariable.ttf` + license) | 0.5d |
| 3 | Wire pubspec.yaml `fonts:` for DM Sans (along with Inter) | 0.25d |
| 4 | Visual review V2 layout in VidCombo Arctic Blue light-mode default | 1d |
| 5 | Audit hardcoded copy strings cho VidCombo divergence (10 vs 15 quota, brand name in copy) | 0.5d |
| 6 | VidCombo-specific content tweaks (popular sites grid: same 9 sites? brand name in onboarding?) | 0.5d |
| 7 | Cross-brand smoke test (Svid + VidCombo on macOS/Windows/Linux) | 1d |
| 8 | Buffer/QA + release notes | 1.5d |
| 9 | Flip `homeV2Enabled` brand-conditional default for VidCombo to `true` | 0.25d |

**Total**: 5.75d ≈ 1.5 weeks single dev.

### 6.2 VidCombo Arctic Blue dark-mode validation

Pass 2A + BrandConfig confirm VidCombo `darkColorScheme` exists with primary `#8DD6FF`. V2 spec dark mode tokens applied via BrandConfig.current → Arctic Blue auto-tinted dark surface. **Should "just work"** with light-mode default.

### 6.3 DM Sans bundle source

DM Sans variable font available from Google Fonts: https://fonts.google.com/specimen/DM+Sans
- Variable file: `DMSans[opsz,wght].ttf` (~310KB)
- License: SIL OFL ✓
- Anh Kỳ chưa pull — em sẽ wait until v2.1 cycle to pull (avoid premature commitment)

---

## 7. Risk register Pass 2E additions

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| **Hardcoded copy strings leak Svid context** (vd "Bạn còn 15..." literal) | High | Medium | Audit Phase 1A for `BrandConfig.freeDailyDownloads` usage, lint rule check no "15" / "10" literals in V2 widgets |
| **VidCombo regression during Svid V2 dev** (shared core code) | Medium | High | CI gate: build cả 2 brand with `--dart-define=BRAND=svid|vidcombo`, smoke test both each PR |
| **VidCombo missing V2 user complaint** | Low | Low | Communicate to anh Kỳ: "VidCombo V2 ships v2.1, ~2 weeks after Svid v2.0" |
| **DM Sans bundle deferred — VidCombo current also phantom font** | Low | Low | Existing behavior unchanged; v2.1 cycle fix both. Note: macOS DM Sans NOT system-native, VidCombo Mac users currently fallback to system font silently |
| **Light mode V2 layout breaks for VidCombo** (V2 designed dark-first) | Medium | Medium | v2.1 visual audit pass (1d), fix tokens that don't translate light |
| **Card radius 12px frosted (VidCombo) vs spec 8px default may visually clash** | Low | Low | V2 components use `BrandConfig.current.cardRadius` NOT spec literal — pre-handled |

---

## 8. Decisions Pass 2E resolves (CTO autonomous)

| ID | Resolution |
|---|---|
| Q13 (Pass 2C) — Multi-brand release schedule | **Strategy (D) HYBRID**. Svid v2.0.0 first, VidCombo v2.1.0 +1 cycle (~2 weeks). |
| Q11 (Pass 2C) — Single dev or 2+ dev parallel | Em recommend **2-dev parallel** for Svid V2 cycle (Track A + B), saves ~12d. VidCombo v2.1 single-dev (small port). |
| Phase 1A free-tier copy refactor | Add 0.25d task to Phase 1A: refactor "15 lượt" → `BrandConfig.freeDailyDownloads` getter |
| CI multi-brand build gate | Em add to Phase 0 / Buffer phase: `flutter build` cả 2 brand |

→ Cumulative open Q for Chairman: Q1-Q6 (Pass 2A), Q8 (i18n), Q14 (timeline accept).

---

## 9. Status sau Pass 2E

| ✓ | Hoàn thành |
|---|---|
| ✅ | Confirm 3 doc CEO Kỳ ZERO VidCombo mention |
| ✅ | BrandConfig 12-field divergence map |
| ✅ | 4 strategy options analyzed |
| ✅ | **Strategy (D) HYBRID chosen** — Svid v2.0 first, VidCombo v2.1 +1 cycle |
| ✅ | Per-phase multi-brand audit (Phase 0/1A/§5/1B/1C/§10/Polish/Buffer) |
| ✅ | 1 hidden Phase 1A refactor identified (free-tier copy) |
| ✅ | Feature flag rollout strategy (homeV2Enabled brand-conditional) |
| ✅ | VidCombo v2.1 pre-spec'd plan (5.75d) |
| ✅ | Risk register +6 multi-brand-specific rows |
| ✅ | All Pass 2E decisions CTO-autonomous |

| ⏳ | Pending |
|---|---|
| ⏳ | Pass 2F — Hyper-plan synthesis (consolidate 2A+2B+2C+2D+2E into single executable plan with timeline + file delta + decision queue) |
