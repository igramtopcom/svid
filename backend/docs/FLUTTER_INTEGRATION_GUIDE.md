# Flutter App Integration Guide for SnakeLoader Backend

> **Purpose**: This document provides complete context for Claude AI to integrate the SnakeLoader Flutter app with the backend API. Include this file when working on frontend integration.

---

## Backend Overview

- **Base URL**: `http://localhost:8080` (dev) or production URL
- **Auth**: API Key in `X-API-Key` header
- **Format**: JSON request/response
- **Response envelope**: `{ "success": bool, "data": T, "error": { "code", "message" } }`

---

## Quick Start Integration

### 1. Add Dependencies (pubspec.yaml)
```yaml
dependencies:
  dio: ^5.4.0
  flutter_secure_storage: ^9.0.0
  freezed_annotation: ^2.4.0
  json_annotation: ^4.8.0

dev_dependencies:
  freezed: ^2.4.0
  json_serializable: ^6.7.0
  build_runner: ^2.4.0
```

### 2. API Client Setup
```dart
// lib/core/api/api_client.dart
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiClient {
  static const String baseUrl = 'http://localhost:8080';
  static const String _apiKeyStorageKey = 'snakeloader_api_key';

  final Dio _dio;
  final FlutterSecureStorage _storage;

  ApiClient() :
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    )),
    _storage = const FlutterSecureStorage() {
    _dio.interceptors.add(_AuthInterceptor(this));
  }

  Future<String?> getApiKey() => _storage.read(key: _apiKeyStorageKey);
  Future<void> saveApiKey(String key) => _storage.write(key: _apiKeyStorageKey, value: key);
  Future<void> clearApiKey() => _storage.delete(key: _apiKeyStorageKey);

  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? params}) =>
    _dio.get(path, queryParameters: params);

  Future<Response<T>> post<T>(String path, {dynamic data}) =>
    _dio.post(path, data: data);
}

class _AuthInterceptor extends Interceptor {
  final ApiClient _client;
  _AuthInterceptor(this._client);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final apiKey = await _client.getApiKey();
    if (apiKey != null) {
      options.headers['X-API-Key'] = apiKey;
    }
    handler.next(options);
  }
}
```

### 3. Device Registration (MUST do first)
```dart
// Call this on first app launch
Future<void> registerDevice() async {
  final deviceInfo = await _getDeviceInfo(); // Use device_info_plus package

  final response = await apiClient.post('/api/v1/devices/register', data: {
    'hardware_id': deviceInfo.uniqueId,      // REQUIRED: Unique device identifier
    'os': deviceInfo.os,                      // REQUIRED: 'windows', 'macos', 'linux'
    'os_version': deviceInfo.osVersion,       // REQUIRED: e.g., '11', '14.2'
    'app_version': '1.0.0',                   // REQUIRED: Your app version
    'device_name': deviceInfo.deviceName,     // OPTIONAL: e.g., 'MacBook Pro'
  });

  if (response.data['success']) {
    final apiKey = response.data['data']['api_key']; // Format: snk_xxxxx
    await apiClient.saveApiKey(apiKey);
  }
}
```

---

## Complete API Reference

### Authentication
All `/api/v1/*` endpoints (except register) require:
```
Header: X-API-Key: snk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

---

### 1. Identity Module

#### Register Device
```
POST /api/v1/devices/register
Content-Type: application/json

Request:
{
  "hardware_id": "unique-device-id",     // REQUIRED - stable unique ID
  "os": "windows",                        // REQUIRED - windows|macos|linux
  "os_version": "11",                     // REQUIRED
  "app_version": "1.0.0",                 // REQUIRED
  "device_name": "My PC"                  // OPTIONAL
}

Response:
{
  "success": true,
  "data": {
    "device_id": "uuid",
    "api_key": "snk_xxxxxxxxxxxxxxxx",   // SAVE THIS SECURELY
    "tier": "free"
  }
}
```

#### Heartbeat (call periodically, e.g., every 5 minutes)
```
POST /api/v1/devices/heartbeat
X-API-Key: snk_xxx

Request:
{
  "app_version": "1.0.0"    // Current app version
}

Response:
{
  "success": true,
  "data": {
    "server_time": "2024-01-15T10:30:00Z"
  }
}
```

---

### 2. Bug Reporting Module

#### Submit Bug Report
```
POST /api/v1/bugs
X-API-Key: snk_xxx

