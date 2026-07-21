// Backend API DTOs - plain Dart classes (no Freezed/build_runner)
// Maps to Svid backend response shapes.

// ==================== Identity ====================

class RegisterResponse {
  final String deviceId;
  final String apiKey;
  final bool isNew;

  RegisterResponse({required this.deviceId, required this.apiKey, required this.isNew});

  factory RegisterResponse.fromJson(Map<String, dynamic> json) => RegisterResponse(
        deviceId: json['device_id'] as String,
        apiKey: json['api_key'] as String,
        isNew: json['is_new'] as bool,
      );
}

class HeartbeatResponse {
  final String serverTime;

  HeartbeatResponse({required this.serverTime});

  factory HeartbeatResponse.fromJson(Map<String, dynamic> json) =>
      HeartbeatResponse(serverTime: json['server_time'] as String);
}

// ==================== Bugs ====================

class BugResponse {
  final String id;
  final String deviceId;
  final String title;
  final String description;
  final String steps;
  final String appVersion;
  final String os;
  final String osVersion;
  final String status;
  final String priority;
  final String adminNotes;
  final String? resolvedAt;
  final String createdAt;
  final String updatedAt;

  BugResponse({
    required this.id,
    required this.deviceId,
    required this.title,
    required this.description,
    required this.steps,
    required this.appVersion,
    required this.os,
    required this.osVersion,
    required this.status,
    required this.priority,
    required this.adminNotes,
    this.resolvedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BugResponse.fromJson(Map<String, dynamic> json) => BugResponse(
        id: json['id'] as String,
        deviceId: json['device_id'] as String,
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        steps: json['steps'] as String? ?? '',
        appVersion: json['app_version'] as String? ?? '',
        os: json['os'] as String? ?? '',
        osVersion: json['os_version'] as String? ?? '',
        status: json['status'] as String? ?? 'open',
        priority: json['priority'] as String? ?? 'medium',
        adminNotes: json['admin_notes'] as String? ?? '',
        resolvedAt: json['resolved_at'] as String?,
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
      );
}

class CrashResponse {
  final String id;
  final String deviceId;
  final String stackTrace;
  final String errorMessage;
  final String appVersion;
  final String os;
  final String osVersion;
  final String severity;
  final String createdAt;

  CrashResponse({
    required this.id,
    required this.deviceId,
    required this.stackTrace,
    required this.errorMessage,
    required this.appVersion,
    required this.os,
    required this.osVersion,
    required this.severity,
    required this.createdAt,
  });

  factory CrashResponse.fromJson(Map<String, dynamic> json) => CrashResponse(
        id: json['id'] as String,
        deviceId: json['device_id'] as String,
        stackTrace: json['stack_trace'] as String? ?? '',
        errorMessage: json['error_message'] as String? ?? '',
        appVersion: json['app_version'] as String? ?? '',
        os: json['os'] as String? ?? '',
        osVersion: json['os_version'] as String? ?? '',
        severity: json['severity'] as String? ?? 'medium',
        createdAt: json['created_at'] as String? ?? '',
      );
}

// ==================== Tickets ====================

class TicketResponse {
  final String id;
  final String deviceId;
  final String subject;
  final String category;
  final String status;
  final String priority;
  final String? aiSessionId;
  final String createdAt;
  final String updatedAt;
  final List<MessageResponse>? messages;

  TicketResponse({
    required this.id,
    required this.deviceId,
    required this.subject,
    required this.category,
    required this.status,
    required this.priority,
    this.aiSessionId,
    required this.createdAt,
    required this.updatedAt,
    this.messages,
  });

  factory TicketResponse.fromJson(Map<String, dynamic> json) => TicketResponse(
        id: json['id'] as String,
        deviceId: json['device_id'] as String,
        subject: json['subject'] as String? ?? '',
        category: json['category'] as String? ?? '',
        status: json['status'] as String? ?? 'open',
        priority: json['priority'] as String? ?? 'medium',
        aiSessionId: json['ai_session_id'] as String?,
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
        messages: (json['messages'] as List?)
            ?.map((e) => MessageResponse.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class TicketListResponse {
  final String id;
  final String subject;
  final String category;
  final String status;
  final String priority;
  final String createdAt;
  final String updatedAt;

  TicketListResponse({
    required this.id,
    required this.subject,
    required this.category,
    required this.status,
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TicketListResponse.fromJson(Map<String, dynamic> json) => TicketListResponse(
        id: json['id'] as String,
        subject: json['subject'] as String? ?? '',
        category: json['category'] as String? ?? '',
        status: json['status'] as String? ?? 'open',
        priority: json['priority'] as String? ?? 'medium',
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
      );
}

class MessageResponse {
  final String id;
  final String senderType;
  final String senderId;
  final String content;
  final String createdAt;

  MessageResponse({
    required this.id,
    required this.senderType,
    required this.senderId,
    required this.content,
    required this.createdAt,
  });

  factory MessageResponse.fromJson(Map<String, dynamic> json) => MessageResponse(
        id: json['id'] as String,
        senderType: json['sender_type'] as String? ?? '',
        senderId: json['sender_id'] as String? ?? '',
        content: json['content'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
      );
}

// ==================== Feature Requests ====================

class FeatureRequestResponse {
  final String id;
  final String deviceId;
  final String title;
  final String description;
  final String status;
  final int upvotes;
  final String adminNotes;
  final String createdAt;
  final String updatedAt;

  FeatureRequestResponse({
    required this.id,
    required this.deviceId,
    required this.title,
    required this.description,
    required this.status,
    required this.upvotes,
    required this.adminNotes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FeatureRequestResponse.fromJson(Map<String, dynamic> json) => FeatureRequestResponse(
        id: json['id'] as String,
        deviceId: json['device_id'] as String,
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        status: json['status'] as String? ?? 'open',
        upvotes: json['upvotes'] as int? ?? 0,
        adminNotes: json['admin_notes'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
      );
}

class VoteResponse {
  final String featureRequestId;
  final int upvotes;
  final bool voted;

  VoteResponse({required this.featureRequestId, required this.upvotes, required this.voted});

  factory VoteResponse.fromJson(Map<String, dynamic> json) => VoteResponse(
        featureRequestId: json['feature_request_id'] as String,
        upvotes: json['upvotes'] as int? ?? 0,
        voted: json['voted'] as bool? ?? false,
      );
}

// ==================== Ratings ====================

class RatingResponse {
  final String id;
  final String deviceId;
  final int rating;
  final String review;
  final String appVersion;
  final String createdAt;
  final String updatedAt;

  RatingResponse({
    required this.id,
    required this.deviceId,
    required this.rating,
    required this.review,
    required this.appVersion,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RatingResponse.fromJson(Map<String, dynamic> json) => RatingResponse(
        id: json['id'] as String,
        deviceId: json['device_id'] as String,
        rating: json['rating'] as int? ?? 0,
        review: json['review'] as String? ?? '',
        appVersion: json['app_version'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
      );
}

// ==================== AI Assistant ====================

class SessionResponse {
  final String id;
  final String deviceId;
  final String title;
  final String status;
  final String createdAt;
  final String updatedAt;
  final List<ChatMessageResponse>? messages;

  SessionResponse({
    required this.id,
    required this.deviceId,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.messages,
  });

  factory SessionResponse.fromJson(Map<String, dynamic> json) => SessionResponse(
        id: json['id'] as String,
        deviceId: json['device_id'] as String,
        title: json['title'] as String? ?? '',
        status: json['status'] as String? ?? 'active',
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
        messages: (json['messages'] as List?)
            ?.map((e) => ChatMessageResponse.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class SessionListResponse {
  final String id;
  final String title;
  final String status;
  final String createdAt;
  final String updatedAt;

  SessionListResponse({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SessionListResponse.fromJson(Map<String, dynamic> json) => SessionListResponse(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        status: json['status'] as String? ?? 'active',
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
      );
}

class ChatMessageResponse {
  final String id;
  final String sessionId;
  final String role;
  final String content;
  final int tokensUsed;
  final String createdAt;

  ChatMessageResponse({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.tokensUsed,
    required this.createdAt,
  });

  factory ChatMessageResponse.fromJson(Map<String, dynamic> json) => ChatMessageResponse(
        id: json['id'] as String,
        sessionId: json['session_id'] as String? ?? '',
        role: json['role'] as String? ?? '',
        content: json['content'] as String? ?? '',
        tokensUsed: json['tokens_used'] as int? ?? 0,
        createdAt: json['created_at'] as String? ?? '',
      );
}

class ChatResponse {
  final ChatMessageResponse userMessage;
  final ChatMessageResponse assistantMessage;

  ChatResponse({required this.userMessage, required this.assistantMessage});

  factory ChatResponse.fromJson(Map<String, dynamic> json) => ChatResponse(
        userMessage: ChatMessageResponse.fromJson(json['user_message'] as Map<String, dynamic>),
        assistantMessage: ChatMessageResponse.fromJson(json['assistant_message'] as Map<String, dynamic>),
      );
}

class EscalationResponse {
  final SessionResponse session;
  final String? ticketId;

  EscalationResponse({required this.session, this.ticketId});

  factory EscalationResponse.fromJson(Map<String, dynamic> json) => EscalationResponse(
        session: SessionResponse.fromJson(json['session'] as Map<String, dynamic>),
        ticketId: json['ticket_id'] as String?,
      );
}

// ==================== Product Control ====================

class FeatureFlagResponse {
  final String key;
  final bool enabled;
  final String? minAppVersion;
  final String? metadata;

  FeatureFlagResponse({
    required this.key,
    required this.enabled,
    this.minAppVersion,
    this.metadata,
  });

  factory FeatureFlagResponse.fromJson(Map<String, dynamic> json) => FeatureFlagResponse(
        key: json['key'] as String,
        enabled: json['enabled'] as bool? ?? false,
        minAppVersion: json['min_app_version'] as String?,
        metadata: json['metadata'] as String?,
      );
}

class RemoteConfigResponse {
  final String key;
  final String value;
  final String valueType;

  RemoteConfigResponse({required this.key, required this.value, required this.valueType});

  factory RemoteConfigResponse.fromJson(Map<String, dynamic> json) => RemoteConfigResponse(
        key: json['key'] as String,
        value: json['value'] as String? ?? '',
        valueType: json['value_type'] as String? ?? 'string',
      );
}

class UpdateCheckResponse {
  final bool updateAvailable;
  final String? latestVersion;
  final String currentVersion;
  final bool isMandatory;
  final String? releaseNotes;
  final String? downloadUrl;
  final int? fileSize;
  final String? checksum;
  final String? publishedAt;

  UpdateCheckResponse({
    required this.updateAvailable,
    this.latestVersion,
    required this.currentVersion,
    required this.isMandatory,
    this.releaseNotes,
    this.downloadUrl,
    this.fileSize,
    this.checksum,
    this.publishedAt,
  });

  factory UpdateCheckResponse.fromJson(Map<String, dynamic> json) => UpdateCheckResponse(
        updateAvailable: json['update_available'] as bool? ?? false,
        latestVersion: json['latest_version'] as String?,
        currentVersion: json['current_version'] as String? ?? '',
        isMandatory: json['is_mandatory'] as bool? ?? false,
        releaseNotes: json['release_notes'] as String?,
        downloadUrl: json['download_url'] as String?,
        fileSize: json['file_size'] as int?,
        checksum: json['checksum'] as String?,
        publishedAt: json['published_at'] as String?,
      );
}

class RestoreLicenseResponse {
  final String? licenseKey;
  final String? billingCycle;
  final String? expiresAt;
  final String? message;

  RestoreLicenseResponse({this.licenseKey, this.billingCycle, this.expiresAt, this.message});

  factory RestoreLicenseResponse.fromJson(Map<String, dynamic> json) => RestoreLicenseResponse(
        licenseKey: json['license_key'] as String?,
        billingCycle: json['billing_cycle'] as String?,
        expiresAt: json['expires_at'] as String?,
        message: json['message'] as String?,
      );
}

class AnnouncementResponse {
  final String id;
  final String title;
  final String content;
  final String type;
  final String? startsAt;
  final String? expiresAt;
  final String createdAt;

  AnnouncementResponse({
    required this.id,
    required this.title,
    required this.content,
    required this.type,
    this.startsAt,
    this.expiresAt,
    required this.createdAt,
  });

  factory AnnouncementResponse.fromJson(Map<String, dynamic> json) => AnnouncementResponse(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        content: json['content'] as String? ?? '',
        type: json['type'] as String? ?? 'info',
        startsAt: json['starts_at'] as String?,
        expiresAt: json['expires_at'] as String?,
        createdAt: json['created_at'] as String? ?? '',
      );
}
