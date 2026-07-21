import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/brand_config.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/user_playlist_summary.dart';
import '../providers/download_providers.dart';
import '../providers/user_playlists_provider.dart';

/// Picker for "Add to playlist" — shows existing user-curated
/// playlists and a "Create new" inline input. Existing playlists are
/// backed by the C-lite membership table, so adding a download here
/// does not overwrite source playlist metadata such as `yt_*`.
///
/// We deliberately exclude `yt_*` source-grouped playlists from the
/// picker — those collections own their identity through the
/// upstream YouTube playlist and aren't user-editable here.
class AddToPlaylistDialog extends ConsumerStatefulWidget {
  /// IDs of downloads to add. Empty list short-circuits to no-op.
  final List<int> downloadIds;

  const AddToPlaylistDialog({super.key, required this.downloadIds});

  /// Returns the destination playlist's display title on success
  /// (so callers can show "Added N to [name]"). Returns `null` on
  /// cancel — callers MUST treat null as "no toast".
  static Future<String?> show(
    BuildContext context, {
    required List<int> downloadIds,
  }) {
    if (downloadIds.isEmpty) return Future.value(null);
    return showDialog<String>(
      context: context,
      builder: (_) => AddToPlaylistDialog(downloadIds: downloadIds),
    );
  }

  @override
  ConsumerState<AddToPlaylistDialog> createState() =>
      _AddToPlaylistDialogState();
}

class _AddToPlaylistDialogState extends ConsumerState<AddToPlaylistDialog> {
  final _newTitleController = TextEditingController();
  final _newTitleFocus = FocusNode();
  bool _busy = false;
  String? _errorText;

  @override
  void dispose() {
    _newTitleController.dispose();
    _newTitleFocus.dispose();
    super.dispose();
  }

  Future<void> _addToExisting(UserPlaylistSummary p) async {
    if (_busy) return;
    setState(() => _busy = true);
    final repo = ref.read(downloadRepositoryProvider);
    final result = await repo.addToUserPlaylist(
      downloadIds: widget.downloadIds,
      playlistId: p.playlistId,
    );
    if (!mounted) return;
    result.when(
      success: (info) {
        // user_playlist_items watch stream propagates the change
        // into all live consumers. Force-invalidate the summary
        // FutureProvider so the next dialog open re-queries counts.
        ref.invalidate(userPlaylistsProvider);
        Navigator.of(context).pop(info.title);
      },
      failure: (e) {
        setState(() {
          _busy = false;
          _errorText = AppExceptionX.readableMessage(e);
        });
      },
    );
  }

