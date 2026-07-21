import '../../../../core/errors/result.dart';
import '../../../../core/errors/app_exception.dart';
import '../repositories/download_repository.dart';

/// Use case for cancelling a download
class CancelDownloadUseCase {
  final DownloadRepository _repository;

  CancelDownloadUseCase(this._repository);

  Future<Result<void>> call(int downloadId) async {
    // Get download to validate it can be cancelled
    final downloadResult = await _repository.getDownloadById(downloadId);

    if (downloadResult.isFailure) {
      return Result.failure(downloadResult.exceptionOrNull!);
    }

    final download = downloadResult.dataOrThrow;

    if (!download.canCancel) {
      return Result.failure(
        AppException.download(
          message: 'Download cannot be cancelled in current state: ${download.status.displayLabel}',
          data: {'downloadId': downloadId, 'status': download.status.name},
        ),
      );
    }

    return await _repository.cancelDownload(downloadId);
  }
}
