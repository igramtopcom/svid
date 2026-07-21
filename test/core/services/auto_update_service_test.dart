import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/core/config/brand_config.dart';
import 'package:svid/core/services/auto_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  String installerExtension() {
    if (Platform.isMacOS) return '.dmg';
    if (Platform.isWindows) return '.exe';
    return '.AppImage';
  }

  String updatePath(String version) {
    return '${tempDir.path}/${BrandConfig.current.brand.name}_update_$version${installerExtension()}';
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('auto_update_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  AutoUpdateNotifier buildNotifier(
    http.Client client, {
    Duration? streamIdleTimeout,
    UpdateLifecycleTelemetry? onLifecycleEvent,
  }) {
    return AutoUpdateNotifier(
      httpClient: client,
      tempDirectoryProvider: () async => tempDir,
      streamIdleTimeout: streamIdleTimeout ?? const Duration(seconds: 45),
      onLifecycleEvent: onLifecycleEvent,
    );
  }

  group('AutoUpdateNotifier.downloadUpdate', () {
    test('reuses existing verified download without hitting network', () async {
      final bytes = utf8.encode('already downloaded update');
      final file = File(updatePath('1.2.3'));
      await file.writeAsBytes(bytes);
      var networkCalls = 0;
      final notifier = buildNotifier(
        MockClient((request) async {
          networkCalls++;
          return http.Response('unexpected', 500);
        }),
      );

      await notifier.downloadUpdate(
        'https://updates.example.com/app.dmg',
        sha256.convert(bytes).toString(),
        '1.2.3',
      );

      expect(networkCalls, 0);
      expect(notifier.state.status, UpdateStatus.readyToInstall);
      expect(notifier.state.installerPath, file.path);
      expect(notifier.state.receivedBytes, bytes.length);
      expect(notifier.state.progress, 1.0);
    });

    test('downloads and verifies update successfully', () async {
      final bytes = utf8.encode('fresh update binary');
      final lifecycleEvents = <String, Map<String, dynamic>>{};
      final notifier = buildNotifier(
        MockClient((request) async {
          expect(request.url.toString(), 'https://updates.example.com/app.dmg');
          return http.Response.bytes(bytes, 200);
        }),
        onLifecycleEvent: (eventName, properties) {
          lifecycleEvents[eventName] = properties;
        },
      );

      await notifier.downloadUpdate(
        'https://updates.example.com/app.dmg',
        sha256.convert(bytes).toString(),
        '2.0.0',
      );

      final file = File(updatePath('2.0.0'));
      expect(await file.exists(), isTrue);
      expect(notifier.state.status, UpdateStatus.readyToInstall);
      expect(notifier.state.installerPath, file.path);
      expect(notifier.state.totalBytes, bytes.length);
      expect(notifier.state.receivedBytes, bytes.length);
      expect(lifecycleEvents.keys, contains('update_download_verified'));
      expect(
        lifecycleEvents['update_download_verified'],
        containsPair('version', '2.0.0'),
      );
      expect(
        lifecycleEvents['update_download_verified'],
        containsPair('already_present', false),
      );
    });

    test('fails and deletes file on hash mismatch', () async {
      final bytes = utf8.encode('tampered update');
      final lifecycleEvents = <String, Map<String, dynamic>>{};
      final notifier = buildNotifier(
        MockClient((request) async => http.Response.bytes(bytes, 200)),
        onLifecycleEvent: (eventName, properties) {
          lifecycleEvents[eventName] = properties;
        },
      );

      await notifier.downloadUpdate(
        'https://updates.example.com/app.dmg',
        sha256.convert(utf8.encode('different payload')).toString(),
        '3.0.0',
      );

      final file = File(updatePath('3.0.0'));
      expect(notifier.state.status, UpdateStatus.failed);
      expect(
        notifier.state.error,
        'Integrity check failed — file hash does not match',
      );
      expect(await file.exists(), isFalse);
      expect(lifecycleEvents.keys, contains('update_download_failed'));
      expect(
        lifecycleEvents['update_download_failed'],
        containsPair('error_code', 'sha256_mismatch'),
      );
    });

    test('fails on non-200 responses', () async {
      final lifecycleEvents = <String, Map<String, dynamic>>{};
      final notifier = buildNotifier(
        MockClient((request) async => http.Response('server error', 503)),
        onLifecycleEvent: (eventName, properties) {
          lifecycleEvents[eventName] = properties;
        },
      );

      await notifier.downloadUpdate(
        'https://updates.example.com/app.dmg',
        '',
        '4.0.0',
      );

      expect(notifier.state.status, UpdateStatus.failed);
      expect(notifier.state.error, 'Download failed: HTTP 503');
      expect(lifecycleEvents.keys, contains('update_download_failed'));
      expect(
        lifecycleEvents['update_download_failed'],
        containsPair('http_status', 503),
      );
    });

    test('fails when CDN stalls after returning HTTP 200', () async {
      final stalledStream = StreamController<List<int>>();
      final notifier = buildNotifier(
        MockClient.streaming(
          (request, bodyStream) async => http.StreamedResponse(
            stalledStream.stream,
            200,
            contentLength: 10,
          ),
        ),
        streamIdleTimeout: const Duration(milliseconds: 20),
      );

      await notifier.downloadUpdate(
        'https://updates.example.com/stall.dmg',
        '',
        '5.0.0',
      );

      expect(notifier.state.status, UpdateStatus.failed);
      expect(notifier.state.error, contains('Update download stalled'));
      await stalledStream.close();
    });

    test('concurrent callers race-guarded — only one download starts AND '
        'only one telemetry event fires, even when three callers '
        '(startup mandatory + banner mandatory + dialog mandatory) fire '
        'on the same frame', () async {
      final bytes = utf8.encode('payload');
      var networkCalls = 0;
      final telemetry = <String>[];
      final notifier = AutoUpdateNotifier(
        httpClient: MockClient((request) async {
          networkCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return http.Response.bytes(bytes, 200);
        }),
        tempDirectoryProvider: () async => tempDir,
        onDownloadStarted: (version, source) {
          telemetry.add('$version:$source');
        },
      );

      await Future.wait(<Future<void>>[
        notifier.downloadUpdate(
          'https://updates.example.com/race.dmg',
          sha256.convert(bytes).toString(),
          '9.9.9',
          source: 'startup_mandatory',
        ),
        notifier.downloadUpdate(
          'https://updates.example.com/race.dmg',
          sha256.convert(bytes).toString(),
          '9.9.9',
          source: 'mandatory_auto',
        ),
        notifier.downloadUpdate(
          'https://updates.example.com/race.dmg',
          sha256.convert(bytes).toString(),
          '9.9.9',
          source: 'mandatory_auto',
        ),
      ]);

      // Round-5: collapsed to 1 network call.
      expect(
        networkCalls,
        1,
        reason: 'Race guard must collapse concurrent callers to 1 fetch.',
      );
      // Round-6: AND collapsed to 1 telemetry emit, fired from inside
      // downloadUpdate AFTER the guard wins. Without consolidation, 3
      // callers would have emitted 3 events even though only 1 actual
      // download happened, polluting the funnel.
      expect(
        telemetry.length,
        1,
        reason:
            'Telemetry must fire exactly once per real download — '
            'not once per caller.',
      );
      expect(telemetry.first, '9.9.9:startup_mandatory');
      expect(notifier.state.status, UpdateStatus.readyToInstall);
    });

    test(
      'guard releases after a failed attempt — retries are allowed',
      () async {
        var calls = 0;
        final notifier = buildNotifier(
          MockClient((request) async {
            calls++;
            if (calls == 1) return http.Response('err', 503);
            return http.Response.bytes(utf8.encode('ok'), 200);
          }),
        );

        await notifier.downloadUpdate(
          'https://updates.example.com/retry.dmg',
          '',
          '1.0.0',
        );
        expect(notifier.state.status, UpdateStatus.failed);

        // Without finally-release of the synchronous guard, this second
        // call would silently no-op forever after a single failure.
        await notifier.downloadUpdate(
          'https://updates.example.com/retry.dmg',
          '',
          '1.0.0',
        );
        expect(calls, 2);
      },
    );

    test('refuses to install an update with no checksum (integrity '
        'invariant) — even when the download itself succeeds', () async {
      final bytes = utf8.encode('unverified payload');
      var networkCalls = 0;
      final lifecycleEvents = <String, Map<String, dynamic>>{};
      final notifier = buildNotifier(
        MockClient((request) async {
          networkCalls++;
          return http.Response.bytes(bytes, 200);
        }),
        onLifecycleEvent: (eventName, properties) {
          lifecycleEvents[eventName] = properties;
        },
      );

      // The version.json fallback path carries no checksum. The chokepoint in
      // downloadUpdate must REFUSE rather than fall through to readyToInstall —
      // this is what stops every caller (startup / dialog / banner) from
      // installing an unverified binary.
      await notifier.downloadUpdate(
        'https://updates.example.com/no-checksum.dmg',
        '',
        '6.6.6',
        source: 'version_json_fallback',
      );

      expect(notifier.state.status, UpdateStatus.failed);
      expect(notifier.state.error, contains('checksum'));
      expect(notifier.state.installerPath, isNull);
      expect(
        lifecycleEvents['update_download_failed'],
        containsPair('error_code', 'missing_checksum'),
      );
      // The unverified artifact must not be left on disk.
      expect(await File(updatePath('6.6.6')).exists(), isFalse);
      // Guard sits at the verify gate (after download): the payload is fetched
      // once, then refused + deleted. Asserting this documents the current
      // placement — a future fail-fast-before-network change would make it 0.
      expect(networkCalls, 1);
    });
  });

  group('UpdateInstallAckService', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('emits completed when app opens at the target version', () async {
      final events = <String, Map<String, dynamic>>{};
      await UpdateInstallAckService.markHandoffStarted(
        prefs,
        targetVersion: '1.7.3',
        currentVersion: '1.7.2',
        source: 'mandatory_auto',
        now: DateTime.utc(2026, 6, 3),
      );

      await UpdateInstallAckService.reconcileOnStartup(
        prefs,
        currentVersion: '1.7.3',
        track: (eventName, properties) {
          events[eventName] = properties;
        },
        flush: () async => true,
      );

      expect(events.keys, contains('update_install_completed'));
      expect(
        events['update_install_completed'],
        containsPair('target_version', '1.7.3'),
      );
      expect(
        events['update_install_completed'],
        containsPair('previous_version', '1.7.2'),
      );
      expect(
        events['update_install_completed'],
        containsPair('source', 'mandatory_auto'),
      );
      expect(prefs.getString('app_update_pending_install_v1'), isNull);
    });

    test('emits not_applied when app reopens below target version', () async {
      final events = <String, Map<String, dynamic>>{};
      await UpdateInstallAckService.markHandoffStarted(
        prefs,
        targetVersion: '1.7.3',
        currentVersion: '1.7.2',
        source: 'banner_click',
      );

      await UpdateInstallAckService.reconcileOnStartup(
        prefs,
        currentVersion: '1.7.2',
        track: (eventName, properties) {
          events[eventName] = properties;
        },
        flush: () async => true,
      );

      expect(events.keys, contains('update_install_not_applied'));
      expect(
        events['update_install_not_applied'],
        containsPair('target_version', '1.7.3'),
      );
      expect(
        events['update_install_not_applied'],
        containsPair('current_version', '1.7.2'),
      );
      expect(prefs.getString('app_update_pending_install_v1'), isNull);
    });

    test('keeps pending marker when ack flush fails', () async {
      final events = <String, Map<String, dynamic>>{};
      await UpdateInstallAckService.markHandoffStarted(
        prefs,
        targetVersion: '1.7.3',
        currentVersion: '1.7.2',
        source: 'startup_mandatory',
      );

      await UpdateInstallAckService.reconcileOnStartup(
        prefs,
        currentVersion: '1.7.3',
        track: (eventName, properties) {
          events[eventName] = properties;
        },
        flush: () async => false,
      );

      expect(events.keys, contains('update_install_completed'));
      expect(prefs.getString('app_update_pending_install_v1'), isNotNull);
    });
  });
}
