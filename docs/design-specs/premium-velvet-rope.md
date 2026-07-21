# Premium "Velvet Rope" Upgrade Prompt — Design Spec

> Source: Stitch project `9746799973876268727`
> Screen: `351adcfdf03041e5838298278910f8ca`
> Status: DRAFT — Pending Chairman review
> Current code: `lib/features/premium/presentation/widgets/upgrade_prompt_dialog.dart` (170 lines)

## 1. Design Intent

**Purpose**: Contextual upgrade gate. Shown when a user attempts to use a Premium-only feature. Modal overlays the current dashboard.

**Mood**: Exclusive, aspirational, but not aggressive. "This is the velvet rope — you can see the room, you just need the right pass."

**Key principle**: The feature they just tried to use is front and center. The user already wants it — reinforce that desire, then make the path to "yes" frictionless. Three sentences of copy maximum before the CTA.

## 2. Visual Structure

### 2.1 Layout

```
┌─────────── blurred/dimmed dashboard background ────────────┐
│  [content grid ghosted behind, blur(20px) brightness(0.4)] │
│                                                             │
│         ┌───────────────────────────────────┐              │
│         │  ┌─────┐                          │              │
│         │  │ ✦✦✦ │  ← premium icon, rotated │              │
│         │  └─────┘     gradient square       │              │
│         │                                    │              │
│         │   Unlock Your Full Potential       │              │
│         │                                    │              │
│         │  ┌──────────────────────────────┐  │              │
│         │  │ ▌ [icon]  Feature Name       │  │              │
│         │  │   Feature description        │  │              │
│         │  └──────────────────────────────┘  │              │
│         │                                    │              │
│         │  · AI-Powered Visual Search        │              │
│         │  · Cross-Device Vault Sync         │              │
│         │  · Priority Rendering Engine       │              │
│         │                                    │              │
│         │   Experience premium from $5.00/mo │              │
│         │                                    │              │
│         │  [    Upgrade to Premium    ]       │              │
│         │        Maybe Later                 │              │
│         └───────────────────────────────────┘              │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Dimensions

| Element | Value | Notes |
|---------|-------|-------|
| Modal width | 480px | Fixed |
| Modal height | 520px | Fixed |
| Modal border-radius | 14px | `BorderRadius.circular(14)` |
| Premium icon container | 64×64px | Rotated square, rounded-2xl (16px radius) |
| Premium icon rotation | 3 degrees | `Matrix4.rotationZ(3 * pi / 180)` |
| Glow circle behind icon | ~96px diameter | `blur-xl`, opacity 40%, premium-gradient fill |
| Feature highlight card | full width inside px-10 padding | `rounded-xl` (12px radius) |
| Feature card left border | 4px | `border-l-4` equivalent: left-side BoxDecoration border |
| Button height (primary) | 48px (h-12) | Full width |
| Button height (secondary) | 40px (h-10) | Full width, text only |
| Top/bottom padding | 32px top (mt-8), 40px bottom (pb-10) | |
| Horizontal padding | 40px (px-10) | All content sections |

### 2.3 Spacing (top to bottom)

| Between | Gap | Notes |
|---------|-----|-------|
| Top edge → Icon center | 32px (mt-8) | |
| Icon → Title | 24px (mt-6) | |
| Title → Feature card | 24px (mt-6) | |
| Feature card → Value props | 24px (mt-6) | |
| Value prop items | 12px (space-y-3) | |
| Value props → Pricing teaser | `mt-auto mb-4` | Pushed to bottom via Spacer |
| Pricing teaser → Buttons | inline in Column | |
| Between buttons | 12px (gap-3) | |
| Buttons → Bottom edge | 40px (pb-10) | |

## 3. Token Extraction

### 3.1 Colors (M3 Dark Palette)

| Element | Stitch Hex | Flutter Mapping | Notes |
|---------|-----------|-----------------|-------|
| Modal background | `#1A1A1A` | `Color(0xFF1A1A1A)` | NOT `colorScheme.surface` — custom dark card |
| Modal shadow | `rgba(0,0,0,0.6)` | `Colors.black.withOpacity(0.6)` | `blurRadius: 64, spreadRadius: 0` |
| Dashboard blur overlay | `#131313` @ 60% | `Color(0xFF131313).withOpacity(0.6)` | Stacked on backdrop blur |
| Modal top tonal layer | `surface-container-high/20` | `Color(0xFF2A2A2A).withOpacity(0.2)` | Gradient: top to transparent, ~30px tall |
| Modal glassmorphism reflection | `white/5` | `Colors.white.withOpacity(0.05)` | Gradient: top-half only, top to transparent |
| Silk texture overlay | `mix-blend-overlay` @ 30% opacity | `BlendMode.overlay`, opacity 0.3 | Decorative only — can omit if no asset |
| Icon gradient start | `#8D021F` | `AppColors.brand` | premium-gradient stop 0% |
| Icon gradient mid | `#AC012C` | `Color(0xFFAC012C)` | premium-gradient stop 50% |
| Icon gradient end | `#F48B9B` | `Color(0xFFF48B9B)` | premium-gradient stop 100% |
| Icon glow | premium-gradient @ 40% opacity | `AppColors.brand.withOpacity(0.4)` | blur-xl behind icon |
| Stars icon | `#FFFFFF` | `Colors.white` | |
| Title text | `#FFFFFF` | `Colors.white` | |
| Feature card background | `surface-container` | `Color(0xFF201F1F)` | `#201f1f` |
| Feature card left border | `primary-container` | `Color(0xFF8D021F)` | `AppColors.brand` |
| Feature card icon | `primary` | `Color(0xFFFFB3B2)` | `colorScheme.primary` in dark |
| Feature card title | `on-surface` | `Color(0xFFE5E2E1)` | `colorScheme.onSurface` |
| Feature card description | `on-surface-variant` | `Color(0xFFE1BEBD)` | `colorScheme.onSurfaceVariant` |
| Value prop icon | `primary` (20px) | `Color(0xFFFFB3B2)` | Same as feature card icon |
| Value prop text | `on-surface` @ 90% | `Color(0xFFE5E2E1).withOpacity(0.9)` | 13px |
| Pricing teaser text | `outline` | `Color(0xFFA88989)` | `colorScheme.outline` in dark |
| Primary button gradient | premium-gradient | `LinearGradient(...)` | `135deg, #8D021F → #AC012C → #F48B9B` |
| Primary button text | `#FFFFFF` | `Colors.white` | |
| Primary button glow | `rgba(141,2,31,0.4)` | `Color(0xFF8D021F).withOpacity(0.4)` | `BoxShadow blurRadius: 20` |
| Secondary button text (idle) | `on-surface-variant` | `Color(0xFFE1BEBD)` | `colorScheme.onSurfaceVariant` |
| Secondary button text (hover) | `tertiary` | `Color(0xFFFFB2BC)` | `colorScheme.tertiary` in dark |

