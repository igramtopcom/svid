import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../core/errors/app_exception.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/logging/app_logger.dart';
import '../entities/download_entity.dart';
import '../entities/post_download_action.dart';

/// Injectable function type for running system processes.
typedef ProcessRunner = Future<ProcessResult> Function(
    String executable, List<String> arguments);

/// Executes the configured post-download action for a completed download.
///
/// Pure Dart — no Flutter dependencies. Inject [processRunner] for testing.
class PostDownloadActionService {
  static const _processTimeout = Duration(seconds: 5);

  final ProcessRunner _processRunner;

  PostDownloadActionService({ProcessRunner? processRunner})
      : _processRunner = processRunner ?? Process.run;

  /// Execute [action] for the given [download].
  ///
  /// [targetFolder] is required when action is [PostDownloadAction.moveToFolder]
  /// or [PostDownloadAction.deleteAfterMove].
  Future<Result<void>> executeAction(
    DownloadEntity download,
    PostDownloadAction action, {
    String? targetFolder,
  }) async {
    if (action == PostDownloadAction.none) return const Success(null);

    final filePath = _resolvedPath(download);
    if (!await File(filePath).exists()) {
      return Result.failure(
          AppException.unknown(message: 'File not found: $filePath'));
    }

    try {
      switch (action) {
        case PostDownloadAction.none:
          return const Success(null);
        case PostDownloadAction.openFile:
          return _openFile(filePath);
        case PostDownloadAction.openFolder:
          return _openFolder(filePath);
        case PostDownloadAction.moveToFolder:
        case PostDownloadAction.deleteAfterMove:
          if (targetFolder == null || targetFolder.isEmpty) {
            return Result.failure(
                AppException.unknown(message: 'Target folder not configured'));
          }
          return _moveToFolder(filePath, targetFolder);
      }
    } catch (e) {
      appLogger.error('Post-download action failed', e);
      return Result.failure(AppException.unknown(message: e.toString()));
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  String _resolvedPath(DownloadEntity download) {
    return '${download.savePath}/${download.filename}';
  }

  Future<Result<void>> _openFile(String filePath) => _runCommand(filePath, openFileArgs: true);

  Future<Result<void>> _openFolder(String filePath) => _runCommand(filePath, openFileArgs: false);

  Future<Result<void>> _runCommand(String filePath,
      {required bool openFileArgs}) async {
    String executable;
    List<String> args;

    if (Platform.isMacOS) {
      executable = 'open';
      args = openFileArgs ? [filePath] : ['-R', filePath];
    } else if (Platform.isWindows) {
      executable = openFileArgs ? 'rundll32.exe' : 'explorer.exe';
      args = openFileArgs
          ? ['url.dll,FileProtocolHandler', filePath.replaceAll('/', '\\')]
          : ['/select,', filePath.replaceAll('/', '\\')];
    } else {
      // Linux
      executable = 'xdg-open';
      args = openFileArgs ? [filePath] : [Directory(filePath).parent.path];
    }

    final result = await _processRunner(executable, args).timeout(_processTimeout);
    if (result.exitCode != 0 && result.exitCode != 1) {
      // exitCode 1 is acceptable for `open -R` on macOS
      return Result.failure(AppException.unknown(
          message: 'Process exited with code ${result.exitCode}'));
    }
    return const Success(null);
  }

  Future<Result<void>> _moveToFolder(
      String filePath, String targetFolder) async {
    final fileName = p.basename(filePath);
    final dest = p.join(targetFolder, fileName);

    try {
      // Copy-then-delete handles cross-volume moves gracefully.
      await File(filePath).copy(dest);
      await File(filePath).delete();
      appLogger.info('Moved $fileName → $targetFolder');
      return const Success(null);
    } on FileSystemException catch (e) {
      return Result.failure(AppException.unknown(message: e.message));
    }
  }
}
