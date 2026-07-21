import '../../../../core/errors/result.dart';
import '../../../../core/errors/app_exception.dart';
import '../repositories/download_repository.dart';

/// Use case for deleting a download
class DeleteDownloadUseCase {
  final DownloadRepository _repository;

  DeleteDownloadUseCase(this._repository);

  Future<Result<void>> call(int downloadId, {bool deleteFile = false}) async {
    // Get download to validate it can be deleted
    final downloadResult = await _repository.getDownloadById(downloadId);

    if (downloadResult.isFailure) {
      return Result.failure(downloadResult.exceptionOrNull!);
    }

    final download = downloadResult.dataOrThrow;

    if (!download.canDelete) {
      return Result.failure(
        AppException.download(
          message: 'Download cannot be deleted in current state: ${download.status.displayLabel}',
          data: {'downloadId': downloadId, 'status': download.status.name},
        ),
      );
    }

    return await _repository.deleteDownload(downloadId, deleteFile: deleteFile);
  }
}
