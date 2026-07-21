import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/network/backend_client.dart';
import '../../domain/entities/pdfconv_paypal_plan.dart';
import '../../domain/entities/pdfconv_purchase_intent.dart';

typedef PdfConvApprovalLauncher = Future<bool> Function(Uri approvalUrl);

/// API client for SnakeLoader-owned PDFConv PayPal purchase intents.
class PdfConvPayPalService {
  final BackendClient _client;
  final Uuid _uuid;
  final PdfConvApprovalLauncher _approvalLauncher;

  PdfConvPayPalService(
    this._client, {
    Uuid? uuid,
    PdfConvApprovalLauncher? approvalLauncher,
  }) : _uuid = uuid ?? const Uuid(),
       _approvalLauncher = approvalLauncher ?? _launchExternalApproval;

  String newIdempotencyKey() => _uuid.v4();

  static String canonicalizeBuyerEmail(String value) {
    return value.trim().toLowerCase();
  }

  Future<PdfConvPurchaseIntent> createIntent({
    required PdfConvPlanId planId,
    required String buyerEmail,
    required String idempotencyKey,
  }) {
    _requireCanonicalUuid(idempotencyKey, 'idempotencyKey');
    final canonicalEmail = canonicalizeBuyerEmail(buyerEmail);
    if (canonicalEmail.isEmpty) {
      throw const FormatException('buyerEmail must not be empty');
    }

    return _client.post<PdfConvPurchaseIntent>(
      '/premium/paypal/intents',
      data: {'planId': planId.wireValue, 'buyerEmail': canonicalEmail},
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      fromJson: _intentFromJson,
    );
  }

  Future<PdfConvPurchaseIntent> captureIntent(String purchaseIntentId) {
    _requireCanonicalUuid(purchaseIntentId, 'purchaseIntentId');
    return _client.post<PdfConvPurchaseIntent>(
      '/premium/paypal/intents/$purchaseIntentId/capture',
      data: const <String, dynamic>{},
      fromJson: _intentFromJson,
    );
  }

  Future<PdfConvPurchaseIntent> getIntentStatus(String purchaseIntentId) {
    _requireCanonicalUuid(purchaseIntentId, 'purchaseIntentId');
    return _client.get<PdfConvPurchaseIntent>(
      '/premium/paypal/intents/$purchaseIntentId',
      fromJson: _intentFromJson,
    );
  }

  Future<bool> openApprovalPage(Uri approvalUrl) async {
    _requireSafeApprovalUrl(approvalUrl);
    try {
      return await _approvalLauncher(approvalUrl);
    } catch (_) {
      return false;
    }
  }

  static PdfConvPurchaseIntent _intentFromJson(dynamic json) {
    if (json is! Map) {
      throw const FormatException('PDFConv response data must be an object');
    }
    return PdfConvPurchaseIntent.fromJson(Map<String, dynamic>.from(json));
  }
}

Future<bool> _launchExternalApproval(Uri approvalUrl) {
  return launchUrl(approvalUrl, mode: LaunchMode.externalApplication);
}

void _requireCanonicalUuid(String value, String field) {
  if (!Uuid.isValidUUID(fromString: value) || value != value.toLowerCase()) {
    throw FormatException('$field must be a canonical UUID');
  }
}

void _requireSafeApprovalUrl(Uri uri) {
  if (uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('approvalUrl must be a safe HTTPS URL');
  }
}
