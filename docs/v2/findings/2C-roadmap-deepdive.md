# Pass 2C — Implementation Roadmap Deep Dive

**Spec đọc**: `docs/SSvid_v2_Implementation_Roadmap.md` v1.0 (513 dòng) — full
**Cross-ref**: Pass 2A findings (Design Spec) + Pass 2B findings (UI Spec) + master_roadmap CEO Kỳ
**Mục tiêu**: Validate 28.5-31.5d ước lượng vs reality, identify hidden work, fix schema rename, plan parallel execution.

---

## 1. Executive summary (TL;DR)

1. **🟢 Roadmap structure tốt**: 7 phase với Files/Tasks/Test Plan/Acceptance/Risks per phase. Track A/B/C parallel work map. Feature flag rollout (`homeV2Enabled`, `playlistContextEnabled`). Rollback plan giữ v1 code path 1 release cycle.

2. **🔴 Phase 1A Task 16 LIE**: Roadmap claim "Inter font bundle ✅ DONE in design spec v1.1 commit" và "Registered in pubspec.yaml under flutter.fonts:". **Pass 2A xác nhận**: pubspec L171-180 fonts section đang COMMENTED PLACEHOLDER. Bundle CHƯA xảy ra. Roadmap text outdated/incorrect.

3. **🔴 DB schema rename cascade**: Spec/Roadmap reference `v15 → v16` migration file `v16_user_playlists.dart` ở **6 vị trí**. Reality `schemaVersion = 18`. **Phải rename → v19** + sync 4 doc places + 2 code references.

4. **🟢 F3 saving 0.5d**: Phase §10.6 (2d) — Pass 2B audit `PlaybackQueueService` đã 80% sẵn sàng. Realistic 1.5d. → Phase §10 cut từ 10d → 9.5d.

5. **🟠 Hidden Phase 1A foundation work +1-1.5d**: Pass 2A flag 2 blocks (`design_tokens.dart` missing + 4 row state tokens missing). Roadmap KHÔNG list những tasks này explicit. → Real Phase 1A: 6.5 + 1.5 = **8d**.

6. **🟠 Polish 2-3d quá lạc quan**: 7 task gồm 5-lang i18n (~30 keys × 5 = 150 strings ≈ 1d) + dark mode tokens + WCAG verify + perf indexes + telemetry. Realistic 3.5-4d.

7. **🟠 i18n 5-lang vs 2-lang reality**: Roadmap multi-mention `vi/en/ja/pt/es`. Reality `assets/translations/{vi,en}.json` only. → **Confirm Q8 Pass 2B: cut V2 to 2 lang**, defer ja/pt/es to v2.1. Saves Polish 0.5d.

8. **🟠 Phase 1C "Thêm vào playlist" dependency on §10**: Phase order 1A→§5→1B→1C→§10. 1C ships BEFORE §10. Roadmap risk-mitigates "stub if needed". → Em đề xuất alternative: ship 1C với 4 bulk actions (drop "Thêm vào playlist" cho đến §10 done) — cleaner UX.

9. **🔴 Multi-brand: ZERO mention trong Roadmap**. 6 risk rows, 0 về VidCombo. → Pass 2E sẽ handle nhưng cần add row vào risk register.

10. **🟢 Realistic re-estimate**:
    - Single dev: **30-34d ~6-7 tuần** (vs spec 28.5-31.5d)
    - 2 dev parallel (Track A + B): **25-28d ~5 tuần**
    - 3 dev parallel (+ Track C): **22-25d ~4-4.5 tuần**

---

## 2. Phase-by-phase validation

### 2.1 Phase 1A — Smart input + preset popover (claimed 6.5d)

**Roadmap tasks**: 17 numbered items + 4 sub-tasks.

