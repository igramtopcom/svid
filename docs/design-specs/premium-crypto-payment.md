# Premium — Crypto Payment Modal — Design Spec

> Source: Stitch project `9746799973876268727`
> Screen: `5a9661b3f6bb46b38d736d10f003e013`
> Status: DRAFT
> Current code: `lib/features/premium/data/services/crypto_payment_service.dart`,
>               `lib/features/premium/presentation/providers/payment_providers.dart`,
>               `lib/features/premium/presentation/screens/premium_upgrade_screen.dart`

## 1. Design Intent

**Purpose**: Full-screen modal overlay shown when the user selects a crypto payment method on the Premium Upgrade screen. Covers the entire app with a blurred, darkened dashboard behind a cinematic two-column glass panel.

**Mood**: Nocturne Cinematic — dark luxury, intentional, like a high-security vault interface. Not a checkout form. An experience that makes crypto feel trustworthy and premium.

**Key principle**: The modal is self-contained. The user never leaves the app. Left column = selection + context. Right column = action (scan or copy + wait). These two halves never compete — they complement.

## 2. Visual Structure

### 2.1 Layout

```
┌────────────────────────────────────────────────────────────────────────────────┐
│  [blurred, darkened dashboard — nav bar + content grid visible through haze]   │
│                                                                                │
│  ┌──────────────────────────────────────────────────────────────────────────┐  │
│  │  LEFT COLUMN (flex-1, p-10)         │  RIGHT COLUMN (w=400px, p-10)     │  │
│  │                                     │                                   │  │
│  │  [★] PREMIUM ACTIVATION             │  ○── Invoice expires in 14:32 ──  │  │
│  │      Annual Plan                    │                                   │  │
│  │      0.00082 BTC                    │  ┌─────────────────────────────┐  │  │
│  │      $59.99 USD                     │  │                             │  │  │
│  │                                     │  │     ▓▓▓▓ QR CODE ▓▓▓▓      │  │  │
│  │  SELECT NETWORK                     │  │       192 × 192 px          │  │  │
│  │  ┌───────────────────────────────┐  │  │    (glow on hover)          │  │  │
│  │  │ ✓  Bitcoin      BTC   [glow] │  │  │                             │  │  │
│  │  └───────────────────────────────┘  │  └─────────────────────────────┘  │  │
│  │  ┌───────────────────────────────┐  │                                   │  │
│  │  │    Litecoin     LTC          │  │  WALLET ADDRESS                   │  │
│  │  └───────────────────────────────┘  │  bc1q…xk7r2                      │  │
│  │  ┌───────────────────────────────┐  │                                   │  │
│  │  │    Monero       XMR          │  │  [  COPY WALLET ADDRESS  ]        │  │
│  │  └───────────────────────────────┘  │                                   │  │
│  │                                     │  ┌ ─── heartbeat tracker ────┐   │  │
│  │  ┊ "Your transaction is              │  │  ◎ Waiting for payment...  │   │  │
│  │  ┊  processed on the blockchain..."  │  │     Status: Mempool Scan   │   │  │
│  │                                     │  └────────────────────────────┘   │  │
│  └──────────────────────────────────────────────────────────────────────────┘  │
│                                                                           [✕]  │
└────────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Dimensions

| Element | Value | Notes |
|---------|-------|-------|
| Outer backdrop | Full screen | `Stack` over entire `Scaffold` body |
| Backdrop blur | `ImageFilter.blur(sigmaX: 12, sigmaY: 12)` | `BackdropFilter` wrapping `ColoredBox` |
| Backdrop tint | `Colors.black.withValues(alpha: 0.5)` | Darkens dashboard beneath |
| Modal container | max-width 896px (`maxWidth: 4xl`) | Center-aligned, 720px height |
| Modal bg | `rgba(14,14,14,0.85)` + `blur(24px)` | Glass panel — see Section 3.4 |
| Modal radius | 16px | `BorderRadius.circular(16)` |
| Modal shadow | 24px blur, 0px Y, `#8D0022` @ 8% | `BoxShadow` with `blurRadius: 24` |
| Left column padding | 40px all sides | |
| Right column width | 400px fixed | |
| Right column bg | `surface-container-low` (`#1C1B1B`) | Subtle separation from left |
| Divider | `border-r` 1px `outline-variant/10` | `VerticalDivider` or `Container` |
| Close button | 24×24px icon, top-right corner | `Icons.close`, `on-surface-variant` |
| Network radio card height | 64px | Fixed row height |
| QR container | 192×192px | Square, white bg, glow border |
| Heartbeat tracker | 64×64px | Double circle + icon |