Request:
{
  "title": "Download fails on YouTube",           // REQUIRED
  "description": "Detailed description...",       // REQUIRED
  "severity": "high",                             // REQUIRED: critical|high|medium|low
  "steps_to_reproduce": "1. Open app\n2. ...",   // OPTIONAL
  "expected_behavior": "Should download",         // OPTIONAL
  "actual_behavior": "Shows error"                // OPTIONAL
}

Response:
{
  "success": true,
  "data": {
    "id": "uuid",
    "status": "open",
    "created_at": "2024-01-15T10:30:00Z"
  }
}
```

#### Submit Crash Report
```
POST /api/v1/crashes
X-API-Key: snk_xxx

Request:
{
  "error_type": "NullPointerException",    // REQUIRED
  "error_message": "Object reference...",   // REQUIRED
  "stack_trace": "at main.dart:42\n..."    // REQUIRED
}

Response:
{
  "success": true,
  "data": { "id": "uuid" }
}
```

#### Get My Bug Reports
```
GET /api/v1/bugs?page=1&per_page=20
X-API-Key: snk_xxx

Response:
{
  "success": true,
  "data": {
    "items": [...],
    "total": 5,
    "page": 1,
    "per_page": 20,
    "total_pages": 1
  }
}
```

---

### 3. Product Control Module

#### Get Feature Flags
```
GET /api/v1/config/flags
X-API-Key: snk_xxx

Response:
{
  "success": true,
  "data": {
    "flags": [
      { "key": "dark_mode", "enabled": true },
      { "key": "batch_download", "enabled": false },
      { "key": "youtube_support", "enabled": true }
    ]
  }
}

Usage in Flutter:
bool isDarkModeEnabled = flags.firstWhere((f) => f.key == 'dark_mode')?.enabled ?? false;
```

#### Get Remote Config
```
GET /api/v1/config/remote
X-API-Key: snk_xxx

Response:
{
  "success": true,
  "data": {
    "configs": [
      { "key": "max_concurrent_downloads", "value": "3", "value_type": "number" },
      { "key": "supported_sites", "value": "[\"youtube\",\"vimeo\"]", "value_type": "json" },
      { "key": "ad_enabled", "value": "true", "value_type": "boolean" }
    ]
  }
}
```

#### Check for Updates
```
GET /api/v1/updates/check?platform=windows&current_version=1.0.0&channel=stable
X-API-Key: snk_xxx

Response (update available):
{
  "success": true,
  "data": {
    "update_available": true,
    "latest_version": "1.1.0",
    "download_url": "https://...",
    "release_notes": "Bug fixes and improvements",
    "is_mandatory": false
  }
}

Response (no update):
{
  "success": true,
  "data": {
    "update_available": false,
    "current_version": "1.0.0"
  }
}
```

#### Get Announcements
```
GET /api/v1/announcements
X-API-Key: snk_xxx

Response:
{
  "success": true,
  "data": {
    "announcements": [
      {
        "id": "uuid",
        "title": "Scheduled Maintenance",
        "message": "Server will be down...",
        "type": "maintenance",              // info|warning|critical|maintenance
        "action_url": "https://...",
        "starts_at": "2024-01-20T00:00:00Z",
        "expires_at": "2024-01-20T06:00:00Z"
      }
    ]
  }
}
```

---

### 4. Feedback Module

#### Create Support Ticket
```
POST /api/v1/tickets
X-API-Key: snk_xxx

Request:
{
  "subject": "Cannot login",              // REQUIRED
  "category": "bug",                       // REQUIRED: general|bug|feature|billing|other
  "message": "When I try to login..."     // REQUIRED: Initial message
}

Response:
{
  "success": true,
  "data": {
    "id": "uuid",
    "status": "open"
  }
}
```

#### Get My Tickets
```
GET /api/v1/tickets?page=1&per_page=20
X-API-Key: snk_xxx
```

#### Get Ticket Detail (with messages)
```
GET /api/v1/tickets/:id
X-API-Key: snk_xxx

