import '../../../../core/errors/result.dart';
import '../entities/media_info.dart';
import '../repositories/conversion_repository.dart';

/// Use case: Probe a media file to extract its technical information.
///
/// Uses ffprobe to analyze the file and return codec, resolution,
/// duration, bitrate, and stream details.
class ProbeMediaUseCase {
  final ConversionRepository _repository;

  ProbeMediaUseCase(this._repository);

  Future<Result<MediaInfo>> call(String filePath) async {
    return runCatching(() => _repository.probeFile(filePath));
  }
}