### 2.3 Spacing

| Between | Gap | Token |
|---------|-----|-------|
| Header icon → "PREMIUM ACTIVATION" label | 12px | `AppSpacing.md` |
| Label → Plan title | 4px | Custom |
| Plan title → Price (crypto) | 6px | Custom |
| Price (crypto) → Price (USD) | 2px | Custom |
| Header block → Network selector label | 32px | `AppSpacing.xl` |
| Network selector label → First card | 8px | `AppSpacing.sm` |
| Between network cards | 8px | `AppSpacing.sm` |
| Network cards → Status quote | 24px | `AppSpacing.lg` |
| Countdown row → QR container | 24px | `AppSpacing.lg` |
| QR container → Address block | 16px | `AppSpacing.md` |
| Address block → Copy button | 12px | Custom |
| Copy button → Heartbeat tracker | 20px | Custom |

## 3. Token Extraction

### 3.1 M3 Color Palette (Nocturne Cinematic — Dark)

| Token name | Hex | Usage |
|------------|-----|-------|
| `surface-container-lowest` | `#0E0E0E` | Modal glass bg base, wallet address bg |
| `surface` | `#131313` | — |
| `surface-container-low` | `#1C1B1B` | Right column bg |
| `surface-container` | `#201F1F` | Countdown chip bg |
| `surface-container-high` | `#2A2A2A` | Unselected network card bg |
| `surface-container-highest` | `#353534` | — |
| `surface-bright` | `#3A3939` | — |
| `primary` | `#FFB3B4` | Active network card check icon, spinner border, heartbeat icon |
| `primary-container` | `#8D0022` | Status quote accent border |
| `secondary` | `#FFB2BC` | Header icon tint, "PREMIUM ACTIVATION" label |
| `tertiary-container` | `#8D021F` | Selected network card bg tint, copy button gradient start |
| `outline` | `#A88989` | Network selector label |
| `outline-variant` | `#594140` | Modal divider, countdown chip border, wallet address border |
| `inverse-primary` | `#BA1434` | Copy button gradient end |
| `on-surface` | `#E5E2E1` | Primary text (plan name, address code) |
| `on-surface-variant` | `#E1BEBD` | Secondary text (USD price, confirmation details) |

Flutter mapping: all tokens above are already defined via `colorScheme` from the app's dark theme seed. No new `AppColors` constants required beyond those introduced in first-time-setup.md (`accentHighlight = #C41E3A`).

### 3.2 Network Card States

| State | Background | Border | Shadow |
|-------|-----------|--------|--------|
| Selected (BTC) | `tertiary-container.withValues(alpha: 0.20)` = `#8D021F` @ 20% | `tertiary-container.withValues(alpha: 0.30)` | `glow-red`: `0 0 40px -10px rgba(141,2,31,0.4)` |
| Unselected | `surface-container-high.withValues(alpha: 0.40)` | `Colors.transparent` | none |
| Hover (unselected) | `surface-container-high.withValues(alpha: 0.60)` | `outline-variant` @ 20% | none |

### 3.3 Typography

| Element | Size | Weight | Tracking | Flutter mapping |
|---------|------|--------|----------|-----------------|
| "PREMIUM ACTIVATION" label | 12px | 600 | 0.15em | `labelMedium` + `letterSpacing: 1.8, fontWeight: w600` |
| "Annual Plan" title | 36px | 600 | tight (−0.02em) | `displaySmall` or `headlineLarge` with custom size |
| Crypto amount ("0.00082 BTC") | 24px | 300 | normal | `headlineSmall` + `fontWeight: w300, color: primary` |
| USD price ("$59.99 USD") | 14px | 500 | normal | `labelLarge` + `color: on-surface-variant` |
| "SELECT NETWORK" label | 10px | 600 | widest (0.3em) | `labelSmall` + `letterSpacing: 3.0, fontWeight: w600` |
| Network card: currency name | 14px | 700 | normal | `titleSmall` + `fontWeight: w700` |
| Network card: detail text | 12px | 400 | normal | `bodySmall` + `color: on-surface-variant` |
| Status quote | 12px | 400 | normal | `bodySmall` + `fontStyle: italic` |
| Countdown timer | 12px | 400 | normal | `labelSmall` + `fontFamily: monospace` |
| "WALLET ADDRESS" label | 10px | 600 | 0.3em | `labelSmall` + `letterSpacing: 3.0` |
| Wallet address code | 12px | 400 | normal | `bodySmall` + `fontFamily: monospace` |
| Copy button | 12px | 700 | 0.2em uppercase | `labelSmall` + `letterSpacing: 2.0, fontWeight: w700` |
| "Waiting for payment..." | 12px | 400 | normal | `labelSmall` |
| "Status: Mempool Scanning" | 10px | 400 | 0.1em | `labelSmall` + `color: on-surface-variant` |