### 3.2 Full M3 Dark Palette Reference

| Token | Hex | Usage |
|-------|-----|-------|
| `surface` | `#131313` | Backdrop overlay color |
| `surface-container` | `#201F1F` | Feature highlight card bg |
| `surface-container-high` | `#2A2A2A` | Modal tonal layer gradient |
| `surface-container-highest` | `#353534` | (available, unused here) |
| `on-surface` | `#E5E2E1` | Feature card title, value prop text |
| `on-surface-variant` | `#E1BEBD` | Feature card description, "Maybe Later" idle |
| `primary` | `#FFB3B2` | Feature card icon, value prop icons |
| `primary-container` | `#8D021F` | Feature card left border |
| `secondary-container` | `#AC012C` | premium-gradient mid stop |
| `outline` | `#A88989` | Pricing teaser text |
| `tertiary` | `#FFB2BC` | "Maybe Later" hover state |
| `inverse-primary` | `#B32736` | (available, unused here) |

### 3.3 Typography

| Element | Size | Weight | Tracking | Style | Flutter Mapping |
|---------|------|--------|----------|-------|-----------------|
| Title "Unlock Your Full Potential" | 30px (3xl) | bold (700) | tight (-0.02em) | normal | `textTheme.headlineMedium` adjusted, or `fontSize: 28, fontWeight: FontWeight.w700` |
| Feature card feature name | 14px | semibold (600) | normal | normal | `textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)` |
| Feature card description | 13px (sm) | regular (400) | normal | normal | `textTheme.bodySmall` |
| Value prop text | 13px | medium (500) | wide (0.15em) | normal | `textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.15)` |
| Pricing teaser | 11px | regular (400) | 0.15em | italic | `textTheme.labelSmall?.copyWith(letterSpacing: 0.15, fontStyle: FontStyle.italic)` |
| Primary button label | 14px | semibold (600) | normal | normal | `textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)` |
| "Maybe Later" label | 14px | regular (400) | normal | normal | `textTheme.labelLarge` |

