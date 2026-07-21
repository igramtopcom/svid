import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/entities/download_entity.dart';
import '../../domain/entities/download_status.dart';

/// Mapper for converting between database models and domain entities
class DownloadMapper {
  DownloadMapper._();

  /// Convert database Download to domain DownloadEntity
  static DownloadEntity toDomain(Download download) {
    return DownloadEntity(
      id: download.id,
      url: download.url,
      filename: download.filename,
      savePath: download.savePath,
      status: DownloadStatus.fromDbString(download.status),
      totalBytes: download.totalBytes,
      downloadedBytes: download.downloadedBytes,
      speed: download.speed,
      thumbnail: download.thumbnail,
      platform: download.platform,
      createdAt: download.createdAt,
      updatedAt: download.updatedAt,
      errorMessage: download.errorMessage,
      retryCount: download.retryCount,
      // Rich metadata
      title: download.title,
      description: download.description,
      uploader: download.uploader,
      duration: download.duration,
      viewCount: download.viewCount,
      uploadDate: download.uploadDate,
      downloadMethod: download.downloadMethod,
      qualityLabel: download.qualityLabel,
      chaptersJson: download.chaptersJson,
      userNote: download.userNote,
      isWatched: download.isWatched,
      scheduledAt: download.scheduledAt,
      queuePosition: download.queuePosition,
      sourceUrl: download.sourceUrl,
      priority: download.priority,
      recurrenceRuleJson: download.recurrenceRuleJson,
      tempDirPath: download.tempDirPath,
      playlistId: download.playlistId,
      playlistTitle: download.playlistTitle,
      playlistIndex: download.playlistIndex,
    );
  }

  /// Convert domain DownloadEntity to database DownloadsCompanion
  static DownloadsCompanion toCompanion(DownloadEntity entity) {
    return DownloadsCompanion.insert(
      url: entity.url,
      filename: entity.filename,
      savePath: entity.savePath,
      status: entity.status.toDbString(),
      totalBytes: Value(entity.totalBytes),
      downloadedBytes: Value(entity.downloadedBytes),
      speed: Value(entity.speed),
      thumbnail: Value(entity.thumbnail),
      platform: Value(entity.platform),
      createdAt: Value(entity.createdAt),
      updatedAt: Value(entity.updatedAt),
      errorMessage: Value(entity.errorMessage),
      retryCount: Value(entity.retryCount),
      // Rich metadata
      title: Value(entity.title),
      description: Value(entity.description),
      uploader: Value(entity.uploader),
      duration: Value(entity.duration),
      viewCount: Value(entity.viewCount),
      uploadDate: Value(entity.uploadDate),
      downloadMethod: Value(entity.downloadMethod),
      qualityLabel: Value(entity.qualityLabel),
      chaptersJson: Value(entity.chaptersJson),
      userNote: Value(entity.userNote),
      isWatched: Value(entity.isWatched),
      scheduledAt: Value(entity.scheduledAt),
      queuePosition: Value(entity.queuePosition),
      sourceUrl: Value(entity.sourceUrl),
      priority: Value(entity.priority),
      recurrenceRuleJson: Value(entity.recurrenceRuleJson),
      tempDirPath: Value(entity.tempDirPath),
      playlistId: Value(entity.playlistId),
      playlistTitle: Value(entity.playlistTitle),
      playlistIndex: Value(entity.playlistIndex),
    );
  }

  /// Convert list of database Downloads to list of domain DownloadEntities
  static List<DownloadEntity> toDomainList(List<Download> downloads) {
    return downloads.map(toDomain).toList();
  }
}
