import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../../../../core/core.dart';
import '../../../../core/navigation/right_panel_provider.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/domain/entities/video_info.dart' show ChapterInfo;
import '../../../player/domain/services/playback_queue_service.dart'
    show QueueRepeatMode;
import '../../../player/domain/services/player_chapter_service.dart';
import '../../../player/presentation/providers/playback_queue_providers.dart';
import '../../../player/presentation/providers/player_providers.dart';

/// Right-panel tab strip rendered below the embedded player, after
/// the filename row. Wires three persistent surfaces — Playlist,
/// Subtitles & Audio, Chapters — into the previously-empty 220px
/// vertical zone the V2 home redesign left blank below the controls.
///
/// All three tabs read from already-existing services / providers
/// (no new state machinery): playback queue from
/// [playbackQueueProvider], subtitle + audio tracks from media_kit's
/// `Player.stream.tracks`, chapter list from
/// [DownloadEntity.chapters]. The tab strip is responsible for
/// picking a sensible default tab on first render so users never
/// land on an empty surface when a richer one is available.
class RightPanelTabs extends ConsumerStatefulWidget {
  final DownloadEntity download;

  /// Live media_kit Player from the parent [_PlayerEmbedBodyState].
  /// Null while the player is initialising, after dispose, or for
  /// pure-image previews — every tab gracefully degrades to an empty
  /// state rather than crashing on null access.
  final Player? player;

  final Duration position;

  /// Hop back into the parent's `_seek()` method instead of calling
  /// `player.seek` directly, so the parent's safety wrappers
  /// (`PlayerSafety.safeCall`) and prefs persistence stay in one place.
  final void Function(Duration) onSeek;

  const RightPanelTabs({
    super.key,
    required this.download,
    required this.player,
    required this.position,
    required this.onSeek,
  });

  @override
  ConsumerState<RightPanelTabs> createState() => _RightPanelTabsState();
}

