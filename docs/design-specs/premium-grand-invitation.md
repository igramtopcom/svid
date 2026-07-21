# Design Spec — Premium "Grand Invitation" Screen

**Source**: Google Stitch
**Project ID**: `9746799973876268727`
**Screen ID**: `5ead0daf82bf4095b9d54e3c99911d89`
**Status**: DRAFT — Pending Chairman review
**Current code**: `lib/features/premium/presentation/screens/premium_upgrade_screen.dart` (1595 lines)
**Date**: 2026-03-24

---

## 1. Design Intent

The "Grand Invitation" design transforms the premium screen from a functional form-and-list UI into an atmospheric, cinematic pitch. The visual language is **Nocturne Cinematic**: near-black surfaces layered with wine red (`#8D021F`) and crimson (`#C41E3A`) accents, Inter typeface, and glass-morphism panels. The goal is to make every visitor feel that purchasing is not a transaction but an upgrade to their identity as a power user.

Key shifts in philosophy:

- **Full-width cinema** vs current 720px centered column. The screen breathes — sections span the full available width with a 7xl (1280px) content cap.
- **Pricing as protagonist**: Five standalone pricing cards replace horizontal chip selectors. The Annual plan physically scales to 110% and glows, commanding attention.
- **Features as world-building**: Categories are visual columns with icon headers, not labeled chip-clusters. Reading them feels like reading a product brochure.
- **Payment as invitation**: Two large cards — Standard Billing and Privacy Payment — sit side by side, each complete with their own branding, sub-detail, and a primary CTA.
- **Trust scaffolding**: A 4-icon row beneath payment grounds every purchase claim with silent credibility signals.

The desktop app context modifies two web-only elements: the navigation bar and footer from the HTML reference are omitted entirely. The app's existing `TopNavigationBar` and app chrome replace them.

---

## 2. Visual Structure

### 2.1 Layout