  Future<void> _createNew() async {
    if (_busy) return;
    final title = _newTitleController.text.trim();
    if (title.isEmpty) {
      setState(
        () => _errorText = AppLocalizations.playlistAddDialogNameRequired,
      );
      _newTitleFocus.requestFocus();
      return;
    }
    setState(() {
      _busy = true;
      _errorText = null;
    });
    final repo = ref.read(downloadRepositoryProvider);
    final result = await repo.addToUserPlaylist(
      downloadIds: widget.downloadIds,
      newPlaylistTitle: title,
    );
    if (!mounted) return;
    result.when(
      success: (info) {
        ref.invalidate(userPlaylistsProvider);
        Navigator.of(context).pop(info.title);
      },
      failure: (e) {
        setState(() {
          _busy = false;
          _errorText = AppExceptionX.readableMessage(e);
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final playlistsAsync = ref.watch(userPlaylistsProvider);
    final cs = theme.colorScheme;
    final surface =
        isDark ? AppColors.homeDarkCardBg : AppColors.surface1(context);
    final elevatedSurface =
        isDark ? AppColors.homeDarkCardHover : AppColors.lightSurfaceLowest;
    final radius = BrandConfig.current.cardRadius;
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderStrong.withValues(alpha: 0.86)
            : AppColors.border(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape):
            () => Navigator.of(context).pop(),
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xl,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 500,
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: isDark ? AppOpacity.overlay : AppOpacity.hover,
                  ),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                  spreadRadius: -14,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.mdLg,
                      AppSpacing.md,
                      AppSpacing.md,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color:
                                isDark
                                    ? AppColors.homeDarkAccentSoft
                                    : AppColors.accentHighlight.withValues(
                                      alpha: AppOpacity.hover,
                                    ),
                            border: Border.all(color: borderColor),
                            borderRadius: BorderRadius.circular(radius),
                          ),
                          child: Icon(
                            Icons.playlist_add_rounded,
                            size: 20,
                            color: AppColors.accentHighlight,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.smMd),
                        Expanded(
                          child: Text(
                            AppLocalizations.playlistAddDialogTitle(
                              widget.downloadIds.length,
                            ),
                            style: AppTypography.appBarTitle.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color:
                                  isDark
                                      ? AppColors.darkLightText
                                      : cs.onSurface,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed:
                              _busy ? null : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          tooltip: AppLocalizations.commonCancel,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: borderColor),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.lg,
                          AppSpacing.lg,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 260),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: elevatedSurface,
                                  borderRadius: BorderRadius.circular(radius),
                                  border: Border.all(color: borderColor),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(radius),
                                  child: playlistsAsync.when(
                                    loading:
                                        () => const SizedBox(
                                          height: 96,
                                          child: Center(
                                            child: SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          ),
                                        ),
                                    error:
                                        (e, _) => _PlaylistDialogMessage(
                                          icon: Icons.error_outline_rounded,
                                          message:
                                              AppLocalizations.playlistAddDialogLoadError(
                                                AppExceptionX.readableMessage(
                                                  e,
                                                ),
                                              ),
                                          isDark: isDark,
                                          color: cs.error,
                                        ),
                                    data: (playlists) {
                                      if (playlists.isEmpty) {
                                        return _PlaylistDialogMessage(
                                          icon: Icons.playlist_play_rounded,
                                          message:
                                              AppLocalizations
                                                  .playlistAddDialogEmpty,
                                          isDark: isDark,
                                          color: AppColors.accentHighlight,
                                        );
                                      }
                                      return ListView.separated(
                                        shrinkWrap: true,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: AppSpacing.xs,
                                        ),
                                        itemCount: playlists.length,
                                        separatorBuilder:
                                            (_, __) => Divider(
                                              height: 1,
                                              indent: 52,
                                              color:
                                                  isDark
                                                      ? AppColors
                                                          .homeDarkBorderSubtle
                                                      : borderColor,
                                            ),
                                        itemBuilder:
                                            (_, i) => _PlaylistRow(
                                              playlist: playlists[i],
                                              enabled: !_busy,
                                              onTap:
                                                  () => _addToExisting(
                                                    playlists[i],
                                                  ),
                                            ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              AppLocalizations.playlistAddDialogCreateNew,
                              style: AppTypography.metadata.copyWith(
                                color:
                                    isDark
                                        ? AppColors.darkMetaText
                                        : cs.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            TextField(
                              controller: _newTitleController,
                              focusNode: _newTitleFocus,
                              enabled: !_busy,
                              autofocus: true,
                              onSubmitted: (_) => _createNew(),
                              decoration: InputDecoration(
                                hintText:
                                    AppLocalizations.playlistAddDialogNameHint,
                                filled: true,
                                fillColor:
                                    isDark
                                        ? AppColors.homeDarkCardBg
                                        : Colors.white,
                                prefixIcon: Icon(
                                  Icons.edit_rounded,
                                  size: 17,
                                  color:
                                      isDark
                                          ? AppColors.homeDarkTextSecondary
                                          : cs.onSurfaceVariant,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(radius),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(radius),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(radius),
                                  borderSide: BorderSide(
                                    color: AppColors.accentHighlight,
                                    width: 1.2,
                                  ),
                                ),
                                errorText: _errorText,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.smMd,
                                  vertical: AppSpacing.sm,
                                ),
                              ),
                              onChanged: (_) {
                                if (_errorText != null) {
                                  setState(() => _errorText = null);
                                }
                              },
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed:
                                      _busy
                                          ? null
                                          : () => Navigator.of(context).pop(),
                                  child: Text(AppLocalizations.commonCancel),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                FilledButton.icon(
                                  onPressed: _busy ? null : _createNew,
                                  icon:
                                      _busy
                                          ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                          : const Icon(Icons.add, size: 18),
                                  label: Text(
                                    AppLocalizations
                                        .playlistAddDialogCreateButton,
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.accentHighlight,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(112, 38),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        BrandConfig.current.buttonRadius,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistDialogMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool isDark;
  final Color color;

  const _PlaylistDialogMessage({
    required this.icon,
    required this.message,
    required this.isDark,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BrandConfig.current.cardRadius;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: AppOpacity.hover),
              borderRadius: BorderRadius.circular(radius),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: AppSpacing.smMd),
          Expanded(
            child: Text(
              message,
              style: AppTypography.metadata.copyWith(
                color:
                    isDark
                        ? AppColors.darkMetaText
                        : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  final UserPlaylistSummary playlist;
  final bool enabled;
  final VoidCallback onTap;

  const _PlaylistRow({
    required this.playlist,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final metaColor =
        isDark ? AppColors.homeDarkTextSecondary : cs.onSurfaceVariant;
    final titleColor = isDark ? AppColors.darkLightText : cs.onSurface;
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderStrong.withValues(alpha: 0.72)
            : cs.outlineVariant.withValues(alpha: 0.72);
    final radius = BrandConfig.current.cardRadius;

    return Opacity(
      opacity: enabled ? 1 : AppOpacity.medium,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(radius),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.smMd,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color:
                        isDark
                            ? AppColors.homeDarkAccentSoft
                            : AppColors.accentHighlight.withValues(
                              alpha: AppOpacity.hover,
                            ),
                    border: Border.all(color: borderColor),
                    borderRadius: BorderRadius.circular(radius),
                  ),
                  child: Icon(
                    Icons.playlist_play_rounded,
                    size: 18,
                    color: AppColors.accentHighlight,
                  ),
                ),
                const SizedBox(width: AppSpacing.smMd),
                Expanded(
                  child: Text(
                    playlist.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.buttonSecondary.copyWith(
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  constraints: const BoxConstraints(minWidth: 28),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isDark
                            ? AppColors.homeDarkCardBg
                            : cs.surfaceContainerHighest.withValues(
                              alpha: AppOpacity.secondary,
                            ),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(color: borderColor),
                  ),
                  child: Text(
                    '${playlist.count}',
                    textAlign: TextAlign.center,
                    style: AppTypography.mini.copyWith(
                      color: metaColor,
                      fontWeight: FontWeight.w700,
                    ),
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
