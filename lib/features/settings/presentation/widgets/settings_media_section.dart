import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../../player/presentation/providers/player_hardware_decode_provider.dart';
import '../providers/settings_provider.dart';
import 'settings_shared_widgets.dart';

class SettingsMediaSection extends ConsumerWidget {
  const SettingsMediaSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        settingsSectionTitle(
          context,
          AppLocalizations.settingsSectionMediaProcessing,
        ),
        const Gap.md(),

        // Card: Thumbnails
        settingsCard(
          context,
          title: AppLocalizations.settingsMediaCardThumbnails.toUpperCase(),
          children: [
            BrandSwitchListTile(
              secondary: const Icon(Icons.image, size: 20),
              title: Text(
                AppLocalizations.settingsMediaEnhancementsDownloadThumbnail,
              ),
              subtitle: Text(
                AppLocalizations.settingsMediaEnhancementsDownloadThumbnailDesc,
              ),
              value: settings.writeThumbnail,
              onChanged:
                  (_) =>
                      ref
                          .read(settingsProvider.notifier)
                          .toggleWriteThumbnail(),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            BrandSwitchListTile(
              secondary: const Icon(Icons.photo_album, size: 20),
              title: Text(
                AppLocalizations.settingsMediaEnhancementsEmbedThumbnail,
              ),
              subtitle: Text(
                AppLocalizations.settingsMediaEnhancementsEmbedThumbnailDesc,
              ),
              value: settings.embedThumbnail,
              onChanged:
                  (_) =>
                      ref
                          .read(settingsProvider.notifier)
                          .toggleEmbedThumbnail(),
            ),
          ],
        ),

        const Gap.md(),

        // Card: Metadata
        settingsCard(
          context,
          title: AppLocalizations.settingsMediaCardMetadata.toUpperCase(),
          children: [
            BrandSwitchListTile(
              secondary: const Icon(Icons.info_outline, size: 20),
              title: Text(
                AppLocalizations.settingsMediaEnhancementsEmbedMetadata,
              ),
              subtitle: Text(
                AppLocalizations.settingsMediaEnhancementsEmbedMetadataDesc,
              ),
              value: settings.embedMetadata,
              onChanged:
                  (_) =>
                      ref.read(settingsProvider.notifier).toggleEmbedMetadata(),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            BrandSwitchListTile(
              secondary: const Icon(Icons.bookmark_outline, size: 20),
              title: Text(
                AppLocalizations.settingsMediaEnhancementsEmbedChapters,
              ),
              subtitle: Text(
                AppLocalizations.settingsMediaEnhancementsEmbedChaptersDesc,
              ),
              value: settings.embedChapters,
              onChanged:
                  (_) =>
                      ref.read(settingsProvider.notifier).toggleEmbedChapters(),
            ),
          ],
        ),

        const Gap.md(),

        // Card: Playback (default-off opt-in for hardware video decode).
        // The flag lives in its own provider rather than `settings`
        // because libmpv evaluates `hwdec` at codec-open time — the
        // value has to be read at Player init, not at download time,
        // so coupling it to the download-flow Settings struct would
        // be misleading.
        settingsCard(
          context,
          title: AppLocalizations.settingsPlayerCardTitle.toUpperCase(),
          children: [
            BrandSwitchListTile(
              secondary: const Icon(Icons.bolt_rounded, size: 20),
              title: Text(AppLocalizations.settingsPlayerHardwareDecodeTitle),
              subtitle: Text(
                AppLocalizations.settingsPlayerHardwareDecodeSubtitle,
              ),
              value: ref.watch(hardwareDecodeEnabledProvider),
              onChanged:
                  (next) => ref
                      .read(hardwareDecodeEnabledProvider.notifier)
                      .set(next),
            ),
          ],
        ),

        const Gap.md(),

        // Card: Subtitles
        settingsCard(
          context,
          title: AppLocalizations.settingsSectionSubtitles.toUpperCase(),
          children: [
            BrandSwitchListTile(
              secondary: const Icon(Icons.subtitles, size: 20),
              title: Text(AppLocalizations.settingsSubtitlesDownloadSubtitles),
              subtitle: Text(
                AppLocalizations.settingsSubtitlesDownloadSubtitlesDesc,
              ),
              value: settings.subtitlesEnabled,
              onChanged:
                  (_) => ref.read(settingsProvider.notifier).toggleSubtitles(),
            ),
            if (settings.subtitlesEnabled) ...[
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.language, size: 20),
                title: Text(
                  AppLocalizations.settingsSubtitlesSubtitleLanguages,
                ),
                subtitle: Text(settings.subtitlesLanguages.join(', ')),
                trailing: const Icon(Icons.chevron_right),
                onTap:
                    () => _showSubtitleLanguagesDialog(
                      context,
                      ref,
                      settings.subtitlesLanguages,
                    ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.text_format, size: 20),
                title: Text(AppLocalizations.settingsSubtitlesSubtitleFormat),
                subtitle: Text(settings.subtitlesFormat.toUpperCase()),
                trailing: const Icon(Icons.chevron_right),
                onTap:
                    () => _showSubtitleFormatDialog(
                      context,
                      ref,
                      settings.subtitlesFormat,
                    ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              BrandSwitchListTile(
                secondary: const Icon(Icons.merge, size: 20),
                title: Text(AppLocalizations.settingsSubtitlesEmbedSubtitles),
                subtitle: Text(
                  AppLocalizations.settingsSubtitlesEmbedSubtitlesDesc,
                ),
                value: settings.embedSubtitles,
                onChanged:
                    (_) =>
                        ref
                            .read(settingsProvider.notifier)
                            .toggleEmbedSubtitles(),
              ),
            ],
          ],
        ),

        const Gap.md(),

        // Card: SponsorBlock
        settingsCard(
          context,
          title: AppLocalizations.settingsMediaCardSponsorBlock.toUpperCase(),
          children: [
            BrandSwitchListTile(
              secondary: const Icon(Icons.skip_next, size: 20),
              title: Text(
                AppLocalizations.settingsSponsorBlockSectionEnableSponsorBlock,
              ),
              subtitle: Text(
                AppLocalizations
                    .settingsSponsorBlockSectionEnableSponsorBlockDesc,
              ),
              value: settings.sponsorBlockEnabled,
              onChanged:
                  (_) =>
                      ref.read(settingsProvider.notifier).toggleSponsorBlock(),
            ),
            if (settings.sponsorBlockEnabled) ...[
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.build, size: 20),
                title: Text(
                  AppLocalizations
                      .settingsSponsorBlockSectionSponsorBlockAction,
                ),
                subtitle: Text(
                  _getSponsorBlockActionLabel(settings.sponsorBlockAction),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap:
                    () => _showSponsorBlockActionDialog(
                      context,
                      ref,
                      settings.sponsorBlockAction,
                    ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.category, size: 20),
                title: Text(
                  AppLocalizations.settingsSponsorBlockSectionSegmentCategories,
                ),
                subtitle: Text(
                  '${settings.sponsorBlockCategories.length} selected',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap:
                    () => _showSponsorBlockCategoriesDialog(
                      context,
                      ref,
                      settings.sponsorBlockCategories,
                    ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _getSponsorBlockActionLabel(String action) {
    switch (action) {
      case 'skip':
        return 'Mark as Chapters (Skip)';
      case 'remove':
        return 'Remove from Video';
      case 'chapter':
        return 'Mark as Chapters Only';
      default:
        return action;
    }
  }

  // ===========================================================================
  // DIALOGS
  // ===========================================================================

  void _showSubtitleLanguagesDialog(
    BuildContext context,
    WidgetRef ref,
    List<String> current,
  ) {
    final availableLanguages = [
      ('en', AppLocalizations.settingsSubtitlesLanguageEnglish),
      ('vi', AppLocalizations.settingsSubtitlesLanguageVietnamese),
      ('zh', AppLocalizations.settingsSubtitlesLanguageChinese),
      ('ja', AppLocalizations.settingsSubtitlesLanguageJapanese),
      ('ko', AppLocalizations.settingsSubtitlesLanguageKorean),
      ('es', AppLocalizations.settingsSubtitlesLanguageSpanish),
      ('fr', AppLocalizations.settingsSubtitlesLanguageFrench),
      ('de', AppLocalizations.settingsSubtitlesLanguageGerman),
      ('pt', AppLocalizations.settingsSubtitlesLanguagePortuguese),
      ('ru', AppLocalizations.settingsSubtitlesLanguageRussian),
      ('ar', AppLocalizations.settingsSubtitlesLanguageArabic),
      ('hi', AppLocalizations.settingsSubtitlesLanguageHindi),
      ('auto', AppLocalizations.settingsSubtitlesLanguageAuto),
      ('all', AppLocalizations.settingsSubtitlesLanguageAll),
    ];

    final selected = Set<String>.from(current);

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: Text(
                    AppLocalizations.settingsSubtitlesSelectLanguagesTitle,
                  ),
                  content: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 520,
                      maxHeight: MediaQuery.sizeOf(context).height * 0.66,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children:
                            availableLanguages.map((lang) {
                              final (code, name) = lang;
                              return CheckboxListTile(
                                title: Text(name),
                                subtitle: Text(code),
                                value: selected.contains(code),
                                onChanged: (value) {
                                  setState(() {
                                    if (value == true) {
                                      selected.add(code);
                                    } else {
                                      selected.remove(code);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(AppLocalizations.commonCancel),
                    ),
                    TextButton(
                      onPressed: () {
                        if (selected.isEmpty) {
                          selected.add('en');
                        }
                        ref
                            .read(settingsProvider.notifier)
                            .updateSubtitlesLanguages(selected.toList());
                        Navigator.pop(context);
                      },
                      child: Text(AppLocalizations.settingsSubtitlesSave),
                    ),
                  ],
                ),
          ),
    );
  }

  void _showSubtitleFormatDialog(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) {
    final formats = [
      ('srt', 'SRT', 'Most compatible format'),
      ('vtt', 'VTT', 'WebVTT format'),
      ('ass', 'ASS', 'Advanced SubStation Alpha'),
    ];

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(AppLocalizations.settingsSubtitlesSubtitleFormat),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children:
                    formats.map((fmt) {
                      final (value, name, description) = fmt;
                      return RadioListTile<String>(
                        title: Text(name),
                        subtitle: Text(description),
                        value: value,
                        groupValue: current,
                        onChanged: (v) {
                          if (v != null) {
                            ref
                                .read(settingsProvider.notifier)
                                .updateSubtitlesFormat(v);
                            Navigator.pop(context);
                          }
                        },
                      );
                    }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.commonCancel),
              ),
            ],
          ),
    );
  }

  void _showSponsorBlockActionDialog(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) {
    final actions = [
      (
        'skip',
        'Mark as Chapters (Skip)',
        'Segments marked as chapters for easy skipping',
      ),
      (
        'remove',
        'Remove from Video',
        'Cut out segments from the video (requires FFmpeg)',
      ),
      (
        'chapter',
        'Mark as Chapters Only',
        'Add chapter markers without modifying video',
      ),
    ];

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              AppLocalizations.settingsSponsorBlockSectionSponsorBlockAction,
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children:
                    actions.map((act) {
                      final (value, name, description) = act;
                      return RadioListTile<String>(
                        title: Text(name),
                        subtitle: Text(description),
                        value: value,
                        groupValue: current,
                        onChanged: (v) {
                          if (v != null) {
                            ref
                                .read(settingsProvider.notifier)
                                .updateSponsorBlockAction(v);
                            Navigator.pop(context);
                          }
                        },
                      );
                    }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.commonCancel),
              ),
            ],
          ),
    );
  }

  void _showSponsorBlockCategoriesDialog(
    BuildContext context,
    WidgetRef ref,
    List<String> current,
  ) {
    final categories = [
      ('sponsor', 'Sponsor', 'Paid promotion or product placement'),
      ('intro', 'Intro', 'Intermission/intro animation'),
      ('outro', 'Outro', 'End credits/outro'),
      ('selfpromo', 'Self-Promotion', 'Promoting own products/channels'),
      ('interaction', 'Interaction', 'Subscribe reminders, like requests'),
      ('music_offtopic', 'Non-Music', 'Non-music section in music video'),
      ('preview', 'Preview', 'Preview/recap of content'),
      ('filler', 'Filler', 'Tangents or jokes'),
    ];

    final selected = Set<String>.from(current);

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: Text(
                    AppLocalizations
                        .settingsSponsorBlockSectionSegmentCategories,
                  ),
                  content: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 540,
                      maxHeight: MediaQuery.sizeOf(context).height * 0.66,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children:
                            categories.map((cat) {
                              final (code, name, description) = cat;
                              return CheckboxListTile(
                                title: Text(name),
                                subtitle: Text(description),
                                value: selected.contains(code),
                                onChanged: (value) {
                                  setState(() {
                                    if (value == true) {
                                      selected.add(code);
                                    } else {
                                      selected.remove(code);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(AppLocalizations.commonCancel),
                    ),
                    TextButton(
                      onPressed: () {
                        if (selected.isEmpty) {
                          selected.add('sponsor');
                        }
                        ref
                            .read(settingsProvider.notifier)
                            .updateSponsorBlockCategories(selected.toList());
                        Navigator.pop(context);
                      },
                      child: Text(AppLocalizations.settingsNetworkAdvancedSave),
                    ),
                  ],
                ),
          ),
    );
  }
}
