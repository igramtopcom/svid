import 'package:flutter/material.dart';
import '../../../../core/core.dart';

/// YouTube search filters
class YouTubeSearchFilters {
  final SearchSortBy sortBy;
  final SearchDuration duration;
  final SearchUploadDate uploadDate;

  const YouTubeSearchFilters({
    this.sortBy = SearchSortBy.relevance,
    this.duration = SearchDuration.any,
    this.uploadDate = SearchUploadDate.anytime,
  });

  YouTubeSearchFilters copyWith({
    SearchSortBy? sortBy,
    SearchDuration? duration,
    SearchUploadDate? uploadDate,
  }) {
    return YouTubeSearchFilters(
      sortBy: sortBy ?? this.sortBy,
      duration: duration ?? this.duration,
      uploadDate: uploadDate ?? this.uploadDate,
    );
  }

  bool get isDefault =>
      sortBy == SearchSortBy.relevance &&
      duration == SearchDuration.any &&
      uploadDate == SearchUploadDate.anytime;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is YouTubeSearchFilters &&
          runtimeType == other.runtimeType &&
          sortBy == other.sortBy &&
          duration == other.duration &&
          uploadDate == other.uploadDate;

  @override
  int get hashCode => sortBy.hashCode ^ duration.hashCode ^ uploadDate.hashCode;
}

/// Sort options for YouTube search
enum SearchSortBy {
  relevance,
  uploadDate,
  viewCount,
  rating;

  String label(BuildContext context) {
    switch (this) {
      case SearchSortBy.relevance:
        return AppLocalizations.youtubeSearchSortRelevance;
      case SearchSortBy.uploadDate:
        return AppLocalizations.youtubeSearchSortUploadDate;
      case SearchSortBy.viewCount:
        return AppLocalizations.youtubeSearchSortViewCount;
      case SearchSortBy.rating:
        return AppLocalizations.youtubeSearchSortRating;
    }
  }

  /// yt-dlp search filter string
  String? get ytdlpFilter {
    switch (this) {
      case SearchSortBy.relevance:
        return null; // Default
      case SearchSortBy.uploadDate:
        return 'date';
      case SearchSortBy.viewCount:
        return 'view_count';
      case SearchSortBy.rating:
        return 'rating';
    }
  }
}

/// Duration filter options
enum SearchDuration {
  any,
  short, // < 4 minutes
  medium, // 4-20 minutes
  long; // > 20 minutes

  String label(BuildContext context) {
    switch (this) {
      case SearchDuration.any:
        return AppLocalizations.youtubeSearchDurationAny;
      case SearchDuration.short:
        return AppLocalizations.youtubeSearchDurationShort;
      case SearchDuration.medium:
        return AppLocalizations.youtubeSearchDurationMedium;
      case SearchDuration.long:
        return AppLocalizations.youtubeSearchDurationLong;
    }
  }

  /// yt-dlp duration filter (in seconds)
  String? get ytdlpFilter {
    switch (this) {
      case SearchDuration.any:
        return null;
      case SearchDuration.short:
        return '<240'; // < 4 minutes
      case SearchDuration.medium:
        return '240-1200'; // 4-20 minutes
      case SearchDuration.long:
        return '>1200'; // > 20 minutes
    }
  }
}

/// Upload date filter options
enum SearchUploadDate {
  anytime,
  today,
  thisWeek,
  thisMonth,
  thisYear;

  String label(BuildContext context) {
    switch (this) {
      case SearchUploadDate.anytime:
        return AppLocalizations.youtubeSearchUploadAnytime;
      case SearchUploadDate.today:
        return AppLocalizations.youtubeSearchUploadToday;
      case SearchUploadDate.thisWeek:
        return AppLocalizations.youtubeSearchUploadThisWeek;
      case SearchUploadDate.thisMonth:
        return AppLocalizations.youtubeSearchUploadThisMonth;
      case SearchUploadDate.thisYear:
        return AppLocalizations.youtubeSearchUploadThisYear;
    }
  }

  /// yt-dlp date filter
  String? get ytdlpFilter {
    switch (this) {
      case SearchUploadDate.anytime:
        return null;
      case SearchUploadDate.today:
        return 'today';
      case SearchUploadDate.thisWeek:
        return 'week';
      case SearchUploadDate.thisMonth:
        return 'month';
      case SearchUploadDate.thisYear:
        return 'year';
    }
  }
}
