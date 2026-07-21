import '../../../downloads/domain/entities/video_info.dart';

/// Pure-Dart service for chapter navigation logic.
/// All methods are static so they can be unit-tested without Flutter bindings.
class PlayerChapterService {
  const PlayerChapterService._();

  /// Returns the current chapter for [positionSec], or `null` if before the
  /// first chapter or [chapters] is empty.
  static ChapterInfo? getCurrentChapter(
    List<ChapterInfo> chapters,
    double positionSec,
  ) {
    if (chapters.isEmpty) return null;
    for (int i = chapters.length - 1; i >= 0; i--) {
      if (positionSec >= chapters[i].startTime) return chapters[i];
    }
    return null;
  }

  /// Returns the start-time (seconds) of the next chapter after [positionSec],
  /// allowing a 1-second tolerance. Returns `null` if already at the last chapter.
  static double? getNextChapterStart(
    List<ChapterInfo> chapters,
    double positionSec,
  ) {
    for (final chapter in chapters) {
      if (chapter.startTime > positionSec + 1.0) return chapter.startTime;
    }
    return null;
  }

  /// Returns the start-time (seconds) of the previous chapter.
  /// If within 3 seconds of the current chapter, goes to the one before it
  /// (rewind behaviour). Returns `null` if already at the first chapter.
  static double? getPreviousChapterStart(
    List<ChapterInfo> chapters,
    double positionSec,
  ) {
    for (int i = chapters.length - 1; i >= 0; i--) {
      if (chapters[i].startTime < positionSec - 3.0) {
        return chapters[i].startTime;
      }
    }
    return null;
  }
}
