import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/domain/entities/download_entity.dart';
import 'package:ssvid/features/downloads/domain/entities/download_status.dart';
import 'package:ssvid/features/downloads/domain/entities/sorting_rule.dart';
import 'package:ssvid/features/downloads/domain/services/sorting_rule_service.dart';

DownloadEntity _entity({
  String platform = 'youtube',
  String filename = 'My Video.mp4',
  String url = 'https://youtube.com/watch?v=abc',
  String? title,
  String? uploader,
  String? uploadDate,
  String? qualityLabel,
}) =>
    DownloadEntity(
      id: 1,
      url: url,
      filename: filename,
      savePath: '/Downloads/$filename',
      status: DownloadStatus.completed,
      totalBytes: 1000,
      downloadedBytes: 1000,
      speed: 0,
      platform: platform,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 15),
      title: title ?? 'My Video',
      uploader: uploader ?? 'Test Channel',
      uploadDate: uploadDate ?? '20260101',
      qualityLabel: qualityLabel ?? '1080p',
    );

SortingRule _rule({
  String id = 'r1',
  String platform = '',
  String fileExtension = '',
  String urlContains = '',
  String destFolder = '',
  String renameTemplate = '',
  bool isEnabled = true,
  int order = 0,
}) =>
    SortingRule(
      id: id,
      name: 'Test Rule',
      condition: SortingCondition(
        platform: platform,
        fileExtension: fileExtension,
        urlContains: urlContains,
      ),
      destFolder: destFolder,
      renameTemplate: renameTemplate,
      isEnabled: isEnabled,
      order: order,
    );