```
┌─────────────────────────────────────────────────────────────────────┐
│  [TopNavigationBar — existing app chrome, unchanged]                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ╔═════════════════════════════════════════════════════════╗        │
│  ║  SECTION 1 — HERO HEADER                               ║        │
│  ║                                                         ║        │
│  ║     ELEVATE YOUR ARCHIVE          ← subtitle, crimson   ║        │
│  ║     SSvid [Premium]               ← title, 6xl bold     ║        │
│  ║       └── "Premium" = auteur-gradient text              ║        │
│  ║     [description paragraph]                             ║        │
│  ║                                                         ║        │
│  ║     [blur atmosphere: 800×400 auteur-gradient, 120px]  ║        │
│  ╚═════════════════════════════════════════════════════════╝        │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────┐      │
│  │  SECTION 2 — PRICING GRID (5 columns)                    │      │
│  │                                                           │      │
│  │  ┌──────┐ ┌──────┐ ┌────────────┐ ┌══════════╗ ┌──────┐ │      │
│  │  │Month │ │Qrtly │ │ Semi-Ann.  │ ║  ANNUAL  ║ │Life  │ │      │
│  │  │$9.99 │ │$24.99│ │ $39.99     │ ║  $59.99  ║ │$149.9│ │      │
│  │  │      │ │      │ │[Best Value]│ ║ scale110%║ │      │ │      │
│  │  │      │ │      │ │ glow-subt. │ ║ glow-int.║ │      │ │      │
│  │  └──────┘ └──────┘ └────────────┘ ╚══════════╝ └──────┘ │      │
│  └───────────────────────────────────────────────────────────┘      │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────┐      │
│  │  SECTION 3 — FEATURES GRID (3 columns × 3 categories)   │      │
│  │                                                           │      │
│  │  ┌─────────────────┐ ┌─────────────────┐ ┌────────────┐ │      │
│  │  │ AI INTELLIGENCE │ │ CLOUD & PRIVACY │ │ ANALYTICS  │ │      │
│  │  │  [psychology]   │ │  [encrypted]    │ │ [monitor]  │ │      │
│  │  │  feature title  │ │  feature title  │ │ feat. title│ │      │
│  │  │  feature desc   │ │  feature desc   │ │ feat. desc │ │      │
│  │  │  feature title  │ │  feature title  │ │ feat. title│ │      │
│  │  │  feature desc   │ │  feature desc   │ │ feat. desc │ │      │
│  │  │  feature title  │ │  feature title  │ │ feat. title│ │      │
│  │  │  feature desc   │ │  feature desc   │ │ feat. desc │ │      │
│  │  └─────────────────┘ └─────────────────┘ └────────────┘ │      │
│  └───────────────────────────────────────────────────────────┘      │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────┐      │
│  │  SECTION 4 — PAYMENT CARDS (2 columns)                   │      │
│  │                                                           │      │
│  │  ┌──────────────────────┐  ┌──────────────────────────┐  │      │
│  │  │ STANDARD BILLING     │  │  PRIVACY PAYMENT         │  │      │
│  │  │ Card / Bank Transfer │  │  Bitcoin · Litecoin      │  │      │
│  │  │ Stripe + Visa logos  │  │  Monero — no KYC         │  │      │
│  │  │                      │  │                          │  │      │
│  │  │ [GET PREMIUM NOW]    │  │  [PAY WITH CRYPTO]       │  │      │
│  │  │  auteur-gradient CTA │  │   outlined CTA           │  │      │
│  │  └──────────────────────┘  └──────────────────────────┘  │      │
│  │                                                           │      │
│  │  ── TRUST SIGNALS (4 columns) ────────────────────────── │      │
│  │  [verified_user]  [lock]  [support_agent]  [cloud_done]  │      │
│  │  SECURE           PRIVATE  LIVE SUPPORT    CLOUD SYNC    │      │
│  └───────────────────────────────────────────────────────────┘      │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────┐      │
│  │  SECTION 5 — LICENSE ACTIVATION                          │      │
│  │                                                           │      │
│  │  Already have a license?                                  │      │
│  │  ┌──────────────────────────────────────────┐ [Activate] │      │
│  │  │  Enter your license key…                 │            │      │
│  │  └──────────────────────────────────────────┘            │      │
│  │  [Restore by email]                                       │      │
│  └───────────────────────────────────────────────────────────┘      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 Dimensions Table

| Element | Width | Height | Notes |
|---|---|---|---|
| Screen max-width | 1280px (7xl) | — | Full viewport width, content capped |
| Hero section | 100% | min 320px | Padding: 96px v, 48px h |
| Hero blur orb | 800px | 400px | Absolute, centered, blur(120px), opacity 0.1 |
| Pricing grid | 100% | auto | 5 equal columns, gap 16px, padding 32px v |
| Pricing card (standard) | 1fr | auto | Padding 24px, radius 12px |
| Pricing card (Annual — hero) | 1fr | auto | scale(1.1), z-index 10, padding 32px |
| Features grid | 100% | auto | 3 equal columns, gap 24px, padding 64px v |
| Feature column | 1fr | auto | Padding 24px, radius 12px |
| Payment cards row | 100% | auto | 2 equal columns, gap 24px |
| Payment card | 1fr | auto | Padding 32px, radius 16px |
| Trust signals row | 100% | auto | 4 equal columns, gap 16px, padding 32px v |
| License activation | 100% | auto | Max-width 640px, centered, padding 32px |
| Input field | Expanded | 48px | Radius 8px |
| Activate button | auto | 48px | Min-width 120px |

### 2.3 Spacing Table

| Context | Value | Token |
|---|---|---|
| Section vertical padding | 64px / 96px | `spacing.section` |
| Section horizontal padding | 48px | `spacing.sectionH` |
| Card internal padding (standard) | 24px | `spacing.cardMd` |
| Card internal padding (hero annual) | 32px | `spacing.cardLg` |
| Column gap (pricing grid) | 16px | `spacing.gridGap` |
| Column gap (features grid) | 24px | `spacing.gridGapLg` |
| Column gap (payment cards) | 24px | `spacing.gridGapLg` |
| Column gap (trust signals) | 16px | `spacing.gridGap` |
| Hero title bottom margin | 16px | `spacing.md` |
| Hero subtitle top margin | 0px, subtitle above title | — |
| Feature item gap (title → desc) | 4px | `spacing.xs` |
| Feature item gap (entry → entry) | 16px | `spacing.md` |
| Badge padding | 4px × 8px | `spacing.badgeH` |
| Section header bottom margin | 48px | `spacing.headerGap` |

---

## 3. Token Extraction — Dark Mode

### 3.1 Colors — Dark Mode

| Role | Hex | Usage |
|---|---|---|
| `surfaceContainerLowest` | `#0e0e0e` | Body background, Annual card CTA background |
| `surface` | `#131313` | Navigation shadow base |
| `surfaceContainerLow` | `#1c1b1b` | Monthly, Quarterly card background |
| `surfaceContainer` | `#201f1f` | Semi-Annual card background |
| `surfaceContainerHigh` | `#2a2a2a` | Annual hero card background (under gradient) |
| `surfaceContainerHighest` | `#353534` | Hover states, subtle chip backgrounds |
| `surfaceBright` | `#3a3939` | Focus rings, active indicator |
| `onSurface` | `#e5e2e1` | Body text, card labels |
| `onSurfaceVariant` | `#e1bebd` | Secondary text, billing period labels |
| `primary` | `#ffb3b4` | Primary accent, M3 primary role |
| `primaryContainer` | `#8d0022` | Semi-Annual top border color |
| `onPrimaryContainer` | `#ff9396` | Semi-Annual price text |
| `secondary` | `#ffb2bc` | Hero subtitle text "ELEVATE YOUR ARCHIVE" |
| `outline` | `#a88989` | Default card border |
| `outlineVariant` | `#594140` | Muted card border (Monthly/Quarterly/Lifetime) |
| `inversePrimary` | `#ba1434` | Gradient stop 2, glow base color |
| `tertiaryContainer` | `#8d021f` | Gradient stop 1, auteur brand red |
| `auteurGradientStart` | `#8d021f` | `linear-gradient(135deg, ...)` stop 0% |
| `auteurGradientEnd` | `#ba1434` | `linear-gradient(135deg, ...)` stop 100% |
| `glowSubtle` | `rgba(141,0,34,0.10)` | Semi-Annual card box-shadow spread |
| `glowIntense` | `rgba(186,20,52,0.20)` | Annual hero card box-shadow spread |
| `navShadow` | `rgba(141,0,34,0.04)` | Top nav bottom shadow |
| `glassPanelBg` | `rgba(14,14,14,0.60)` | Glass-morphism panel fill |
| `heroBlueBg` | `rgba(141,2,31,0.10)` | Hero blur orb (auteur at 10% opacity) |
| `lifetimeBg` | `#1a1a1a` | Lifetime card background |
| `lifetimeBorder` | `rgba(89,65,64,0.20)` | Lifetime card border (`outlineVariant` 20%) |

