# Premium "Welcome Home" Celebration Screen — Design Spec

> Source: Stitch project `9746799973876268727`
> Screen: `631d2228f9ce439cb1dc3ceefe485da5`
> Status: DRAFT — Pending Chairman review
> Current code: `lib/features/premium/presentation/screens/premium_upgrade_screen.dart` — `_showActivationSuccessDialog()` (line 1490)

## 1. Design Intent

**Purpose**: Full-page cinematic celebration shown immediately after successful payment or manual license activation. Replaces the current `AlertDialog`. Also navigable from the Members Lounge (account/profile section) so premium users can revisit it.

**Mood**: "You've arrived." Atmospheric, unhurried, auteur. Not a utility confirmation — a ceremony. The user should feel the upgrade was worth it the moment this screen appears.

**Key principle**: Every element earns its place. Glass, glow, and shimmer reinforce exclusivity without clutter. The license key is the hero artifact — treat it as such.

## 2. Visual Structure

### 2.1 Layout

```
┌──────────────────────────────────────────────────────────────────┐
│  [●] [●] [●]         SSvid Premium                  [✕]         │  ← macOS title bar (40px)
├──────────────────────────────────────────────────────────────────┤
│  [Background: dark surface + radial glow + shimmer dots + orbs]  │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                                                            │  │  ← Scrollable content area
│  │              Welcome to SSvid Premium                      │  │  ← shimmer gradient heading
│  │           The Auteur's Experience Begins Now               │  │  ← subtitle
│  │                                                            │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │  Your Personal Activation Key                        │  │  │  ← glass card
│  │  │  ┌────────────────────────────────────────────────┐  │  │  │
│  │  │  │  XXXX-XXXX-XXXX-XXXX-XXXX          [Copy]      │  │  │  │
│  │  │  └────────────────────────────────────────────────┘  │  │  │
│  │  │  Save this key — it cannot be recovered automatically │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  │                                                            │  │
│  │  ┌───────────────────────┬──────────────────────────────┐  │  │
│  │  │  Plan Details         │  Billing Info                 │  │  │  ← 2-col subscription summary
│  │  │  Annual · $59.99/yr   │  Next: [date] · Visa ····4242 │  │  │
│  │  └───────────────────────┴──────────────────────────────┘  │  │
│  │                                                            │  │
│  │  NEW SUPERPOWERS UNLOCKED                                  │  │
│  │  ┌──────────┬──────────┬──────────┬──────────┐            │  │
│  │  │ AI Search│  Batch   │  Cloud   │  Smart   │            │  │  ← 4-col bento grid
│  │  │          │ Downloads│  Backup  │ Collections│           │  │
│  │  └──────────┴──────────┴──────────┴──────────┘            │  │
│  │                                                            │  │
│  │         [  Start Exploring SSvid Premium  ]                │  │  ← primary gradient CTA
│  │                    Manage Subscription                     │  │  ← secondary text button
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  [Bottom gradient overlay: black/80 → transparent, fixed h-1/3] │
└──────────────────────────────────────────────────────────────────┘
```

### 2.2 Dimensions

| Element | Value | Notes |
|---------|-------|-------|
| Screen layout | Full-page (replaces current screen / modal) | `Scaffold` over full window |
| Content max-width | 720px | Centered, constrained |
| Content side padding | 48px | `EdgeInsets.symmetric(horizontal: 48)` |
| Glass card (license) | Full width within content area | `border-radius: 16px` |
| License key display | Full width, `px: 24, py: 16` | `bg-black/40` |
| Subscription summary | Full width, 2-column | `Row` with `Expanded` each side, 1px divider |
| Bento grid cell | `flex: 1`, equal columns | `IntrinsicHeight` Row of 4 |
| Bento icon circle | 48×48px | `BoxShape.circle` |
| Primary CTA min-width | 320px | `constraints: BoxConstraints(minWidth: 320)` |
| Bottom gradient height | 1/3 of screen height | `Positioned`, `h: screenHeight / 3` |
| Bottom-right orb | 384px diameter | `BoxShape.circle`, `blur: 120px` |
| Center orb | Full screen width × 600px tall | Centered vertically above CTA |

### 2.3 Spacing

