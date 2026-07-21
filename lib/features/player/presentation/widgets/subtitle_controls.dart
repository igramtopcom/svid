import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/core.dart';
import '../providers/player_providers.dart';
import '../screens/video_player_screen.dart' show ExternalSubtitle;

/// Maps ISO 639-2/B language codes to human-readable names.
@visibleForTesting
String isoToLanguageName(String code) {
  const map = <String, String>{
    'eng': 'English', 'jpn': 'Japanese', 'kor': 'Korean',
    'zho': 'Chinese', 'cmn': 'Chinese', 'yue': 'Cantonese',
    'fra': 'French', 'deu': 'German', 'spa': 'Spanish',
    'por': 'Portuguese', 'ita': 'Italian', 'rus': 'Russian',
    'ara': 'Arabic', 'hin': 'Hindi', 'vie': 'Vietnamese',
    'tha': 'Thai', 'ind': 'Indonesian', 'msa': 'Malay',
    'nld': 'Dutch', 'pol': 'Polish', 'swe': 'Swedish',
    'tur': 'Turkish', 'und': 'Undetermined',
  };
  return map[code.toLowerCase()] ?? code;
}

/// Returns a display label for an audio track.
///
/// Priority: language name (ISO 639 -> human-readable) + code -> title -> "Track N"
String audioTrackLabel(AudioTrack track, int index) {
  final lang = track.language;
  if (lang != null && lang.isNotEmpty) {
    final langName = isoToLanguageName(lang);
    return '$langName ($lang)';
  }
  final title = track.title;
  if (title != null && title.isNotEmpty) return title;
  return 'Track ${index + 1}';
}