### 3.4 Effects

| Effect | Value | Flutter Implementation |
|--------|-------|----------------------|
| Dashboard backdrop blur | `blur(20px) brightness(0.4)` | `BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20))` + overlay `Colors.black.withOpacity(0.6)` |
| Modal drop shadow | `0 24px 64px rgba(0,0,0,0.6)` | `BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 64, offset: Offset(0, 24))` |
| Premium icon glow | `blur-xl`, premium-gradient, opacity 40% | `Container` with `BoxDecoration(gradient: premiumGradient, shape: BoxShape.circle)` + `ImageFilter.blur(sigmaX: 24, sigmaY: 24)` or `BackdropFilter` approach; alternatively `BoxShadow(color: brand.withOpacity(0.4), blurRadius: 32, spreadRadius: 8)` |
| Primary button glow | `0 0 20px rgba(141,2,31,0.4)` | `BoxShadow(color: Color(0xFF8D021F).withOpacity(0.4), blurRadius: 20, spreadRadius: 0)` |
| Primary button press | `scale(0.98)` | `GestureDetector` + `AnimatedScale` with `scale: _pressed ? 0.98 : 1.0`, duration 100ms |
| Modal top tonal wash | gradient from `surface-container-high/20` → transparent | `LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2A2A2A).withOpacity(0.2), Colors.transparent])` over top ~30px |
| Glassmorphism reflection | gradient from `white/5` → transparent, top-half | Same as above: `LinearGradient` on top 50%, `colors: [Colors.white.withOpacity(0.05), Colors.transparent]` |

## 4. Gap Analysis — Design vs Current Code

### 4.1 MAJOR Changes

| # | Current | Design | Impact |
|---|---------|--------|--------|
| 1 | Standard `AlertDialog` (system-styled, auto-width) | Custom `Dialog` with fixed 480×520px, `#1A1A1A` bg, 14px radius, manual shadow | Full widget replacement — `AlertDialog` cannot be used |
| 2 | `workspace_premium_rounded` icon, 48px, `cs.primary` color, no container | 64×64 gradient square, rotate(3°), `stars` icon white, glow circle behind | `_PremiumIcon` sub-widget needed |
| 3 | Feature card: `surfaceContainerHighest` bg, simple `Row` (icon + name only) | Feature card: `surface-container` bg, 4px left border in `primary-container`, icon + name row + description text below | Card needs `Column` inside, left-border via `BoxDecoration.border` |
| 4 | No value proposition list | 3 value prop items below feature card: icon (20px, primary) + text (13px, on-surface/90, tracking-wide) | New `_ValuePropList` sub-widget |
| 5 | No pricing teaser | Italic 11px pricing teaser pushed to bottom: "Experience the premium life from $5.00/month." | New `_PricingTeaser` sub-widget, `mt-auto` = `Spacer()` before it |
| 6 | `TextButton` ("Cancel") + `FilledButton.icon` ("Upgrade") — side by side | Full-width gradient primary CTA (h-12) + full-width text-only "Maybe Later" (h-10), stacked vertically | New `_UpgradeButtons` sub-widget, `Column` not `Row` |
| 7 | No background treatment | Blurred + dimmed dashboard behind the Dialog | `showDialog` with custom `barrierColor` + `BackdropFilter` in barrier widget |
| 8 | `showDialog<bool>` returns `false` on Cancel, `true` on Upgrade | Returns `true` on Upgrade, `null` on dismiss/Maybe Later | Change Cancel path: `pop(null)` not `pop(false)` — matches existing static `show()` doc |

### 4.2 KEEP (functional requirements not in design)

