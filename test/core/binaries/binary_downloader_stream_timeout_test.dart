import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:ssvid/core/binaries/binary_downloader.dart';
import 'package:ssvid/core/binaries/binary_info.dart';
import 'package:ssvid/core/binaries/binary_type.dart';

void main() {
  group('BinaryDownloader stream timeout', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'binary_downloader_timeout_test_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('emits error when CDN stalls after returning HTTP 200', () async {
      final stalledBody = StreamController<List<int>>();
      final client = MockClient.streaming((request, _) async {
        if (request.method == 'HEAD') {
          return http.StreamedResponse(const Stream.empty(), 200);
        }
        return http.StreamedResponse(
          stalledBody.stream,
          200,
          contentLength: 10,
        );
      });

      final downloader = BinaryDownloader(
        client: client,
        streamIdleTimeout: const Duration(milliseconds: 20),
      );
      final progress =
          await downloader
              .download(
                info: const BinaryInfo(
                  type: BinaryType.ytDlp,
                  version: 'test',
                  downloadUrl: 'https://example.test/yt-dlp',
                ),
                targetDir: tempDir.path,
              )
              .toList();

      expect(progress.first.status, BinaryDownloadStatus.starting);
      expect(progress.last.status, BinaryDownloadStatus.error);
      expect(progress.last.error, contains('timed out'));
      expect(
        File(p.join(tempDir.path, 'yt-dlp.download')).existsSync(),
        isFalse,
        reason: 'stalled partial downloads must be cleaned up',
      );

      await stalledBody.close();
      downloader.dispose();
    });
  });
}
