# Premium Member's Lounge — Design Spec

> Source: Stitch project `9746799973876268727`
> Screen: `83c98c6ae5334d9aba7209dd3328b865`
> Status: DRAFT — Pending Chairman review
> Current code: `lib/features/premium/presentation/screens/premium_upgrade_screen.dart` — `_buildSubscriptionManagement()` method (lines 864–1021)

## 1. Design Intent

**Purpose**: Full-page subscription management dashboard shown exclusively to active Premium users. Replaces the current minimal `_buildSubscriptionManagement()` section with a dedicated, cinematic management experience.

**Mood**: VIP lounge, not a settings panel. "You've earned this — here's your command center." The user should feel recognized, not processed.

**Key principle**: Information density with visual hierarchy. Every data point earns its place. The crown + glow header communicates premium identity before the user reads a single word.

**Scope boundary**: Usage stats (batch downloads, AI searches, cloud storage) are cosmetic in this design — the current backend does not track per-user consumption. All progress bar values and stat boxes are **FUTURE** placeholders. Mark clearly in code. Do not invent tracking logic to fill them.

## 2. Visual Structure

### 2.1 Layout Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  [●][●][●]   SSvid Premium                          top bar     │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  [VIP Access ●]                               gradient bg │  │
│  │  👑 SSvid Premium Member                                  │  │  ← Membership Header
│  │  Member since October 2024 • Annual Plan                  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌──────────────────────────────┐  ┌──────────────────────────┐ │
│  │ ▌ Current Plan               │  │ Your Premium Usage       │ │
│  │   $59.99/year  [● Active]    │  │                          │ │
│  │   Next Billing   Payment     │  │  Batch Downloads ░░░░    │ │  ← Dashboard Grid
│  │   [Master License Key] [⎘]   │  │  AI Deep Searches ░░░   │ │    (7 cols | 5 cols)
│  │   [══] Auto-renewal enabled  │  │  Cloud Storage ░░░░░░    │ │
│  │   [Update Payment]           │  │  [84%] [0]               │ │
│  │   Deactivate   Cancel        │  │  Efficiency  Wait Times  │ │
│  └──────────────────────────────┘  └──────────────────────────┘ │
│                                                                   │
│  Available Tiers ──────────────────────────────────────────────  │
│  ┌──────┐  ┌──────────┐  ┌──────┐  ┌──────┐  ┌──────┐         │
│  │Monthly│  │ Annual  ↑│  │Family│  │Biz   │  │Life  │         │  ← Tier Selector
│  │ $9.99 │  │ $59.99  ↑│  │$99.99│  │$149  │  │$299  │         │    (5 columns)
│  └──────┘  └──────────┘  └──────┘  └──────┘  └──────┘         │
│                                                                   │
├─────────────────────────────────────────────────────────────────┤
│  ✓ Verified 2 days ago  •  Next check in 5 days  •  Active 💻  │  ← Verification Footer (fixed)
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Dimensions

