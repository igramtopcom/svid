import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssvid/features/downloads/data/datasources/download_native_datasource.dart';
import 'package:ssvid/features/settings/data/datasources/settings_local_datasource.dart';

void main() {
  group('Task 68.2: Multi-Segment Parallel Download', () {
    group('DownloadNativeDataSource — numSegments parameter', () {
      test('startDownload accepts numSegments parameter', () {
        final ds = DownloadNativeDataSource();
        expect(
          () => ds.startDownload(
            nativeId: 'test-id',
            url: 'https://example.com/video.mp4',
            outputPath: '/tmp/video.mp4',
            numSegments: 4,
          ),
          throwsA(anything), // RustLib not initialized
        );
      });

      test('startDownload accepts numSegments=1 (single stream)', () {
        final ds = DownloadNativeDataSource();
        expect(
          () => ds.startDownload(
            nativeId: 'test-id',
            url: 'https://example.com/video.mp4',
            outputPath: '/tmp/video.mp4',
            numSegments: 1,
          ),
          throwsA(anything), // RustLib not initialized
        );
      });

      test('startDownload accepts null numSegments (default)', () {
        final ds = DownloadNativeDataSource();
        expect(
          () => ds.startDownload(
            nativeId: 'test-id',
            url: 'https://example.com/video.mp4',
            outputPath: '/tmp/video.mp4',
            numSegments: null,
          ),
          throwsA(anything), // RustLib not initialized
        );
      });

      test('startDownload accepts numSegments=16 (max)', () {
        final ds = DownloadNativeDataSource();
        expect(
          () => ds.startDownload(
            nativeId: 'test-id',
            url: 'https://example.com/video.mp4',
            outputPath: '/tmp/video.mp4',
            numSegments: 16,
          ),
          throwsA(anything), // RustLib not initialized
        );
      });

      test('startDownload accepts numSegments with other params', () {
        final ds = DownloadNativeDataSource();
        expect(
          () => ds.startDownload(
            nativeId: 'test-id',
            url: 'https://example.com/video.mp4',
            outputPath: '/tmp/video.mp4',
            resumeOffset: 5000,
            maxSpeedBytes: 1048576,
            numSegments: 4,
          ),
          throwsA(anything), // RustLib not initialized
        );
      });
    });

    group('SettingsLocalDatasource — maxSegments', () {
      late SettingsLocalDatasource datasource;

      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        datasource = SettingsLocalDatasource(prefs);
      });

      test('getMaxSegments returns default 4', () {
        expect(datasource.getMaxSegments(), 4);
      });

      test('saveMaxSegments persists value', () async {
        await datasource.saveMaxSegments(8);
        expect(datasource.getMaxSegments(), 8);
      });

      test('saveMaxSegments clamps to minimum 1', () async {
        await datasource.saveMaxSegments(0);
        expect(datasource.getMaxSegments(), 1);
      });

      test('saveMaxSegments clamps to maximum 16', () async {
        await datasource.saveMaxSegments(32);
        expect(datasource.getMaxSegments(), 16);
      });

      test('saveMaxSegments clamps negative to 1', () async {
        await datasource.saveMaxSegments(-5);
        expect(datasource.getMaxSegments(), 1);
      });

      test('saveMaxSegments accepts exact boundaries', () async {
        await datasource.saveMaxSegments(1);
        expect(datasource.getMaxSegments(), 1);

        await datasource.saveMaxSegments(16);
        expect(datasource.getMaxSegments(), 16);
      });

      test('saveMaxSegments overwrites previous value', () async {
        await datasource.saveMaxSegments(4);
        expect(datasource.getMaxSegments(), 4);

        await datasource.saveMaxSegments(8);
        expect(datasource.getMaxSegments(), 8);
      });
    });

    group('DownloadNativeDataSource.generateNativeId — segmented consistency',
        () {
      test('same url+filename always produces same ID (segment-safe)', () {
        // Multi-segment downloads need deterministic IDs
        final id1 = DownloadNativeDataSource.generateNativeId(
          'https://cdn.example.com/large-file.mp4',
          'large-file.mp4',
        );
        final id2 = DownloadNativeDataSource.generateNativeId(
          'https://cdn.example.com/large-file.mp4',
          'large-file.mp4',
        );
        expect(id1, equals(id2));
      });

      test('different files produce different IDs', () {
        final id1 = DownloadNativeDataSource.generateNativeId(
          'https://cdn.example.com/video1.mp4',
          'video1.mp4',
        );
        final id2 = DownloadNativeDataSource.generateNativeId(
          'https://cdn.example.com/video2.mp4',
          'video2.mp4',
        );
        expect(id1, isNot(equals(id2)));
      });
    });
  });
}