### 3.2 Colors — Light Mode

Light mode is not represented in the Stitch design. The implementation should derive light tokens by inverting the luminance stack while preserving the auteur-gradient identity:

| Role | Light Hex (derived) | Notes |
|---|---|---|
| `surfaceContainerLowest` | `#faf9f9` | Near-white body |
| `surface` | `#f4f0f0` | Light surface |
| `surfaceContainerLow` | `#ede8e8` | Card backgrounds |
| `onSurface` | `#1c1b1b` | Dark text |
| `onSurfaceVariant` | `#4e3736` | Secondary text |
| `primary` | `#ba1434` | Crimson primary |
| `primaryContainer` | `#ffdad9` | Light primary container |
| `auteurGradientStart` | `#8d021f` | Unchanged — brand identity |
| `auteurGradientEnd` | `#ba1434` | Unchanged — brand identity |
| `glowSubtle` | `rgba(141,0,34,0.06)` | Reduced opacity for light bg |
| `glowIntense` | `rgba(141,0,34,0.12)` | Reduced opacity for light bg |

### 3.3 Typography Table

| Element | Size | Weight | Tracking | Transform | Color Token |
|---|---|---|---|---|---|
| Hero subtitle "ELEVATE YOUR ARCHIVE" | 14px (sm) | 600 | 0.2em | uppercase | `secondary` |
| Hero title "SSvid" | 60px / 96px | 700 | tight | — | `onSurface` |
| Hero title "Premium" word | 60px / 96px | 700 | tight | — | auteur-gradient text clip |
| Hero description | 16px | 400 | normal | — | `onSurfaceVariant` |
| Plan label (MONTHLY, etc.) | 14px | 700 | widest (0.1em+) | uppercase | `onSurface` / `onPrimary` |
| Plan price (standard) | 36px | 700 | tight | — | `onSurface` |
| Plan price (Annual hero) | 48px | 800 | tight | — | `onSurface` (on gradient bg) |
| "per month" / billing period | 12px | 400 | normal | — | `onSurfaceVariant` opacity 0.6 |
| "Best Value" badge | 10px | 700 | normal | uppercase | white (on auteur-gradient) |
| "The Professional Choice" | 14px | 400 | normal | italic | `onSurface` opacity 0.7 |
| Feature section header | 18px | 700 | tight | uppercase | `onSurface` |
| Feature item title | 14px | 600 | normal | — | `onSurface` |
| Feature item description | 12px | 400 | normal | — | `onSurfaceVariant` |
| Payment card title | 20px | 700 | tight | — | `onSurface` |
| Payment card subtitle | 14px | 400 | normal | — | `onSurfaceVariant` |
| Payment CTA label | 16px | 700 | wider | uppercase | white / `onSurface` |
| Trust signal label | 12px | 700 | widest | uppercase | `onSurface` |
| Trust signal description | 10px | 400 | normal | — | `onSurfaceVariant` |
| License section header | 16px | 600 | normal | — | `onSurface` |
| License input placeholder | 13px | 400 | normal | — | `onSurface` opacity 0.3 |

### 3.4 Effects Table

| Effect Name | CSS / Flutter Equivalent | Value |
|---|---|---|
| `auteur-gradient` | `LinearGradient(135deg)` | `#8d021f` 0% → `#ba1434` 100% |
| `glass-panel` | `BackdropFilter(blur) + BoxDecoration` | blur(16px) + bg `rgba(14,14,14,0.6)` |
| `glow-subtle` | `BoxShadow` | `0 0 40px rgba(141,0,34,0.10)` |
| `glow-intense` | `BoxShadow` | `0 0 60px rgba(186,20,52,0.20)` |
| `hero-bg-blur` | `ImageFiltered` / `BackdropFilter` | 800×400px auteur-gradient, blur(120px), opacity 0.1 |
| `nav-shadow` | `BoxShadow` | `0 24px 24px rgba(141,0,34,0.04)` |
| `annual-scale` | `Transform.scale` | `scale: 1.1`, `alignment: Alignment.center`, `z-index: 10` |
| `annual-bg` | `BoxDecoration gradient + color` | `surfaceContainerHigh` base + auteur-gradient overlay |
| `pricing-hover-border` | `AnimatedContainer` border | border → `outlineVariant` on hover |
| `gradient-text-clip` | `ShaderMask` / `Paint shader` | auteur-gradient clipped to text bounds |

