import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ssvid/features/downloads/data/datasources/ytdlp_datasource.dart';

/// DL-FB-FINALPATH-1: Facebook pathNotFound from final-path resolution.
///
/// When the `.final_path` sidecar is empty/stale and the stdout-parsed path
/// is a download-FRAGMENT destination rather than the merged output (the
/// Facebook multi-stream case), the resolved path is not on disk and the
/// move returns a constructed predicted path → the download completes as
/// pathNotFound even though the file IS present. `_findPrimaryOutputFile`
/// recovers the real merged output. These tests lock the acceptance:
/// returned path exists, is non-zero, and is never an intermediate/sidecar.
void main() {
  group('DL-FB-FINALPATH-1 _findPrimaryOutputFile', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('fb_finalpath_');
    });
    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    Future<void> write(String name, int bytes) async {
      await File(p.join(temp.path, name)).writeAsBytes(List.filled(bytes, 0x41));
    }

    test(
        'promotes the real merged mp4 over a stale .final_path sidecar + '
        'fragments + subtitle (the Facebook stale-resolution case)', () async {
      await write('.final_path', 50); // internal sidecar (stale)
      await write('Cat Video.f399v.mp4', 1000); // video fragment (intermediate)
      await write('Cat Video.f140a.m4a', 200); // audio fragment (intermediate)
      await write('Cat Video.en.srt', 80); // subtitle sidecar
      await write('Cat Video.mp4', 5000); // the REAL merged output (largest)

      final result =
          await YtDlpDataSource.findPrimaryOutputFileForTest(temp.path);

      expect(result, isNotNull);
      expect(p.basename(result!), 'Cat Video.mp4');
      expect(await File(result).exists(), isTrue); // exists
      expect(await File(result).length(), greaterThan(0)); // non-zero
      // never the sidecar / a fragment / a subtitle
      expect(result, isNot(contains('.final_path')));
      expect(result, isNot(contains('.f399v.')));
      expect(result, isNot(endsWith('.srt')));
    });

    test('returns null when only the sidecar + aux files exist (no media)',
        () async {
      await write('.final_path', 50);
      await write('Video.en.srt', 80);
      await write('Video.jpg', 300);
      await write('Video.info.json', 400);
      expect(
        await YtDlpDataSource.findPrimaryOutputFileForTest(temp.path),
        isNull,
      );
    });

    test('skips zero-byte files and .part partials (never completes a partial)',
        () async {
      await write('Video.part', 9999); // incomplete download
      await write('Video.mp4', 0); // zero-byte placeholder
      expect(
        await YtDlpDataSource.findPrimaryOutputFileForTest(temp.path),
        isNull,
      );
    });

    test('single muxed file (no merge step) is returned as-is', () async {
      await write('Reel.mp4', 1234);
      final r = await YtDlpDataSource.findPrimaryOutputFileForTest(temp.path);
      expect(p.basename(r!), 'Reel.mp4');
    });

    test('non-existent temp dir → null (no throw)', () async {
      expect(
        await YtDlpDataSource.findPrimaryOutputFileForTest(
          p.join(temp.path, 'does-not-exist'),
        ),
        isNull,
      );
    });

    test(
        'CONTRACT (Codex P1): a promoted .mkv for an MP4 pick is still caught '
        'by the C3 container guard — the promote runs BEFORE C3, so a wrong '
        'container is salvaged/failed, never silently completed', () async {
      // mp4-incompatible source merged to .mkv; resolved path missing.
      await write('Some Video.mkv', 5000);
      final promoted =
          await YtDlpDataSource.findPrimaryOutputFileForTest(temp.path);
      expect(p.basename(promoted!), 'Some Video.mkv');

      // The C3 guard (now downstream of the promote) flags mkv-vs-mp4 — it
      // will salvage-recode to mp4 or hard-fail; it does NOT silently
      // complete .mkv for an MP4 pick.
      final mismatch = YtDlpDataSource.detectFinalExtensionMismatch(
        outputPath: promoted,
        videoFormat: 'mp4',
      );
      expect(mismatch, isNotNull);
      expect(mismatch!.expected, 'mp4');
      expect(mismatch.actual, 'mkv');

      // And when the promoted file already matches the pick (the Facebook
      // H.264/AAC → .mp4 case), C3 sees no mismatch → fast completion.
      expect(
        YtDlpDataSource.detectFinalExtensionMismatch(
          outputPath: p.join(temp.path, 'Some Video.mp4'),
          videoFormat: 'mp4',
        ),
        isNull,
      );
    });
  });
}