void main() {
  final service = SortingRuleService();

  // ── matchesRule ────────────────────────────────────────────────────────────

  group('matchesRule', () {
    test('wildcard rule matches any download', () {
      expect(service.matchesRule(_entity(), _rule()), isTrue);
    });

    test('platform match — correct platform', () {
      expect(
        service.matchesRule(_entity(platform: 'youtube'), _rule(platform: 'youtube')),
        isTrue,
      );
    });

    test('platform match — wrong platform', () {
      expect(
        service.matchesRule(_entity(platform: 'tiktok'), _rule(platform: 'youtube')),
        isFalse,
      );
    });

    test('platform match is case-insensitive', () {
      expect(
        service.matchesRule(_entity(platform: 'YouTube'), _rule(platform: 'youtube')),
        isTrue,
      );
    });

    test('fileExtension match — correct ext', () {
      expect(
        service.matchesRule(_entity(filename: 'video.mp4'), _rule(fileExtension: 'mp4')),
        isTrue,
      );
    });

    test('fileExtension match — wrong ext', () {
      expect(
        service.matchesRule(_entity(filename: 'audio.mp3'), _rule(fileExtension: 'mp4')),
        isFalse,
      );
    });

    test('urlContains match — URL contains substring', () {
      expect(
        service.matchesRule(
          _entity(url: 'https://youtube.com/playlist?list=PL123'),
          _rule(urlContains: 'playlist'),
        ),
        isTrue,
      );
    });

    test('urlContains match — URL does not contain substring', () {
      expect(
        service.matchesRule(
          _entity(url: 'https://youtube.com/watch?v=abc'),
          _rule(urlContains: 'playlist'),
        ),
        isFalse,
      );
    });

    test('AND logic — all conditions must match', () {
      expect(
        service.matchesRule(
          _entity(platform: 'youtube', filename: 'v.mp4'),
          _rule(platform: 'youtube', fileExtension: 'mp4'),
        ),
        isTrue,
      );
    });

    test('AND logic — one condition fails → no match', () {
      expect(
        service.matchesRule(
          _entity(platform: 'tiktok', filename: 'v.mp4'),
          _rule(platform: 'youtube', fileExtension: 'mp4'),
        ),
        isFalse,
      );
    });

    test('disabled rule still matches (matchesRule ignores isEnabled)', () {
      expect(
        service.matchesRule(_entity(), _rule(isEnabled: false)),
        isTrue,
      );
    });
  });

  // ── findMatchingRule ───────────────────────────────────────────────────────

  group('findMatchingRule', () {
    test('returns null for empty rules list', () {
      expect(service.findMatchingRule(_entity(), []), isNull);
    });

    test('returns first matching rule by order', () {
      final rules = [
        _rule(id: 'a', platform: 'youtube', order: 0),
        _rule(id: 'b', platform: 'youtube', order: 1),
      ];
      final result = service.findMatchingRule(_entity(platform: 'youtube'), rules);
      expect(result?.id, 'a');
    });

    test('skips disabled rules', () {
      final rules = [
        _rule(id: 'a', platform: 'youtube', order: 0, isEnabled: false),
        _rule(id: 'b', platform: 'youtube', order: 1, isEnabled: true),
      ];
      final result = service.findMatchingRule(_entity(platform: 'youtube'), rules);
      expect(result?.id, 'b');
    });

    test('returns null when no rule matches', () {
      final rules = [_rule(platform: 'tiktok')];
      expect(service.findMatchingRule(_entity(platform: 'youtube'), rules), isNull);
    });

    test('orders by order field regardless of list insertion order', () {
      final rules = [
        _rule(id: 'high', platform: 'youtube', order: 1),
        _rule(id: 'low', platform: 'youtube', order: 0),
      ];
      final result = service.findMatchingRule(_entity(platform: 'youtube'), rules);
      expect(result?.id, 'low');
    });
  });

  // ── applyRename ────────────────────────────────────────────────────────────

  group('applyRename', () {
    test('empty template returns original filename', () {
      expect(
        service.applyRename('', _entity(filename: 'original.mp4')),
        'original.mp4',
      );
    });

    test('substitutes {title}', () {
      final result = service.applyRename(
        '{title}.{ext}',
        _entity(filename: 'x.mp4', title: 'My Video'),
      );
      expect(result, 'My Video.mp4');
    });

    test('substitutes {uploader}', () {
      final result = service.applyRename(
        '{title} - {uploader}.{ext}',
        _entity(filename: 'x.mp4', title: 'Video', uploader: 'Channel'),
      );
      expect(result, 'Video - Channel.mp4');
    });

    test('substitutes {date} (upload date)', () {
      final result = service.applyRename(
        '{date}_{title}.{ext}',
        _entity(filename: 'x.mp4', title: 'V', uploadDate: '20260115'),
      );
      expect(result, '20260115_V.mp4');
    });

    test('substitutes {download_date}', () {
      final result = service.applyRename(
        '{download_date}.{ext}',
        _entity(filename: 'x.mp4'),
      );
      // Should be a valid YYYYMMDD-like string
      expect(result, matches(RegExp(r'^\d{8}\.mp4$')));
    });

    test('substitutes {platform}', () {
      final result = service.applyRename(
        '{platform}/{title}.{ext}',
        _entity(filename: 'x.mp4', title: 'V', platform: 'youtube'),
      );
      // Path separator in filename is sanitized
      expect(result, contains('youtube'));
    });

    test('substitutes {quality}', () {
      final result = service.applyRename(
        '{title} [{quality}].{ext}',
        _entity(filename: 'x.mp4', title: 'V', qualityLabel: '1080p'),
      );
      expect(result, 'V [1080p].mp4');
    });

    test('sanitizes forbidden characters in title', () {
      final result = service.applyRename(
        '{title}.{ext}',
        _entity(filename: 'x.mp4', title: 'Video: "Best"'),
      );
      // Colons and quotes should be sanitized
      expect(result, isNot(contains(':')));
      expect(result, endsWith('.mp4'));
    });

    test('preserves extension when template lacks {ext}', () {
      final result = service.applyRename(
        '{title}',
        _entity(filename: 'x.mp4', title: 'My Video'),
      );
      expect(result, endsWith('.mp4'));
    });
  });

  // ── SortingCondition serialization ────────────────────────────────────────

  group('SortingCondition toJson/fromJson', () {
    test('round-trip preserves all fields', () {
      const cond = SortingCondition(
        platform: 'youtube',
        fileExtension: 'mp4',
        urlContains: 'shorts',
      );
      final json = cond.toJson();
      final restored = SortingCondition.fromJson(json);
      expect(restored.platform, 'youtube');
      expect(restored.fileExtension, 'mp4');
      expect(restored.urlContains, 'shorts');
    });

    test('isWildcard when all fields empty', () {
      const cond = SortingCondition();
      expect(cond.isWildcard, isTrue);
    });
  });

  // ── SortingRule serialization ──────────────────────────────────────────────

  group('SortingRule toJson/fromJson', () {
    test('round-trip preserves all fields', () {
      final rule = _rule(
        id: 'abc',
        platform: 'youtube',
        destFolder: '/Videos',
        renameTemplate: '{title}.{ext}',
        isEnabled: false,
        order: 3,
      );
      final restored = SortingRule.fromJson(rule.toJson());
      expect(restored.id, 'abc');
      expect(restored.condition.platform, 'youtube');
      expect(restored.destFolder, '/Videos');
      expect(restored.renameTemplate, '{title}.{ext}');
      expect(restored.isEnabled, isFalse);
      expect(restored.order, 3);
    });
  });
}