---

## 4. Gap Analysis — Design vs Current Code

### 4.1 MAJOR Changes

| # | Area | Current Code | Design Target | Priority |
|---|---|---|---|---|
| 1 | Max width | 720px centered | 1280px (7xl) full-section layout | HIGH |
| 2 | Hero | Icon + headlineSmall text in gradient-bordered container | Full-width cinematic hero with blur orb, gradient text on "Premium", subtitle with letter-spacing | HIGH |
| 3 | Pricing layout | Horizontal chips in 2-row grid | 5 standalone vertical pricing cards in a single row | HIGH |
| 4 | Annual plan | Standard chip with primary border | Hero card: scale 1.1, glow-intense, auteur-gradient bg, `text-5xl extrabold`, "The Professional Choice" italic | HIGH |
| 5 | Semi-Annual plan | Standard chip | Elevated card: top border 2px `primary-container`, glow-subtle, "Best Value" badge | MEDIUM |
| 6 | Lifetime plan | Standard chip (`lifetime1/2/3`) | Single Lifetime card, `#1a1a1a` bg, muted border | MEDIUM |
| 7 | Features layout | Vertical accordion list of categories + chip wraps | 3-column grid, each column = category with icon header + 3 feature rows (title + desc) | HIGH |
| 8 | Payment section | 2 row-cards with icon, title, subtitle, arrow | 2 large side-by-side cards with branding, sub-details, and full-width CTA buttons | HIGH |
| 9 | Trust signals | Not present | 4-column icon row below payment section | MEDIUM |
| 10 | License activation | Container with 2 buttons (Activate Key, Restore) | Dedicated section with inline input field + Activate button, restore as text link | LOW |
| 11 | Background | `Scaffold` default surface | `#0e0e0e` custom background throughout | HIGH |
| 12 | Billing cycles count | 5 cycles (monthly, yearly, lifetime1/2/3) | 5 plans (monthly, quarterly, semi-annual, annual, lifetime) — mapping needed | HIGH |
| 13 | Prices | $7.99 / $29.99 / $49.99 / $79.99 / $99 | $9.99 / $24.99 / $39.99 / $59.99 / $149.99 — Stripe is source of truth, prices from `productPricingProvider` | NOTE |

### 4.2 KEEP (unchanged from current code)

| Element | Reason |
|---|---|
| `paymentProvider` and all payment notifier logic | Business logic unchanged |
| `premiumLicenseProvider` and `PremiumLicense` entity | Data model unchanged |
| `selectedBillingCycleProvider` | State provider unchanged — UI binds to it |
| `_showActivateKeyDialog` | Dialog UI unchanged |
| `_showRestoreLicenseDialog` | Dialog UI unchanged |
| `_showCryptoSelector` | Bottom sheet unchanged |
| `_showActivationSuccessDialog` | Celebration dialog unchanged |
| `_showActivationErrorDialog` | Error dialog unchanged |
| `_buildSubscriptionManagement` | Active subscriber view unchanged |
| `_buildInfoRow` | Subscription detail rows unchanged |
| `_confirmCancelSubscription` / `_confirmDeactivate` | Confirmation dialogs unchanged |
| All `AppLocalizations` string keys | No new keys needed for redesign |
| `AppColors`, `AppColors.success`, `AppColors.border` | Color helpers unchanged |
| Top bar (56px, border-bottom) | App-level navigation chrome unchanged |

### 4.3 UX Decisions

**Nav bar**: The Stitch HTML includes a sticky top navigation with logo and links. This is a web pattern. The desktop app uses `TopNavigationBar` (existing, unchanged). Do not implement a second nav bar inside the premium screen.

**Footer**: The Stitch HTML has a footer with SSvid logo and links. This is a web pattern. The desktop app has no footer. Omit entirely.

**Billing cycle mapping**: The design shows 5 plans (Monthly, Quarterly, Semi-Annual, Annual, Lifetime). Current `BillingCycle` enum has: `monthly`, `yearly`, `lifetime1`, `lifetime2`, `lifetime3`. The redesign collapses the 3 lifetime variants into a single "Lifetime" display card. The card triggers `_showCryptoSelector` or Stripe with a default cycle (`lifetime1`). A separate "Lifetime Device Tiers" expansion UI (optional) can be deferred.

**Prices**: Design reference shows $9.99/$24.99/$39.99/$59.99/$149.99. These are visual placeholders. The app renders prices from `productPricingProvider` (backend-sourced from Stripe). The design's prices must not be hardcoded. Use the existing provider — if the provider returns null, show a loading shimmer in the price slot.

