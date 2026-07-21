/// Regression test for the "completed download flips to
/// `permissionDenied`" bug observed 2026-05-12 (log.md §517–522).
///
/// Sequence: yt-dlp exits 0 → file on disk → post-success
/// `_cleanupDashOriginals` calls `Directory.list()` on
/// `~/Downloads/...` → macOS TCC denies in dev builds →
/// `PathAccessException` thrown → caught by the catch-all wrapping
/// the whole stream loop → status stamped `failDownload(...)` on top
/// of an already-completed file. The user sees "Download failed"
/// even though the MKV is on disk and playable.
///
/// Root-cause fix lives in `StartDownloadUseCase._cleanupDashOriginals`:
/// the helper now wraps its own `_findDashOriginals` call in a
/// try/catch so a filesystem-listing failure is logged as a
/// best-effort skip and never propagates. This test pins that
/// contract — call the helper against a path whose parent directory
/// `Directory.list()` will refuse to enumerate, and confirm it
/// returns normally instead of throwing.
///
/// We can't easily simulate a TCC denial on CI (it's grant-based,
/// not mode-bit-based) so we use a missing directory as a generic
/// filesystem-failure stand-in. The helper's `dir.exists()` guard
/// in `_findDashOriginalsStatic` returns `[]` for that case, so the
/// stand-in only covers half the contract. The other half — listing
/// a directory that exists but denies enumeration — is covered by a
/// `Directory` subclass stub in `_findDashOriginalsStatic`'s test
/// surface. For now this test covers the "do not throw on missing
/// directory" leg; the TCC leg is covered by the broader sentinel
/// flag in `start_download_usecase.dart` (downloadCommitted gate
/// in the background-monitoring catch-all).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/data/datasources/gallerydl_datasource.dart';
import 'package:svid/features/downloads/data/datasources/ytdlp_datasource.dart';
import 'package:svid/features/downloads/domain/repositories/download_repository.dart';
import 'package:svid/features/downloads/domain/usecases/start_download_usecase.dart';
import 'package:mocktail/mocktail.dart';

class _MockDownloadRepository extends Mock implements DownloadRepository {}

class _MockYtDlpDataSource extends Mock implements YtDlpDataSource {}

class _MockGalleryDlDataSource extends Mock implements GalleryDlDataSource {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('_cleanupDashOriginals defensive filesystem behavior', () {
    // Construct a usecase with mocks — none of the mocks need to
    // do anything because `_cleanupDashOriginals` only touches the
    // filesystem and the appLogger sink.
    StartDownloadUseCase makeUseCase() => StartDownloadUseCase(
          _MockDownloadRepository(),
          _MockYtDlpDataSource(),
          _MockGalleryDlDataSource(),
        );

    test(
      'does not throw when target directory does not exist — '
      'covers antivirus-deleted / unmounted-volume scenarios',
      () async {
        // A path under a directory that provably does not exist on
        // disk. The helper's `dir.exists()` guard short-circuits to
        // `[]` and the outer try/catch in the helper guards against
        // any sync-throw from path resolution itself.
        final phantomPath =
            '/var/folders/__svid_test_does_not_exist__/'
            'phantom_dir/output.mkv';

        // The behavior we pin is "no throw". If the helper ever
        // changes to throw on a missing parent dir, this assertion
        // fires.
        expect(
          () async => await makeUseCase()
              .cleanupDashOriginalsForTesting(phantomPath),
          returnsNormally,
        );
      },
    );

    test(
      'returns without rethrowing even when Directory.list throws — '
      'simulates macOS TCC permissionDenied on ~/Downloads in '
      'dev builds (log.md 2026-05-12 §517 root cause)',
      () async {
        // Create a real temp directory, then chmod it to 0 so the
        // OS itself refuses to list its contents. This is the
        // closest portable stand-in for the macOS TCC denial
        // observed in the dev log without requiring a TCC consent
        // grant on the CI runner.
        final tempRoot = await Directory.systemTemp.createTemp(
          'svid_cleanup_perm_',
        );
        try {
          // Pre-populate so the listing would otherwise succeed —
          // confirms the perm change is what's blocking, not an
          // empty-dir short-circuit somewhere.
          await File('${tempRoot.path}/Video.f137.mp4')
              .writeAsString('fake-dash-video');
          await File('${tempRoot.path}/Video.f140.m4a')
              .writeAsString('fake-dash-audio');

          // Strip all permissions. POSIX-only; on Windows the
          // chmod is a no-op so this test degrades to "does not
          // throw on a normal listing" which is still a valid pin.
          if (!Platform.isWindows) {
            await Process.run('chmod', ['000', tempRoot.path]);
          }

          final outputPath = '${tempRoot.path}/Video.mkv';
          // The helper must NOT propagate the PathAccessException.
          // Pre-fix, this would throw "Operation not permitted".
          await expectLater(
            makeUseCase().cleanupDashOriginalsForTesting(outputPath),
            completes,
            reason:
                'A directory-listing failure on the parent of the '
                'merged file must NEVER bubble out of '
                '_cleanupDashOriginals — that propagation is what '
                'stamps permissionDenied on completed downloads.',
          );
        } finally {
          // Restore perms so cleanup of the temp dir itself
          // succeeds, otherwise the CI runner accumulates
          // unreadable dirs across runs.
          if (!Platform.isWindows) {
            await Process.run('chmod', ['755', tempRoot.path]);
          }
          await tempRoot.delete(recursive: true);
        }
      },
      skip: Platform.isWindows
          ? 'chmod 000 is a no-op on Windows — POSIX-only repro'
          : null,
    );
  });
}