| Between | Gap | Notes |
|---------|-----|-------|
| Header group → License card | 48px | `SizedBox(height: 48)` |
| License card → Subscription summary | 24px | `SizedBox(height: 24)` |
| Subscription summary → Bento label | 32px | `SizedBox(height: 32)` |
| Bento label → Bento grid | 16px | `SizedBox(height: 16)` |
| Bento grid → CTA button | 48px | `SizedBox(height: 48)` |
| CTA primary → secondary text link | 16px | `SizedBox(height: 16)` |
| Title → subtitle | 12px | `SizedBox(height: 12)` |
| Top padding (scrollable content) | 64px | `padding: EdgeInsets.only(top: 64)` |
| Bottom padding (scrollable content) | 120px | Clears fixed bottom gradient |

## 3. Token Extraction

### 3.1 Background Effects

All background layers are stacked in a `Stack`, behind the scrollable content column.

| Layer | Implementation | Notes |
|-------|---------------|-------|
| Base surface | `colorScheme.surface` = `#131313` | Full `Scaffold` background |
| Premium glow (center) | `RadialGradient(center: Alignment.center, colors: [Color(0xFF8D0022).withOpacity(0.15), Colors.transparent], stops: [0.0, 0.7])` | `Positioned.fill` |
| Shimmer dots | Custom `CustomPainter` — 40px grid, `radial-gradient` dots at 2px, `rgba(255,179,180,0.05)`, opacity 30% | `Positioned.fill` |
| Bottom gradient | `LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withOpacity(0.8), Colors.transparent])` | Fixed `Positioned(bottom: 0)`, height = `screenH / 3` |
| Bottom-right orb | 384px circle, `Color(0xFF8D021F).withOpacity(0.05)`, `ImageFilter.blur(sigmaX: 120, sigmaY: 120)` via `BackdropFilter` | `Positioned(bottom: -192, right: -192)` |
| Center orb | Full-width × 600px, `primaryContainer.withOpacity(0.05)`, `blur(150)` | `Positioned`, vertically centered |

> Flutter note: True CSS `radial-gradient` dot patterns require `CustomPainter`. Use `canvas.drawCircle` in a grid loop (step: 40px, radius: 1px, `Paint()..color = Color(0xFFFFB3B4).withOpacity(0.05)`). Apply `Opacity(opacity: 0.3)` to the painter widget.

### 3.2 Colors — Dark Mode

| Element | Stitch Value | Flutter Mapping | Notes |
|---------|-------------|-----------------|-------|
| Page background | `#131313` | `colorScheme.surface` | Nocturne Cinematic base |
| Premium glow center | `rgba(141,0,34,0.15)` | `Color(0xFF8D0022).withOpacity(0.15)` | Radial, fades to transparent |
| Shimmer dots | `rgba(255,179,180,0.05) @ 30%` | `Color(0xFFFFB3B4).withOpacity(0.015)` | Net: 0.05 × 0.3 |
| Bottom-right orb | `bg-primary/5` | `colorScheme.primary.withOpacity(0.05)` | `Color(0xFFFFB3B4) @ 5%` |
| Center orb | `bg-primary-container/5` | `Color(0xFF8D0022).withOpacity(0.05)` | Maps to design `#8d0022` |
| Glass card bg | `rgba(26,26,26,0.6)` | `Color(0xFF1A1A1A).withOpacity(0.6)` | `backdropFilter: blur(20px)` |
| Glass card border | `rgba(255,255,255,0.05)` | `Colors.white.withOpacity(0.05)` | 1px `Border.all` |
| License key field bg | `rgba(0,0,0,0.4)` | `Colors.black.withOpacity(0.4)` | `Container` inside glass card |
| License key text | `#ffb3b4` | `colorScheme.primary` (dark) | = `Color(0xFFFFB3B4)` ✅ |
| License key mono font | JetBrains Mono | `GoogleFonts.jetBrainsMono()` | **New — see §7** |
| Copy button gradient start | `#8d0022` | `AppColors.brand` | `Color(0xFF8D021F)` ✅ close |
| Copy button gradient end | `#910621` | `AppColors.accentMuted` adjacent | `Color(0xFF910621)` ≈ `accentMuted` |
| Card label (uppercase) | `on-surface-variant` | `colorScheme.onSurfaceVariant` | `#e1bebd` in Nocturne |
| Save notice text | `on-surface-variant @ 70%` | `colorScheme.onSurfaceVariant.withOpacity(0.7)` | Italic |
| Subscription grid divider | `rgba(outline-variant, 0.2)` | `colorScheme.outlineVariant.withOpacity(0.2)` | 1px wide |
| Plan/billing label | `on-surface-variant` | `colorScheme.onSurfaceVariant` | |
| Plan/billing value | `on-surface` | `colorScheme.onSurface` | |
| Bento cell bg | `surface-container-low` | `Color(0xFF1C1B1B)` | Nocturne design token |
| Bento icon circle | `primary-container/20` | `Color(0xFF8D0022).withOpacity(0.2)` | |
| Bento icon | `colorScheme.primary` | `Color(0xFFFFB3B4)` | |
| Bento title | `on-surface` | `colorScheme.onSurface` | |
| Heading shimmer (start/end) | `#e5e2e1` | `Color(0xFFE5E2E1)` | |
| Heading shimmer (mid) | `#ffb3b4` | `Color(0xFFFFB3B4)` | |
| Subtitle text | `on-surface-variant` | `colorScheme.onSurfaceVariant` | |
| CTA primary gradient | `#8D021F → #910621 → #FFB3B4` | Custom `LinearGradient` | See §5.5 |
| CTA shadow | `rgba(141,2,31,0.4)` | `Color(0xFF8D021F).withOpacity(0.4)` | Blur 25px |
| Secondary text button | `colorScheme.primary` | `Color(0xFFFFB3B4)` | |

