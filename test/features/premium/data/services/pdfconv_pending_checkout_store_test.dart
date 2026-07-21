import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssvid/core/services/secure_credential_store.dart';
import 'package:ssvid/features/premium/data/services/pdfconv_pending_checkout_store.dart';
import 'package:ssvid/features/premium/domain/entities/pdfconv_paypal_plan.dart';

const _idempotencyKey = '970b0341-fc86-47bc-9a57-e2ddd218d356';
const _intentId = '0cc27c14-f861-44df-a656-00a519d6f22b';

class _MemoryCredentialStore extends SecureCredentialStore {
  final values = <String, String>{};

  _MemoryCredentialStore(super.prefs);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryCredentialStore credentials;
  late PdfConvPendingCheckoutStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    credentials = _MemoryCredentialStore(prefs);
    store = PdfConvPendingCheckoutStore(credentials);
  });

  test('persists pre-request marker without an intent ID', () async {
    final marker = PdfConvPendingCheckout(
      idempotencyKey: _idempotencyKey,
      planId: PdfConvPlanId.p30,
      buyerEmail: 'buyer@example.com',
      createdAt: DateTime.utc(2026, 7, 17, 10),
    );

    await store.write(marker);
    final restored = await store.read();

    expect(restored?.idempotencyKey, _idempotencyKey);
    expect(restored?.purchaseIntentId, isNull);
    expect(restored?.planId, PdfConvPlanId.p30);
    expect(restored?.buyerEmail, 'buyer@example.com');
  });

  test(
    'binding an intent preserves the original idempotency identity',
    () async {
      final original = PdfConvPendingCheckout(
        idempotencyKey: _idempotencyKey,
        planId: PdfConvPlanId.p90,
        buyerEmail: 'buyer@example.com',
        createdAt: DateTime.utc(2026, 7, 17, 10),
      );

      final approvalUrl = Uri.parse(
        'https://www.paypal.com/checkoutnow?token=ORDER-1',
      );
      await store.write(
        original.bindPurchaseIntent(_intentId, approvalUrl: approvalUrl),
      );
      final restored = await store.read();

      expect(restored?.idempotencyKey, original.idempotencyKey);
      expect(restored?.planId, original.planId);
      expect(restored?.purchaseIntentId, _intentId);
      expect(restored?.approvalUrl, approvalUrl);
    },
  );

  test('clear removes the recovery marker', () async {
    await store.write(
      PdfConvPendingCheckout(
        idempotencyKey: _idempotencyKey,
        planId: PdfConvPlanId.p7,
        buyerEmail: 'buyer@example.com',
        createdAt: DateTime.utc(2026, 7, 17, 10),
      ),
    );

    await store.clear();
    expect(await store.read(), isNull);
  });

  test(
    'corrupt or unsupported marker fails without silently clearing it',
    () async {
      credentials.values[PdfConvPendingCheckoutStore.storageKey] =
          '{"schemaVersion":2}';

      expect(store.read(), throwsFormatException);
      expect(
        credentials.values,
        contains(PdfConvPendingCheckoutStore.storageKey),
      );
    },
  );

  test('marker requires canonical email and UUIDs', () {
    expect(
      () => PdfConvPendingCheckout(
        idempotencyKey: _idempotencyKey,
        planId: PdfConvPlanId.p30,
        buyerEmail: ' Buyer@Example.com ',
        createdAt: DateTime.utc(2026, 7, 17),
      ),
      throwsFormatException,
    );
    expect(
      () => PdfConvPendingCheckout(
        idempotencyKey: 'not-a-uuid',
        planId: PdfConvPlanId.p30,
        buyerEmail: 'buyer@example.com',
        createdAt: DateTime.utc(2026, 7, 17),
      ),
      throwsFormatException,
    );
  });

  test('approval URL requires a bound intent and safe HTTPS transport', () {
    expect(
      () => PdfConvPendingCheckout(
        idempotencyKey: _idempotencyKey,
        planId: PdfConvPlanId.p30,
        buyerEmail: 'buyer@example.com',
        createdAt: DateTime.utc(2026, 7, 17),
        approvalUrl: Uri.parse('https://www.paypal.com/checkout'),
      ),
      throwsFormatException,
    );
    expect(
      () => PdfConvPendingCheckout(
        idempotencyKey: _idempotencyKey,
        planId: PdfConvPlanId.p30,
        buyerEmail: 'buyer@example.com',
        createdAt: DateTime.utc(2026, 7, 17),
        purchaseIntentId: _intentId,
        approvalUrl: Uri.parse('http://www.paypal.com/checkout'),
      ),
      throwsFormatException,
    );
  });
}