### 3.4 Effects

| Effect | Value | Flutter implementation |
|--------|-------|----------------------|
| Backdrop blur | `blur(12px)` at 50% brightness | `BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12))` over `ColoredBox(color: Colors.black54)` |
| Glass panel bg | `rgba(14,14,14,0.85)` + `blur(24px)` | `ClipRRect` + `BackdropFilter(blur: sigmaX: 24, sigmaY: 24)` + `Container(color: Color(0xD90E0E0E))` |
| Modal shadow | `0 24px 24px rgba(141,0,34,0.08)` | `BoxShadow(color: Color(0x148D0022), blurRadius: 24, offset: Offset(0, 24))` |
| glow-red (selected card) | `0 0 40px -10px rgba(141,2,31,0.4)` | `BoxShadow(color: Color(0x668D021F), blurRadius: 40, spreadRadius: -10)` |
| scannable-glow (QR border) | `inset 0 0 20px rgba(141,2,31,0.2)` | Inner `Container` with `BoxShadow` — simulate with `DecoratedBox` + gradient overlay |
| QR hover glow | bg-primary/10 `blur(32px)` scale | `AnimatedContainer` with `Transform.scale` + translucent `BoxDecoration` background |
| Countdown spinner | `border-2 primary, animate-spin` | `SizedBox` + `CircularProgressIndicator(strokeWidth: 2, color: primary)` |
| Heartbeat outer ring | `primary/20`, full border | `Container` with `BoxDecoration(shape: circle, border: Border.all(...))` |
| Heartbeat inner ring | `primary`, `animate-spin` partial | `CircularProgressIndicator` at reduced `value: null` (indeterminate), small size |
| Heartbeat pulse icon | `monitor_heart FILL 1`, pulse | `AnimationController` → `ScaleTransition` 0.9–1.0, 1s repeat |
| Copy button gradient | `#8D021F → #BA1434` left-to-right | `LinearGradient(colors: [Color(0xFF8D021F), Color(0xFFBA1434)])` |

## 4. Gap Analysis — Design vs Current Code

### 4.1 MAJOR Changes (new UI layer, not in current code)

| # | Current | Design | Impact |
|---|---------|--------|--------|
| 1 | No dedicated crypto modal widget exists — premium screen has inline state handling | New: `CryptoPaymentModal` — full-screen `Stack` overlay with two-column glass panel | New widget file |
| 2 | Network selection is a simple dropdown or button list (not radio cards) | Network radio cards: bg tint + glow on selected, smooth animated selection | New `_NetworkCard` component |
| 3 | QR code shown inline with no visual treatment | QR in styled white container, `scannable-glow` inset shadow, hover scale + glow | New `_QrContainer` component |
| 4 | No countdown timer — expiry tracked in `CryptoInvoice.timeRemaining` but not displayed | Countdown pill: spinner + "Invoice expires in MM:SS" monospace, updates every second | New `_CountdownChip` + `Timer.periodic` |
| 5 | Polling indicated by `PaymentState.isLoading` bool only | Heartbeat tracker: double concentric circles, animated inner ring, pulsing icon, status text | New `_HeartbeatTracker` component |
| 6 | No status quote / atmospheric copy | Left column footer: italic quote with `primary-container` left border accent | New `_StatusQuote` widget |
| 7 | Dashboard visible during crypto wait (no modal overlay) | Blurred + darkened full-screen backdrop — actual app content shows through | `BackdropFilter` + `Stack` in `Overlay` or modal route |
| 8 | Copy address: not shown as dedicated styled button | Full-width gradient "COPY WALLET ADDRESS" button with `Clipboard.setData` | New `_CopyAddressButton` |

### 4.2 KEEP (functional, do not change)

