import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../widgets/settings_search_delegate.dart';
import '../widgets/settings_general_section.dart';
import '../widgets/settings_downloads_section.dart';
import '../widgets/settings_quality_section.dart';
import '../widgets/settings_media_section.dart';
import '../widgets/settings_platforms_section.dart';
import '../widgets/settings_browser_section.dart';
import '../widgets/settings_network_section.dart';
import '../widgets/settings_engine_section.dart';
import '../widgets/settings_premium_section.dart';
import '../widgets/settings_about_section.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Index of the Premium section in [_sections] / [_buildSectionContent].
  /// Hidden from the sidebar when the brand ships all features free.
  static const _premiumSectionIndex = 8;

  int _selectedSectionIndex = 0;
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _searchDelegate = SettingsSearchDelegate();
  String _searchQuery = '';

  static const _sidebarWidth = 244.0;
  static const _contentMaxWidth = 980.0;
  final _sidebarFocusNode = FocusNode();

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _sidebarFocusNode.dispose();
    super.dispose();
  }

  late final _sections = <_SettingsSectionItem>[
    _SettingsSectionItem(
      icon: Icons.tune_rounded,
      labelGetter: () => AppLocalizations.settingsSectionGeneral,
    ),
    _SettingsSectionItem(
      icon: Icons.download_rounded,
      labelGetter: () => AppLocalizations.settingsSectionDownloads,
    ),
    _SettingsSectionItem(
      icon: Icons.high_quality_rounded,
      labelGetter: () => AppLocalizations.settingsSectionQualityFormat,
    ),
    _SettingsSectionItem(
      icon: Icons.movie_filter_rounded,
      labelGetter: () => AppLocalizations.settingsSectionMediaProcessing,
    ),
    _SettingsSectionItem(
      icon: Icons.public_rounded,
      labelGetter: () => AppLocalizations.settingsSectionPlatforms,
    ),
    _SettingsSectionItem(
      icon: Icons.language_rounded,
      labelGetter: () => AppLocalizations.settingsSectionBrowser,
    ),
    _SettingsSectionItem(
      icon: Icons.wifi_rounded,
      labelGetter: () => AppLocalizations.settingsSectionNetworkProxy,
    ),
    _SettingsSectionItem(
      icon: Icons.engineering_rounded,
      labelGetter: () => AppLocalizations.settingsSectionEngineComponents,
    ),
    _SettingsSectionItem(
      icon: Icons.workspace_premium_rounded,
      labelGetter: () => AppLocalizations.premiumTitle,
    ),
    _SettingsSectionItem(
      icon: Icons.info_outline_rounded,
      labelGetter: () => AppLocalizations.settingsSectionAboutSupport,
    ),
  ];

  late final _sectionGroups = <_SettingsSectionGroup>[
    _SettingsSectionGroup(
      labelGetter: () => AppLocalizations.settingsSectionGeneral,
      sectionIndexes: const [0],
    ),
    _SettingsSectionGroup(
      labelGetter: () => AppLocalizations.settingsSectionDownloads,
      sectionIndexes: const [1, 2, 3, 4],
    ),
    _SettingsSectionGroup(
      labelGetter: () => AppLocalizations.settingsSectionNetworkAdvanced,
      sectionIndexes: const [5, 6, 7],
    ),
    _SettingsSectionGroup(
      labelGetter: () => AppLocalizations.settingsAccountTitle,
      sectionIndexes: const [8, 9],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final cs = Theme.of(context).colorScheme;
    final pageBg = isDark ? AppColors.homeDarkAppBg : AppColors.lightBase;
    final sidebarBg =
        isDark ? AppColors.homeDarkCardBg : AppColors.surface1(context);
    final dividerColor =
        isDark
            ? AppColors.homeDarkBorderStrong
            : AppColors.border(context).withValues(alpha: 0.76);
    final textPrimary = cs.onSurface;
    final textSecondary = cs.onSurfaceVariant;
    final searchBg = AppColors.surface2(context);
    final searchBorder = dividerColor;
    final selectedTint = AppColors.accentHighlight.withValues(
      alpha: isDark ? 0.14 : 0.10,
    );
    final cardBorder =
        isDark
            ? AppColors.homeDarkBorderStrong
            : AppColors.border(context).withValues(alpha: 0.72);

    return Scaffold(
      backgroundColor: pageBg,
      body: Row(
        children: [
          SizedBox(
            width: _sidebarWidth,
            child: Container(
              color: sidebarBg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.mdLg,
                      AppSpacing.mdLg,
                      AppSpacing.mdLg,
                      AppSpacing.sm,
                    ),
                    child: Text(
                      AppLocalizations.settingsTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                        color: textPrimary,
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.smMd,
                      0,
                      AppSpacing.smMd,
                      AppSpacing.sm,
                    ),
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: AppLocalizations.settingsSearchHint,
                          hintStyle: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: textSecondary),
                          prefixIcon: Icon(
                            Icons.search,
                            size: 16,
                            color: textSecondary,
                          ),
                          suffixIcon:
                              _searchQuery.isNotEmpty
                                  ? IconButton(
                                    icon: const Icon(Icons.close, size: 14),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                  : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.smMd,
                            vertical: AppSpacing.sm,
                          ),
                          filled: true,
                          fillColor: searchBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            borderSide: BorderSide(
                              color: searchBorder,
                              width: 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            borderSide: BorderSide(
                              color: searchBorder,
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            borderSide: BorderSide(
                              color: AppColors.accentHighlight,
                              width: 1,
                            ),
                          ),
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: textPrimary,
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                            _searchDelegate.invalidateCache();
                          });
                        },
                      ),
                    ),
                  ),

                  Expanded(
                    child:
                        _searchQuery.isNotEmpty
                            ? _buildSearchResults(
                              isDark,
                              textPrimary,
                              textSecondary,
                            )
                            : Focus(
                              focusNode: _sidebarFocusNode,
                              onKeyEvent: (node, event) {
                                if (event is! KeyDownEvent) {
                                  return KeyEventResult.ignored;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowDown) {
                                  _selectSection(
                                    (_selectedSectionIndex + 1).clamp(
                                      0,
                                      _sections.length - 1,
                                    ),
                                  );
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowUp) {
                                  _selectSection(
                                    (_selectedSectionIndex - 1).clamp(
                                      0,
                                      _sections.length - 1,
                                    ),
                                  );
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                              child: ListView(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                ),
                                children: [
                                  for (final group in _sectionGroups) ...[
                                    _SidebarGroupLabel(
                                      label: group.labelGetter(),
                                    ),
                                    for (final index in group.sectionIndexes)
                                      // Free-unlimited build: no Premium section.
                                      if (!(BrandConfig
                                              .current.allFeaturesFree &&
                                          index == _premiumSectionIndex))
                                        _SidebarItem(
                                          icon: _sections[index].icon,
                                          label: _sections[index].labelGetter(),
                                          isSelected:
                                              _selectedSectionIndex == index,
                                          onTap: () => _selectSection(index),
                                        ),
                                    const SizedBox(height: AppSpacing.sm),
                                  ],
                                ],
                              ),
                            ),
                  ),
                ],
              ),
            ),
          ),

          Container(width: 1, color: dividerColor),

          Expanded(
            child: Theme(
              data: Theme.of(context).copyWith(
                scaffoldBackgroundColor: pageBg,
                switchTheme: SwitchThemeData(
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return AppColors.accentHighlight;
                    }
                    return cs.onSurfaceVariant;
                  }),
                  trackColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return AppColors.accentHighlight.withValues(alpha: 0.34);
                    }
                    return AppColors.surface3(context);
                  }),
                  trackOutlineColor: WidgetStateProperty.all(
                    Colors.transparent,
                  ),
                ),
                checkboxTheme: CheckboxThemeData(
                  fillColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return AppColors.accentHighlight;
                    }
                    return Colors.transparent;
                  }),
                  checkColor: WidgetStateProperty.all(Colors.white),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(2),
                  ),
                  side: BorderSide(
                    color: AppColors.border(context),
                    width: 1.5,
                  ),
                ),
                segmentedButtonTheme: SegmentedButtonThemeData(
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return selectedTint;
                      }
                      return AppColors.surface2(context);
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return AppColors.accentHighlight;
                      }
                      return cs.onSurfaceVariant;
                    }),
                    side: WidgetStateProperty.all(
                      BorderSide(color: cardBorder),
                    ),
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                    ),
                    iconColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return AppColors.accentHighlight;
                      }
                      return cs.onSurfaceVariant;
                    }),
                  ),
                ),
                sliderTheme: SliderThemeData(
                  activeTrackColor: AppColors.accentHighlight,
                  inactiveTrackColor: AppColors.surface3(context),
                  thumbColor: AppColors.accentHighlight,
                  overlayColor: AppColors.accentHighlight.withValues(
                    alpha: 0.16,
                  ),
                  trackHeight: 3,
                ),
                chipTheme: ChipThemeData(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  side: BorderSide(color: cardBorder),
                  selectedColor: selectedTint,
                  checkmarkColor: AppColors.accentHighlight,
                ),
                listTileTheme: ListTileThemeData(
                  iconColor: cs.onSurfaceVariant,
                  textColor: textPrimary,
                  tileColor: Colors.transparent,
                ),
                dividerTheme: DividerThemeData(
                  color: dividerColor,
                  thickness: 1,
                ),
                cardTheme: CardThemeData(
                  color: AppColors.surface2(context),
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    side: BorderSide(color: cardBorder, width: 1),
                  ),
                ),
                outlinedButtonTheme: OutlinedButtonThemeData(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: AppColors.accentHighlight.withValues(alpha: 0.64),
                      width: 1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    foregroundColor: AppColors.accentHighlight,
                  ),
                ),
                filledButtonTheme: FilledButtonThemeData(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentHighlight,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                  ),
                ),
                textButtonTheme: TextButtonThemeData(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accentHighlight,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                  ),
                ),
                radioTheme: RadioThemeData(
                  fillColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return AppColors.accentHighlight;
                    }
                    return cs.onSurfaceVariant;
                  }),
                ),
                inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  fillColor: AppColors.surface2(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    borderSide: BorderSide(color: cardBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    borderSide: BorderSide(color: cardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    borderSide: BorderSide(color: AppColors.accentHighlight),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.smMd,
                    vertical: AppSpacing.smMd,
                  ),
                ),
                dropdownMenuTheme: DropdownMenuThemeData(
                  inputDecorationTheme: InputDecorationTheme(
                    filled: true,
                    fillColor: AppColors.surface2(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      borderSide: BorderSide(color: cardBorder),
                    ),
                  ),
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: SingleChildScrollView(
                  key: ValueKey(_selectedSectionIndex),
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.xxl,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _contentMaxWidth,
                      ),
                      child: _buildSectionContent(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _selectSection(int index) {
    if (index == _selectedSectionIndex) return;
    setState(() => _selectedSectionIndex = index);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  Widget _buildSearchResults(
    bool isDark,
    Color textPrimary,
    Color textSecondary,
  ) {
    final results = _searchDelegate.search(_searchQuery);
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 28, color: textSecondary),
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppLocalizations.settingsSearchNoResults,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        return _SearchResultItem(
          result: result,
          query: _searchQuery,
          isSelected: _selectedSectionIndex == result.sectionIndex,
          onTap: () {
            setState(() {
              _selectedSectionIndex = result.sectionIndex;
              _searchQuery = '';
              _searchController.clear();
            });
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(0);
            }
          },
        );
      },
    );
  }

  Widget _buildSectionContent() {
    const sections = <Widget>[
      SettingsGeneralSection(),
      SettingsDownloadsSection(),
      SettingsQualitySection(),
      SettingsMediaSection(),
      SettingsPlatformsSection(),
      SettingsBrowserSection(),
      SettingsNetworkSection(),
      SettingsEngineSection(),
      SettingsPremiumSection(),
      SettingsAboutSection(),
    ];
    if (_selectedSectionIndex < sections.length) {
      return sections[_selectedSectionIndex];
    }
    return const SizedBox.shrink();
  }
}