| # | Element | Reason |
|---|---------|--------|
| 1 | `PremiumFeature?` parameter | Architecture contract — callers pass the triggering feature |
| 2 | `UpgradePromptDialog.show()` static factory | All callers use this — signature must not change |
| 3 | `_featureIcon(PremiumFeature)` logic | 16-feature switch — keep as-is, used in feature card |
| 4 | `_featureDisplayName(PremiumFeature)` logic | Same — localized display names |
| 5 | `featureIcon()` / `featureDisplayName()` public aliases | Other widgets depend on these for reuse |
| 6 | `AppLocalizations.premiumUpgradeTitle` / `premiumUpgrade` strings | Existing i18n keys — reuse for title and CTA label |

### 4.3 Dynamic Feature Highlight Card

The feature card content changes based on `PremiumFeature?`:

- **When `feature != null`**: Show the specific gated feature — its icon, display name, and a short description.
- **When `feature == null`**: Show a generic "Batch Downloads" fallback (design default, `dynamic_feed` icon) with generic description.

Feature description strings (new, need addition to `AppLocalizations` or inline for now):

| PremiumFeature | Icon | Description (short) |
|---------------|------|---------------------|
| `aiSummarization` | `auto_awesome` | Summarize any video content instantly with AI |
| `aiSubtitleTranslation` | `translate` | Auto-translate subtitles to 50+ languages |
| `smartFeed` | `dynamic_feed` | Curate your download queue by topic or creator |
| `cloudSync` | `sync_saved_locally` | Access your library on any device, anytime |
| `remoteControl` | `devices` | Control downloads from your phone or tablet |
| `encryptedVault` | `enhanced_encryption` | Store sensitive downloads with AES-256 encryption |
| `appLock` | `lock` | Protect your library with biometrics or PIN |
| `auditLog` | `security` | Full activity log of every download and action |
| `analyticsDashboard` | `bar_chart` | Visualize your download habits and trends |
| `downloadMetrics` | `speed` | Real-time speed, queue stats, and progress data |
| `storageReport` | `storage` | Understand and manage your disk usage |
| `scheduledDownloads` | `schedule` | Queue downloads for off-peak hours automatically |
| `bandwidthScheduling` | `wifi` | Set bandwidth limits by time of day |
| `downloadTemplates` | `bookmarks` | Save format/quality presets for one-tap downloads |
| `smartCollections` | `folder_special` | Auto-organize downloads by channel, tag, or date |
| `privacyDashboard` | `privacy_tip` | Review and control all data SSvid stores |
| `null` (generic) | `dynamic_feed` | Download entire playlists and channels in one click |

## 5. Widget Spec — Flutter Implementation

### 5.1 Dialog Presentation

```dart
// In UpgradePromptDialog.show():
static Future<bool?> show(BuildContext context, {PremiumFeature? feature}) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (_) => UpgradePromptDialog(feature: feature),
  );
}
```

Note: The `barrierColor` at 60% black handles the dim. The blur effect on the background requires wrapping the dialog in a `BackdropFilter`. Since Flutter's `showDialog` does not natively support a blurred barrier, use one of two approaches:

**Approach A (recommended — simpler)**: Accept that the blur is a visual enhancement only; use a dark semi-transparent barrier (`barrierColor: Color(0xFF131313).withOpacity(0.75)`) without true blur. Visually close enough for desktop.

**Approach B (full fidelity)**: Use `showGeneralDialog` with a custom `pageBuilder` that wraps the entire stack in `BackdropFilter`:

```dart
showGeneralDialog(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Upgrade prompt',
  barrierColor: Colors.transparent,
  pageBuilder: (ctx, anim1, anim2) => Stack(
    children: [
      // Blur layer
      BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(color: Color(0xFF131313).withOpacity(0.6)),
      ),
      // Modal
      Center(child: UpgradePromptDialog(feature: feature)),
    ],
  ),
);
```

### 5.2 Widget Tree (target)

