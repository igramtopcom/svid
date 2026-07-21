import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/core/network/backend_client.dart';
import 'package:svid/core/services/secure_credential_store.dart';

import '../services/fake_error_reporter.dart';

/// Item B integration tests: drive the REAL `BackendClient` (auth +
/// Sentry + log interceptors) through a stub `HttpClientAdapter`. This
/// proves the production interceptor wiring, not a mirror.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SecureCredentialStore credentials;
  late FakeErrorReporter reporter;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    credentials = SecureCredentialStore(prefs);
    reporter = FakeErrorReporter();
  });

  Future<BackendClient> buildClientWith(_StubAdapter adapter) async {
    final client = BackendClient(credentials, errorReporter: reporter);
    client.httpClientAdapterForTesting = adapter;
    return client;
  }

  group('http breadcrumb on success', () {
    test('successful POST emits http breadcrumb', () async {
      final client = await buildClientWith(_StubAdapter([
        _CannedResponse(200, {'success': true, 'data': {}}),
      ]));

      await client.post(
        '/bugs',
        data: const {'title': 'x'},
        fromJson: (j) => j,
      );
      expect(reporter.breadcrumbs, contains('http'));
      expect(reporter.capturedScopedExceptions, isEmpty);
    });
  });

  group('self-protection: backendInternalRequestFlag', () {
    test(
        'submitCrash-style internal POST → no breadcrumb, no event on 5xx',
        () async {
      final client = await buildClientWith(_StubAdapter([
        _CannedResponse(500, {'error': 'boom'}),
      ]));

      try {
        await client.post(
          '/crashes',
          data: const {},
          options: Options(extra: const {backendInternalRequestFlag: true}),
          fromJson: (j) => j,
        );
      } catch (_) {/* expected */}

      expect(reporter.breadcrumbs, isEmpty,
          reason: 'internal requests must not emit breadcrumbs');
      expect(reporter.capturedScopedExceptions, isEmpty,
          reason: 'internal requests must not capture transport events');
    });

    test(
        'envelope failure on internal POST → no captured event (loop break)',
        () async {
      final client = await buildClientWith(_StubAdapter([
        _CannedResponse(200,
            {'success': false, 'error': {'code': 'X', 'message': 'fail'}}),
      ]));

      try {
        await client.post(
          '/crashes',
          data: const {},
          options: Options(extra: const {backendInternalRequestFlag: true}),
          fromJson: (j) => j,
        );
      } catch (_) {/* expected */}

      expect(reporter.capturedScopedExceptions, isEmpty,
          reason: '_reportEnvelopeError must skip internal requests');
    });

    test('non-internal POST → captures transport event on 5xx', () async {
      final client = await buildClientWith(_StubAdapter([
        _CannedResponse(500, {'error': 'boom'}),
      ]));

      try {
        await client.post('/bugs', data: const {}, fromJson: (j) => j);
      } catch (_) {/* expected */}

      expect(reporter.capturedScopedExceptions, hasLength(1));
      final captured = reporter.capturedScopedExceptions.single;
      expect(captured.capturedTags['op'], 'http.transport_error');
      expect(captured.capturedTags['http.method'], 'POST');
    });
  });

  group('envelope failure tap', () {
    test('200 + success:false → captures envelope event', () async {
      final client = await buildClientWith(_StubAdapter([
        _CannedResponse(200,
            {'success': false, 'error': {'code': 'BAD', 'message': 'oops'}}),
      ]));

      try {
        await client.post('/bugs', data: const {}, fromJson: (j) => j);
      } catch (_) {/* expected */}

      // One envelope event (from _reportEnvelopeError); regular http
      // breadcrumb on response is also emitted.
      expect(reporter.capturedScopedExceptions, hasLength(1));
      final captured = reporter.capturedScopedExceptions.single;
      expect(captured.capturedTags['op'], 'http.envelope_error');
      expect(captured.capturedTags['http.envelope_error_code'], 'BAD');
    });

    test('postVoid envelope failure → bit-exact behavior + envelope event',
        () async {
      final client = await buildClientWith(_StubAdapter([
        _CannedResponse(200,
            {'success': false, 'error': {'message': 'nope'}}),
      ]));

      Object? caught;
      try {
        await client.postVoid('/foo', data: const {});
      } catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      // Bit-exact preservation: void variant uses `'Request failed'` as
      // fallback (NOT `'Unknown error'`); but here error provided 'nope'.
      expect(caught.toString(), contains('nope'));
      // Envelope event captured.
      expect(reporter.capturedScopedExceptions, hasLength(1));
    });

    test('postVoid with no error message → falls back to "Request failed"',
        () async {
      final client = await buildClientWith(_StubAdapter([
        _CannedResponse(200, {'success': false}),
      ]));

      Object? caught;
      try {
        await client.postVoid('/foo', data: const {});
      } catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught.toString(), contains('Request failed'),
          reason: 'void variant must use "Request failed" fallback, '
              'NOT "Unknown error" — bit-exact with prior behavior');
    });
  });

  group('_mapDioError — license-verdict reason extraction (P2 device-limit)', () {
    DioException badResponse(int status, Object body) => DioException(
          requestOptions: RequestOptions(path: '/premium/licenses/verify'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/premium/licenses/verify'),
            statusCode: status,
            data: body,
          ),
        );

    test(
        'device-limit real envelope (403 + success:true/data.reason) preserves '
        'reason so it is NOT a fail-open offline grace', () async {
      final client = BackendClient(credentials, errorReporter: reporter);
      // Exact shape the deployed backend returns for ErrDeviceLimitReached:
      // response.Success(c, 403, result) -> {success:true, data:{reason,...}}.
      final mapped = client.mapDioErrorForTest(badResponse(403, const {
        'success': true,
        'data': {'reason': 'device_limit_exceeded', 'is_valid': false},
      }));
      final code = mapped.maybeWhen(
        network: (message, statusCode, data) => data,
        orElse: () => null,
      );
      expect(code, 'device_limit_exceeded',
          reason: 'data.reason must survive so serverVerdictFor4xx can demote');
    });

    test('standard error envelope still maps error.code', () async {
      final client = BackendClient(credentials, errorReporter: reporter);
      final mapped = client.mapDioErrorForTest(badResponse(404, const {
        'error': {'code': 'INVALID_LICENSE_KEY', 'message': 'nope'},
      }));
      final code = mapped.maybeWhen(
        network: (message, statusCode, data) => data,
        orElse: () => null,
      );
      expect(code, 'INVALID_LICENSE_KEY');
    });

    test('bare non-2xx with no code/reason → data null (offline grace)',
        () async {
      final client = BackendClient(credentials, errorReporter: reporter);
      final mapped = client.mapDioErrorForTest(badResponse(403, const {
        'success': false,
      }));
      final code = mapped.maybeWhen(
        network: (message, statusCode, data) => data,
        orElse: () => null,
      );
      expect(code, isNull);
    });
  });
}

// --- Test helpers ---

class _CannedResponse {
  final int statusCode;
  final Object body;
  _CannedResponse(this.statusCode, this.body);
}

class _StubAdapter implements HttpClientAdapter {
  final List<_CannedResponse> responses;
  int _index = 0;

  _StubAdapter(this.responses);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final canned = responses[_index.clamp(0, responses.length - 1)];
    _index++;
    final bodyBytes = utf8.encode(
      canned.body is String ? canned.body as String : jsonEncode(canned.body),
    );
    return ResponseBody.fromBytes(
      bodyBytes,
      canned.statusCode,
      headers: const {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
