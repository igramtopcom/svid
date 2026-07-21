import '../../../../core/errors/result.dart';
import '../../../../core/errors/app_exception.dart';
import '../repositories/download_repository.dart';

/// Use case for resuming a paused or failed download
class ResumeDownloadUseCase {
  final DownloadRepository _repository;

  ResumeDownloadUseCase(this._repository);

  Future<Result<void>> call(int downloadId) async {
    // Get download to validate it can be resumed
    final downloadResult = await _repository.getDownloadById(downloadId);

    if (downloadResult.isFailure) {
      return Result.failure(downloadResult.exceptionOrNull!);
    }

    final download = downloadResult.dataOrThrow;

    if (!download.canResume) {
      return Result.failure(
        AppException.download(
          message: 'Download cannot be resumed in current state: ${download.status.displayLabel}',
          data: {'downloadId': downloadId, 'status': download.status.name},
        ),
      );
    }

    return await _repository.resumeDownload(downloadId);
  }
}
