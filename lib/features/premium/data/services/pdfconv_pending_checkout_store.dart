import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../../core/services/secure_credential_store.dart';
import '../../domain/entities/pdfconv_paypal_plan.dart';

/// Crash-recovery marker persisted before the first create-intent request.
class PdfConvPendingCheckout {
  static const schemaVersion = 1;

  final String idempotencyKey;
  final PdfConvPlanId planId;
  final String buyerEmail;
  final DateTime createdAt;
  final String? purchaseIntentId;
  final Uri? approvalUrl;

  PdfConvPendingCheckout({
    required this.idempotencyKey,
    required this.planId,
    required this.buyerEmail,
    required DateTime createdAt,
    this.purchaseIntentId,
    this.approvalUrl,
  }) : createdAt = createdAt.toUtc() {
    _requireCanonicalUuid(idempotencyKey, 'idempotencyKey');
    if (purchaseIntentId != null) {
      _requireCanonicalUuid(purchaseIntentId!, 'purchaseIntentId');
    }
    if (approvalUrl != null) {
      if (purchaseIntentId == null) {
        throw const FormatException(
          'approvalUrl cannot be stored before a purchase intent is bound',
        );
      }
      _requireSafeApprovalUrl(approvalUrl!);
    }
    if (buyerEmail.isEmpty || buyerEmail != buyerEmail.trim().toLowerCase()) {
      throw const FormatException('buyerEmail must be canonical');
    }
  }

  PdfConvPendingCheckout bindPurchaseIntent(
    String intentId, {
    Uri? approvalUrl,
  }) {
    return PdfConvPendingCheckout(
      idempotencyKey: idempotencyKey,
      planId: planId,
      buyerEmail: buyerEmail,
      createdAt: createdAt,
      purchaseIntentId: intentId,
      approvalUrl: approvalUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'idempotencyKey': idempotencyKey,
    'planId': planId.wireValue,
    'buyerEmail': buyerEmail,
    'createdAt': createdAt.toIso8601String(),
    if (purchaseIntentId != null) 'purchaseIntentId': purchaseIntentId,
    if (approvalUrl != null) 'approvalUrl': approvalUrl.toString(),
  };

  factory PdfConvPendingCheckout.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException(
        'Unsupported PDFConv checkout marker version',
      );
    }
    final createdAtRaw = _requiredString(json, 'createdAt');
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) {
      throw const FormatException('Invalid PDFConv marker createdAt');
    }

    return PdfConvPendingCheckout(
      idempotencyKey: _requiredString(json, 'idempotencyKey'),
      planId: PdfConvPlanId.fromWireValue(_requiredString(json, 'planId')),
      buyerEmail: _requiredString(json, 'buyerEmail'),
      createdAt: createdAt,
      purchaseIntentId: _optionalString(json, 'purchaseIntentId'),
      approvalUrl: _optionalApprovalUrl(json, 'approvalUrl'),
    );
  }
}

class PdfConvPendingCheckoutStore {
  static const storageKey = 'pending_pdfconv_paypal_checkout_v1';

  final SecureCredentialStore _credentials;

  const PdfConvPendingCheckoutStore(this._credentials);

  Future<PdfConvPendingCheckout?> read() async {
    final encoded = await _credentials.read(storageKey);
    if (encoded == null || encoded.isEmpty) return null;

    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FormatException('PDFConv checkout marker must be an object');
    }
    return PdfConvPendingCheckout.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<void> write(PdfConvPendingCheckout checkout) {
    return _credentials.write(storageKey, jsonEncode(checkout.toJson()));
  }

  Future<void> clear() => _credentials.delete(storageKey);
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('PDFConv marker field "$key" must be a string');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw FormatException('PDFConv marker field "$key" must be a string');
  }
  return value;
}

void _requireCanonicalUuid(String value, String field) {
  if (!Uuid.isValidUUID(fromString: value) || value != value.toLowerCase()) {
    throw FormatException('PDFConv marker field "$field" is not a UUID');
  }
}

Uri? _optionalApprovalUrl(Map<String, dynamic> json, String key) {
  final raw = _optionalString(json, key);
  if (raw == null) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null) {
    throw const FormatException('PDFConv marker approvalUrl is invalid');
  }
  _requireSafeApprovalUrl(uri);
  return uri;
}

void _requireSafeApprovalUrl(Uri uri) {
  if (uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('PDFConv marker approvalUrl is not safe');
  }
}
