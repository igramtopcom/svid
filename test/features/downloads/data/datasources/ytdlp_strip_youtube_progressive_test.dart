import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/data/datasources/ytdlp_datasource.dart';

/// P0 1080p-regression golden lock — group (a): the YouTube progressive
/// strip MUST remove EVERY trailing `/best[...]` net, including the
/// multi-bracket tails the old `RegExp(r'/best\[[^\]]+\]$')` could not
/// match (`[^\]]+` cannot cross the first inner `]`). RC-1 (commit
/// 1c555eff) let a multi-bracket `/best[ext=mp4][height<=1080]` survive,
/// so a failed 1080p DASH pull resolved to itag-18 360p labelled 1080p.
///
/// Helper had ZERO coverage before this file. Exposed via
/// YtDlpDataSource.stripYouTubeProgressiveBestFallbackForTest.
void main() {
  String strip(String? f) =>
      YtDlpDataSource.stripYouTubeProgressiveBestFallbackForTest(f) ?? '';

  group('_stripYouTubeProgressiveBestFallback — remove ALL trailing /best[...]',
      () {
    test('multi-bracket double tail is fully removed (RC-1 core bug)', () {
      // Exact live buildBestFormatSelector(1080, mp4, h264/aac) tail.
      const input =
          'bestvideo[vcodec^=avc][height<=1080]+bestaudio[acodec^=aac]'
          '/bestvideo[vcodec^=avc][width<=1080]+bestaudio[acodec^=aac]'
          '/bestvideo[ext=mp4][height<=1080]+bestaudio[ext=m4a]'
          '/bestvideo[ext=mp4][width<=1080]+bestaudio[ext=m4a]'
          '/best[ext=mp4][height<=1080]/best[ext=mp4][width<=1080]';
      final out = strip(input);
      expect(out, isNot(contains('/best[')),
          reason: 'no single-file progressive /best[...] net may survive');
      expect(out, isNot(endsWith('/best')));
      // Bounded merge tiers (with +bestaudio) MUST be preserved.
      expect(
          out, contains('bestvideo[ext=mp4][height<=1080]+bestaudio[ext=m4a]'));
      expect(out,
          contains('bestvideo[vcodec^=avc][height<=1080]+bestaudio[acodec^=aac]'));
    });

    test('three chained multi-bracket /best[...] tails fully removed', () {
      const input =
          'bestvideo[ext=mp4][height<=1080]+ba'
          '/best[ext=mp4][height<=1080]/best[ext=mp4][width<=1080]';
      final out = strip(input);
      expect(out, 'bestvideo[ext=mp4][height<=1080]+ba');
      expect(out, isNot(contains('/best[')));
    });

    test('full 3-bracket-per-segment tail removed, merge prefix kept', () {
      const input =
          'bestvideo[ext=mp4][height<=1080]+ba'
          '/best[ext=mp4][height<=1080][width<=1080]';
      final out = strip(input);
      expect(out, 'bestvideo[ext=mp4][height<=1080]+ba');
      expect(out, isNot(contains('/best[')));
    });

    // Reviewer-mandated: YouTube MKV free-tier double-SINGLE-bracket tail.
    // The OLD single-shot code stripped only the LAST segment (left
    // `/best[height<=1080]` behind — a known under-strip). The new loop
    // strips BOTH. Locks the strictly-more-correct behavior.
    test('MKV-free double single-bracket tail fully removed (loop lock)', () {
      const input =
          'bestvideo[height<=1080]+bestaudio/bestvideo[width<=1080]+bestaudio'
          '/best[height<=1080]/best[width<=1080]';
      final out = strip(input);
      expect(
          out, 'bestvideo[height<=1080]+bestaudio/bestvideo[width<=1080]+bestaudio');
      expect(out, isNot(contains('/best[')));
      expect(out, isNot(endsWith('/best')));
    });

    test('legacy single-bracket /best[...] tail still strips (regression guard)',
        () {
      final out = strip('bestvideo[height<=1080]+bestaudio/best[height<=1080]');
      expect(out, 'bestvideo[height<=1080]+bestaudio');
    });

    test('bare /best tail still strips (regression guard)', () {
      expect(strip('bestvideo+bestaudio/best'), 'bestvideo+bestaudio');
    });

    test('no /best[...] net present → string unchanged (no over-strip)', () {
      const merged =
          'bestvideo[ext=mp4][height<=1080]+bestaudio[ext=m4a]'
          '/bestvideo[ext=mp4][width<=1080]+bestaudio[ext=m4a]';
      expect(strip(merged), merged);
    });

    test('null and empty pass through', () {
      expect(
        YtDlpDataSource.stripYouTubeProgressiveBestFallbackForTest(null),
        isNull,
      );
      expect(
        YtDlpDataSource.stripYouTubeProgressiveBestFallbackForTest(''),
        '',
      );
    });
  });
}
