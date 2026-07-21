import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/domain/usecases/start_download_usecase.dart';

/// RC2 of Ultra Plan v3 — Pick X → Get X must survive the Facebook
/// progressive single-file fallback.
///
/// Pre-RC2, when the DASH merge produced a no-audio output and the
/// loop fell back to `best[ext=mp4]/best`, it ALSO nulled
/// `mergeFormatPriority`, `remuxVideo`, and `recodeVideo`. A user
/// who picked AVI silently received MP4 because the recode
/// post-process was dropped. RC2 keeps those three args so the
/// container pick is honored even on the progressive retry path.
void main() {
  group('Facebook progressive fallback — Pick X → Get X (RC2)', () {
    test(
      'AVI request: format flips to best[ext=mp4]/best, recodeVideo=avi preserved',
      () {
        // Pre-fallback state: user picked AVI so containerPlanner
        // emitted recodeVideo='avi' + remuxVideo=null and a DASH
        // bestvideo+bestaudio format selector.
        final result =
            StartDownloadUseCase.applyFacebookProgressiveFallbackForTest(
          format: 'bestvideo+bestaudio/best',
          sortOptions: 'res,ext:avi:m4a',
          mergeFormatPriority: 'mkv/mp4/webm',
          remuxVideo: null,
          recodeVideo: 'avi',
        );

        expect(result.format, 'best[ext=mp4]/best',
            reason: 'Progressive selector must always be best[ext=mp4]/best');
        expect(result.recodeVideo, 'avi',
            reason: 'RC2 invariant: AVI recode survives the fallback — '
                'user picked AVI and MUST get AVI, not silent MP4');
        expect(result.mergeFormatPriority, 'mkv/mp4/webm',
            reason: 'mergeFormatPriority preserved (moot but harmless '
                'in progressive mode)');
        expect(result.remuxVideo, isNull);
      },
    );

    test(
      'MOV request: remuxVideo=mov preserved',
      () {
        final result =
            StartDownloadUseCase.applyFacebookProgressiveFallbackForTest(
          format: 'bestvideo+bestaudio/best',
          sortOptions: 'res,ext:mp4:m4a',
          mergeFormatPriority: 'mp4',
          remuxVideo: 'mov',
          recodeVideo: null,
        );

        expect(result.format, 'best[ext=mp4]/best');
        expect(result.remuxVideo, 'mov',
            reason: 'RC2 invariant: MOV remux survives — '
                'user picked MOV and MUST get MOV');
        expect(result.recodeVideo, isNull);
        expect(result.mergeFormatPriority, 'mp4');
      },
    );

    test(
      'MKV request: mergeFormatPriority preserved alongside recode',
      () {
        final result =
            StartDownloadUseCase.applyFacebookProgressiveFallbackForTest(
          format: 'bestvideo+bestaudio/best',
          sortOptions: 'res,ext:mkv:m4a',
          mergeFormatPriority: 'mkv',
          remuxVideo: 'mkv',
          recodeVideo: null,
        );

        expect(result.format, 'best[ext=mp4]/best');
        expect(result.mergeFormatPriority, 'mkv',
            reason: 'Pre-RC2 nulled this — MUST be preserved now');
        expect(result.remuxVideo, 'mkv');
      },
    );

    test(
      'MP4 (default) request: no-op semantics — recode/remux still null',
      () {
        // The common path: user picked MP4 so containerPlanner
        // emitted no recode/remux. Fallback should not invent
        // values; result must mirror inputs for the three preserved
        // args.
        final result =
            StartDownloadUseCase.applyFacebookProgressiveFallbackForTest(
          format: 'bestvideo+bestaudio/best',
          sortOptions: 'res,ext:mp4:m4a',
          mergeFormatPriority: 'mp4',
          remuxVideo: null,
          recodeVideo: null,
        );

        expect(result.format, 'best[ext=mp4]/best');
        expect(result.recodeVideo, isNull);
        expect(result.remuxVideo, isNull);
        expect(result.mergeFormatPriority, 'mp4');
      },
    );

    test(
      'sortOptions are dropped (paired with format selector)',
      () {
        // Sort options encode codec preferences that pair with the
        // bestvideo+bestaudio selector. With `best[ext=mp4]/best`
        // there is a single progressive stream pick; the sort
        // tiebreaker no longer applies. Keep this explicit so a
        // future change does not accidentally reintroduce stale
        // sort flags into the progressive retry.
        final result =
            StartDownloadUseCase.applyFacebookProgressiveFallbackForTest(
          format: 'bestvideo+bestaudio/best',
          sortOptions: 'res,vcodec:vp9:avc1,acodec:opus:mp4a',
          mergeFormatPriority: 'mp4',
          remuxVideo: null,
          recodeVideo: null,
        );

        expect(result.sortOptions, isNull,
            reason: 'sortOptions pair with format selector — '
                'fallback to progressive drops them');
      },
    );

    test(
      'all three preserve fields are pass-through (no rewriting)',
      () {
        const sentinelMerge = '___MERGE_SENTINEL___';
        const sentinelRemux = '___REMUX_SENTINEL___';
        const sentinelRecode = '___RECODE_SENTINEL___';

        final result =
            StartDownloadUseCase.applyFacebookProgressiveFallbackForTest(
          format: 'anything',
          sortOptions: 'anything',
          mergeFormatPriority: sentinelMerge,
          remuxVideo: sentinelRemux,
          recodeVideo: sentinelRecode,
        );

        expect(result.mergeFormatPriority, sentinelMerge);
        expect(result.remuxVideo, sentinelRemux);
        expect(result.recodeVideo, sentinelRecode);
      },
    );
  });
}
