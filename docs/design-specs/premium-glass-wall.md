# Premium Glass Wall — Design Spec

> Source: Stitch project `9746799973876268727`
> Screen: `ac7c123582dc48fbac0a5a25ffeba8aa`
> Status: DRAFT — Pending Chairman review
> Current code: `lib/features/premium/presentation/widgets/premium_gate.dart` (130 lines)

## 1. Design Intent

**Purpose**: Feature gate overlay that blocks premium content. Shown whenever a free-tier user reaches a feature gated by `PremiumGate`.

**Mood**: "You can almost touch it." The glass wall lets users see the value they're missing — blurred content is tantalizing, not hidden. The lock overlay is confident but not aggressive: cinematic, premium, deserved.

**Key principle**: Three-layer sandwich. The content exists and renders normally (layer 0). A glass frost gradient fades it into mystery (layer 1). A centered gate prompt converts (layer 2). The split between visible content above and gated content below is the hook — users see their library working fine, then hit the wall exactly at the premium boundary.

## 2. Visual Structure

### 2.1 Layout — Three-Layer Stack

```
┌──────────────────────────────────────────────────────────────────┐
│  TOP HALF — visible (z-0, NOT blurred)                           │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ Vault Storage            [Sort ▾] [Filter ▾]              │  │
│  │                                                            │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐                 │  │
│  │  │ [thumb]  │  │ [thumb]  │  │ [thumb]  │                 │  │
│  │  │ title    │  │ title    │  │ title    │                 │  │
│  │  └──────────┘  └──────────┘  └──────────┘                 │  │
│  └────────────────────────────────────────────────────────────┘  │
├──────────────────────────────────────────────────────────────────┤
│  BOTTOM HALF — gated zone                                        │
│                                                                  │
│  Layer 0 (z-0): Premium content — blur(8px)                      │
│  ┌──────────────────────────────┐  ┌──────────────┐             │
│  │  Advanced Analytics          │  │  Smart        │             │
│  │  [▓▓▓░░][▓▓▓▓░][▓░░░░░]     │  │  Collections  │             │
│  │  bar chart visualization     │  │  · Favorites  │             │
│  └──────────────────────────────┘  │  · Tutorial   │             │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌────┐│  · Saved      │             │
│  │      │ │      │ │      │ │    ││  · Liked      │             │
│  └──────┘ └──────┘ └──────┘ └────┘└──────────────┘             │
│                                                                  │
│  Layer 1 (z-10): Glass frost — backdrop-filter blur(12px)        │
│            + mask gradient(transparent → black 15%)              │
│            + opacity-40, pointer-events-none                     │
│                                                                  │
│  Layer 2 (z-30): Gate overlay — centered                         │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              ◉  [glow halo]  🔒                          │   │
│  │         ┌─────────────────────────────┐                  │   │
│  │         │  SSVID PREMIUM FEATURE      │  ← badge         │   │
│  │         └─────────────────────────────┘                  │   │
│  │                                                           │   │
│  │           Unlock the Full Vault.                         │   │
│  │                                                           │   │
│  │    [description text — max-width 576px, 2 lines]         │   │
│  │                                                           │   │
│  │  [  Upgrade to SSvid Premium  ]  View Feature Comparison →│  │
│  │                                                           │   │
│  │    SECURE CHECKOUT • NO ADS • UNLIMITED SPEED            │   │
│  └──────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

### 2.2 The Split Pattern

The "visible top / gated bottom" is achieved by `PremiumGate` wrapping only the premium section, not the full screen. Whatever renders above the `PremiumGate` widget in the parent layout is naturally visible. The glass wall effect belongs entirely within the gated widget bounds.

### 2.3 Dimensions

| Element | Value | Token mapping |
|---------|-------|---------------|
| Blurred content sigma | 8px x/y | `ImageFilter.blur(sigmaX: 8, sigmaY: 8)` |
| Glass frost blur sigma | 12px | `ImageFilter.blur(sigmaX: 12, sigmaY: 12)` |
| Glass frost opacity | 40% | `Opacity(opacity: 0.40)` |
| Gradient mask fade start | 0% transparent | Top of gated zone |
| Gradient mask fade end | 15% opaque black | `Alignment(-1, -0.70)` approx |
| Lock icon container size | p-5 (20px pad) + icon | `EdgeInsets.all(20)` |
| Lock icon size | ~40px (5xl) | `size: 40` |
| Lock glow blur radius | blur-2xl (~40px) | `blurRadius: 40` |
| Lock glow container scale | 150% relative | `Transform.scale(scale: 1.5)` |
| Badge padding | px-16 py-6 | `EdgeInsets.symmetric(horizontal: 16, vertical: 6)` |
| Badge border-radius | full (999px) | `BorderRadius.circular(999)` |
| Title max font size | 48–60px (5xl/6xl) | `textTheme.displaySmall` |
| Description max-width | 576px | `ConstrainedBox(maxWidth: 576)` |
| Primary button padding | px-40 py-16 | `EdgeInsets.symmetric(horizontal: 40, vertical: 16)` |
| Primary button radius | lg (14px) | `BorderRadius.circular(14)` |
| Trust footer tracking | wide (0.2em) | `letterSpacing: 2.8` (14px × 0.2) |
| Trust footer size | xs (~10px) | `textTheme.labelSmall` |

### 2.4 Spacing — Gate Overlay (center column)

| Between | Gap | Token |
|---------|-----|-------|
| Lock icon → Badge | 20px | `AppSpacing.xl` (24) — close, or custom 20px |
| Badge → Title | 16px | `AppSpacing.lg` |
| Title → Description | 12px | `AppSpacing.md` |
| Description → Buttons | 32px | `AppSpacing.2xl` |
| Buttons → Trust footer | 20px | Custom 20px |

## 3. Token Extraction

### 3.1 M3 Palette — This Screen

This screen uses a **distinct palette** from other premium screens. The `primary` is `#ffb2bc` (light rose), `secondary-container` doubles as the deep red for CTA. Note the unique sky-blue tertiary — likely Stitch's auto-generated M3 palette complement, used for visual variety.