/// Builds the subtitle & audio track popup menu button.
Widget buildSubtitleButton({
  required Player player,
  required WidgetRef ref,
  required BuildContext context,
  required List<ExternalSubtitle> externalSubtitles,
  required VoidCallback? onLoadSubtitleFile,
  required VoidCallback? onSearchSubtitlesOnline,
  required VoidCallback onShowDelayDialog,
  required VoidCallback onShowAppearanceDialog,
}) {
  final currentTrack = ref.watch(currentSubtitleTrackProvider);
  final currentAudioTrack = ref.watch(currentAudioTrackProvider);
  final subtitleDelay = ref.watch(subtitleDelayProvider);
  final isSubtitleActive = currentTrack.id != 'no';

  return StreamBuilder<Tracks>(
    stream: player.stream.tracks,
    initialData: player.state.tracks,
    builder: (context, snapshot) {
      final tracks = snapshot.data ?? player.state.tracks;
      final embeddedTracks = tracks.subtitle
          .where((t) => t.id != 'auto' && t.id != 'no')
          .toList();
      final audioTracks = tracks.audio
          .where((t) => t.id != 'auto' && t.id != 'no')
          .toList();

      return PopupMenuButton<String>(
        icon: Icon(
          isSubtitleActive ? Icons.subtitles : Icons.subtitles_off_outlined,
          color: Colors.white,
          size: 20,
        ),
        tooltip: AppLocalizations.playerSubtitlesAndAudio,
        onSelected: (value) {
          if (value.startsWith('audio_')) {
            final trackId = value.substring(6);
            final track = audioTracks.firstWhere(
              (t) => t.id == trackId,
              orElse: () => AudioTrack.no(),
            );
            player.setAudioTrack(track);
            ref.read(currentAudioTrackProvider.notifier).state = track;
          } else if (value == 'off') {
            player.setSubtitleTrack(SubtitleTrack.no());
            ref.read(currentSubtitleTrackProvider.notifier).state =
                SubtitleTrack.no();
          } else if (value.startsWith('embedded_')) {
            final trackId = value.substring(9);
            final track = embeddedTracks.firstWhere(
              (t) => t.id == trackId,
              orElse: () => SubtitleTrack.no(),
            );
            player.setSubtitleTrack(track);
            ref.read(currentSubtitleTrackProvider.notifier).state = track;
          } else if (value.startsWith('external_')) {
            final index = int.tryParse(value.substring(9)) ?? 0;
            if (index < externalSubtitles.length) {
              final sub = externalSubtitles[index];
              final track = SubtitleTrack.uri(
                sub.path,
                title: sub.langName,
                language: sub.langCode,
              );
              player.setSubtitleTrack(track);
              ref.read(currentSubtitleTrackProvider.notifier).state = track;
            }
          } else if (value == 'delay') {
            onShowDelayDialog();
          } else if (value == 'load_file') {
            onLoadSubtitleFile?.call();
          } else if (value == 'search_online') {
            onSearchSubtitlesOnline?.call();
          } else if (value == 'appearance') {
            onShowAppearanceDialog();
          }
        },
        itemBuilder: (context) {
          final items = <PopupMenuEntry<String>>[];

          // Audio track section (only if >= 2 audio tracks)
          if (audioTracks.length >= 2) {
            items.add(PopupMenuItem(
              enabled: false,
              child: Text(AppLocalizations.playerAudioTrack,
                  style: AppTypography.metadata.copyWith(fontWeight: AppTypography.bold)),
            ));
            for (int i = 0; i < audioTracks.length; i++) {
              final track = audioTracks[i];
              final label = audioTrackLabel(track, i);
              items.add(CheckedPopupMenuItem(
                value: 'audio_${track.id}',
                checked: currentAudioTrack.id == track.id,
                child: Text(label),
              ));
            }
            items.add(const PopupMenuDivider());
          }

          // Subtitle track section header
          items.add(PopupMenuItem(
            enabled: false,
            child: Text(AppLocalizations.playerSubtitles,
                style: AppTypography.metadata.copyWith(fontWeight: AppTypography.bold)),
          ));

          // Off option
          items.add(CheckedPopupMenuItem(
            value: 'off',
            checked: !isSubtitleActive,
            child: Text(AppLocalizations.playerSubtitleOff),
          ));

          // Embedded tracks
          if (embeddedTracks.isNotEmpty) {
            items.add(PopupMenuItem(
              enabled: false,
              child: Text(AppLocalizations.playerSubtitleEmbedded,
                  style: AppTypography.metadata.copyWith(fontWeight: AppTypography.bold)),
            ));
            for (final track in embeddedTracks) {
              final label =
                  track.title ?? track.language ?? 'Track ${track.id}';
              items.add(CheckedPopupMenuItem(
                value: 'embedded_${track.id}',
                checked: currentTrack.id == track.id,
                child: Text(label),
              ));
            }
          }

          // External subtitle files
          if (externalSubtitles.isNotEmpty) {
            items.add(const PopupMenuDivider());
            items.add(PopupMenuItem(
              enabled: false,
              child: Text(AppLocalizations.playerSubtitleExternalFiles,
                  style: AppTypography.metadata.copyWith(fontWeight: AppTypography.bold)),
            ));
            for (int i = 0; i < externalSubtitles.length; i++) {
              final sub = externalSubtitles[i];
              items.add(CheckedPopupMenuItem(
                value: 'external_$i',
                checked: currentTrack.title == sub.langName &&
                    currentTrack.language == sub.langCode,
                child: Text('${sub.langName} (.${sub.ext})'),
              ));
            }
          }

          // Actions section
          items.add(const PopupMenuDivider());
          // Subtitle delay item
          items.add(PopupMenuItem(
            value: 'delay',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_outlined, size: 16),
                const SizedBox(width: AppSpacing.sm),
                Text(AppLocalizations.playerSubtitleDelay),
                if (subtitleDelay != 0) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: Text(
                      '${subtitleDelay > 0 ? '+' : ''}${subtitleDelay}ms',
                      style: AppTypography.compact.copyWith(
                          color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ));
          items.add(PopupMenuItem(
            value: 'load_file',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_open, size: 16),
                const SizedBox(width: AppSpacing.sm),
                Text(AppLocalizations.subtitleAppearanceLoadFile),
              ],
            ),
          ));
          items.add(PopupMenuItem(
            value: 'search_online',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.search, size: 16),
                const SizedBox(width: AppSpacing.sm),
                Text(AppLocalizations.subtitleSearchOnline),
              ],
            ),
          ));
          items.add(PopupMenuItem(
            value: 'appearance',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.text_format, size: 16),
                const SizedBox(width: AppSpacing.sm),
                Text(AppLocalizations.subtitleAppearanceAppearance),
              ],
            ),
          ));

          return items;
        },
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Subtitle Delay Dialog
// ---------------------------------------------------------------------------