```dart
// UpgradePromptDialog.build()
Dialog(
  backgroundColor: Colors.transparent,
  elevation: 0,
  child: SizedBox(
    width: 480,
    height: 520,
    child: Stack(
      children: [
        // Layer 0: Modal container with decoration
        _ModalContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Premium icon
              _PremiumIcon(),          // mt-8, centered

              // 2. Title
              _ModalTitle(),           // mt-6, px-10

              // 3. Feature highlight card
              _FeatureHighlightCard(feature: feature),  // mt-6, px-10

              // 4. Value proposition list
              _ValuePropList(),        // mt-6, px-10

              // 5. Spacer → pricing teaser pinned to bottom area
              const Spacer(),

              // 6. Pricing teaser
              _PricingTeaser(),        // mb-4, px-10

              // 7. Buttons
              _UpgradeButtons(),       // px-10, pb-10
            ],
          ),
        ),

        // Layer 1: Glassmorphism reflection (top-half gradient overlay)
        _GlassmorphismOverlay(),
      ],
    ),
  ),
)
```

### 5.3 Component: `_ModalContainer`

```dart
Widget _ModalContainer({required Widget child}) {
  return Container(
    width: 480,
    height: 520,
    decoration: BoxDecoration(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [
        BoxShadow(
          color: Color(0x99000000),  // rgba(0,0,0,0.6)
          blurRadius: 64,
          offset: Offset(0, 24),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: child,
    ),
  );
}
```

### 5.4 Component: `_PremiumIcon`

```dart
// Rotated gradient square with stars icon + glow behind
Widget _PremiumIcon() {
  const premiumGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    transform: GradientRotation(135 * pi / 180),
    colors: [Color(0xFF8D021F), Color(0xFFAC012C), Color(0xFFF48B9B)],
    stops: [0.0, 0.5, 1.0],
  );

  return Padding(
    padding: const EdgeInsets.only(top: 32),
    child: Center(
      child: SizedBox(
        width: 96, height: 96,  // glow overflow
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Glow circle behind icon
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: premiumGradient,
              ),
              // Use ImageFilter.blur via BackdropFilter is not applicable here.
              // Instead: large blurRadius BoxShadow approximates blur-xl glow.
            ),
            // Actual shadow/glow via outer BoxShadow on icon container
            Transform(
              transform: Matrix4.rotationZ(3 * pi / 180),
              alignment: Alignment.center,
              child: Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  gradient: premiumGradient,
                  borderRadius: BorderRadius.circular(16),  // rounded-2xl
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8D021F).withOpacity(0.4),
                      blurRadius: 32,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.stars_rounded,   // "stars" icon, FILL 1 equivalent
                  color: Colors.white,
                  size: 32,              // 4xl → ~32px on desktop
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
```

### 5.5 Component: `_ModalTitle`

```dart
Widget _ModalTitle() {
  return Padding(
    padding: const EdgeInsets.only(top: 24, left: 40, right: 40),
    child: Text(
      'Unlock Your Full Potential',
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: -0.5,
        height: 1.2,
      ),
    ),
  );
}
```

Note: `AppLocalizations.premiumUpgradeTitle` may be used here if the string matches. If it reads "Upgrade to Premium" or similar, use the hardcoded string above and add a new l10n key `premiumVelvetTitle` = "Unlock Your Full Potential".

### 5.6 Component: `_FeatureHighlightCard`

```dart
Widget _FeatureHighlightCard({required PremiumFeature? feature}) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;

  final icon = feature != null
      ? UpgradePromptDialog.featureIcon(feature)
      : Icons.dynamic_feed_rounded;
  final name = feature != null
      ? UpgradePromptDialog.featureDisplayName(feature)
      : 'Batch Downloads';
  final description = _featureDescription(feature);  // see Section 4.3 table

  return Padding(
    padding: const EdgeInsets.only(top: 24, left: 40, right: 40),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF201F1F),  // surface-container
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: const Color(0xFF8D021F),  // primary-container
            width: 4,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: tt.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFE5E2E1),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: tt.bodySmall?.copyWith(
              color: const Color(0xFFE1BEBD),  // on-surface-variant
            ),
          ),
        ],
      ),
    ),
  );
}
```

### 5.7 Component: `_ValuePropList`

```dart
// 3 static value propositions — always the same regardless of triggering feature
Widget _ValuePropList() {
  final cs = Theme.of(context).colorScheme;

  const items = [
    (Icons.tune_rounded, 'AI-Powered Visual Search'),                // temp_preferences_custom equivalent
    (Icons.sync_saved_locally_rounded, 'Cross-Device Vault Sync'),
    (Icons.speed_rounded, 'Priority Rendering Engine'),
  ];

  return Padding(
    padding: const EdgeInsets.only(top: 24, left: 40, right: 40),
    child: Column(
      children: [
        for (final (icon, label) in items) ...[
          Row(
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.15,
                  color: const Color(0xFFE5E2E1).withOpacity(0.9),
                ),
              ),
            ],
          ),
          if (item != items.last) const SizedBox(height: 12),
        ],
      ],
    ),
  );
}
```

