import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('translation assets', () {
    test('all locales have the same key tree and placeholders as English', () {
      final dir = Directory('assets/translations');
      final files =
          dir
              .listSync()
              .whereType<File>()
              .where((file) => file.path.endsWith('.json'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      final english = files.firstWhere(
        (file) => file.path.endsWith('/en.json'),
      );
      final base = _flatten(_readJson(english));
      final baseKeys = base.keys.toSet();

      for (final file in files) {
        final locale = file.uri.pathSegments.last;
        final current = _flatten(_readJson(file));
        final currentKeys = current.keys.toSet();

        expect(
          currentKeys.difference(baseKeys).toList()..sort(),
          isEmpty,
          reason: '$locale has keys that en.json does not have',
        );
        expect(
          baseKeys.difference(currentKeys).toList()..sort(),
          isEmpty,
          reason: '$locale is missing keys from en.json',
        );

        for (final key in baseKeys) {
          final expected = _placeholders(base[key] ?? '');
          final actual = _placeholders(current[key] ?? '');
          expect(
            actual,
            expected,
            reason: '$locale placeholder mismatch at "$key"',
          );
        }
      }
    });
  });
}

Map<String, dynamic> _readJson(File file) {
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

Map<String, String> _flatten(
  Map<String, dynamic> source, [
  String prefix = '',
]) {
  final output = <String, String>{};
  source.forEach((key, value) {
    final fullKey = prefix.isEmpty ? key : '$prefix.$key';
    if (value is Map<String, dynamic>) {
      output.addAll(_flatten(value, fullKey));
    } else {
      output[fullKey] = value.toString();
    }
  });
  return output;
}

Set<String> _placeholders(String value) {
  return RegExp(
    r'\{[A-Za-z0-9_]+\}',
  ).allMatches(value).map((match) => match.group(0)!).toSet();
}
