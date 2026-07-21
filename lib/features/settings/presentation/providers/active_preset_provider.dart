/// V2 — Active preset state + currentConfig overrides.
///
/// Tracks which built-in / user FormatPreset is currently selected and
/// the in-memory + persistent override snapshot the user is editing in
/// the popover (UI Spec §5.4). Persistence is SharedPreferences-backed:
///   - `active_preset_id` (String — UUID or built-in id)
///   - `current_config` (JSON FormatPresetExtended snapshot)
///
/// "Current config" is a transient working copy of the active preset
/// with the user's popover tweaks applied. It is NOT the saved preset
/// — saving requires explicit "Tạo profile mới…" action (Spec §5.4).
///
/// The [activePresetProvider] watches `formatPresetsProvider` so the
/// "active preset deleted → fallback to `auto`" rule (Spec §5.4) is
/// enforced reactively rather than on read.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/logging/app_logger.dart';
import '../../data/datasources/builtin_presets_seeder.dart';
import '../../domain/entities/format_preset_extended.dart';
import 'settings_provider.dart';

// ─────────────────────────────────────────────────────────────────────
// Available presets — single source of truth for chip popover, profile
// selector and ActivePresetController construction. Reads from the
// SharedPreferences key written by [V2FormatPresetMigration] on app
// startup. Falls back to canonical built-ins on missing / corrupt data
// so the user never sees an empty popover.
// ─────────────────────────────────────────────────────────────────────

/// Reads the migrated v2 `format_presets` records from SharedPreferences
/// and returns them as a list of [FormatPresetExtended]. Custom user
/// presets and the six built-ins are returned in a single list.
///
/// The provider re-watches `sharedPreferencesProvider` so any consumer
/// that wants live updates after a custom preset is added (Settings →
/// Quality) can invalidate the provider explicitly. We avoid auto-
/// invalidation on every SharedPreferences write to keep popover state
/// stable while the user is mid-edit.
final availableExtendedPresetsProvider = Provider<List<FormatPresetExtended>>((
  ref,
) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final raw = prefs.getString('format_presets');
  if (raw == null || raw.isEmpty) {
    // Migration hasn't run yet (test harness, fresh install before
    // bootstrap, etc.). Surface canonical built-ins so the popover
    // stays usable instead of empty.
    return BuiltinPresetsSeeder.canonicalBuiltins();
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return BuiltinPresetsSeeder.canonicalBuiltins();
    final list = decoded
        .whereType<Map<String, dynamic>>()
        // Only v2-shaped records (have schemaVersion). Pre-migration
        // records (7-field legacy) lack `id`, so surfacing them here
        // would yield empty-id presets that setActive can't address.
        // Known limitation: a user creating a preset via the legacy
        // Settings → Quality screen writes 7-field records and won't
        // see them in the popover until the next app launch (when
        // V2FormatPresetMigration upgrades them in place). Acceptable
        // trade — the legacy CRUD UI continues to show them; chip
        // popover lags by one launch.
        .where((m) => m['schemaVersion'] != null)
        .map(FormatPresetExtended.fromJson)
        .toList(growable: false);
    if (list.isEmpty) return BuiltinPresetsSeeder.canonicalBuiltins();
    return list;
  } catch (e, st) {
    appLogger.error(
      'availableExtendedPresetsProvider: parse failed, '
      'falling back to canonical built-ins',
      e,
      st,
    );
    return BuiltinPresetsSeeder.canonicalBuiltins();
  }
});

const String _activePresetIdKey = 'active_preset_id';
const String _currentConfigKey = 'current_config';
const String _useManualModeKey = 'use_manual_mode';

/// Snapshot of the active preset + the user's working override.
class ActivePresetState {
  const ActivePresetState({
    required this.activeId,
    required this.activePreset,
    required this.currentConfig,
    this.useManualMode = false,
  });

  /// ID of the preset the popover currently shows as ✓-selected.
  final String activeId;

  /// The original [FormatPresetExtended] for [activeId] — used to
  /// detect "modified" status against [currentConfig].
  final FormatPresetExtended activePreset;

  /// Working copy with popover tweaks applied. When equal to
  /// [activePreset], the popover is "clean"; otherwise the
  /// "(đã chỉnh sửa)" badge shows.
  final FormatPresetExtended currentConfig;

  /// "Always show advanced dialog" mode (opt-in via popover toggle).
  ///
  /// When true, Rule 1.5 (preset auto-pick) is short-circuited in
  /// `HomeDownloadMixin.handleDownloadDecision` and every download
  /// flows straight to `DownloadConfigDialog` — the legacy "super
  /// feature" surface that exposes every preference (codec, container,
  /// fps, subs, sponsor block, watermark, etc.).
  ///
  /// Designed to be a peer of preset selection, not a replacement: a
  /// power user can keep their preset list as a quick path AND have a
  /// one-click switch to the full dialog when they need fine control.
  /// Saved preferences from the dialog (Rule 2 platform savedPref +
  /// new "Save as preset" via [ActivePresetController.addUserPreset])
  /// continue to flow back into the chip popover for next time.
  final bool useManualMode;