Implementation note: The `if (item != items.last)` pattern does not work on records directly — use `for (int i = 0; i < items.length; i++)` with an index check instead, or `ListView.separated`.

### 5.8 Component: `_PricingTeaser`

```dart
Widget _PricingTeaser() {
  return Padding(
    padding: const EdgeInsets.only(left: 40, right: 40, bottom: 16),
    child: Text(
      'Experience the premium life from \$5.00/month.',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 11,
        fontStyle: FontStyle.italic,
        letterSpacing: 0.15,
        color: const Color(0xFFA88989),  // outline
      ),
    ),
  );
}
```

### 5.9 Component: `_UpgradeButtons`

```dart
Widget _UpgradeButtons() {
  const premiumGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    transform: GradientRotation(135 * pi / 180),
    colors: [Color(0xFF8D021F), Color(0xFFAC012C), Color(0xFFF48B9B)],
    stops: [0.0, 0.5, 1.0],
  );

  return Padding(
    padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
    child: Column(
      children: [
        // Primary: gradient CTA
        _PressableButton(
          onTap: () => Navigator.of(context).pop(true),
          child: Container(
            height: 48,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: premiumGradient,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x668D021F),  // rgba(141,2,31,0.4)
                  blurRadius: 20,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              AppLocalizations.premiumUpgrade,  // "Upgrade to Premium"
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Secondary: "Maybe Later" text button
        SizedBox(
          height: 40,
          width: double.infinity,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFE1BEBD),  // on-surface-variant
            ),
            child: const Text('Maybe Later'),
          ),
        ),
      ],
    ),
  );
}
```

`_PressableButton` is a simple `StatefulWidget` that wraps child in `AnimatedScale` (scale 0.98 when pressed, 1.0 when released), `duration: Duration(milliseconds: 100)`.

### 5.10 Component: `_GlassmorphismOverlay`

```dart
// Top-half gradient from white/5 to transparent — renders over entire modal
Widget _GlassmorphismOverlay() {
  return Positioned(
    top: 0, left: 0, right: 0,
    height: 260,  // top half of 520px modal
    child: Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x0DFFFFFF),  // white/5
            Colors.transparent,
          ],
        ),
      ),
    ),
  );
}
```

## 6. State Flow

### 6.1 States

This dialog is stateless by design — it presents information and returns a result. No internal async operations.

```
SHOW (feature: PremiumFeature?) → User reads modal
  ↓
  [Upgrade to Premium] → pop(true)  → caller navigates to premium screen
  [Maybe Later]        → pop(null)  → caller dismisses, user stays put
  [Barrier tap]        → pop(null)  → same as Maybe Later
```

### 6.2 Caller Contract

```dart
final result = await UpgradePromptDialog.show(context, feature: feature);
if (result == true) {
  // Navigate to premium/payment screen
}
// null → do nothing, user stays on current screen
```

### 6.3 Feature Highlight Card — Dynamic Content

