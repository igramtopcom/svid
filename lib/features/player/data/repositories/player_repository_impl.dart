import 'dart:io';
import 'package:path/path.dart' as p;
import '../../../../core/errors/app_exception.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/utils/file_utils.dart';
import '../../domain/entities/media_metadata.dart';
import '../../domain/entities/player_config.dart';
import '../../domain/repositories/player_repository.dart';

/// Implementation of PlayerRepository
/// Uses file metadata and media_kit for playback
class PlayerRepositoryImpl implements PlayerRepository {
  PlayerRepositoryImpl();

  @override
  Future<Result<MediaMetadata>> extractMetadata(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return Result.failure(
        AppException.storage(message: 'File not found: $filePath', path: filePath),
      );
    }

    final fileName = p.basename(filePath);
    final fileSize = await file.length();
    final mediaType = getMediaType(filePath);

    // For now, return basic metadata
    // TODO(Phase 59+): Use ffprobe via Rust bridge for detailed metadata extraction
    return Result.success(MediaMetadata(
      filePath: filePath,
      duration: const Duration(seconds: 0), // Will be updated by media_kit
      title: p.basenameWithoutExtension(fileName),
      mediaType: mediaType,
      fileSize: fileSize,
    ));
  }

  @override
  bool isSupportedFormat(String filePath) {
    return FileUtils.isMediaFile(filePath);
  }

  @override
  MediaType getMediaType(String filePath) {
    if (FileUtils.isVideoFile(filePath)) {
      return MediaType.video;
    } else if (FileUtils.isAudioFile(filePath)) {
      return MediaType.audio;
    } else if (FileUtils.isImageFile(filePath)) {
      return MediaType.image;
    }
    return MediaType.unknown;
  }

  @override
  bool validateConfig(PlayerConfig config) {
    return config.isVolumeValid && config.isPlaybackSpeedValid;
  }

  @override
  int getOptimalBufferSize(MediaType mediaType) {
    switch (mediaType) {
      case MediaType.video:
        return 15; // 15 seconds for video
      case MediaType.audio:
        return 10; // 10 seconds for audio
      case MediaType.image:
        return 0; // No buffer for images
      case MediaType.unknown:
        return 10;
    }
  }
}
