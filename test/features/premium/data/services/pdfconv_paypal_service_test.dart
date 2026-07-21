import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/core/network/backend_client.dart';
import 'package:svid/core/services/secure_credential_store.dart';
import 'package:svid/features/premium/data/services/pdfconv_paypal_service.dart';
import 'package:svid/features/premium/domain/entities/pdfconv_paypal_plan.dart';
import 'package:svid/features/premium/domain/entities/pdfconv_purchase_intent.dart';
import 'package:uuid/uuid.dart';

const _idempotencyKey = '970b0341-fc86-47bc-9a57-e2ddd218d356';
const _intentId = '0cc27c14-f861-44df-a656-00a519d6f22b';

Map<String, dynamic> _intentResponse({String billingStatus = 'created'}) => {
  'purchaseIntentId': _intentId,
  'billingStatus': billingStatus,
  'entitlementStatus': 'pending',
  'planId': 'p30',
  'approvalUrl': 'https://www.paypal.com/checkoutnow?token=ORDER-1',
  'retryable': false,
};

class _RecordedCall {
  final String method;
  final String path;
  final dynamic data;
  final Options? options;

  const _RecordedCall(this.method, this.path, this.data, this.options);
}

class _RecordingBackendClient extends BackendClient {
  final List<_RecordedCall> calls = [];
  Map<String, dynamic> response = _intentResponse();

  _RecordingBackendClient(super.credentials);

  @override
  Future<T> post<T>(
    String path, {
    dynamic data,
    Options? options,
    required T Function(dynamic json) fromJson,
  }) async {
    calls.add(_RecordedCall('POST', path, data, options));
    return fromJson(response);
  }

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    required T Function(dynamic json) fromJson,
  }) async {
    calls.add(_RecordedCall('GET', path, queryParameters, options));
    return fromJson(response);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingBackendClient client;
  late PdfConvPayPalService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    client = _RecordingBackendClient(SecureCredentialStore(prefs));
    service = PdfConvPayPalService(client);
  });

  test('create sends exact public API wire contract', () async {
    final result = await service.createIntent(
      planId: PdfConvPlanId.p30,
      buyerEmail: ' Buyer@Example.com ',
      idempotencyKey: _idempotencyKey,
    );

    expect(result.purchaseIntentId, _intentId);
    final call = client.calls.single;
    expect(call.method, 'POST');
    expect(call.path, '/premium/paypal/intents');
    expect(call.data, {'planId': 'p30', 'buyerEmail': 'buyer@example.com'});
    expect(call.options?.headers?['Idempotency-Key'], _idempotencyKey);
  });

  test('retries can reuse the exact same idempotency key', () async {
    for (var attempt = 0; attempt < 2; attempt++) {
      await service.createIntent(
        planId: PdfConvPlanId.p30,
        buyerEmail: 'buyer@example.com',
        idempotencyKey: _idempotencyKey,
      );
    }

    expect(client.calls, hasLength(2));
    expect(
      client.calls.map((call) => call.options?.headers?['Idempotency-Key']),
      everyElement(_idempotencyKey),
    );
  });

  test('capture posts an empty object to the bound intent', () async {
    client.response = _intentResponse(billingStatus: 'capture_pending');
    final result = await service.captureIntent(_intentId);

    expect(result.billingStatus, PdfConvBillingStatus.capturePending);
    final call = client.calls.single;
    expect(call.method, 'POST');
    expect(call.path, '/premium/paypal/intents/$_intentId/capture');
    expect(call.data, isEmpty);
    expect(call.options, isNull);
  });

  test('status gets the bound intent without query parameters', () async {
    client.response = _intentResponse(billingStatus: 'fulfilled');
    final result = await service.getIntentStatus(_intentId);

    expect(result.isAwaitingSettlement, isTrue);
    final call = client.calls.single;
    expect(call.method, 'GET');
    expect(call.path, '/premium/paypal/intents/$_intentId');
    expect(call.data, isNull);
  });

  test('new idempotency keys are valid UUIDs', () {
    expect(Uuid.isValidUUID(fromString: service.newIdempotencyKey()), isTrue);
  });

  test('invalid local UUIDs are rejected before any network call', () async {
    expect(() => service.captureIntent('not-a-uuid'), throwsFormatException);
    expect(
      () => service.createIntent(
        planId: PdfConvPlanId.p30,
        buyerEmail: 'buyer@example.com',
        idempotencyKey: 'not-a-uuid',
      ),
      throwsFormatException,
    );
    expect(client.calls, isEmpty);
  });

  test('unknown response state is not silently treated as pending', () async {
    client.response = _intentResponse(billingStatus: 'paid');
    expect(service.getIntentStatus(_intentId), throwsFormatException);
  });

  test('opens a safe approval URL through the injected launcher', () async {
    Uri? launchedUrl;
    final launchingService = PdfConvPayPalService(
      client,
      approvalLauncher: (url) async {
        launchedUrl = url;
        return true;
      },
    );
    final approvalUrl = Uri.parse(
      'https://www.paypal.com/checkoutnow?token=ORDER-1',
    );

    expect(await launchingService.openApprovalPage(approvalUrl), isTrue);
    expect(launchedUrl, approvalUrl);
  });

  test('browser launch failure returns false', () async {
    final launchingService = PdfConvPayPalService(
      client,
      approvalLauncher: (_) async => throw StateError('launcher failed'),
    );

    expect(
      await launchingService.openApprovalPage(
        Uri.parse('https://www.paypal.com/checkout'),
      ),
      isFalse,
    );
  });

  test('unsafe approval URL is rejected before launching', () async {
    var launchCalls = 0;
    final launchingService = PdfConvPayPalService(
      client,
      approvalLauncher: (_) async {
        launchCalls++;
        return true;
      },
    );

    expect(
      () => launchingService.openApprovalPage(
        Uri.parse('http://www.paypal.com/checkout'),
      ),
      throwsFormatException,
    );
    expect(launchCalls, 0);
  });
}
