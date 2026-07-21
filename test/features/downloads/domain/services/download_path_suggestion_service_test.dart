import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/config/brand_config.dart';
import 'package:ssvid/core/errors/app_exception.dart';
import 'package:ssvid/core/utils/platform_detector.dart';
import 'package:ssvid/features/downloads/domain/entities/video_info.dart';
import 'package:ssvid/features/downloads/domain/services/download_path_suggestion_service.dart';

void main() {
  late DownloadPathSuggestionService service;

  setUp(() {
    service = DownloadPathSuggestionService();
  });

  group('suggestSubdirectory', () {
    test('youtube + video → "YouTube Videos"', () {
      expect(
        service.suggestSubdirectory(VideoPlatform.youtube, MediaType.video),
        'YouTube Videos',
      );
    });

    test('youtube + audio → "YouTube Music"', () {
      expect(
        service.suggestSubdirectory(VideoPlatform.youtube, MediaType.audio),
        'YouTube Music',
      );
    });

    test('tiktok + video → "TikTok Videos"', () {
      expect(
        service.suggestSubdirectory(VideoPlatform.tiktok, MediaType.video),
        'TikTok Videos',
      );
    });

    test('instagram + image → "Instagram Photos"', () {
      expect(
        service.suggestSubdirectory(VideoPlatform.instagram, MediaType.image),
        'Instagram Photos',
      );
    });

    test('soundcloud + audio → "SoundCloud Music"', () {
      expect(
        service.suggestSubdirectory(VideoPlatform.soundcloud, MediaType.audio),
        'SoundCloud Music',
      );
    });

    test('unknown + video → "Videos"', () {
      expect(
        service.suggestSubdirectory(VideoPlatform.unknown, MediaType.video),
        'Videos',
      );
    });

    test('unknown + audio → "Music"', () {
      expect(
        service.suggestSubdirectory(VideoPlatform.unknown, MediaType.audio),
        'Music',
      );
    });

    test('unknown + image → "Images"', () {
      expect(
        service.suggestSubdirectory(VideoPlatform.unknown, MediaType.image),
        'Images',
      );
    });
  });

  group('resolveAndCreate', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('path_suggestion_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('creates directory with brand folder and subdirectory', () async {
      final result = await service.resolveAndCreate(
        tempDir.path,
        'YouTube Videos',
      );

      // Brand folder name is stamped at runtime via BrandConfig.current.appName
      // — must read it the same way the production service does so the test
      // passes under both BRAND=ssvid and BRAND=vidcombo.
      expect(result, contains('${BrandConfig.current.appName} App Downloader'));
      expect(result, contains('YouTube Videos'));
      expect(Directory(result).existsSync(), isTrue);
    });

    test('is idempotent — no error on repeated calls', () async {
      final result1 = await service.resolveAndCreate(
        tempDir.path,
        'YouTube Videos',
      );
      final result2 = await service.resolveAndCreate(
        tempDir.path,
        'YouTube Videos',
      );

      expect(result1, result2);
    });

    test('throws AppException.permission on FileSystemException', () async {
      // Use a directoryFactory that always throws
      Future<String> call() => service.resolveAndCreate(
        tempDir.path,
        'Test',
        directoryFactory: (path) => _ThrowingDirectory(path),
      );

      expect(call, throwsA(isA<AppException>()));
    });
  });

  group('buildOutputPath', () {
    test('returns the same final path used by resolveAndCreate', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'path_suggestion_test_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final outputPath = service.buildOutputPath(
        tempDir.path,
        'Instagram Photos',
      );
      final createdPath = await service.resolveAndCreate(
        tempDir.path,
        'Instagram Photos',
      );

      expect(outputPath, createdPath);
      // Brand-aware assertion — pre-fix this hardcoded
      // `'SSvid App Downloader'`, so a VidCombo test run would
      // fail even though the production code was correct (the
      // legacy `static const brandFolder = 'SSvid App Downloader'`
      // happened to match the literal). Pulling from
      // `BrandConfig.current.appName` keeps the test paired with
      // the real branding contract.
      expect(
        outputPath,
        contains('${BrandConfig.current.appName} App Downloader'),
      );
      expect(outputPath, contains('Instagram Photos'));
    });
  });

  group('brandFolder', () {
    test('matches BrandConfig.current.appName', () {
      expect(
        DownloadPathSuggestionService.brandFolder,
        '${BrandConfig.current.appName} App Downloader',
      );
    });

    test('SSvid build produces "SSvid App Downloader"', () {
      // Build-time invariant: when the current build is the SSvid
      // brand, the folder is "SSvid App Downloader". This test plus
      // its VidCombo sibling form the matched-pair guard against
      // a future regression to a hardcoded literal.
      if (BrandConfig.current.brand != Brand.ssvid) return;
      expect(
        DownloadPathSuggestionService.brandFolder,
        'SSvid App Downloader',
      );
    });

    test('VidCombo build produces "VidCombo App Downloader"', () {
      // Build-time invariant. Before the brand-aware getter, this
      // value was the literal "SSvid App Downloader" even on
      // VidCombo builds, leaving VidCombo testers with downloads
      // under an SSvid-named folder.
      if (BrandConfig.current.brand != Brand.vidcombo) return;
      expect(
        DownloadPathSuggestionService.brandFolder,
        'VidCombo App Downloader',
      );
    });

    test(
      'buildOutputPath embeds the branded folder between basePath and subdirectory',
      () {
        // Pinning the path SHAPE — basePath / brand folder /
        // subdirectory — keeps the on-disk layout stable across
        // brands and makes the brand swap visible in tests rather
        // than only at runtime.
        final out = service.buildOutputPath('/tmp/downloads', 'YouTube Videos');
        expect(
          out,
          '/tmp/downloads/${BrandConfig.current.appName} App Downloader/YouTube Videos',
        );
      },
    );
  });
}

/// A Directory stub that throws FileSystemException on create().
class _ThrowingDirectory implements Directory {
  _ThrowingDirectory(this._path);
  final String _path;

  @override
  String get path => _path;

  @override
  Future<Directory> create({bool recursive = false}) {
    throw const FileSystemException('Permission denied');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
