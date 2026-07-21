# Svid Accessibility QA Checklist

Manual VoiceOver (macOS) and accessibility audit for Phase 23.4.

## Test Environment

- macOS: System Settings > Accessibility > VoiceOver (Cmd+F5 to toggle)
- Flutter: all builds with `flutter run --release` or from DMG

---

## 1. Download Item Cards

| # | Action | Expected VoiceOver output | Pass/Fail |
|---|--------|--------------------------|-----------|
| 1.1 | Tab to a pending download card | "filename.mp4, Status: Pending, Actions: Cancel" | ☐ |
| 1.2 | Tab to a completed card | "filename.mp4, Status: Completed, Actions: Delete, Open" | ☐ |
| 1.3 | Tab to a downloading card | "filename.mp4, Status: Downloading, 42 percent, Actions: Pause, Cancel" | ☐ |
| 1.4 | Tab to a failed card | "filename.mp4, Status: Failed, Actions: Retry, Delete" | ☐ |
| 1.5 | Tab to a paused card | "filename.mp4, Status: Paused, Actions: Resume, Cancel, Delete" | ☐ |
| 1.6 | Download completes | VoiceOver announces "Download complete: filename.mp4" | ☐ |
| 1.7 | Download fails | VoiceOver announces "Download failed: filename.mp4" | ☐ |

## 2. Action Buttons (hover / focus)

| # | Action | Expected | Pass/Fail |
|---|--------|----------|-----------|
| 2.1 | Focus Pause button | VoiceOver: "Pause download, button" | ☐ |
| 2.2 | Focus Resume button | VoiceOver: "Resume download, button" | ☐ |
| 2.3 | Focus Cancel button | VoiceOver: "Cancel download, button" | ☐ |
| 2.4 | Focus Delete button | VoiceOver: "Delete download, button" | ☐ |
| 2.5 | Focus Move-to-top button | VoiceOver: "Move to top of queue, button" | ☐ |
| 2.6 | Focus Open folder button | VoiceOver: "Open file location, button" | ☐ |

## 3. Video Info Sheet (Quality Selection)

| # | Action | Expected | Pass/Fail |
|---|--------|----------|-----------|
| 3.1 | Open sheet, press Tab | Focus moves to first quality radio button | ☐ |
| 3.2 | Tab again | Focus moves to next quality radio button | ☐ |
| 3.3 | Tab past all qualities | Focus moves to Cancel button | ☐ |
| 3.4 | Tab past Cancel | Focus moves to Download button | ☐ |
| 3.5 | Space on Download button | Sheet closes, download starts | ☐ |
| 3.6 | Escape key | Sheet closes (Cancel) | ☐ |

## 4. Home Screen

| # | Action | Expected | Pass/Fail |
|---|--------|----------|-----------|
| 4.1 | Tab to URL input field | VoiceOver: "URL input, text field" | ☐ |
| 4.2 | Tab to Extract button | VoiceOver: "Extract video info, button" | ☐ |
| 4.3 | Tab to suggestion chips | VoiceOver reads chip label | ☐ |
| 4.4 | Tab to filter chips | VoiceOver: "All, filter chip" etc. | ☐ |

## 5. Settings Screen

| # | Action | Expected | Pass/Fail |
|---|--------|----------|-----------|
| 5.1 | Tab through settings | Each SwitchListTile and ListTile receives focus in top-to-bottom order | ☐ |
| 5.2 | Space on a toggle | Toggle flips, VoiceOver announces new state | ☐ |

## 6. Batch Action Bar

| # | Action | Expected | Pass/Fail |
|---|--------|----------|-----------|
| 6.1 | Long-press to enter multi-select, Tab to batch bar | Focus moves to Pause batch, Resume batch, Cancel batch, Delete batch buttons in order | ☐ |
| 6.2 | Activate Delete batch | Confirmation dialog opens and is focusable | ☐ |

---

## Notes

- All `IconButton` widgets in `_buildActions()` have `tooltip:` set — these double as VoiceOver labels
- `Semantics(label: downloadCardSemanticLabel(...))` wraps each `_DownloadItemCard`
- `SemanticsService.announce()` fires on `DownloadStatus.completed` and `DownloadStatus.failed` transitions in `DownloadsNotifier._handleDownloadStatusChanges()`
- `FocusTraversalGroup(policy: OrderedTraversalPolicy())` wraps `VideoInfoSheet` body