  bool get isModified => !_presetsEqual(activePreset, currentConfig);

  static bool _presetsEqual(FormatPresetExtended a, FormatPresetExtended b) =>
      a.maxResolution == b.maxResolution &&
      a.videoCodec == b.videoCodec &&
      a.audioCodec == b.audioCodec &&
      a.containerFormat == b.containerFormat &&
      a.fpsPreference == b.fpsPreference &&
      a.audioOnly == b.audioOnly &&
      a.audioBitrate == b.audioBitrate &&
      a.fallbackBehavior == b.fallbackBehavior &&
      a.saveLocation == b.saveLocation &&
      a.subtitlesEnabled == b.subtitlesEnabled &&
      a.embedThumbnail == b.embedThumbnail &&
      a.embedMetadata == b.embedMetadata &&
      a.embedChapters == b.embedChapters;
}

/// Notifier owning [ActivePresetState] persistence + transitions.
///
/// Public API mirrors the user-facing actions in Spec §5.4:
///   - [setActive] — user picks a different profile.
///   - [updateField] — user tweaks a popover field.
///   - [reset] — discard current overrides, restore active preset.
class ActivePresetController extends StateNotifier<ActivePresetState> {
  ActivePresetController({
    required SharedPreferences prefs,
    required List<FormatPresetExtended> availablePresets,
    void Function()? onListMutated,
  }) : _prefs = prefs,
       _availablePresets = availablePresets,
       _onListMutated = onListMutated,
       super(_initialState(prefs, availablePresets));

  final SharedPreferences _prefs;
  List<FormatPresetExtended> _availablePresets;

  /// Optional callback fired after [addUserPreset] mutates the
  /// persisted `format_presets` store. The provider factory wires this
  /// to `ref.invalidate(availableExtendedPresetsProvider)` so the chip
  /// popover sees the new entry on the next frame without manual
  /// refresh.
  final void Function()? _onListMutated;

  /// Recompute state when the available preset list changes (e.g. user
  /// deletes a preset elsewhere). Enforces the Spec §5.4 fallback:
  /// active preset gone → revert to `auto`.
  void onPresetListChanged(List<FormatPresetExtended> latest) {
    _availablePresets = latest;
    final stillExists = latest.any((p) => p.id == state.activeId);
    if (stillExists) return;

    appLogger.info(
      'ActivePresetController: active preset "${state.activeId}" was '
      'deleted — falling back to "${BuiltinPresetIds.auto}"',
    );
    final auto = _findOrAuto(latest, BuiltinPresetIds.auto);
    state = ActivePresetState(
      activeId: auto.id,
      activePreset: auto,
      currentConfig: auto,
      useManualMode: state.useManualMode,
    );
    _prefs.setString(_activePresetIdKey, auto.id);
    _prefs.remove(_currentConfigKey);
  }

  /// Switch to a different preset. Resets `currentConfig` to mirror the
  /// new active preset (Spec §5.4 "Chọn preset khác → currentConfig =
  /// preset.config"). Picking a real preset clears `useManualMode` —
  /// the two are mutually exclusive UX modes (preset auto-pick vs
  /// always-show-dialog).
  Future<void> setActive(String presetId) async {
    final preset = _availablePresets.firstWhere(
      (p) => p.id == presetId,
      orElse: () => _findOrAuto(_availablePresets, BuiltinPresetIds.auto),
    );
    state = ActivePresetState(
      activeId: preset.id,
      activePreset: preset,
      currentConfig: preset,
      useManualMode: false,
    );
    await _prefs.setString(_activePresetIdKey, preset.id);
    await _prefs.remove(_currentConfigKey);
    await _prefs.setBool(_useManualModeKey, false);
  }

  /// Apply a popover field tweak. Persists `currentConfig` JSON so the
  /// edit survives app restart even if the user never explicitly saves
  /// it as a new preset.
  Future<void> updateConfig(FormatPresetExtended next) async {
    state = ActivePresetState(
      activeId: state.activeId,
      activePreset: state.activePreset,
      currentConfig: next,
      useManualMode: state.useManualMode,
    );
    await _prefs.setString(_currentConfigKey, jsonEncode(next.toJson()));
  }

  /// Toggle the "always show advanced dialog" mode. When true,
  /// Rule 1.5 in `HomeDownloadMixin.handleDownloadDecision` is
  /// short-circuited so every download surfaces the full
  /// `DownloadConfigDialog` instead of auto-picking via the active
  /// preset. Persisted across launches via SharedPreferences.
  Future<void> setManualMode(bool enabled) async {
    if (state.useManualMode == enabled) return;
    state = ActivePresetState(
      activeId: state.activeId,
      activePreset: state.activePreset,
      currentConfig: state.currentConfig,
      useManualMode: enabled,
    );
    await _prefs.setBool(_useManualModeKey, enabled);
  }