| # | Element | Reason |
|---|---------|--------|
| 1 | `CryptoPaymentService.createInvoice()` | Data layer unchanged — modal calls the same method |
| 2 | `CryptoPaymentService.pollForConfirmation()` | Polling logic unchanged — heartbeat is purely UI on top of existing poll |
| 3 | `PaymentNotifier.startCryptoCheckout()` | State machine unchanged — modal observes `paymentProvider` |
| 4 | `CryptoInvoice` entity (`invoiceId`, `address`, `paymentUri`, `expiresAt`, `amount`, `currency`) | All fields drive the new UI directly |
| 5 | `CryptoCurrency` enum with 3 variants (BTC/LTC/XMR), `requiredConfirmations`, `displayName` | Drives network selector card content and status text |
| 6 | `PaymentState.invoice` / `PaymentState.result` / `PaymentState.error` | Modal reads these via `ref.watch(paymentProvider)` |
| 7 | `PaymentState.activationError` / `pendingLicenseKey` retry path | Unchanged — activation error dialog fires after modal completes |
| 8 | `PaymentNotifier.reset()` | Called on close/cancel to allow fresh attempt |

### 4.3 UX Decision: Currency Pre-selection

**Design shows**: BTC pre-selected when modal opens.
**Current code**: `startCryptoCheckout(currency, billingCycle)` is called immediately — invoice created at the moment of trigger.

**Recommended approach — Lazy Invoice Creation**:
- Modal opens with BTC selected (no invoice yet)
- User confirms selection → taps "Generate Invoice" → invoice created
- OR: Treat the radio card tap as immediate invoice creation, cancel + recreate on switch
- Simplest: add a local `selectedCurrency` `StateProvider` inside the modal; user picks currency, then taps "Pay with [CURRENCY]" to trigger `startCryptoCheckout`
- This avoids creating/abandoning invoices on every card tap

**Alternative (match existing flow exactly)**:
- Pass currency from the calling screen before opening modal
- Modal opens already in `isLoading` state creating the invoice
- Network selector becomes display-only (already chosen)
- If user wants different currency, close and reopen

Recommendation: **Lazy approach** — aligns with the design's interactive selector.

## 5. Widget Spec — Flutter Implementation

### 5.1 Widget Tree (target)

```dart
// Entry point: overlay shown from PremiumUpgradeScreen
// Navigator.of(context).push(
//   PageRouteBuilder(
//     opaque: false,
//     barrierColor: Colors.transparent,
//     pageBuilder: (_, __, ___) => CryptoPaymentModal(billingCycle: billingCycle),
//   )
// );

class CryptoPaymentModal extends ConsumerStatefulWidget {
  final BillingCycle billingCycle;
  const CryptoPaymentModal({required this.billingCycle, super.key});
}

// Widget tree inside _CryptoPaymentModalState.build():
Stack(
  children: [
    // Layer 0: Blurred backdrop (actual app content)
    Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: ColoredBox(color: Colors.black.withValues(alpha: 0.5)),
      ),
    ),

    // Layer 1: Modal glass panel (centered)
    Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 896, maxHeight: 720),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xD90E0E0E),  // 0.85 opacity
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left column
                  Expanded(child: _LeftColumn(...)),

                  // Divider
                  VerticalDivider(
                    width: 1,
                    color: Color(0xFF594140).withValues(alpha: 0.10),
                  ),

                  // Right column
                  SizedBox(
                    width: 400,
                    child: _RightColumn(...),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),

    // Layer 2: Close button (absolute top-right of modal)
    Positioned(
      top: ...,  // calculated: (screenH - modalH) / 2 + 24
      right: ...,
      child: _CloseButton(onClose: _handleClose),
    ),
  ],
)
```

### 5.2 Component: `_LeftColumn`

```dart
// Left: header + network selector + status quote
// Padding: EdgeInsets.all(40)

Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    // Header block
    _ModalHeader(
      plan: widget.billingCycle,
      invoice: paymentState.invoice,
    ),

    const SizedBox(height: 32),

    // Network selector label
    Text(
      'SELECT NETWORK',
      style: textTheme.labelSmall?.copyWith(
        color: const Color(0xFFA88989),  // outline
        letterSpacing: 3.0,
        fontWeight: FontWeight.w600,
      ),
    ),

    const SizedBox(height: 8),

    // Network radio cards
    for (final currency in CryptoCurrency.values)
      _NetworkCard(
        currency: currency,
        isSelected: _selectedCurrency == currency,
        isEnabled: paymentState.invoice == null,  // lock after invoice created
        onTap: () => setState(() => _selectedCurrency = currency),
      ),

    const Spacer(),

    // Status quote
    _StatusQuote(),
  ],
)
```

