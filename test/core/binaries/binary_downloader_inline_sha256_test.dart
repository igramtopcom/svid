import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:svid/core/binaries/binary_downloader.dart';
import 'package:svid/core/binaries/binary_info.dart';
import 'package:svid/core/binaries/binary_type.dart';

/// Inline SHA-256 pinning is the supply-chain defense for binaries
/// whose upstream publishes no co-located `SHA2-256SUMS` manifest
/// (Deno is the canonical case — the hash is pinned at build time
/// in `binary_info.dart` and refreshed on version bumps). The
/// downloader MUST verify the downloaded payload against `info.sha256`
/// and FAIL CLOSED on mismatch — accepting a different binary than
/// pinned would defeat the whole defense.
void main() {
  group('BinaryDownloader inline SHA-256 pin', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'binary_downloader_inline_sha_test_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    /// Build a downloader whose HTTP layer returns [body] for the
    /// download request, so we can deterministically assert behavior
    /// for both matching and mismatching pinned hashes.
    BinaryDownloader buildDownloaderReturning(Uint8List body) {
      final client = MockClient.streaming((request, _) async {
        if (request.method == 'HEAD') {
          return http.StreamedResponse(const Stream.empty(), 200);
        }
        return http.StreamedResponse(
          Stream.value(body),
          200,
          contentLength: body.length,
        );
      });
      return BinaryDownloader(client: client);
    }

    test('accepts the binary when the inline hash matches', () async {
      final body = Uint8List.fromList(utf8.encode('deno-bytes'));
      final pinned = sha256.convert(body).toString();

      final downloader = buildDownloaderReturning(body);
      final progress = await downloader
          .download(
            info: BinaryInfo(
              type: BinaryType.deno,
              version: 'test',
              downloadUrl: 'https://example.test/deno',
              sha256: pinned,
            ),
            targetDir: tempDir.path,
          )
          .toList();

      expect(
        progress.last.status,
        BinaryDownloadStatus.completed,
        reason: 'matching pin must allow the binary through',
      );
      expect(
        File(p.join(tempDir.path, BinaryType.deno.filename)).existsSync(),
        isTrue,
        reason: 'final binary must land at target path '
            '(platform-aware: `deno.exe` on Windows, `deno` elsewhere)',
      );
      downloader.dispose();
    });

    test('refuses the binary when the inline hash mismatches', () async {
      final body = Uint8List.fromList(utf8.encode('deno-bytes'));
      // Deliberately wrong hash — this is the supply-chain attack:
      // CDN returns a *different* file than the one whose hash was
      // pinned, and the downloader must reject it.
      final wrongPin = '0' * 64;

      final downloader = buildDownloaderReturning(body);
      final progress = await downloader
          .download(
            info: BinaryInfo(
              type: BinaryType.deno,
              version: 'test',
              downloadUrl: 'https://example.test/deno',
              sha256: wrongPin,
            ),
            targetDir: tempDir.path,
          )
          .toList();

      expect(progress.last.status, BinaryDownloadStatus.error);
      expect(progress.last.error, contains('Integrity verification failed'));
      expect(progress.last.error, contains('Pinned SHA-256 expected'));
      expect(
        File(p.join(tempDir.path, BinaryType.deno.filename)).existsSync(),
        isFalse,
        reason: 'mismatched binary must NOT be installed',
      );
      expect(
        File(p.join(tempDir.path, '${BinaryType.deno.filename}.download'))
            .existsSync(),
        isFalse,
        reason: 'the rejected partial download must be cleaned up',
      );
      downloader.dispose();
    });

    test('matches case-insensitively (upstream may publish uppercase)',
        () async {
      final body = Uint8List.fromList(utf8.encode('deno-bytes'));
      final pinnedUpper = sha256.convert(body).toString().toUpperCase();

      final downloader = buildDownloaderReturning(body);
      final progress = await downloader
          .download(
            info: BinaryInfo(
              type: BinaryType.deno,
              version: 'test',
              downloadUrl: 'https://example.test/deno',
              sha256: pinnedUpper,
            ),
            targetDir: tempDir.path,
          )
          .toList();

      expect(
        progress.last.status,
        BinaryDownloadStatus.completed,
        reason: 'hex compare must be case-insensitive',
      );
      downloader.dispose();
    });
  });
}
