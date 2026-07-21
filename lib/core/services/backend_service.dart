import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart' show Options;
import '../config/brand_config.dart';
import '../constants/app_constants.dart';
import '../errors/result.dart';
import '../network/backend_client.dart';
import '../network/backend_dtos.dart';

/// Central service for all backend API calls.
/// Each method returns `Result<T>` for safe error handling.
class BackendService {
  final BackendClient _client;

  BackendService(this._client);

  Future<Result<void>> trackBootstrapEvent({
    required String installId,
    required String stage,
    required String status,
    String? errorCode,
    String? errorMessage,
    Map<String, dynamic>? metadata,
  }) => runCatching(
    () => _client.postNoAuth<void>(
      '/bootstrap/events',
      data: {
        'install_id': installId,
        'brand': BrandConfig.current.brand.name,
        'os': _platformOs,
        'os_version': Platform.operatingSystemVersion,
        'app_version': AppConstants.appVersion,
        'stage': stage,
        'status': status,
        if (errorCode != null && errorCode.isNotEmpty) 'error_code': errorCode,
        if (errorMessage != null && errorMessage.isNotEmpty)
          'error_message': errorMessage,
        if (metadata != null && metadata.isNotEmpty)
          'metadata': jsonEncode(metadata),
      },
      options: Options(extra: const {suppressBackendErrorReportFlag: true}),
      fromJson: (_) {},
    ),
  );

  // ==================== Bugs ====================

  Future<Result<BugResponse>> submitBug({
    required String title,
    required String description,
    String? steps,
    String? diagnosticLog,
  }) => runCatching(
    () => _client.post(
      '/bugs',
      data: {
        'title': title,
        'description': description,
        if (steps != null) 'steps': steps,
        'app_version': AppConstants.appVersion,
        'os': _platformOs,
        'os_version': Platform.operatingSystemVersion,
        if (diagnosticLog != null && diagnosticLog.isNotEmpty)
          'diagnostic_log': diagnosticLog,
      },
      fromJson: (json) => BugResponse.fromJson(json as Map<String, dynamic>),
    ),
  );

  Future<Result<List<BugResponse>>> listBugs() => runCatching(
    () => _client.get(
      '/bugs',
      fromJson:
          (json) =>
              (json as List)
                  .map((e) => BugResponse.fromJson(e as Map<String, dynamic>))
                  .toList(),
    ),
  );

  // ==================== Crashes ====================

  Future<Result<CrashResponse>> submitCrash({
    required String stackTrace,
    String? errorMessage,
    String severity = 'medium',
    String? metadata,
    String? diagnosticLog,
  }) => runCatching(
    () => _client.post(
      '/crashes',
      data: {
        'stack_trace': stackTrace,
        if (errorMessage != null) 'error_message': errorMessage,
        'app_version': AppConstants.appVersion,
        'os': _platformOs,
        'os_version': Platform.operatingSystemVersion,
        'severity': severity,
        if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
        if (diagnosticLog != null && diagnosticLog.isNotEmpty)
          'diagnostic_log': diagnosticLog,
      },
      // CRITICAL: marks this request as internal so the Sentry HTTP
      // interceptor does NOT capture failures here. Without the flag,
      // a failed crash submission → captured event → Sentry reporter
      // forwards to backend → submitCrash again → loop. This breaks
      // the cycle. Only crash forwarding is internal; submitBug
      // (user-initiated) intentionally remains instrumented.
      options: Options(extra: const {backendInternalRequestFlag: true}),
      fromJson: (json) => CrashResponse.fromJson(json as Map<String, dynamic>),
    ),
  );

  // ==================== Tickets ====================

  Future<Result<TicketResponse>> createTicket({
    required String subject,
    required String category,
    required String message,
    String? diagnosticLog,
  }) => runCatching(
    () => _client.post(
      '/tickets',
      data: {
        'subject': subject,
        'category': category,
        'message': message,
        if (diagnosticLog != null && diagnosticLog.isNotEmpty)
          'diagnostic_log': diagnosticLog,
      },
      fromJson: (json) => TicketResponse.fromJson(json as Map<String, dynamic>),
    ),
  );

  Future<Result<List<TicketListResponse>>> listTickets() => runCatching(
    () => _client.get(
      '/tickets',
      fromJson:
          (json) =>
              (json as List)
                  .map(
                    (e) =>
                        TicketListResponse.fromJson(e as Map<String, dynamic>),
                  )
                  .toList(),
    ),
  );

  Future<Result<TicketResponse>> getTicket(String id) => runCatching(
    () => _client.get(
      '/tickets/$id',
      fromJson: (json) => TicketResponse.fromJson(json as Map<String, dynamic>),
    ),
  );

  Future<Result<MessageResponse>> sendTicketMessage(
    String ticketId,
    String content,
  ) => runCatching(
    () => _client.post(
      '/tickets/$ticketId/messages',
      data: {'content': content},
      fromJson:
          (json) => MessageResponse.fromJson(json as Map<String, dynamic>),
    ),
  );

  // ==================== Feature Requests ====================

  Future<Result<FeatureRequestResponse>> submitFeatureRequest({
    required String title,
    required String description,
  }) => runCatching(
    () => _client.post(
      '/features',
      data: {'title': title, 'description': description},
      fromJson:
          (json) =>
              FeatureRequestResponse.fromJson(json as Map<String, dynamic>),
    ),
  );

  Future<Result<List<FeatureRequestResponse>>> listFeatureRequests() =>
      runCatching(
        () => _client.get(
          '/features',
          fromJson: (json) {
            final map = json as Map<String, dynamic>;
            final items = map['items'] as List? ?? [];
            return items
                .map(
                  (e) => FeatureRequestResponse.fromJson(
                    e as Map<String, dynamic>,
                  ),
                )
                .toList();
          },
        ),
      );

