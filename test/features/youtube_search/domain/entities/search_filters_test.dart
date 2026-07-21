import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/youtube_search/domain/entities/search_filters.dart';

void main() {
  group('YouTubeSearchFilters', () {
    test('default constructor has default values', () {
      const filters = YouTubeSearchFilters();
      expect(filters.sortBy, SearchSortBy.relevance);
      expect(filters.duration, SearchDuration.any);
      expect(filters.uploadDate, SearchUploadDate.anytime);
    });

    test('isDefault returns true for defaults', () {
      expect(const YouTubeSearchFilters().isDefault, isTrue);
    });

    test('isDefault returns false when changed', () {
      const filters = YouTubeSearchFilters(sortBy: SearchSortBy.viewCount);
      expect(filters.isDefault, isFalse);
    });

    test('copyWith preserves unchanged fields', () {
      const original = YouTubeSearchFilters(
        sortBy: SearchSortBy.rating,
        duration: SearchDuration.long,
      );
      final copied = original.copyWith(duration: SearchDuration.short);
      expect(copied.sortBy, SearchSortBy.rating);
      expect(copied.duration, SearchDuration.short);
      expect(copied.uploadDate, SearchUploadDate.anytime);
    });

    test('equality works', () {
      const a = YouTubeSearchFilters(sortBy: SearchSortBy.viewCount);
      const b = YouTubeSearchFilters(sortBy: SearchSortBy.viewCount);
      const c = YouTubeSearchFilters(sortBy: SearchSortBy.rating);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('SearchSortBy.ytdlpFilter', () {
    test('relevance returns null', () {
      expect(SearchSortBy.relevance.ytdlpFilter, isNull);
    });

    test('uploadDate returns date', () {
      expect(SearchSortBy.uploadDate.ytdlpFilter, 'date');
    });

    test('viewCount returns view_count', () {
      expect(SearchSortBy.viewCount.ytdlpFilter, 'view_count');
    });

    test('rating returns rating', () {
      expect(SearchSortBy.rating.ytdlpFilter, 'rating');
    });
  });

  group('SearchDuration.ytdlpFilter', () {
    test('any returns null', () {
      expect(SearchDuration.any.ytdlpFilter, isNull);
    });

    test('short returns <240', () {
      expect(SearchDuration.short.ytdlpFilter, '<240');
    });

    test('medium returns 240-1200', () {
      expect(SearchDuration.medium.ytdlpFilter, '240-1200');
    });

    test('long returns >1200', () {
      expect(SearchDuration.long.ytdlpFilter, '>1200');
    });
  });

  group('SearchUploadDate.ytdlpFilter', () {
    test('anytime returns null', () {
      expect(SearchUploadDate.anytime.ytdlpFilter, isNull);
    });

    test('today returns today', () {
      expect(SearchUploadDate.today.ytdlpFilter, 'today');
    });

    test('thisWeek returns week', () {
      expect(SearchUploadDate.thisWeek.ytdlpFilter, 'week');
    });

    test('thisMonth returns month', () {
      expect(SearchUploadDate.thisMonth.ytdlpFilter, 'month');
    });

    test('thisYear returns year', () {
      expect(SearchUploadDate.thisYear.ytdlpFilter, 'year');
    });
  });
}