| M3 Role | Hex | Flutter Mapping |
|---------|-----|-----------------|
| `surface` | `#131313` | `colorScheme.surface` |
| `surface-container-low` | `#1c1b1b` | `colorScheme.surfaceContainerLow` |
| `surface-container` | `#201f1f` | `colorScheme.surfaceContainer` |
| `surface-container-high` | `#2a2a2a` | `colorScheme.surfaceContainerHigh` |
| `surface-container-highest` | `#353534` | `colorScheme.surfaceContainerHighest` |
| `on-surface` | `#e5e2e1` | `colorScheme.onSurface` |
| `on-surface-variant` | `#e1bebd` | `colorScheme.onSurfaceVariant` |
| `primary` | `#ffb2bc` | `colorScheme.primary` |
| `primary-container` | `#782839` | `colorScheme.primaryContainer` |
| `secondary-container` | `#910621` | `colorScheme.secondaryContainer` |
| `outline` | `#a88989` | `colorScheme.outline` |
| `outline-variant` | `#594140` | `colorScheme.outlineVariant` |
| `inverse-primary` | `#994252` | `colorScheme.inversePrimary` |
| `tertiary` | `#97ceeb` | `colorScheme.tertiary` (sky blue — unique) |
| `tertiary-container` | `#004a62` | `colorScheme.tertiaryContainer` |

**In Flutter code** — reference via `Theme.of(context).colorScheme.*`. Do NOT hardcode these hex values; they flow from the theme.

### 3.2 Derived Colors (opacity composites)

| Usage | Composition | Code |
|-------|-------------|------|
| Lock glow halo fill | `primary` @ 20% | `cs.primary.withValues(alpha: 0.20)` |
| Lock container border | `primary` @ 20% | `cs.primary.withValues(alpha: 0.20)` |
| Badge background | `primary` @ 10% | `cs.primary.withValues(alpha: 0.10)` |
| Badge border | `primary` @ 30% | `cs.primary.withValues(alpha: 0.30)` |
| Lock icon color | `primary` | `cs.primary` |
| Trust footer text | `on-surface` @ 40% | `cs.onSurface.withValues(alpha: 0.40)` |
| Primary button shadow | `primary` @ 20% | `cs.primary.withValues(alpha: 0.20)` |

### 3.3 Premium Gradient (CTA Button)

```
linear-gradient(135deg, #910621 0%, #FFB2BC 100%)
```

