# Pass 2B — UI Spec v1.1 Deep Dive (Home + Download Manager)

**Spec đọc**: `docs/SSvid_Home_Download_Manager_UI_Spec_v1.1.md` v1.5 (1090 dòng) — full
**Code đối chiếu**: `format_presets_service.dart`, `home_download_mixin.dart`, `app_database.dart`, `collection_entity.dart`, `playback_queue_service.dart`, plus existing infrastructure
**Mục tiêu**: Map mỗi spec section ra existing code surface, identify exact build/refactor delta.

---

## 1. Executive summary (TL;DR)

1. **🔴 CRITICAL: Schema version mismatch (Pass 1 agent missed)**: Spec § 17.1 + roadmap đều say "DB migration **v15 → v16**" cho `UserPlaylists`. **Reality**: `app_database.dart:180 schemaVersion = 18`. Code đã trải qua v16 (tempDirPath line 79), v17 (ConversionJobs line 132), và đang ở v18. → Migration target **PHẢI là v19**, KHÔNG phải v16. Spec text outdated.

2. **🟢 F3 (Player queue) ~80% sẵn sàng — phát hiện thú vị**: `PlaybackQueueService` 263 dòng đã có **đầy đủ** setQueue/addToQueue/playNext/removeFromQueue/reorder/next/previous/jumpTo/peekNext + 3 repeat modes + shuffle + hasNext/hasPrevious. Spec §10.5 (2d estimate) chỉ cần: add `playlistContext` field vào `PlayerNotifier` + wire `setQueue` từ detail screen + UI Next/Previous buttons. **Có thể ship trong 1d**, không phải 2d.

3. **🟠 F1 (Preset 3-layer) ~30% sẵn sàng**: `FormatPreset` hiện tại 7 fields (NO id, NO UUID, NO isBuiltIn) vs spec 15 fields. Layer 1 PlatformQualityPreference đã có (Rule 2 wired). Layer 2 (active preset + currentConfig + 6 built-in seed) gần như KHÔNG có. Layer 3 SettingsState đã có. → 6.5d Phase 1A + 6d Phase §5 estimate **chính xác**, không thể giảm.

4. **🟠 F2 (Playlist của tôi) ~10% sẵn sàng**: DB tables (UserPlaylists + UserPlaylistItems), freezed entities, repository, use cases, screens, dialogs — TẤT CẢ phải build mới. **Đúng** §10.8 estimate 10d. Disambiguation với existing `CollectionEntity` (Smart Collections, filter-driven) đã clean ở §10.0.

5. **🟢 5-Rule chain refactor scope rõ**: `home_download_mixin.dart:437-490` `handleDownloadDecision` hiện có **Rule 1** (single item) + **Rule 2** (saved pref) ✓. Rule 3 (silent active preset), Rule 3' (popoverDeepCustomize toggle), Rule 4 (⚙️ click), Rule 5 (per-row retry) — TẤT CẢ chưa tồn tại. → 1 hàm refactor, ~150 dòng change.

6. **🟢 §17.2 Migration code template ready-to-use**: Spec đã ship gần-complete migration code (60 dòng). Em chỉ cần adopt + add UUID generation + wire vào `main.dart` startup.

7. **🟢 9 row states partially mapped**: Code có 5 status (`Active/Completed/Paused/Failed/Cancelled`). Thiếu `Downloading` (separate from generic Active), `PostProcessing` (token có nhưng container thiếu), `Pending`, `WaitingForNetwork`. → Phase 1B (4d) bổ sung 4 token sets + UI variant logic.

8. **🟢 Pass 1 mockup-vs-spec divergence flag REVISITED**: §2 Layout table list 5 tab (Trang chủ, Đăng ký, Chuyển đổi, Trình duyệt + Nâng cấp/Premium). Mockup ảnh anh Kỳ HOÀN TOÀN ALIGN với spec. Pass 1 agent đọc nhầm §3 chỉ 3 tabs. Resolution: **mockup ↔ spec hợp nhau**.

---

## 2. F1 — Preset 3-layer architecture deep map

### 2.1 Layer-by-layer audit

