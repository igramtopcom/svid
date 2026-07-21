import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/features/settings/data/datasources/settings_local_datasource.dart';

void main() {
  group('SettingsLocalDatasource — Advanced Options', () {
    late SettingsLocalDatasource datasource;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      datasource = SettingsLocalDatasource(prefs);
    });

    // ==================== NETWORK TUNING ====================

    group('socketTimeout', () {
      test('returns default 30 when not set', () {
        expect(datasource.getSocketTimeout(), 30);
      });

      test('saves and retrieves value', () async {
        await datasource.saveSocketTimeout(60);
        expect(datasource.getSocketTimeout(), 60);
      });
    });

    group('maxRetries', () {
      test('returns default 3 when not set', () {
        expect(datasource.getMaxRetries(), 3);
      });

      test('saves and retrieves value', () async {
        await datasource.saveMaxRetries(7);
        expect(datasource.getMaxRetries(), 7);
      });
    });

    group('httpChunkSizeMb', () {
      test('returns default 10 when not set', () {
        expect(datasource.getHttpChunkSizeMb(), 10);
      });

      test('saves and retrieves value', () async {
        await datasource.saveHttpChunkSizeMb(25);
        expect(datasource.getHttpChunkSizeMb(), 25);
      });
    });

    // ==================== FILENAME TEMPLATE ====================

    group('filenameTemplate', () {
      test('returns default template when not set', () {
        expect(datasource.getFilenameTemplate(), '%(title)s.%(ext)s');
      });

      test('saves and retrieves custom template', () async {
        await datasource.saveFilenameTemplate('%(title)s - %(uploader)s.%(ext)s');
        expect(datasource.getFilenameTemplate(), '%(title)s - %(uploader)s.%(ext)s');
      });
    });

    // ==================== CUSTOM POSTPROCESSOR ARGS ====================

    group('customPostprocessorArgs', () {
      test('returns empty string when not set', () {
        expect(datasource.getCustomPostprocessorArgs(), '');
      });

      test('saves and retrieves args', () async {
        await datasource.saveCustomPostprocessorArgs('-ac 2 -ar 44100');
        expect(datasource.getCustomPostprocessorArgs(), '-ac 2 -ar 44100');
      });

      test('removes key when empty string is saved', () async {
        await datasource.saveCustomPostprocessorArgs('-ac 2');
        expect(datasource.getCustomPostprocessorArgs(), '-ac 2');

        await datasource.saveCustomPostprocessorArgs('');
        expect(datasource.getCustomPostprocessorArgs(), '');
      });
    });

    // ==================== CLEAR ALL ====================

    group('clearAll', () {
      test('clears all advanced options', () async {
        await datasource.saveSocketTimeout(90);
        await datasource.saveMaxRetries(5);
        await datasource.saveHttpChunkSizeMb(20);
        await datasource.saveFilenameTemplate('%(id)s.%(ext)s');
        await datasource.saveCustomPostprocessorArgs('-ac 2');

        await datasource.clearAll();

        expect(datasource.getSocketTimeout(), 30);
        expect(datasource.getMaxRetries(), 3);
        expect(datasource.getHttpChunkSizeMb(), 10);
        expect(datasource.getFilenameTemplate(), '%(title)s.%(ext)s');
        expect(datasource.getCustomPostprocessorArgs(), '');
      });
    });
  });
}