**Annual as hero**: The Annual card is the primary upsell. `selectedBillingCycleProvider` should default to `BillingCycle.yearly` when the screen opens.

**Hover states**: Flutter desktop supports `MouseRegion`. Pricing cards animate their border color on hover (add `AnimatedContainer` with hover state).

**Active subscriber view**: When `license.isActiveSubscription == true`, the pricing grid and payment section are replaced by `_buildSubscriptionManagement`. The hero section adapts its copy. Features grid and trust signals remain visible.

---

## 5. Widget Spec — Flutter Implementation

### 5.1 Widget Tree

```
PremiumUpgradeScreen (ConsumerWidget)
└── Scaffold
    ├── TopBar (56px, existing — unchanged)
    └── Expanded
        └── SingleChildScrollView
            └── Column
                ├── _HeroSection
                │   ├── Stack
                │   │   ├── _HeroBlurOrb (Positioned, absolute)
                │   │   └── Column (content)
                │   │       ├── Text (subtitle — "ELEVATE YOUR ARCHIVE")
                │   │       ├── _GradientTextTitle ("SSvid Premium")
                │   │       └── Text (description)
                │   └── [if isActive] _ActiveBadge
                ├── _PricingGridSection
                │   └── Row (5 children, Expanded each)
                │       ├── _PricingCard(Monthly)
                │       ├── _PricingCard(Quarterly)
                │       ├── _PricingCard(SemiAnnual, isFeatured: true)
                │       ├── _PricingCard(Annual, isHero: true)
                │       └── _PricingCard(Lifetime)
                ├── _FeaturesGridSection
                │   └── Row (3 children, Expanded each)
                │       ├── _FeatureColumn(AiIntelligence)
                │       ├── _FeatureColumn(CloudPrivacy)
                │       └── _FeatureColumn(AnalyticsTools)
                ├── [if !isActive] _PaymentSection
                │   ├── Row (2 children, Expanded each)
                │   │   ├── _PaymentCard(stripe)
                │   │   └── _PaymentCard(crypto)
                │   └── _TrustSignalsRow
                └── [if !isActive] _LicenseActivationSection
                    ├── Row (input + button)
                    └── TextButton (Restore by email)
```

### 5.2 `_HeroSection`

```dart
class _HeroSection extends StatelessWidget {
  final PremiumLicense license;
  const _HeroSection({required this.license});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 96, horizontal: 48),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Blur atmosphere orb
          Positioned(
            child: _HeroBlurOrb(),
          ),
          // Content
          Column(
            children: [
              // Subtitle
              Text(
                'ELEVATE YOUR ARCHIVE',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2 * 14, // 0.2em
                  color: cs.secondary,
                ),
              ),
              const SizedBox(height: 16),
              // Title with gradient text on "Premium"
              _GradientTextTitle(),
              const SizedBox(height: 16),
              // Description
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(
                  'Unlock the complete SSvid experience — unlimited downloads, '
                  'AI-powered tools, cloud sync, and priority support.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    color: cs.onSurfaceVariant,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

### 5.3 `_HeroBlurOrb`

```dart
class _HeroBlurOrb extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: 800,
        height: 400,
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF8D021F), Color(0xFFBA1434)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

Note: Wrap `_HeroBlurOrb` in `Opacity(opacity: 0.1)` to achieve the 10% opacity from the design. `ImageFilter.blur` at 120px will extend beyond the container bounds — clip using `ClipRect` on the Stack if overflow causes layout issues.

### 5.4 `_GradientTextTitle`

```dart
class _GradientTextTitle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const titleSize = 72.0; // 6xl — adapt to available width

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        children: [
          TextSpan(
            text: 'SSvid ',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: titleSize,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          // "Premium" with gradient shader
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xFF8D021F), Color(0xFFBA1434)],
              ).createShader(bounds),
              child: Text(
                'Premium',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: titleSize,
                  fontWeight: FontWeight.w700,
                  color: Colors.white, // ShaderMask requires opaque base
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

### 5.5 `_PricingGridSection` and `_PricingCard`

The pricing grid is a `Row` of 5 `Expanded` children. The Annual card uses `Transform.scale`.

```dart
class _PricingGridSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCycle = ref.watch(selectedBillingCycleProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end, // annual scales up, align others to bottom
        children: [
          Expanded(child: _PricingCard(
            cycle: BillingCycle.monthly,
            label: 'MONTHLY',
            billingNote: 'per month',
            isSelected: selectedCycle == BillingCycle.monthly,
          )),
          const SizedBox(width: 16),
          Expanded(child: _PricingCard(
            cycle: BillingCycle.quarterly, // map to existing quarterly if present, else use monthly logic
            label: 'QUARTERLY',
            billingNote: 'per quarter',
            isSelected: selectedCycle == BillingCycle.quarterly,
          )),
          const SizedBox(width: 16),
          Expanded(child: _PricingCard(
            cycle: BillingCycle.semiAnnual,
            label: 'SEMI-ANNUAL',
            billingNote: 'per 6 months',
            isFeatured: true,
            isSelected: selectedCycle == BillingCycle.semiAnnual,
          )),
          const SizedBox(width: 16),
          Expanded(child: _PricingCard(
            cycle: BillingCycle.yearly,
            label: 'ANNUAL',
            billingNote: 'per year',
            heroNote: 'The Professional Choice',
            isHero: true,
            isSelected: selectedCycle == BillingCycle.yearly,
          )),
          const SizedBox(width: 16),
          Expanded(child: _PricingCard(
            cycle: BillingCycle.lifetime1,
            label: 'LIFETIME',
            billingNote: 'one-time',
            isSelected: selectedCycle == BillingCycle.lifetime1,
          )),
        ],
      ),
    );
  }
}
```

**`_PricingCard` — key decoration logic:**

```dart
// Standard card (Monthly, Quarterly)
BoxDecoration(
  color: const Color(0xFF1C1B1B), // surfaceContainerLow
  borderRadius: BorderRadius.circular(12),
  border: Border.all(color: const Color(0xFF594140)), // outlineVariant
)

