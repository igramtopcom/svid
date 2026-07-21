# YouTube Search Results — Design Spec

> Source: Stitch project `10022260214920217805`
> Screen ID: `341a9953abfd4f84ae45d5e29ba3e70d`
> Status: **IMPLEMENTED** (v2 refinement complete)
> Current code: `lib/features/youtube_search/presentation/widgets/youtube_results_view.dart`
> Detail panel: `lib/features/youtube_search/presentation/widgets/video_detail_panel.dart`

## 1. Design Intent

**Purpose**: Display search results with 70/30 split — results list + detail panel. User selects a video to see quality options and download.

**Mood**: Productive, information-dense but clean. The detail panel provides depth without clutter.

**Key principle**: First result is featured (larger card), remaining results are compact list items. Right panel lazy-loads quality data on selection.

## 2. Visual Structure

### 2.1 Layout — 70/30 Split

```
┌──────────────────────────────────────────────────┐
│ [SSvid]  Downloads  YouTube  Subs    [+] [?] [⚙]│  ← TopNavigationBar (52px)
├──────────────────────────────────────────────────┤
│ [← ] [🔍 lofi hip hop                ] [Search] │  ← Search bar + back button
├──────────────────────────────────────────────────┤
│  [SORT: RELEVANCE ▾] [DURATION: ANY ▾] [DATE ▾] │  ← SearchFiltersBar
│  12 results                                       │
├────────────────────────────┬─────────────────────┤
│                            │ CURRENTLY SELECTED   │
│  ┌──────────────────────┐  │                      │
│  │ ████████████████████ │  │  ┌─────────────┐    │
│  │ Featured 1st Result  │  │  │  Thumbnail   │    │
│  │ (large 16:9 thumb)   │  │  │  16:9        │    │
│  │ Title · Channel      │  │  └─────────────┘    │
│  │            [Download] │  │  Title              │
│  └──────────────────────┘  │  Channel · Views     │
│                            │                      │
│  ┌──────┐ Title            │  ┌──────────────┐   │
│  │thumb │ Channel · 1.2M   │  │ CODEC: H.264 │   │
│  └──────┘ 2 hours ago      │  │ FPS: 60      │   │
│                            │  │ BITRATE: 12M │   │
│  ┌──────┐ Title            │  │ AUDIO: AAC   │   │
│  │thumb │ Channel · 500K   │  └──────────────┘   │
│  └──────┘ 1 week ago       │                      │
│                            │  Available Quality   │
│  ┌──────┐ Title            │  [2160p] MP4  45MB  │
│  │thumb │ Channel · 200K   │  [1080p] MP4  22MB  │
│  └──────┘ 3 days ago       │  [720p]  MP4  11MB  │
│                            │                      │
│  (infinite scroll)         │  Audio Only          │
│  ·····loading·····         │  [128k]  M4A  3MB   │
│                            │                      │
│                            │  [⬇ Download]       │
└────────────────────────────┴─────────────────────┘
```

### 2.2 Dimensions

| Element | Value | Token mapping |
|---------|-------|---------------|
| Results list flex | 7 (70%) | `Expanded(flex: 7)` |
| Detail panel width | 340px | `Container(width: 340)` |
| Panel border-left | 1px | `Border(left: BorderSide)` |
| Featured card border-radius | 12px | `BorderRadius.circular(12)` |
| Featured card padding | 12px all | Custom |
| Featured thumbnail aspect | 16:9 | `AspectRatio(16/9)` |
| Selected item left border | 3px crimson | `BorderSide(AppColors.accentHighlight, width: 3)` |
| Metadata container radius | 10px | `BorderRadius.circular(10)` |
| Format tile radius | 8px | `BorderRadius.circular(8)` |

## 3. Token Extraction — Dark Mode

### 3.1 Colors

| Element | Stitch Hex | Flutter Mapping |
|---------|-----------|-----------------|
| Detail panel bg | `#0E0E0E` | `const Color(0xFF0E0E0E)` (surface lowest) |
| Panel border | `#2A2A2A` | `const Color(0xFF2A2A2A)` |
| Selected item bg | `#8D021F @ 8%` | `AppColors.brand.withValues(alpha: 0.08)` |
| Selected item border | `#C41E3A` | `AppColors.accentHighlight` |
| Featured card hover | `#1C1B1B` | `const Color(0xFF1C1B1B)` |
| Featured card selected border | `#C41E3A @ 30%` | `AppColors.accentHighlight.withValues(alpha: 0.3)` |
| Metadata container bg | `#1C1B1B` | `const Color(0xFF1C1B1B)` |
| Metadata border | `#2A2A2A` | `const Color(0xFF2A2A2A)` |
| Format tile bg | `#1C1B1B` | `const Color(0xFF1C1B1B)` |
| Video quality badge bg | `#8D021F @ 15%` | `AppColors.brand.withValues(alpha: 0.15)` |
| Video quality badge text | `#C41E3A` | `AppColors.accentHighlight` |
| Audio quality badge bg | `#5B21B6 @ 20%` | Purple tint |
| Audio quality badge text | `#A78BFA` | Purple accent |
| "CURRENTLY SELECTED" label | `#C41E3A @ 70%` | `AppColors.accentHighlight.withValues(alpha: 0.7)` |
| Loading spinner | `#C41E3A @ 50%` | `AppColors.accentHighlight.withValues(alpha: 0.5)` |

