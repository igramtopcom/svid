# YouTube Autocomplete State — Design Spec

> Source: Stitch project `10022260214920217805`
> Screen ID: `123a3a9c23154ef88586bc4384775059`
> Status: **IMPLEMENTED** (v2 refinement complete)
> Current code: `lib/features/youtube_search/presentation/screens/youtube_explore_screen.dart` (autocomplete overlay builder)

## 1. Design Intent

**Purpose**: Autocomplete dropdown appears while typing in search bar. Shows suggestions from Google Suggest API or recent searches.

**Mood**: Fast, responsive, keyboard-friendly. Feels native — not a modal dialog.

**Key principle**: Overlay positioned directly below search bar. Keyboard navigation (arrows + Enter + Escape) for power users. Minimal latency with 300ms debounce.

## 2. Visual Structure

### 2.1 Layout — OverlayEntry

```
┌──────────────────────────────────────────────────┐
│ [SSvid]  Downloads  YouTube  Subs    [+] [?] [⚙]│  ← TopNavigationBar
├──────────────────────────────────────────────────┤
│  [🔍 lofi|                          ]  [Search]  │  ← Search bar (focused)
│  ┌──────────────────────────────────┐             │
│  │ 🔍 lofi hip hop          ◀── highlighted       │  ← Suggestion row (selected)
│  │ 🔍 lofi girl                                   │
│  │ 🔍 lofi beats to study                         │
│  │ 🔍 lofi jazz                                   │
│  │ 🔍 lofi rain                                   │
│  │ 🔍 lofi anime                                  │
│  │ 🔍 lofi christmas                              │
│  │ 🔍 lofi playlist 2024                          │
│  ├──────────────────────────────────┤             │
│  │ ⌨ ↑↓ navigate  ↵ select  esc close            │  ← Keyboard hint footer
│  └──────────────────────────────────┘             │
│                                                   │
│  (Discovery content visible behind overlay)       │
│                                                   │
└──────────────────────────────────────────────────┘
```

### 2.2 Dimensions

| Element | Value | Token mapping |
|---------|-------|---------------|
| Overlay width | 500px | `Positioned(width: 500)` |
| Overlay max-height | 400px | `BoxConstraints(maxHeight: 400)` |
| Overlay border-radius | 12px | `BorderRadius.circular(12)` |
| Overlay offset from search | 54px down | `Offset(0, 54)` |
| Suggestion row height | ~40px | Padding: 10px vertical + text |
| Suggestion row padding | 16px horizontal, 10px vertical | Custom |
| Keyboard hint padding | 16px horizontal, 8px vertical | Custom |
| Max suggestions shown | 8 | `.take(8)` |
| Max recent searches | 5 | `.take(5)` |

## 3. Token Extraction — Dark Mode

### 3.1 Colors

| Element | Stitch Hex | Flutter Mapping |
|---------|-----------|-----------------|
| Overlay bg | `#1C1B1B` | `const Color(0xFF1C1B1B)` |
| Overlay border | `#2A2A2A` | `const Color(0xFF2A2A2A)` |
| Overlay elevation | 12 | `elevation: 12` (dark), `8` (light) |
| Shadow | `Colors.black54` | Dark mode shadow |
| Highlighted row bg | `#2A2A2A` | `const Color(0xFF2A2A2A)` / `surfaceContainerHighest` |
| Highlighted icon | `primary` | `cs.primary` |
| Highlighted text | `onSurface` w500 | Full opacity, medium weight |
| Normal icon | `onSurface @ 35%` | `cs.onSurface.withValues(alpha: 0.35)` |
| Normal text | `onSurface @ 80%` | `cs.onSurface.withValues(alpha: 0.8)` |
| Arrow icon (↗) normal | `onSurface @ 20%` | `cs.onSurface.withValues(alpha: 0.2)` |
| Arrow icon highlighted | `onSurface @ 50%` | `cs.onSurface.withValues(alpha: 0.5)` |
| Keyboard hint text | `onSurface @ 25%` (11px) | `cs.onSurface.withValues(alpha: 0.25)` |
| Hint separator | `#2A2A2A` | Border(top: ...) |
| "Recent Searches" label | `onSurface @ 40%` | `cs.onSurface.withValues(alpha: 0.4)` |

### 3.2 Colors — Light Mode