// Featured card (Semi-Annual)
BoxDecoration(
  color: const Color(0xFF201F1F), // surfaceContainer
  borderRadius: BorderRadius.circular(12),
  border: Border(
    top: const BorderSide(color: Color(0xFF8D0022), width: 2), // primaryContainer
    left: BorderSide(color: const Color(0xFF594140)),
    right: BorderSide(color: const Color(0xFF594140)),
    bottom: BorderSide(color: const Color(0xFF594140)),
  ),
  boxShadow: [BoxShadow(color: Color(0xFF8D0022).withValues(alpha: 0.10), blurRadius: 40)],
)
// "Best Value" badge: auteur-gradient container, 10px font, uppercase, padding 4×8

// Annual hero card — wrapped in Transform.scale(scale: 1.1)
BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2A2A2A), Color(0xFF8D021F)], // surfaceContainerHigh + brand
  ),
  borderRadius: BorderRadius.circular(12),
  boxShadow: [BoxShadow(color: Color(0xFFBA1434).withValues(alpha: 0.20), blurRadius: 60)],
)
// Price: 48px, FontWeight.w800
// CTA button bg: Color(0xFF0E0E0E) — surfaceContainerLowest

// Lifetime card
BoxDecoration(
  color: const Color(0xFF1A1A1A),
  borderRadius: BorderRadius.circular(12),
  border: Border.all(color: const Color(0xFF594140).withValues(alpha: 0.20)),
)
```

**Hover behavior** (all cards):

```dart
class _PricingCard extends ConsumerStatefulWidget { ... }

class _PricingCardState extends ConsumerState<_PricingCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => ref.read(selectedBillingCycleProvider.notifier).state = widget.cycle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          // border animates to outlineVariant on hover for non-hero cards
          // ...
        ),
      ),
    );
  }
}
```

**Price display**: Bind to `ref.watch(productPricingProvider)`. Show `CircularProgressIndicator(strokeWidth: 1.5)` in the price slot if data is loading. Never hardcode prices.

### 5.6 `_FeaturesGridSection` and `_FeatureColumn`

Three design columns map to the 6 existing feature categories by collapsing 2 categories per column:

| Design Column | Icon | Categories |
|---|---|---|
| AI Intelligence | `Icons.psychology` | AI (summarization, subtitle translation, smart feed) |
| Cloud & Privacy | `Icons.encrypted` | Cloud + Security (sync, remote control, vault, app lock) |
| Analytics & Tools | `Icons.monitoring` | Analytics + Download + Organization |

Each column shows exactly 3 feature items (title + description). If a category has more than 3 features, the spec shows 3 per column — trim or stack visually.

```dart
class _FeatureColumn extends StatelessWidget {
  final String categoryLabel;
  final IconData categoryIcon;
  final List<(String title, String description)> features;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1B1B), // surfaceContainerLow
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category header
          Icon(categoryIcon, size: 28, color: cs.primary),
          const SizedBox(height: 12),
          Text(
            categoryLabel,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: Color(0xFFE5E2E1),
            ),
          ),
          const SizedBox(height: 20),
          // Feature rows
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.$1, style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE5E2E1),
                )),
                const SizedBox(height: 4),
                Text(f.$2, style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: Color(0xFFE1BEBD),
                )),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
