import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/network/backend_dtos.dart';

void main() {
  group('Backend DTOs fromJson', () {
    group('BugResponse', () {
      test('parses complete JSON', () {
        final json = {
          'id': 'bug-1',
          'device_id': 'dev-1',
          'title': 'Crash on startup',
          'description': 'App crashes',
          'steps': '1. Open app\n2. Crash',
          'app_version': '1.0.0',
          'os': 'macos',
          'os_version': '14.0',
          'status': 'open',
          'priority': 'high',
          'admin_notes': '',
          'resolved_at': null,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        };

        final bug = BugResponse.fromJson(json);
        expect(bug.id, 'bug-1');
        expect(bug.title, 'Crash on startup');
        expect(bug.status, 'open');
        expect(bug.priority, 'high');
        expect(bug.resolvedAt, isNull);
      });

      test('handles missing optional fields with defaults', () {
        final json = {
          'id': 'bug-2',
          'device_id': 'dev-1',
        };

        final bug = BugResponse.fromJson(json);
        expect(bug.title, '');
        expect(bug.description, '');
        expect(bug.status, 'open');
        expect(bug.priority, 'medium');
      });
    });

    group('TicketResponse', () {
      test('parses with messages', () {
        final json = {
          'id': 'ticket-1',
          'device_id': 'dev-1',
          'subject': 'Help',
          'category': 'support',
          'status': 'open',
          'priority': 'medium',
          'created_at': '2026-01-01',
          'updated_at': '2026-01-01',
          'messages': [
            {
              'id': 'msg-1',
              'sender_type': 'user',
              'sender_id': 'dev-1',
              'content': 'I need help',
              'created_at': '2026-01-01',
            },
          ],
        };

        final ticket = TicketResponse.fromJson(json);
        expect(ticket.subject, 'Help');
        expect(ticket.messages, isNotNull);
        expect(ticket.messages!.length, 1);
        expect(ticket.messages!.first.content, 'I need help');
      });
    });

    group('FeatureFlagResponse', () {
      test('parses feature flag', () {
        final json = {
          'key': 'dark_mode',
          'enabled': true,
          'min_app_version': '1.0.0',
          'metadata': '{"variant": "beta"}',
        };

        final flag = FeatureFlagResponse.fromJson(json);
        expect(flag.key, 'dark_mode');
        expect(flag.enabled, isTrue);
        expect(flag.minAppVersion, '1.0.0');
      });

      test('defaults enabled to false', () {
        final json = {'key': 'test_flag'};
        final flag = FeatureFlagResponse.fromJson(json);
        expect(flag.enabled, isFalse);
      });
    });

    group('UpdateCheckResponse', () {
      test('parses update check with update available', () {
        final json = {
          'update_available': true,
          'latest_version': '2.0.0',
          'current_version': '1.0.0',
          'is_mandatory': true,
          'release_notes': 'New features',
          'download_url': 'https://svid.app/download',
          'file_size': 50000000,
          'checksum': 'abc123',
          'published_at': '2026-02-01',
        };

        final update = UpdateCheckResponse.fromJson(json);
        expect(update.updateAvailable, isTrue);
        expect(update.latestVersion, '2.0.0');
        expect(update.isMandatory, isTrue);
        expect(update.fileSize, 50000000);
      });

      test('parses no update available', () {
        final json = {
          'current_version': '1.0.0',
        };

        final update = UpdateCheckResponse.fromJson(json);
        expect(update.updateAvailable, isFalse);
        expect(update.isMandatory, isFalse);
        expect(update.latestVersion, isNull);
      });
    });

    group('RegisterResponse', () {
      test('parses registration', () {
        final json = {
          'device_id': 'dev-123',
          'api_key': 'key-abc',
          'is_new': true,
        };

        final reg = RegisterResponse.fromJson(json);
        expect(reg.deviceId, 'dev-123');
        expect(reg.apiKey, 'key-abc');
        expect(reg.isNew, isTrue);
      });
    });

    group('SessionResponse', () {
      test('parses AI session with messages', () {
        final json = {
          'id': 'session-1',
          'device_id': 'dev-1',
          'title': 'Help session',
          'status': 'active',
          'created_at': '2026-01-01',
          'updated_at': '2026-01-01',
          'messages': [
            {
              'id': 'msg-1',
              'session_id': 'session-1',
              'role': 'user',
              'content': 'Hello',
              'tokens_used': 10,
              'created_at': '2026-01-01',
            },
          ],
        };

        final session = SessionResponse.fromJson(json);
        expect(session.title, 'Help session');
        expect(session.messages, isNotNull);
        expect(session.messages!.first.role, 'user');
        expect(session.messages!.first.tokensUsed, 10);
      });
    });

    group('AnnouncementResponse', () {
      test('parses announcement', () {
        final json = {
          'id': 'ann-1',
          'title': 'New Release',
          'content': 'Version 2.0 is here!',
          'type': 'info',
          'starts_at': '2026-01-01',
          'expires_at': '2026-02-01',
          'created_at': '2026-01-01',
        };

        final ann = AnnouncementResponse.fromJson(json);
        expect(ann.title, 'New Release');
        expect(ann.type, 'info');
        expect(ann.startsAt, isNotNull);
      });
    });
  });
}
