import '../../../../core/errors/result.dart';
import '../entities/download_entity.dart';
import '../entities/download_status.dart';
import '../repositories/download_repository.dart';

/// Use case for getting downloads with various filters
class GetDownloadsUseCase {
  final DownloadRepository _repository;

  GetDownloadsUseCase(this._repository);

  /// Get all downloads
  Future<Result<List<DownloadEntity>>> call() async {
    return await _repository.getAllDownloads();
  }

  /// Get downloads by status
  Future<Result<List<DownloadEntity>>> byStatus(DownloadStatus status) async {
    return await _repository.getDownloadsByStatus(status);
  }

  /// Get active downloads only
  Future<Result<List<DownloadEntity>>> activeOnly() async {
    return await _repository.getActiveDownloads();
  }

  /// Get a single download by ID
  Future<Result<DownloadEntity>> byId(int id) async {
    return await _repository.getDownloadById(id);
  }

  /// Watch all downloads as a stream
  Stream<List<DownloadEntity>> watchAll() {
    return _repository.watchAllDownloads();
  }

  /// Watch a single download as a stream
  Stream<DownloadEntity> watch(int id) {
    return _repository.watchDownload(id);
  }
}