### 3.3 Colors — Light Mode

Light mode is secondary for this screen (premium users more likely in dark), but must be consistent.

| Element | Flutter Mapping |
|---------|----------------|
| Page background | `colorScheme.surface` (light) = `Color(0xFFFAF9F8)` |
| Premium glow | Same radial, reduced to `rgba(141,0,31,0.08)` |
| Shimmer dots | Same painter, opacity 15% |
| Glass card bg | `Colors.white.withOpacity(0.7)`, blur 20px |
| Glass card border | `Color(0xFF8D021F).withOpacity(0.08)` |
| License key field bg | `Color(0xFF1A1A1A)` (always dark for readability) |
| License key text | `Color(0xFFFFB3B4)` (always brand rose on dark field) |
| Bento cell bg | `colorScheme.surfaceContainerLow` (light scheme) |
| Heading shimmer (dark variant) | `#1a1a1a` → `#8d021f` → `#1a1a1a` |
| CTA gradient | Same brand gradient — constant across modes |

### 3.4 Typography

| Element | Size | Weight | Tracking | Flutter Style |
|---------|------|--------|----------|---------------|
| Celebration heading | 48px (5xl) | bold (700) | tight (-0.03em) | `textTheme.displayLarge` (48px/700) ✅ |
| Heading shimmer variant | 56px (7xl) on wider breakpoints | 700 | tight | `textTheme.displayLarge` + media query |
| Subtitle | 16px | light (300) | 0.2em (widest), uppercase | `textTheme.bodyLarge.copyWith(fontWeight: w300, letterSpacing: 3.2, fontSize: 16)` |
| Card label (uppercase) | 11px | semibold (600) | 0.2em | `AppTypography.sectionHeader` ✅ |
| License key | 20px (xl) / 24px (2xl wide) | regular (400) | 0.15em (widest) | `GoogleFonts.jetBrainsMono(fontSize: 20, letterSpacing: 3.0)` |
| Save notice | 12px | regular (400) | normal | `textTheme.bodySmall`, `FontStyle.italic` |
| Plan/billing label | 13px | medium (500) | 0.05em | `textTheme.titleSmall` ✅ |
| Plan/billing value | 15px | semibold (600) | tight | `textTheme.titleMedium.copyWith(fontWeight: w600)` |
| Bento section label | 11px | semibold (600) | 0.2em, uppercase | `AppTypography.sectionHeader` ✅ |
| Bento feature title | 13px | medium (500) | normal | `textTheme.titleSmall` ✅ |
| CTA primary button | 16px | bold (700) | 0.05em | `textTheme.bodyLarge.copyWith(fontWeight: w700, fontSize: 16)` |
| Secondary text button | 13px | medium (500) | normal | `textTheme.labelLarge` ✅ |