| Element | Value | Notes |
|---------|-------|-------|
| Screen max-width | Full-width (no center constraint) | Unlike upgrade screen's 720px cap |
| Content horizontal padding | 24px | `EdgeInsets.symmetric(horizontal: 24)` |
| Membership header border-radius | 12px (xl) | `BorderRadius.circular(12)` |
| Membership header padding | 48px all sides | `EdgeInsets.all(48)` — maps to design's `p-12` (12×4=48px) |
| Dashboard grid gap | 16px | Between left and right columns |
| Tier card border-radius | 12px | Same radius system-wide |
| Tier card padding | 16px | `EdgeInsets.all(16)` |
| Progress bar height | 6px | `h-1.5` in design tokens |
| Progress bar track color | `surface-container-lowest` (#0e0e0e) | |
| Verification footer height | 48px | Fixed at bottom, `h-12` |
| Left accent bar width | 4px | Absolute positioned, full height |
| VIP badge border-radius | 999px (full pill) | `BorderRadius.circular(999)` |
| VIP badge padding | h: 16px, v: 6px | `px-4 py-1.5` |
| Pulse dot size | 8×8px | `w-2 h-2` |

### 2.3 Spacing

| Between | Gap | Notes |
|---------|-----|-------|
| Membership header → Dashboard grid | 16px | `SizedBox(height: 16)` |
| Dashboard grid → Tier selector header | 24px | `SizedBox(height: 24)` |
| Tier selector header → Tier card row | 16px | `SizedBox(height: 16)` |
| VIP badge → Title | 16px | `SizedBox(height: 16)` |
| Title → Subtitle | 8px | `SizedBox(height: 8)` |
| Subscription card sections | 16px | Between logical groups |
| Usage insight label → progress bar | 6px | `SizedBox(height: 6)` |
| Progress bar → value label | 4px | `SizedBox(height: 4)` |
| Between progress bar groups | 12px | `SizedBox(height: 12)` |
| Stat boxes from progress section | 16px | `SizedBox(height: 16)` |

## 3. Token Extraction — Dark Mode (Nocturne Cinematic)

### 3.1 M3 Palette (Full)

| Token Name | Hex | Usage |
|------------|-----|-------|
| `surface` | `#131313` | Page background |
| `surface-container-low` | `#1c1b1b` | Membership header bg |
| `surface-container` | `#201f1f` | Mid-tier card backgrounds |
| `surface-container-high` | `#2a2a2a` | Subscription card, usage card bg |
| `surface-container-highest` | `#353534` | Active status badge bg |
| `surface-container-lowest` | `#0e0e0e` | Progress track, license key row, stat boxes |
| `on-surface` | `#e5e2e1` | Primary text |
| `on-surface-variant` | `#e1bebd` | Secondary text, subtitle |
| `primary` | `#ffb3b4` | Accent text, icons, progress fill, copy button |
| `primary-container` | `#8d0022` | Left accent bar, gradient progress fill end, active tier ring |
| `secondary-container` | `#910621` | VIP badge background |
| `on-secondary-container` | `#ff9899` | VIP badge text |
| `outline` | `#a88989` | Borders |
| `outline-variant` | `#594140` | Subtle borders, footer border |
| `inverse-primary` | `#ba1434` | Footer border top |
| `error` | `#ffb4ab` | "Deactivate License" hover color |

### 3.2 Flutter ColorScheme Mapping

```dart
// All values already present in existing Nocturne Cinematic M3 seed.
// No new color tokens needed — use colorScheme references directly.

colorScheme.surface                    // #131313
colorScheme.surfaceContainerLow        // #1c1b1b
colorScheme.surfaceContainer           // #201f1f
colorScheme.surfaceContainerHigh       // #2a2a2a
colorScheme.surfaceContainerHighest    // #353534
colorScheme.surfaceContainerLowest     // #0e0e0e  (verify token exists)
colorScheme.onSurface                  // #e5e2e1
colorScheme.onSurfaceVariant           // #e1bebd
colorScheme.primary                    // #ffb3b4
colorScheme.primaryContainer           // #8d0022
colorScheme.secondaryContainer         // #910621
colorScheme.onSecondaryContainer       // #ff9899
colorScheme.outline                    // #a88989
colorScheme.outlineVariant             // #594140
colorScheme.error                      // #ffb4ab
```

> Note: `surfaceContainerLowest` may need verification — check `AppColors` or theme generation. If absent, use `Color(0xFF0E0E0E)` directly with a `// TODO: replace with colorScheme.surfaceContainerLowest when token confirmed` comment.

### 3.3 Typography

| Element | Flutter Style | Size | Weight | Notes |
|---------|--------------|------|--------|-------|
| VIP badge text | `labelSmall` + override | 12px | bold | `letterSpacing: 0.5` |
| Membership title | `displaySmall` or custom | 36-48px equiv. | extrabold (800) | `letterSpacing: -0.04em` (tracking-tighter) |
| Membership subtitle | `titleMedium` | 16px | medium (500) | `colorScheme.onSurfaceVariant` |
| Card section label | `labelSmall` + override | 11px | bold (700) | `letterSpacing: 0.2em`, uppercase |
| Plan price ($59.99/yr) | `headlineMedium` | ~28px | bold (700) | |
| Active status badge | `labelSmall` | 11px | bold | |
| Detail key text | `labelSmall` | 11px | medium | uppercase, tracked |
| Detail value text | `bodySmall` | 12px | medium | |
| License key code | `labelSmall` mono | 10px | bold | `FontFeatures.tabularFigures()` |
| Usage card title | `titleLarge` | 22px | bold | |
| Progress label | `labelSmall` | 11px | medium | |
| Progress value | `labelSmall` | 11px | medium | Right-aligned |
| Stat value | `headlineSmall` | ~24px | bold | `colorScheme.primary` |
| Stat label | custom | 10px | bold | `letterSpacing: 0.1em`, uppercase |
| Tier card label | `labelSmall` | 11px | bold | uppercase, `letterSpacing: 0.1em` |
| Tier price | `titleLarge` | 22px | bold | |
| "Current Plan" badge | custom | 9px | black (900) | floating badge |
| Section header "Available Tiers" | `headlineSmall` | ~24px | bold | |
| Footer items | `labelSmall` | 12px | medium | |

### 3.4 Effects & Shadows

| Effect | Spec | Flutter Implementation |
|--------|------|----------------------|
| Membership header gradient | Right 1/3: `LinearGradient` from transparent → `primaryContainer` at 20% opacity | `BoxDecoration.gradient` or `ShaderMask` overlay |
| Title text glow (rose) | `text-shadow: 0 0 15px rgba(255,179,180,0.3)` | Not natively supported in Flutter text. Use `Stack` with blurred copy or `Paint` with `MaskFilter.blur`. See §5.3 |
| Annual tier card glow | `box-shadow: 0 0 30px rgba(141,2,31,0.15)` | `BoxDecoration.boxShadow` |
| Annual tier ring | `ring-1 ring-primary/40` | `Border.all(color: cs.primary.withValues(alpha: 0.4), width: 1)` |
| Verification footer blur | `backdrop-blur-md` + bg at 80% opacity | `BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12))` + `colorScheme.surfaceContainerLowest.withValues(alpha: 0.8)` |
| Pulse dot animation | CSS `animate-pulse` | `AnimationController` repeat + `Opacity` or `Transform.scale` oscillation |
| Left accent bar | `absolute w-1 h-full bg-primary-container` | `Positioned` inside `Stack`, fills card height |
| Toggle knob | `bg-primary` translated right when on | Custom toggle widget — `AnimatedContainer` with `Transform.translate` |

## 4. Gap Analysis — Design vs Current Code

### 4.1 MAJOR Changes

| # | Current | Design | Impact |
|---|---------|--------|--------|
| 1 | No header section — jumps straight to info rows | **Cinematic membership header** with gradient, VIP badge, crown icon, glow title | New widget `_MembershipHeader` |
| 2 | Simple info rows (label + value) in a single column | **12-column dashboard grid**: rich subscription card (7 cols) + usage insights card (5 cols) | Layout restructure |
| 3 | No usage stats of any kind | **Usage progress bars + stat boxes** (FUTURE data — hardcoded placeholder values) | New widget `_UsageInsightsCard` |
| 4 | No tier comparison | **5-column tier selector grid** with active indicator, floating badge, glow shadow | New widget `_TierSelectorGrid` |
| 5 | No verification status UI | **Fixed verification footer** with 3 items + backdrop blur | New widget `_VerificationFooter` |
| 6 | License key shown as info row (truncated) | **Dedicated license key row**: darker bg container, monospace code, inline copy button | Redesigned sub-widget |
| 7 | Auto-renewal as info row (text only) | **Custom toggle widget** with animated knob | New `_AutoRenewalToggle` widget |
| 8 | "Deactivate" as `TextButton.icon` | **Inline destructive link** styled with `cancel` icon, hover error color | Restyled |
| 9 | Full-width cancel button with error border | **Underlined text link** (xs, muted, below deactivate) | Simplified |
| 10 | `maxWidth: 720` centered layout | **Full-width layout** — no center constraint — left/right column layout fills available width | Container restructure |

### 4.2 KEEP (functional requirements not in design)

| # | Element | Why |
|---|---------|-----|
| 1 | `_confirmCancelSubscription()` dialog | Cancel flow is business-critical — keep logic, just change trigger widget |
| 2 | `_confirmDeactivate()` dialog | Deactivate flow same |
| 3 | `Clipboard.setData()` for license key copy | Core functional requirement |
| 4 | `ScaffoldMessenger` snackbar on copy | User feedback on action |
| 5 | `license.isCancelled` already-cancelled message | Important UX state — keep warning, restyle as orange info banner |
| 6 | `license.billingCycle?.isLifetime` guard | Don't show cancel for lifetime users |
| 7 | `_buildInfoRow()` for transaction ID + purchase date | Retain as secondary info below primary card, or move to expandable section |
| 8 | `license.isAutoRenew` state read | Drives toggle widget |

### 4.3 Usage Stats — FUTURE Placeholder Strategy

The design shows usage progress bars (Batch Downloads, AI Deep Searches, Cloud Storage) and two stat boxes (Efficiency, Wait Times). The backend currently does **not** track per-user consumption metrics.

**Implementation approach**:
- Render all UI components with hardcoded placeholder data
- Wrap each placeholder value in a clearly named constant: `const _kPlaceholderBatchUsed = 47`, etc.
- Add `// FUTURE(usage-tracking): Replace with real data from backend when analytics implemented` comment on each
- Do NOT create providers, API calls, or domain entities for usage tracking in this implementation pass

## 5. Widget Spec — Flutter Implementation

### 5.1 Widget Tree (target)

```dart
// Entry point in premium_upgrade_screen.dart — replaces _buildSubscriptionManagement()
// This method is conditionally shown when isActive == true

Widget _buildMembersLounge(BuildContext context, WidgetRef ref) {
  return Stack(
    children: [
      // Main scrollable content
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 60), // 60px bottom for footer
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Section 1: Membership Header
            _MembershipHeader(license: license),
            const SizedBox(height: 16),

            // Section 2: Dashboard Grid
            _DashboardGrid(license: license, ref: ref),
            const SizedBox(height: 24),

            // Section 3: Tier Selector
            _TierSelectorSection(currentCycle: license.billingCycle),
          ],
        ),
      ),

      // Section 4: Verification Footer (fixed at bottom)
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: _VerificationFooter(license: license),
      ),
    ],
  );
}
```

### 5.2 Component: `_MembershipHeader`

```dart
// Section 1 — Cinematic membership identity card
// bg: surfaceContainerLow, rounded-xl, p-12 (48px all), overflow hidden

Widget _MembershipHeader({required PremiumLicense license}) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;

  // Compute display strings from license
  final memberSince = license.purchaseDate != null
      ? _formatMonthYear(license.purchaseDate!)      // e.g. "October 2024"
      : 'Unknown';
  final planLabel = _cycleLabel(license.billingCycle); // e.g. "Annual Plan"

  return Container(
    padding: const EdgeInsets.all(48),
    decoration: BoxDecoration(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.hardEdge,
    child: Stack(
      children: [
        // Gradient overlay (right 1/3)
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: MediaQuery.of(context).size.width * 0.33,  // approximate right third
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [
                  cs.primaryContainer.withValues(alpha: 0.20),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Content
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // VIP Badge
            _VipBadge(),
            const SizedBox(height: 16),

            // Title row: crown icon + "SSvid Premium Member"
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Text glow title — see §5.3 for text glow technique
                _GlowText(
                  'SSvid Premium Member',
                  style: tt.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.04 * (tt.displaySmall?.fontSize ?? 36),
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.crown_rounded,          // verify icon name in flutter_material_icons
                  color: cs.primary,
                  size: 36,
                  // FILL=1 requires variable font support — use Icons.workspace_premium if unavailable
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Subtitle
            Text(
              'Member since $memberSince • $planLabel',
              style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
```

### 5.3 Component: `_VipBadge`

```dart
// VIP Access pill badge with animated pulse dot
Widget _VipBadge() {
  final cs = Theme.of(context).colorScheme;

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    decoration: BoxDecoration(
      color: cs.secondaryContainer,    // #910621
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'VIP Access',
          style: TextStyle(
            color: cs.onSecondaryContainer,  // #ff9899
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 8),
        // Pulse dot
        _PulseDot(),
      ],
    ),
  );
}

// Animated pulse dot (rose-400 ≈ #fb7185)
class _PulseDot extends StatefulWidget {
  @override
  State<_PulseDot> createState() => _PulseDotState();
}
class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _opacity = Tween(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFFfb7185),  // rose-400
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
```

### 5.4 Text Glow Technique — `_GlowText`

Flutter's `Text` widget does not support CSS `text-shadow`. Use a `Stack` with a blurred `Text` layer underneath:

```dart
// Approximates: text-shadow: 0 0 15px rgba(255,179,180,0.3)
class _GlowText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const _GlowText(this.text, {this.style});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Glow layer: blurred, rose-tinted
        Text(
          text,
          style: style?.copyWith(
            foreground: Paint()
              ..color = const Color(0xFFffb3b4).withValues(alpha: 0.3)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
          ),
        ),
        // Actual text on top
        Text(text, style: style),
      ],
    );
  }
}
```

> Alternative: If `Stack` glow causes layout issues (width mismatch), wrap in `RepaintBoundary` or use `CustomPainter` for both layers in one pass.

### 5.5 Component: `_DashboardGrid`

```dart
// Two-column dashboard layout using Row + Expanded with flex weights
Widget _DashboardGrid({required PremiumLicense license, required WidgetRef ref}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Left: subscription detail card (7/12 → flex 7)
      Expanded(
        flex: 7,
        child: _SubscriptionDetailCard(license: license, ref: ref),
      ),
      const SizedBox(width: 16),
      // Right: usage insights card (5/12 → flex 5)
      Expanded(
        flex: 5,
        child: _UsageInsightsCard(),
      ),
    ],
  );
}
```

### 5.6 Component: `_SubscriptionDetailCard`

```dart
// Left column — subscription details with left accent bar
Widget _SubscriptionDetailCard({required PremiumLicense license, required WidgetRef ref}) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;

  return Container(
    decoration: BoxDecoration(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.hardEdge,
    child: Stack(
      children: [
        // Left accent bar
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 4,
          child: ColoredBox(color: cs.primaryContainer),
        ),

        // Card content (offset from accent bar)
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 24, 24), // 28 = 4 bar + 24 padding
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Header: "Current Plan" label + price + status badge ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CURRENT PLAN',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                            letterSpacing: 0.2 * 11,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '\$59.99/year',    // FUTURE: derive from license.billingCycle + pricing
                          style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  // Active Status badge
                  _ActiveStatusBadge(),
                ],
              ),
              const SizedBox(height: 16),

              // ── Detail grid (2 columns) ──
              Row(
                children: [
                  Expanded(child: _DetailCell(
                    label: 'Next Billing Date',
                    value: license.expiresAt != null ? _formatDate(license.expiresAt!) : '—',
                  )),
                  const SizedBox(width: 16),
                  Expanded(child: _DetailCell(
                    label: 'Payment Method',
                    icon: Icons.credit_card_rounded,
                    value: _paymentMethodLabel(license.paymentMethod),  // e.g. "Visa 4242"
                  )),
                ],
              ),
              const SizedBox(height: 16),

              // ── License key row ──
              _LicenseKeyRow(licenseKey: license.licenseKey),
              const SizedBox(height: 16),

              // ── Auto-renewal toggle ──
              _AutoRenewalToggle(isEnabled: license.isAutoRenew),
              const SizedBox(height: 16),

              // ── Update Payment outlined button ──
              OutlinedButton(
                onPressed: null,  // FUTURE: payment method update flow
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.30),
                  ),
                  foregroundColor: cs.primary,
                ),
                child: const Text('Update Payment'),
              ),
              const SizedBox(height: 16),

              // ── Destructive links ──
              Row(
                children: [
                  // Deactivate License
                  InkWell(
                    onTap: () => _confirmDeactivate(context, ref),
                    borderRadius: BorderRadius.circular(4),
                    hoverColor: cs.error.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cancel_outlined, size: 14, color: cs.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            'Deactivate License',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Cancel Subscription (if applicable)
                  if (!license.isCancelled && !(license.billingCycle?.isLifetime ?? false))
                    InkWell(
                      onTap: () => _confirmCancelSubscription(context, ref),
                      child: Text(
                        'Cancel Subscription',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.4),
                          decoration: TextDecoration.underline,
                          decorationColor: cs.onSurface.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                ],
              ),

              // Already cancelled warning
              if (license.isCancelled) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          AppLocalizations.premiumCancelledInfo,
                          style: tt.bodySmall?.copyWith(color: Colors.orange.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
```

### 5.7 Sub-components: Status Badge, Detail Cell, License Key Row, Toggle

```dart
// Active status indicator badge
Widget _ActiveStatusBadge() {
  final cs = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: Color(0xFF4ade80),  // green-400
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'Active',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF4ade80),
          ),
        ),
      ],
    ),
  );
}

// Label + value pair (used in 2-col detail grid)
class _DetailCell extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  const _DetailCell({required this.label, required this.value, this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1 * 10,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: cs.onSurface),
              const SizedBox(width: 4),
            ],
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// License key display row with copy button
Widget _LicenseKeyRow({String? licenseKey}) {
  final cs = Theme.of(context).colorScheme;

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: cs.surfaceContainerLowest,   // #0e0e0e
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MASTER LICENSE KEY',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1 * 10,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                licenseKey ?? '—',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (licenseKey != null)
              IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: licenseKey));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppLocalizations.premiumCryptoAddressCopied),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                icon: Icon(Icons.copy_all_rounded, size: 16, color: cs.primary),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Copy license key',
              ),
          ],
        ),
      ],
    ),
  );
}

// Auto-renewal toggle
Widget _AutoRenewalToggle({required bool isEnabled}) {
  final cs = Theme.of(context).colorScheme;

  return Row(
    children: [
      // Custom toggle (48×24 target area, 36×18 visual)
      GestureDetector(
        onTap: null,  // FUTURE: toggle auto-renewal via API
        child: Container(
          width: 36,
          height: 20,
          decoration: BoxDecoration(
            color: isEnabled
                ? cs.primaryContainer.withValues(alpha: 0.4)
                : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.all(2),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: isEnabled ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: isEnabled ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Text(
        isEnabled ? 'Auto-renewal enabled' : 'Auto-renewal disabled',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: cs.onSurface,
        ),
      ),
    ],
  );
}
```

### 5.8 Component: `_UsageInsightsCard`

```dart
// Right column — cosmetic usage stats (FUTURE: replace placeholders with real data)
// IMPORTANT: All values below are hardcoded placeholders.
// FUTURE(usage-tracking): Connect to backend analytics when per-user tracking is implemented.
const _kPlaceholderBatchUsed = 47;
const _kPlaceholderBatchMax = 100;
const _kPlaceholderAiUsed = 12;
const _kPlaceholderAiMax = 50;
const _kPlaceholderStorageGb = 3.2;
const _kPlaceholderStorageMaxGb = 10.0;
const _kPlaceholderEfficiency = 84;
const _kPlaceholderWaitTimes = 0;

Widget _UsageInsightsCard() {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;

  return Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Text(
              'Your Premium Usage',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Icon(Icons.insights_rounded, size: 20, color: cs.onSurfaceVariant),
          ],
        ),
        const SizedBox(height: 20),

        // Progress bar: Batch Downloads
        _UsageProgressBar(
          label: 'Batch Downloads',
          used: _kPlaceholderBatchUsed,
          max: _kPlaceholderBatchMax,
          valueLabel: '$_kPlaceholderBatchUsed/$_kPlaceholderBatchMax',
          fillColor: cs.primary,
        ),
        const SizedBox(height: 12),

        // Progress bar: AI Deep Searches
        _UsageProgressBar(
          label: 'AI Deep Searches',
          used: _kPlaceholderAiUsed,
          max: _kPlaceholderAiMax,
          valueLabel: '$_kPlaceholderAiUsed/$_kPlaceholderAiMax',
          fillColor: cs.primaryContainer,
        ),
        const SizedBox(height: 12),

        // Progress bar: Cloud Backup Storage (gradient)
        _UsageProgressBar(
          label: 'Cloud Backup Storage',
          used: (_kPlaceholderStorageGb * 10).toInt(),
          max: (_kPlaceholderStorageMaxGb * 10).toInt(),
          valueLabel: '${_kPlaceholderStorageGb}GB/${_kPlaceholderStorageMaxGb}GB',
          gradientColors: [cs.primaryContainer, cs.primary],
        ),
        const SizedBox(height: 16),

        // Stat boxes (2 columns)
        Row(
          children: [
            Expanded(child: _StatBox(
              value: '$_kPlaceholderEfficiency%',
              label: 'Efficiency',
            )),
            const SizedBox(width: 12),
            Expanded(child: _StatBox(
              value: '$_kPlaceholderWaitTimes',
              label: 'Wait Times',
            )),
          ],
        ),
      ],
    ),
  );
}

// Single horizontal progress bar with label + value
class _UsageProgressBar extends StatelessWidget {
  final String label;
  final int used;
  final int max;
  final String valueLabel;
  final Color? fillColor;
  final List<Color>? gradientColors;
  const _UsageProgressBar({
    required this.label,
    required this.used,
    required this.max,
    required this.valueLabel,
    this.fillColor,
    this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fraction = max > 0 ? (used / max).clamp(0.0, 1.0) : 0.0;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            Text(valueLabel, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 6,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: FractionallySizedBox(
            widthFactor: fraction,
            alignment: Alignment.centerLeft,
            child: Container(
              decoration: BoxDecoration(
                color: gradientColors == null ? fillColor : null,
                gradient: gradientColors != null
                    ? LinearGradient(colors: gradientColors!)
                    : null,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Single stat display box
class _StatBox extends StatelessWidget {
  final String value;
  final String label;
  const _StatBox({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1 * 10,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
```

### 5.9 Component: `_TierSelectorSection`

```dart
// Section 3 — Tier comparison grid
// Tiers are hardcoded display-only — changing tier is not supported in v1.
// FUTURE(tier-switch): Add tier upgrade/downgrade flow when billing supports mid-cycle changes.
Widget _TierSelectorSection({String? currentCycle}) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;

  const tiers = [
    _TierData(label: 'Monthly',  price: '\$9.99',   cycle: 'monthly',  suffix: '/mo'),
    _TierData(label: 'Annual',   price: '\$59.99',  cycle: 'annual',   suffix: '/yr'),
    _TierData(label: 'Family',   price: '\$99.99',  cycle: 'family',   suffix: '/yr'),
    _TierData(label: 'Business', price: '\$149.99', cycle: 'business', suffix: '/yr'),
    _TierData(label: 'Lifetime', price: '\$299.99', cycle: 'lifetime', suffix: ''),
  ];

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Header + divider
      Row(
        children: [
          Text(
            'Available Tiers',
            style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cs.primaryContainer.withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),

      // 5-column tier grid
      Row(
        children: tiers.map((tier) {
          final isCurrent = tier.cycle == (currentCycle ?? 'annual');
          final isLifetime = tier.cycle == 'lifetime';
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: tiers.last == tier ? 0 : 12,
              ),
              child: _TierCard(
                tier: tier,
                isCurrent: isCurrent,
                isLifetime: isLifetime,
              ),
            ),
          );
        }).toList(),
      ),
    ],
  );
}

// Tier data record
class _TierData {
  final String label;
  final String price;
  final String cycle;
  final String suffix;
  const _TierData({
    required this.label,
    required this.price,
    required this.cycle,
    required this.suffix,
  });
}

// Individual tier card
class _TierCard extends StatelessWidget {
  final _TierData tier;
  final bool isCurrent;
  final bool isLifetime;
  const _TierCard({
    required this.tier,
    required this.isCurrent,
    required this.isLifetime,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Card body
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isCurrent
                ? cs.surfaceContainerHigh
                : cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isCurrent
                  ? cs.primary.withValues(alpha: 0.4)
                  : isLifetime
                      ? cs.primary.withValues(alpha: 0.05)
                      : Colors.transparent,
              width: 1,
            ),
            boxShadow: isCurrent
                ? [
                    BoxShadow(
                      color: const Color(0xFF8D021F).withValues(alpha: 0.15),
                      blurRadius: 30,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tier.label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1 * 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: tier.price,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isLifetime ? cs.primary : cs.onSurface,
                      ),
                    ),
                    if (tier.suffix.isNotEmpty)
                      TextSpan(
                        text: tier.suffix,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // "Current Plan" floating badge (above card, centered)
        if (isCurrent)
          Positioned(
            top: -10,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Current Plan',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFffb3b4),  // primary
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
```

### 5.10 Component: `_VerificationFooter`

```dart
// Fixed bottom bar — license verification status
// Uses BackdropFilter for glassmorphism effect
Widget _VerificationFooter({required PremiumLicense license}) {
  final cs = Theme.of(context).colorScheme;

  // FUTURE(verification-tracking): Derive actual last-verified and next-check
  // dates from license metadata when backend exposes verification timestamps.
  const _kLastVerifiedLabel = 'Verified 2 days ago';
  const _kNextCheckLabel = 'Next check in 5 days';
  const _kActiveLabel = 'License is active and authorized for this device.';

  return ClipRect(
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest.withValues(alpha: 0.8),
          border: Border(
            top: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.10),
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _FooterItem(
              icon: Icons.verified_rounded,   // FILL=1 variant preferred
              label: _kLastVerifiedLabel,
              iconColor: cs.primary,
            ),
            _FooterSeparator(),
            _FooterItem(
              icon: Icons.schedule_rounded,
              label: _kNextCheckLabel,
            ),
            _FooterSeparator(),
            _FooterItem(
              icon: Icons.laptop_mac_rounded,
              label: _kActiveLabel,
              iconColor: cs.primary,
            ),
          ],
        ),
      ),
    ),
  );
}

// Footer item: icon + label
class _FooterItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;
  const _FooterItem({required this.icon, required this.label, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor ?? cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

// Separator dot between footer items
class _FooterSeparator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(
          color: cs.onSurfaceVariant.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
```

> Import required: `import 'dart:ui' as ui;` for `ui.ImageFilter.blur`.

## 6. State Flow

### 6.1 States

The Member's Lounge is shown only when `license.isActiveSubscription == true`. It does not have its own loading state — it reads from the same `premiumLicenseProvider` already consumed by the upgrade screen.

```
[isActive == false] → Premium Upgrade Screen (existing flow)
[isActive == true]  → Member's Lounge (this screen)
```

### 6.2 Conditional Rendering Matrix

| Condition | Element affected |
|-----------|-----------------|
| `license.isCancelled == true` | Hide "Cancel Subscription" link; show orange warning banner |
| `license.billingCycle?.isLifetime == true` | Hide "Cancel Subscription" link entirely |
| `license.licenseKey == null` | License key shows `—`, copy button hidden |
| `license.expiresAt == null` | "Next Billing Date" shows `—` |
| `license.paymentMethod == null` | Payment Method shows `—`, no credit_card icon |
| `license.isAutoRenew == false` | Toggle rendered in off state |
| Current billing cycle matches tier card | That tier card shows current-plan styling + badge |

### 6.3 Current Plan Badge — Cycle Matching

Map `license.billingCycle` string to tier `cycle` field:

| `license.billingCycle` | Matches tier |
|------------------------|-------------|
| `'monthly'` | Monthly |
| `'annual'` or `'yearly'` | Annual |
| `'family'` | Family |
| `'business'` | Business |
| `'lifetime'` | Lifetime |
| `null` (unknown) | Annual (design default) |

## 7. Token Changes Required

### 7.1 No new tokens needed

All colors map to existing M3 ColorScheme roles already generated from the Nocturne Cinematic seed. No additions to `app_colors.dart` required for this screen.

### 7.2 Verify `surfaceContainerLowest` availability

```dart
// Check: does colorScheme expose surfaceContainerLowest?
// If not, use direct hex until token is added:
final lowestSurface = cs.surfaceContainerLowest;  // may throw — verify
// Fallback: const Color(0xFF0E0E0E)
```

### 7.3 Import additions for this file

```dart
import 'dart:ui' as ui;              // for ImageFilter.blur (verification footer)
import 'dart:ui' show FontFeature;  // for FontFeature.tabularFigures (license key)
```

## 8. Platform Considerations

### 8.1 macOS

- The `_VerificationFooter` is `Positioned` at bottom of the lounge Stack. It sits above the bottom edge of the `Scaffold` body, NOT floating over the macOS dock or system bar.
- Window resize: Left/right columns will compress at narrow widths. Add minimum column widths:
  - Left col: `minWidth: 320px` via `ConstrainedBox`
  - Right col: `minWidth: 240px` via `ConstrainedBox`
  - Below ~640px total width: stack vertically (use `LayoutBuilder` breakpoint)
- `BackdropFilter` in footer: works correctly on macOS — no known Flutter issues on this platform.

### 8.2 Windows

- `BackdropFilter` has known performance concerns on Windows with certain GPU drivers. If jank is observed: remove blur and use opaque `surfaceContainerLowest` bg instead.
- `Icons.laptop_mac_rounded` in footer → use `Icons.laptop_rounded` on Windows for semantic accuracy.
- Text glow (`_GlowText` with `MaskFilter.blur`) renders correctly on Windows.

### 8.3 Linux

- Same considerations as Windows for `BackdropFilter`.
- All other components platform-agnostic.

### 8.4 Responsive Breakpoints

```dart
// In _DashboardGrid (§5.5):
LayoutBuilder(
  builder: (context, constraints) {
    if (constraints.maxWidth < 640) {
      // Vertical stack
      return Column(children: [
        _SubscriptionDetailCard(...),
        const SizedBox(height: 16),
        _UsageInsightsCard(),
      ]);
    }
    // Horizontal split (default)
    return Row(...);
  },
)
```

## 9. Animation Spec

| Animation | Duration | Curve | Notes |
|-----------|----------|-------|-------|
| VIP badge pulse dot | 1000ms, repeat reverse | `Curves.easeInOut` | `AnimationController` in `_PulseDotState` |
| Auto-renewal toggle knob | 200ms | `Curves.easeInOut` | `AnimatedAlign` |
| Membership header entrance | 300ms fade-in | `Curves.easeOut` | Animate on first build; trigger from `initState` |
| Tier card hover highlight | 150ms | `Curves.easeInOut` | `AnimatedContainer` color switch |
| License key copy feedback | SnackBar (existing) | — | No animation change needed |

## 10. Verification Checklist

- [ ] Membership header renders with gradient overlay visible on right third
- [ ] VIP badge shows correct bg (#910621), text (#ff9899), pulse dot animates
- [ ] Crown/premium icon renders at correct size + primary color
- [ ] Title text glow effect visible (subtle rose bloom behind text)
- [ ] Left accent bar visible on subscription card (4px, primaryContainer color)
- [ ] "Current Plan" label + price render correctly
- [ ] Active status badge: green dot + "Active" text
- [ ] Next billing date + payment method populate from license data (or `—`)
- [ ] License key row: darker bg, monospace text, copy button functional
- [ ] Copy triggers SnackBar confirmation
- [ ] Auto-renewal toggle: animated knob matches license.isAutoRenew state
- [ ] "Update Payment" button renders (disabled — FUTURE)
- [ ] "Deactivate License" link triggers existing `_confirmDeactivate()` dialog
- [ ] "Cancel Subscription" link hidden for lifetime + already-cancelled users
- [ ] "Cancel Subscription" link triggers existing `_confirmCancelSubscription()` dialog
- [ ] Already-cancelled orange banner shows when `license.isCancelled == true`
- [ ] Usage progress bars render with placeholder values
- [ ] Progress bar fills respect color assignments (primary / primaryContainer / gradient)
- [ ] Stat boxes: correct values, centered, surfaceContainerLowest bg
- [ ] Tier selector: 5 cards in single row
- [ ] Annual tier card: ring border, box-shadow glow, "Current Plan" floating badge
- [ ] "Current Plan" badge positioned correctly (-10px top)
- [ ] Tier matching: badge appears on card matching `license.billingCycle`
- [ ] Lifetime tier price text in `primary` color
- [ ] Verification footer: fixed at bottom, 48px height
- [ ] Footer backdrop blur renders (or falls back gracefully on slow GPU)
- [ ] Footer shows 3 items with separator dots
- [ ] `flutter analyze` passes with 0 issues on the premium screen file
- [ ] No regression in the upgrade path (non-active user view unchanged)
- [ ] Layout stacks vertically below 640px width (LayoutBuilder breakpoint)
- [ ] All FUTURE placeholder constants are commented and named with `_kPlaceholder` prefix
