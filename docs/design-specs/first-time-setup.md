# First-Time Setup Screen — Design Spec

> Source: Stitch project `10022260214920217805`
> Dark: screen `348c7397` | Light: screen `a4da878d`
> Status: APPROVED — Ready for implementation
> Current code: `lib/core/binaries/presentation/binary_setup_screen.dart` (468 lines)

## 1. Design Intent

**Purpose**: First impression screen. Shown once on first launch while downloading yt-dlp, ffmpeg, gallery-dl.

**Mood**: Cinematic, minimal, confident. "This is a premium tool, not a utility."

**Key principle**: The setup should feel like an experience, not a loading screen. One focused element at a time — no information overload.

## 2. Visual Structure

### 2.1 Layout (Both Modes)

```
┌──────────────────────────────────────────────────┐
│ [●] [●] [●]     Svid Setup           [?] [⚙]  │  ← macOS title bar (40px)
├──────────────────────────────────────────────────┤
│                                                   │
│                                                   │
│              ┌───────┐  ← Back square             │
│              │ ┌───┐ │     (crimson, rotated 5°)  │
│              │ │ ▶ │ │  ← Front square            │
│              │ └───┘ │     (wine red, play icon)   │
│              └───────┘                             │
│                                                   │
│            Welcome to Svid                       │  ← 28px semibold
│         Preparing your experience...              │  ← 14px medium
│                                                   │
│         ████████████░░░░░░░░░░░░                 │  ← gradient progress bar
│         Setting up video engine · 2 of 3          │  ← 12px medium
│                                                   │
│                                                   │
│                                                   │
│            THIS ONLY HAPPENS ONCE                 │  ← 11px uppercase footer
└──────────────────────────────────────────────────┘
```

### 2.2 Dimensions

| Element | Value | Token mapping |
|---------|-------|---------------|
| Container max-width | 400px | Custom |
| Logo size | 80×80px | Custom |
| Logo border-radius | xl (Flutter: `AppRadius.xl` = 20px) | `AppRadius.xl` |
| Logo rotation (back) | 5 degrees | Custom |
| Logo translation (back) | x+4px, y-4px | Custom |
| Progress bar width | 300px | Custom |
| Progress bar height | 4px (h-1) | Custom |
| Progress bar radius | full (999px) | `AppRadius.full` |

### 2.3 Spacing

| Between | Gap | Token |
|---------|-----|-------|
| Logo → Title | 24px | `AppSpacing.lg` |
| Title → Subtitle | 8px | `AppSpacing.sm` |
| Subtitle → Progress | 32px | `AppSpacing.xl` |
| Progress bar → Status text | 12px | `AppSpacing.md - 4` (custom 12px) |
| Footer from bottom | 40px | Custom padding |

## 3. Token Extraction — Dark Mode

### 3.1 Colors (from Stitch HTML)

| Element | Stitch Hex | Flutter Mapping | Notes |
|---------|-----------|-----------------|-------|
| Background | `#121212` | `colorScheme.surface` (= `#121212`) | ✅ Exact match |
| Background glow center | `#1C1B1B` | Custom `RadialGradient` | Subtle noir light source |
| Title bar bg | `#1A1A1A` | `AppColors.darkSurface1` → adjust to `#1A1A1A` | Close (current `#1E1E1E`) |
| Traffic light (close) | `#C41E3A` | `AppColors.brand` accent | Crimson variant |
| Traffic light (min/max) | `#393939` | `colorScheme.surfaceContainerHighest` | Inactive dots |
| Title bar text | `#E5E2E1` @ 40% | `colorScheme.onSurface.withOpacity(0.4)` | ✅ Match |
| Title text | `#FFFFFF` | `Colors.white` | Pure white for emphasis |
| Subtitle text | `#888888` | Custom — not in current tokens | Need: `Color(0xFF888888)` |
| Logo back square | `#C41E3A` | New: `AppColors.accentHighlight` | From DESIGN.md |
| Logo front square | `#8D021F` | `AppColors.brand` | ✅ Exact match |
| Play icon | `#FFFFFF` | `Colors.white` | |
| Progress track | `#2C2C2C` | `AppColors.darkSurface3` (= `#2C2C2C`) | ✅ Exact match |
| Progress fill start | `#8D021F` | `AppColors.brand` | Gradient start |
| Progress fill end | `#C41E3A` | New: `AppColors.accentHighlight` | Gradient end |
| Status text | `#666666` | Custom | Dimmer than onSurfaceVariant |
| Footer text | `#444444` | Custom | Very dim |
| Help/Settings icons | `#393939` | `colorScheme.surfaceContainerHighest` | |
| Icon hover | `#FFB3B4` | `colorScheme.primary` (dark) | ✅ Match |