### 3.5 Effects Summary

| Effect | Spec | Flutter Implementation |
|--------|------|----------------------|
| Heading shimmer animation | 200% bg-size, left→right sweep | `AnimationController` (2s loop) + `LinearGradient` via `ShaderMask` |
| Glass card blur | `backdrop-filter: blur(20px)` | `BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20))` + `ClipRRect` |
| Bento cell hover scale | `scale-110` on hover | `MouseRegion` + `AnimatedScale(scale: isHovered ? 1.1 : 1.0)` |
| CTA hover glow grow | shadow 25px → 35px, `scale-105` | `MouseRegion` + `AnimatedContainer` + `AnimatedScale` |
| Orb blur | `blur(120px)` / `blur(150px)` | `BackdropFilter` or `ImageFilter.blur` on colored container |
| Bottom gradient | Fixed overlay | `Positioned(bottom: 0)` + `IgnorePointer` |

## 4. Gap Analysis — Design vs Current Code

### 4.1 MAJOR Changes

| # | Current | Design | Impact |
|---|---------|--------|--------|
| 1 | `AlertDialog` (modal, dismissible) | Full-page `Scaffold` screen | Architecture change — new route/screen |
| 2 | Simple `Text` for license key | Glass card + JetBrains Mono + copy button | New widget tree |
| 3 | No subscription info | 2-column plan + billing summary | New data binding from `PremiumLicenseState` |
| 4 | No feature showcase | 4-column bento grid with icons | New section widget |
| 5 | No atmospheric effects | Radial glow + shimmer dots + blur orbs + bottom gradient | New `_BackgroundEffects` layer |
| 6 | `checkmark` success icon (success green) | Shimmer gradient text heading, no checkmark | Visual overhaul |
| 7 | One button: "Got it" (dismisses dialog) | Primary CTA "Start Exploring" + secondary "Manage Subscription" | New actions |
| 8 | Not navigable after first show | Accessible from Members Lounge | Navigation integration |
| 9 | JetBrains Mono not in project | JetBrains Mono for license key | `pubspec.yaml` + `app_typography.dart` change |

### 4.2 KEEP (functional requirements not in design)

| # | Element | Reason |
|---|---------|--------|
| 1 | `ref.read(paymentProvider.notifier).reset()` on dismiss | Clears payment state to avoid re-triggering |
| 2 | License key sourced from `PremiumLicenseState` | Data layer unchanged |
| 3 | Clipboard copy logic (`Clipboard.setData`) | UX requirement for license key copy |
| 4 | Navigation back to `Home` on CTA press | User must be able to leave this screen |
| 5 | "Manage Subscription" → opens `premium_upgrade_screen` or URL | Existing purchase flow reuse |

### 4.3 Entry Points

| Trigger | Entry Method |
|---------|-------------|
| Payment success (`Stripe webhook`) | `paymentProvider` listener in `premium_upgrade_screen.dart` → `Navigator.push(AppTransitions.pageRoute(PremiumWelcomeScreen()))` |
| Manual key activation success | `_showActivationSuccessDialog()` → same push |
| Members Lounge (revisit) | Direct route from account/profile section |

## 5. Widget Spec — Flutter Implementation

### 5.1 Widget Tree (target)

```dart
// lib/features/premium/presentation/screens/premium_welcome_screen.dart

class PremiumWelcomeScreen extends ConsumerWidget {
  const PremiumWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          // Layer 0: Atmospheric background
          _WelcomeBackgroundEffects(isDark: isDark),

          // Layer 1: Scrollable content
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 48).copyWith(
              top: 64,
              bottom: 120,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Section 1: Celebration header
                    const _CelebrationHeader(),

                    const SizedBox(height: 48),

                    // Section 2: License key glass card
                    _LicenseKeyCard(),

                    const SizedBox(height: 24),

                    // Section 3: Subscription summary
                    _SubscriptionSummary(),

                    const SizedBox(height: 32),

                    // Section 4: Unlocked features bento
                    const _UnlockedFeaturesBento(),

                    const SizedBox(height: 48),

                    // Section 5: CTAs
                    _WelcomeCtas(onDone: () {
                      ref.read(paymentProvider.notifier).reset();
                      Navigator.of(context).pop();
                    }),
                  ],
                ),
              ),
            ),
          ),

          // Layer 2: Bottom gradient overlay (fixed, non-interactive)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: _BottomGradientOverlay(),
            ),
          ),
        ],
      ),
    );
  }
}
```

