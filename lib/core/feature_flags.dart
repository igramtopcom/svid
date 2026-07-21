/// V2 Campaign — Feature Flag Gates
///
/// **Why this file is intentionally retained even though no widget
/// currently consumes [homeV2Enabled]:**
///
/// The current V2 redesign (top bar + smart input adaptive routing +
/// right-rail rebuild + auto-extract removal) ships unconditionally —
/// the production code path now is V2. That makes [homeV2Enabled]
/// look like dead code at first glance, BUT:
///
/// 1. **Rollback safety net.** If a regression surfaces in
///    production, we want a single line to flip ("kill switch") that
///    routes the home shell back to the legacy v1 path without a
///    binary roll-back. Re-introducing a gate later means re-running
///    the whole feature flag plumbing — much higher cost than keeping
///    the constant + the doc here.
/// 2. **Phase 1A scaffold lives behind it.** `SmartInputBar` and its
///    sub-widgets (`smart_cta_button`, `customize_icon_button`,
///    `preset_dropdown_button`, `preset_popover`,
///    `customize_preferences_provider`) are a deliberate dormant
///    scaffold for a future fully-V2 home that replaces
///    GlassmorphismHeader rather than augmenting it. Restoring the
///    gate lets that scaffold come back online without re-writing
///    widgets that are already analyzer-clean and tested.
/// 3. **Multi-brand HYBRID schedule.** Svid ships V2 first; VidCombo
///    continues v1.x until the v2.1.0 port cycle (DECISIONS.md Q13).
///    [homeV2Enabled] returns `false` for VidCombo today, so deleting
///    it would also delete the brand-conditional contract.
///
/// Don't reflex-delete this file. If a future engineer concludes the
/// scaffold path is permanently abandoned, replace this rationale with
/// the new decision before removing the gate.
///
/// References:
///   - docs/v2/DECISIONS.md (rollback strategy, brand HYBRID)
///   - docs/v2/findings/2E-multibrand-strategy.md §5
library;

import 'config/brand_config.dart';

/// Compile-time / hotfix-controlled rollout flags for the V2 campaign.
///
/// During development the Svid default stays `false` so PRs can ship
/// gated UI without affecting alpha builds. Each rollout milestone (alpha
/// → beta → public) flips the default in a separate commit.
///
/// VidCombo always returns `false` for V2 flags during the Svid v2.0
/// cycle. The v2.1 port branch will flip the brand-conditional check.
class FeatureFlags {
  FeatureFlags._();

  /// Svid V2 default. Currently `false` (pre-alpha).
  /// Flip sequence:
  ///   - Internal alpha (after Phase 1A+§5):  `_kSvidV2Default = true` in
  ///     a "release(alpha)" commit, internal builds only.
  ///   - Internal beta (after Phase 1B+1C):   stays `true`.
  ///   - Closed beta (after Phase §10):       stays `true`.
  ///   - Public release (after Polish+Buffer): stays `true`; backend can
  ///     remote-toggle via `home_v2_enabled` flag for staged rollout.
  ///   - Hotfix rollback: flip `false`, ship hotfix.
  static const bool _kSvidV2Default = false;

  /// `true` when the V2 home screen + download manager redesign should
  /// render, replacing the v1 home shell. Brand-conditional: VidCombo
  /// stays `false` until the v2.1 cycle. Svid honors
  /// [_kSvidV2Default] (no remote-config wiring yet — additive in
  /// Polish phase).
  static bool get homeV2Enabled {
    if (BrandConfig.current.brand == Brand.vidcombo) return false;
    return _kSvidV2Default;
  }

  /// `true` when the player can attach a [UserPlaylist] context to its
  /// queue (F3 — player play list). Gated independently from
  /// [homeV2Enabled] because the player feature ships in Phase §10
  /// after the home redesign is already in beta.
  static bool get playlistContextEnabled =>
      homeV2Enabled && _kPlaylistContextDefault;

  static const bool _kPlaylistContextDefault = false;
}