| Element | Flutter Mapping |
|---------|-----------------|
| Overlay bg | `cs.surface` |
| Overlay border | `outlineVariant @ 30%` |
| Highlighted row bg | `surfaceContainerHighest` |
| Hint separator | `outlineVariant @ 20%` |

### 3.3 Search Bar (parent container)

| Element | Dark | Light |
|---------|------|-------|
| Bar bg | transparent | `cs.surface` |
| Bar bottom border | `outlineVariant @ 20%` | `outlineVariant @ 50%` |
| Input fill | `#1C1B1B` | `AppColors.surface2(context)` |
| Input focused border | `accentHighlight @ 40%`, 1.5px | Same |
| Hint text icon | `onSurface @ 40%` | Same |
| Clear icon | `onSurface @ 40%` | Same |
| Search button | `AppColors.brand` bg, white text | Same |

## 4. Keyboard Navigation

### 4.1 Key Bindings

| Key | Action |
|-----|--------|
| `↓` Arrow Down | Highlight next item (wraps to first) |
| `↑` Arrow Up | Highlight previous item (wraps to last) |
| `Enter` (with highlight) | Select highlighted suggestion → perform search |
| `Enter` (no highlight) | Submit raw text as search |
| `Escape` | Close overlay, reset highlight |

### 4.2 Implementation

```dart
KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
  // Only handle KeyDownEvent and KeyRepeatEvent
  // ArrowDown: (_highlightedIndex + 1) % _currentItems.length
  // ArrowUp: wrap to end if at 0
  // Escape: _removeAutocompleteOverlay()
  // Enter + highlighted: _onSuggestionTap(_currentItems[_highlightedIndex])
  // _autocompleteOverlay?.markNeedsBuild() after index change
}
```

The `Focus(onKeyEvent: _handleKeyEvent)` wraps the `TextField` to intercept keys before they reach the text input.

## 5. Data Flow

### 5.1 Suggestion Source

```
User types → 300ms debounce → youtubeAutocompleteProvider.fetchSuggestions(text)
                              → Google Suggest API (suggestqueries.google.com)
                              → List<String> suggestions
```

### 5.2 Fallback (no API suggestions)

When API suggestions are empty, overlay shows recent searches from `recentSearchesProvider` (SharedPreferences).

### 5.3 Combined Items List

```dart
_currentItems = suggestions.isNotEmpty
    ? suggestions.take(8).toList()
    : recents.take(5).toList();
```

This list drives both the ListView rendering and keyboard navigation indices.

## 6. Overlay Lifecycle

| Event | Action |
|-------|--------|
| Text changes (non-empty) | Show overlay (or markNeedsBuild if exists) |
| Text cleared | Remove overlay |
| Focus lost | Remove overlay (200ms delay for tap handling) |
| Focus regained (text non-empty) | Show overlay |
| Suggestion tapped | Set text, remove overlay, perform search |
| Search submitted | Remove overlay, unfocus, perform search |
| Back to discovery | Clear text, clear autocomplete, remove overlay |

## 7. Stitch Design vs Implementation

| Stitch Design Element | Implementation | Notes |
|----------------------|----------------|-------|
| Centered modal overlay | `CompositedTransformFollower` below search | Positioned, not centered — more natural UX |
| Cursor blink animation | Native TextField cursor | Flutter handles natively |
| "QUICK SEARCH MODE" link | Not implemented | No distinct mode needed |
| Blurred background | No blur | OverlayEntry sits above, no dimming |

## 8. Verification Checklist

- [x] Overlay appears when typing (non-empty text)
- [x] Overlay disappears when text cleared
- [x] Overlay disappears when focus lost (200ms delay)
- [x] Google Suggest API provides suggestions (300ms debounce)
- [x] Recent searches shown as fallback
- [x] "Recent Searches" label shown when displaying recents
- [x] Arrow Down/Up navigates suggestions
- [x] Enter selects highlighted suggestion
- [x] Enter without highlight submits raw text
- [x] Escape closes overlay
- [x] Highlighted row has distinct bg + icon color
- [x] Each row has search/history icon + ↗ arrow icon
- [x] Keyboard hint footer visible at bottom
- [x] Loading spinner shown while API fetching
- [x] Max 8 suggestions / 5 recent searches
- [x] Overlay positioned correctly below search bar
- [x] Dark/light mode properly themed
- [x] Overlay shadow and border per design tokens
