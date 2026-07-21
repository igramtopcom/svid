import '../entities/conversion_job.dart';
import '../repositories/conversion_repository.dart';

/// Use case: Batch convert multiple media files.
///
/// Wraps [ConvertFileUseCase] to handle multiple jobs sequentially.
/// The queue management (concurrency control) is handled at the
/// presentation layer by [ConversionQueueNotifier].
class BatchConvertUseCase {
  final ConversionRepository _repository;

  BatchConvertUseCase(this._repository);

  /// Start conversion for a single job in the batch.
  /// Returns a stream of progress updates for that job.
  Stream<ConversionProgress> convertOne(ConversionJob job) {
    return _repository.convertFile(job);
  }

  /// Cancel a specific job in the batch.
  void cancelJob(String jobId) {
    _repository.cancelConversion(jobId);
  }
}