```

### 5.7 `_PaymentSection`

```dart
class _PaymentSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentState = ref.watch(paymentProvider);
    final billingCycle = ref.watch(selectedBillingCycleProvider);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 48),
      child: Column(
        children: [
          // 2-column payment cards
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _StripePaymentCard(
                isLoading: paymentState.isLoading && paymentState.session != null,
                onTap: paymentState.isLoading
                    ? null
                    : () => ref.read(paymentProvider.notifier)
                        .startStripeCheckout(billingCycle),
              )),
              const SizedBox(width: 24),
              Expanded(child: _CryptoPaymentCard(
                isLoading: paymentState.isLoading && paymentState.invoice != null,
                onTap: paymentState.isLoading
                    ? null
                    : () => _showCryptoSelector(context, ref),
              )),
            ],
          ),
          const SizedBox(height: 32),
          // Error / success banners (existing logic, unchanged)
          _PaymentStatusBanner(paymentState),
          const SizedBox(height: 32),
          // Trust signals row
          _TrustSignalsRow(),
        ],
      ),
    );
  }
}
```

**`_StripePaymentCard` decoration:**

```dart
BoxDecoration(
  color: const Color(0xFF1C1B1B), // surfaceContainerLow
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: const Color(0xFF594140).withValues(alpha: 0.5)),
)
// CTA: Container with auteur-gradient, full width, 48px height, radius 8
// gradient: LinearGradient(135°, [Color(0xFF8D021F), Color(0xFFBA1434)])
```

**`_CryptoPaymentCard` decoration:**

```dart
BoxDecoration(
  color: const Color(0xFF1C1B1B),
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: const Color(0xFF594140).withValues(alpha: 0.5)),
)
// Sub-detail: "Bitcoin · Litecoin · Monero"
// Privacy note: "No KYC required. Fully anonymous."
// CTA: OutlinedButton with auteur-gradient border, transparent fill
```

### 5.8 `_TrustSignalsRow`

Four equal columns. Each: icon (28px, `cs.primary`) → label → description.

```dart
Row(
  children: [
    Expanded(child: _TrustSignal(Icons.verified_user, 'SECURE', '256-bit encryption')),
    const SizedBox(width: 16),
    Expanded(child: _TrustSignal(Icons.lock, 'PRIVATE', 'No data harvesting')),
    const SizedBox(width: 16),
    Expanded(child: _TrustSignal(Icons.support_agent, 'LIVE SUPPORT', 'Response < 24h')),
    const SizedBox(width: 16),
    Expanded(child: _TrustSignal(Icons.cloud_done, 'CLOUD SYNC', 'Cross-device access')),
  ],
)
```

### 5.9 `_LicenseActivationSection`

Replaces current `_buildActivateLicenseKey` — same logic, new layout.

```dart
Container(
  width: double.infinity,
  padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 48),
  child: Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Already have a license?', style: /* 16px 600 */),
          const SizedBox(height: 4),
          Text('Paste your key below to activate instantly.', style: /* 14px onSurfaceVariant */),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keyController,
                  decoration: InputDecoration(
                    hintText: 'SSVID-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                    filled: true,
                    fillColor: const Color(0xFF1C1B1B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    // border color: outlineVariant
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: () => _showActivateKeyDialog(context, ref),
                  style: FilledButton.styleFrom(
                    // auteur-gradient via ButtonStyle + ShaderMask or gradient BoxDecoration overlay
                    backgroundColor: const Color(0xFF8D021F),
                  ),
                  child: const Text('ACTIVATE'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _showRestoreLicenseDialog(context, ref),
            child: const Text('Restore by email'),
          ),
        ],
      ),
    ),
  ),
)
```

---

## 6. State Flow

```
PremiumUpgradeScreen opens
  → premiumLicenseProvider.isActiveSubscription ?
      YES → show Hero (active copy) + _buildSubscriptionManagement
             Features grid + Trust signals visible
             Pricing grid hidden
             Payment section hidden
      NO  → show full Grand Invitation layout (all 5 sections)

User taps pricing card (non-hero)
  → selectedBillingCycleProvider.state = tapped cycle
  → All 5 cards re-render: selected card gets primary border ring

User taps [GET PREMIUM NOW] (Stripe card)
  → paymentProvider.notifier.startStripeCheckout(selectedCycle)
  → PaymentState.isLoading = true
  → CTA shows CircularProgressIndicator
  → On session created: launches browser URL (existing logic)

User taps [PAY WITH CRYPTO]
  → _showCryptoSelector(context, ref) — bottom sheet (existing, unchanged)
  → Selects BTC/LTC/XMR → paymentProvider.notifier.startCryptoCheckout(currency, cycle)

paymentProvider listen (existing):
  → activationError → _showActivationErrorDialog
  → isActivationSuccess → _showActivationSuccessDialog (screen reloads as active subscriber view)

License input + Activate button
  → opens _showActivateKeyDialog (existing dialog, unchanged behavior)

Restore by email
  → opens _showRestoreLicenseDialog (existing dialog, unchanged behavior)