### 5.3 Component: `_ModalHeader`

```dart
// workspace_premium icon + "PREMIUM ACTIVATION" label
// + plan title + crypto price + USD price

Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Row(
      children: [
        Icon(
          Icons.workspace_premium,
          // fill=1 via font variation: use `FontVariation('FILL', 1.0)`
          color: colorScheme.secondary,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          'PREMIUM ACTIVATION',
          style: textTheme.labelMedium?.copyWith(
            color: colorScheme.secondary,
            letterSpacing: 1.8,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),

    const SizedBox(height: 4),

    Text(
      billingCycle == BillingCycle.annual ? 'Annual Plan' : 'Monthly Plan',
      style: textTheme.headlineLarge?.copyWith(
        fontSize: 36,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
    ),

    const SizedBox(height: 6),

    // Crypto amount — shown once invoice is created; placeholder before
    Text(
      invoice != null
          ? '${invoice.amount} ${invoice.currency.symbol}'
          : '—',
      style: textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w300,
        color: colorScheme.primary,
      ),
    ),

    const SizedBox(height: 2),

    Text(
      // USD price from pricing plan, e.g. "$59.99 USD"
      planPrice,
      style: textTheme.labelLarge?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
    ),
  ],
)
```

### 5.4 Component: `_NetworkCard`

```dart
// Animated radio-style selection card
// Height: 64px. Smooth color transition on select.

AnimatedContainer(
  duration: const Duration(milliseconds: 200),
  curve: Curves.easeOut,
  margin: const EdgeInsets.only(bottom: 8),
  padding: const EdgeInsets.symmetric(horizontal: 16),
  height: 64,
  decoration: BoxDecoration(
    color: isSelected
        ? const Color(0xFF8D021F).withValues(alpha: 0.20)
        : const Color(0xFF2A2A2A).withValues(alpha: 0.40),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: isSelected
          ? const Color(0xFF8D021F).withValues(alpha: 0.30)
          : Colors.transparent,
    ),
    boxShadow: isSelected
        ? [BoxShadow(
            color: const Color(0xFF8D021F).withValues(alpha: 0.40),
            blurRadius: 40,
            spreadRadius: -10,
          )]
        : [],
  ),
  child: Row(
    children: [
      // Selected state: check_circle FILL 1. Unselected: circle outline.
      Icon(
        isSelected ? Icons.check_circle : Icons.circle_outlined,
        color: isSelected ? colorScheme.primary : colorScheme.outline,
        size: 20,
      ),
      const SizedBox(width: 12),

      // Currency symbol badge
      Text(
        currency.symbol,
        style: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
      ),
      const SizedBox(width: 8),

      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(currency.displayName, style: ...bold),
            Text(_confirmationDetail(currency), style: ...variant),
          ],
        ),
      ),
    ],
  ),
)

// Confirmation detail strings:
String _confirmationDetail(CryptoCurrency c) => switch (c) {
  CryptoCurrency.btc => '1 confirmation • ~10 mins',
  CryptoCurrency.ltc => '3 confirmations • ~7.5 mins',
  CryptoCurrency.xmr => '10 confirmations • ~20 mins',
};
```

### 5.5 Component: `_StatusQuote`

```dart
// Atmospheric italic quote at bottom of left column
// Left accent border = primary-container (#8D0022)

Container(
  padding: const EdgeInsets.all(20),
  decoration: BoxDecoration(
    color: const Color(0xFF0E0E0E).withValues(alpha: 0.50),
    borderRadius: BorderRadius.circular(8),
    border: Border(
      left: BorderSide(
        color: const Color(0xFF8D0022),  // primary-container
        width: 2,
      ),
    ),
  ),
  child: Text(
    'Your transaction is processed directly on the blockchain. '
    'No intermediaries. No chargebacks. Once confirmed, your license activates automatically.',
    style: textTheme.bodySmall?.copyWith(
      fontStyle: FontStyle.italic,
      color: colorScheme.onSurfaceVariant,
    ),
  ),
)
```

### 5.6 Component: `_CountdownChip`

