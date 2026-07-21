# Svid Download Options Dialog - PRD / UI Design Spec v1.1

Scope: Single-item download dialog + Batch download dialog

Priority principle: Most users only care about a few primary options. The default dialog must optimize for File Type, Quality, Download Location, and a visually dominant Download action.

---

# 1. Executive summary

This spec defines the download option dialogs used after Svid recognizes a downloadable item or when the user starts a batch download. The dialog must make common downloads fast while keeping advanced controls available but collapsed by default.

- Single-item dialog: used for one video/audio/subtitle item.
- Batch dialog: used when multiple selected items will share a common configuration.
- Primary options are always visible: file type, quality, save location, and main download action.
- Secondary options are visible but visually quiet.
- Advanced options are collapsed by default.
- This spec is a product/UX contract for the designer and developer. The designer owns visual layout exploration, but must not reinterpret the preference, fallback, batch, or engine-mapping rules defined here.

---

# 2. Goals and non-goals

| Category | Details |
| --- | --- |
| Goals | Make a normal YouTube download require no more than confirming Video, optionally choosing Best/1080p/720p, then clicking Download. |
| Goals | Reduce cognitive load by hiding codec, raw streams, container, metadata, subtitle details, SponsorBlock, and trim until the user opens Advanced options. |
| Goals | Support both single-item and batch contexts using shared component anatomy. |
| Goals | Keep the Download button visually dominant and unambiguous. |
| Goals | Keep the new dialog compatible with Svid's existing `DownloadConfig`, `Quality`, platform preference, and save-path behavior. |
| Non-goals | Do not build a full stream inspector as the default experience. |
| Non-goals | Do not force users to pick codec/container before downloading. |
| Non-goals | Do not make subtitle-only a primary option unless subtitle data is available/relevant. |
| Non-goals | Do not solve the full in-app browser or queue manager in this dialog spec. |

---

# 3. Dialog variants

| Variant | Trigger | Main difference |
| --- | --- | --- |
| DownloadOptionsDialog | User downloads one recognized video/item. | Shows one media preview and item-level options. |
| BatchDownloadOptionsDialog | User downloads multiple selected items or multiple URLs. | Shows a selected item list and an Apply to all control. |
| Advanced expanded state | User opens Tùy chọn nâng cao. | Shows codec, container, subtitles, SponsorBlock, trim, and FFmpeg warnings. |
| Error/blocked state | Required data or storage/path is invalid. | Primary CTA disabled or warning shown with clear recovery action. |
| Metadata loading state | Formats, thumbnail, title, or size are not available yet. | Shows skeleton rows and keeps primary choices understandable. |
| Source/auth required state | Platform requires cookies/login or content is unsupported. | Shows recovery action or clear non-blocking explanation. |

---

# 4. Priority principle and information hierarchy

The dialog should visually rank information in this order:

1. Primary options: File Type, Quality, Download Location.
2. Main action: Download button, anchored in footer and visually dominant.
3. Secondary options: remember choice, apply to all in batch, save as default.
4. Advanced options: collapsed by default and visually quiet.

A normal YouTube download should not require the user to understand codec, container, raw streams, subtitles, metadata, SponsorBlock, trim, or FFmpeg warnings.

---

# 5. Single-item dialog anatomy

```text
DownloadOptionsDialog
├── Header
│   ├── Download icon
│   ├── Title: Tùy chọn tải xuống
│   └── Close icon
├── Media preview
│   ├── Thumbnail + duration
│   ├── Title
│   └── Source/channel + date
├── Primary options grid
│   ├── 1. Loại tệp
│   ├── 2. Chất lượng
│   └── 3. Vị trí lưu
├── Secondary options row
│   ├── Ghi nhớ lựa chọn này cho YouTube
│   └── Lưu làm mặc định
├── Advanced accordion
└── Footer
    ├── Safe-use note
    ├── Hủy
    └── Tải xuống
```

Recommended dialog width: 960-1100px desktop. The footer should remain stable and the Download button should be aligned to the bottom-right.

Responsive behavior:

- Max height should be 85vh. Header and footer remain pinned; the body scrolls.
- At narrow desktop widths, the primary options grid stacks vertically in the order File Type, Quality, Download Location.
- The footer action area must not wrap the Download button below Cancel unless the viewport is extremely constrained.

---

# 6. Batch dialog anatomy

```text
BatchDownloadOptionsDialog
├── Header
│   ├── Title: Tải xuống N mục
│   └── Close icon
├── Selected item list
│   ├── Item rows with thumbnail/title/source/estimated size
│   └── Optional checkbox to include/exclude item
├── Shared primary options grid
│   ├── Loại tệp
│   ├── Chất lượng
│   └── Vị trí lưu
├── Secondary options row
│   ├── Áp dụng cho tất cả N mục
│   └── Lưu làm mặc định
├── Advanced accordion
└── Footer
    ├── Hủy
    └── Tải xuống
```

The batch dialog should not force per-item tuning in the default view. Per-item tuning belongs in a future dedicated batch editor, not in this default dialog.

Batch behavior rules:

- Batch must open one shared configuration dialog by default. It must not spawn repeated single-item dialogs.
- `Áp dụng cho tất cả N mục` is checked by default and applies file type, quality, location, and safe advanced options to all included items.
- If the user disables `Áp dụng cho tất cả N mục`, the default dialog should not expand into full per-item editing. For more than 5 items, show a confirmation or redirect to a future batch editor.
- The selected item list may show loading rows when title, thumbnail, duration, or estimated size are not available yet.
- For large batches, show a compact summary plus the first few rows rather than a long unbounded list.

---

# 7. Primary option: File Type

| Option | When visible | Default behavior | Notes |
| --- | --- | --- | --- |
| Video | Always if video stream exists. | Default for normal YouTube/video downloads. | Show format hint such as MP4. |
| Audio | Always if audio stream exists. | User can switch to MP3/audio download. | Quality options change to bitrate choices. |
| Subtitle-only | Only if subtitles are available/relevant. | Not selected by default. | Less prominent. Label: Subtitle (nếu có). Use SRT/VTT options after selected. |

File Type should be represented as selectable cards or compact list items. The selected option uses brand primary border/accent and a clear selected indicator.

Subtitle clarification:

- `Subtitle-only` means Svid creates subtitle files only, such as `.srt` or `.vtt`.
- `Download subtitles with video` in Advanced means include or save subtitles alongside a video download.
- These two modes must use different copy so users do not confuse them.

---

# 8. Primary option: Quality

| File type | Visible quality options | Recommended default | Additional behavior |
| --- | --- | --- | --- |
| Video | Đề xuất / Tốt nhất, 1080p, 720p, Thêm... | Đề xuất / Tốt nhất | Show estimated container and size when available, e.g. MP4 - ~224.5 MB. |
| Audio | Đề xuất, 320kbps, 192kbps, 128kbps, Thêm... | Đề xuất | Do not show 1080p/720p when Audio is selected. |
| Subtitle-only | Language, format SRT/VTT, optional auto-generated subtitle toggle. | Vietnamese or source default if available | Do not show video resolution choices. |

Quality options should be easy to scan. A normal user should see Best/1080p/720p immediately. More detailed streams go inside More or Advanced, not the default state.

Quality is a user intent, not a raw stream selector:

| User selection | Engine mapping rule |
| --- | --- |
| Đề xuất / Tốt nhất | Use the current Svid smart/default quality behavior. Prefer a playable merged result without asking the user to choose codec/container. |
| 1080p / 720p | Treat as target vertical resolution. If unavailable, choose the nearest suitable fallback and show a short warning. |
| Video requiring merge | Automatically pair video-only stream with compatible audio when needed. Surface FFmpeg warnings only if they affect the current choice. |
| Audio bitrate | Treat as target bitrate/export intent. If exact bitrate is unavailable, choose nearest practical output and keep the raw stream list hidden. |
| Thêm... | Reveals more qualities or stream details, but still should not become a full raw stream inspector by default. |

---

# 9. Primary option: Download location