| Layer | Spec yêu cầu | Code reality | Gap |
|---|---|---|---|
| **Layer 1: PlatformQualityPreference** (auto, per-URL platform) | Map từ platform → quality + format options | ✅ `platformPreferencesProvider` ([home_download_mixin.dart:452-453](lib/features/home/presentation/screens/home_download_mixin.dart#L452)). Auto-save khi user explicit pick qua dialog (Rule 4 / 3'). Existing logic NO change cần. | ✅ Match |
| **Layer 2: Active FormatPreset + currentConfig** (manual, global) | `activePresetId` + `currentConfig` JSON SharedPreferences keys; 6 built-in seed | 🔴 `FormatPreset` 7 fields only, NO id, NO UUID, NO isBuiltIn flag. NO `activePresetId` concept. NO `currentConfig` override. NO 6 built-in seeding logic. `FormatPresetsNotifier` chỉ add/remove operations | 🔴 ~70% missing |
| **Layer 3: SettingsState global defaults** (codec, container, fps) | Fallback cho field nào FormatPreset không cover | ✅ `settings_provider.dart` có `preferredQuality`, `qualityFallbackEnabledProvider`. Code đã work | ✅ Match |
| **Resolver: `EffectiveDownloadConfigService.resolve(url)`** | Detect platform → merge L1 → L2 → L3 → DownloadConfig | 🔴 Service KHÔNG tồn tại. Logic merge phải build từ scratch | 🔴 100% missing |

### 2.2 FormatPreset schema diff

```
LEGACY (current — format_presets_service.dart:8-25):
  name, maxResolution, videoCodec, audioCodec, containerFormat,
  fpsPreference, createdAt
  → 7 fields, NO id, NO UUID

V2 SPEC (§5.3 + §17.2):
  + id (UUID v4)
  + audioOnly (bool)
  + audioBitrate (nullable int)
  + fallbackBehavior ('nearest' | 'higher' | 'block')
  + saveLocation (nullable string — null = global default)
  + isBuiltIn (bool — true = read-only, can clone)
  + subtitlesEnabled (nullable — null = inherit global)
  + embedThumbnail (nullable bool)
  + embedMetadata (nullable bool)
  + embedChapters (nullable bool)
  + schemaVersion (int — future migration tracking)
  → 15 fields total (8 mới)
```

### 2.3 Built-in seed (6 presets)

| ID | Tên | Config | Status |
|---|---|---|---|
| `auto` ⭐ default | Tự động (cao nhất) | `containerFormat: auto, maxResolution: 0, fallback: nearest` | 🔴 build new |
| `1080p_mp4` | 1080p MP4 | `mp4, h264, 1080p` | 🔴 build new |
| `720p_compact` | 720p tiết kiệm | `mp4, h264, 720p` | 🔴 build new |
| `audio_mp3_320` | Audio MP3 320k | `mp3, audioOnly: true, 320kbps` | 🔴 build new |
| `4k_max` | 4K cao nhất | `mp4, 2160p, fallback: nearest` | 🔴 build new |
| `archive` | Lưu trữ | `mkv, best, +sub +metadata +chapters` | 🔴 build new |

→ Tất cả `isBuiltIn: true`, có 🔒 icon, user CHỈ clone, không edit/delete.

### 2.4 Rule chain — current state vs spec

**Code hiện tại** ([home_download_mixin.dart:437-490](lib/features/home/presentation/screens/home_download_mixin.dart#L437)):

```
handleDownloadDecision(videoInfo):
  Rule 1: Single item                → auto-download ✅
  Rule 2: Saved per-platform pref    → auto-download with pref ✅
  Rule 3: (Multi-quality, no pref)   → showVideoDetailsModal()  ← post-extract picker
```

**Spec yêu cầu** (§5.5):

```
Rule 1: Single quality                                → auto (KHÔNG ĐỔI)
Rule 2: PlatformQualityPreference exists              → auto (KHÔNG ĐỔI)
Rule 3: No per-platform + popoverDeepCustomize=OFF   → silent với active preset (snackbar)
Rule 3' (NEW): No per-platform + popoverDeepCustomize=ON → DownloadConfigDialog
Rule 4 (NEW): User clicked ⚙️ icon trên action bar    → DownloadConfigDialog (highest priority)
Rule 5: User explicit "Tùy chỉnh" từ row sau download → per-row edit (riêng biệt)
```

**Refactor scope**: 1 hàm, ~150 dòng. Bỏ fallback dialog → silent download. Add 3 entry conditions (popoverDeepCustomize / ⚙️ pre-click flag / row-level edit). Logic:

```dart
Future<bool> handleDownloadDecision(VideoInfo info, {bool customizeRequested = false}) async {
  // Rule 4 (highest)
  if (customizeRequested) {
    final config = await DownloadConfigDialog.show(...);
    if (config == null) return false;
    return startDownloadWithConfig(info, config);
  }
  // Rule 1: KHÔNG ĐỔI
  if (info.availableQualities.length == 1) { ... }
  // Rule 2: KHÔNG ĐỔI
  if (savedPref != null && canApplySavedChoice(info)) { ... }
  // Rule 3' check
  if (popoverDeepCustomizeProvider.read()) {
    final config = await DownloadConfigDialog.show(...);
    if (config == null) return false;
    return startDownloadWithConfig(info, config);
  }
  // Rule 3: silent
  final effectiveConfig = await effectiveConfigResolver.resolve(info.url);
  AppSnackBar.success(message: 'Đang tải với ${activePreset.name}...');
  return startDownloadWithConfig(info, effectiveConfig);
}
```

---

## 3. F2 — Playlist của tôi deep map

### 3.1 Database schema (spec §10.1) vs code reality

| Element | Spec | Code reality | Action |
|---|---|---|---|
| **Schema version target** | `v15 → v16` | 🔴 `schemaVersion = 18` ([app_database.dart:180](lib/core/database/app_database.dart#L180)) | **PHẢI sửa target → v18 → v19** trong roadmap + spec |
| `Downloads.id` | `IntColumn autoIncrement` (existing) | ✅ `IntColumn().autoIncrement()` ([line 15](lib/core/database/app_database.dart#L15)) | Match |
| `UserPlaylists` table | TextColumn UUID id + name + description + coverPath + itemCount + totalDurationMs + createdAt + updatedAt | 🔴 KHÔNG tồn tại | Build new |
| `UserPlaylistItems` table | TextColumn playlistId FK UserPlaylists + IntColumn downloadId FK Downloads + IntColumn position + DateTimeColumn addedAt + composite PK (playlistId, downloadId) | 🔴 KHÔNG tồn tại | Build new |
| FK type matching | `UserPlaylistItems.downloadId IntColumn` (matches Downloads.id) | N/A — chưa build | ✅ Spec đã fix v1.5 P1 |
| `KeyAction.cascade` | Both FKs cascade delete | N/A | Standard — drift `ON DELETE CASCADE` |
| Foreign keys enabled | `PRAGMA foreign_keys = ON` | ✅ Already done ([line 196](lib/core/database/app_database.dart#L196)) | Match |

### 3.2 Disambiguation — 3 concepts cùng tồn tại (§10.0 — Gemini P1 #2)

| Feature | Nature | Storage | Code location | V2 status |
|---|---|---|---|---|
| **Smart Collections** (existing) | Dynamic — auto-match by filter | SharedPreferences | [`collection_entity.dart`](lib/features/downloads/domain/entities/collection_entity.dart) (139 dòng), filter-driven via `CollectionFilter` (platforms/statuses/tags AND-logic) | ✅ Keep, no refactor |
| **PlaybackQueue** (existing) | Session-scoped, in-memory | None | [`playback_queue_service.dart`](lib/features/player/domain/services/playback_queue_service.dart) (263 dòng) | ✅ Keep, F3 wires INTO this |
| **Playlist của tôi** (NEW) | User-curated, ordered, persistent | Drift DB v19 | 🔴 Build new — entity + repo + screens + dialogs | 🔴 Phase §10 (10d) |

→ KHÔNG conflict. 3 entry points hoàn toàn khác nhau.

### 3.3 Domain layer (§10.2) — files cần tạo

```
lib/features/playlists/                                  ← NEW feature module
├── data/
│   ├── datasources/playlist_dao.dart                    (Drift DAO)
│   └── repositories/playlist_repository_impl.dart
├── domain/
│   ├── entities/user_playlist.dart                      (freezed)
│   ├── entities/user_playlist_item.dart                 (freezed)
│   ├── repositories/user_playlist_repository.dart       (abstract)
│   └── usecases/
│       ├── create_playlist_usecase.dart
│       ├── rename_playlist_usecase.dart
│       ├── add_to_playlist_usecase.dart                 (bulk)
│       ├── remove_from_playlist_usecase.dart            (soft, file remains)
│       ├── reorder_items_usecase.dart
│       └── delete_playlist_usecase.dart                 (cascade)
└── presentation/
    ├── providers/                                       (Riverpod)
    ├── screens/
    │   ├── playlists_tab.dart                           (Tab 2 trong Manager)
    │   └── playlist_detail_screen.dart
    └── widgets/
        ├── playlist_card.dart
        ├── playlist_item_row.dart
        ├── add_to_playlist_menu.dart
        └── create_playlist_dialog.dart
```

→ Tổng ~18 files mới. Phase §10 estimate 10d cover hết.

---

## 4. F3 — Player queue deep map

### 4.1 PlaybackQueueService capabilities (existing — phát hiện rich)

```dart
// lib/features/player/domain/services/playback_queue_service.dart
class PlaybackQueueService {
  // Items management
  setQueue(downloads, {startIndex})        ✅
  addToQueue(download)                     ✅
  playNext(download)                       ✅
  removeFromQueue(downloadId)              ✅
  reorder(oldIndex, newIndex)              ✅
  clear()                                  ✅

  // Navigation
  next() / previous() / jumpTo(index)      ✅
  peekNext()                               ✅

  // Mode controls
  setRepeatMode(off/repeatOne/repeatAll)   ✅
  cycleRepeatMode()                        ✅
  toggleShuffle() / setShuffle(bool)       ✅

  // Getters
  items / currentIndex / currentItem       ✅
  hasNext / hasPrevious                    ✅
  repeatMode / shuffleEnabled              ✅
}
```

### 4.2 §10.5 spec — gap analysis

| Spec requirement | Existing | Action |
|---|---|---|
| `PlayerNotifier.playlistContext: UserPlaylist?` | NOT in PlayerNotifier | 🔴 Add field |
| Khi play playlist → `setQueue(items)` theo position order | `setQueue` đã có | 🟢 Just call |
| Player UI Next/Previous buttons khi có playlist context | Chưa wired (chỉ có hasPrevious/hasNext getter) | 🟠 Add widgets, conditional rendering |
| "Auto next" toggle (default ON) | `cycleRepeatMode` đã có (off/repeatAll/repeatOne) | 🟢 Repeat mode = repeatAll-by-default cho playlist context |
| Item kết thúc → auto chuyển | Auto-advance hookup at `video_player_screen.dart:311` "Listen for playback completion" | 🟢 Already wired (Pass 1 agent confirmed) |

→ **F3 spec §10.5 + §10.6 = ~1d work**, không phải 2d. Roadmap có thể giảm slack.

---

## 5. Mockup ↔ Spec — Pass 1 flag revisited

| Pass 1 finding | Reality |
|---|---|
| "Mockup top bar 4 tabs (`Trang chủ / Đăng ký / Chuyển đổi / Trình duyệt`) ↔ UI Spec §3 chỉ 3 (`Home / Trình duyệt / Settings`). Divergence." | ❌ **INCORRECT**. §2 Layout table L81 list đầy đủ 5 tab: "Logo, Trang chủ, Đăng ký, Chuyển đổi, Trình duyệt, Nâng cấp/Premium, notification, settings, theme, window controls". §3 chỉ thảo luận **rule** (không hiển thị Premium + Nâng cấp đồng thời) + role của "Trình duyệt" tab. Mockup ↔ spec **align hoàn toàn**. |
| "Mockup show 5 row states ↔ UI Spec §8.3 spec 9" | ✅ Correct. Mockup là demo subset (completed/downloading/queued/failed/audio). Spec mandates 9 (thêm postProcessing/pending/paused/cancelled/waitingForNetwork). |

→ Pass 2D scope nhẹ đi đáng kể. Mockup KHÔNG diverge.

---

## 6. Spec sections cross-reference với current code

| Spec § | Spec content | Code surface | Phase | Effort |
|---|---|---|---|---|
| §3 Top bar (Premium/Nâng cấp logic, Trình duyệt tab role) | Mutual exclusion logic + tab routing | `lib/core/navigation/top_navigation_bar.dart` (existing); premium gate via `PremiumFeature` | 1A | 0.5d |
| §4 Smart input (5 control bar widgets + 7 detection rules + extraction states) | `home_screen.dart:517-574` filter tabs + glassmorphism_header (input wrapper); detection logic mới | 1A | 2d (smart_input_bar + smart_cta_button + smart detection logic) |
| §5 Preset 3-layer | Layer 1 ✓ (Rule 2). Layer 2 🔴. Layer 3 ✓. Resolver 🔴. Popover 🔴. 6 built-in 🔴. | 1A + §5 | 6.5d (UI) + 6d (architecture) |
| §6 Right column (Bắt đầu nhanh + Mở nhanh website 9-tile + Windows fallback) | `popular_sites_grid.dart` (existing 6 sites) + onboarding mới | 1A | 0.5d (extend grid + add onboarding card + Windows external launcher) |
| §7 Plan strip (15-quota inline banner + independent gates) | `home_screen_banners.dart` (existing) — cần convert sang inline banner format | 1A | 0.5d |
| §8 Manager 9 row states | `download_list_item.dart` (existing 5 states), `AppColors.lightStatus*` 5 states | 1B | 4d (rebuild rows + 4 row state tokens + drag handle queued + watch progress overlay) |
| §9 Multi-select + bulk | `batch_operations_bar.dart` (existing) cần extend | 1C | 4-5d |
| §10 Playlist của tôi | Build hoàn toàn mới | §10 | 10d |
| §11 Dialogs (Search/Playlist/Channel/Batch/Preset/Delete confirm/Create playlist/AddToPlaylist) | 3 sheets existing; 5 mới | Phân tán 1A/§5/§10 | (đã count trong các phase trên) |
| §12 Visual rules | Pass 2A đã handle (Block #1 phantom Inter, Block #2 design_tokens.dart) | 1A foundation | (Pass 2A scope) |
| §13 Accessibility | Tab order, WCAG AA, reduced motion, screen reader announcements | Polish | 2-3d |
| §14 Empty/loading/error states | 9 states với specific copy | 1A/1B/§10 cho từng surface | (count trong phases) |
| §17 Migration plan | DTO migration code §17.2 ready-to-adopt | 1A | 0.5d (adopt template + wire startup) |
| §18 Telemetry | 10 events qua Sentry | Polish | 0.5d |
| §19 Performance | ListView virtualization, debounce, indexed DB queries, lazy thumbnails | Polish | 1d (audit + add indexes) |

---

## 7. Block-level gotchas / surprises (highlight cho Pass 2C/2F)

### 7.1 Schema version mismatch (CRITICAL)
- Spec `v15 → v16`, code đã ở `v18` → migration phải target `v19`
- Rename trong codebase + spec: `v16_user_playlists.dart` → `v19_user_playlists.dart`
- Roadmap reference `v15 → v16` ở 4 places → đồng bộ hóa

### 7.2 `FormatPresetsNotifier` chỉ basic add/remove
Code 86 dòng. Spec yêu cầu:
- `_load()` migrate legacy 7→15 fields
- `getActive()` lấy by `activePresetId`
- `setActive(id)` update + persist
- `clone(preset)` create user-editable copy
- `currentConfig` separate state với (activePreset.config) merge logic
- 6 built-in seed nếu missing

→ Phải refactor toàn bộ provider, có thể replace bằng `EffectivePresetService`.

### 7.3 `PlatformQualityPreference` — keep existing flow
Spec §5.6 explicit: "Per-platform pref auto-save chỉ trigger qua Rule 4 / Rule 3' (existing logic, no code change)". → KHÔNG đụng [home_download_mixin.dart:825 area].

### 7.4 ConversionJobs dependency
`ConversionJobs` table v17 đã có `downloadId` nullable FK. Khi build UserPlaylists, KHÔNG conflict (different table). Nhưng cần check: nếu user delete download có conversion job → cascade behavior?

### 7.5 i18n key changes
Spec §17.1 step 6: "Đã hoàn thành" → "Đã tải" trong **5 lang files (vi/en/ja/pt/es)**. Code hiện tại có `assets/translations/{en,vi}.json` (per CLAUDE.md). → Cần add ja/pt/es OR update spec to 2 langs.

### 7.6 Telemetry §18 — `dialog_opened` chưa có
Code có Sentry breadcrumbs cho download/extract events nhưng KHÔNG track preset/playlist/dialog events. Polish phase 0.5d.

### 7.7 Performance §19 — DB indexes
Spec say index trên `Downloads.addedAt`, `Downloads.status`, `UserPlaylistItems.position`. Drift schema có `customIndexes` API (đã dùng cho `SubscribedChannels.hasNewVideos` line 117). → Add 3 index trong v19 migration.

### 7.8 Drift v18 → v19 migration ordering
Migration runs AT app open. Existing migrations:
- v15 (recurrenceRuleJson)
- v16 (tempDirPath)
- v17 (ConversionJobs table)
- v18 (current — chưa rõ field nào)
- v19 (NEW — UserPlaylists, UserPlaylistItems, indexes)

→ Em cần đọc thêm `app_database.dart` migration strategy `onUpgrade` để biết pattern. Nhưng đó là Phase §10 implementation detail.

---

## 8. Updated decision matrix (bổ sung cho Q1-Q6 từ Pass 2A)

| Q | Mới phát sinh ở Pass 2B | Em đề xuất |
|---|---|---|
| Q7 | DB schema target — spec say `v15→v16`, code reality `v18`. Roadmap update? | **Em fix ở Pass 2C** khi đào Roadmap. Không cần Chairman quyết — đây là execution detail. |
| Q8 | i18n langs — spec say 5 (vi/en/ja/pt/es), code có 2 (vi/en). Add 3 hay update spec? | **Em đề xuất giảm spec → 2 lang** (vi/en) cho V2 ship. ja/pt/es defer to v2.1. Send anh Kỳ confirm. |
| Q9 | F3 effort — spec 2d, em estimate 1d (PlaybackQueue rich đã có sẵn). Optimistic? | **Em đề xuất 1.5d** — buffer 0.5d cho UI polish + edge cases (clear queue khi exit playlist context). |
| Q10 | FormatPreset migration backward-compat — spec say v2 → v1 rollback OK (extra fields ignored). Có cần test rollback path? | **YES — add to Buffer phase QA**: rollback v1.x từ v2 user data, verify no crash. |

---

## 9. Status sau Pass 2B

| ✓ | Hoàn thành |
|---|---|
| ✅ | Đọc full UI Spec v1.1 §1-§20 (1090 dòng) |
| ✅ | Đối chiếu với 5 critical code files (format_presets, app_database, collection_entity, playback_queue_service, home_download_mixin) |
| ✅ | F1 layer-by-layer audit: 30% sẵn sàng |
| ✅ | F2 build map (~18 files mới): 10% sẵn sàng |
| ✅ | F3 capability surprise: 80% sẵn sàng (1d, không 2d) |
| ✅ | Schema version critical bug detected (v15→v16 spec vs v18 code) |
| ✅ | Pass 1 mockup-vs-spec divergence resolved (false positive) |
| ✅ | 5 Rule chain refactor scope rõ |
| ✅ | 4 decision points mới (Q7-Q10) |

| ⏳ | Pending |
|---|---|
| ⏳ | Pass 2C — Roadmap deep dive (28.5-31.5d validation, schema v19 fix, F3 1d-vs-2d update, parallel work matrix) |
| ⏳ | Pass 2D — Mockup full audit (slim down — Pass 1 false positive đã clear chính) |
| ⏳ | Pass 2E — Multi-brand (VidCombo gap, font/color/quota divergence) |
| ⏳ | Pass 2F — Hyper-plan synthesis |