```dart
// Countdown timer pill — top of right column
// Updates every second from invoice.expiresAt

// Use a StatefulWidget with Timer.periodic(1s) or StreamBuilder on a tick stream.

Container(
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  decoration: BoxDecoration(
    color: const Color(0xFF201F1F),   // surface-container
    borderRadius: BorderRadius.circular(999),
    border: Border.all(
      color: const Color(0xFF594140).withValues(alpha: 0.10),
    ),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colorScheme.primary,
        ),
      ),
      const SizedBox(width: 8),
      Text(
        'Invoice expires in ${_formatCountdown(invoice.timeRemaining)}',
        style: textTheme.labelSmall?.copyWith(
          fontFamily: 'monospace',
        ),
      ),
    ],
  ),
)

// Format: MM:SS
String _formatCountdown(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
```

### 5.7 Component: `_QrContainer`

```dart
// White bg QR code with scannable inner glow + hover scale

// Note: use qr_flutter package (already available) with paymentUri
// Format: bitcoin:ADDRESS?amount=AMOUNT (or litecoin: / monero:)

MouseRegion(
  onEnter: (_) => setState(() => _qrHovered = true),
  onExit: (_) => setState(() => _qrHovered = false),
  child: AnimatedScale(
    scale: _qrHovered ? 1.02 : 1.0,
    duration: const Duration(milliseconds: 200),
    child: Stack(
      alignment: Alignment.center,
      children: [
        // Hover glow background (behind QR)
        AnimatedOpacity(
          opacity: _qrHovered ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),

        // QR container (white bg)
        Container(
          width: 192,
          height: 192,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              // scannable-glow: inset simulation via overlay
              BoxShadow(
                color: const Color(0xFF8D021F).withValues(alpha: 0.20),
                blurRadius: 20,
                spreadRadius: 0,
              ),
            ],
          ),
          child: QrImageView(
            data: invoice.paymentUri,
            version: QrVersions.auto,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
        ),
      ],
    ),
  ),
)
```

### 5.8 Component: `_WalletAddressBlock`

```dart
Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: const Color(0xFF0E0E0E),  // surface-container-lowest
    borderRadius: BorderRadius.circular(8),
    border: Border.all(
      color: const Color(0xFF594140).withValues(alpha: 0.05),
    ),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'WALLET ADDRESS',
        style: textTheme.labelSmall?.copyWith(
          letterSpacing: 3.0,
          fontWeight: FontWeight.w600,
          color: colorScheme.outline,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        invoice.address,
        style: textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          color: colorScheme.onSurface,
        ),
      ),
    ],
  ),
)
```

### 5.9 Component: `_CopyAddressButton`

```dart
// Full-width gradient button. Shows "COPIED!" for 2s on tap.

GestureDetector(
  onTap: () async {
    await Clipboard.setData(ClipboardData(text: invoice.address));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  },
  child: AnimatedContainer(
    duration: const Duration(milliseconds: 150),
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: BoxDecoration(
      gradient: _copied
          ? null
          : const LinearGradient(
              colors: [Color(0xFF8D021F), Color(0xFFBA1434)],
            ),
      color: _copied ? const Color(0xFF201F1F) : null,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      _copied ? 'COPIED!' : 'COPY WALLET ADDRESS',
      textAlign: TextAlign.center,
      style: textTheme.labelSmall?.copyWith(
        color: Colors.white,
        letterSpacing: 2.0,
        fontWeight: FontWeight.w700,
      ),
    ),
  ),
)
```

### 5.10 Component: `_HeartbeatTracker`

```dart
// 64×64 concentric circles + pulsing heart icon + status text

Column(
  children: [
    SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer static ring: primary/20
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.20),
                width: 1,
              ),
            ),
          ),

          // Inner animated ring: spinning indicator
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: colorScheme.primary.withValues(alpha: 0.60),
            ),
          ),

          // Heart icon: pulsing scale animation
          ScaleTransition(
            scale: _heartbeatAnimation,  // 0.9 → 1.0, repeat 1s
            child: Icon(
              Icons.monitor_heart,
              color: colorScheme.primary,
              size: 24,
              // FILL=1: use outlined icon + variation if available
            ),
          ),
        ],
      ),
    ),

    const SizedBox(height: 12),

    Text(
      'Waiting for payment...',
      style: textTheme.labelSmall,
    ),

    const SizedBox(height: 2),

    Text(
      'Status: Mempool Scanning',
      style: textTheme.labelSmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
        fontSize: 10,
      ),
    ),
  ],
)

// Animation setup in initState():
_heartbeatController = AnimationController(
  vsync: this,
  duration: const Duration(milliseconds: 1000),
)..repeat(reverse: true);
_heartbeatAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
  CurvedAnimation(parent: _heartbeatController, curve: Curves.easeInOut),
);
```

