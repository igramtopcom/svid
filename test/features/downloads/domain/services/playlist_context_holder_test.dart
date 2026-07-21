/// Regression tests for `PlaylistContextHolder` — the URL→context
/// bridge between `HomeBatchDownloadMixin.handleBatchDownload` and
/// `DownloadRepositoryImpl.createDownload`.
///
/// The holder itself is dead-simple, but it carries an invariant
/// that's easy to break in calling code: stamps must NEVER outlive
/// the batch that created them, otherwise a future ad-hoc download
/// of the same URL inherits a stale playlist tag.
///
/// Reviewer caught the original P1 bug (2026-05-07): the batch flow
/// stamped on the deduped URL list BEFORE `filterPendingUrls`
/// removed already-completed URLs, then cleared only the pending
/// set at the end. Skipped URLs were left stamped indefinitely. The
/// fix moved stamping to AFTER `pendingUrls` was computed; these
/// tests lock that contract for both the holder's own behaviour
/// and the eviction guarantees the batch flow relies on.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/domain/services/playlist_context_holder.dart';

void main() {
  group('PlaylistContextHolder — basic stamp/consume', () {
    test('consume returns the entry and removes it', () {
      final h = PlaylistContextHolder();
      h.stampBatch(
        ['https://yt/1', 'https://yt/2'],
        playlistId: 'yt_PL123',
        playlistTitle: 'Mix',
      );
      expect(h.pendingCount, 2);

      final first = h.consume('https://yt/1');
      expect(first?.playlistId, 'yt_PL123');
      expect(first?.playlistTitle, 'Mix');
      expect(first?.playlistIndex, 0);
      expect(h.pendingCount, 1);

      // Idempotent re-consume returns null — the stamp is gone.
      expect(h.consume('https://yt/1'), isNull);
      expect(h.pendingCount, 1);
    });

    test('preserves per-URL playlistIndex matching the input order', () {
      final h = PlaylistContextHolder();
      h.stampBatch(
        ['a', 'b', 'c'],
        playlistId: 'yt_PL',
        playlistTitle: null,
      );
      expect(h.consume('a')?.playlistIndex, 0);
      expect(h.consume('b')?.playlistIndex, 1);
      expect(h.consume('c')?.playlistIndex, 2);
    });

    test('null playlistTitle is propagated unchanged', () {
      // Real case: extraction couldn't fetch a private playlist's
      // title. Holder must carry the null through so the eventual
      // row has a null `playlistTitle` instead of an empty string
      // that the UI would render as a blank header.
      final h = PlaylistContextHolder();
      h.stampBatch(['x'], playlistId: 'yt_PL', playlistTitle: null);
      expect(h.consume('x')?.playlistTitle, isNull);
    });
  });

  group('PlaylistContextHolder — clearForUrls', () {
    test('removes only the listed URLs', () {
      final h = PlaylistContextHolder();
      h.stampBatch(
        ['a', 'b', 'c'],
        playlistId: 'yt_PL',
        playlistTitle: null,
      );
      h.clearForUrls(['a', 'c']);
      expect(h.consume('a'), isNull);
      expect(h.consume('c'), isNull);
      expect(h.consume('b'), isNotNull);
    });

    test('idempotent for unknown URLs', () {
      final h = PlaylistContextHolder();
      h.stampBatch(['a'], playlistId: 'yt_PL', playlistTitle: null);
      // Unknown URL — no-op, no exception.
      h.clearForUrls(['unknown']);
      expect(h.consume('a'), isNotNull);
    });
  });

  group('PlaylistContextHolder — re-stamp semantics', () {
    test('overwrites prior entry for the same URL', () {
      // If the user dispatches a batch from playlist X, then before
      // the first batch finishes dispatches the same URL again from
      // playlist Y, the second stamp should win — the eventual row
      // belongs to whatever batch most-recently claimed that URL.
      final h = PlaylistContextHolder();
      h.stampBatch(['url'], playlistId: 'yt_X', playlistTitle: 'X');
      h.stampBatch(['url'], playlistId: 'yt_Y', playlistTitle: 'Y');
      final got = h.consume('url');
      expect(got?.playlistId, 'yt_Y');
      expect(got?.playlistTitle, 'Y');
    });
  });

  group(
    'P1 regression — stamping must happen on pendingUrls, not uniqueUrls',
    () {
      test(
        'simulates the fixed batch flow: stamps after dedupe + skip filter',
        () {
          // This emulates the call sequence in
          // `home_batch_download_mixin.dart:handleBatchDownload`
          // post-fix. We stamp ONLY the pendingUrls (after the
          // resume-support filter runs), and clear those same URLs
          // at the end. There must be ZERO leaked stamps.
          final h = PlaylistContextHolder();

          // The batch arrived with 5 URLs from the playlist sheet.
          // We only model the SUBSET that survives `filterPendingUrls`
          // here — the original 5-URL list is implicit in the
          // commentary; what matters for the contract is that we
          // stamp ONLY the survivors.

          // 2 of the 5 are already completed locally and get filtered
          // out by `PlaylistDownloadService.filterPendingUrls`.
          final pendingUrls = const [
            'https://yt/b',
            'https://yt/d',
            'https://yt/e',
          ];

          // POST-FIX behaviour: stamp on pendingUrls (NOT
          // originalUrls). This is the contract `home_batch_download_
          // mixin.dart` now obeys.
          h.stampBatch(
            pendingUrls,
            playlistId: 'yt_PL',
            playlistTitle: 'Mix',
          );

          // Skipped URLs must NEVER have a stamp. Pre-fix, they did.
          expect(h.consume('https://yt/a'), isNull,
              reason: 'P1 BUG: skipped URL would carry a stale stamp');
          expect(h.consume('https://yt/c'), isNull,
              reason: 'P1 BUG: skipped URL would carry a stale stamp');

          // Pending URLs are stamped and ready for repository consume.
          expect(h.consume('https://yt/b')?.playlistIndex, 0);
          expect(h.consume('https://yt/d')?.playlistIndex, 1);

          // After the batch completes (or aborts), the trailing
          // `clearForUrls(urls)` must use `pendingUrls` (= local
          // `urls` var post-rebind). Since we already consumed b/d,
          // only e is left. clearForUrls evicts it cleanly.
          h.clearForUrls(pendingUrls);
          expect(h.pendingCount, 0,
              reason: 'Holder must end the batch with zero pending stamps');
        },
      );

      test('P1 regression: pre-fix bug pattern leaks stamps', () {
        // Documenting what would HAVE happened pre-fix: stamping
        // on `uniqueUrls` then clearing only `pendingUrls` leaks
        // 2 stamps. We don't run the buggy flow in production code
        // anymore; this test exists to clarify what was wrong, so
        // a future "optimisation" doesn't reintroduce it without
        // someone reading this comment first.
        final h = PlaylistContextHolder();
        const uniqueUrls = ['a', 'b', 'c', 'd', 'e'];
        const pendingUrls = ['b', 'd', 'e'];

        h.stampBatch(uniqueUrls, playlistId: 'yt_PL', playlistTitle: null);
        // Simulate "all URLs failed extraction" — only pendingUrls
        // gets cleared.
        h.clearForUrls(pendingUrls);

        // Pre-fix bug — stamps for skipped URLs leak.
        expect(h.consume('a'), isNotNull);
        expect(h.consume('c'), isNotNull);
        // The leaked entries are real and would be consumed by a
        // future ad-hoc download of the same URL — that's the bug.
      });
    },
  );
}