Response:
{
  "success": true,
  "data": {
    "id": "uuid",
    "subject": "Cannot login",
    "status": "in_progress",
    "messages": [
      { "sender_type": "device", "message": "...", "created_at": "..." },
      { "sender_type": "admin", "message": "...", "created_at": "..." }
    ]
  }
}
```

#### Reply to Ticket
```
POST /api/v1/tickets/:id/messages
X-API-Key: snk_xxx

Request:
{ "message": "Thanks for the help..." }
```

#### Create Feature Request
```
POST /api/v1/features
X-API-Key: snk_xxx

Request:
{
  "title": "Add TikTok support",          // REQUIRED
  "description": "It would be great..."   // REQUIRED
}
```

#### List Feature Requests
```
GET /api/v1/features?page=1&per_page=20&sort=upvotes
X-API-Key: snk_xxx
```

#### Vote for Feature Request
```
POST /api/v1/features/:id/vote
X-API-Key: snk_xxx

Response:
{
  "success": true,
  "data": { "upvotes": 42 }
}

Note: One vote per device. Duplicate votes return error.
```

#### Submit App Rating
```
POST /api/v1/ratings
X-API-Key: snk_xxx

Request:
{
  "rating": 5,                            // REQUIRED: 1-5
  "review": "Great app!"                  // OPTIONAL
}

Note: Upsert behavior - updates if already rated.
```

---

### 5. AI Assistant Module

#### Create Chat Session
```
POST /api/v1/assistant/sessions
X-API-Key: snk_xxx

Request:
{
  "message": "How do I download from YouTube?"   // REQUIRED: First message
}

Response:
{
  "success": true,
  "data": {
    "session_id": "uuid",
    "title": "YouTube Download Help",
    "messages": [
      { "role": "user", "content": "How do I..." },
      { "role": "assistant", "content": "To download from YouTube..." }
    ]
  }
}
```

#### List My Sessions
```
GET /api/v1/assistant/sessions?page=1&per_page=20
X-API-Key: snk_xxx
```

#### Get Session Detail
```
GET /api/v1/assistant/sessions/:id
X-API-Key: snk_xxx
```

#### Send Message (continue conversation)
```
POST /api/v1/assistant/sessions/:id/messages
X-API-Key: snk_xxx

Request:
{ "message": "What about Vimeo?" }

Response:
{
  "success": true,
  "data": {
    "user_message": { "role": "user", "content": "..." },
    "assistant_message": { "role": "assistant", "content": "..." }
  }
}
```

#### Escalate to Human Support
```
POST /api/v1/assistant/sessions/:id/escalate
X-API-Key: snk_xxx

Request:
{ "reason": "AI cannot help with my issue" }   // OPTIONAL

Note: After escalation, session is locked. No more messages allowed.
```

---

### 6. Analytics Module

#### Track Events (Batch)
```
POST /api/v1/analytics/events
X-API-Key: snk_xxx

Request:
{
  "events": [
    { "event_type": "app_open", "event_data": "{}" },
    { "event_type": "download_start", "event_data": "{\"url\":\"...\",\"quality\":\"1080p\"}" },
    { "event_type": "download_complete", "event_data": "{\"duration_ms\":5000}" },
    { "event_type": "feature_used", "event_data": "{\"feature\":\"batch_download\"}" }
  ]
}

Response:
{
  "success": true,
  "data": { "tracked": 4 }
}