class _RightPanelTabsState extends ConsumerState<RightPanelTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;

  static const int _kPlaylistTab = 0;
  static const int _kSubAudioTab = 1;
  static const int _kChaptersTab = 2;

  /// Pick the most informative tab to show first. Order of precedence:
  /// chapters (most specific to the current video) → playlist (queue
  /// of multiple items) → subtitles & audio (always present). Picking
  /// "always present" first would mean a chapter-rich video opens on
  /// a blank-ish track list, which is the opposite of what the user
  /// wants.
  int _pickDefaultTab() {
    if (widget.download.hasChapters) return _kChaptersTab;
    final queueLength = ref.read(playbackQueueProvider).length;
    if (queueLength > 1) return _kPlaylistTab;
    return _kSubAudioTab;
  }

  @override
  void initState() {
    super.initState();
    _controller = TabController(
      length: 3,
      vsync: this,
      initialIndex: _pickDefaultTab(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tab labels — compact, lowercase weight to fit 340px sidebar.
        TabBar(
          controller: _controller,
          isScrollable: false,
          labelColor: AppColors.accentHighlight,
          unselectedLabelColor: AppColors.metaText(context),
          indicatorColor: AppColors.accentHighlight,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: AppTypography.metadata.copyWith(
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: AppTypography.metadata,
          tabs: [
            Tab(text: AppLocalizations.rightPanelTabsPlaylist, height: 36),
            Tab(text: AppLocalizations.rightPanelTabsSubsAudio, height: 36),
            Tab(text: AppLocalizations.rightPanelTabsChapters, height: 36),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        // Bounded vertical space — sidebar already lives inside a
        // SingleChildScrollView so the user scrolls when content
        // exceeds this floor. 240px fits ~6 list rows comfortably.
        SizedBox(
          height: 240,
          child: TabBarView(
            controller: _controller,
            children: [
              _PlaylistTab(currentDownloadId: widget.download.id),
              _SubAudioTab(player: widget.player),
              _ChaptersTab(
                chapters: widget.download.chapters,
                position: widget.position,
                onSeek: widget.onSeek,
              ),
            ],
          ),
        ),
        // Subtle divider so the tab block reads as a distinct
        // section rather than bleeding into whatever future content
        // lands below it.
        Divider(
          height: AppSpacing.lg,
          color: cs.outline.withValues(alpha: 0.15),
        ),
      ],
    );
  }
}

// ─── Playlist tab ───────────────────────────────────────────────────────────

class _PlaylistTab extends ConsumerWidget {
  final int currentDownloadId;

  const _PlaylistTab({required this.currentDownloadId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(playbackQueueProvider);
    if (queue.items.isEmpty) {
      return _TabEmpty(
        icon: Icons.queue_music_rounded,
        message: AppLocalizations.rightPanelPlaylistEmpty,
      );
    }
    final notifier = ref.read(playbackQueueProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Shuffle + repeat row — reuse the same icons VideoPlayerScreen
        // already exposes so the mental model is consistent across
        // sidebar and fullscreen player.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              _QueueControlButton(
                icon: Icons.shuffle_rounded,
                active: queue.shuffleEnabled,
                tooltip: AppLocalizations.rightPanelPlaylistShuffle,
                onPressed: notifier.toggleShuffle,
              ),
              const SizedBox(width: AppSpacing.xs),
              _QueueControlButton(
                icon: switch (queue.repeatMode) {
                  QueueRepeatMode.off => Icons.repeat_rounded,
                  QueueRepeatMode.repeatAll => Icons.repeat_on_rounded,
                  QueueRepeatMode.repeatOne => Icons.repeat_one_rounded,
                },
                active: queue.repeatMode != QueueRepeatMode.off,
                tooltip: AppLocalizations.rightPanelPlaylistRepeat,
                onPressed: notifier.cycleRepeatMode,
              ),
              const Spacer(),
              _QueueCountPill(
                label: AppLocalizations.rightPanelPlaylistItemCount(
                  queue.length,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: queue.items.length,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              0,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            itemBuilder: (context, index) {
              final item = queue.items[index];
              final isCurrent = item.id == currentDownloadId;
              return _QueueItemTile(
                item: item,
                index: index,
                isCurrent: isCurrent,
                onTap:
                    isCurrent
                        ? null
                        : () {
                          notifier.jumpTo(index);
                          ref
                              .read(rightPanelProvider.notifier)
                              .showDetail(item);
                        },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _QueueControlButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onPressed;

  const _QueueControlButton({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color =
        active ? AppColors.accentHighlight : AppColors.metaText(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: AnimatedContainer(
          duration: AppTransitions.controls,
          width: 34,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                active
                    ? AppColors.accentHighlight.withValues(
                      alpha: isDark ? 0.18 : 0.08,
                    )
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color:
                  active
                      ? AppColors.accentHighlight.withValues(alpha: 0.28)
                      : AppColors.metaText(context).withValues(alpha: 0.12),
              width: 0.8,
            ),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }
}

class _QueueCountPill extends StatelessWidget {
  final String label;

  const _QueueCountPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = AppColors.metaText(context);
    return Container(
      height: 28,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color:
            isDark
                ? AppColors.homeDarkCardBg
                : Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: color.withValues(alpha: 0.14), width: 0.8),
      ),
      child: Text(
        label,
        style: AppTypography.compact.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _QueueItemTile extends StatelessWidget {
  final DownloadEntity item;
  final int index;
  final bool isCurrent;
  final VoidCallback? onTap;

  const _QueueItemTile({
    required this.item,
    required this.index,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final accent = AppColors.accentHighlight;
    final metaColor = AppColors.metaText(context);
    final surface =
        isCurrent
            ? accent.withValues(alpha: isDark ? 0.16 : 0.075)
            : Colors.transparent;
    final borderColor =
        isCurrent
            ? accent.withValues(alpha: isDark ? 0.34 : 0.22)
            : (isDark
                ? AppColors.homeDarkBorderSubtle.withValues(alpha: 0.74)
                : cs.outlineVariant.withValues(alpha: 0.62));

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: AnimatedContainer(
            duration: AppTransitions.controls,
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: borderColor, width: 0.8),
            ),
            child: Row(
              children: [
                _QueueThumbnail(item: item, isCurrent: isCurrent),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.fileName.copyWith(
                          color:
                              isDark ? AppColors.darkLightText : cs.onSurface,
                          fontWeight:
                              isCurrent ? FontWeight.w800 : FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _queueMeta(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.mini.copyWith(
                          color: metaColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        isCurrent
                            ? accent.withValues(alpha: isDark ? 0.22 : 0.12)
                            : metaColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child:
                      isCurrent
                          ? Icon(
                            Icons.play_arrow_rounded,
                            size: 16,
                            color: accent,
                          )
                          : Text(
                            '${index + 1}',
                            style: AppTypography.mini.copyWith(
                              color: metaColor,
                              fontWeight: FontWeight.w800,
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

  String _queueMeta(DownloadEntity item) {
    final parts = <String>[
      if ((item.uploader ?? '').trim().isNotEmpty) item.uploader!.trim(),
      if (item.qualityLabel != null && item.qualityLabel!.trim().isNotEmpty)
        item.qualityLabel!.trim(),
      if (item.fileExtension.isNotEmpty)
        item.fileExtension.replaceAll('.', '').toUpperCase(),
    ];
    return parts.isEmpty ? item.status.displayLabel : parts.join(' · ');
  }
}

class _QueueThumbnail extends StatelessWidget {
  final DownloadEntity item;
  final bool isCurrent;

  const _QueueThumbnail({required this.item, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentHighlight;
    final thumbnail = item.thumbnail?.trim();
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child:
              thumbnail == null || thumbnail.isEmpty
                  ? Container(
                    width: 54,
                    height: 40,
                    alignment: Alignment.center,
                    color: accent.withValues(alpha: 0.10),
                    child: Icon(
                      Icons.playlist_play_rounded,
                      size: 18,
                      color: accent,
                    ),
                  )
                  : AppCachedImage(
                    imageUrl: thumbnail,
                    width: 54,
                    height: 40,
                    fit: BoxFit.cover,
                    errorWidget: Container(
                      width: 54,
                      height: 40,
                      alignment: Alignment.center,
                      color: accent.withValues(alpha: 0.10),
                      child: Icon(
                        Icons.playlist_play_rounded,
                        size: 18,
                        color: accent,
                      ),
                    ),
                  ),
        ),
        if (isCurrent)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: accent, width: 1.4),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Subs & Audio tab ───────────────────────────────────────────────────────

/// Pure helper — the audio track at [index] is selected when its id
/// matches [currentTrack.id]. Lifted out of the widget so the
/// selection contract can be unit-tested without spinning a Player.
/// The previous `tracks.audio.any(...)` form was a tautology
/// (comparing a list-derived item against the same list) and Codex
/// caught it — every tile was reporting selected.
@visibleForTesting
bool isAudioTrackSelected(AudioTrack track, AudioTrack currentTrack) {
  // Defensive: `AudioTrack.no()` has id `'no'`; treat any current
  // sentinel as "nothing selected" so tiles render unselected
  // instead of accidentally matching on the sentinel.
  if (currentTrack.id == 'no' || currentTrack.id == 'auto') return false;
  return track.id == currentTrack.id;
}

@visibleForTesting
bool isSubtitleTrackSelected(SubtitleTrack track, SubtitleTrack currentTrack) {
  if (currentTrack.id == 'no' || currentTrack.id == 'auto') return false;
  return track.id == currentTrack.id;
}

class _SubAudioTab extends ConsumerWidget {
  final Player? player;

  const _SubAudioTab({required this.player});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = player;
    if (p == null) {
      return _TabEmpty(
        icon: Icons.subtitles_off_rounded,
        message: AppLocalizations.rightPanelSubsAudioNotReady,
      );
    }
    // Source of truth for the currently-selected tracks lives in the
    // shared providers wired by the fullscreen player + side panel
    // (player_providers.dart). Watching them here means selecting a
    // track from any surface (fullscreen overflow, side-panel tab,
    // future contexts) keeps every UI in sync, instead of each
    // duplicating its own current-track flag.
    final currentSubtitle = ref.watch(currentSubtitleTrackProvider);
    final currentAudio = ref.watch(currentAudioTrackProvider);

    return StreamBuilder<Tracks>(
      stream: p.stream.tracks,
      initialData: p.state.tracks,
      builder: (context, snapshot) {
        final tracks = snapshot.data ?? p.state.tracks;
        final embeddedSubs =
            tracks.subtitle
                .where((t) => t.id != 'auto' && t.id != 'no')
                .toList();
        final audioTracks =
            tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();

        if (embeddedSubs.isEmpty && audioTracks.isEmpty) {
          return _TabEmpty(
            icon: Icons.subtitles_off_rounded,
            message: AppLocalizations.rightPanelSubsAudioEmpty,
          );
        }

        final subtitleIsOff = currentSubtitle.id == 'no';

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          children: [
            if (audioTracks.isNotEmpty)
              _TabSectionHeader(
                label: AppLocalizations.rightPanelSubsAudioAudioHeader(
                  audioTracks.length,
                ),
              ),
            for (var i = 0; i < audioTracks.length; i++)
              _TrackTile(
                label: _audioTrackLabel(audioTracks[i], i),
                selected: isAudioTrackSelected(audioTracks[i], currentAudio),
                onTap: () {
                  p.setAudioTrack(audioTracks[i]);
                  ref.read(currentAudioTrackProvider.notifier).state =
                      audioTracks[i];
                },
              ),
            if (embeddedSubs.isNotEmpty)
              _TabSectionHeader(
                label: AppLocalizations.rightPanelSubsAudioSubtitlesHeader(
                  embeddedSubs.length,
                ),
              ),
            for (final s in embeddedSubs)
              _TrackTile(
                label: s.title ?? s.language ?? 'Track ${s.id}',
                selected: isSubtitleTrackSelected(s, currentSubtitle),
                onTap: () {
                  p.setSubtitleTrack(s);
                  ref.read(currentSubtitleTrackProvider.notifier).state = s;
                },
              ),
            if (embeddedSubs.isNotEmpty)
              _TrackTile(
                label: AppLocalizations.rightPanelSubsAudioOff,
                selected: subtitleIsOff,
                onTap: () {
                  final off = SubtitleTrack.no();
                  p.setSubtitleTrack(off);
                  ref.read(currentSubtitleTrackProvider.notifier).state = off;
                },
              ),
          ],
        );
      },
    );
  }

  String _audioTrackLabel(AudioTrack track, int index) {
    final lang = track.language;
    if (lang != null && lang.isNotEmpty) return lang;
    final title = track.title;
    if (title != null && title.isNotEmpty) return title;
    return AppLocalizations.rightPanelSubsAudioTrackFallback(index + 1);
  }
}

// ─── Chapters tab ───────────────────────────────────────────────────────────

class _ChaptersTab extends StatelessWidget {
  final List<ChapterInfo> chapters;
  final Duration position;
  final void Function(Duration) onSeek;

  const _ChaptersTab({
    required this.chapters,
    required this.position,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    if (chapters.isEmpty) {
      return _TabEmpty(
        icon: Icons.bookmark_outline_rounded,
        message: AppLocalizations.rightPanelChaptersEmpty,
      );
    }
    final positionSeconds = position.inMilliseconds / 1000.0;
    final current = PlayerChapterService.getCurrentChapter(
      chapters,
      positionSeconds,
    );
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      itemCount: chapters.length,
      itemBuilder: (context, index) {
        final c = chapters[index];
        final isCurrent = current != null && current == c;
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Text(
            _formatTimestamp(c.startTime),
            style: AppTypography.metadata.copyWith(
              color:
                  isCurrent
                      ? AppColors.accentHighlight
                      : AppColors.metaText(context),
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          title: Text(
            c.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.fileName.copyWith(
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          onTap:
              () =>
                  onSeek(Duration(milliseconds: (c.startTime * 1000).round())),
        );
      },
    );
  }

  /// Format chapter start time as `mm:ss` or `hh:mm:ss` for ≥1h
  /// chapters. Mirrors the timestamp shape the scrubber labels use
  /// so users compare rows easily.
  static String _formatTimestamp(double seconds) {
    final total = seconds.round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:$mm:$ss';
    return '$m:$ss';
  }
}

// ─── Shared tab helpers ─────────────────────────────────────────────────────

class _TabEmpty extends StatelessWidget {
  final IconData icon;
  final String message;

  const _TabEmpty({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.metaText(context), size: 32),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.metadata.copyWith(
                color: AppColors.metaText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabSectionHeader extends StatelessWidget {
  final String label;

  const _TabSectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.metadata.copyWith(
          color: AppColors.metaText(context),
          letterSpacing: 0.6,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TrackTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(
        selected ? Icons.check_rounded : null,
        color: AppColors.accentHighlight,
        size: 18,
      ),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.fileName.copyWith(
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      onTap: onTap,
    );
  }
}
