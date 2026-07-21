import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:svid/core/config/brand_download_path_resolver.dart';

/// Unit tests for [BrandDownloadPathResolver.detectVidComboLegacyFolder].
///
/// Regression guard for production feedback #78 — "All the music that i had
/// download before the new update 1.7.0 ... all gone or hid somewhere". Root
/// cause: the resolver was added in commit e74a1af2 but never wired into
/// [SettingsNotifier._init], so legacy ObjectBox VidCombo folders were
/// invisible to the rewritten 1.7.x app and the default fell through to a
/// fresh `~/Downloads` system folder.
///
/// These tests cover the probe logic in isolation against temp directories.
/// The wiring itself is verified by manual smoke + production observability.
void main() {
  late Directory tempRoot;
  late Directory fakeHome;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('vidcombo_resolver_test_');
    fakeHome = Directory(p.join(tempRoot.path, 'home'));
    await fakeHome.create(recursive: true);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Future<Directory> mkdir(String path) async {
    final dir = Directory(path);
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> writeMedia(Directory dir, String filename) async {
    await File(p.join(dir.path, filename)).writeAsString('stub');
  }

  group('detectVidComboLegacyFolder — empty / missing home', () {
    test('returns null when homeOverride is empty', () async {
      final resolver = const BrandDownloadPathResolver();
      final result = await resolver.detectVidComboLegacyFolder(
        homeOverride: '',
      );
      expect(result, isNull);
    });

    test(
      'returns null when no candidate directory exists under home',
      () async {
        final resolver = const BrandDownloadPathResolver();
        final result = await resolver.detectVidComboLegacyFolder(
          homeOverride: fakeHome.path,
        );
        expect(result, isNull);
      },
    );

    test(
      'returns null when candidate directory exists but has no media',
      () async {
        // Empty folder doesn't qualify — must have at least one media file
        // matching `_legacyMediaExts`. Prevents matching a stale empty
        // folder left over from an old install + manual cleanup.
        await mkdir(p.join(fakeHome.path, 'Documents', 'VidCombo'));
        final resolver = const BrandDownloadPathResolver();
        final result = await resolver.detectVidComboLegacyFolder(
          homeOverride: fakeHome.path,
        );
        expect(result, isNull);
      },
    );
  });

  group('detectVidComboLegacyFolder — primary candidates', () {
    test('detects ~/Documents/VidCombo when it has media', () async {
      final docs = await mkdir(p.join(fakeHome.path, 'Documents', 'VidCombo'));
      await writeMedia(docs, 'song.mp3');
      final resolver = const BrandDownloadPathResolver();
      final result = await resolver.detectVidComboLegacyFolder(
        homeOverride: fakeHome.path,
      );
      expect(result, docs.path);
    });

    test('detects ~/Downloads/VidCombo when it has media', () async {
      final dl = await mkdir(p.join(fakeHome.path, 'Downloads', 'VidCombo'));
      await writeMedia(dl, 'clip.mp4');
      final resolver = const BrandDownloadPathResolver();
      final result = await resolver.detectVidComboLegacyFolder(
        homeOverride: fakeHome.path,
      );
      expect(result, dl.path);
    });

    test('detects ~/Downloads/VidCombo App Downloader variant', () async {
      // Older BLUEBYTE installs used this longer folder name.
      final legacy = await mkdir(
        p.join(fakeHome.path, 'Downloads', 'VidCombo App Downloader'),
      );
      await writeMedia(legacy, 'video.mkv');
      final resolver = const BrandDownloadPathResolver();
      final result = await resolver.detectVidComboLegacyFolder(
        homeOverride: fakeHome.path,
      );
      expect(result, legacy.path);
    });
  });

  group('detectVidComboLegacyFolder — cloud-provider variants', () {
    test('detects ~/Dropbox/VidCombo when present', () async {
      final dropbox = await mkdir(p.join(fakeHome.path, 'Dropbox', 'VidCombo'));
      await writeMedia(dropbox, 'audio.m4a');
      final resolver = const BrandDownloadPathResolver();
      final result = await resolver.detectVidComboLegacyFolder(
        homeOverride: fakeHome.path,
      );
      expect(result, dropbox.path);
    });

    test('detects nested ~/Google Drive/Downloads/VidCombo', () async {
      final gdrive = await mkdir(
        p.join(fakeHome.path, 'Google Drive', 'Downloads', 'VidCombo'),
      );
      await writeMedia(gdrive, 'song.flac');
      final resolver = const BrandDownloadPathResolver();
      final result = await resolver.detectVidComboLegacyFolder(
        homeOverride: fakeHome.path,
      );
      expect(result, gdrive.path);
    });
  });

  group('detectVidComboLegacyFolder — OneDrive override', () {
    test('detects OneDrive-redirected Documents/VidCombo', () async {
      // Windows OneDrive often redirects Documents/Downloads; the resolver
      // must check the OneDrive root in addition to USERPROFILE.
      final oneDrive = Directory(p.join(tempRoot.path, 'OneDrive'));
      await oneDrive.create(recursive: true);
      final docs = await mkdir(p.join(oneDrive.path, 'Documents', 'VidCombo'));
      await writeMedia(docs, 'tune.mp3');
      final resolver = const BrandDownloadPathResolver();
      final result = await resolver.detectVidComboLegacyFolder(
        homeOverride: fakeHome.path,
        oneDriveOverride: oneDrive.path,
      );
      expect(result, docs.path);
    });

    test(
      'ignores empty oneDriveOverride and falls through to home probe',
      () async {
        final dl = await mkdir(p.join(fakeHome.path, 'Downloads', 'VidCombo'));
        await writeMedia(dl, 'clip.webm');
        final resolver = const BrandDownloadPathResolver();
        final result = await resolver.detectVidComboLegacyFolder(
          homeOverride: fakeHome.path,
          oneDriveOverride: '',
        );
        expect(result, dl.path);
      },
    );
  });

  group('detectVidComboLegacyFolder — pick the most populated', () {
    test(
      'returns the candidate with the most media files when multiple exist',
      () async {
        // Documents has 1 file, Downloads has 3 → Downloads wins.
        final docs = await mkdir(p.join(fakeHome.path, 'Documents', 'VidCombo'));
        await writeMedia(docs, 'a.mp3');
        final dl = await mkdir(p.join(fakeHome.path, 'Downloads', 'VidCombo'));
        await writeMedia(dl, 'a.mp4');
        await writeMedia(dl, 'b.mkv');
        await writeMedia(dl, 'c.opus');
        final resolver = const BrandDownloadPathResolver();
        final result = await resolver.detectVidComboLegacyFolder(
          homeOverride: fakeHome.path,
        );
        expect(result, dl.path);
      },
    );

    test('ignores non-media files when counting populated-ness', () async {
      // Folder with only README.txt should NOT be picked even though it
      // exists. Matches importer expectation: confirm "live" content first.
      final docs = await mkdir(p.join(fakeHome.path, 'Documents', 'VidCombo'));
      await File(p.join(docs.path, 'README.txt')).writeAsString('notes');
      await File(p.join(docs.path, 'settings.json')).writeAsString('{}');

      final dl = await mkdir(p.join(fakeHome.path, 'Downloads', 'VidCombo'));
      await writeMedia(dl, 'real_media.mp4');

      final resolver = const BrandDownloadPathResolver();
      final result = await resolver.detectVidComboLegacyFolder(
        homeOverride: fakeHome.path,
      );
      expect(result, dl.path);
    });
  });
}