**Note**: This gradient runs from `secondary-container` (#910621) to `primary` (#ffb2bc). This is specific to this screen — other premium screens may use a different stop ordering. In Flutter, implement as `LinearGradient`:

```dart
const premiumGradient = LinearGradient(
  begin: Alignment.topLeft,    // approximates 135deg
  end: Alignment.bottomRight,
  colors: [Color(0xFF910621), Color(0xFFFFB2BC)],
);
```

### 3.4 Typography

| Element | Size | Weight | Tracking | Color |
|---------|------|--------|----------|-------|
| Badge label | ~10.4px (0.65rem) | bold (700) | 0.2em (3.2px) / uppercase | `primary` |
| Title "Unlock the Full Vault." | 48–60px | bold (700) | tight (-0.02em) | `on-surface` |
| Description | 18px | regular (400) | 0 | `on-surface-variant` |
| Primary button label | 18px | bold (700) | 0 | `on-primary` (white) |
| Secondary button label | 14–16px | medium (500) | 0 | `on-surface-variant` |
| Trust footer | ~10px | medium (500) | 0.2em / uppercase | `on-surface` @ 40% |

**Flutter text style mapping**:

| Element | `textTheme` entry |
|---------|-------------------|
| Badge | `labelSmall` + custom tracking + uppercase |
| Title | `displaySmall` (57px M3) → override to 48–52px |
| Description | `bodyLarge` (16px) → override to 18px |
| Button label | `titleMedium` + bold override |
| Trust footer | `labelSmall` + tracking |

### 3.5 Effects

| Effect | Spec | Flutter |
|--------|------|---------|
| Content blur | `blur(8px)` | `ImageFilter.blur(sigmaX: 8, sigmaY: 8)` |
| Glass frost backdrop blur | `blur(12px)` | `BackdropFilter` + `ImageFilter.blur(sigmaX: 12, sigmaY: 12)` |
| Glass frost gradient mask | `mask-image: linear-gradient(to bottom, transparent, black 15%)` | `ShaderMask` with `LinearGradient(begin: Alignment.topCenter, end: Alignment(0, -0.7), colors: [Colors.transparent, Colors.black])` |
| Glass frost opacity | 40% | `Opacity(opacity: 0.4)` wrapping `BackdropFilter` |
| Lock glow halo | `bg-primary/20 blur-2xl scale-150` | `Transform.scale(1.5)` + `Container` with `BoxDecoration(color: cs.primary.withValues(alpha:0.2), borderRadius: BorderRadius.circular(999))` + `imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20)` |
| Lock container | `surfaceContainerHighest` fill + `primary/20` border | `BoxDecoration(color: cs.surfaceContainerHighest, shape: BoxShape.circle, border: Border.all(color: cs.primary.withValues(alpha: 0.2), width: 1.5))` |
| Primary button hover | `scale-105` | `MouseRegion` + `AnimatedScale` (105%) |
| Primary button shadow | `shadow-2xl shadow-primary/20` | `BoxShadow(color: cs.primary.withValues(alpha: 0.2), blurRadius: 40, spreadRadius: 4)` |

## 4. Gap Analysis — Design vs Current Code

### 4.1 MAJOR Changes

| # | Current | Design | Impact |
|---|---------|--------|--------|
| 1 | `ImageFilter.blur(sigmaX: 6, sigmaY: 6)` on full child | Blur sigma **8**, applied only to gated portion | Blur intensity change |
| 2 | `Opacity(0.4)` directly on child | Content visible above gate; glass frost (blur-12 + gradient mask + opacity-40) at boundary | Add `BackdropFilter` glass layer |
| 3 | No gradient mask | `mask-image: linear-gradient(transparent → black 15%)` at top of gated zone | Add `ShaderMask` |
| 4 | Basic lock circle (surfaceContainerHighest, no border) | Lock container: surfaceContainerHighest + primary/20 border + **glow halo** behind (scale-150, blur-2xl, primary/20) | Glow layer behind icon |
| 5 | Lock icon: `onSurface @ 70%`, 32px | Lock icon: **primary** color, **40px** | Color + size change |
| 6 | Title: `featureLabel` (small, titleSmall) | "Unlock the Full Vault." (displaySmall, bold, on-surface) — context-specific override | Major typography upgrade |
| 7 | "Upgrade to unlock" (bodySmall, onSurface@60%) | Full **description** paragraph (bodyLarge 18px, on-surface-variant, max-w 576px) | Add feature description |
| 8 | Single `FilledButton` (standard theme) | **Premium gradient** filled button (custom LinearGradient background) | Custom button style |
| 9 | No secondary action | "View Feature Comparison" text button + `arrow_forward` icon | Add secondary button |
| 10 | No badge | "SSVID PREMIUM FEATURE" badge (rounded pill, primary/10 bg, primary/30 border) | Add badge widget |
| 11 | No trust footer | "SECURE CHECKOUT • NO ADS • UNLIMITED SPEED" | Add footer text |
| 12 | Full-area blur (entire child) | Split: **top visible** (above PremiumGate), bottom gated | Architecture unchanged — gate wraps only premium sections |

### 4.2 KEEP (unchanged)

| # | Element | Reason |
|---|---------|--------|
| 1 | `PremiumGate(feature, child, featureLabel)` API | Architecture contract — callers unchanged |
| 2 | `premiumFeatureProvider(feature)` watch | State management unchanged |
| 3 | `UpgradePromptDialog.show(context, feature: feature)` callback | Dialog flow unchanged |
| 4 | `if (isAvailable) return child` fast path | Premium users see no overhead |
| 5 | `IgnorePointer` on blurred content | Still needed — gated content must not be interactive |

### 4.3 Architecture Decision: Split Layout

**Design shows**: Visible library above / gated analytics+collections below.

**Reality**: `PremiumGate` wraps specific widget subtrees, not the whole screen. The "visible top" is the parent screen rendering content above the gated widget. The glass wall effect belongs inside `PremiumGate` only.

**Consequence**: The gradient mask at the top of the gated zone (transparent → opaque at 15%) creates the visual boundary between "I can see my library" and "this is where the wall starts." This must be preserved regardless of what content renders above.

**Recommended approach**: `PremiumGate` stays a wrapper widget. The gradient mask on the glass frost layer naturally creates the "wall" appearance at whatever vertical position the gate begins. No split-layout special casing needed.

## 5. Widget Spec — Flutter Implementation

### 5.1 Widget Tree (target)

```dart
// PremiumGate — non-premium branch
Stack(
  children: [
    // Layer 0: Blurred premium content (teaser)
    IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: child,  // rendered at full opacity — frost layer handles dimming
      ),
    ),

    // Layer 1: Glass frost (gradient mask + backdrop blur + opacity)
    Positioned.fill(
      child: _GlassFrostLayer(),
    ),

    // Layer 2: Gate overlay (centered prompt)
    Positioned.fill(
      child: _GlassWallOverlay(
        feature: feature,
        featureLabel: featureLabel,
        onUpgrade: () => UpgradePromptDialog.show(context, feature: feature),
        onCompare: () => _openFeatureComparison(context),
      ),
    ),
  ],
)
```

### 5.2 Component: `_GlassFrostLayer`

The gradient mask creates the fade-in from visible content above. `BackdropFilter` blurs whatever is rendered beneath it (the blurred content layer). `Opacity` dims the whole frosted area.

```dart
class _GlassFrostLayer extends StatelessWidget {
  const _GlassFrostLayer();

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.40,
      child: ShaderMask(
        // Gradient mask: transparent at top → opaque at 15% down
        // Mirrors CSS: mask-image: linear-gradient(to bottom, transparent, black 15%)
        shaderCallback: (Rect bounds) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment(0.0, -0.70),  // 15% from top ≈ Alignment -0.70 on y-axis
            colors: [Colors.transparent, Colors.black],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }
}
```

**Note**: `ShaderMask` with `BlendMode.dstIn` clips the alpha of the child using the gradient. The top (transparent) shows the blurred content beneath as-is; the bottom (black = fully opaque mask) shows the full frosted effect. This is the CSS `mask-image` equivalent.

### 5.3 Component: `_GlassWallOverlay`

```dart
class _GlassWallOverlay extends StatelessWidget {
  final PremiumFeature feature;
  final String? featureLabel;
  final VoidCallback onUpgrade;
  final VoidCallback onCompare;

  const _GlassWallOverlay({
    required this.feature,
    this.featureLabel,
    required this.onUpgrade,
    required this.onCompare,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LockIcon(),
            const SizedBox(height: 20),
            _PremiumBadge(),
            const SizedBox(height: 16),
            _GateTitle(),
            const SizedBox(height: 12),
            _GateDescription(feature: feature),
            const SizedBox(height: 32),
            _GateButtons(onUpgrade: onUpgrade, onCompare: onCompare),
            const SizedBox(height: 20),
            _TrustFooter(),
          ],
        ),
      ),
    );
  }
}
```

### 5.4 Component: `_LockIcon`

```dart
// Glowing lock — halo behind, container in front
Widget _LockIcon() {
  final cs = Theme.of(context).colorScheme;

  return SizedBox(
    width: 96,
    height: 96,
    child: Stack(
      alignment: Alignment.center,
      children: [
        // Glow halo: scale-150, blur-2xl, primary/20
        Transform.scale(
          scale: 1.5,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary.withValues(alpha: 0.20),
            ),
            foregroundDecoration: BoxDecoration(
              shape: BoxShape.circle,
              // Apply blur via ImageFiltered wrapper instead
            ),
          ),
        ),
        // Blurred glow using ImageFiltered
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Transform.scale(
            scale: 1.5,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primary.withValues(alpha: 0.20),
              ),
            ),
          ),
        ),
        // Icon container
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            shape: BoxShape.circle,
            border: Border.all(
              color: cs.primary.withValues(alpha: 0.20),
              width: 1.5,
            ),
          ),
          child: Icon(
            Icons.lock_rounded,
            fill: 1.0,      // FILL 1 — filled variant
            size: 40,
            color: cs.primary,
          ),
        ),
      ],
    ),
  );
}
```

### 5.5 Component: `_PremiumBadge`

```dart
Widget _PremiumBadge() {
  final cs = Theme.of(context).colorScheme;

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    decoration: BoxDecoration(
      color: cs.primary.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: cs.primary.withValues(alpha: 0.30),
        width: 1,
      ),
    ),
    child: Text(
      'SSVID PREMIUM FEATURE',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: cs.primary,
        fontWeight: FontWeight.w700,
        letterSpacing: 2.8,  // 0.2em at ~14px base
        fontSize: 10.4,
      ),
    ),
  );
}
```

### 5.6 Component: `_GateTitle`

```dart
Widget _GateTitle() {
  return Text(
    'Unlock the Full Vault.',
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.displaySmall?.copyWith(
      fontSize: 48,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.96,  // tight, -0.02em
      color: Theme.of(context).colorScheme.onSurface,
    ),
  );
}
```

### 5.7 Component: `_GateDescription`

The description text is feature-specific. Define per-feature copy in `PremiumFeature` or a companion map. Fallback to a generic message.

```dart
Widget _GateDescription({required PremiumFeature feature}) {
  final cs = Theme.of(context).colorScheme;
  final description = _featureDescriptions[feature] ??
      'This feature is available exclusively for SSvid Premium members. '
      'Upgrade to unlock advanced tools and unlimited access.';

  return ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 576),
    child: Text(
      description,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        fontSize: 18,
        color: cs.onSurfaceVariant,
        height: 1.6,  // leading-relaxed
      ),
    ),
  );
}

// Feature description copy (example entries — expand per PremiumFeature values)
const _featureDescriptions = <PremiumFeature, String>{
  PremiumFeature.advancedAnalytics:
      'Deep-dive into your download history with beautiful charts, '
      'smart collections, and insights across every platform you use.',
  PremiumFeature.smartCollections:
      'Organize your vault automatically — SSvid groups your downloads '
      'by platform, topic, and mood so you can find anything instantly.',
  // ... add remaining features
};
```

### 5.8 Component: `_GateButtons`

```dart
Widget _GateButtons({
  required VoidCallback onUpgrade,
  required VoidCallback onCompare,
}) {
  final cs = Theme.of(context).colorScheme;

  return Wrap(
    alignment: WrapAlignment.center,
    spacing: 24,
    runSpacing: 12,
    children: [
      // Primary — premium gradient CTA
      _PremiumGradientButton(
        label: 'Upgrade to SSvid Premium',
        onPressed: onUpgrade,
      ),

      // Secondary — text button + arrow
      TextButton.icon(
        onPressed: onCompare,
        icon: const SizedBox.shrink(),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'View Feature Comparison',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward, size: 16, color: cs.onSurfaceVariant),
          ],
        ),
        style: TextButton.styleFrom(
          foregroundColor: cs.onSurface,
        ),
      ),
    ],
  );
}
```

### 5.9 Component: `_PremiumGradientButton`

```dart
class _PremiumGradientButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;

  const _PremiumGradientButton({
    required this.label,
    required this.onPressed,
  });

  @override
  State<_PremiumGradientButton> createState() => _PremiumGradientButtonState();
}

class _PremiumGradientButtonState extends State<_PremiumGradientButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _hovered ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,   // 135deg
                end: Alignment.bottomRight,
                colors: [Color(0xFF910621), Color(0xFFFFB2BC)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.20),
                  blurRadius: 40,
                  spreadRadius: 4,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Text(
              widget.label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,  // on-primary
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

### 5.10 Component: `_TrustFooter`

```dart
Widget _TrustFooter() {
  return Text(
    'SECURE CHECKOUT \u2022 NO ADS \u2022 UNLIMITED SPEED',
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.40),
      letterSpacing: 2.0,
      fontWeight: FontWeight.w500,
      fontSize: 10,
    ),
  );
}
```

## 6. State Flow

### 6.1 States

The `PremiumGate` widget has two states — identical to current:

```
isAvailable = true  → return child (fast path, no overlay)
isAvailable = false → Glass Wall overlay (3-layer stack)
```

No loading state, no error state. `premiumFeatureProvider` is synchronous (Riverpod, local license check).

### 6.2 Secondary Action: Feature Comparison

The "View Feature Comparison" button needs a destination. Options (to discuss with Chairman):

| Option | Implementation | Notes |
|--------|---------------|-------|
| A | `UpgradePromptDialog.show(...)` with comparison tab | Reuse existing dialog |
| B | Navigate to `/premium` settings tab | Uses existing routes |
| C | Open `ssvid.app/premium` in browser | External |

**Default for implementation**: Use option A (reuse `UpgradePromptDialog`) until Chairman decides. Pass `feature` param for context.

### 6.3 Interaction

| Interaction | Response |
|------------|---------|
| Click anywhere on blurred content | Blocked — `IgnorePointer` |
| Click "Upgrade to SSvid Premium" | `UpgradePromptDialog.show(context, feature: feature)` |
| Click "View Feature Comparison" | TBD — see 6.2 |
| Hover primary button | Scale 105%, `AnimatedScale` 150ms |
| Hover secondary button | `onSurface` color (from `onSurfaceVariant`) |
| Keyboard Tab | Focus ring on both buttons — standard Flutter focus |

## 7. Token Changes Required

### 7.1 No new tokens needed in `app_colors.dart`

The glass wall uses `colorScheme.*` exclusively (M3 roles from theme). No new `AppColors` constants needed.

If `FILL 1` (filled icon variant) is used via `Icon(fill: 1.0)`, confirm Flutter version supports `fill` parameter — it requires Flutter 3.12+ with M3 icons. SSvid uses Flutter 3.29.3 — confirmed supported.

### 7.2 No changes to `app_typography.dart`

All styles override from `textTheme.*` inline. No new named styles warranted — the gate is a one-off overlay.

### 7.3 No changes to `app_spacing.dart`

Spacings are custom inline `SizedBox` values derived from Stitch spec. None map to new reusable tokens.

### 7.4 Feature Description Copy

Add to `app_localizations.dart` (or a companion `premium_copy.dart`):

```dart
// Premium gate descriptions — per PremiumFeature
static const String premiumGateAnalyticsDesc =
    'Deep-dive into your download history with beautiful charts, '
    'smart collections, and insights across every platform you use.';