### 5.2 Component: `_WelcomeBackgroundEffects`

```dart
class _WelcomeBackgroundEffects extends StatelessWidget {
  final bool isDark;
  const _WelcomeBackgroundEffects({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Base: premium radial glow
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.7,
                colors: [
                  const Color(0xFF8D0022).withOpacity(isDark ? 0.15 : 0.08),
                  Colors.transparent,
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),

        // Shimmer dots pattern
        Positioned.fill(
          child: Opacity(
            opacity: isDark ? 0.30 : 0.15,
            child: CustomPaint(painter: _ShimmerDotsPainter()),
          ),
        ),

        // Bottom-right orb (blur circle)
        Positioned(
          bottom: -192,
          right: -192,
          child: _BlurOrb(
            diameter: 384,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
            blurSigma: 120,
          ),
        ),

        // Center orb
        Positioned(
          left: 0,
          right: 0,
          top: MediaQuery.of(context).size.height * 0.2,
          child: _BlurOrb(
            diameter: MediaQuery.of(context).size.width,
            height: 600,
            color: const Color(0xFF8D0022).withOpacity(0.05),
            blurSigma: 150,
          ),
        ),
      ],
    );
  }
}

// CustomPainter for dot grid
class _ShimmerDotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFB3B4).withOpacity(0.05)
      ..style = PaintingStyle.fill;
    const step = 40.0;
    for (double x = 2; x < size.width; x += step) {
      for (double y = 2; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Reusable blur orb
class _BlurOrb extends StatelessWidget {
  final double diameter;
  final double? height;
  final Color color;
  final double blurSigma;

  const _BlurOrb({
    required this.diameter,
    this.height,
    required this.color,
    required this.blurSigma,
  });

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          width: diameter,
          height: height ?? diameter,
          decoration: BoxDecoration(
            color: color,
            shape: height == null ? BoxShape.circle : BoxShape.rectangle,
          ),
        ),
      ),
    );
  }
}
```

### 5.3 Component: `_CelebrationHeader`

```dart
// Shimmer gradient animated heading + subtitle
class _CelebrationHeader extends StatefulWidget {
  const _CelebrationHeader();

  @override
  State<_CelebrationHeader> createState() => _CelebrationHeaderState();
}

class _CelebrationHeaderState extends State<_CelebrationHeader>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFFE5E2E1) : const Color(0xFF1A1A1A);
    final accentColor = const Color(0xFFFFB3B4);

    return Column(
      children: [
        // Shimmer heading
        AnimatedBuilder(
          animation: _shimmerController,
          builder: (context, child) {
            return ShaderMask(
              shaderCallback: (bounds) {
                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [baseColor, accentColor, baseColor],
                  stops: const [0.2, 0.5, 0.8],
                  transform: _SlideGradientTransform(_shimmerController.value),
                ).createShader(bounds);
              },
              child: Text(
                'Welcome to SSvid Premium',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.white, // ShaderMask requires opaque color
                      letterSpacing: -0.03 * 48,
                    ),
                textAlign: TextAlign.center,
              ),
            );
          },
        ),

        const SizedBox(height: 12),

        // Subtitle
        Text(
          'THE AUTEUR\'S EXPERIENCE BEGINS NOW',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w300,
                letterSpacing: 3.2,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// Gradient transform for shimmer sweep
class _SlideGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlideGradientTransform(this.slidePercent);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * (slidePercent * 2 - 0.5),
      0,
      0,
    );
  }
}
```

### 5.4 Component: `_LicenseKeyCard`

