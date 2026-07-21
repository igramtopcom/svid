import '../entities/conversion_job.dart';
import '../repositories/conversion_repository.dart';

/// Use case: Convert a single media file.
///
/// Delegates to the repository which manages the ffmpeg process
/// and emits progress updates through a stream.
class ConvertFileUseCase {
  final ConversionRepository _repository;

  ConvertFileUseCase(this._repository);

  /// Start conversion and return a stream of progress updates.
  Stream<ConversionProgress> call(ConversionJob job) {
    return _repository.convertFile(job);
  }

  /// Cancel an in-progress conversion.
  void cancel(String jobId) {
    _repository.cancelConversion(jobId);
  }
}
