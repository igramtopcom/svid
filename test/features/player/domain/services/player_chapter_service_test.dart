import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/domain/entities/video_info.dart';
import 'package:svid/features/player/domain/services/player_chapter_service.dart';

void main() {
  // Helper: build a simple chapter list
  List<ChapterInfo> makeChapters() => [
        const ChapterInfo(title: 'Intro', startTime: 0.0, endTime: 30.0),
        const ChapterInfo(title: 'Main', startTime: 30.0, endTime: 120.0),
        const ChapterInfo(title: 'Outro', startTime: 120.0, endTime: 180.0),
      ];

  group('PlayerChapterService.getCurrentChapter', () {
    test('returns null for empty chapter list', () {
      expect(PlayerChapterService.getCurrentChapter([], 10.0), isNull);
    });

    test('returns first chapter when position is at start', () {
      final result = PlayerChapterService.getCurrentChapter(makeChapters(), 0.0);
      expect(result?.title, 'Intro');
    });

    test('returns correct chapter mid-video', () {
      final result = PlayerChapterService.getCurrentChapter(makeChapters(), 60.0);
      expect(result?.title, 'Main');
    });

    test('returns last chapter when at its start time', () {
      final result = PlayerChapterService.getCurrentChapter(makeChapters(), 120.0);
      expect(result?.title, 'Outro');
    });

    test('returns null when position is before first chapter start', () {
      final chapters = [
        const ChapterInfo(title: 'Ch1', startTime: 10.0, endTime: 60.0),
      ];
      expect(PlayerChapterService.getCurrentChapter(chapters, 5.0), isNull);
    });
  });

  group('PlayerChapterService.getNextChapterStart', () {
    test('returns null for empty chapter list', () {
      expect(PlayerChapterService.getNextChapterStart([], 10.0), isNull);
    });

    test('returns start time of the next chapter', () {
      final result = PlayerChapterService.getNextChapterStart(makeChapters(), 5.0);
      expect(result, 30.0);
    });

    test('respects 1-second tolerance — position just before chapter boundary', () {
      // At 29.5s the next chapter starts at 30.0 — diff is only 0.5s → skipped
      final result = PlayerChapterService.getNextChapterStart(makeChapters(), 29.5);
      // 30.0 is NOT > 29.5+1.0 (30.5), so skip to Outro at 120.0
      expect(result, 120.0);
    });

    test('returns null when already at the last chapter', () {
      final result = PlayerChapterService.getNextChapterStart(makeChapters(), 130.0);
      expect(result, isNull);
    });
  });

  group('PlayerChapterService.getPreviousChapterStart', () {
    test('returns null for empty chapter list', () {
      expect(PlayerChapterService.getPreviousChapterStart([], 10.0), isNull);
    });

    test('returns previous chapter when more than 3s into current chapter', () {
      // At 40s: current chapter starts at 30s. 30 < 40-3=37 → go to Main(30)
      final result = PlayerChapterService.getPreviousChapterStart(makeChapters(), 40.0);
      expect(result, 30.0);
    });

    test('returns chapter before current when within 3s of chapter start', () {
      // At 31s: current chapter starts at 30s. 30 is NOT < 31-3=28 → skip.
      // Intro(0) < 28 → returns Intro
      final result = PlayerChapterService.getPreviousChapterStart(makeChapters(), 31.0);
      expect(result, 0.0);
    });

    test('returns null when at beginning (no previous chapter satisfies condition)', () {
      // At 2s, no chapter.startTime < 2-3 = -1 → null
      final result = PlayerChapterService.getPreviousChapterStart(makeChapters(), 2.0);
      expect(result, isNull);
    });
  });
}