```dart
class _LicenseKeyCard extends ConsumerStatefulWidget {
  const _LicenseKeyCard();

  @override
  ConsumerState<_LicenseKeyCard> createState() => _LicenseKeyCardState();
}

class _LicenseKeyCardState extends ConsumerState<_LicenseKeyCard> {
  bool _copied = false;

  Future<void> _copyKey(String key) async {
    await Clipboard.setData(ClipboardData(text: key));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final licenseKey = ref.watch(premiumLicenseProvider).valueOrNull?.licenseKey ?? '—';

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A).withOpacity(0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 25,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card label
              Text(
                'YOUR PERSONAL ACTIVATION KEY',
                style: AppTypography.sectionHeader.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 16),

              // Key display + copy button
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        licenseKey,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 20,
                          fontWeight: FontWeight.w400,
                          color: colorScheme.primary, // #FFB3B4
                          letterSpacing: 3.0,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Copy button
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8D0022), Color(0xFF910621)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: TextButton.icon(
                      onPressed: () => _copyKey(licenseKey),
                      icon: Icon(
                        _copied ? Icons.check_rounded : Icons.copy_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      label: Text(
                        _copied ? 'Copied!' : 'Copy',
                        style: const TextStyle(color: Colors.white),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Save notice
              Text(
                'Save this key — it cannot be recovered automatically.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### 5.5 Component: `_SubscriptionSummary`

```dart
class _SubscriptionSummary extends ConsumerWidget {
  const _SubscriptionSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    // Read subscription data from premium license state
    final license = ref.watch(premiumLicenseProvider).valueOrNull;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1B1B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.2),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Left: Plan details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PLAN DETAILS',
                      style: AppTypography.sectionHeader.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      license?.planName ?? 'Annual',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      license?.priceDisplay ?? '\$59.99/year',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),

            // Divider (1px vertical)
            VerticalDivider(
              width: 1,
              color: colorScheme.outlineVariant.withOpacity(0.2),
            ),

            // Right: Billing info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BILLING INFO',
                      style: AppTypography.sectionHeader.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      license?.nextBillingDate != null
                          ? 'Renews ${_formatDate(license!.nextBillingDate!)}'
                          : 'Next billing date pending',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      license?.paymentMethod ?? 'Payment method on file',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
```

### 5.6 Component: `_UnlockedFeaturesBento`

```dart
// Features to showcase post-upgrade
const _premiumFeatures = [
  _FeatureItem(
    icon: Icons.search_rounded,          // search_spark equivalent
    title: 'AI-Powered Search',
  ),
  _FeatureItem(
    icon: Icons.download_done_rounded,
    title: 'Batch Downloads',
  ),
  _FeatureItem(
    icon: Icons.cloud_sync_rounded,      // cloud_sync equivalent
    title: 'Cloud Backup',
  ),
  _FeatureItem(
    icon: Icons.auto_awesome_motion_rounded,
    title: 'Smart Collections',
  ),
];

class _UnlockedFeaturesBento extends StatelessWidget {
  const _UnlockedFeaturesBento();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label
        Text(
          'NEW SUPERPOWERS UNLOCKED',
          style: AppTypography.sectionHeader.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),

        const SizedBox(height: 16),