## 6. State Flow

### 6.1 States

```
IDLE (currency selection)
  ↓ user taps "Pay with BTC" (or equivalent confirm CTA)
CREATING_INVOICE → [paymentState.isLoading = true, invoice = null]
  ↓ invoice created
WAITING_FOR_PAYMENT → [invoice != null, result = null]
  ↓ polling: checkInvoiceStatus every 5–30s (exponential backoff)
  ↓ invoice.isExpired
EXPIRED → show error + "Generate New Invoice" CTA
  ↓ blockchain confirms
CONFIRMED → [result.isSuccess = true]
  ↓ license activation (separate path from payment)
ACTIVATING_LICENSE
  ↓ success
COMPLETE → close modal, show success dialog
  ↓ Keychain/storage error
ACTIVATION_ERROR → modal shows activation retry dialog (existing path)
```

### 6.2 UI per State

| State | Left column | Right column | CTA |
|-------|-------------|--------------|-----|
| IDLE | Network selector active, no price shown | Countdown hidden, QR placeholder, heartbeat hidden | "Pay with [SYMBOL]" button (bottom of right col) |
| CREATING_INVOICE | Network selector locked, spinner on price line | Countdown hidden, QR shimmer loading | Loading spinner replaces CTA |
| WAITING_FOR_PAYMENT | Network selector locked, invoice amount visible | Countdown active, QR visible, copy button active, heartbeat pulsing | No CTA (waiting) |
| EXPIRED | "Invoice expired" badge on selected card | QR greyed out, countdown shows 00:00 | "Generate New Invoice" button |
| CONFIRMED | Green check on selected card | QR replaced by checkmark animation | Auto-dismiss in 1.5s |
| ACTIVATION_ERROR | Unchanged | Unchanged | Modal auto-closes, existing error dialog fires |

### 6.3 Status Text per Confirmation Count

| Phase | Heartbeat status text |
|-------|-----------------------|
| 0 confirmations | "Status: Mempool Scanning" |
| Partial confirmations | "Status: `N`/`required` Confirmations" |
| Fully confirmed | "Status: Confirmed" |

### 6.4 Close / Cancel Behavior

- IDLE: close freely → `paymentNotifier.reset()`
- CREATING_INVOICE: close disabled (show "creating invoice..." tooltip if attempted)
- WAITING_FOR_PAYMENT: close allowed with confirmation dialog ("Your payment will still be processed. Return to check status later.")
- CONFIRMED / ACTIVATION_ERROR: close handled automatically by flow

## 7. New Provider Required

### 7.1 Local Modal State Provider

The modal needs a local `selectedCurrency` that is **not** in `paymentProvider` (to avoid persisting across sessions). Use a `StateProvider` scoped inside the modal's `ConsumerStatefulWidget`:

```dart
// Inside _CryptoPaymentModalState — no Riverpod provider needed
// Simple setState is sufficient for selectedCurrency:
CryptoCurrency _selectedCurrency = CryptoCurrency.btc;
```

### 7.2 Countdown Timer

```dart
// In initState / when invoice is received:
Timer? _countdownTimer;

void _startCountdown(CryptoInvoice invoice) {
  _countdownTimer?.cancel();
  _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
    if (mounted) setState(() {});       // triggers timeRemaining recalc
    if (invoice.isExpired) {
      _countdownTimer?.cancel();
      // Transition to EXPIRED state
    }
  });
}

@override
void dispose() {
  _countdownTimer?.cancel();
  _heartbeatController.dispose();
  super.dispose();
}
```

### 7.3 No New Riverpod Providers

All payment state is already in `paymentProvider` (`PaymentNotifier`). The modal reads:
- `ref.watch(paymentProvider)` → `PaymentState`
- `ref.watch(paymentProvider.notifier).startCryptoCheckout()`
- `ref.watch(selectedBillingCycleProvider)` → passed in as `widget.billingCycle`

## 8. Platform Considerations

### 8.1 macOS

