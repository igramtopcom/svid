import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import '../../../../core/core.dart';
import '../../../../core/services/opensubtitles_service.dart';

/// Bottom sheet that lets users search OpenSubtitles for a subtitle file
/// and save it alongside the currently-playing video.
///
/// Stores the API key in SharedPreferences under `opensubtitles_api_key`.
class SubtitleSearchSheet extends StatefulWidget {
  /// Path to the video file (used to derive the save location and query).
  final String videoFilePath;

  /// Called with the saved `.srt` file path after a successful download.
  final void Function(String srtPath)? onSubtitleSaved;

  const SubtitleSearchSheet({
    super.key,
    required this.videoFilePath,
    this.onSubtitleSaved,
  });

  @override
  State<SubtitleSearchSheet> createState() => _SubtitleSearchSheetState();

  /// Show as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String videoFilePath,
    void Function(String srtPath)? onSubtitleSaved,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SubtitleSearchSheet(
        videoFilePath: videoFilePath,
        onSubtitleSaved: onSubtitleSaved,
      ),
    );
  }
}

class _SubtitleSearchSheetState extends State<SubtitleSearchSheet> {
  static const _prefKeyApiKey = 'opensubtitles_api_key';
  static const _prefKeyLastLang = 'opensubtitles_last_lang';

  final _apiKeyController = TextEditingController();
  final _queryController = TextEditingController();
  final _langController = TextEditingController();

  String? _savedApiKey;
  bool _loadingPrefs = true;
  bool _searching = false;
  bool _downloading = false;
  String? _error;

  List<SubtitleResult> _results = [];
  int? _downloadingId;

  @override
  void initState() {
    super.initState();
    // Pre-fill query with video filename (without extension)
    final baseName = p.basenameWithoutExtension(widget.videoFilePath);
    _queryController.text = baseName;
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_prefKeyApiKey) ?? '';
    final lang = prefs.getString(_prefKeyLastLang) ?? 'en';
    if (mounted) {
      setState(() {
        _savedApiKey = key.isEmpty ? null : key;
        _apiKeyController.text = key;
        _langController.text = lang;
        _loadingPrefs = false;
      });
    }
  }

  Future<void> _saveApiKey() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyApiKey, key);
    if (mounted) {
      setState(() => _savedApiKey = key);
      AppSnackBar.success(context, message: AppLocalizations.subtitleSearchApiKeySave);
    }
  }

  Future<void> _search() async {
    final apiKey = _savedApiKey ?? _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      setState(() => _error = AppLocalizations.subtitleSearchApiKeyRequired);
      return;
    }

    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    final lang = _langController.text.trim().isNotEmpty
        ? _langController.text.trim()
        : 'en';

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyLastLang, lang);

    setState(() {
      _searching = true;
      _error = null;
      _results = [];
    });

    try {
      final service = OpenSubtitlesService(apiKey);
      final results = await service.searchSubtitles(query, language: lang);
      if (mounted) {
        setState(() {
          _results = results;
          _searching = false;
          if (results.isEmpty) _error = AppLocalizations.subtitleSearchNoResults;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searching = false;
          _error = '${AppLocalizations.subtitleSearchError}: $e';
        });
      }
    }
  }

  Future<void> _downloadSubtitle(SubtitleResult result) async {
    final apiKey = _savedApiKey ?? _apiKeyController.text.trim();
    if (apiKey.isEmpty) return;

    setState(() {
      _downloading = true;
      _downloadingId = result.fileId;
      _error = null;
    });

    try {
      final service = OpenSubtitlesService(apiKey);
      final link = await service.getDownloadLink(result.fileId);
      final content = await service.downloadSubtitleContent(link);

      // Save as <videoname>.<lang>.srt alongside the video
      final dir = p.dirname(widget.videoFilePath);
      final base = p.basenameWithoutExtension(widget.videoFilePath);
      final lang = result.language.isNotEmpty ? result.language : 'sub';
      final srtPath = p.join(dir, '$base.$lang.srt');

      await File(srtPath).writeAsString(content);

      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadingId = null;
        });
        widget.onSubtitleSaved?.call(srtPath);
        AppSnackBar.success(context, message: AppLocalizations.subtitleSearchSaved);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadingId = null;
          _error = '${AppLocalizations.subtitleSearchError}: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _queryController.dispose();
    _langController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPrefs) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.subtitles_outlined),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.subtitleSearchTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // API key row (collapsed if already saved)
              if (_savedApiKey == null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _apiKeyController,
                          decoration: InputDecoration(
                            labelText: AppLocalizations.subtitleSearchApiKeyLabel,
                            hintText: AppLocalizations.subtitleSearchApiKeyHint,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          obscureText: true,
                          onSubmitted: (_) => _saveApiKey(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _saveApiKey,
                        child: Text(AppLocalizations.subtitleSearchApiKeySave),
                      ),
                    ],
                  ),
                ),

              if (_savedApiKey != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        AppLocalizations.subtitleSearchApiKeyLabel,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.green),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() => _savedApiKey = null),
                        child: Text(AppLocalizations.playerSubtitlesChange),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 8),

              // Query + language + search button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: TextField(
                        controller: _queryController,
                        decoration: InputDecoration(
                          hintText: AppLocalizations.subtitleSearchHint,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _search(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 52,
                      child: TextField(
                        controller: _langController,
                        decoration: const InputDecoration(
                          hintText: 'en',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        maxLength: 5,
                        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                        textAlign: TextAlign.center,
                        onSubmitted: (_) => _search(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _searching ? null : _search,
                      child: _searching
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(AppLocalizations.subtitleSearchButton),
                    ),
                  ],
                ),
              ),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    _error!,
                    style: AppTypography.metadata.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),

              const SizedBox(height: 8),
              const Divider(height: 1),

              // Results
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final result = _results[index];
                    final isDownloading =
                        _downloading && _downloadingId == result.fileId;
                    return ListTile(
                      leading: const Icon(Icons.subtitles, size: 20),
                      title: Text(
                        result.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${result.language.toUpperCase()}'
                        '${result.downloadCount != null ? ' · ${result.downloadCount} downloads' : ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: isDownloading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              icon: const Icon(Icons.download),
                              onPressed: _downloading
                                  ? null
                                  : () => _downloadSubtitle(result),
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