### 3.2 Colors — Light Mode

| Element | Stitch Hex | Flutter Mapping |
|---------|-----------|-----------------|
| Background | `#FFFFFF` | `Colors.white` |
| Title bar bg | `#F0F0F0` | Custom — close to `AppColors.lightSurface2` |
| Title bar border | `#E0E0E0` | `AppColors.lightBorder` |
| Traffic lights | `#FF5F57` / `#FFBD2E` / `#28C840` | Standard macOS colors |
| Title bar text | `#999999` | Custom |
| Title text | `#1A1A1A` | `colorScheme.onSurface` (= `#1A1A1A`) | ✅ |
| Subtitle text | `#999999` | Custom |
| Progress track | `#EEEEEE` | Close to `AppColors.lightSurface3` |
| Progress fill | Same gradient `#8D021F → #C41E3A` | Brand constant |
| Status text | `#AAAAAA` | Custom |
| Footer text | `#CCCCCC` | Custom |
| Decorative blur (bottom-right) | `primary-container @ 3%` | `AppColors.brand.withOpacity(0.03)` |
| Decorative blur (top-left) | `primary @ 2%` | `AppColors.brand.withOpacity(0.02)` |

### 3.3 Typography

| Element | Size | Weight | Tracking | Flutter Style |
|---------|------|--------|----------|---------------|
| Title bar label | 12px (dark) / 11px (light) | bold / medium | 0.2em / tight | `AppTypography.sectionHeader` adjusted |
| Welcome heading | 28px | semibold (600) | tight (-0.02em) | `textTheme.headlineLarge` (= 28px/600) ✅ |
| Subtitle | 14px | medium (500) | normal | `textTheme.labelLarge` (= 14px/500) ✅ |
| Status text | 12px | medium (500) | wide (0.05em) | `textTheme.labelMedium` (= 12px/500) close |
| Footer | 11px | medium (500) | 0.2em, uppercase | `textTheme.labelSmall` (= 11px/500) ✅ |

### 3.4 Effects

| Effect | Dark | Light |
|--------|------|-------|
| Background glow | `radial-gradient(circle at center, #1C1B1B 0%, #121212 70%)` | None (clean white) |
| Decorative blurs | None | 2 circles: 384px diameter, blur(100-120px), 2-3% opacity |
| Logo shadow | `shadow-2xl` (25px spread, 10px blur) | `shadow-lg` (15px spread, 6px blur) |
| Logo back rotation | `rotate(5deg) translateX(4px) translateY(-4px)` | Same |

## 4. Gap Analysis — Design vs Current Code

### 4.1 MAJOR Changes

| # | Current | Design | Impact |
|---|---------|--------|--------|
| 1 | PNG logo (100×100, ClipRRect) | **Overlapping rotated squares** (80×80) with play_arrow icon | Widget replacement |
| 2 | 3 binary cards with individual progress | **Single progress bar** with "N of 3" counter | Layout simplification |
| 3 | Title: "Setting Up Svid" | "Welcome to Svid" | Text change |
| 4 | Subtitle: "Downloading required components..." | "Preparing your experience..." | Text change |
| 5 | No background effects | Radial glow (dark) / blur circles (light) | Add decorative layer |
| 6 | No footer | "This only happens once" footer | Add widget |
| 7 | Container maxWidth: 500 | maxWidth: 400 | Narrow |

### 4.2 KEEP (functional requirements not in design)

| # | Element | Reason |
|---|---------|--------|
| 1 | Error container + retry button | Essential UX — users need to see errors and retry |
| 2 | Per-binary status tracking internally | Data layer unchanged — only presentation changes |
| 3 | Success animation + auto-proceed | Flow requirement — 500ms delay then proceed |
| 4 | `onSetupComplete` callback | Architecture contract |
| 5 | `_friendlyErrorMessage()` logic | User-facing error translation |
| 6 | `_formatBytes()` helper | Still needed for error context |

### 4.3 UX Decision: Progress Detail

**Design shows**: 1 bar + "2 of 3" (minimal)
**Current code has**: 3 cards with icons, names, descriptions, per-binary progress