| Trigger | Icon | Card Title | Card Description |
|---------|------|-----------|-----------------|
| `null` | `dynamic_feed` | "Batch Downloads" | "Download entire playlists and channels in one click." |
| `aiSummarization` | `auto_awesome` | "AI Summarization" | "Summarize any video content instantly with AI." |
| `aiSubtitleTranslation` | `translate` | "AI Subtitle Translation" | "Auto-translate subtitles to 50+ languages." |
| `smartFeed` | `dynamic_feed` | "Smart Feed" | "Curate your download queue by topic or creator." |
| `cloudSync` | `sync_saved_locally` | "Cloud Sync" | "Access your library on any device, anytime." |
| `remoteControl` | `devices` | "Remote Control" | "Control downloads from your phone or tablet." |
| `encryptedVault` | `enhanced_encryption` | "Encrypted Vault" | "Store sensitive downloads with AES-256 encryption." |
| `appLock` | `lock` | "App Lock" | "Protect your library with biometrics or PIN." |
| `auditLog` | `security` | "Audit Log" | "Full activity log of every download and action." |
| `analyticsDashboard` | `bar_chart` | "Analytics Dashboard" | "Visualize your download habits and trends." |
| `downloadMetrics` | `speed` | "Download Metrics" | "Real-time speed, queue stats, and progress data." |
| `storageReport` | `storage` | "Storage Report" | "Understand and manage your disk usage." |
| `scheduledDownloads` | `schedule` | "Scheduled Downloads" | "Queue downloads for off-peak hours automatically." |
| `bandwidthScheduling` | `wifi` | "Bandwidth Scheduling" | "Set bandwidth limits by time of day." |
| `downloadTemplates` | `bookmarks` | "Download Templates" | "Save format/quality presets for one-tap downloads." |
| `smartCollections` | `folder_special` | "Smart Collections" | "Auto-organize downloads by channel, tag, or date." |
| `privacyDashboard` | `privacy_tip` | "Privacy Dashboard" | "Review and control all data SSvid stores." |

Note: `_featureDisplayName()` already exists and covers the Title column above. Only `_featureDescription()` is new — add as a private static method inside `UpgradePromptDialog`.

## 7. Token Changes Required

### 7.1 No new tokens required in `app_colors.dart`

All hex values used in this design are either:
- Already in the M3 color scheme (accessed via `colorScheme.*`)
- Defined as `AppColors.brand` (`#8D021F`) which already exists
- Used as inline `Color(0xFF...)` constants local to this widget

If `AppColors.accentHighlight` (`#C41E3A`) was added per `first-time-setup.md` spec, it is not needed here — this modal uses `AppColors.brand` for the gradient start and the mid-stop is inline.

One optional addition for shared use:

```dart
// Optional: extracted as constant if used in multiple widgets
static const Color _premiumGradientMid = Color(0xFFAC012C);
static const Color _premiumGradientHighlight = Color(0xFFF48B9B);
```

### 7.2 New `AppLocalizations` keys (optional — can be inline initially)

| Key | Value (EN) | Usage |
|-----|-----------|-------|
| `premiumVelvetTitle` | "Unlock Your Full Potential" | Modal title (if different from existing `premiumUpgradeTitle`) |
| `premiumVelvetMaybeLater` | "Maybe Later" | Secondary button label |
| `premiumVelvetPricingTeaser` | "Experience the premium life from \$5.00/month." | Bottom pricing text — note: price may need to be dynamic |
| `premiumFeatureDescription_*` | (16 entries per feature) | Feature card description text |

For the initial implementation: inline strings are acceptable. Externalize to `AppLocalizations` in a follow-up pass.

### 7.3 Pricing string — dynamic concern

The `$5.00/month` figure in the pricing teaser must stay in sync with actual Stripe pricing. Options:

- **Option A (simple)**: Hardcode and update manually with each pricing change.
- **Option B (live)**: Fetch from backend `GET /api/v1/product` and display the lowest monthly price. Show nothing if request fails.
- **Decision for Chairman**: Confirm approach before implementation. Spec assumes Option A initially.

### 7.4 Icon notes

| Design term | Material icon to use |
|-------------|---------------------|
| `stars` (FILL 1) | `Icons.stars_rounded` |
| `dynamic_feed` (FILL 1) | `Icons.dynamic_feed_rounded` |
| `temp_preferences_custom` | `Icons.tune_rounded` (closest Material equivalent) |
| `sync_saved_locally` | `Icons.sync_saved_locally_rounded` |
| `speed` | `Icons.speed_rounded` |

FILL 1 variant: Flutter Material Symbols can be used via `font_awesome_flutter` or `material_symbols_icons` package for true FILL=1 variants. If neither package is in `pubspec.yaml`, use standard `Icons.*` as listed above — visually close.

## 8. Platform Considerations

### 8.1 Desktop (macOS / Windows / Linux) — Primary Target