  /// Persist a new user-owned preset into the `format_presets` store
  /// and signal the popover provider to refresh. Intended for the
  /// "Save as preset" flow — the dialog picks a quality + format, the
  /// caller builds a [FormatPresetExtended] and hands it here.
  ///
  /// Returns the persisted preset's id so the caller can immediately
  /// call [setActive] if the user wants the new preset to take effect
  /// for subsequent downloads in the same session.
  ///
  /// Idempotent on duplicate ids — if a record with the same id
  /// already exists it's replaced (preserves the user's mental model
  /// "I saved this one, now I'm updating it").
  Future<String> addUserPreset(FormatPresetExtended preset) async {
    final existing = _readPresetMaps();

    // Replace-on-id semantics. Avoids duplicate entries when the user
    // re-saves a preset they previously created (e.g. tweaks then
    // commits again with the same name → same id).
    final filtered = existing
        .where((m) => m['id'] != preset.id)
        .toList(growable: true);
    filtered.add(preset.toJson());

    await _prefs.setString(formatPresetsKey, jsonEncode(filtered));
    _onListMutated?.call();
    return preset.id;
  }

  List<Map<String, dynamic>> _readPresetMaps() {
    final raw = _prefs.getString(formatPresetsKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {
      // Corrupt JSON — fall through to a fresh write of the next preset.
    }
    return const [];
  }

  /// Discard popover tweaks, restoring `currentConfig = activePreset`.
  Future<void> reset() async {
    state = ActivePresetState(
      activeId: state.activeId,
      activePreset: state.activePreset,
      currentConfig: state.activePreset,
      useManualMode: state.useManualMode,
    );
    await _prefs.remove(_currentConfigKey);
  }

  // ── Construction helpers ──

  static ActivePresetState _initialState(
    SharedPreferences prefs,
    List<FormatPresetExtended> presets,
  ) {
    final storedId =
        prefs.getString(_activePresetIdKey) ?? BuiltinPresetIds.auto;
    final active = _findOrAuto(presets, storedId);
    final manualMode = prefs.getBool(_useManualModeKey) ?? false;

    final rawCurrent = prefs.getString(_currentConfigKey);
    if (rawCurrent == null || rawCurrent.isEmpty) {
      return ActivePresetState(
        activeId: active.id,
        activePreset: active,
        currentConfig: active,
        useManualMode: manualMode,
      );
    }

    try {
      final json = jsonDecode(rawCurrent) as Map<String, dynamic>;
      final restored = FormatPresetExtended.fromJson(json);
      return ActivePresetState(
        activeId: active.id,
        activePreset: active,
        currentConfig: restored,
        useManualMode: manualMode,
      );
    } catch (e, st) {
      appLogger.error(
        'ActivePresetController: corrupt current_config JSON, '
        'falling back to active preset',
        e,
        st,
      );
      return ActivePresetState(
        activeId: active.id,
        activePreset: active,
        currentConfig: active,
        useManualMode: manualMode,
      );
    }
  }

  static FormatPresetExtended _findOrAuto(
    List<FormatPresetExtended> presets,
    String id,
  ) {
    final match = presets.where((p) => p.id == id);
    if (match.isNotEmpty) return match.first;
    final auto = presets.where((p) => p.id == BuiltinPresetIds.auto);
    if (auto.isNotEmpty) return auto.first;
    // Defensive fallback — synthesize an in-memory `auto` if the seeder
    // hasn't run yet. Should not happen in production because main()
    // runs the migration before constructing providers.
    return BuiltinPresetsSeeder.canonicalBuiltins().first;
  }
}

/// Provider — fed by [availableExtendedPresetsProvider] which reads the
/// migrated v2 `format_presets` records (built-ins + custom user
/// presets). Uses `ref.read` for the initial snapshot then `ref.listen`
/// for incremental updates so the controller's in-memory state
/// (currentConfig overrides, activeId) survives across preset list
/// refreshes — `onPresetListChanged` enforces the Spec §5.4 fallback
/// (active preset deleted → revert to `auto`).
final activePresetProvider =
    StateNotifierProvider<ActivePresetController, ActivePresetState>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider);
      final initialPresets = ref.read(availableExtendedPresetsProvider);
      final controller = ActivePresetController(
        prefs: prefs,
        availablePresets: initialPresets,
        // Wire prefs-write → provider-refresh so addUserPreset() shows up
        // in the popover on the next frame (SharedPreferences instance is
        // stable across writes; without explicit invalidation the watch
        // would never fire).
        onListMutated: () => ref.invalidate(availableExtendedPresetsProvider),
      );
      ref.listen<List<FormatPresetExtended>>(
        availableExtendedPresetsProvider,
        (_, next) => controller.onPresetListChanged(next),
      );
      return controller;
    });
