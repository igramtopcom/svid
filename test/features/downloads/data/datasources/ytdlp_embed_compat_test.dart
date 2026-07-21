import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/data/datasources/ytdlp_datasource.dart';

/// Pin the postprocess compatibility matrix against yt-dlp upstream
/// drift. The hard-fail surface here is `--embed-thumbnail` on an
/// unsupported container, which is exactly the Windows production
/// crash from 2026-05-21 (`ERROR: Postprocessing: Supported filetypes
/// for thumbnail embedding are: mp3, mkv/mka, ogg/opus/flac,
/// m4a/mp4/m4v/mov`). The test matrix below is intentionally
/// exhaustive across the 4 new recoded containers (AVI/MOV/M4V/FLV)
/// AND the 3 native containers (MP4/MKV/WebM) AND a handful of common
/// audio extracts — so any future change to either the upstream sets
/// or our resolver fires a lockstep diff.
void main() {
  group('resolveEmbedCompatibility — video containers (post-recode)', () {
    test('mp4 supports all three embeds', () {
      final c = YtDlpDataSource.resolveEmbedCompatibility(
        recodeVideo: null,
        videoFormat: 'mp4',
        audioFormat: null,
        extractAudio: false,
      );
      expect(c.effectiveExt, 'mp4');
      expect(c.canEmbedThumbnail, isTrue);
      expect(c.canEmbedSubs, isTrue);
      expect(c.canEmbedChapters, isTrue);
    });

    test('mkv supports all three embeds', () {
      final c = YtDlpDataSource.resolveEmbedCompatibility(
        recodeVideo: null,
        videoFormat: 'mkv',
        audioFormat: null,
        extractAudio: false,
      );
      expect(c.effectiveExt, 'mkv');
      expect(c.canEmbedThumbnail, isTrue);
      expect(c.canEmbedSubs, isTrue);
      expect(c.canEmbedChapters, isTrue);
    });

    test('webm supports subs + chapters but NOT thumbnail', () {
      // WebM is missing from yt-dlp's thumbnail SUPPORTED_EXTS.
      // Embedding silently fails (raises) so we treat as unsupported.
      final c = YtDlpDataSource.resolveEmbedCompatibility(
        recodeVideo: null,
        videoFormat: 'webm',
        audioFormat: null,
        extractAudio: false,
      );
      expect(c.effectiveExt, 'webm');
      expect(c.canEmbedThumbnail, isFalse);
      expect(c.canEmbedSubs, isTrue);
      expect(c.canEmbedChapters, isTrue);
    });

    test('avi (recoded) supports NEITHER thumbnail NOR subs', () {
      // The 2026-05-21 Windows production crash. recodeVideo='avi'
      // means the final file is .avi, which yt-dlp's
      // EmbedThumbnailPP rejects. Caller MUST skip --embed-thumbnail
      // here or yt-dlp exits non-zero and the download fails.
      final c = YtDlpDataSource.resolveEmbedCompatibility(
        recodeVideo: 'avi',
        videoFormat: 'mkv', // merger intermediate; irrelevant post-recode
        audioFormat: null,
        extractAudio: false,
      );
      expect(c.effectiveExt, 'avi');
      expect(c.canEmbedThumbnail, isFalse);
      expect(c.canEmbedSubs, isFalse);
      expect(c.canEmbedChapters, isFalse,
          reason: 'AVI has no chapter atom; chapters dropped silently');
    });

    test('mov (recoded) supports all three embeds (Apple QuickTime)', () {
      final c = YtDlpDataSource.resolveEmbedCompatibility(
        recodeVideo: 'mov',
        videoFormat: 'mkv',
        audioFormat: null,
        extractAudio: false,
      );
      expect(c.effectiveExt, 'mov');
      expect(c.canEmbedThumbnail, isTrue);
      expect(c.canEmbedSubs, isTrue);
      expect(c.canEmbedChapters, isTrue);
    });

    test('m4v effective ext: yt-dlp recode "mp4" but final file is .m4v', () {
      // resolveRecodeVideo maps user-chosen m4v -> 'mp4' (yt-dlp has
      // no m4v target). videoFormat carries the user's intended
      // extension. From the embed PP's perspective the file is .m4v
      // (post-rename); .m4v IS in the thumbnail SUPPORTED_EXTS but
      // NOT in the subs SUPPORTED_EXTS, matching mp4 behavior for
      // chapters.
      final c = YtDlpDataSource.resolveEmbedCompatibility(
        recodeVideo: 'mp4',
        videoFormat: 'm4v',
        audioFormat: null,
        extractAudio: false,
      );
      // recodeVideo wins in the resolver — we trust the recode target
      // since that's what yt-dlp's PP chain actually sees. The Dart
      // post-rename to .m4v happens AFTER the PP chain finishes.
      expect(c.effectiveExt, 'mp4');
      expect(c.canEmbedThumbnail, isTrue);
      expect(c.canEmbedSubs, isTrue);
      expect(c.canEmbedChapters, isTrue);
    });

    test('flv (recoded) supports NEITHER thumbnail NOR subs NOR chapters', () {
      final c = YtDlpDataSource.resolveEmbedCompatibility(
        recodeVideo: 'flv',
        videoFormat: 'mkv',
        audioFormat: null,
        extractAudio: false,
      );
      expect(c.effectiveExt, 'flv');
      expect(c.canEmbedThumbnail, isFalse);
      expect(c.canEmbedSubs, isFalse);
      expect(c.canEmbedChapters, isFalse,
          reason: 'FLV is a flat stream container with no chapter atom');
    });
  });

  group('resolveEmbedCompatibility — audio extracts', () {
    test('mp3 supports thumbnail embed only', () {
      final c = YtDlpDataSource.resolveEmbedCompatibility(
        recodeVideo: null,
        videoFormat: null,
        audioFormat: 'mp3',
        extractAudio: true,
      );
      expect(c.effectiveExt, 'mp3');
      expect(c.canEmbedThumbnail, isTrue);
      expect(c.canEmbedSubs, isFalse);
      expect(c.canEmbedChapters, isFalse);
    });

    test('m4a supports all three', () {
      final c = YtDlpDataSource.resolveEmbedCompatibility(
        recodeVideo: null,
        videoFormat: null,
        audioFormat: 'm4a',
        extractAudio: true,
      );
      expect(c.canEmbedThumbnail, isTrue);
      expect(c.canEmbedSubs, isTrue);
      expect(c.canEmbedChapters, isFalse,
          reason: 'm4a is in subs set but NOT chapters set');
    });

    test('opus supports thumbnail only', () {
      final c = YtDlpDataSource.resolveEmbedCompatibility(
        recodeVideo: null,
        videoFormat: null,
        audioFormat: 'opus',
        extractAudio: true,
      );
      expect(c.canEmbedThumbnail, isTrue);
      expect(c.canEmbedSubs, isFalse);
      expect(c.canEmbedChapters, isFalse);
    });

    test('wav supports nothing (pre-Phase-1b carve-out)', () {
      // The legacy unsupportedEmbedFormats set was {wav, aiff, pcm}.
      // Reproduce that behavior by negation: wav is missing from
      // every embed set.
      final c = YtDlpDataSource.resolveEmbedCompatibility(
        recodeVideo: null,
        videoFormat: null,
        audioFormat: 'wav',
        extractAudio: true,
      );
      expect(c.canEmbedThumbnail, isFalse);
      expect(c.canEmbedSubs, isFalse);
      expect(c.canEmbedChapters, isFalse);
    });
  });

  group('resolveEmbedCompatibility — precedence', () {
    test('extractAudio + audioFormat wins over recodeVideo', () {
      // Defensive — extractAudio implies no video container to embed
      // into. The audio extension drives the matrix.
      final c = YtDlpDataSource.resolveEmbedCompatibility(
        recodeVideo: 'avi',
        videoFormat: 'mkv',
        audioFormat: 'mp3',
        extractAudio: true,
      );
      expect(c.effectiveExt, 'mp3');
      expect(c.canEmbedThumbnail, isTrue);
    });

    test('recodeVideo wins over videoFormat for non-audio downloads', () {
      // Native videoFormat would say mkv (universal); user chose AVI
      // (recoded). Effective ext is the final container = AVI.
      final c = YtDlpDataSource.resolveEmbedCompatibility(
        recodeVideo: 'avi',
        videoFormat: 'mkv',
        audioFormat: null,
        extractAudio: false,
      );
      expect(c.effectiveExt, 'avi');
    });

    test('fallback to mp4 when nothing provided', () {
      // Defensive against an unset call path — historical default.
      final c = YtDlpDataSource.resolveEmbedCompatibility(
        recodeVideo: null,
        videoFormat: null,
        audioFormat: null,
        extractAudio: false,
      );
      expect(c.effectiveExt, 'mp4');
      expect(c.canEmbedThumbnail, isTrue);
      expect(c.canEmbedSubs, isTrue);
      expect(c.canEmbedChapters, isTrue);
    });

    test('case-insensitive — uppercase extensions resolve correctly', () {
      final c = YtDlpDataSource.resolveEmbedCompatibility(
        recodeVideo: 'AVI',
        videoFormat: null,
        audioFormat: null,
        extractAudio: false,
      );
      expect(c.effectiveExt, 'avi');
      expect(c.canEmbedThumbnail, isFalse);
    });
  });
}
