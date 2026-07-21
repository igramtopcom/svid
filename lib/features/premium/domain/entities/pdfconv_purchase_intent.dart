import 'package:uuid/uuid.dart';

import 'pdfconv_paypal_plan.dart';

/// Billing-cell state. This is intentionally separate from entitlement state.
enum PdfConvBillingStatus {
  creating('creating'),
  created('created'),
  approved('approved'),
  capturePending('capture_pending'),
  captured('captured'),
  fulfillmentPending('fulfillment_pending'),
  fulfilled('fulfilled'),
  cancelled('cancelled'),
  expired('expired'),
  denied('denied'),
  refunded('refunded'),
  reversed('reversed'),
  manualReview('manual_review');

  const PdfConvBillingStatus(this.wireValue);

  final String wireValue;

  bool get requiresCapture =>
      this == PdfConvBillingStatus.approved ||
      this == PdfConvBillingStatus.capturePending;

  bool get isAwaitingSettlement =>
      this == PdfConvBillingStatus.captured ||
      this == PdfConvBillingStatus.fulfillmentPending ||
      this == PdfConvBillingStatus.fulfilled;

  bool get isDefinitiveFailure =>
      this == PdfConvBillingStatus.cancelled ||
      this == PdfConvBillingStatus.expired ||
      this == PdfConvBillingStatus.denied;

  static PdfConvBillingStatus fromWireValue(String value) {
    return PdfConvBillingStatus.values.firstWhere(
      (status) => status.wireValue == value,
      orElse:
          () => throw FormatException('Unknown PDFConv billing status: $value'),
    );
  }
}

/// SnakeLoader-owned entitlement state for a purchase intent.
enum PdfConvEntitlementStatus {
  pending('pending'),
  granted('granted'),
  revoked('revoked');

  const PdfConvEntitlementStatus(this.wireValue);

  final String wireValue;

  static PdfConvEntitlementStatus fromWireValue(String value) {
    return PdfConvEntitlementStatus.values.firstWhere(
      (status) => status.wireValue == value,
      orElse:
          () =>
              throw FormatException(
                'Unknown PDFConv entitlement status: $value',
              ),
    );
  }
}

/// Converged checkout state returned by create, capture, and status endpoints.
class PdfConvPurchaseIntent {
  final String purchaseIntentId;
  final PdfConvBillingStatus billingStatus;
  final PdfConvEntitlementStatus entitlementStatus;
  final PdfConvPlanId planId;
  final Uri? approvalUrl;
  final String? licenseKey;
  final DateTime? licenseExpiresAt;
  final bool retryable;

  const PdfConvPurchaseIntent({
    required this.purchaseIntentId,
    required this.billingStatus,
    required this.entitlementStatus,
    required this.planId,
    this.approvalUrl,
    this.licenseKey,
    this.licenseExpiresAt,
    required this.retryable,
  });

  bool get isActivatable =>
      entitlementStatus == PdfConvEntitlementStatus.granted &&
      licenseKey != null &&
      licenseKey!.isNotEmpty;

  bool get requiresCapture =>
      entitlementStatus == PdfConvEntitlementStatus.pending &&
      billingStatus.requiresCapture;

  bool get isAwaitingSettlement =>
      entitlementStatus == PdfConvEntitlementStatus.pending &&
      billingStatus.isAwaitingSettlement;

  factory PdfConvPurchaseIntent.fromJson(Map<String, dynamic> json) {
    final purchaseIntentId = _requiredString(json, 'purchaseIntentId');
    _requireCanonicalUuid(purchaseIntentId, 'purchaseIntentId');

    final entitlementStatus = PdfConvEntitlementStatus.fromWireValue(
      _requiredString(json, 'entitlementStatus'),
    );
    final licenseKey = _optionalString(json, 'licenseKey');
    final licenseExpiresAt = _optionalDateTime(json, 'licenseExpiresAt');

    if (entitlementStatus == PdfConvEntitlementStatus.granted) {
      if (licenseKey == null ||
          licenseKey.isEmpty ||
          licenseExpiresAt == null) {
        throw const FormatException(
          'Granted PDFConv intent is missing license material',
        );
      }
    } else if (licenseKey != null || licenseExpiresAt != null) {
      throw const FormatException(
        'Pending or revoked PDFConv intent must not contain license material',
      );
    }

    return PdfConvPurchaseIntent(
      purchaseIntentId: purchaseIntentId,
      billingStatus: PdfConvBillingStatus.fromWireValue(
        _requiredString(json, 'billingStatus'),
      ),
      entitlementStatus: entitlementStatus,
      planId: PdfConvPlanId.fromWireValue(_requiredString(json, 'planId')),
      approvalUrl: _optionalHttpsUri(json, 'approvalUrl'),
      licenseKey: licenseKey,
      licenseExpiresAt: licenseExpiresAt,
      retryable: _requiredBool(json, 'retryable'),
    );
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('PDFConv response field "$key" must be a string');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('PDFConv response field "$key" must be a string');
  }
  return value;
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw FormatException('PDFConv response field "$key" must be a bool');
  }
  return value;
}

DateTime? _optionalDateTime(Map<String, dynamic> json, String key) {
  final raw = _optionalString(json, key);
  if (raw == null) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw FormatException('PDFConv response field "$key" is not a date-time');
  }
  return parsed.toUtc();
}

Uri? _optionalHttpsUri(Map<String, dynamic> json, String key) {
  final raw = _optionalString(json, key);
  if (raw == null) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw FormatException('PDFConv response field "$key" is not a safe URL');
  }
  return uri;
}

void _requireCanonicalUuid(String value, String field) {
  if (!Uuid.isValidUUID(fromString: value) || value != value.toLowerCase()) {
    throw FormatException('PDFConv field "$field" must be a canonical UUID');
  }
}