**Recommended approach — Progressive Disclosure**:
- Default: Minimal (match design) — single bar + counter
- Below progress: Small collapsible "Details" text link
- When expanded: Show 3 compact lines (icon + name + status) — no cards, no borders
- Error state: Auto-expand details to show which binary failed

This preserves the cinematic minimalism while keeping functional info accessible.

## 5. Widget Spec — Flutter Implementation

### 5.1 Widget Tree (target)

```dart
Scaffold(
  backgroundColor: colorScheme.surface,
  body: Stack(
    children: [
      // Layer 0: Background effects
      _BackgroundEffects(isDark: isDark),

      // Layer 1: Main content (centered)
      Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Overlapping squares logo
              _SetupLogo(),

              Gap.lg,  // 24px

              // Welcome heading
              Text("Welcome to Svid", ...),

              Gap.sm,  // 8px

              // Subtitle (changes with state)
              Text(_subtitle, ...),

              SizedBox(height: 32),

              // Progress section
              _SetupProgress(
                currentStep: _completedCount + 1,
                totalSteps: BinaryType.values.length,
                progress: _currentProgress,
              ),

              // Expandable detail section
              if (_showDetails) _BinaryDetailList(...),

              Gap.lg,  // 24px

              // Error state (conditional)
              if (_error != null) _SetupError(
                message: _friendlyErrorMessage(_error!),
                rawError: _error,
                onRetry: _startDownload,
              ),

              // Success state (conditional)
              if (_isComplete) _SetupSuccess(),
            ],
          ),
        ),
      ),

      // Layer 2: Footer
      Positioned(
        bottom: 40,
        left: 0, right: 0,
        child: _SetupFooter(),
      ),
    ],
  ),
)
```

### 5.2 Component: `_SetupLogo`

```dart
// Overlapping rotated squares with play icon
Widget _SetupLogo() {
  return SizedBox(
    width: 88,  // 80 + rotation overflow
    height: 88,
    child: Stack(
      alignment: Alignment.center,
      children: [
        // Back square: crimson, rotated 5°
        Transform(
          transform: Matrix4.identity()
            ..translate(4.0, -4.0)
            ..rotateZ(5 * pi / 180),
          alignment: Alignment.center,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.accentHighlight,  // #C41E3A
              borderRadius: AppRadius.borderRadius.xl,
            ),
          ),
        ),
        // Front square: wine red, play icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.brand,  // #8D021F
            borderRadius: AppRadius.borderRadius.xl,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.5 : 0.25),
                blurRadius: isDark ? 25 : 15,
                spreadRadius: isDark ? 10 : 6,
              ),
            ],
          ),
          child: Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 40,
          ),
        ),
      ],
    ),
  );
}
```

### 5.3 Component: `_SetupProgress`

```dart
// Single gradient progress bar + step counter
Widget _SetupProgress({
  required int currentStep,
  required int totalSteps,
  required double progress,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return SizedBox(
    width: 300,
    child: Column(
      children: [
        // Track
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: isDark ? Color(0xFF2C2C2C) : Color(0xFFEEEEEE),
            borderRadius: AppRadius.borderRadius.full,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.brand, accentHighlight],
                  ),
                  borderRadius: AppRadius.borderRadius.full,
                ),
              ),
            ),
          ),
        ),

        SizedBox(height: 12),

        // Step counter
        Text(
          '${_currentBinaryName} · $currentStep of $totalSteps',
          style: textTheme.labelMedium?.copyWith(
            color: isDark ? Color(0xFF666666) : Color(0xFFAAAAAA),
            letterSpacing: 0.5,
          ),
        ),
      ],
    ),
  );
}
```

### 5.4 Component: `_BackgroundEffects`

```dart
// Dark: radial glow from center
// Light: decorative blur circles
Widget _BackgroundEffects({required bool isDark}) {
  if (isDark) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 0.7,
            colors: [Color(0xFF1C1B1B), Color(0xFF121212)],
          ),
        ),
      ),
    );
  }

  return Stack(
    children: [
      Positioned(
        bottom: -128,
        right: -128,
        child: Container(
          width: 384, height: 384,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.brand.withOpacity(0.03),
          ),
          // ImageFilter.blur in BackdropFilter not needed here —
          // use BoxDecoration blur or pre-blurred container
        ),
      ),
      Positioned(
        top: -128,
        left: -128,
        child: Container(
          width: 384, height: 384,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.brand.withOpacity(0.02),
          ),
        ),
      ),
    ],
  );
}
```