### 3.2 Colors — Light Mode

| Element | Flutter Mapping |
|---------|-----------------|
| Detail panel bg | `AppColors.lightSurface1` |
| Panel border | `outlineVariant @ 30%` |
| Selected item bg | `primaryContainer @ 30%` |
| Format tile bg | `AppColors.lightSurface2` |
| Quality badge | `primaryContainer / tertiaryContainer` |

### 3.3 Typography

| Element | Style | Weight | Color |
|---------|-------|--------|-------|
| "CURRENTLY SELECTED" | `labelSmall` | w600 | crimson @ 70% |
| "Available Quality" | `labelMedium` | w600 | onSurface @ 70% |
| "Audio Only" | `labelSmall` | w400 | onSurface @ 40% |
| Metadata label | `labelSmall` (10px) | w400 | onSurface @ 35% |
| Metadata value | `labelSmall` | w600 | onSurface @ 70% |
| Quality label | `labelSmall` | w600 | brand-tinted |
| Format ext | `labelSmall` | w400 | onSurface @ 50% |
| File size | `labelSmall` | w400 | onSurface @ 40% |
| Codec | `labelSmall` (10px) | w400 | onSurface @ 30% |

## 4. Featured First Result

Per Stitch design, the first search result renders as a large featured card:

- Full-width 16:9 thumbnail (within left column)
- Title below (titleSmall, w600)
- Channel + views row with inline Download button (crimson pill)
- Duration badge on thumbnail (bottom-right)
- Hover: subtle bg tint, selected: crimson border outline

Remaining results use the standard `YouTubeSearchResultItem` widget (160x90 thumbnail + text).

## 5. Detail Panel — Video Info

### 5.1 Sections (top to bottom)

1. **"CURRENTLY SELECTED"** header + close button
2. **Thumbnail** (16:9, CachedNetworkImage, duration badge overlay)
3. **Title** (titleSmall, w600, max 3 lines)
4. **Channel + views** (bodySmall, muted)
5. **Metadata grid** (when videoDetail loaded):
   - Codec (H.264/AV1/VP9/H.265)
   - Frame Rate (fps)
   - Bitrate (kbps)
   - Audio codec (AAC/Opus/Vorbis/FLAC)
   - Upload date (Mon DD, YYYY)
6. **Available Quality** format tiles (deduped by height, max 6 video + 3 audio)
7. **Download button** (full-width crimson FilledButton)

### 5.2 Loading States

| State | Display |
|-------|---------|
| Video selected, detail loading | Spinner + "Loading quality options..." + 4 shimmer boxes |
| Detail loaded | Metadata section + format tiles |
| Detail error | Error container with warning icon |
| No video selected | Centered placeholder: icon + "Select a video" |

### 5.3 Data Source

Quality data comes from `ytdlpExtractInfo(url)` via Rust FFI bridge:
- Latency: 3-10 seconds (lazy-loaded on video selection)
- Returns `YtDlpVideoInfo` with `List<YtDlpFormat>` containing: formatId, ext, resolution, height, width, filesize, vcodec, acodec, fps, tbr, formatNote
- `videoFormats` getter: filters by has height + has vcodec, sorted by height desc
- `audioFormats` getter: filters by isAudioOnly, sorted by tbr desc

## 6. Interaction States

| Trigger | Effect |
|---------|--------|
| Click video in list | Highlights with crimson border, loads detail panel |
| Click featured result | Same selection + highlight |
| Click Download (detail panel) | `onVideoDownload(url)` → navigates to Home → auto-extract |
| Click Download (featured card) | Same flow |
| Click close (detail panel) | Clears selection, shows empty panel |
| Scroll near bottom | `youtubeSearchProvider.loadMore()` |
| Change filter | `youtubeSearchProvider.updateFilters()` |

## 7. Verification Checklist

- [x] Featured first result renders as large card
- [x] Remaining results use standard `YouTubeSearchResultItem`
- [x] Selected video highlighted with crimson left border
- [x] Detail panel shows "CURRENTLY SELECTED" header
- [x] Metadata section displays codec, fps, bitrate, audio, date
- [x] Format tiles deduped by height (max 6 video)
- [x] Audio formats shown separately (max 3)
- [x] Loading shimmer while `ytdlpExtractInfo` runs
- [x] Error state for failed quality load
- [x] Empty panel when no video selected
- [x] Infinite scroll pagination
- [x] Filter bar functional
- [x] Download flow navigates to Home with `addPostFrameCallback`
- [x] Dark/light mode properly themed
- [x] Panel border uses `#2A2A2A` in dark mode