| Element | Required behavior |
| --- | --- |
| Current folder | Show compact path, e.g. D:\Downloads\Svid. If path is long, truncate middle. |
| Free space | Show if available, e.g. Còn trống: 126.3 GB. |
| Change folder | Secondary action. Opens native folder picker. |
| Open folder | Optional secondary action, not primary. |
| Invalid path | Show warning and disable Download until resolved, or fallback to default folder with clear notice. |
| Insufficient storage | Show warning with estimated size and free space. Download may be disabled or require confirmation depending severity. |

Persistence rules:

- The displayed folder starts from the current Svid download path setting.
- Changing folder inside the dialog is a one-time override for the submitted download or batch.
- `Ghi nhớ lựa chọn này cho YouTube/TikTok/...` should not persist save location by default.
- `Lưu làm mặc định` may persist the selected save location as the new global default.
- If both platform remember and global default are checked, platform remember controls file type/quality for that platform, while global default controls the shared save location.

---

# 10. Secondary options

| Option | Visibility | Default | Notes |
| --- | --- | --- | --- |
| Ghi nhớ lựa chọn này cho YouTube | Only for YouTube context or platform-specific source. | Unchecked | Saves platform-specific preference. Text should change by source: YouTube/TikTok/etc. |
| Áp dụng cho tất cả N mục | Only in batch context. | Checked | Applies shared type/quality/location to all selected batch items. |
| Lưu làm mặc định | Visible in both contexts, less prominent. | Unchecked | Saves global default preset. Do not make this primary. |

Preference precedence:

1. Explicit selection made in the currently open dialog.
2. Platform-specific remembered choice, e.g. YouTube, TikTok, Instagram.
3. Global default saved by `Lưu làm mặc định`.
4. Built-in app default: Video + Đề xuất + current download folder.

If both `Ghi nhớ lựa chọn này` and `Lưu làm mặc định` are checked on submit, save both scopes. On the next download, the platform-specific choice wins for that same platform; the global default applies elsewhere.

---

# 11. Advanced options collapsed by default

Advanced options should be an accordion labelled `Tùy chọn nâng cao` with a short summary such as `Codec, phụ đề, SponsorBlock...`. The accordion is collapsed by default.

| Group | Options |
| --- | --- |
| Streams | Raw streams, video-only stream, audio-only stream details. |
| Format | Codec, container, FPS, max resolution override. |
| Metadata | Embed thumbnail, embed metadata, embed chapters. |
| Subtitles | Download subtitles with video, subtitle language, subtitle format. |
| Cleanup | SponsorBlock, section trim. |
| Diagnostics | FFmpeg warnings, incompatible option warnings. |

Advanced changes should not silently break default downloads. If a selected advanced option conflicts with the chosen file type/quality, show a warning inside the accordion or near the footer.

Advanced scope rules:

- Advanced options may expose existing Svid controls, but they should not be required for a normal download.
- Raw stream details should remain behind `Thêm...` or Advanced and must not dominate the default dialog.
- Unsafe or incompatible combinations should be prevented or explained before submit.
- The accordion summary should mention only changed advanced settings, e.g. `Codec: H.264, phụ đề: VI`.

---

# 12. Main action and footer behavior

| Element | Spec |
| --- | --- |
| Tải xuống | Primary button, visually dominant, bottom-right, no dropdown arrow. Uses Svid muted burgundy primary. |
| Hủy | Secondary button, bottom-right before Download. Ghost or outline style. |
| Close X | Top-right icon-only. Same as Cancel behavior unless there are unsaved changes. |
| Safe-use note | Optional footer note: Tải video chỉ để sử dụng cá nhân. Vui lòng tôn trọng bản quyền. |
| Loading state | Download button shows spinner/text such as Đang chuẩn bị... and prevents duplicate submit. |

---

# 13. Visual design rules

Use Svid's existing design token system where available, especially `lib/core/design/design_tokens.dart`. The values below are directionally approved fallbacks for designer handoff, not a separate token source of truth.

