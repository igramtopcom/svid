import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/features/downloads/domain/entities/download_selection_intent.dart';
import 'package:svid/features/settings/data/datasources/settings_local_datasource.dart';
import 'package:svid/features/settings/data/repositories/settings_repository_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Settings download intent persistence', () {
    test('loads explicit default download intent fields', () async {
      SharedPreferences.setMockInitialValues({
        'settings_download_path': '/tmp',
        'settings_default_download_file_type': 'audio',
        'settings_default_download_quality_intent': 'specific',
        'settings_default_download_quality_target': jsonEncode({
          'fileType': 'audio',
          'outputFormat': 'mp3',
          'targetBitrateKbps': 192,
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = SettingsRepositoryImpl(SettingsLocalDatasource(prefs));

      final settings = await repo.loadSettings();

      expect(settings, isNotNull);
      expect(settings!.defaultDownloadFileType, DownloadFileType.audio);
      expect(
        settings.defaultDownloadQualityIntent,
        DownloadQualityIntent.specific,
      );
      expect(settings.defaultDownloadQualityTarget?.outputFormat, 'mp3');
      expect(settings.defaultDownloadQualityTarget?.targetBitrateKbps, 192);
    });

    test(
      'maps legacy preferredQuality to new default intent when absent',
      () async {
        SharedPreferences.setMockInitialValues({
          'settings_download_path': '/tmp',
          'settings_preferred_quality': 'p720',
        });
        final prefs = await SharedPreferences.getInstance();
        final repo = SettingsRepositoryImpl(SettingsLocalDatasource(prefs));

        final settings = await repo.loadSettings();

        expect(settings, isNotNull);
        expect(settings!.defaultDownloadFileType, DownloadFileType.video);
        expect(
          settings.defaultDownloadQualityIntent,
          DownloadQualityIntent.specific,
        );
        expect(
          settings.defaultDownloadQualityTarget,
          const PortableQualityTarget.video(targetHeight: 720),
        );
      },
    );
  });

  group('Settings system PiP persistence', () {
    test(
      'defaults system PiP to enabled for existing out-app behavior',
      () async {
        SharedPreferences.setMockInitialValues({
          'settings_download_path': '/tmp',
        });
        final prefs = await SharedPreferences.getInstance();
        final repo = SettingsRepositoryImpl(SettingsLocalDatasource(prefs));

        final settings = await repo.loadSettings();

        expect(settings, isNotNull);
        expect(settings!.systemPipEnabled, isTrue);
      },
    );

    test('loads canonical system PiP preference', () async {
      SharedPreferences.setMockInitialValues({
        'settings_download_path': '/tmp',
        'settings_system_pip_enabled': false,
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = SettingsRepositoryImpl(SettingsLocalDatasource(prefs));

      final settings = await repo.loadSettings();

      expect(settings, isNotNull);
      expect(settings!.systemPipEnabled, isFalse);
    });

    test('loads legacy current-branch system PiP key as fallback', () async {
      SharedPreferences.setMockInitialValues({
        'settings_download_path': '/tmp',
        'system_pip_enabled': false,
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = SettingsRepositoryImpl(SettingsLocalDatasource(prefs));

      final settings = await repo.loadSettings();

      expect(settings, isNotNull);
      expect(settings!.systemPipEnabled, isFalse);
    });
  });
}