class _SettingsSectionItem {
  final IconData icon;
  final String Function() labelGetter;

  const _SettingsSectionItem({required this.icon, required this.labelGetter});
}

class _SettingsSectionGroup {
  final String Function() labelGetter;
  final List<int> sectionIndexes;

  const _SettingsSectionGroup({
    required this.labelGetter,
    required this.sectionIndexes,
  });
}

class _SidebarGroupLabel extends StatelessWidget {
  final String label;

  const _SidebarGroupLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.smMd,
        AppSpacing.md,
        AppSpacing.smMd,
        AppSpacing.xs,
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color.withValues(alpha: 0.72),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// =============================================================================
// SIDEBAR ITEM
// =============================================================================

class _SidebarItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cs = Theme.of(context).colorScheme;
    final selectedBg = AppColors.accentHighlight.withValues(
      alpha: isDark ? 0.14 : 0.10,
    );
    final hoverBg = AppColors.surface2(context);
    final selectedBorder = AppColors.accentHighlight.withValues(
      alpha: isDark ? 0.48 : 0.38,
    );
    final selectedTextColor = AppColors.accentHighlight;
    final normalTextColor = cs.onSurfaceVariant;
    final hoverTextColor = cs.onSurface;

    Color bgColor;
    Color textColor;

    if (widget.isSelected) {
      bgColor = selectedBg;
      textColor = selectedTextColor;
    } else if (_isHovered) {
      bgColor = hoverBg;
      textColor = hoverTextColor;
    } else {
      bgColor = Colors.transparent;
      textColor = normalTextColor;
    }

    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _isHovered = false);
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(AppRadius.card),
          splashColor: AppColors.accentHighlight.withValues(
            alpha: AppOpacity.pressed,
          ),
          highlightColor: AppColors.accentHighlight.withValues(
            alpha: AppOpacity.hover,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.smMd,
              vertical: AppSpacing.smMd,
            ),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: widget.isSelected ? selectedBorder : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 18, color: textColor),
                const SizedBox(width: AppSpacing.smMd),
                Expanded(
                  child: Text(
                    widget.label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: textColor,
                      fontWeight:
                          widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// SEARCH RESULT ITEM
// =============================================================================

class _SearchResultItem extends StatefulWidget {
  final SettingsSearchResult result;
  final String query;
  final bool isSelected;
  final VoidCallback onTap;

  const _SearchResultItem({
    required this.result,
    required this.query,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SearchResultItem> createState() => _SearchResultItemState();
}

class _SearchResultItemState extends State<_SearchResultItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final textPrimary = cs.onSurface;
    final textSecondary = cs.onSurfaceVariant;

    final selectedBg = AppColors.accentHighlight.withValues(
      alpha: isDark ? 0.14 : 0.10,
    );
    final hoverBg = AppColors.surface2(context);
    final selectedBorder = AppColors.accentHighlight.withValues(
      alpha: isDark ? 0.48 : 0.38,
    );

    Color bgColor;
    if (widget.isSelected) {
      bgColor = selectedBg;
    } else if (_isHovered) {
      bgColor = hoverBg;
    } else {
      bgColor = Colors.transparent;
    }

    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _isHovered = false);
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(AppRadius.card),
          splashColor: AppColors.accentHighlight.withValues(
            alpha: AppOpacity.pressed,
          ),
          highlightColor: AppColors.accentHighlight.withValues(
            alpha: AppOpacity.hover,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.smMd,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: widget.isSelected ? selectedBorder : Colors.transparent,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HighlightedText(
                  text: widget.result.settingLabel,
                  query: widget.query,
                  style:
                      Theme.of(
                        context,
                      ).textTheme.labelMedium?.copyWith(color: textPrimary) ??
                      const TextStyle(),
                  highlightColor: AppColors.accentHighlight.withAlpha(50),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Row(
                  children: [
                    Icon(
                      widget.result.sectionIcon,
                      size: 12,
                      color: textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        widget.result.sectionLabel,
                        style: AppTypography.mini.copyWith(
                          color: textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Highlights matching substring in text.
class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle style;
  final Color highlightColor;

  const _HighlightedText({
    required this.text,
    required this.query,
    required this.style,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase().trim();
    final matchIndex = lowerText.indexOf(lowerQuery);

    if (matchIndex < 0) {
      return Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          if (matchIndex > 0)
            TextSpan(text: text.substring(0, matchIndex), style: style),
          TextSpan(
            text: text.substring(matchIndex, matchIndex + lowerQuery.length),
            style: style.copyWith(
              backgroundColor: highlightColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (matchIndex + lowerQuery.length < text.length)
            TextSpan(
              text: text.substring(matchIndex + lowerQuery.length),
              style: style,
            ),
        ],
      ),
    );
  }
}
