import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/brand_config.dart';

/// Result from an OpenSubtitles subtitle search.
class SubtitleResult {
  final int fileId;
  final String language;
  final String fileName;
  final int? downloadCount;

  const SubtitleResult({
    required this.fileId,
    required this.language,
    required this.fileName,
    this.downloadCount,
  });
}

/// Light wrapper around the OpenSubtitles REST API v1.
///
/// Requires a free API key from https://www.opensubtitles.com/consumers
/// Rate limit: 5 downloads/day on free tier.
class OpenSubtitlesService {
  static const _baseUrl = 'https://api.opensubtitles.com/api/v1';
  static final _userAgent = '${BrandConfig.current.appName} v1.0';

  final String apiKey;

  const OpenSubtitlesService(this.apiKey);

  Map<String, String> get _headers => {
        'Api-Key': apiKey,
        'User-Agent': _userAgent,
        'Content-Type': 'application/json',
      };

  /// Search for subtitles by title query and optional language code (e.g. "en").
  Future<List<SubtitleResult>> searchSubtitles(
    String query, {
    String language = 'en',
  }) async {
    final uri = Uri.parse('$_baseUrl/subtitles').replace(
      queryParameters: {
        'query': query,
        'languages': language,
        'type': 'movie',
      },
    );

    final response = await http.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('OpenSubtitles search failed (${response.statusCode}): ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'] as List<dynamic>? ?? [];

    final results = <SubtitleResult>[];
    for (final item in data) {
      final attrs = item['attributes'] as Map<String, dynamic>?;
      if (attrs == null) continue;

      final files = attrs['files'] as List<dynamic>? ?? [];
      if (files.isEmpty) continue;

      final file = files.first as Map<String, dynamic>;
      final fileId = file['file_id'];
      if (fileId == null) continue;

      results.add(SubtitleResult(
        fileId: fileId as int,
        language: (attrs['language'] as String?) ?? language,
        fileName: (file['file_name'] as String?) ?? 'subtitle',
        downloadCount: attrs['download_count'] as int?,
      ));
    }
    return results;
  }

  /// Obtain the download link for a subtitle file.
  /// Returns the direct download URL.
  Future<String> getDownloadLink(int fileId) async {
    final uri = Uri.parse('$_baseUrl/download');
    final response = await http.post(
      uri,
      headers: _headers,
      body: jsonEncode({'file_id': fileId}),
    );

    if (response.statusCode != 200) {
      throw Exception('OpenSubtitles download failed (${response.statusCode}): ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final link = json['link'] as String?;
    if (link == null) {
      throw Exception('OpenSubtitles: no download link in response');
    }
    return link;
  }

  /// Download subtitle content (SRT/VTT bytes) from a direct link.
  Future<String> downloadSubtitleContent(String downloadUrl) async {
    final response = await http.get(Uri.parse(downloadUrl));
    if (response.statusCode != 200) {
      throw Exception('Failed to download subtitle content (${response.statusCode})');
    }
    return response.body;
  }
}
