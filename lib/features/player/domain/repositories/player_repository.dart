import '../../../../core/errors/result.dart';
import '../entities/media_metadata.dart';
import '../entities/player_config.dart';

/// Repository interface for media player operations
/// Implementation will use media_kit for actual playback
abstract class PlayerRepository {
  /// Extract media metadata from file
  Future<Result<MediaMetadata>> extractMetadata(String filePath);

  /// Check if file format is supported
  bool isSupportedFormat(String filePath);

  /// Get media type from file extension
  MediaType getMediaType(String filePath);

  /// Validate player configuration
  bool validateConfig(PlayerConfig config);

  /// Get optimal buffer size for media type
  int getOptimalBufferSize(MediaType mediaType);
}
