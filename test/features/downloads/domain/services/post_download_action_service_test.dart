import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/errors/result.dart';
import 'package:svid/features/downloads/domain/entities/download_entity.dart';
import 'package:svid/features/downloads/domain/entities/download_status.dart';
import 'package:svid/features/downloads/domain/entities/post_download_action.dart';
import 'package:svid/features/downloads/domain/services/post_download_action_service.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

DownloadEntity _makeDownload({
  String savePath = '/tmp',
  String filename = 'test_video.mp4',
}) {
  return DownloadEntity(
    id: 1,
    url: 'https://example.com/video.mp4',
    title: 'Test Video',
    status: DownloadStatus.completed,
    savePath: savePath,
    filename: filename,
    totalBytes: 1024,
    downloadedBytes: 1024,
    speed: 0,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

ProcessResult _successResult() => ProcessResult(0, 0, '', '');

ProcessResult _failResult(int exitCode) =>
    ProcessResult(0, exitCode, '', 'error');

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PostDownloadActionService', () {
    group('none action', () {
      test('returns Success without calling ProcessRunner', () async {
        var called = false;
        final svc = PostDownloadActionService(
          processRunner: (_, __) async {
            called = true;
            return _successResult();
          },
        );
        final download = _makeDownload();

        final result = await svc.executeAction(download, PostDownloadAction.none);

        expect(result.isSuccess, isTrue);
        expect(called, isFalse);
      });
    });

    group('file not found', () {
      test('returns Failure when file does not exist', () async {
        final svc = PostDownloadActionService(
          processRunner: (_, __) async => _successResult(),
        );
        final download = _makeDownload(
          savePath: '/nonexistent_dir_abc123',
          filename: 'ghost.mp4',
        );

        final result =
            await svc.executeAction(download, PostDownloadAction.openFile);

        expect(result.isFailure, isTrue);
        expect(result.exceptionOrNull.toString(), contains('File not found'));
      });
    });

    group('openFile action', () {
      test('calls process runner with file path', () async {
        final tmpFile = await File('/tmp/svid_test_open.mp4').create();
        try {
          String? capturedExecutable;
          List<String>? capturedArgs;
          final svc = PostDownloadActionService(
            processRunner: (exe, args) async {
              capturedExecutable = exe;
              capturedArgs = args;
              return _successResult();
            },
          );
          final download =
              _makeDownload(savePath: '/tmp', filename: 'svid_test_open.mp4');

          final result =
              await svc.executeAction(download, PostDownloadAction.openFile);

          expect(result.isSuccess, isTrue);
          expect(capturedExecutable, isNotNull);
          expect(capturedArgs!.join(' '), contains('svid_test_open.mp4'));
        } finally {
          await tmpFile.delete().catchError((_) => File(''));
        }
      });

      test('returns Failure when process exits with code > 1', () async {
        final tmpFile = await File('/tmp/svid_test_fail.mp4').create();
        try {
          final svc = PostDownloadActionService(
            processRunner: (_, __) async => _failResult(2),
          );
          final download =
              _makeDownload(savePath: '/tmp', filename: 'svid_test_fail.mp4');

          final result =
              await svc.executeAction(download, PostDownloadAction.openFile);

          expect(result.isFailure, isTrue);
        } finally {
          await tmpFile.delete().catchError((_) => File(''));
        }
      });

      test('exit code 1 is acceptable (macOS open -R quirk)', () async {
        final tmpFile = await File('/tmp/svid_test_ec1.mp4').create();
        try {
          final svc = PostDownloadActionService(
            processRunner: (_, __) async => _failResult(1),
          );
          final download =
              _makeDownload(savePath: '/tmp', filename: 'svid_test_ec1.mp4');

          final result =
              await svc.executeAction(download, PostDownloadAction.openFile);

          expect(result.isSuccess, isTrue);
        } finally {
          await tmpFile.delete().catchError((_) => File(''));
        }
      });
    });

    group('openFolder action', () {
      test('calls process runner for folder reveal', () async {
        final tmpFile = await File('/tmp/svid_test_folder.mp4').create();
        try {
          String? capturedExecutable;
          final svc = PostDownloadActionService(
            processRunner: (exe, args) async {
              capturedExecutable = exe;
              return _successResult();
            },
          );
          final download = _makeDownload(
              savePath: '/tmp', filename: 'svid_test_folder.mp4');

          final result =
              await svc.executeAction(download, PostDownloadAction.openFolder);

          expect(result.isSuccess, isTrue);
          expect(capturedExecutable, isNotNull);
        } finally {
          await tmpFile.delete().catchError((_) => File(''));
        }
      });
    });

    group('moveToFolder action', () {
      test('returns Failure when targetFolder is null', () async {
        final tmpFile = await File('/tmp/svid_test_move.mp4').create();
        try {
          final svc = PostDownloadActionService(
            processRunner: (_, __) async => _successResult(),
          );
          final download =
              _makeDownload(savePath: '/tmp', filename: 'svid_test_move.mp4');

          final result = await svc.executeAction(
            download,
            PostDownloadAction.moveToFolder,
            targetFolder: null,
          );

          expect(result.isFailure, isTrue);
          expect(result.exceptionOrNull.toString(),
              contains('Target folder not configured'));
        } finally {
          await tmpFile.delete().catchError((_) => File(''));
        }
      });

      test('returns Failure when targetFolder is empty string', () async {
        final tmpFile =
            await File('/tmp/svid_test_moveempty.mp4').create();
        try {
          final svc = PostDownloadActionService(
            processRunner: (_, __) async => _successResult(),
          );
          final download = _makeDownload(
              savePath: '/tmp', filename: 'svid_test_moveempty.mp4');

          final result = await svc.executeAction(
            download,
            PostDownloadAction.moveToFolder,
            targetFolder: '',
          );

          expect(result.isFailure, isTrue);
        } finally {
          await tmpFile.delete().catchError((_) => File(''));
        }
      });

      test('copies file to target folder and deletes original', () async {
        final tmpDir =
            await Directory.systemTemp.createTemp('svid_move_');
        final srcFile = await File('${tmpDir.path}/src.mp4').create();
        final destDir =
            await Directory('${tmpDir.path}/dest').create();
        try {
          final svc = PostDownloadActionService(
            processRunner: (_, __) async => _successResult(),
          );
          final download =
              _makeDownload(savePath: tmpDir.path, filename: 'src.mp4');

          final result = await svc.executeAction(
            download,
            PostDownloadAction.moveToFolder,
            targetFolder: destDir.path,
          );

          expect(result.isSuccess, isTrue);
          expect(await File('${destDir.path}/src.mp4').exists(), isTrue);
          expect(await srcFile.exists(), isFalse);
        } finally {
          await tmpDir.delete(recursive: true).catchError((_) async => tmpDir);
        }
      });

      test('deleteAfterMove uses same move logic', () async {
        final tmpDir =
            await Directory.systemTemp.createTemp('svid_del_');
        await File('${tmpDir.path}/src2.mp4').create();
        final destDir =
            await Directory('${tmpDir.path}/dest2').create();
        try {
          final svc = PostDownloadActionService(
            processRunner: (_, __) async => _successResult(),
          );
          final download =
              _makeDownload(savePath: tmpDir.path, filename: 'src2.mp4');

          final result = await svc.executeAction(
            download,
            PostDownloadAction.deleteAfterMove,
            targetFolder: destDir.path,
          );

          expect(result.isSuccess, isTrue);
          expect(
              await File('${destDir.path}/src2.mp4').exists(), isTrue);
        } finally {
          await tmpDir
              .delete(recursive: true)
              .catchError((_) async => tmpDir);
        }
      });
    });

    group('ProcessRunner injection', () {
      test('default constructor uses Process.run (no crash)', () {
        final svc = PostDownloadActionService();
        expect(svc, isNotNull);
      });

      test('custom processRunner is called for openFile', () async {
        var callCount = 0;
        final tmpFile =
            await File('/tmp/svid_injection.mp4').create();
        try {
          final svc = PostDownloadActionService(
            processRunner: (_, __) async {
              callCount++;
              return _successResult();
            },
          );
          final download = _makeDownload(
              savePath: '/tmp', filename: 'svid_injection.mp4');

          await svc.executeAction(download, PostDownloadAction.openFile);

          expect(callCount, equals(1));
        } finally {
          await tmpFile.delete().catchError((_) => File(''));
        }
      });
    });

    group('PostDownloadAction enum', () {
      test('has 5 values', () {
        expect(PostDownloadAction.values.length, equals(5));
      });

      test('none is the first/default value', () {
        expect(PostDownloadAction.values.first, equals(PostDownloadAction.none));
      });

      test('all enum names are non-empty', () {
        for (final action in PostDownloadAction.values) {
          expect(action.name, isNotEmpty);
        }
      });
    });
  });
}