static const String premiumGateCollectionsDesc =
    'Organize your vault automatically — SSvid groups your downloads '
    'by platform, topic, and mood so you can find anything instantly.';

static const String premiumGateGenericDesc =
    'This feature is available exclusively for SSvid Premium members. '
    'Upgrade to unlock advanced tools and unlimited access.';

// Trust footer
static const String premiumGateTrustFooter =
    'SECURE CHECKOUT \u2022 NO ADS \u2022 UNLIMITED SPEED';

// Badge
static const String premiumGateBadgeLabel = 'SSVID PREMIUM FEATURE';

// Title
static const String premiumGateTitle = 'Unlock the Full Vault.';

// Secondary button
static const String premiumGateCompareAction = 'View Feature Comparison';
```

## 8. Platform Considerations

### 8.1 macOS

- `BackdropFilter` works correctly in Flutter macOS — hardware-accelerated.
- `MouseRegion` hover on the gradient button is supported.
- `Icon(fill: 1.0)` — requires M3 icon font. Verify icons font is bundled. If not: use `Icons.lock` (filled by default) as fallback.
- `SingleChildScrollView` ensures gate overlay doesn't clip on small window heights.

### 8.2 Windows

- `BackdropFilter` works on Windows Flutter — DirectX backend.
- `AnimatedScale` on the CTA button works. No platform-specific issues.
- `Icon(fill: 1.0)` — same M3 icon font requirement as macOS.

### 8.3 Linux

- `BackdropFilter` works on Linux Flutter (GTK/Vulkan backend).
- All animations and effects are Flutter-native — no platform-specific rendering.

### 8.4 Performance Note

`BackdropFilter` repaints the entire subtree on every frame. The gate is shown as a full overlay — no animation in the glass frost layer itself, so this is not a concern (single paint pass per state change). If animated entrance is added (see Section 9), use `AnimatedOpacity` wrapping the glass layer, not `AnimatedContainer`.

### 8.5 Accessibility

- `IgnorePointer` on blurred content: screen readers also skip the underlying content. This is intentional — the locked content should not be announced.
- CTA button: `Semantics` label should read "Upgrade to SSvid Premium — opens upgrade dialog".
- Secondary button: "View Feature Comparison".
- Lock icon: exclude from semantics (`excludeFromSemantics: true` on the `Icon`) — decorative.
- Badge: exclude from semantics — the title conveys the same meaning.

## 9. Animation Spec

| Animation | Duration | Curve | Notes |
|-----------|----------|-------|-------|
| Glass wall entrance (full overlay) | 250ms | `Curves.easeOut` | `AnimatedOpacity` 0→1 on mount |
| Lock icon scale entrance | 300ms, 50ms delay | `Curves.easeOutBack` | Subtle "pop" — feels premium |
| Badge + title fade-in | 200ms, 100ms delay | `Curves.easeOut` | Staggered after lock |
| Primary button hover scale | 150ms | `Curves.easeOut` | `AnimatedScale` 1.0→1.05 |
| Frost layer | static | — | No animation — static overlay |

The entrance animation plays once when `isAvailable` switches to false (or on first render). It is not looped or repeated.

## 10. Verification Checklist

- [ ] Fast path: premium users see `child` directly, no glass overhead
- [ ] Blurred content renders at sigma-8 (not sigma-6 current)
- [ ] Glass frost layer: `BackdropFilter` blur-12 visible
- [ ] Gradient mask: top of gated zone fades in (transparent → frosted), not hard edge
- [ ] Glass frost opacity 40% — content dimmed but recognizable shapes visible
- [ ] Lock icon: **filled** variant, primary color (#ffb2bc in dark), size 40
- [ ] Glow halo behind lock icon: visible soft radial glow in primary/20
- [ ] Badge renders: pill shape, correct border, correct text (uppercase, spaced)
- [ ] Title: "Unlock the Full Vault." — large, bold, centered
- [ ] Description: readable, on-surface-variant, max-width 576px, multi-line wraps correctly
- [ ] Primary button: gradient renders (dark-red → rose), NOT solid theme color
- [ ] Primary button: hover scale animates (scale 105%, 150ms)
- [ ] Primary button: shadow visible (primary/20, blur-40)
- [ ] Secondary button: text + arrow_forward icon, on-surface-variant
- [ ] Trust footer: uppercase, dot-separated, on-surface @ 40%
- [ ] `IgnorePointer` confirmed: clicking blurred content area does nothing
- [ ] CTA triggers `UpgradePromptDialog`
- [ ] Gate overlay `SingleChildScrollView`: does not clip on window height < 700px
- [ ] Entrance animation plays once on mount (250ms opacity fade)
- [ ] `flutter analyze` passes with 0 issues
- [ ] Works in both dark and light themes (colorScheme tokens adapt)
- [ ] `Icon(fill: 1.0)` renders filled lock — if font issue, fallback is `Icons.lock_rounded`
