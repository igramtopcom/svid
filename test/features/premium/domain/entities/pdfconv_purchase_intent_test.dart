import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/premium/domain/entities/pdfconv_paypal_plan.dart';
import 'package:svid/features/premium/domain/entities/pdfconv_purchase_intent.dart';

const _intentId = '0cc27c14-f861-44df-a656-00a519d6f22b';

Map<String, dynamic> _response({
  String billingStatus = 'created',
  String entitlementStatus = 'pending',
  String? approvalUrl = 'https://www.paypal.com/checkoutnow?token=ORDER-1',
  String? licenseKey,
  String? licenseExpiresAt,
  bool retryable = false,
}) => {
  'purchaseIntentId': _intentId,
  'billingStatus': billingStatus,
  'entitlementStatus': entitlementStatus,
  'planId': 'p30',
  'approvalUrl': approvalUrl,
  if (licenseKey != null) 'licenseKey': licenseKey,
  if (licenseExpiresAt != null) 'licenseExpiresAt': licenseExpiresAt,
  'retryable': retryable,
};

void main() {
  test('parses pending intent and safe approval URL', () {
    final intent = PdfConvPurchaseIntent.fromJson(_response());

    expect(intent.purchaseIntentId, _intentId);
    expect(intent.billingStatus, PdfConvBillingStatus.created);
    expect(intent.entitlementStatus, PdfConvEntitlementStatus.pending);
    expect(intent.planId, PdfConvPlanId.p30);
    expect(intent.approvalUrl?.scheme, 'https');
    expect(intent.isActivatable, isFalse);
  });

  test('granted intent requires and exposes license material', () {
    final intent = PdfConvPurchaseIntent.fromJson(
      _response(
        billingStatus: 'fulfilled',
        entitlementStatus: 'granted',
        approvalUrl: null,
        licenseKey: 'VIDCOMBO-1234-1234-1234-1234-1234-1234-1234-1234',
        licenseExpiresAt: '2026-08-16T12:00:00Z',
      ),
    );

    expect(intent.isActivatable, isTrue);
    expect(intent.licenseExpiresAt, DateTime.utc(2026, 8, 16, 12));
  });

  test('fulfilled billing remains pending until entitlement is granted', () {
    final intent = PdfConvPurchaseIntent.fromJson(
      _response(billingStatus: 'fulfilled'),
    );

    expect(intent.isAwaitingSettlement, isTrue);
    expect(intent.isActivatable, isFalse);
  });

  test('approved and capture_pending require capture', () {
    for (final status in ['approved', 'capture_pending']) {
      final intent = PdfConvPurchaseIntent.fromJson(
        _response(billingStatus: status),
      );
      expect(intent.requiresCapture, isTrue);
    }
  });

  test('unknown backend states fail closed', () {
    expect(
      () => PdfConvPurchaseIntent.fromJson(_response(billingStatus: 'paid')),
      throwsFormatException,
    );
    expect(
      () => PdfConvPurchaseIntent.fromJson(
        _response(entitlementStatus: 'active'),
      ),
      throwsFormatException,
    );
  });

  test('granted without complete license material fails closed', () {
    expect(
      () => PdfConvPurchaseIntent.fromJson(
        _response(entitlementStatus: 'granted'),
      ),
      throwsFormatException,
    );
    expect(
      () => PdfConvPurchaseIntent.fromJson(
        _response(entitlementStatus: 'granted', licenseKey: 'VIDCOMBO-KEY'),
      ),
      throwsFormatException,
    );
  });

  test('pending intent carrying license material fails closed', () {
    expect(
      () =>
          PdfConvPurchaseIntent.fromJson(_response(licenseKey: 'VIDCOMBO-KEY')),
      throwsFormatException,
    );
  });

  test('unsafe or malformed approval URLs are rejected', () {
    for (final url in [
      'http://www.paypal.com/checkout',
      'javascript:alert(1)',
      'https://user@example.com/checkout',
    ]) {
      expect(
        () => PdfConvPurchaseIntent.fromJson(_response(approvalUrl: url)),
        throwsFormatException,
      );
    }
  });

  test('purchase intent ID must be a canonical UUID', () {
    final json = _response()..['purchaseIntentId'] = _intentId.toUpperCase();
    expect(() => PdfConvPurchaseIntent.fromJson(json), throwsFormatException);
  });
}