  Future<Result<VoteResponse>> voteFeature(String featureId) => runCatching(
    () => _client.post(
      '/features/$featureId/vote',
      data: {},
      fromJson: (json) => VoteResponse.fromJson(json as Map<String, dynamic>),
    ),
  );

  // ==================== Ratings ====================

  Future<Result<RatingResponse>> submitRating({
    required int rating,
    String? review,
  }) => runCatching(
    () => _client.post(
      '/ratings',
      data: {
        'rating': rating,
        if (review != null && review.isNotEmpty) 'review': review,
        'app_version': AppConstants.appVersion,
      },
      fromJson: (json) => RatingResponse.fromJson(json as Map<String, dynamic>),
    ),
  );

  // ==================== AI Assistant ====================

  Future<Result<SessionResponse>> createAiSession(String message) =>
      runCatching(
        () => _client.post(
          '/assistant/sessions',
          data: {'message': message},
          fromJson:
              (json) => SessionResponse.fromJson(json as Map<String, dynamic>),
        ),
      );

  Future<Result<List<SessionListResponse>>> listAiSessions() => runCatching(
    () => _client.get(
      '/assistant/sessions',
      fromJson:
          (json) =>
              (json as List)
                  .map(
                    (e) =>
                        SessionListResponse.fromJson(e as Map<String, dynamic>),
                  )
                  .toList(),
    ),
  );

  Future<Result<SessionResponse>> getAiSession(String id) => runCatching(
    () => _client.get(
      '/assistant/sessions/$id',
      fromJson:
          (json) => SessionResponse.fromJson(json as Map<String, dynamic>),
    ),
  );

  Future<Result<ChatResponse>> sendAiMessage(
    String sessionId,
    String message,
  ) => runCatching(
    () => _client.post(
      '/assistant/sessions/$sessionId/messages',
      data: {'message': message},
      fromJson: (json) => ChatResponse.fromJson(json as Map<String, dynamic>),
    ),
  );

  Future<Result<EscalationResponse>> escalateSession(
    String sessionId,
    String subject,
  ) => runCatching(
    () => _client.post(
      '/assistant/sessions/$sessionId/escalate',
      data: {'subject': subject},
      fromJson:
          (json) => EscalationResponse.fromJson(json as Map<String, dynamic>),
    ),
  );

  // ==================== Analytics ====================

  Future<Result<void>> trackEvents(List<Map<String, dynamic>> events) =>
      runCatching(
        () => _client.postVoid(
          '/analytics/events',
          data: {'events': events},
          options: Options(extra: {suppressBackendErrorReportFlag: true}),
        ),
      );

  /// Submit a structured download error for detailed analytics.
  Future<Result<void>> submitDownloadError({
    required String url,
    required String platform,
    required String errorCode,
    required String errorPhase,
    required String errorMessage,
    String? metadata,
  }) => runCatching(
    () => _client.postVoid(
      '/analytics/download-errors',
      data: {
        'url': url,
        'platform': platform,
        'error_code': errorCode,
        'error_phase': errorPhase,
        'error_message': errorMessage,
        if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
      },
      options: Options(extra: {suppressBackendErrorReportFlag: true}),
    ),
  );

  // ==================== Product Control ====================

  Future<Result<UpdateCheckResponse>> checkUpdate({
    required String platform,
    required String version,
    String channel = 'stable',
    String? brand,
  }) => runCatching(
    () => _client.get(
      '/updates/check',
      queryParameters: {
        'platform': platform,
        'version': version,
        'channel': channel,
        'brand': brand ?? BrandConfig.current.brand.name,
      },
      options: Options(extra: {suppressBackendErrorReportFlag: true}),
      fromJson:
          (json) => UpdateCheckResponse.fromJson(json as Map<String, dynamic>),
    ),
  );

  Future<Result<List<FeatureFlagResponse>>> getFlags() => runCatching(
    () => _client.get(
      '/config/flags',
      fromJson:
          (json) =>
              (json as List)
                  .map(
                    (e) =>
                        FeatureFlagResponse.fromJson(e as Map<String, dynamic>),
                  )
                  .toList(),
    ),
  );

  Future<Result<List<RemoteConfigResponse>>> getRemoteConfig() => runCatching(
    () => _client.get(
      '/config/remote',
      fromJson:
          (json) =>
              (json as List)
                  .map(
                    (e) => RemoteConfigResponse.fromJson(
                      e as Map<String, dynamic>,
                    ),
                  )
                  .toList(),
    ),
  );

  Future<Result<List<AnnouncementResponse>>> getAnnouncements() => runCatching(
    () => _client.get(
      '/announcements',
      fromJson:
          (json) =>
              (json as List)
                  .map(
                    (e) => AnnouncementResponse.fromJson(
                      e as Map<String, dynamic>,
                    ),
                  )
                  .toList(),
    ),
  );

  // ==================== Premium ====================

  /// Issue a magic-link restore email. Always returns `true` on a successful
  /// HTTP 200 regardless of whether the email matched a license — the server
  /// preserves enumeration resistance. The user must click the link in their
  /// inbox to view the license key on the website, then paste it back into
  /// the app's "Activate License Key" dialog.
  ///
  /// Replaces the legacy `restoreLicense` which returned the key directly
  /// over an authenticated API key + email — that path leaked the key to
  /// any holder of any valid API key.
  Future<Result<bool>> requestRestoreEmail({required String email}) =>
      runCatching(
        () => _client.post(
          '/premium/web-restore-email',
          data: {'email': email},
          fromJson: (json) {
            final m = json as Map<String, dynamic>;
            return m['sent'] == true;
          },
        ),
      );

  // ==================== Helpers ====================

  String get _platformOs {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}
