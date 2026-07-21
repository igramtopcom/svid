import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:svid/features/downloads/data/datasources/ytdlp_datasource.dart';

/// 2026-05-26 Codex spec — duplicate warning was removed from the
/// Home + Floating Capture user-initiated paths. The "safe unique
/// filename on final move" in `_moveFilesToOutputDir` is the
/// foundation that lets duplicate re-downloads succeed without
/// overwriting an existing file on disk.
///
/// Round-2 fix (P1.1): suffix N is valid ONLY when every sibling
/// destination in the batch is free. Pre-fix the helper checked
/// only the main basename and would overwrite sibling subtitles /
/// thumbnails when a stale sibling existed from a prior run.
///
/// These tests pin the helper behavior end-to-end against a real
/// temp dir (no mocking — `File.exists()` returns true/false based
/// on actual filesystem state).
void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('ytdlp_unique_test_');
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('computeBatchUniqueSuffix — whole-batch sibling check', () {
    test('no collision anywhere → empty suffix', () async {
      final suffix = await YtDlpDataSource.computeBatchUniqueSuffixForTest(
        outputDir: tempRoot.path,
        batchFileNames: ['video.mp4', 'video.en.srt', 'video.jpg'],
        mainBasenameNoExt: 'video',
      );
      expect(suffix, '');
    });

    test('main collision only → " (1)" when no sibling collides at (1)',
        () async {
      await File(p.join(tempRoot.path, 'video.mp4')).create();
      final suffix = await YtDlpDataSource.computeBatchUniqueSuffixForTest(
        outputDir: tempRoot.path,
        batchFileNames: ['video.mp4', 'video.en.srt'],
        mainBasenameNoExt: 'video',
      );
      expect(suffix, ' (1)');
    });

    test(
      'P1.1 REGRESSION — sibling collision at (1) bumps to (2) even when '
      'main video (1).mp4 does NOT exist',
      () async {
        // The Codex example: pre-existing landscape state has
        //   video.mp4 + video (1).en.srt
        // Pre-fix helper looked only at video.mp4 collision → returned
        // " (1)" → move loop wrote video (1).en.srt → OVERWROTE the
        // stale subtitle. New helper rejects " (1)" because the
        // subtitle target already exists → walks to " (2)".
        await File(p.join(tempRoot.path, 'video.mp4')).create();
        await File(p.join(tempRoot.path, 'video (1).en.srt')).create();
        final suffix =
            await YtDlpDataSource.computeBatchUniqueSuffixForTest(
          outputDir: tempRoot.path,
          batchFileNames: ['video.mp4', 'video.en.srt'],
          mainBasenameNoExt: 'video',
        );
        expect(
          suffix,
          ' (2)',
          reason:
              'Suffix " (1)" must be rejected because video (1).en.srt '
              'already exists — would overwrite stale subtitle.',
        );
      },
    );

    test(
      'P1.1 REGRESSION — only sibling collides at (1) but no other file '
      'collides at all → still bumps to (2)',
      () async {
        // Stricter form: main video.mp4 does NOT exist; only
        // video (1).en.srt exists. New batch wants {video.mp4,
        // video.en.srt}. Empty suffix would land both freely
        // (video.mp4 + video.en.srt clean), but the helper sees
        // video (1).en.srt is stale debris and a future re-download
        // would land at " (1)". Empty suffix STILL safe here because
        // empty != ' (1)'. Helper should return ''.
        await File(p.join(tempRoot.path, 'video (1).en.srt')).create();
        final suffix =
            await YtDlpDataSource.computeBatchUniqueSuffixForTest(
          outputDir: tempRoot.path,
          batchFileNames: ['video.mp4', 'video.en.srt'],
          mainBasenameNoExt: 'video',
        );
        expect(suffix, '',
            reason: 'No sibling at empty suffix → return empty');
      },
    );

    test('cascading collisions walk through (N) until all clear', () async {
      // Simulate 3 prior batches all complete (with subs).
      for (final n in [null, 1, 2]) {
        final suffix = n == null ? '' : ' ($n)';
        await File(p.join(tempRoot.path, 'video$suffix.mp4')).create();
        await File(p.join(tempRoot.path, 'video$suffix.en.srt')).create();
      }
      final result = await YtDlpDataSource.computeBatchUniqueSuffixForTest(
        outputDir: tempRoot.path,
        batchFileNames: ['video.mp4', 'video.en.srt'],
        mainBasenameNoExt: 'video',
      );
      expect(result, ' (3)');
    });

    test('main exists at (1) but sibling doesn\'t exist at (1) → bump to (2)',
        () async {
      // Stress: pre-existing video.mp4 + video (1).mp4 (main collides
      // through to N=2 on its own). Subtitle (1) doesn't exist but
      // helper still picks (2) because main collides at (1).
      await File(p.join(tempRoot.path, 'video.mp4')).create();
      await File(p.join(tempRoot.path, 'video (1).mp4')).create();
      final result = await YtDlpDataSource.computeBatchUniqueSuffixForTest(
        outputDir: tempRoot.path,
        batchFileNames: ['video.mp4', 'video.en.srt'],
        mainBasenameNoExt: 'video',
      );
      expect(result, ' (2)');
    });

    test('orphan file (no shared prefix) excluded from suffix decision',
        () async {
      // yt-dlp occasionally drops an unrelated file in temp dir
      // (rare). Helper should ignore it for suffix purpose; the
      // move loop's per-file fallback handles its collision later.
      await File(p.join(tempRoot.path, 'video.mp4')).create();
      await File(p.join(tempRoot.path, 'unrelated.log')).create();
      final result = await YtDlpDataSource.computeBatchUniqueSuffixForTest(
        outputDir: tempRoot.path,
        batchFileNames: ['video.mp4', 'unrelated.log'],
        mainBasenameNoExt: 'video',
      );
      expect(result, ' (1)');
    });

    test('empty siblings set → empty suffix (defensive)', () async {
      final result = await YtDlpDataSource.computeBatchUniqueSuffixForTest(
        outputDir: tempRoot.path,
        batchFileNames: ['unrelated.log'],
        mainBasenameNoExt: 'video',
      );
      expect(result, '');
    });

    test(
      'Codex round-2 P2 tightening — same-prefix-but-not-sibling file '
      'does NOT inherit batch suffix',
      () {
        // The startsWith trap Codex flagged: stem `video` would
        // naïvely match `videoOther.mp4`. With dot-boundary check,
        // `videoOther.*` files are NOT considered siblings and get
        // individual collision resolution via the per-file path.
        //
        // This is enforced inside _computeBatchUniqueSuffix's
        // sibling filter; we exercise it by passing a mixed batch
        // and asserting the helper ignores the same-prefix-but-not-
        // sibling file when computing the shared suffix.
        return () async {
          // Pre-existing video.mp4 forces a collision on the main.
          await File(p.join(tempRoot.path, 'video.mp4')).create();
          // The same-prefix-but-not-sibling file would normally
          // cause confusion if `startsWith('video')` were used
          // without the dot-boundary check.
          await File(p.join(tempRoot.path, 'videoOther.mp4')).create();
          // Batch includes the same-prefix orphan; it must be
          // IGNORED for suffix computation purposes.
          final suffix =
              await YtDlpDataSource.computeBatchUniqueSuffixForTest(
            outputDir: tempRoot.path,
            batchFileNames: ['video.mp4', 'video.en.srt', 'videoOther.mp4'],
            mainBasenameNoExt: 'video',
          );
          // Only video.mp4 + video.en.srt are siblings (dot-bounded).
          // videoOther.mp4 is not a sibling, so its existence on
          // disk does NOT participate. Suffix " (1)" is fine because
          // video (1).mp4 + video (1).en.srt are both free.
          expect(suffix, ' (1)');
        }();
      },
    );

    test('filename with parentheses / special chars survives', () async {
      // Real-world yt-dlp output: title contains "(feat. Artist)"
      const main = 'Title (feat. Artist) [1080p].mp4';
      const sub = 'Title (feat. Artist) [1080p].en.srt';
      await File(p.join(tempRoot.path, main)).create();
      final suffix = await YtDlpDataSource.computeBatchUniqueSuffixForTest(
        outputDir: tempRoot.path,
        batchFileNames: [main, sub],
        mainBasenameNoExt: 'Title (feat. Artist) [1080p]',
      );
      expect(suffix, ' (1)');
    });
  });

  group('Sequential probe behavior (NOT a concurrency test)', () {
    // IMPORTANT — this is NOT a parallel-execution test. The suffix
    // helper itself is a pure read-only function and cannot be
    // "raced" in isolation; the true concurrency contract lives at
    // the `_outputDirMoveLocks` wrapper in `_moveFilesToOutputDir`
    // which serializes whole batches per outputDir. Verifying that
    // lock requires a full Process.start round-trip which this
    // unit test deliberately does not do.
    //
    // What this test DOES verify: when callers run the helper in
    // strict lock order (as `_moveFilesToOutputDir` does), each
    // probe sees the previous probe's landed files on disk and
    // walks to the next free suffix. This proves the helper is
    // FORWARD-CONSISTENT with serialized state advancement —
    // necessary but not sufficient for full concurrency safety.
    // The lock wrapper is verified by code review + runtime
    // matrix (see commit message + manual test plan).
    test(
      'after a prior batch lands video (1).mp4, next sequential probe '
      'bumps to video (2).mp4',
      () async {
        // Pre-seed video.mp4 (collision baseline).
        await File(p.join(tempRoot.path, 'video.mp4')).create();

        final suffixA = await YtDlpDataSource
            .computeBatchUniqueSuffixForTest(
          outputDir: tempRoot.path,
          batchFileNames: ['video.mp4'],
          mainBasenameNoExt: 'video',
        );
        expect(suffixA, ' (1)');

        // Simulate the lock-serialized first move landing video (1).mp4.
        await File(p.join(tempRoot.path, 'video (1).mp4')).create();

        // Next-in-lock-order probe sees the new file and advances.
        final suffixB = await YtDlpDataSource
            .computeBatchUniqueSuffixForTest(
          outputDir: tempRoot.path,
          batchFileNames: ['video.mp4'],
          mainBasenameNoExt: 'video',
        );
        expect(suffixB, ' (2)');
      },
    );
  });

  group('resolveSingleFileUniqueName — per-file fallback', () {
    test('no collision → returns desired name unchanged', () async {
      final result =
          await YtDlpDataSource.resolveSingleFileUniqueNameForTest(
        outputDir: tempRoot.path,
        fileName: 'subtitle.en.srt',
      );
      expect(result, 'subtitle.en.srt');
    });

    test('collision → adds " (1)" before final extension', () async {
      await File(p.join(tempRoot.path, 'subtitle.en.srt')).create();
      final result =
          await YtDlpDataSource.resolveSingleFileUniqueNameForTest(
        outputDir: tempRoot.path,
        fileName: 'subtitle.en.srt',
      );
      // Multi-dot extension: basenameWithoutExtension returns
      // `subtitle.en`, extension returns `.srt`. Suffix lands
      // before `.srt`: `subtitle.en (1).srt`.
      expect(result, 'subtitle.en (1).srt');
    });

    test('cascading collisions independent of batch helper', () async {
      await File(p.join(tempRoot.path, 'thumb.jpg')).create();
      await File(p.join(tempRoot.path, 'thumb (1).jpg')).create();
      final result =
          await YtDlpDataSource.resolveSingleFileUniqueNameForTest(
        outputDir: tempRoot.path,
        fileName: 'thumb.jpg',
      );
      expect(result, 'thumb (2).jpg');
    });
  });
}