### 5.5 Component: `_SetupFooter`

```dart
// "This only happens once" — reassurance micro-copy
Widget _SetupFooter() {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return Center(
    child: Text(
      'THIS ONLY HAPPENS ONCE',
      style: textTheme.labelSmall?.copyWith(
        color: isDark ? Color(0xFF444444) : Color(0xFFCCCCCC),
        letterSpacing: 2.0,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}
```

## 6. State Flow

### 6.1 States

```
INIT → CHECKING → DOWNLOADING → COMPLETE
                ↘ ERROR → RETRY → DOWNLOADING
```

### 6.2 Subtitle Text per State

| State | Subtitle |
|-------|----------|
| Checking | "Preparing your experience..." |
| Downloading | "Preparing your experience..." |
| Error | "Something went wrong" |
| Complete | "You're all set!" |

### 6.3 Progress per State

| State | Progress value | Counter text |
|-------|---------------|--------------|
| Checking | 0.0 (indeterminate pulse) | "Checking components..." |
| Downloading binary 1 | 0.0 → 0.33 | "Setting up video engine · 1 of 3" |
| Downloading binary 2 | 0.33 → 0.66 | "Setting up media tools · 2 of 3" |
| Downloading binary 3 | 0.66 → 1.0 | "Setting up image engine · 3 of 3" |
| Complete | 1.0 | "Ready!" |

### 6.4 Binary → Display Name Mapping

| BinaryType | Current displayName | Design-friendly name |
|------------|--------------------|--------------------|
| `ytDlp` | "yt-dlp" | "video engine" |
| `ffmpeg` | "FFmpeg" | "media tools" |
| `galleryDl` | "gallery-dl" | "image engine" |

## 7. Token Changes Required

### 7.1 Add to `app_colors.dart`

```dart
// Accent highlight — crimson for gradients, CTA, active states
static const Color accentHighlight = Color(0xFFC41E3A);

// Accent muted — subtle accent backgrounds, badges
static const Color accentMuted = Color(0xFF5C0114);
```

### 7.2 No changes to `app_typography.dart`
All text styles covered by existing textTheme entries.

### 7.3 No changes to `app_spacing.dart`
All spacings covered. The 12px gap (between progress bar and text) = custom inline `SizedBox(height: 12)`.

## 8. Platform Considerations

### 8.1 macOS Title Bar
- Flutter handles native traffic lights automatically
- Do NOT recreate the HTML header — it's Stitch visual reference only
- `window_manager` already configured — title bar is native
- The "Svid Setup" title text in the design → could set via `window_manager.setTitle('Svid Setup')`

### 8.2 Windows
- No traffic lights — Windows title bar has minimize/maximize/close
- Same screen content, different window chrome (handled by Flutter)

### 8.3 Linux
- Same as Windows — system title bar

## 9. Animation Spec

| Animation | Duration | Curve | Token |
|-----------|----------|-------|-------|
| Progress bar fill | Continuous (follows download) | `Curves.easeOut` | — |
| Logo entrance | 400ms | `Curves.easeOutCubic` | `AppTransitions.curveEnter` |
| Title/subtitle fade-in | 300ms, staggered 100ms | `Curves.easeOut` | `AppTransitions.slow` |
| State transition (subtitle text) | 200ms crossfade | `Curves.easeInOut` | `AppTransitions.normal` |
| Success → proceed | 500ms delay | — | Existing |
| Error appear | 200ms slide-up + fade | `Curves.easeOutCubic` | `AppTransitions.normal` |

## 10. Verification Checklist

- [ ] Logo: overlapping squares visible, back rotated 5°, front has play icon
- [ ] Colors match token table (dark mode)
- [ ] Colors match token table (light mode)
- [ ] Progress bar gradient renders correctly
- [ ] Progress tracks per-binary download accurately
- [ ] Step counter updates: "1 of 3" → "2 of 3" → "3 of 3"
- [ ] Footer text visible, uppercase, correct color
- [ ] Background glow visible (dark mode)
- [ ] Decorative blurs visible (light mode)
- [ ] Error state shows error message + retry button
- [ ] Retry works after error
- [ ] Auto-proceed after success (500ms delay)
- [ ] `flutter analyze` passes with 0 issues
- [ ] Theme toggle: dark ↔ light works correctly on this screen
- [ ] Window title shows "Svid Setup" during this screen
- [ ] All existing binary download logic preserved (no functional regression)
