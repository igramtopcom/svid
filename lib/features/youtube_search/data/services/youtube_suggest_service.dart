import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../core/core.dart';

/// Service for fetching YouTube search suggestions
class YouTubeSuggestService {
  static const String _baseUrl = 'https://suggestqueries.google.com/complete/search';

  final http.Client _client;

  YouTubeSuggestService({http.Client? client})
      : _client = client ?? http.Client();

  /// Get search suggestions for a query
  /// Returns list of suggestion strings
  Future<Result<List<String>>> getSuggestions(String query) async {
    if (query.trim().isEmpty) {
      return Result.success([]);
    }

    try {
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        'client': 'firefox',
        'ds': 'yt', // YouTube dataset
        'q': query.trim(),
      });

      appLogger.debug('[YouTube Suggest] Fetching suggestions for: "$query"');

      final response = await _client.get(uri).timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw Exception('Suggestion request timeout'),
      );

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      // Response format: [query, [suggestions], ...other metadata]
      final decoded = json.decode(response.body) as List;

      if (decoded.length < 2 || decoded[1] is! List) {
        return Result.success([]);
      }

      final suggestions = (decoded[1] as List)
          .map((s) => s.toString())
          .where((s) => s.isNotEmpty)
          .toList();

      appLogger.debug('[YouTube Suggest] Found ${suggestions.length} suggestions');

      return Result.success(suggestions);
    } catch (e) {
      appLogger.warning('[YouTube Suggest] Failed to fetch suggestions: $e');
      return Result.failure(Exception('Failed to fetch suggestions: $e'));
    }
  }

  void dispose() {
    _client.close();
  }
}