class SubtitleDelayDialog extends ConsumerWidget {
  final WidgetRef ref;

  const SubtitleDelayDialog({super.key, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef watchRef) {
    final delay = watchRef.watch(subtitleDelayProvider);

    void applyDelay(int newDelay) {
      final clamped = newDelay.clamp(-5000, 5000);
      // State tracked here; playback application requires media_kit subtitle
      // delay API (not exposed in v1.2.6 -- apply when API becomes available).
      ref.read(subtitleDelayProvider.notifier).state = clamped;
    }

    return AlertDialog(
      title: Text(AppLocalizations.playerSubtitleDelay),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Current delay display
          Text(
            delay == 0
                ? AppLocalizations.playerSubtitleDelayReset
                : '${delay > 0 ? '+' : ''}${delay}ms',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: AppTypography.bold,
                  color: delay == 0
                      ? null
                      : delay > 0
                          ? Colors.blue
                          : Colors.orange,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Delay adjustment buttons
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () => applyDelay(delay - 500),
                child: const Text('-500ms'),
              ),
              OutlinedButton(
                onPressed: () => applyDelay(delay - 100),
                child: const Text('-100ms'),
              ),
              OutlinedButton(
                onPressed: () => applyDelay(delay + 100),
                child: const Text('+100ms'),
              ),
              OutlinedButton(
                onPressed: () => applyDelay(delay + 500),
                child: const Text('+500ms'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => applyDelay(0),
          child: Text(AppLocalizations.playerSubtitleDelayReset),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.playerDone),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Subtitle Appearance Dialog
// ---------------------------------------------------------------------------

/// Dialog for customizing subtitle appearance (font size, color, background, position).
class SubtitleAppearanceDialog extends StatelessWidget {
  final WidgetRef ref;

  const SubtitleAppearanceDialog({super.key, required this.ref});

  static const _colorPresets = <Color>[
    Color(0xFFFFFFFF), // White
    Color(0xFFFFFF00), // Yellow
    Color(0xFF00FF00), // Green
    Color(0xFF00FFFF), // Cyan
    Color(0xFFFF8800), // Orange
    Color(0xFFFF4444), // Red
  ];

  static const _bgOpacityPresets = <double>[
    0.0,  // None
    0.25, // Light
    0.50, // Medium
    0.75, // Heavy
  ];

  @override
  Widget build(BuildContext context) {
    final fontSize = ref.watch(subtitleFontSizeProvider);
    final textColor = ref.watch(subtitleTextColorProvider);
    final bgEnabled = ref.watch(subtitleBackgroundEnabledProvider);
    final bgColor = ref.watch(subtitleBackgroundColorProvider);
    final bottomPadding = ref.watch(subtitleBottomPaddingProvider);

    return AlertDialog(
      title: Text(AppLocalizations.subtitleAppearanceTitle),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Live preview
              Container(
                width: double.infinity,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                alignment: Alignment.bottomCenter,
                padding: EdgeInsets.only(bottom: bottomPadding.clamp(4, 40) / 2),
                child: Text(
                  AppLocalizations.subtitleAppearancePreview,
                  textAlign: TextAlign.center,
                  style: AppTypography.metadata.copyWith(
                    fontSize: fontSize.clamp(12, 40),
                    color: textColor,
                    backgroundColor: bgEnabled ? bgColor : Colors.transparent,
                    fontWeight: FontWeight.normal,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Font size
              Text(AppLocalizations.subtitleAppearanceFontSize,
                  style: Theme.of(context).textTheme.titleSmall),
              Row(
                children: [
                  Text('A', style: AppTypography.metadata),
                  Expanded(
                    child: Slider(
                      value: fontSize,
                      min: 16,
                      max: 64,
                      divisions: 24,
                      label: '${fontSize.round()}',
                      onChanged: (v) {
                        ref.read(subtitleFontSizeProvider.notifier).state = v;
                        _savePreference('subtitle_font_size', v);
                      },
                    ),
                  ),
                  Text('A', style: AppTypography.appBarTitle.copyWith(fontSize: 24)),
                ],
              ),

              const SizedBox(height: AppSpacing.smMd),

              // Text color
              Text(AppLocalizations.subtitleAppearanceTextColor,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: _colorPresets.map((color) {
                  final isSelected = textColor.toARGB32() == color.toARGB32();
                  return GestureDetector(
                    onTap: () {
                      ref.read(subtitleTextColorProvider.notifier).state = color;
                      _savePreference('subtitle_text_color', color.toARGB32());
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.blue : Colors.grey,
                          width: isSelected ? 3 : 1,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: AppSpacing.smMd),

              // Background
              Text(AppLocalizations.subtitleAppearanceBackground,
                  style: Theme.of(context).textTheme.titleSmall),
              BrandSwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(AppLocalizations.subtitleAppearanceBackground),
                value: bgEnabled,
                onChanged: (v) {
                  ref.read(subtitleBackgroundEnabledProvider.notifier).state = v;
                  _savePreference('subtitle_bg_enabled', v);
                },
              ),

              // Background opacity
              if (bgEnabled) ...[
                Text(AppLocalizations.subtitleAppearanceBackgroundOpacity,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: _bgOpacityPresets.map((opacity) {
                    final currentOpacity = bgColor.a;
                    final isSelected = (currentOpacity - opacity).abs() < 0.05;
                    return ChoiceChip(
                      label: Text('${(opacity * 100).round()}%'),
                      selected: isSelected,
                      onSelected: (_) {
                        final newColor = Color.fromRGBO(0, 0, 0, opacity);
                        ref.read(subtitleBackgroundColorProvider.notifier).state = newColor;
                        _savePreference('subtitle_bg_color', newColor.toARGB32());
                      },
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: AppSpacing.smMd),

              // Position
              Text(AppLocalizations.subtitleAppearancePosition,
                  style: Theme.of(context).textTheme.titleSmall),
              Slider(
                value: bottomPadding,
                min: 0,
                max: 100,
                divisions: 20,
                label: '${bottomPadding.round()}',
                onChanged: (v) {
                  ref.read(subtitleBottomPaddingProvider.notifier).state = v;
                  _savePreference('subtitle_bottom_padding', v);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _resetDefaults(),
          child: Text(AppLocalizations.subtitleAppearanceResetDefault),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }

  void _resetDefaults() {
    ref.read(subtitleFontSizeProvider.notifier).state = 32.0;
    ref.read(subtitleTextColorProvider.notifier).state = const Color(0xFFFFFFFF);
    ref.read(subtitleBackgroundColorProvider.notifier).state = const Color(0xAA000000);
    ref.read(subtitleBackgroundEnabledProvider.notifier).state = true;
    ref.read(subtitleBottomPaddingProvider.notifier).state = 24.0;
    // Persist defaults
    _savePreference('subtitle_font_size', 32.0);
    _savePreference('subtitle_text_color', 0xFFFFFFFF);
    _savePreference('subtitle_bg_color', 0xAA000000);
    _savePreference('subtitle_bg_enabled', true);
    _savePreference('subtitle_bottom_padding', 24.0);
  }

  Future<void> _savePreference(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    }
  }
}