| Token/area | Light mode fallback | Dark mode fallback |
| --- | --- | --- |
| Primary CTA | #B00030 | #C12C49 |
| Primary hover | #980028 | #CC3154 |
| Primary pressed | #7A001F | #A91535 |
| Active text | #B00030 | #E05267 |
| Dialog surface | #FFFFFF | #111827 |
| Nested surface | #F8FAFC | #172033 |
| Border | #E2E8F0 | #243044 |
| Text primary | #0F172A | #F8FAFC |
| Text secondary | #475569 | #CBD5E1 |

- Do not use bright/neon red in dark mode. Use muted burgundy.
- Do not use primary burgundy for error states. Error remains semantic red.
- Use blue only for technical downloading/progress states.
- Selected option cards use primary border/accent and a clear check indicator.
- Advanced accordion should be visually quiet.

---

# 14. State variations

| State | UI behavior |
| --- | --- |
| Initial/default | Video + Đề xuất + current save folder selected. Download enabled if item is ready. |
| Analyzing formats | Show skeleton/loading in quality area. Download disabled or says Đang chuẩn bị... |
| No 1080p available | Keep 1080p visible only if useful; otherwise More... includes available qualities. If user selected unavailable quality from preset, choose nearest and show warning. |
| Subtitle not available | Hide Subtitle-only or show disabled low-prominence option with tooltip. |
| Storage insufficient | Show warning in location section and footer. Disable Download if required. |
| Invalid folder | Show error under save location. Change folder is highlighted as recovery action. |
| Batch conflict | Show non-blocking warning: Một số video không có 1080p. Ứng dụng sẽ chọn chất lượng gần nhất. |
| FFmpeg warning | Show inside Advanced or footer warning if it affects current selection. |
| Auth/cookies required | Show recovery action if available. If recovery is outside this dialog, explain why Download is unavailable. |
| Duplicate existing item | Show non-blocking warning and allow user to continue only if the app supports duplicate downloads. |
| Wi-Fi-only/download policy blocked | Show policy message and route to Settings if the current app policy blocks download. |
| Missing FFmpeg for chosen option | Show warning near Advanced/Footer and disable only options that require FFmpeg. |

---

# 15. Interaction flows

## 15.1. Normal single YouTube video

```text
User clicks Tải xuống on a recognized video
→ Dialog opens with Video + Đề xuất selected
→ User optionally chooses 1080p/720p
→ User clicks Tải xuống
→ Dialog closes or transitions to preparing state
→ Download row appears in history as Đang tải
```

## 15.2. Audio download

```text
User opens dialog
→ User selects Audio
→ Quality options switch to Đề xuất / 320kbps / 192kbps / 128kbps / Thêm...
→ User clicks Tải xuống
→ Download row appears as audio item
```

## 15.3. Batch download

```text
User selects multiple items or pastes multiple URLs
→ Batch dialog opens with selected item list
→ Áp dụng cho tất cả N mục is checked by default
→ User chooses shared file type, quality, location
→ User clicks Tải xuống
→ Items enter history as downloading/queued rows
```

---

# 16. Accessibility and keyboard behavior

- Dialog traps focus while open.
- Esc closes dialog, unless a destructive/processing confirmation is active.
- Tab order follows visual order: close, file type, quality, location, secondary options, advanced, cancel, download.
- Arrow keys can move within segmented option groups where applicable.
- Enter on primary button triggers download.
- All icon-only buttons require Flutter `Semantics(label:)` and visible `Tooltip` text.
- Selected state must not rely only on color; include checkmark/border/label.
- Normal text contrast must meet WCAG AA 4.5:1. UI components/icons must meet at least 3:1.
- Use Flutter `FocusTraversalOrder` or equivalent ordering so keyboard focus matches the visual hierarchy.
- Use Flutter `Shortcuts`/`Actions` or equivalent behavior for Esc, Enter, and arrow-key option navigation.