        // 4-column bento grid
        Row(
          children: _premiumFeatures.map((feature) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: feature == _premiumFeatures.last ? 0 : 12,
                ),
                child: _BentoCell(feature: feature),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _BentoCell extends StatefulWidget {
  final _FeatureItem feature;
  const _BentoCell({required this.feature});

  @override
  State<_BentoCell> createState() => _BentoCellState();
}

class _BentoCellState extends State<_BentoCell> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.10 : 1.0,
        duration: AppTransitions.fast,
        curve: AppTransitions.curveEnter,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1B1B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(
                _isHovered ? 0.3 : 0.15,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon in circle
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF8D0022).withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.feature.icon,
                  size: 24,
                  color: colorScheme.primary,
                ),
              ),

              const SizedBox(height: 12),

              // Feature title
              Text(
                widget.feature.title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureItem {
  final IconData icon;
  final String title;
  const _FeatureItem({required this.icon, required this.title});
}
```

### 5.7 Component: `_WelcomeCtas`

```dart
class _WelcomeCtas extends StatefulWidget {
  final VoidCallback onDone;
  const _WelcomeCtas({required this.onDone});

  @override
  State<_WelcomeCtas> createState() => _WelcomeCtasState();
}

class _WelcomeCtasState extends State<_WelcomeCtas> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Primary CTA — gradient button
        MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedScale(
            scale: _isHovered ? 1.05 : 1.0,
            duration: AppTransitions.fast,
            curve: AppTransitions.curveEnter,
            child: AnimatedContainer(
              duration: AppTransitions.fast,
              constraints: const BoxConstraints(minWidth: 320),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF8D021F),
                    Color(0xFF910621),
                    Color(0xFFFFB3B4),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8D021F).withOpacity(0.4),
                    blurRadius: _isHovered ? 35 : 25,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextButton(
                onPressed: widget.onDone,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Start Exploring SSvid Premium',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Secondary: Manage Subscription
        TextButton(
          onPressed: () {
            // Navigate to subscription management (Stripe portal or premium screen)
            // Implementation: launch_url with Stripe billing portal URL
          },
          child: Text(
            'Manage Subscription',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                ),
          ),
        ),
      ],
    );
  }
}
```

### 5.8 Component: `_BottomGradientOverlay`

```dart
class _BottomGradientOverlay extends StatelessWidget {
  const _BottomGradientOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height / 3,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Color(0xCC000000), // black/80
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}
```

## 6. State & Navigation Flow

### 6.1 Entry Navigation

```
Payment success (Stripe)       ──┐
Manual key activation success  ──┼──► Navigator.push(AppTransitions.pageRoute(PremiumWelcomeScreen()))
Members Lounge "View Benefits" ──┘
```

Replace `_showActivationSuccessDialog()` calls with:
```dart
Navigator.of(context).push(
  AppTransitions.pageRoute(const PremiumWelcomeScreen()),
);
```

### 6.2 Exit Navigation

| Action | Behavior |
|--------|----------|
| "Start Exploring" CTA | `ref.read(paymentProvider.notifier).reset()` → `Navigator.pop()` |
| "Manage Subscription" | Launch Stripe billing portal URL (or navigate to billing screen) |
| macOS window close `[✕]` | System window close — treated as natural exit |
| Back gesture / escape key | `Navigator.pop()` after `paymentProvider.reset()` |

### 6.3 Screen Data Requirements

| Data | Source | Provider |
|------|--------|----------|
| License key | `PremiumLicenseState.licenseKey` | `premiumLicenseProvider` |
| Plan name | `PremiumLicenseState.planName` | `premiumLicenseProvider` |
| Price display | `PremiumLicenseState.priceDisplay` | `premiumLicenseProvider` |
| Next billing date | `PremiumLicenseState.nextBillingDate` | `premiumLicenseProvider` |
| Payment method display | `PremiumLicenseState.paymentMethod` | `premiumLicenseProvider` |

> If `PremiumLicenseState` does not currently expose `planName`, `priceDisplay`, `nextBillingDate`, or `paymentMethod`, these fields should be added to the entity and populated from the backend `/license/validate` response. Fallback gracefully to static strings (`'Annual'`, `'\$59.99/year'`) when not available — do not block the screen render.

## 7. Token Changes Required

### 7.1 Add JetBrains Mono to `pubspec.yaml`

```yaml
dependencies:
  google_fonts: ^6.x.x  # already present

# No pubspec change needed — google_fonts fetches JetBrainsMono at runtime.
# Use: GoogleFonts.jetBrainsMono(...)
```

### 7.2 Add to `app_typography.dart`

```dart
/// Monospace style for license keys, codes, terminal output
static TextStyle licenseKey({double fontSize = 20}) =>
    GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      fontWeight: FontWeight.w400,
      letterSpacing: 3.0,
    );