Note: Max 50 events per request. event_data is optional JSON string.
```

#### Suggested Event Types
```dart
class AnalyticsEvents {
  static const appOpen = 'app_open';
  static const appClose = 'app_close';
  static const downloadStart = 'download_start';
  static const downloadComplete = 'download_complete';
  static const downloadError = 'download_error';
  static const downloadCancel = 'download_cancel';
  static const featureUsed = 'feature_used';
  static const settingsChanged = 'settings_changed';
  static const errorOccurred = 'error_occurred';
  static const searchPerformed = 'search_performed';
}
```

---

## Error Handling

### Error Response Format
```json
{
  "success": false,
  "error": {
    "code": "INVALID_API_KEY",
    "message": "API key is invalid or expired",
    "details": "Optional additional info"
  }
}
```

### Common Error Codes
| Code | HTTP Status | Meaning |
|------|-------------|---------|
| `INVALID_API_KEY` | 401 | API key missing, invalid, or revoked |
| `DEVICE_NOT_FOUND` | 404 | Device not registered |
| `VALIDATION_ERROR` | 400 | Invalid request body |
| `RATE_LIMITED` | 429 | Too many requests |
| `INTERNAL_ERROR` | 500 | Server error |
| `NOT_FOUND` | 404 | Resource not found |
| `ALREADY_EXISTS` | 409 | Duplicate (e.g., already voted) |
| `SESSION_ESCALATED` | 400 | Chat session already escalated |

### Dart Error Handling
```dart
try {
  final response = await apiClient.post('/api/v1/bugs', data: bugData);
  if (response.data['success']) {
    // Handle success
  } else {
    final error = response.data['error'];
    // Handle API error: error['code'], error['message']
  }
} on DioException catch (e) {
  if (e.response?.statusCode == 401) {
    // Re-register device, API key may be revoked
  } else if (e.response?.statusCode == 429) {
    // Rate limited, retry after delay
  }
}
```

---

## Implementation Checklist

### Phase 1: Core Setup
- [ ] Add dependencies to pubspec.yaml
- [ ] Create ApiClient with Dio
- [ ] Implement secure API key storage
- [ ] Device registration on first launch
- [ ] Heartbeat service (background, every 5 min)

### Phase 2: Essential Features
- [ ] Feature flags integration
- [ ] Remote config integration
- [ ] Update checker (on app start)
- [ ] Announcements display

### Phase 3: User Feedback
- [ ] Crash reporting (global error handler)
- [ ] Bug report form
- [ ] App rating prompt
- [ ] Support ticket system

### Phase 4: Advanced
- [ ] Analytics event tracking
- [ ] AI assistant chat UI
- [ ] Feature request voting
- [ ] Offline queue for failed requests

---

## Flutter Code Examples

### Global Crash Handler
```dart
void main() {
  FlutterError.onError = (details) {
    _reportCrash(details.exception.toString(), details.stack.toString());
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    _reportCrash(error.toString(), stack.toString());
    return true;
  };

  runApp(MyApp());
}

Future<void> _reportCrash(String error, String stackTrace) async {
  try {
    await apiClient.post('/api/v1/crashes', data: {
      'error_type': error.split(':').first,
      'error_message': error,
      'stack_trace': stackTrace,
    });
  } catch (_) {} // Don't crash while reporting crash
}
```

### Feature Flag Provider (Riverpod)
```dart
final featureFlagsProvider = FutureProvider<Map<String, bool>>((ref) async {
  final response = await apiClient.get('/api/v1/config/flags');
  if (response.data['success']) {
    final flags = response.data['data']['flags'] as List;
    return { for (var f in flags) f['key']: f['enabled'] };
  }
  return {};
});

// Usage
final isDarkMode = ref.watch(featureFlagsProvider).value?['dark_mode'] ?? false;
```

### Analytics Service
```dart
class AnalyticsService {
  final List<Map<String, String>> _queue = [];
  Timer? _flushTimer;

  void track(String eventType, [Map<String, dynamic>? data]) {
    _queue.add({
      'event_type': eventType,
      'event_data': data != null ? jsonEncode(data) : '',
    });
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(seconds: 5), _flush);
  }

  Future<void> _flush() async {
    if (_queue.isEmpty) return;
    final events = List.from(_queue);
    _queue.clear();

    try {
      await apiClient.post('/api/v1/analytics/events', data: {'events': events});
    } catch (_) {
      _queue.insertAll(0, events); // Re-queue on failure
    }
  }
}
```

---

## Testing the Integration

### 1. Test Registration
```bash
curl -X POST http://localhost:8080/api/v1/devices/register \
  -H "Content-Type: application/json" \
  -d '{"hardware_id":"flutter-test-001","os":"macos","os_version":"14","app_version":"1.0.0"}'
```

### 2. Test with API Key
```bash
API_KEY="snk_xxx"  # From registration response

curl http://localhost:8080/api/v1/config/flags \
  -H "X-API-Key: $API_KEY"
```

### 3. Verify in Admin Dashboard
- Open http://localhost:8080/dashboard-ui/
- Login: admin@snakeloader.com / SnakeAdmin2025
- Check Devices page for your test device

---

## Backend Repository
https://github.com/DinhVanMy/snakeloader-backend

## Questions?
Include this document when asking Claude AI for help with Flutter integration.