```

---

## 7. Animation Spec

| Animation | Trigger | Duration | Curve | Implementation |
|---|---|---|---|---|
| Pricing card border on hover | `MouseRegion.onEnter/Exit` | 200ms | `Curves.easeOut` | `AnimatedContainer` border color |
| Pricing card selected ring | `selectedBillingCycleProvider` change | 200ms | `Curves.easeInOut` | `AnimatedContainer` border + shadow |
| Annual card scale | static (always 1.1) | — | — | `Transform.scale(scale: 1.1)` |
| Stripe CTA loading state | `paymentState.isLoading` | instant | — | Replace button content with `CircularProgressIndicator` |
| Crypto CTA loading state | `paymentState.isLoading` | instant | — | Replace button content with `CircularProgressIndicator` |
| Payment status banner appear | `paymentState.error != null` / `isSuccess` | 300ms | `Curves.easeOut` | `AnimatedSwitcher` wrapping banner |
| Hero blur orb | static (no animation in v1) | — | — | Static `ImageFiltered` |
| Screen entry | scroll to top on open | instant | — | `ScrollController.jumpTo(0)` in `initState` |

**Deferred (v2)**:
- Hero orb slow drift animation (`AnimationController` + `SlideTransition`)
- Annual card subtle pulse glow (`AnimationController` + `BoxShadow` lerp)
- Pricing card micro-bounce on selection (`AnimationController` + `ScaleTransition` 1.0 → 1.02 → 1.0)

---

## 8. Verification Checklist

### Visual Fidelity
- [ ] Body background is `#0e0e0e` (not default M3 surface)
- [ ] Hero subtitle "ELEVATE YOUR ARCHIVE" is uppercase, 0.2em letter-spacing, `secondary` color
- [ ] "Premium" word in hero title renders auteur-gradient via `ShaderMask`
- [ ] Hero blur orb is present: 800×400, blur 120px, 10% opacity, centered
- [ ] Pricing grid has exactly 5 columns in a single row (not 2-row layout)
- [ ] Semi-Annual card has top border `#8d0022` 2px + glow-subtle shadow
- [ ] Semi-Annual card has "Best Value" badge in auteur-gradient with 10px text
- [ ] Annual card is visually scaled to 110% (`Transform.scale`)
- [ ] Annual card background uses auteur-gradient overlay on `surfaceContainerHigh`
- [ ] Annual card price text is 48px / FontWeight.w800
- [ ] Annual card CTA button background is `#0e0e0e` (surfaceContainerLowest)
- [ ] Annual card has glow-intense shadow (60px blur, `rgba(186,20,52,0.20)`)
- [ ] Annual card shows "The Professional Choice" italic note
- [ ] Lifetime card background is `#1a1a1a`, border at 20% opacity
- [ ] Features section is 3 equal columns (not accordion list)
- [ ] Feature columns use `Icons.psychology`, `Icons.encrypted`, `Icons.monitoring`
- [ ] Feature column headers are uppercase, 18px bold
- [ ] Payment section is 2 equal columns side by side
- [ ] Stripe card CTA is full-width auteur-gradient container
- [ ] Trust signals row has 4 columns: verified_user, lock, support_agent, cloud_done
- [ ] Trust signal labels are uppercase, 12px bold, widest tracking
- [ ] License activation section is centered, max 640px wide
- [ ] License input + Activate button are in a single row

### Behavioral
- [ ] `selectedBillingCycleProvider` defaults to `BillingCycle.yearly` on screen open
- [ ] Tapping any pricing card updates `selectedBillingCycleProvider`
- [ ] Prices are read from `productPricingProvider` (not hardcoded)
- [ ] Loading shimmer shown in price slot when provider is loading
- [ ] Annual card CTA triggers `startStripeCheckout(BillingCycle.yearly)`
- [ ] Hover on pricing cards animates border color in 200ms
- [ ] Active subscriber sees `_buildSubscriptionManagement` instead of pricing grid
- [ ] `_showActivateKeyDialog` opens from Activate button (unchanged logic)
- [ ] `_showRestoreLicenseDialog` opens from "Restore by email" link (unchanged logic)
- [ ] `_showCryptoSelector` opens from Crypto card CTA (unchanged logic)
- [ ] `_showActivationSuccessDialog` triggers on `isActivationSuccess` (unchanged logic)
- [ ] `_showActivationErrorDialog` triggers on `activationError` (unchanged logic)
- [ ] `_showCryptoSelector` bottom sheet still works (unchanged)
- [ ] `_buildSubscriptionManagement` cancel / deactivate buttons still function

### Accessibility
- [ ] All interactive elements have `Semantics` labels
- [ ] Pricing cards are keyboard-focusable (`FocusNode` per card)
- [ ] Gradient text "Premium" has a `Semantics` `label: 'Premium'` override (screen readers cannot read gradient-painted text)
- [ ] Trust signal icons have `Semantics(label: ...)` with the label text
- [ ] Contrast: `onSurfaceVariant (#e1bebd)` on `surfaceContainerLow (#1c1b1b)` — verify WCAG AA (minimum 4.5:1 for text below 18px)
- [ ] `AnimatedContainer` durations respect `MediaQuery.disableAnimations`

### Regression
- [ ] `fvm flutter analyze --no-pub` — zero issues
- [ ] `fvm flutter test` — all 141 tests passing
- [ ] macOS release build succeeds (`fvm flutter build macos --release`)
- [ ] No hardcoded prices anywhere in the new widget code
- [ ] `paymentProvider`, `premiumLicenseProvider`, `selectedBillingCycleProvider` — no breaking changes to provider signatures
- [ ] TopNavigationBar (existing app chrome) — unaffected
