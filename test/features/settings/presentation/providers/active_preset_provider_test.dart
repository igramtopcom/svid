import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssvid/features/settings/data/datasources/builtin_presets_seeder.dart';
import 'package:ssvid/features/settings/domain/entities/format_preset_extended.dart';
import 'package:ssvid/features/settings/presentation/providers/active_preset_provider.dart';

/// Pure-controller tests — no Riverpod harness, no widgets. Asserts the
/// state-transition contract documented in active_preset_provider.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ActivePresetController — initial state', () {
    test('no stored id → defaults to BuiltinPresetIds.auto', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final ctrl = ActivePresetController(
        prefs: prefs,
        availablePresets: BuiltinPresetsSeeder.canonicalBuiltins(),
      );
      expect(ctrl.state.activeId, BuiltinPresetIds.auto);
      expect(ctrl.state.activePreset.id, BuiltinPresetIds.auto);
      // currentConfig identical to activePreset on cold start.
      expect(ctrl.state.isModified, isFalse);
    });

    test('stored id matches available preset → restores it', () async {
      SharedPreferences.setMockInitialValues({
        'active_preset_id': BuiltinPresetIds.mp4_1080p,
      });
      final prefs = await SharedPreferences.getInstance();
      final ctrl = ActivePresetController(
        prefs: prefs,
        availablePresets: BuiltinPresetsSeeder.canonicalBuiltins(),
      );
      expect(ctrl.state.activeId, BuiltinPresetIds.mp4_1080p);
      expect(ctrl.state.activePreset.id, BuiltinPresetIds.mp4_1080p);
    });

    test('stored id missing from list → falls back to auto', () async {
      SharedPreferences.setMockInitialValues({
        'active_preset_id': 'user-uuid-deleted-elsewhere',
      });
      final prefs = await SharedPreferences.getInstance();
      final ctrl = ActivePresetController(
        prefs: prefs,
        availablePresets: BuiltinPresetsSeeder.canonicalBuiltins(),
      );
      expect(ctrl.state.activeId, BuiltinPresetIds.auto);
    });

    test('current_config JSON restored as currentConfig override',
        () async {
      final base = BuiltinPresetsSeeder.canonicalBuiltins()
          .firstWhere((p) => p.id == BuiltinPresetIds.mp4_1080p);
      final tweaked = base.copyWith(maxResolution: 720);
      SharedPreferences.setMockInitialValues({
        'active_preset_id': BuiltinPresetIds.mp4_1080p,
        'current_config': jsonEncode(tweaked.toJson()),
      });
      final prefs = await SharedPreferences.getInstance();
      final ctrl = ActivePresetController(
        prefs: prefs,
        availablePresets: BuiltinPresetsSeeder.canonicalBuiltins(),
      );
      expect(ctrl.state.activePreset.maxResolution, 1080);
      expect(ctrl.state.currentConfig.maxResolution, 720);
      expect(ctrl.state.isModified, isTrue);
    });

    test('corrupt current_config JSON → reverts to activePreset (no throw)',
        () async {
      SharedPreferences.setMockInitialValues({
        'active_preset_id': BuiltinPresetIds.mp4_1080p,
        'current_config': '{not valid json',
      });
      final prefs = await SharedPreferences.getInstance();
      final ctrl = ActivePresetController(
        prefs: prefs,
        availablePresets: BuiltinPresetsSeeder.canonicalBuiltins(),
      );
      expect(ctrl.state.activeId, BuiltinPresetIds.mp4_1080p);
      expect(ctrl.state.isModified, isFalse);
    });
  });

  group('ActivePresetController — setActive', () {
    test('switching preset clears currentConfig override', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final builtins = BuiltinPresetsSeeder.canonicalBuiltins();
      final ctrl = ActivePresetController(
        prefs: prefs,
        availablePresets: builtins,
      );

      // Start: tweak current config
      final auto = builtins.firstWhere((p) => p.id == BuiltinPresetIds.auto);
      await ctrl.updateConfig(auto.copyWith(maxResolution: 4320));
      expect(ctrl.state.isModified, isTrue);

      // Switch to MP4 1080p — currentConfig must reset to mirror new preset.
      await ctrl.setActive(BuiltinPresetIds.mp4_1080p);
      expect(ctrl.state.activeId, BuiltinPresetIds.mp4_1080p);
      expect(ctrl.state.activePreset.id, BuiltinPresetIds.mp4_1080p);
      expect(ctrl.state.currentConfig.id, BuiltinPresetIds.mp4_1080p);
      expect(ctrl.state.isModified, isFalse);

      // Persistence: stored id updated, current_config wiped.
      expect(prefs.getString('active_preset_id'), BuiltinPresetIds.mp4_1080p);
      expect(prefs.getString('current_config'), isNull);
    });

    test('unknown preset id → falls back to auto', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final ctrl = ActivePresetController(
        prefs: prefs,
        availablePresets: BuiltinPresetsSeeder.canonicalBuiltins(),
      );

      await ctrl.setActive('nonexistent-id');
      expect(ctrl.state.activeId, BuiltinPresetIds.auto);
    });
  });

  group('ActivePresetController — updateConfig & reset', () {
    test('updateConfig persists JSON snapshot', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final builtins = BuiltinPresetsSeeder.canonicalBuiltins();
      final ctrl = ActivePresetController(
        prefs: prefs,
        availablePresets: builtins,
      );

      final tweaked = ctrl.state.activePreset.copyWith(maxResolution: 4320);
      await ctrl.updateConfig(tweaked);

      expect(ctrl.state.currentConfig.maxResolution, 4320);
      expect(ctrl.state.isModified, isTrue);

      final stored = prefs.getString('current_config');
      expect(stored, isNotNull);
      final restored = FormatPresetExtended.fromJson(
        jsonDecode(stored!) as Map<String, dynamic>,
      );
      expect(restored.maxResolution, 4320);
    });

    test('reset wipes currentConfig override + JSON', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final ctrl = ActivePresetController(
        prefs: prefs,
        availablePresets: BuiltinPresetsSeeder.canonicalBuiltins(),
      );

      await ctrl.updateConfig(
        ctrl.state.activePreset.copyWith(maxResolution: 4320),
      );
      expect(prefs.getString('current_config'), isNotNull);

      await ctrl.reset();
      expect(ctrl.state.isModified, isFalse);
      expect(prefs.getString('current_config'), isNull);
    });
  });

  group('ActivePresetController — manualMode toggle', () {
    test('default state useManualMode = false (preset auto-pick mode)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final ctrl = ActivePresetController(
        prefs: prefs,
        availablePresets: BuiltinPresetsSeeder.canonicalBuiltins(),
      );
      expect(ctrl.state.useManualMode, isFalse);
    });

    test('setManualMode(true) persists across cold-load', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final ctrl = ActivePresetController(
        prefs: prefs,
        availablePresets: BuiltinPresetsSeeder.canonicalBuiltins(),
      );

      await ctrl.setManualMode(true);
      expect(ctrl.state.useManualMode, isTrue);
      expect(prefs.getBool('use_manual_mode'), isTrue);

      // Simulate cold reload — new controller reads the persisted flag.
      final ctrl2 = ActivePresetController(
        prefs: prefs,
        availablePresets: BuiltinPresetsSeeder.canonicalBuiltins(),
      );
      expect(ctrl2.state.useManualMode, isTrue);
    });

    test('setActive(presetId) auto-clears manualMode (mutually exclusive)',
        () async {
      SharedPreferences.setMockInitialValues({'use_manual_mode': true});
      final prefs = await SharedPreferences.getInstance();
      final ctrl = ActivePresetController(
        prefs: prefs,
        availablePresets: BuiltinPresetsSeeder.canonicalBuiltins(),
      );
      expect(ctrl.state.useManualMode, isTrue);

      // Picking any concrete preset = "I want auto-pick now". Toggle
      // must clear so the preset actually drives the next download
      // instead of being silently bypassed by manual mode.
      await ctrl.setActive(BuiltinPresetIds.mp4_1080p);
      expect(ctrl.state.useManualMode, isFalse);
      expect(prefs.getBool('use_manual_mode'), isFalse);
    });

    test('updateConfig preserves manualMode (popover edits orthogonal)',
        () async {
      SharedPreferences.setMockInitialValues({'use_manual_mode': true});
      final prefs = await SharedPreferences.getInstance();
      final ctrl = ActivePresetController(
        prefs: prefs,
        availablePresets: BuiltinPresetsSeeder.canonicalBuiltins(),
      );

      // Editing a popover field doesn't mean "exit manual mode".
      // Manual mode persists until the user picks a real preset OR
      // toggles it off explicitly.
      await ctrl.updateConfig(
        ctrl.state.activePreset.copyWith(maxResolution: 720),
      );
      expect(ctrl.state.useManualMode, isTrue);
    });

    test('setManualMode(same value) early-returns without write', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final ctrl = ActivePresetController(
        prefs: prefs,
        availablePresets: BuiltinPresetsSeeder.canonicalBuiltins(),
      );

      // Toggling to the SAME value shouldn't write to prefs (avoids
      // unnecessary disk churn on re-toggle from UI).
      await ctrl.setManualMode(false);
      expect(prefs.getBool('use_manual_mode'), isNull);

      await ctrl.setManualMode(true);
      expect(prefs.getBool('use_manual_mode'), isTrue);

      // Already true — second call is a no-op.
      await ctrl.setManualMode(true);
      expect(prefs.getBool('use_manual_mode'), isTrue);
    });
  });

  group('ActivePresetController — addUserPreset', () {
    test('writes new preset to format_presets store + signals callback',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var callbackFired = 0;
      final ctrl = ActivePresetController(
        prefs: prefs,
        availablePresets: BuiltinPresetsSeeder.canonicalBuiltins(),
        onListMutated: () => callbackFired++,
      );

      final newPreset = FormatPresetExtended(
        id: 'user_test_1',
        name: 'My Custom 1080p',
        isBuiltIn: false,
        maxResolution: 1080,
        videoCodec: 'h264',
        audioCodec: 'aac',
        containerFormat: 'mp4',
        fpsPreference: 'auto',
        createdAt: DateTime(2026, 5, 6),
      );
      final id = await ctrl.addUserPreset(newPreset);
      expect(id, 'user_test_1');
      expect(callbackFired, 1);

      final raw = prefs.getString('format_presets')!;
      final list = jsonDecode(raw) as List;
      final entry = list.firstWhere(
        (m) => m['id'] == 'user_test_1',
      ) as Map<String, dynamic>;
      expect(entry['name'], 'My Custom 1080p');
      expect(entry['maxResolution'], 1080);
    });

    test('duplicate id → replaces existing record (idempotent save)',
        () async {
      final original = FormatPresetExtended(
        id: 'user_test_1',
        name: 'V1',
        isBuiltIn: false,
        maxResolution: 720,
        videoCodec: 'auto',
        audioCodec: 'auto',
        containerFormat: 'mp4',
        fpsPreference: 'auto',
        createdAt: DateTime(2026, 1, 1),
      );
      SharedPreferences.setMockInitialValues({
        'format_presets': jsonEncode([original.toJson()]),
      });
      final prefs = await SharedPreferences.getInstance();
      final ctrl = ActivePresetController(
        prefs: prefs,
        availablePresets: BuiltinPresetsSeeder.canonicalBuiltins(),
      );

      final updated = original.copyWith(
        name: 'V2',
        maxResolution: 1080,
      );
      await ctrl.addUserPreset(updated);

      final raw = prefs.getString('format_presets')!;
      final list = (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      // Single record with that id — duplicate replacement.
      final matches = list.where((m) => m['id'] == 'user_test_1').toList();
      expect(matches.length, 1);
      expect(matches.first['name'], 'V2');
      expect(matches.first['maxResolution'], 1080);
    });

    test('appends to existing list without disturbing built-ins', () async {
      final builtins = BuiltinPresetsSeeder.canonicalBuiltins();
      SharedPreferences.setMockInitialValues({
        'format_presets': jsonEncode(builtins.map((p) => p.toJson()).toList()),
      });
      final prefs = await SharedPreferences.getInstance();
      final ctrl = ActivePresetController(
        prefs: prefs,
        availablePresets: builtins,
      );

      final newPreset = FormatPresetExtended(
        id: 'user_appended',
        name: 'Appended',
        isBuiltIn: false,
        maxResolution: 720,
        videoCodec: 'auto',
        audioCodec: 'auto',
        containerFormat: 'mp4',
        fpsPreference: 'auto',
        createdAt: DateTime(2026, 5, 6),
      );
      await ctrl.addUserPreset(newPreset);

      final list = (jsonDecode(prefs.getString('format_presets')!) as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      // 6 built-ins + 1 user = 7.
      expect(list.length, builtins.length + 1);
      // Built-in IDs all still present.
      for (final b in builtins) {
        expect(list.any((m) => m['id'] == b.id), isTrue);
      }
    });
  });

  group('ActivePresetController — onPresetListChanged', () {
    test('active preset still in list → no state change', () async {
      SharedPreferences.setMockInitialValues({
        'active_preset_id': BuiltinPresetIds.mp4_1080p,
      });
      final prefs = await SharedPreferences.getInstance();
      final builtins = BuiltinPresetsSeeder.canonicalBuiltins();
      final ctrl = ActivePresetController(
        prefs: prefs,
        availablePresets: builtins,
      );

      ctrl.onPresetListChanged(builtins);
      expect(ctrl.state.activeId, BuiltinPresetIds.mp4_1080p);
    });

    test('active preset removed → falls back to auto + clears persistence',
        () async {
      SharedPreferences.setMockInitialValues({
        'active_preset_id': BuiltinPresetIds.mp4_1080p,
        'current_config': jsonEncode(
          BuiltinPresetsSeeder.canonicalBuiltins()
              .firstWhere((p) => p.id == BuiltinPresetIds.mp4_1080p)
              .copyWith(maxResolution: 720)
              .toJson(),
        ),
      });
      final prefs = await SharedPreferences.getInstance();
      final ctrl = ActivePresetController(
        prefs: prefs,
        availablePresets: BuiltinPresetsSeeder.canonicalBuiltins(),
      );
      expect(ctrl.state.activeId, BuiltinPresetIds.mp4_1080p);

      // Simulate user deleting the MP4 1080p preset elsewhere — list
      // shrinks, controller must enforce Spec §5.4 fallback rule.
      final shrunken = BuiltinPresetsSeeder.canonicalBuiltins()
          .where((p) => p.id != BuiltinPresetIds.mp4_1080p)
          .toList();
      ctrl.onPresetListChanged(shrunken);

      expect(ctrl.state.activeId, BuiltinPresetIds.auto);
      expect(prefs.getString('active_preset_id'), BuiltinPresetIds.auto);
      expect(prefs.getString('current_config'), isNull);
    });
  });
}
