import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ssvid/core/binaries/ytdlp_version_service.dart';

void main() {
  group('YtDlpVersionService', () {
    group('fetchLatestVersion', () {
      test('returns tag_name from GitHub API', () async {
        final client = MockClient((request) async {
          expect(
            request.url.toString(),
            contains(
              'api.github.com/repos/yt-dlp/yt-dlp-master-builds/releases/latest',
            ),
          );
          return http.Response(
            jsonEncode({'tag_name': '2026.05.25.232152'}),
            200,
          );
        });

        final service = YtDlpVersionService(client: client);
        final version = await service.fetchLatestVersion();

        expect(version, '2026.05.25.232152');
        service.dispose();
      });

      test('returns null on non-200 response', () async {
        final client = MockClient((request) async {
          return http.Response('rate limited', 403);
        });

        final service = YtDlpVersionService(client: client);
        final version = await service.fetchLatestVersion();

        expect(version, isNull);
        service.dispose();
      });

      test('returns null on network error', () async {
        final client = MockClient((request) async {
          throw Exception('Network error');
        });

        final service = YtDlpVersionService(client: client);
        final version = await service.fetchLatestVersion();

        expect(version, isNull);
        service.dispose();
      });

      test('returns null when tag_name is missing', () async {
        final client = MockClient((request) async {
          return http.Response(jsonEncode({'name': 'release'}), 200);
        });

        final service = YtDlpVersionService(client: client);
        final version = await service.fetchLatestVersion();

        expect(version, isNull);
        service.dispose();
      });
    });

    group('isNewerVersion', () {
      late YtDlpVersionService service;

      setUp(() {
        service = YtDlpVersionService();
      });

      tearDown(() {
        service.dispose();
      });

      test('detects newer version (year)', () {
        expect(service.isNewerVersion('2026.01.01', '2025.12.31'), isTrue);
      });

      test('detects newer version (month)', () {
        expect(service.isNewerVersion('2025.03.01', '2025.02.28'), isTrue);
      });

      test('detects newer version (day)', () {
        expect(service.isNewerVersion('2025.02.20', '2025.02.19'), isTrue);
      });

      test('detects newer version with patch number', () {
        expect(service.isNewerVersion('2025.02.19.1', '2025.02.19'), isTrue);
      });

      test('detects newer master timestamp build', () {
        expect(
          service.isNewerVersion('2026.05.25.232152', '2026.05.25.224748'),
          isTrue,
        );
      });

      test('returns false for same version', () {
        expect(service.isNewerVersion('2025.02.19', '2025.02.19'), isFalse);
      });

      test('returns false for older version', () {
        expect(service.isNewerVersion('2025.01.15', '2025.02.19'), isFalse);
      });

      test('returns false for invalid format', () {
        expect(service.isNewerVersion('invalid', '2025.02.19'), isFalse);
        expect(service.isNewerVersion('2025.02.19', 'invalid'), isFalse);
      });
    });

    group('isUpdateAvailable', () {
      test('returns false for null installed version', () async {
        final service = YtDlpVersionService();
        final result = await service.isUpdateAvailable(null);
        expect(result, isFalse);
        service.dispose();
      });

      test('returns false for empty installed version', () async {
        final service = YtDlpVersionService();
        final result = await service.isUpdateAvailable('');
        expect(result, isFalse);
        service.dispose();
      });

      test('returns true when newer version available', () async {
        final client = MockClient((request) async {
          return http.Response(jsonEncode({'tag_name': '2025.03.01'}), 200);
        });

        final service = YtDlpVersionService(client: client);
        final result = await service.isUpdateAvailable('2025.02.19');

        expect(result, isTrue);
        service.dispose();
      });

      test('returns false when already up to date', () async {
        final client = MockClient((request) async {
          return http.Response(jsonEncode({'tag_name': '2025.02.19'}), 200);
        });

        final service = YtDlpVersionService(client: client);
        final result = await service.isUpdateAvailable('2025.02.19');

        expect(result, isFalse);
        service.dispose();
      });
    });
  });
}
