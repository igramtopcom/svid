import '../../../../core/errors/result.dart';
import '../../../../core/errors/app_exception.dart';
import '../repositories/download_repository.dart';

/// Use case for pausing a download
class PauseDownloadUseCase {
  final DownloadRepository _repository;

  PauseDownloadUseCase(this._repository);

  Future<Result<void>> call(int downloadId) async {
    // Get download to validate it can be paused
    final downloadResult = await _repository.getDownloadById(downloadId);

    if (downloadResult.isFailure) {
      return Result.failure(downloadResult.exceptionOrNull!);
    }

    final download = downloadResult.dataOrThrow;

    if (!download.canPause) {
      return Result.failure(
        AppException.download(
          message: 'Download cannot be paused in current state: ${download.status.displayLabel}',
          data: {'downloadId': downloadId, 'status': download.status.name},
        ),
      );
    }

    return await _repository.pauseDownload(downloadId);
  }
}