- **Fixed 480×520 modal**: Works correctly on desktop where window is large enough. No scrolling needed.
- **`Dialog` widget**: Use `Dialog` (not `AlertDialog` or `SimpleDialog`) for full layout control.
- **Backdrop blur**: Approach A (dark barrier, no blur) is safe and requires no additional packages. Approach B (true blur) works on desktop Flutter — no platform restrictions.
- **Hover states for "Maybe Later"**: On desktop, `MouseRegion` + `onEnter`/`onExit` changes text color from `on-surface-variant` to `tertiary`. Use `StatefulWidget` or `InkWell` with `overlayColor`.
- **Press animation on CTA**: `GestureDetector` `onTapDown`/`onTapUp`/`onTapCancel` controlling `AnimatedScale` works on all desktop platforms.
- **Window size constraint**: If window is narrower than 480px (unlikely for desktop target, minimum window is larger), the modal will clip. Not a concern.

### 8.2 macOS Specifics

- `showDialog` barrier tap dismisses correctly (system behavior).
- No additional macOS-specific handling required.

### 8.3 Windows Specifics

- Same behavior as macOS.
- `BackdropFilter` blur (Approach B) works on Windows with Flutter's Impeller renderer.

### 8.4 Linux Specifics

- Backdrop blur (Approach B) may have performance variance depending on compositor. Approach A recommended for Linux.

### 8.5 NOT Designed For

This modal is desktop-only. Do not use as-is on mobile form factors — the fixed 480px width would overflow on phone screens.

## 9. Animation Spec

| Animation | Trigger | Duration | Curve | Notes |
|-----------|---------|----------|-------|-------|
| Modal entrance (scale + fade) | `showDialog` open | 220ms | `Curves.easeOutCubic` | Flutter's default Dialog animation — acceptable; can override with custom `transitionBuilder` in `showGeneralDialog` |
| Modal exit (fade) | pop | 150ms | `Curves.easeIn` | Default |
| Primary button press (scale) | `onTapDown` / `onTapUp` | 100ms | `Curves.easeOut` | `AnimatedScale`: 1.0 → 0.98 → 1.0 |
| "Maybe Later" hover (color) | `MouseRegion` enter/exit | 150ms | `Curves.easeOut` | `AnimatedDefaultTextStyle` or `TweenAnimationBuilder<Color>` |
| Backdrop blur appearance | With modal entrance | Same as modal | Same as modal | If using Approach B — blur is part of same `showGeneralDialog` transition |

No staggered entrance animations within the modal content — the design reads as a single composed unit that appears together.

## 10. Verification Checklist

- [ ] Modal is exactly 480×520px (verify with Flutter DevTools layout inspector)
- [ ] Modal background is `#1A1A1A` with 14px border-radius
- [ ] Drop shadow renders: offset Y+24, blur 64, 60% black
- [ ] Premium icon: 64×64, rotated 3°, gradient square, `stars_rounded` icon white
- [ ] Glow behind icon visible (reddish bloom)
- [ ] Title "Unlock Your Full Potential" — white, 28px, bold, tight tracking
- [ ] Feature card: `#201F1F` bg, 4px left border in `#8D021F`
- [ ] Feature card icon + name + description render in correct hierarchy
- [ ] Feature card content is dynamic — changes per triggering `PremiumFeature`
- [ ] Feature card falls back to "Batch Downloads" when `feature == null`
- [ ] Value prop list shows 3 items with correct icons and labels
- [ ] Pricing teaser is italic, 11px, `outline` color, pinned above buttons
- [ ] Primary button is full-width, 48px, premium gradient, white semibold text
- [ ] Primary button glow shadow renders correctly
- [ ] Primary button scale animation (0.98) on press
- [ ] "Maybe Later" is full-width, 40px, text-only, `on-surface-variant` color
- [ ] "Maybe Later" changes to `tertiary` color on hover
- [ ] Upgrade button returns `true` via `Navigator.pop(true)`
- [ ] "Maybe Later" returns `null` via `Navigator.pop(null)`
- [ ] Barrier tap dismisses modal and returns `null`
- [ ] Glassmorphism top-half reflection gradient visible (subtle white shimmer)
- [ ] `UpgradePromptDialog.show()` signature unchanged — existing callers not broken
- [ ] `featureIcon()` and `featureDisplayName()` public methods still accessible
- [ ] `flutter analyze` passes with 0 issues on the modified file
- [ ] Dark mode: all colors verified against Section 3.1 table
- [ ] No hardcoded `$5.00` if pricing source decision is Option B
