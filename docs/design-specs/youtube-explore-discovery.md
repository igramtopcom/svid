# YouTube Explore — Discovery Screen Design Spec

> Source: Stitch project `10022260214920217805`
> Screen ID: `1b679801cd0949d89f6541ac1a9cbbb6`
> Status: **IMPLEMENTED** (v2 refinement complete)
> Current code: `lib/features/youtube_search/presentation/widgets/youtube_discovery_view.dart`

## 1. Design Intent

**Purpose**: Default landing state of YouTube tab. Encourages exploration without a search query.

**Mood**: Rich, inviting, cinematic. Content discovery hub — not a blank search page.

**Key principle**: Guide users toward content via multiple entry points (categories, trending, subscriptions, recent searches) while maintaining the Nocturne dark aesthetic.

## 2. Visual Structure

### 2.1 Layout

```
┌──────────────────────────────────────────────────┐
│ [SSvid]  Downloads  YouTube  Subs    [+] [?] [⚙]│  ← TopNavigationBar (52px)
├──────────────────────────────────────────────────┤
│  [🔍 Search YouTube videos...]          [Search] │  ← Search bar (always visible)
├──────────────────────────────────────────────────┤
│                                                   │
│  [Music] [Gaming] [Education] [Entertainment]... │  ← Category quick-tabs (horizontal)
│                                                   │
│  🕐 Recent Searches                     [Clear]  │
│  [lofi hip hop] [react tutorial] [cooking] ×     │  ← Chips with delete
│                                                   │
│  🔥 Trending Now                                 │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐            │
│  │🎧 Lo-│ │🤖 AI │ │💪 Wor│ │🌿 Nat│            │  ← 4-col grid, icon+text cards
│  │Fi Hip│ │Chat  │ │kout  │ │ure   │            │
│  └──────┘ └──────┘ └──────┘ └──────┘            │
│                                                   │
│  🧭 Explore Categories                           │
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐    │
│  │ Music  │ │ Gaming │ │ Educa- │ │ Enter- │    │  ← 4-col grid, larger cards
│  │New Rel.│ │Live Now│ │ tion   │ │tainment│    │     with subtitles
│  └────────┘ └────────┘ └────────┘ └────────┘    │
│                                                   │
│  📺 Your Subscriptions                           │
│  (○) (○) (○) (○) (○) (○)  ← horizontal avatars  │
│  MKB  Fire Lofi  Mrw  LTT  Code                 │
│                                                   │
└──────────────────────────────────────────────────┘
```

### 2.2 Dimensions

| Element | Value | Token mapping |
|---------|-------|---------------|
| Max content width | 1120px | `ConstrainedBox(maxWidth: 1120)` |
| Horizontal padding | 24px | Custom |
| Category tab height | 36px | Custom |
| Category tab pill radius | 18px | `BorderRadius.circular(18)` |
| Trending card aspect ratio | 2.8:1 | `childAspectRatio: 2.8` |
| Category card aspect ratio | 1.5:1 | `childAspectRatio: 1.5` |
| Category icon container | 44x44px | Custom |
| Subscription avatar | 50x50px (+ 2px border) | Custom |
| Grid gap | 10px | `mainAxisSpacing/crossAxisSpacing: 10` |

### 2.3 Spacing

| Between | Gap |
|---------|-----|
| Category tabs → Recent Searches | 28px |
| Section header → Content | 12px |
| Recent Searches → Trending | 28px |
| Trending → Categories | 32px |
| Categories → Subscriptions | 32px |
| Bottom padding | 24px |

## 3. Token Extraction — Dark Mode

### 3.1 Colors

| Element | Stitch Hex | Flutter Mapping |
|---------|-----------|-----------------|
| Background (page) | `#131313` | RadialGradient: `#1A0508 → #131313` |
| Surface idle (cards/chips) | `#1C1B1B` | `const Color(0xFF1C1B1B)` |
| Surface hover | `#2A2A2A` | `const Color(0xFF2A2A2A)` / `surfaceContainerHighest` |
| Chip border (idle) | `#2A2A2A` | `const Color(0xFF2A2A2A)` |
| Chip border (hover) | category color @ 30% | `color.withValues(alpha: 0.3)` |
| Text primary | `#E5E2E1` | `onSurface` |
| Text secondary | `#E5E2E1 @ 70%` | `onSurface.withValues(alpha: 0.7)` |
| Text muted | `#E5E2E1 @ 40%` | `onSurface.withValues(alpha: 0.4)` |
| Section header glow | `#C41E3A @ 30%` | `Shadow(AppColors.accentHighlight, blur: 12)` |
| Category icon bg | category color @ 12% | `color.withValues(alpha: 0.12)` |

### 3.2 Colors — Light Mode

| Element | Flutter Mapping |
|---------|-----------------|
| Surface idle | `AppColors.lightSurface2` |
| Surface hover | `surfaceContainerHighest` |
| Border | `AppColors.lightBorder` |
| Category icon bg | category color @ 8% |

### 3.3 Typography

| Element | Style | Weight |
|---------|-------|--------|
| Section title | `titleSmall` | w600 |
| Category tab label | `labelMedium` | w500 |
| Trending card text | `bodySmall` | w500 |
| Category card title | `bodySmall` | w600 |
| Category card subtitle | `labelSmall` (11px) | w400 |
| Recent search chip | `bodySmall` | w400 |
| Subscription name | `labelSmall` (10px) | w400 |

## 4. Stitch Design vs Implementation

| Stitch Design Element | Implementation | Notes |
|----------------------|----------------|-------|
| Real trending thumbnails (16:9) | Icon + text cards | No trending API — curated topics |
| Category images with overlay | Icon + text cards | No category images available |
| "VIEW ALL" links | Not implemented | Static content, no pagination needed |
| Featured/large first trending card | Uniform grid | Grid simpler, all cards equal |
| Channel avatars from API | `subscribedChannelsStreamProvider` | Real user subscriptions |

## 5. Category Data

### Quick-Tabs (8 items)
Music (red), Gaming (purple), Education (amber), Entertainment (pink), Tech (cyan), Sports (green), Cooking (orange), News (blue)

### Trending Topics (8 items)
Lo-Fi Hip Hop, AI & ChatGPT, Workout Music, Nature Sounds, Tech Reviews, Cooking Shows, Travel Vlogs, Live Concerts

### Explore Categories (8 items, with subtitles)
Music/New Releases, Gaming/Live Now, Education/Learn Anything, Entertainment/Trending, Sports/Major Events, Tech/Future Tech, Film & Animation/Art & Craft, News/Global Updates

## 6. Interaction States

| Trigger | Effect |
|---------|--------|
| Hover category tab | Tint bg with category color, brighten border |
| Hover trending card | `#2A2A2A` bg, arrow icon brightens |
| Hover category card | `#2A2A2A` bg |
| Hover subscription avatar | Crimson border ring |
| Tap any category/trending/chip | → `onSearch(query)` → switches to Search Results mode |
| Tap recent search × | Removes individual search |
| Tap "Clear" | Removes all recent searches |

## 7. Verification Checklist

- [x] Category tabs scroll horizontally
- [x] Recent searches show chips with individual delete
- [x] Trending grid adapts columns (4/3/2) by width
- [x] Category grid adapts columns (4/3/2) by width
- [x] Subscriptions show only when user has subscribed channels
- [x] Recent searches show only when history exists
- [x] All hover states animate (150ms)
- [x] Dark/light mode properly themed
- [x] Radial gradient background in dark mode
- [x] Section headers have text glow in dark mode
- [x] Content centered with max-width constraint