```

### 7.3 Existing Color Tokens — All Sufficient

All required colors are covered by existing `AppColors` and `colorScheme`. No new constants needed beyond what was added in first-time-setup spec.

| Design Token | Existing Flutter Mapping | Status |
|-------------|-------------------------|--------|
| `primary` (#ffb3b4 dark) | `colorScheme.primary` | ✅ |
| `primary-container` (#8d0022) | `Color(0xFF8D0022)` direct | ✅ (`AppColors.brand` ≈) |
| `secondary-container` (#910621) | `AppColors.accentMuted` = `Color(0xFF5C0114)` | ⚠ Close — use `Color(0xFF910621)` inline |
| `surface-container-low` (#1c1b1b) | `AppColors.darkSurface1` adjusted | Use `Color(0xFF1C1B1B)` inline |
| `on-surface` (#e5e2e1) | `colorScheme.onSurface` | ✅ |
| `on-surface-variant` (#e1bebd) | `colorScheme.onSurfaceVariant` | ✅ |
| `outline-variant` (#594140) | `colorScheme.outlineVariant` | ✅ (close) |
| `inverse-primary` (#ba1434) | `colorScheme.inversePrimary` | ✅ |

### 7.4 No Changes to `app_spacing.dart` or `app_transitions.dart`

All spacing is expressed as inline `SizedBox` with explicit pixel values. `AppTransitions.fast` and `AppTransitions.curveEnter` are already defined and used.

## 8. Animation Spec

| Animation | Duration | Curve | Notes |
|-----------|----------|-------|-------|
| Screen entrance (fade + slide) | 250ms | `AppTransitions.curveEnter` | Via `AppTransitions.pageRoute` |
| Heading shimmer sweep | 2s loop | Linear | `AnimationController.repeat()` |
| Bento cell hover scale | 150ms | `curveEnter` | `AnimatedScale` |
| CTA hover scale | 150ms | `curveEnter` | `AnimatedScale` |
| CTA shadow grow (25px → 35px) | 150ms | Linear | `AnimatedContainer` |
| Copy button icon swap | 200ms | `curveEnter` | `AnimatedSwitcher` on icon + label |
| Copy confirmation auto-reset | 2s delay | — | `Future.delayed` |
| Background orb: no animation | — | — | Static, blur only |

## 9. Platform Considerations

### 9.1 macOS
- Full-page screen, window chrome native — no manual title bar recreation
- `window_manager.setTitle('SSvid Premium')` during this screen, restore on pop
- `BackdropFilter` with `blur` is GPU-accelerated on macOS — no perf concern
- `MouseRegion` hover effects: ✅ native desktop support

### 9.2 Windows
- Same widget tree, system window chrome (no traffic lights)
- `BackdropFilter` works on Windows with Flutter's Impeller or Skia renderer
- Hover interactions: ✅ works identically

### 9.3 Linux
- Same widget tree, system window chrome
- Blur performance: depends on compositor. Use `ImageFilter.blur` directly rather than `BackdropFilter` as fallback if perf is poor — wrap with platform check

### 9.4 Scrolling
- `SingleChildScrollView` handles overflow at small window heights (e.g., 600px tall)
- Bottom `IgnorePointer` + gradient overlay does not block scroll events

## 10. Verification Checklist

- [ ] Screen fills full window — no modal/overlay frame visible
- [ ] Radial glow renders correctly (dark: crimson center, fades to transparent)
- [ ] Shimmer dots visible (dark: subtle pattern; light: even subtler)
- [ ] Bottom-right orb visible as soft blur circle
- [ ] Heading shimmer animates left-to-right continuously, loops smoothly
- [ ] Subtitle is uppercase, wide tracking, light weight, `onSurfaceVariant` color
- [ ] Glass card has visible blur/frost effect behind it
- [ ] License key renders in JetBrains Mono, rose/primary color
- [ ] Copy button: gradient fill, white text/icon
- [ ] Copy button: icon swaps to checkmark for 2s, then resets
- [ ] Subscription summary: 2 columns with 1px divider between them
- [ ] All subscription data populates from `premiumLicenseProvider` (or graceful fallback)
- [ ] Bento grid: 4 equal columns, all same height via `IntrinsicHeight`
- [ ] Bento cells scale up on hover (scale 1.10), scale down on leave
- [ ] Icon circles: 48px, `primary-container/20` bg, `primary` icon color
- [ ] CTA button: 3-stop gradient (#8D021F → #910621 → #FFB3B4)
- [ ] CTA glow shadow visible below button
- [ ] CTA hover: shadow grows + button scales 1.05
- [ ] CTA press: calls `paymentProvider.reset()` + `Navigator.pop()`
- [ ] "Manage Subscription" text button visible below CTA
- [ ] Bottom gradient overlay covers bottom 1/3 of screen, non-interactive
- [ ] Screen scrollable at 600px window height without clipping content
- [ ] `flutter analyze` passes with 0 issues
- [ ] Dark mode: all tokens render correctly
- [ ] Light mode: all tokens render correctly, glass card uses white/70 bg
- [ ] Navigator back / escape exits screen (paymentProvider reset on pop)
- [ ] Screen navigable from Members Lounge (not only from payment flow)
- [ ] Window title set to "SSvid Premium" on entry, restored on exit
