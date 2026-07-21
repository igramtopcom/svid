import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/domain/services/telemetry_metadata_keys.dart';

void main() {
  group('extractHttpStatusCode', () {
    test('extracts code from Rust executor HTTP_403_FORBIDDEN: prefix', () {
      expect(
        TelemetryMetadataKeys.extractHttpStatusCode(
          'HTTP_403_FORBIDDEN: youtube returned access denied',
        ),
        403,
      );
    });

    test('extracts code from HTTP_410_GONE: prefix', () {
      expect(
        TelemetryMetadataKeys.extractHttpStatusCode(
          'HTTP_410_GONE: video removed by uploader',
        ),
        410,
      );
    });

    test('extracts code from yt-dlp text "HTTP Error 403"', () {
      expect(
        TelemetryMetadataKeys.extractHttpStatusCode(
          'ERROR: unable to download video data: HTTP Error 403: Forbidden',
        ),
        403,
      );
    });

    test('case-insensitive http error match', () {
      expect(
        TelemetryMetadataKeys.extractHttpStatusCode('http error 429'),
        429,
      );
    });

    test('extracts code from "status 502"', () {
      expect(
        TelemetryMetadataKeys.extractHttpStatusCode(
          'fragment download failed: status 502 Bad Gateway',
        ),
        502,
      );
    });

    test('extracts code from "status code 504"', () {
      expect(
        TelemetryMetadataKeys.extractHttpStatusCode(
          'gateway timeout, status code 504',
        ),
        504,
      );
    });

    test('returns null when no HTTP status present', () {
      expect(
        TelemetryMetadataKeys.extractHttpStatusCode(
          'SocketException: Connection refused',
        ),
        isNull,
      );
    });

    test('returns null for unrelated 3-digit numbers (no http context)', () {
      // "123" alone must not be misread as a status code.
      expect(
        TelemetryMetadataKeys.extractHttpStatusCode('ERROR: video id 123abc'),
        isNull,
      );
    });
  });

  group('extractFormatProtocol', () {
    test('recognises http_dash_segments yt-dlp protocol', () {
      expect(
        TelemetryMetadataKeys.extractFormatProtocol(
          'fragment of http_dash_segments format 233 failed',
        ),
        'http_dash_segments',
      );
    });

    test('recognises "DASH segment" wording', () {
      expect(
        TelemetryMetadataKeys.extractFormatProtocol(
          'unable to download DASH segment',
        ),
        'http_dash_segments',
      );
    });

    test('recognises m3u8_native protocol explicitly', () {
      expect(
        TelemetryMetadataKeys.extractFormatProtocol(
          'protocol m3u8_native failed mid-stream',
        ),
        'm3u8_native',
      );
    });

    test('recognises plain .m3u8 manifest URL', () {
      expect(
        TelemetryMetadataKeys.extractFormatProtocol(
          'failed to fetch https://cdn.example.com/playlist.m3u8',
        ),
        'm3u8',
      );
    });

    test('recognises rtmp:// scheme', () {
      expect(
        TelemetryMetadataKeys.extractFormatProtocol(
          'rtmp:// stream rejected',
        ),
        'rtmp',
      );
    });

    test('falls back to https when HTTP status is present', () {
      expect(
        TelemetryMetadataKeys.extractFormatProtocol(
          'HTTPS GET failed with HTTP error 403',
        ),
        'https',
      );
    });

    test('falls back to http when HTTP status present without scheme hint', () {
      expect(
        TelemetryMetadataKeys.extractFormatProtocol(
          'HTTP_429_TOO_MANY_REQUESTS: rate limited',
        ),
        'http',
      );
    });

    test(
      'returns null for plain SocketException without protocol or status',
      () {
        // Plain TCP failure should not claim a protocol bucket.
        expect(
          TelemetryMetadataKeys.extractFormatProtocol(
            'SocketException: failed host lookup',
          ),
          isNull,
        );
      },
    );
  });
}