| Control | Accessible label |
| --- | --- |
| Close icon | Đóng hộp thoại tùy chọn tải xuống |
| Video option | Loại tệp: Video, MP4 |
| Audio option | Loại tệp: Audio, MP3 |
| Subtitle option | Loại tệp: Subtitle, SRT |
| Quality recommended | Chất lượng: Đề xuất, tốt nhất |
| Change folder | Thay đổi thư mục lưu |
| Advanced accordion | Mở tùy chọn nâng cao |
| Download button | Tải xuống với tùy chọn đã chọn |

---

# 17. Implementation guide

| Component | Responsibility |
| --- | --- |
| DownloadOptionsDialog | Single-item dialog shell and orchestration. |
| BatchDownloadOptionsDialog | Batch dialog shell, selected item list, apply-to-all behavior. |
| MediaPreview | Thumbnail, duration, title, source/channel, date. |
| FileTypeSelector | Video/Audio/Subtitle option group. |
| QualitySelector | Quality/resolution/bitrate/subtitle quality options. |
| SaveLocationSelector | Path display, free space, change folder action. |
| SecondaryOptionsRow | Remember, apply all, save default. |
| AdvancedOptionsAccordion | Collapsed advanced configuration. |
| DialogFooter | Safe-use note, cancel, primary download action. |

## 17.1. Suggested data model

This is a conceptual view-model shape, not TypeScript implementation code. In Flutter, map it onto existing Svid entities such as `DownloadConfig`, `Quality`, `VideoInfo`, platform preferences, and save-path providers.

```text
type DownloadDialogContext = {
  mode: "single" | "batch";
  sourcePlatform?: "youtube" | "tiktok" | "facebook" | "other";
  items: DownloadItem[];
  availableFileTypes: FileType[];
  availableQualities: QualityOption[];
  subtitleOptions?: SubtitleOption[];
  defaultPreset: DownloadPreset;
  saveLocation: SaveLocation;
  batchApplyToAll?: boolean;
  preferenceSource?: "current" | "platform" | "global" | "appDefault";
};

type DownloadPreset = {
  fileType: "video" | "audio" | "subtitle";
  quality: "recommended" | "1080p" | "720p" | string;
  container?: "mp4" | "webm" | "mp3" | "m4a" | "srt" | "vtt";
  fallback: "nearest" | "ask";
  savePath: string;
  savePathPersistence: "oneTime" | "globalDefault";
  rememberForPlatform?: boolean;
  saveAsDefault?: boolean;
  advancedOverrides?: {
    codec?: string;
    fps?: string;
    subtitles?: unknown;
    metadata?: unknown;
    sponsorBlock?: unknown;
    trim?: unknown;
  };
};
```

---

# 18. Acceptance checklist

- Default dialog shows File Type, Quality, Download Location, and Download action without needing Advanced.
- Download button is the most visually dominant action and has no dropdown arrow.
- Cancel and close are secondary.
- Subtitle-only is hidden or low-prominence unless subtitles are available/relevant.
- Audio selection changes quality choices to bitrate options.
- Download location shows current folder compactly and provides Change folder as secondary action.
- Remember choice is platform-specific and only shown when applicable.
- Apply to all appears only in batch context and is checked by default.
- Save as default is visible but not visually primary.
- Advanced options are collapsed by default.
- Batch dialog shows selected items and shared configuration.
- Batch dialog never spawns repeated single-item dialogs by default.
- Preference precedence between current selection, platform remember, global default, and app default is implemented.
- Download location change is one-time unless `Lưu làm mặc định` is checked.
- Quality options map to Svid engine behavior without exposing raw streams in the default state.
- Quality conflicts use nearest fallback or show clear non-blocking warning.
- Error, storage, and invalid-folder states have clear recovery actions.
- Keyboard navigation, Flutter semantics, and tooltips are implemented.
- Dark mode uses muted burgundy, not neon red.

---

# 19. Out of scope for this dialog spec

- Full queue manager with reorderable queue.
- Full stream inspector as a default state.
- Advanced per-item batch editing.
- Complete media player redesign.
- Browser tab management.
- Subtitle translation workflow.
- Filename template builder.
- Proxy/cookie/account login configuration.
- Long-form analytics or session pulse.
- Mobile-first dialog redesign.