- `BackdropFilter` works correctly on macOS — no platform workarounds needed
- `qr_flutter` renders as Flutter widget — platform-independent
- `Clipboard.setData` uses native pasteboard — works on all platforms
- Modal entry: use transparent `PageRoute` to preserve desktop window chrome
- Do NOT use `showDialog` — it adds a scrim and the design requires controlled backdrop

### 8.2 Windows

- Same widget tree — `BackdropFilter` supported
- `Clipboard.setData` works via `services` platform channel
- Window chrome remains unchanged (modal is inside Flutter surface)
- No Windows-specific overrides needed

### 8.3 Linux

- Same as Windows
- `qr_flutter` renders via Skia — no system dependency

### 8.4 QR Package

- `qr_flutter` is the established package for Flutter QR rendering
- Verify it is already in `pubspec.yaml` before writing import
- The `paymentUri` format from BTCPay: `bitcoin:ADDRESS?amount=0.00082` (BIP21)
- Monero uses `monero:ADDRESS?tx_amount=0.5` format — BTCPay handles URI generation server-side

## 9. Animation Spec

| Animation | Duration | Curve | Notes |
|-----------|----------|-------|-------|
| Modal enter (scale + fade) | 250ms | `Curves.easeOutCubic` | `ScaleTransition` 0.95→1.0 + `FadeTransition` |
| Modal exit | 180ms | `Curves.easeIn` | Reverse of enter |
| Network card selection | 200ms | `Curves.easeOut` | `AnimatedContainer` bg + border + shadow |
| QR hover scale | 200ms | `Curves.easeOut` | `AnimatedScale` 1.0→1.02 |
| QR hover glow | 200ms | `Curves.easeOut` | `AnimatedOpacity` 0.0→1.0 |
| Copy button "COPIED!" state | 150ms enter, 150ms exit | `Curves.easeOut` | `AnimatedContainer` bg swap |
| Countdown update | Instant (every 1s) | — | `setState` in `Timer.periodic` |
| Heartbeat icon pulse | 1000ms, reverse: true | `Curves.easeInOut` | `AnimationController.repeat(reverse: true)` |
| Heartbeat inner ring spin | Continuous indeterminate | — | `CircularProgressIndicator(value: null)` |
| State transition (CREATING → WAITING) | 300ms | `Curves.easeOut` | `AnimatedSwitcher` on right column content |
| Confirmed state (QR → checkmark) | 400ms | `Curves.easeOutBack` | Scale-in `Icons.check_circle_rounded` in primary color |

## 10. Verification Checklist

- [ ] Backdrop blur renders correctly — dashboard visible but softened behind modal
- [ ] Glass panel bg: dark, semi-transparent, distinct from solid black
- [ ] Left column: header icon (workspace_premium) uses secondary color
- [ ] Plan title, crypto amount, USD price all display correctly with invoice data
- [ ] Network selector: BTC pre-selected on open, correct card highlight + glow
- [ ] Network card switch: animated bg + border + shadow transition
- [ ] Confirmation detail strings match: "1 confirmation • ~10 mins" / "3 confirmations • ~7.5 mins" / "10 confirmations • ~20 mins"
- [ ] Status quote: italic text, left border accent visible
- [ ] Countdown: starts from invoice expiry, counts down every second, "00:00" on expire
- [ ] QR renders correctly with `paymentUri` data
- [ ] QR hover: scale + glow appear, revert on mouse exit
- [ ] Wallet address: monospace, break-all wrapping, full address shown
- [ ] Copy button: gradient bg, uppercase tracking, "COPIED!" state for 2s
- [ ] Clipboard actually copies — verify paste in another app
- [ ] Heartbeat: outer ring visible, inner ring spinning, icon pulsing
- [ ] Status text updates: "Mempool Scanning" → "N/M Confirmations" → "Confirmed"
- [ ] On confirmation: right column transitions to checkmark, modal auto-dismisses
- [ ] Activation error: existing dialog fires after modal closes (no regression)
- [ ] Close button: top-right, only visible when not in CREATING_INVOICE state
- [ ] Close in WAITING state: confirmation dialog appears before closing
- [ ] `paymentNotifier.reset()` called on close
- [ ] `flutter analyze` passes with 0 issues
- [ ] No layout overflow on minimum modal width (test at 896px window width)
- [ ] All 3 platforms: macOS, Windows, Linux — modal renders without platform errors