| Task # | Validation |
|---|---|
| 1-4 | InputType enum + UrlClassifierService + SmartInputProvider 500ms debounce + SmartCTAButton state machine | ✅ Reasonable. ~1d. |
| 5-7 | PresetDropdownButton + PresetPopover (UI only, stub for §5) + 5 submit handlers (existing sheets reused) | ✅ Reasonable. ~1d. |
| 8 | CustomizeIconButton (Tier 1) — visibility/disabled logic + DownloadConfigDialog one-shot | ✅ ~0.5d. |
| 9 | Tier 2 toggle + `*` indicator | ✅ ~0.5d. |
| 10 | Rule chain in home_download_mixin (Rule 4 / 3' / 3) | ✅ ~0.5d. Pass 2B đã map exact 150-line refactor. |
| 11 | Active preset deleted fallback | ✅ ~0.25d. |
| 12-14 | DownloadConfigDialog batch context extension (3 params + uncheck warning + Tier 2 batch interaction) | 🟠 ~1d. Roadmap underestimate — `DownloadConfigDialog` hiện tại 499 dòng (Pass 1 audit), batch extension non-trivial. |
| 15 | Windows browser fallback (url_launcher) | ✅ ~0.25d. |
| **16** | **"Inter font bundle ✅ DONE"** | 🔴 **FALSE**. Pass 2A reality: pubspec fonts section commented, `assets/fonts/InterVariable.ttf` mới pulled chưa wired, `google_fonts ^6.3.2` dependency vẫn còn. **Hidden work**: actually register pubspec, remove google_fonts dep, smoke test 3 platforms. ~0.5-1d. |
| **HIDDEN** | **`lib/core/design/design_tokens.dart` 8 class** (Pass 2A Block #2) | 🔴 Roadmap không list. ~1d cho 8 class skeleton + migration starter widgets. |
| **HIDDEN** | **4 row state tokens missing trong `AppColors`** (`postProcessing` container, `pending` pair, `waitingForNetwork` pair) | 🟠 Phase 1B sẽ touch row colors but token foundation thuộc Phase 1A. ~0.25d. |
| 17 | Total estimate update | (admin) |

**Phase 1A real estimate**: 6.5d (claim) + 1.5d (hidden) = **8d**

### 2.2 Phase §5 — FormatPreset 3-layer (claimed 6d)

| Task # | Validation |
|---|---|
| 1 | Extend FormatPreset (15 fields, backward-compat JSON parse) | ✅ ~1d. Spec §17.2 ship template. |
| 2 | Define 6 built-in presets | ✅ ~0.5d. |
| 3 | BuiltinPresetsSeeder (idempotent) | ✅ ~0.5d. |
| 4 | EffectiveConfigResolver (3-layer merge, 15+ fields) | 🟠 ~2d. Roadmap đúng — 15-field merge logic phức tạp, edge cases (null inheritance, container/codec compat matrix). |
| 5 | Modify Rule 3 in home_download_mixin | ✅ ~0.5d. Pass 2B map ~30 lines change. |
| 6 | Rule 4 row action "Tuỳ chỉnh cho lần này" | ✅ ~0.5d. |
| 7 | PresetPopover UI wiring | ✅ ~1d. |
| **HIDDEN** | **DTO migration `v2_format_preset_migration.dart` adopt + wire main.dart** | 🟠 Roadmap list ở Files-to-create nhưng KHÔNG list trong Tasks. ~0.5d. |

**Phase §5 real estimate**: 6d ✅ (hidden migration task fits within estimate)

### 2.3 Phase 1B — Manager rows + 9 states + filter (claimed 4d)

| Task # | Validation |
|---|---|
| 1-3 | DownloadRow base + 9 state widgets + per-state metadata/action/visual | 🟠 ~2.5d. 9 states × 0.25d = 2.25d, đủ cover variant audio + image rows. |
| 4 | i18n update "Đã hoàn thành" → "Đã tải" + new state labels | ✅ ~0.25d (cut to 2 lang). |
| 5-6 | FilterPopover + filter badge | ✅ ~0.5d. Existing `filter_chips.dart` 231 dòng base. |
| 7 | SortDropdown 6 options | ✅ ~0.25d. |
| 8 | Tag chip inline display | ✅ ~0.25d. Phase 73.4 integration đã done. |
| 9 | Watch progress overlay | ✅ ~0.25d. Phase 22 integration đã done. |
| 10 | Drag handle queued rows | ✅ ~0.25d. Phase 73 integration đã done. |

**Phase 1B real estimate**: 4d ✅ (matches claim, integrations from Phase 22/73 reduce risk)

### 2.4 Phase 1C — Selection + bulk (claimed 4-5d)

| Task # | Validation |
|---|---|
| 1-7 | SelectionProvider + checkbox visibility + range/all/esc + 5-action toolbar | ✅ ~2.5d. |
| 8 | Mixed-state handling | ✅ ~0.25d. |
| 9 | BulkDeleteConfirmDialog 2 options | ✅ ~0.25d. |
| 10 | BulkActionService.execute() — 4 actions (Phát, Xoá, Khác, Huỷ) | ✅ ~1d. |
| **DEPENDENCY** | **Action 5 "Thêm vào playlist" depends on §10** | 🟠 Roadmap mitigation = stub. Em đề xuất: **drop action ra v1, ship 4 actions, add lại sau §10 hoàn**. Cleaner UX. |
| 11 | Keyboard shortcuts (Cmd+A, Esc, Shift+Click, Cmd/Ctrl+Click, Delete) | ✅ ~0.5d. |

**Phase 1C real estimate**: 4d (drop "Thêm vào playlist" stub) hoặc 5d (giữ stub) ✅

### 2.5 Phase §10 — Playlist của tôi + player (claimed 10d, 8 sub-phases)

| Sub-phase | Validation |
|---|---|
| §10.1 DB + Domain (1.5d) — `v16_user_playlists.dart` | 🔴 **RENAME `v19_user_playlists.dart`** + DAO. ~1.5d. |
| §10.2 Repository + 6 use cases (1d) | ✅ ~1d. |
| §10.3 Tab + List UI (2d) | ✅ ~2d. |
| §10.4 Detail screen (1.5d) | ✅ ~1.5d. Drag reorder via existing `flutter_reorderable_list` (or similar). |
| §10.5 Dialogs (1d) | ✅ ~1d. 4 dialogs. |
| **§10.6 Player integration (2d)** | 🟢 **CUT 1.5d** — Pass 2B audit PlaybackQueueService đã có setQueue/playNext/next/previous/repeat/shuffle/hasNext/hasPrevious. Chỉ cần: PlayerNotifier.playlistContext field + UI Next/Previous buttons + auto-next bind to repeatAll mode. |
| §10.7 Bulk action wiring (0.5d) | ✅ ~0.5d. Conditional khi 1C giữ stub. **Skip nếu 1C drop action**. |
| §10.8 Tests (1.5d) | ✅ ~1.5d. |

**Phase §10 real estimate**: 9.5d (cut F3 0.5d) **OR** 9d (cut F3 + skip §10.7 nếu 1C drop) ✅

### 2.6 Polish phase — Dark mode + a11y + i18n + perf (claimed 2-3d)

| Task | Validation |
|---|---|
| 1 Dark mode tokens applied to all new widgets | ✅ ~0.5d (BrandConfig.darkColorScheme đã có). |
| 2 WCAG AA contrast verify | ✅ ~0.5d (existing `app_colors.dart` đã WCAG AA per inline comments). |
| 3 Reduced motion respect | 🟠 ~0.5d (audit + fix MediaQuery.disableAnimations). |
| 4 i18n complete 5 langs ~30 new keys | 🔴 **5 lang × 30 keys = 150 strings = 1d min**. Cut to 2 lang giảm 0.5d. |
| 5 Performance (virtualization + 3 indexes + debounce verify) | ✅ ~0.5d. |
| 6 Telemetry events §18 (10 events) | ✅ ~0.5d. |
| 7 "What's new" dialog v2.0 first launch | ✅ ~0.25d. |

**Polish real estimate**: 3.25d (5 lang) hoặc **2.75d (2 lang)** 🟠

### 2.7 Buffer phase — QA + bug fix (claimed 3d)

| Activity | Validation |
|---|---|
| Manual QA against qa_checklist | ✅ |
| Internal dogfooding 1-2d | ✅ |
| Bug triage + fix | ✅ |
| Release notes draft | ✅ |
| Migration smoke test (v1.x DB → v2 startup) | ✅ |
| **HIDDEN** | **v2.0 → v1.x rollback test** (Q10 Pass 2B) | 🟠 ~0.5d. Add to QA checklist. |
| **HIDDEN** | **Multi-brand smoke test (VidCombo)** | 🔴 Phải có. ~0.5d. |

**Buffer real estimate**: 3d ✅ (within estimate, hidden tests fit slack)

---

## 3. Schema rename cascade — files cần sync

| Reference | Current text | Update to |
|---|---|---|
| Roadmap §10.1 file | `v16_user_playlists.dart` | `v19_user_playlists.dart` |
| Roadmap §10.1 schema check | "matches Downloads.id autoIncrement int" | (no change, still correct) |
| Roadmap risk register row 2 | "v16 conflicts with concurrent v15 work" | Risk obsolete (v15 already shipped past) → DELETE row OR replace with "v19 idempotency vs forced re-migration" |
| UI Spec §10.1 caption | "Database schema (Drift v16)" | "Database schema (Drift v19)" |
| UI Spec §17.1 step 1 | "DB migration v15 → v16" | "DB migration v18 → v19" |
| Code feature flag | `playlistContextEnabled` | (no change — flag name OK) |

→ Em note để Pass 2F hyper-plan capture all 6 places.

---

## 4. Realistic timeline matrix

### 4.1 Single developer

| Phase | Claim | Real | Δ |
|---|---:|---:|---:|
| 1A Smart input | 6.5d | **8d** | +1.5 (hidden foundation) |
| §5 Preset 3-layer | 6d | 6d | 0 |
| 1B Manager rows | 4d | 4d | 0 |
| 1C Selection bulk | 4-5d | 4d | -0.5 (drop playlist stub) |
| §10 Playlist + F3 | 10d | **9d** | -1 (F3 cut + skip §10.7 stub) |
| Polish | 2-3d | **2.75d** | -0.25 (cut to 2 lang) |
| Buffer | 3d | 3d | 0 |
| **Total** | **28.5-31.5d** | **36.75d** | **+5.25d** |

→ **Single dev realistic: 36-37 working days ~7-7.5 tuần**.

### 4.2 Parallel work (2 dev)

Track A (UI/UX): 1A → 1B → 1C → Polish → Buffer
Track B (data): §5 (overlap 1A) → §10 (start week 2)

```
Week 1: A=1A(8d)  /  B=§5(6d, finish ahead)
Week 2: A=1A finish → 1B(4d)  /  B=§10.1-10.2 (2.5d) → §10.3 (2d)
Week 3: A=1C(4d)  /  B=§10.4-10.5 (2.5d) → §10.6(1.5d)
Week 4: A+B merge §10.7 (skip if drop) + §10.8 tests(1.5d) + Polish(2.75d)
Week 5: Buffer(3d)
```

→ **2-dev realistic: 25-28d ~5 tuần**.

### 4.3 Parallel work (3 dev)

Add Track C: §10 entirely — start week 1 since DB independent.

→ **3-dev realistic: 22-24d ~4-4.5 tuần**.

---

## 5. Phase-1A entry criteria (foundation tokens MUST go first)

Em propose adding mini "Phase 0" trước Phase 1A để clean foundation:

```
Phase 0 — Foundation (1-1.5d, MUST run before Phase 1A)
├── Task 0.1: Wire pubspec.yaml fonts section (Inter bundle)
├── Task 0.2: Remove google_fonts ^6.3.2 dependency + verify no call sites
├── Task 0.3: Smoke test Inter render on 3 platforms (macOS native fallback,
│             Windows fresh install, Linux Cantarell fallback)
├── Task 0.4: Create lib/core/design/design_tokens.dart with 8 classes
│             (AppSpacing/Radius/Shadow/Motion/IconSize/ComponentSize/
│              Breakpoint/MinWidth)
├── Task 0.5: Add 4 missing row state token sets to AppColors
│             (postProcessing container, pending pair, waitingForNetwork pair,
│              + verify dark variants)
└── Task 0.6: Wire window min size (lib/core/window_size.dart) to OS layer
              (MainFlutterWindow.swift / win32_window.cpp / Linux equivalent)
```

→ Phase 0 = 1-1.5d. Removes hidden work from Phase 1A. Clean separation: foundation → features.

**Updated phase order**: **Phase 0 → 1A → §5 (overlap) → 1B → 1C → §10 → Polish → Buffer**

---

## 6. Risk register augmentation

| Original risk | Status |
|---|---|
| §5 backward-compat breaks existing FormatPreset | Mitigation strong (§17.2 spec template) ✅ |
| §10 DB migration v16 conflicts v15 | 🔴 **OBSOLETE** — v15 đã ship, target rename v19. Replace with: "v19 migration vs running v18 user data — verify idempotent + reversible" |
| Player queue refactor breaks single-track | Mitigated by feature flag ✅ |
| Translation gaps 5 lang overflow | Reduced by cutting to 2 lang ✅ |
| Performance regression 1000+ items | Mitigated by virtualization + indexes ✅ |
| Per-platform pref auto-save flow | KHÔNG đổi (Rule 2 untouched) ✅ |

| **NEW risks Pass 2C identified** |
|---|
| **🔴 Multi-brand parity (VidCombo)** — V2 tokens/font/quota assume SSvid only. Risk HIGH that VidCombo test ship breaks. → Mitigation Pass 2E: explicit brand audit per phase + multi-brand smoke test in Buffer. |
| **🟠 Phantom Inter font silent regression** — Existing macOS users using system Inter, switch to bundle may render slightly different (kerning, metrics). → Mitigation: visual diff before/after on 3 weights × 3 platforms. |
| **🟠 Spec/code v15→v19 confusion** — multiple devs may grep "v16 user playlists" and miss the rename. → Mitigation: rename ALL occurrences in 1 commit, add CHANGELOG entry. |
| **🟠 EffectiveConfigResolver merge edge cases** — 15-field merge with null inheritance has combinatorial test surface. → Mitigation: dedicated unit test matrix (≥30 cases), ship as separate PR before integrating Rule 3. |

---

## 7. Rollout strategy refinement

Roadmap section "Rollout strategy" tốt nhưng thiếu detail:

1. **Internal alpha (after Phase 1A+§5)**: feature flag `homeV2Enabled=false` default. Dev team toggles ON. **Verify**: rollback flag → no crash on existing data.
2. **Internal beta (after Phase 1B+1C)**: extended team dogfood. Add: telemetry verify events fire, perf metrics baseline.
3. **Closed beta (after §10)**: ~50 invite users. Add: backend feature flag remote toggle (kill switch nếu critical bug).
4. **Public release (after Polish+Buffer)**: feature flag flip default ON. **Multi-brand**: ship SSvid first, VidCombo 1 release cycle later (per Pass 2E recommendation).
5. **Rollback**: keep v1 home code path 1 release cycle. Definition: if rollback rate >5% → re-investigate.

---

## 8. Decisions/answers Pass 2C resolves (no Chairman input needed)

| ID | Resolution |
|---|---|
| Q7 (Pass 2B) | Schema rename `v15→v16` → `v18→v19` in 6 places. CTO autonomous fix. |
| Phase 1C playlist action stub | Em đề xuất **drop action ra v1**, ship 4 bulk actions. Add "Thêm vào playlist" sau §10 done. CTO autonomous decision (UX cleaner). |
| Hidden Phase 0 foundation | Em đề xuất **inject Phase 0 (1-1.5d)** trước Phase 1A. CTO autonomous. |
| Polish 2-3d | Em đề xuất **2.75d cho 2-lang scope** (depends on Q8 Chairman). |

---

## 9. Decisions cần Chairman + anh Kỳ chốt (cumulative Q1-Q14 sau Pass 2A+2B+2C)

Em compile lại tất cả Q hiện tại + thêm Q11-Q14 mới:

| Q | Source | Domain |
|---|---|---|
| Q1-Q6 | Pass 2A | Tokens (Tailwind delete, type scale, VidCombo font, theme mode default, brand vs spec radius, MissionBriefing tokens) |
| Q7 | Pass 2B | Schema rename — **resolved CTO autonomous** |
| Q8 | Pass 2B | i18n 5→2 lang — **needs Chairman confirm before saving Polish 0.5d** |
| Q9 | Pass 2B | F3 1.5d vs 2d — **resolved (1.5d)** |
| Q10 | Pass 2B | Backward-compat rollback test — **resolved (yes, add to Buffer)** |
| **Q11 NEW** | Pass 2C | **Single dev or 2-dev or 3-dev parallel?** Em recommend 2-dev (25-28d, save ~12d vs single) |
| **Q12 NEW** | Pass 2C | **Phase 1C "Thêm vào playlist" — drop or stub?** Em recommend drop (cleaner UX) |
| **Q13 NEW** | Pass 2C | **Multi-brand release schedule** — SSvid first, VidCombo +1 cycle? **Pass 2E sẽ deep dive** |
| **Q14 NEW** | Pass 2C | **Roadmap timeline acceptance**: spec say 28.5-31.5d, em estimate 36-37d single (5-day delta). Anh accept timeline truth hay tighten scope? |

---

## 10. Status sau Pass 2C

| ✓ | Hoàn thành |
|---|---|
| ✅ | Đọc full Roadmap 513 dòng |
| ✅ | Validate 7 phase estimates against Pass 2A + 2B findings |
| ✅ | Identify Phase 1A Task 16 incorrect claim (Inter font) |
| ✅ | Identify hidden Phase 0 foundation work (1-1.5d) |
| ✅ | Schema rename cascade map (6 places) |
| ✅ | F3 saving 0.5d confirmed |
| ✅ | i18n 5→2 lang impact mapped |
| ✅ | Polish 2-3d → 2.75-3.25d realistic |
| ✅ | Buffer hidden tests fit within slack |
| ✅ | Realistic timeline matrix: 36-37d (1 dev) / 25-28d (2 dev) / 22-24d (3 dev) |
| ✅ | Risk register +4 new rows |
| ✅ | 4 new decisions (Q11-Q14) compiled |

| ⏳ | Pending |
|---|---|
| ⏳ | Pass 2D — Mockup audit (slim — Pass 2B already cleared major flag) |
| ⏳ | Pass 2E — Multi-brand strategy (P2C risk #1 dependent) |
| ⏳ | Pass 2F — Hyper-plan synthesis (combine 2A+2B+2C+2D+2E into single executable plan) |
