/// Right-sidebar item view — state-aware download surface.
///
/// Replaces the legacy detail panel (which duplicated metadata already
/// visible in the list row + cloned action buttons). When the user
/// taps a download row in Box 3, this widget routes by
/// [DownloadEntity.status] to a body that's actually useful at that
/// moment:
///
///   - `pending` / `queued`     → waiting card with cancel + priority CTA
///   - `downloading`            → live progress + pause / cancel
///   - `paused`                 → progress paused + resume / cancel
///   - `completed` (file ok)    → embedded player (video / audio / image)
///   - `completed` (file gone)  → re-download CTA
///   - `failed`                 → error message + retry / report
///   - `cancelled`              → re-add to queue CTA
///
/// Visual is stock Material (cards, buttons, list tiles) — UI agent
/// (GPT 5.5) polishes after. The state machine + player resource
/// lifecycle are owned by this file.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../../../../core/core.dart';
import '../../../../core/navigation/right_panel_provider.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/domain/entities/download_error_code.dart';
import '../../../downloads/domain/entities/download_status.dart';
import '../../../downloads/presentation/providers/downloads_notifier.dart';
import '../../../player/domain/entities/player_handoff_result.dart';
import '../../../player/domain/services/player_hardware_decode_service.dart';
import '../../../player/domain/services/player_prefs_service.dart';
import '../../../player/domain/services/player_safety.dart';
import '../../../player/domain/services/watch_progress_service.dart';
import '../../../player/presentation/providers/playback_queue_providers.dart';
import '../../../player/presentation/providers/player_hardware_decode_provider.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../../player/presentation/screens/audio_player_screen.dart';
import '../../../player/presentation/screens/image_viewer_screen.dart';
import '../../../player/presentation/screens/video_player_screen.dart';
import 'download_list_helpers.dart';
import 'right_panel_tabs.dart';

// ═════════════════════════════════════════════════════════════════════
// Public entry — state-aware item view
// ═════════════════════════════════════════════════════════════════════

class RightPanelItemView extends ConsumerWidget {
  final DownloadEntity download;
  const RightPanelItemView({super.key, required this.download});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // CRITICAL: resolve the LIVE download by id from the notifier.
    // `rightPanelProvider.selectedDownload` is a snapshot captured
    // at click time — without this lookup the sidebar would show a
    // stale status card forever (user pauses from the list row,
    // sidebar still says "Đang tải" until they click another item).
    // Pre-V2 right sidebar had this exact bug; the redesign must
    // not regress it.
    final downloadsState = ref.watch(downloadsNotifierProvider);
    final live = downloadsState.downloads.firstWhere(
      (d) => d.id == download.id,
      // Fallback to the click-time snapshot if the download was
      // deleted while the panel showed it — caller's switch will
      // most likely route to a CTA that no longer applies, but
      // crashing on missing element is worse than stale UI.
      orElse: () => download,
    );
    final isFileMissing = downloadsState.isFileMissing(live.id);

    return Column(
      children: [
        _ItemHeader(download: live),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            child: _routeBody(context, ref, live, isFileMissing),
          ),
        ),
      ],
    );
  }

  /// Status → body widget. The completed branch splits on file
  /// existence because a "completed" record whose file the user
  /// deleted on disk needs the missing-file CTA, not the player.
  Widget _routeBody(
    BuildContext context,
    WidgetRef ref,
    DownloadEntity download,
    bool isFileMissing,
  ) {
    if (download.isCompleted) {
      if (isFileMissing) {
        return _MissingFileBody(download: download);
      }
      return _PlayerEmbedBody(
        // Key by id so swapping selected items disposes the old Player
        // before constructing the new — prevents media_kit instance
        // leaks when the user clicks through the list quickly.
        key: ValueKey('player_${download.id}'),
        download: download,
      );
    }

    return switch (download.status) {
      DownloadStatus.pending ||
      DownloadStatus.queued => _QueuedBody(download: download),
      DownloadStatus.downloading ||
      // postProcessing = bytes done, yt-dlp/ffmpeg merging or
      // converting. From the user's point of view it's still
      // "downloading" — same UX (progress, no actions to take).
      // RC10.3: same body for merging/remuxing/converting sub-states.
      DownloadStatus.postProcessing ||
      DownloadStatus.merging ||
      DownloadStatus.remuxing ||
      DownloadStatus.converting => _DownloadingBody(download: download),
      DownloadStatus.paused => _PausedBody(download: download),
      DownloadStatus.failed => _FailedBody(download: download),
      DownloadStatus.cancelled => _CancelledBody(download: download),
      // waitingForNetwork = paused-by-OS until network restored. Not
      // terminal, will auto-resume. Surface as a "waiting" card so the
      // user knows nothing is broken.
      DownloadStatus.waitingForNetwork => _WaitingForNetworkBody(
        download: download,
      ),
      DownloadStatus.completed =>
        // Unreachable — handled above. Defensive empty so the switch
        // is exhaustive.
        const SizedBox.shrink(),
    };
  }
}

// ═════════════════════════════════════════════════════════════════════
// Multi-select preview — surfaces batch summary when ≥2 items selected
// ═════════════════════════════════════════════════════════════════════

/// Right-sidebar surface when the user has multi-selected (≥2 items).
///
/// Shows selection count, status mix breakdown (X downloading, Y
/// completed, Z failed), and a thumbnail strip of the first six
/// selected items. Batch actions live in the existing
/// `BatchOperationsBar` mounted above the list — no need to duplicate
/// retry/delete CTAs here. The sidebar's job during multi-select is
/// orientation: "yes I see what you picked, here's the shape of it".
class RightPanelMultiSelectView extends ConsumerWidget {
  final Set<int> selectedIds;
  const RightPanelMultiSelectView({super.key, required this.selectedIds});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final all = ref.watch(downloadsNotifierProvider).downloads;
    final selected = all.where((d) => selectedIds.contains(d.id)).toList();
    if (selected.isEmpty) return const SizedBox.shrink();

    // Status mix — counts per status the user actually has selected.
    final mix = <DownloadStatus, int>{};
    for (final d in selected) {
      mix[d.status] = (mix[d.status] ?? 0) + 1;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color:
                    isDark
                        ? AppColors.homeDarkCardBg
                        : cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color:
                      isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 22,
                        color: AppColors.brand,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          AppLocalizations.batchOpsSelected(selected.length),
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color:
                                isDark ? AppColors.darkLightText : cs.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (mix.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final entry in mix.entries)
                          _StatusPill(status: entry.key, count: entry.value),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Thumbnail strip — first 6 items. Cap so 50-item batch
            // doesn't blow the sidebar height.
            _MultiSelectThumbnails(
              downloads: selected.take(6).toList(),
              moreCount: selected.length - 6,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final DownloadStatus status;
  final int count;
  const _StatusPill({required this.status, required this.count});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    Color tint;
    switch (status) {
      case DownloadStatus.completed:
        tint = AppColors.statusCompleted(context);
      case DownloadStatus.downloading ||
            DownloadStatus.postProcessing ||
            // RC10.3: new sub-states share active tint.
            DownloadStatus.merging ||
            DownloadStatus.remuxing ||
            DownloadStatus.converting:
        tint = AppColors.statusActive(context);
      case DownloadStatus.paused:
        tint = AppColors.statusPaused(context);
      case DownloadStatus.queued || DownloadStatus.pending:
        tint = AppColors.statusPending(context);
      case DownloadStatus.failed:
        tint = AppColors.statusFailed(context);
      case DownloadStatus.cancelled:
        tint = AppColors.metaText(context);
      case DownloadStatus.waitingForNetwork:
        tint = AppColors.metaText(context);
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: tint.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        '$count ${status.displayLabel}',
        style: tt.labelSmall?.copyWith(
          color: tint,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MultiSelectThumbnails extends StatelessWidget {
  final List<DownloadEntity> downloads;
  final int moreCount;
  const _MultiSelectThumbnails({
    required this.downloads,
    required this.moreCount,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final d in downloads)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: SizedBox(
              width: 84,
              height: 56,
              child:
                  d.thumbnail != null && d.thumbnail!.isNotEmpty
                      ? AppCachedImage(
                        imageUrl: d.thumbnail!,
                        fit: BoxFit.cover,
                        width: 84,
                        height: 56,
                      )
                      : Container(
                        color: AppColors.metaText(
                          context,
                        ).withValues(alpha: 0.12),
                        child: Icon(
                          Icons.video_file_outlined,
                          size: 18,
                          color: AppColors.metaText(context),
                        ),
                      ),
            ),
          ),
        if (moreCount > 0)
          Container(
            width: 84,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.metaText(context).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            alignment: Alignment.center,
            child: Text(
              '+$moreCount',
              style: AppTypography.metadata.copyWith(
                color: AppColors.metaText(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Header — back button + title (shared across all status bodies)
// ═════════════════════════════════════════════════════════════════════

class _ItemHeader extends ConsumerWidget {
  final DownloadEntity download;
  const _ItemHeader({required this.download});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tt = Theme.of(context).textTheme;

    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Row(
          children: [
            IconButton(
              tooltip: AppLocalizations.commonBack,
              onPressed:
                  () => ref.read(rightPanelProvider.notifier).showQuickStart(),
              icon: Icon(
                Icons.arrow_back,
                size: 18,
                color:
                    isDark
                        ? AppColors.darkMetaText
                        : cs.onSurface.withValues(alpha: AppOpacity.overlay),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                download.title?.isNotEmpty == true
                    ? download.title!
                    : download.filename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.darkLightText : cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Status bodies — minimal Material placeholders
// (UI agent GPT 5.5 polishes visual surface; state-machine wiring
//  + provider calls land here.)
// ═════════════════════════════════════════════════════════════════════

class _QueuedBody extends ConsumerWidget {
  final DownloadEntity download;
  const _QueuedBody({required this.download});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _StatusCard(
      icon: Icons.schedule_rounded,
      iconColor: AppColors.metaText(context),
      title: AppLocalizations.rightPanelPendingTitle,
      subtitle: AppLocalizations.rightPanelPendingSubtitle,
      thumbnailUrl: download.thumbnail,
      actions: [
        _ActionButton(
          icon: Icons.close_rounded,
          label: AppLocalizations.commonCancel,
          onPressed:
              () => ref
                  .read(downloadsNotifierProvider.notifier)
                  .cancelDownload(download.id),
        ),
      ],
    );
  }
}

class _DownloadingBody extends ConsumerWidget {
  final DownloadEntity download;
  const _DownloadingBody({required this.download});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the live download so progress refreshes without the user
    // having to reopen the panel.
    final live = ref
        .watch(downloadsNotifierProvider)
        .downloads
        .firstWhere((d) => d.id == download.id, orElse: () => download);
    final percent = live.progressPercentage.round();

    return _StatusCard(
      icon: Icons.download_rounded,
      iconColor: AppColors.brand,
      title: AppLocalizations.rightPanelDownloadingTitle(percent),
      subtitle:
          live.totalBytes > 0
              ? '${_formatBytes(live.downloadedBytes)} / ${_formatBytes(live.totalBytes)}'
              : AppLocalizations.rightPanelDownloadingPreparingSource,
      thumbnailUrl: live.thumbnail,
      progress: live.totalBytes > 0 ? live.progress : null,
      actions: [
        _ActionButton(
          icon: Icons.pause_rounded,
          label: AppLocalizations.downloadsPause,
          onPressed:
              () => ref
                  .read(downloadsNotifierProvider.notifier)
                  .pauseDownload(download.id),
        ),
        _ActionButton(
          icon: Icons.close_rounded,
          label: AppLocalizations.commonCancel,
          onPressed:
              () => ref
                  .read(downloadsNotifierProvider.notifier)
                  .cancelDownload(download.id),
        ),
      ],
    );
  }
}

class _PausedBody extends ConsumerWidget {
  final DownloadEntity download;
  const _PausedBody({required this.download});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final percent = download.progressPercentage.round();
    return _StatusCard(
      icon: Icons.pause_circle_rounded,
      iconColor: AppColors.metaText(context),
      title: AppLocalizations.rightPanelPausedTitle(percent),
      subtitle: AppLocalizations.rightPanelPausedSubtitle,
      thumbnailUrl: download.thumbnail,
      progress: download.totalBytes > 0 ? download.progress : null,
      actions: [
        _ActionButton(
          icon: Icons.play_arrow_rounded,
          label: AppLocalizations.downloadsResume,
          isPrimary: true,
          onPressed:
              () => ref
                  .read(downloadsNotifierProvider.notifier)
                  .resumeDownload(download.id),
        ),
        _ActionButton(
          icon: Icons.close_rounded,
          label: AppLocalizations.commonCancel,
          onPressed:
              () => ref
                  .read(downloadsNotifierProvider.notifier)
                  .cancelDownload(download.id),
        ),
      ],
    );
  }
}

class _FailedBody extends ConsumerWidget {
  final DownloadEntity download;
  const _FailedBody({required this.download});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final errorCode = download.errorCode;
    final detail =
        errorCode != null
            ? AppLocalizations.errorFeedbackHint(errorCode.name)
            : download.errorDetail ?? download.errorMessage ?? '';
    final title =
        errorCode != null
            ? AppLocalizations.errorFeedbackTitle(errorCode.name)
            : AppLocalizations.rightPanelFailedTitle;
    return _StatusCard(
      icon: errorCode?.icon ?? Icons.error_outline_rounded,
      iconColor: Theme.of(context).colorScheme.error,
      title: title,
      subtitle:
          detail.isEmpty
              ? AppLocalizations.rightPanelFailedDefaultHint
              : detail,
      thumbnailUrl: download.thumbnail,
      actions: [
        _ActionButton(
          icon: Icons.refresh_rounded,
          label: AppLocalizations.commonRetry,
          isPrimary: true,
          onPressed:
              () => ref
                  .read(downloadsNotifierProvider.notifier)
                  .retryDownload(download.id),
        ),
        _ActionButton(
          icon: Icons.delete_outline_rounded,
          label: AppLocalizations.commonDelete,
          onPressed:
              () => ref
                  .read(downloadsNotifierProvider.notifier)
                  .deleteDownload(download.id),
        ),
      ],
    );
  }
}

class _CancelledBody extends ConsumerWidget {
  final DownloadEntity download;
  const _CancelledBody({required this.download});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _StatusCard(
      icon: Icons.do_not_disturb_on_outlined,
      iconColor: AppColors.metaText(context),
      title: AppLocalizations.rightPanelCancelledTitle,
      subtitle: AppLocalizations.rightPanelCancelledSubtitle,
      thumbnailUrl: download.thumbnail,
      actions: [
        _ActionButton(
          icon: Icons.refresh_rounded,
          label: AppLocalizations.downloadsRedownload,
          isPrimary: true,
          onPressed:
              () => ref
                  .read(downloadsNotifierProvider.notifier)
                  .retryDownload(download.id),
        ),
        _ActionButton(
          icon: Icons.delete_outline_rounded,
          label: AppLocalizations.commonDelete,
          onPressed:
              () => ref
                  .read(downloadsNotifierProvider.notifier)
                  .deleteDownload(download.id),
        ),
      ],
    );
  }
}

class _WaitingForNetworkBody extends ConsumerWidget {
  final DownloadEntity download;
  const _WaitingForNetworkBody({required this.download});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _StatusCard(
      icon: Icons.wifi_off_rounded,
      iconColor: AppColors.metaText(context),
      title: AppLocalizations.rightPanelWaitingNetworkTitle,
      subtitle: AppLocalizations.rightPanelWaitingNetworkSubtitle,
      thumbnailUrl: download.thumbnail,
      progress: download.totalBytes > 0 ? download.progress : null,
      actions: [
        _ActionButton(
          icon: Icons.close_rounded,
          label: AppLocalizations.commonCancel,
          onPressed:
              () => ref
                  .read(downloadsNotifierProvider.notifier)
                  .cancelDownload(download.id),
        ),
      ],
    );
  }
}

class _MissingFileBody extends ConsumerWidget {
  final DownloadEntity download;
  const _MissingFileBody({required this.download});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _StatusCard(
      icon: Icons.warning_amber_rounded,
      iconColor: Theme.of(context).colorScheme.error,
      title: AppLocalizations.rightPanelFileMissingTitle,
      subtitle: AppLocalizations.rightPanelFileMissingSubtitle,
      thumbnailUrl: download.thumbnail,
      actions: [
        _ActionButton(
          icon: Icons.cloud_download_rounded,
          label: AppLocalizations.downloadsRedownload,
          isPrimary: true,
          onPressed:
              () => ref
                  .read(downloadsNotifierProvider.notifier)
                  .retryDownload(download.id),
        ),
        _ActionButton(
          icon: Icons.delete_outline_rounded,
          label: AppLocalizations.rightPanelActionRemoveFromList,
          onPressed:
              () => ref
                  .read(downloadsNotifierProvider.notifier)
                  .deleteDownload(download.id),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Player embed — completed media plays in-sidebar
// ═════════════════════════════════════════════════════════════════════

class _PlayerEmbedBody extends ConsumerStatefulWidget {
  final DownloadEntity download;
  const _PlayerEmbedBody({super.key, required this.download});

  @override
  ConsumerState<_PlayerEmbedBody> createState() => _PlayerEmbedBodyState();
}

class _PlayerEmbedBodyState extends ConsumerState<_PlayerEmbedBody> {
  Player? _player;
  VideoController? _videoController;
  late final String _filePath;
  late final bool _isVideo;
  late final bool _isAudio;
  late final bool _isImage;

  // Live playback state — kept in sync via media_kit streams. Surfaces
  // through controls (slider position, play/pause icon) and powers the
  // periodic position-save timer for resume-where-you-left-off.
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  double _volume = 1.0; // 0..1 (matches PlayerPrefs.volume scale)
  double _speed = 1.0;
  // Pre-mute volume — restored when the user un-mutes via the icon
  // toggle. Distinguishes "user dragged slider to 0" (no restore
  // needed) from "user clicked mute" (restore prior volume).
  double _volumeBeforeMute = 1.0;
  final FocusNode _focusNode = FocusNode();

  // ── Race-safety guards ─────────────────────────────────────────────
  // [_initializePlayer] is async. Without these guards, rapidly
  // clicking through downloads creates the canonical pattern:
  //   t=0  user clicks A → State.initState → fire-and-forget init
  //   t=0  Player A constructed (sync)
  //   t=10 user clicks B → State A's dispose runs → Player A.dispose
  //   t=20 init's `await prefs.getPrefs()` completes → tries to call
  //        `player.setVolume(...)` on disposed Player → media_kit
  //        crash, or worse: leaked init that finishes after dispose
  //        and re-attaches stream listeners on a zombie player.
  // [_disposed] short-circuits each await boundary.
  // [_initError] surfaces a fallback UI when init throws.
  bool _disposed = false;
  Object? _initError;
  bool _advancingAfterCompletion = false;
  bool _playerTransferredAway = false;

  /// PlayerManager registration id. Sidebar uses the `mini_*` prefix
  /// the existing service recognises, so the auto-pause invariant +
  /// auto-dispose timers + window-blur policy all apply automatically.
  /// Distinct from fullscreen's `video_*` / `audio_*` prefix so a
  /// sidebar→fullscreen handoff doesn't collide on the same key.
  String get _playerManagerId =>
      _isVideo
          ? 'mini_video_${widget.download.id}'
          : 'mini_audio_${widget.download.id}';

  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _completedSub;
  Timer? _saveTimer;
  WatchProgressService? _watchProgressService;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _watchProgressService = ref.read(watchProgressServiceProvider);
    _filePath = p.join(widget.download.savePath, widget.download.filename);
    _isVideo = FileUtils.isVideoFile(widget.download.filename);
    _isAudio = FileUtils.isAudioFile(widget.download.filename);
    _isImage = FileUtils.isImageFile(widget.download.filename);

    if (_isVideo || _isAudio) {
      // ignore: discarded_futures — fire-and-forget bootstrap; UI
      // shows progressive loading while the player wires up.
      _initializePlayer();
    }
  }

  Future<void> _initializePlayer({
    bool autoPlay = true,
    Duration? resumePosition,
  }) async {
    Player? player;
    try {
      _playerTransferredAway = false;
      // Bail before any allocation if the widget was already disposed
      // (rapid click-through case where dispose ran before this
      // microtask started).
      if (_disposed) return;

      player = Player();
      // Stamp the field BEFORE the first await so dispose() can find
      // and tear down the half-built player if the user clicks away
      // mid-init.
      _player = player;

      // CRITICAL: register with PlayerManager singleton.
      //
      // PlayerManager enforces the "max 1 actively playing media_kit
      // Player at a time" invariant across the whole app — without
      // this registration:
      //   - rapid item swaps stack N native libmpv processes (each
      //     allocating GPU surfaces + audio threads) → memory blow
      //     up + GPU contention → app crash on macOS / Windows
      //   - opening a fullscreen player while sidebar plays leaves
      //     two audio streams overlapping
      //   - app shutdown's `playerManager.disposeAll()` hook misses
      //     this player → libmpv subprocess leak past app close
      //
      // Registration auto-pauses any other registered player when
      // this one starts playing, auto-disposes after 5 min of paused
      // + window-blurred, and replaces / disposes any prior player
      // registered under the same key (so re-mount with same id is
      // self-cleaning).
      playerManager.registerPlayer(_playerManagerId, player);

      if (_isVideo) {
        if (_disposed) {
          // dispose() already ran in parallel — it called
          // `playerManager.unregisterPlayer(_playerManagerId)` which
          // disposed our player. Just bail out of init without
          // double-disposing.
          return;
        }
        _videoController = VideoController(player);
      }

      // Apply hardware-decode hint BEFORE the open() call below.
      // mpv evaluates `hwdec` at codec-open time, so setting it after
      // open is a no-op for the file currently being loaded. The
      // sidebar embedded player is the V2 entry point most users
      // hit first (single-tap any download in the list), so missing
      // this site means the opt-in flag would only kick in on
      // fullscreen — which Codex called out. We await before the
      // pref restore + open chain to keep the hint deterministic.
      // setProperty failures are swallowed inside the service so a
      // misbehaving mpv build can never block playback startup.
      final hwdecEnabled = ref.read(hardwareDecodeEnabledProvider);
      await PlayerHardwareDecodeService.apply(player, enabled: hwdecEnabled);
      if (_disposed) return;

      // Restore user prefs (volume, speed). After each await we
      // re-check `_disposed` — if the user has clicked another item
      // (or closed the panel) we abandon init and tear down whatever
      // we've allocated. Skipping these checks is what lets media_kit
      // operate on a disposed Player instance and crash the engine.
      final prefsService = ref.read(playerPrefsServiceProvider);
      final prefs =
          await prefsService.getPrefs(widget.download.url) ??
          const PlayerPrefs();
      if (_disposed) {
        // dispose() already ran in parallel — see top-of-method
        // comment. PlayerManager already disposed our player.
        return;
      }

      _volume = prefs.volume;
      _speed = prefs.speed;
      await player.setVolume(prefs.volume * 100);
      if (_disposed) {
        // dispose() already ran in parallel — see top-of-method
        // comment. PlayerManager already disposed our player.
        return;
      }
      await player.setRate(prefs.speed);
      if (_disposed) {
        // dispose() already ran in parallel — see top-of-method
        // comment. PlayerManager already disposed our player.
        return;
      }

      // media_kit starts playback by default. Keep the embedded player
      // paused until the saved resume point is applied, otherwise it can
      // briefly play from 0s before the seek completes.
      await player.open(Media('file://$_filePath'), play: false);
      if (_disposed) {
        // dispose() already ran in parallel — see top-of-method
        // comment. PlayerManager already disposed our player.
        return;
      }
      _syncPlayerSnapshot(player);

      // Resume position. Explicit handoff wins because it is live
      // surface state; saved progress is the fallback for cold sidebar
      // opens from the downloads list.
      final initialPosition = resumePosition ?? _savedResumePosition();
      if (initialPosition != null) {
        await _seekToResumePosition(player, initialPosition);
        if (_disposed) {
          // dispose() already ran in parallel — it called
          // `playerManager.unregisterPlayer(_playerManagerId)` which
          // disposed our player. Just bail out of init without
          // double-disposing.
          return;
        }
        _syncPlayerSnapshot(player);
      }

      // Wire streams. dispose() cancels these subscriptions before
      // the player goes — no setState on disposed widget.
      //
      // [onError] catches the case where PlayerManager auto-disposes
      // this Player out from under us (5-min idle + window blur
      // policy). The stream throws a disposed-player error; we treat
      // it as "rebuild me" rather than a hard failure: null out the
      // dead reference, set _initialized=false to surface the
      // loading spinner, and schedule a fresh _initializePlayer()
      // pass. The user clicks play and we transparently re-allocate.
      void handleStreamError(Object error) {
        if (!mounted || _disposed) return;
        if (!PlayerSafety.isDisposedPlayerError(error)) return;
        _player = null;
        _videoController = null;
        _saveTimer?.cancel();
        setState(() => _initialized = false);
        _initializePlayer(autoPlay: _isPlaying);
      }

      _positionSub = player.stream.position.listen((pos) {
        if (mounted && !_disposed) setState(() => _position = pos);
      }, onError: handleStreamError);
      _durationSub = player.stream.duration.listen((dur) {
        if (mounted && !_disposed) setState(() => _duration = dur);
      }, onError: handleStreamError);
      _playingSub = player.stream.playing.listen((playing) {
        if (mounted && !_disposed) setState(() => _isPlaying = playing);
      }, onError: handleStreamError);
      _completedSub = player.stream.completed.listen((done) {
        if (done && mounted && !_disposed) {
          _handlePlaybackCompleted();
        }
      }, onError: handleStreamError);

      // Periodic position save so a crash / unexpected close still
      // preserves the resume point. Skips when paused — position
      // hasn't moved since last tick, no point re-writing the same
      // bytes to SharedPreferences 12 times/min. The dispose() final
      // save covers the "user paused then closed" case.
      _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted || _disposed) return;
        if (!_isPlaying) return;
        final dur = _duration;
        if (dur.inMilliseconds <= 0) return;
        ref
            .read(watchProgressServiceProvider)
            .saveResumePoint(widget.download.id, _position, dur);
      });

      if (autoPlay) {
        if (mounted && !_disposed) {
          setState(() => _isPlaying = true);
        }
        await player.play();
        if (_disposed) return;
      }

      if (mounted && !_disposed) {
        final playing = autoPlay || _livePlaying(player);
        final position = _livePosition(player);
        final duration = _liveDuration(player);
        setState(() {
          _isPlaying = playing;
          _position = position;
          _duration = duration;
          _initialized = true;
        });
      }
    } catch (e, st) {
      // Disposed-player error here means the user clicked away mid-
      // init (race between dispose() and an in-flight `await`) —
      // race-safety surface, not real failure. Tear down silently
      // without showing the error fallback.
      if (PlayerSafety.isDisposedPlayerError(e)) {
        playerManager.unregisterPlayer(_playerManagerId);
        _player = null;
        _videoController = null;
        return;
      }
      // Real error: media_kit threw on invalid path / unsupported
      // codec / file deleted between check and open. Surface graceful
      // fallback. Route teardown through PlayerManager so bookkeeping
      // + any listener is cleaned up.
      playerManager.unregisterPlayer(_playerManagerId);
      _player = null;
      _videoController = null;
      if (mounted && !_disposed) {
        setState(() {
          _initialized = true;
          _initError = e;
        });
      }
      // Logged-but-not-rethrown — the UI fallback covers user-facing
      // damage; surfacing the stack to console helps debug.
      debugPrint('[_PlayerEmbedBody] init failed: $e\n$st');
    }
  }

  // _safeDispose helper removed — all teardown now routes through
  // [PlayerManager.unregisterPlayer], which handles double-dispose
  // and "not yet opened" edge cases internally and keeps the
  // singleton's bookkeeping consistent.

  // ── User-action handlers ──
  //
  // All gestures route through [PlayerSafety.safeCall] so a delayed
  // tap that resolves after the player was disposed (rapid item-swap
  // race) no-ops instead of surfacing media_kit's "Player has been
  // disposed" assertion as a production crash. Mirrors the pattern
  // every canonical player widget uses (mini_video_player,
  // video_controls, system_pip_view, mini_player).

  void _togglePlayPause() {
    final player = _player;
    if (player == null) return;
    final wasPlaying = _livePlaying(player);
    if (mounted && !_disposed) {
      setState(() => _isPlaying = !wasPlaying);
    }
    PlayerSafety.safeCall(() async {
      if (wasPlaying) {
        await player.pause();
      } else {
        await player.play();
      }
      _syncPlayerSnapshot(player, playingOverride: !wasPlaying);
    });
  }

  void _seek(Duration target) {
    if (mounted && !_disposed) {
      setState(() => _position = target);
    }
    PlayerSafety.safeCall(() => _player?.seek(target));
  }

  Future<void> _seekToResumePosition(Player player, Duration position) async {
    if (position <= const Duration(milliseconds: 500)) return;

    final currentDeltaMs =
        (_livePosition(player) - position).inMilliseconds.abs();
    if (currentDeltaMs <= 800) {
      if (mounted && !_disposed) {
        setState(() => _position = position);
      }
      return;
    }

    await player.seek(position);
    if (!mounted || _disposed) return;
    setState(() => _position = position);

    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (!mounted || _disposed) return;
    final observed = _livePosition(player);
    if (observed + const Duration(milliseconds: 800) < position) {
      await player.seek(position);
      if (!mounted || _disposed) return;
      setState(() => _position = position);
    }
  }

  Duration? _savedResumePosition() {
    final progress = ref
        .read(watchProgressServiceProvider)
        .getProgress(widget.download.id);
    if (progress == null) return null;
    if (progress.position <= const Duration(milliseconds: 500)) return null;
    if (progress.fraction >= 0.90) return null;
    return progress.position;
  }

  void _handlePlaybackCompleted() {
    if (_advancingAfterCompletion) return;
    _advancingAfterCompletion = true;

    // Auto-mark watched + clear progress per WatchProgressService contract.
    ref.read(watchProgressServiceProvider).onPlaybackEnd(widget.download.id);

    final nextDownload = ref.read(playbackQueueProvider.notifier).next();
    if (nextDownload == null || !mounted || _disposed) {
      _advancingAfterCompletion = false;
      return;
    }

    if (nextDownload.id == widget.download.id) {
      final player = _player;
      if (player != null) {
        PlayerSafety.safeCall(() async {
          await player.seek(Duration.zero);
          await player.play();
        });
      }
      _advancingAfterCompletion = false;
      return;
    }

    PlayerSafety.safeCall(() => _player?.stop());
    ref.read(rightPanelProvider.notifier).showDetail(nextDownload);
  }

  Future<void> _setVolume(double next) async {
    final player = _player;
    if (player == null) return;
    setState(() => _volume = next);
    PlayerSafety.safeCall(() => player.setVolume(next * 100));
    // Prefs store write is independent of player lifecycle — keep
    // awaited so callers (mute toggle, slider) settle once the disk
    // write completes.
    await ref
        .read(playerPrefsServiceProvider)
        .savePrefs(
          widget.download.url,
          PlayerPrefs(speed: _speed, volume: next),
        );
  }

  Future<void> _setSpeed(double next) async {
    final player = _player;
    if (player == null) return;
    setState(() => _speed = next);
    PlayerSafety.safeCall(() => player.setRate(next));
    await ref
        .read(playerPrefsServiceProvider)
        .savePrefs(
          widget.download.url,
          PlayerPrefs(speed: next, volume: _volume),
        );
  }

  /// Fullscreen handoff. Pattern:
  ///   1. Save the current playback position so the fullscreen player
  ///      lands at the same frame (shared `WatchProgressService`).
  ///   2. Transfer the live Player into fullscreen. Reusing the native
  ///      player avoids a stop/open/play cycle, so the handoff stays on
  ///      the exact frame and keeps audio continuous.
  ///   3. Push [VideoPlayerScreen] (or AudioPlayerScreen) with the
  ///      existing player and current play/pause intent.
  ///   4. On return, re-init the sidebar player from the position the
  ///      fullscreen surface advanced to. If playback was active at
  ///      handoff, the embedded player resumes; if it was paused, it
  ///      stays paused at the latest frame.
  Future<void> _expandFullscreen() async {
    final player = _player;
    if (player == null) return;

    // Capture playing state — restored on return so the user lands
    // continuing playback in the sidebar, not stuck paused. Standard
    // YouTube / Netflix / Apple TV pattern: PiP / mini surface
    // resumes the rhythm the fullscreen left at, without an extra
    // tap. Combined with the saved position (below), the user
    // perceives a continuous timeline across the surface swap.
    final handoffPosition = _livePosition(player);
    final handoffDuration = _liveDuration(player);
    final wasPlaying = _livePlaying(player);
    final videoController = _videoController;
    if (_isVideo && videoController == null) return;

    // Persist current position before tearing down so fullscreen
    // resumes exactly here.
    if (handoffDuration.inMilliseconds > 0) {
      ref
          .read(watchProgressServiceProvider)
          .saveResumePoint(
            widget.download.id,
            handoffPosition,
            handoffDuration,
          );
    }

    // Transfer ownership to fullscreen. Cancel sidebar listeners first
    // so the hidden sidebar no longer drives UI state for this Player.
    _saveTimer?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _playingSub?.cancel();
    await _completedSub?.cancel();
    _positionSub = null;
    _durationSub = null;
    _playingSub = null;
    _completedSub = null;

    playerManager.unregisterPlayer(_playerManagerId, dispose: false);
    _player = null;
    _videoController = null;

    // Surface the loading state while fullscreen is active so the
    // sidebar doesn't show a stale frame.
    if (mounted && !_disposed) {
      setState(() {
        _initialized = false;
        _isPlaying = false;
      });
    }

    if (!mounted) return;
    PlayerHandoffResult? handoffResult;
    if (_isVideo && videoController != null) {
      handoffResult = await Navigator.of(context).push<PlayerHandoffResult>(
        MaterialPageRoute<PlayerHandoffResult>(
          builder:
              (_) => VideoPlayerScreen(
                download: widget.download,
                existingPlayer: player,
                existingVideoController: videoController,
                resumePosition: handoffPosition,
                autoPlay: wasPlaying,
              ),
        ),
      );
    } else if (_isAudio) {
      handoffResult = await Navigator.of(context).push<PlayerHandoffResult>(
        MaterialPageRoute<PlayerHandoffResult>(
          builder:
              (_) => AudioPlayerScreen(
                download: widget.download,
                existingPlayer: player,
                resumePosition: handoffPosition,
                autoPlay: wasPlaying,
              ),
        ),
      );
    }

    // Returned from fullscreen — re-init the sidebar player from the
    // exact route result when available. This avoids depending on the
    // 5-second periodic saver or the persistent 5% save threshold.
    if (!mounted || _disposed) return;
    if (handoffResult == null) {
      await _initializePlayer(autoPlay: false, resumePosition: handoffPosition);
      return;
    }
    final result = handoffResult;
    if (!result.restoreSidebar) {
      setState(() {
        _playerTransferredAway = true;
        _initialized = true;
        _isPlaying = result.isPlaying;
        _position = result.position;
      });
      return;
    }
    await _initializePlayer(
      autoPlay: result.isPlaying,
      resumePosition: result.position,
    );
  }

  T? _safePlayerState<T>(Player player, T Function(Player player) reader) {
    try {
      return reader(player);
    } catch (error, stackTrace) {
      if (PlayerSafety.isDisposedPlayerError(error)) return null;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  bool _livePlaying(Player player) =>
      _safePlayerState(player, (player) => player.state.playing) ?? _isPlaying;

  Duration _livePosition(Player player) =>
      _safePlayerState(player, (player) => player.state.position) ?? _position;

  Duration _liveDuration(Player player) =>
      _safePlayerState(player, (player) => player.state.duration) ?? _duration;

  void _syncPlayerSnapshot(Player player, {bool? playingOverride}) {
    if (!mounted || _disposed) return;
    final playing = playingOverride ?? _livePlaying(player);
    final position = _livePosition(player);
    final duration = _liveDuration(player);
    setState(() {
      _isPlaying = playing;
      _position = position;
      _duration = duration;
    });
  }

  Future<void> _toggleMute() async {
    final player = _player;
    if (player == null) return;
    if (_volume > 0) {
      _volumeBeforeMute = _volume;
      await _setVolume(0);
    } else {
      // Restore prior level (default 1.0 if user never set explicitly).
      await _setVolume(_volumeBeforeMute > 0 ? _volumeBeforeMute : 1.0);
    }
  }

  KeyEventResult _onKeyEvent(KeyEvent event) {
    // Desktop keyboard shortcuts. Only handles the embedded sidebar
    // surface — fullscreen player has its own keymap.
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      _togglePlayPause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      final target = _position - const Duration(seconds: 10);
      _seek(target.isNegative ? Duration.zero : target);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      final target = _position + const Duration(seconds: 10);
      _seek(target > _duration ? _duration : target);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _setVolume((_volume + 0.05).clamp(0.0, 1.0));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _setVolume((_volume - 0.05).clamp(0.0, 1.0));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void deactivate() {
    // Called when widget is removed from the tree (e.g. user clicks
    // another item, or hits the back arrow on the item header).
    // AnimatedSwitcher fades the old child out — without pausing
    // here, audio continues during the fade and the user hears the
    // previous item leak into the new one. Routed through
    // PlayerSafety so a deactivate that beats async dispose by a
    // microtask doesn't surface "Player has been disposed".
    PlayerSafety.safeCall(() => _player?.pause());
    super.deactivate();
  }

  @override
  void dispose() {
    // Mark disposed FIRST so any in-flight init bails out at its
    // next await boundary instead of touching this state.
    _disposed = true;

    // Cancel timers + stream subscriptions BEFORE disposing the
    // player. Otherwise a stream tick can fire after the player is
    // gone and re-attempt setState on a dead State.
    _saveTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _completedSub?.cancel();

    // Final position save — covers the "user closes panel mid-play"
    // case the periodic timer might miss by up to 5 seconds.
    if (_duration.inMilliseconds > 0 && _player != null) {
      _watchProgressService?.saveResumePoint(
        widget.download.id,
        _position,
        _duration,
      );
    }

    final player = _player;
    _player = null;
    _videoController = null;
    if (player != null) {
      // Route disposal through PlayerManager so the singleton's
      // bookkeeping (active map, currently-playing pointer,
      // auto-dispose timers, stream subscriptions) stays consistent.
      // PlayerManager.unregisterPlayer with dispose:true calls
      // _disposePlayerSafely under the hood — no double-dispose risk.
      playerManager.unregisterPlayer(_playerManagerId);
    }
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filename = widget.download.filename;

    // Image: no Player, just file display.
    if (_isImage) {
      return _ImageEmbed(filePath: _filePath, download: widget.download);
    }

    // Unsupported (rare — download flagged completed but filename has
    // no recognised media extension). Fallback card.
    if (!_isVideo && !_isAudio) {
      return _StatusCard(
        icon: Icons.help_outline_rounded,
        iconColor: AppColors.metaText(context),
        title: AppLocalizations.rightPanelUnsupportedTitle,
        subtitle: filename,
        thumbnailUrl: widget.download.thumbnail,
        actions: const [
          // No actions — file exists but app can't preview it.
          // User can open in OS via row context menu.
        ],
      );
    }

    // Init failed (file moved between status update + open, codec
    // unsupported by the platform's media_kit backend, etc). Surface
    // a fallback card with retry — re-mount the widget to retry by
    // toggling a key in parent. For now show CTA to open externally.
    if (_initError != null) {
      return _StatusCard(
        icon: Icons.error_outline_rounded,
        iconColor: Theme.of(context).colorScheme.error,
        title: AppLocalizations.rightPanelNoEmbedTitle,
        subtitle: AppLocalizations.rightPanelNoEmbedSubtitle,
        thumbnailUrl: widget.download.thumbnail,
        actions: [
          _ActionButton(
            icon: Icons.fullscreen_rounded,
            label: AppLocalizations.rightPanelActionFullscreen,
            isPrimary: true,
            onPressed:
                () => openPlayerForDownload(
                  context,
                  ref,
                  widget.download,
                ),
          ),
        ],
      );
    }

    // Loading state while _initializePlayer() bootstraps.
    final transferredOverlayActive = _isPlayerEmbedOverlayActive(
      ref,
      widget.download,
    );
    if (_playerTransferredAway && _player == null && transferredOverlayActive) {
      return _StatusCard(
        icon: Icons.picture_in_picture_alt_rounded,
        iconColor: AppColors.accentHighlight,
        title: AppLocalizations.playerPictureInPicture,
        subtitle: filename,
        thumbnailUrl: widget.download.thumbnail,
        actions: const [],
      );
    }

    if (_playerTransferredAway &&
        _player == null &&
        !transferredOverlayActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _disposed || !_playerTransferredAway) return;
        _initializePlayer(autoPlay: false, resumePosition: _position);
      });
    }

    if (!_initialized || _player == null) {
      return const _PlayerEmbedLoadingSkeleton();
    }

    // Video + audio share the same controls bar — only the visual
    // surface above differs.
    final livePlayer = _player;
    final displayPlaying =
        livePlayer == null ? _isPlaying : _livePlaying(livePlayer);
    final displayPosition =
        livePlayer == null ? _position : _livePosition(livePlayer);
    final displayDuration =
        livePlayer == null ? _duration : _liveDuration(livePlayer);
    final mediaSurface =
        _isVideo && _videoController != null
            ? AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Video(
                  controller: _videoController!,
                  // Sidebar uses our custom controls below — hide
                  // media_kit's default overlay to avoid double UI.
                  controls: NoVideoControls,
                ),
              ),
            )
            : _AudioVisual(
              thumbnailUrl: widget.download.thumbnail,
              isPlaying: displayPlaying,
            );

    // Focus wraps the embedded surface so keyboard shortcuts (space /
    // arrows / M) work on desktop without pulling focus from the rest
    // of the app. autofocus=false — the user must click into the
    // sidebar to start receiving keys; otherwise typing into the URL
    // input field would be hijacked.
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (_, e) => _onKeyEvent(e),
      child: GestureDetector(
        onTap: _focusNode.requestFocus,
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            mediaSurface,
            const SizedBox(height: AppSpacing.md),
            _PlayerControls(
              isPlaying: displayPlaying,
              position: displayPosition,
              duration: displayDuration,
              volume: _volume,
              speed: _speed,
              onPlayPause: _togglePlayPause,
              onSeek: _seek,
              onVolumeChanged: _setVolume,
              onSpeedChanged: _setSpeed,
              onMuteToggle: _toggleMute,
              onExpand: _expandFullscreen,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              filename,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.metadata.copyWith(
                color: AppColors.metaText(context),
              ),
            ),
            // Fill the previously-empty zone below the filename with
            // the playlist / subs+audio / chapters tab strip. The
            // strip self-degrades to empty states when the underlying
            // data isn't there (no queue, no embedded subs, no
            // chapters) so it stays out of the way for plain video
            // files while paying off on grouped / multi-track ones.
            if (_isVideo || _isAudio) ...[
              const SizedBox(height: AppSpacing.md),
              RightPanelTabs(
                download: widget.download,
                player: _player,
                position: _position,
                onSeek: _seek,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Image preview embed. Reuses [ImageViewerScreen] for the fullscreen
/// path so carousels (gallery-dl multi-image) work consistently.
class _ImageEmbed extends ConsumerWidget {
  final String filePath;
  final DownloadEntity download;
  const _ImageEmbed({required this.filePath, required this.download});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final file = File(filePath);
    if (!file.existsSync()) {
      return _StatusCard(
        icon: Icons.broken_image_rounded,
        iconColor: Theme.of(context).colorScheme.error,
        title: AppLocalizations.rightPanelImageFileMissingTitle,
        subtitle: download.filename,
        thumbnailUrl: download.thumbnail,
        actions: const [],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: GestureDetector(
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ImageViewerScreen(download: download),
                  ),
                ),
            child: Image.file(file, fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color:
                isDark ? AppColors.homeDarkCardBg : AppColors.surface2(context),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border(context)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.touch_app_outlined,
                size: 16,
                color: AppColors.metaText(context),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  AppLocalizations.homeCarouselClickHint,
                  style: AppTypography.metadata.copyWith(
                    color: AppColors.metaText(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

bool _isPlayerEmbedOverlayActive(WidgetRef ref, DownloadEntity download) {
  final downloadId = download.id.toString();
  final videoState = ref.watch(miniVideoPlayerStateProvider);
  if (videoState?.downloadId == downloadId) return true;

  final audioState = ref.watch(miniPlayerStateProvider);
  return audioState?.downloadId == downloadId;
}

/// Audio "now playing" surface — placeholder rectangle with filename
/// + animated indicator. UI agent can replace with waveform later.
class _AudioVisual extends StatelessWidget {
  final String? thumbnailUrl;
  final bool isPlaying;

  const _AudioVisual({required this.thumbnailUrl, required this.isPlaying});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface2(context),
            border: Border.all(color: AppColors.border(context)),
          ),
          child:
              thumbnailUrl != null && thumbnailUrl!.isNotEmpty
                  ? Stack(
                    fit: StackFit.expand,
                    children: [
                      LayoutBuilder(
                        builder:
                            (ctx, constraints) => AppCachedImage(
                              imageUrl: thumbnailUrl,
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              fit: BoxFit.cover,
                              errorWidget: _fallbackVisual(context),
                            ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.02),
                              Colors.black.withValues(alpha: 0.16),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                  : _fallbackVisual(context),
        ),
      ),
    );
  }

  Widget _fallbackVisual(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.surface2(context)),
      child: Center(child: _audioBadge()),
    );
  }

  Widget _audioBadge() {
    return Container(
      width: 82,
      height: 82,
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: AppOpacity.subtle),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: AppColors.accentHighlight.withValues(
            alpha: AppOpacity.secondary,
          ),
        ),
      ),
      child: Icon(
        isPlaying ? Icons.graphic_eq_rounded : Icons.audiotrack_rounded,
        size: 42,
        color: AppColors.accentHighlight,
      ),
    );
  }
}

class _PlayerEmbedLoadingSkeleton extends StatelessWidget {
  const _PlayerEmbedLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final bone = ShimmerColors.bone(context);

    return Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Container(
                color: bone,
                alignment: Alignment.center,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: bone,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface.withValues(
                        alpha: AppOpacity.pressed,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Row(
            children: [
              SkeletonCircle(size: 44),
              SizedBox(width: AppSpacing.sm),
              Expanded(child: SkeletonLine(height: 8)),
              SizedBox(width: AppSpacing.sm),
              SkeletonLine(width: 42, height: 18),
              SizedBox(width: AppSpacing.xs),
              SkeletonCircle(size: 32),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const SkeletonLine(height: 12),
          const SizedBox(height: AppSpacing.xs),
          const SkeletonLine(width: 180, height: 12),
        ],
      ),
    );
  }
}

/// Custom control bar for the embedded player. Stock Material widgets
/// — UI agent (GPT 5.5) replaces visual surface later.
class _PlayerControls extends StatelessWidget {
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double volume;
  final double speed;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback onMuteToggle;
  final VoidCallback onExpand;

  const _PlayerControls({
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.volume,
    required this.speed,
    required this.onPlayPause,
    required this.onSeek,
    required this.onVolumeChanged,
    required this.onSpeedChanged,
    required this.onMuteToggle,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    final maxMs = duration.inMilliseconds.toDouble();
    final posMs = position.inMilliseconds.toDouble().clamp(
      0.0,
      maxMs <= 0 ? 1.0 : maxMs,
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface2(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        children: [
          // Seek slider + time labels
          Row(
            children: [
              Text(
                _formatDuration(position),
                style: AppTypography.metadata.copyWith(
                  color: AppColors.metaText(context),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                  ),
                  child: Slider(
                    value: posMs,
                    max: maxMs <= 0 ? 1.0 : maxMs,
                    onChanged: (v) => onSeek(Duration(milliseconds: v.toInt())),
                    activeColor: AppColors.brand,
                  ),
                ),
              ),
              Text(
                _formatDuration(duration),
                style: AppTypography.metadata.copyWith(
                  color: AppColors.metaText(context),
                ),
              ),
            ],
          ),
          // Transport row — play/pause + volume + speed + expand
          Row(
            children: [
              IconButton(
                tooltip:
                    isPlaying
                        ? AppLocalizations.playerPause
                        : AppLocalizations.playerPlay,
                onPressed: onPlayPause,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.brand.withValues(
                    alpha: AppOpacity.subtle,
                  ),
                  foregroundColor: AppColors.accentHighlight,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                ),
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 32,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              // Volume slider — compact horizontal. Click icon = mute
              // toggle (restores prior level on un-mute).
              IconButton(
                tooltip: AppLocalizations.homeMuteToggleTooltip,
                onPressed: onMuteToggle,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  volume == 0
                      ? Icons.volume_off_rounded
                      : volume < 0.5
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded,
                  size: 18,
                  color: AppColors.metaText(context),
                ),
              ),
              SizedBox(
                width: 80,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10,
                    ),
                  ),
                  child: Slider(
                    value: volume.clamp(0.0, 1.0),
                    onChanged: onVolumeChanged,
                    activeColor: AppColors.brand,
                  ),
                ),
              ),
              const Spacer(),
              // Speed picker — popup menu of common rates.
              PopupMenuButton<double>(
                tooltip: AppLocalizations.rightPanelTooltipSpeed,
                initialValue: speed,
                onSelected: onSpeedChanged,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface3(context),
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    border: Border.all(color: AppColors.border(context)),
                  ),
                  child: Text(
                    '${speed.toStringAsFixed(speed == speed.toInt() ? 0 : 2)}×',
                    style: AppTypography.buttonSecondary.copyWith(
                      color: AppColors.metaText(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                itemBuilder:
                    (ctx) => const [
                      PopupMenuItem(value: 0.5, child: Text('0.5×')),
                      PopupMenuItem(value: 0.75, child: Text('0.75×')),
                      PopupMenuItem(value: 1.0, child: Text('1×')),
                      PopupMenuItem(value: 1.25, child: Text('1.25×')),
                      PopupMenuItem(value: 1.5, child: Text('1.5×')),
                      PopupMenuItem(value: 2.0, child: Text('2×')),
                    ],
              ),
              IconButton(
                tooltip: AppLocalizations.rightPanelTooltipFullscreen,
                onPressed: onExpand,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surface3(context),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                ),
                icon: Icon(
                  Icons.fullscreen_rounded,
                  size: 22,
                  color: AppColors.metaText(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Shared building blocks — stock Material placeholders
// ═════════════════════════════════════════════════════════════════════

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? thumbnailUrl;
  final double? progress;
  final List<_ActionButton> actions;

  const _StatusCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.thumbnailUrl,
    this.progress,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface2(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: LayoutBuilder(
                  builder:
                      (ctx, constraints) => AppCachedImage(
                        imageUrl: thumbnailUrl!,
                        fit: BoxFit.cover,
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                      ),
                ),
              ),
            ),
          if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty)
            const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle,
            style: tt.bodySmall?.copyWith(color: AppColors.metaText(context)),
          ),
          if (progress != null) ...[
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: cs.onSurface.withValues(
                  alpha: AppOpacity.divider,
                ),
                valueColor: AlwaysStoppedAnimation(AppColors.brand),
              ),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isPrimary;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isPrimary) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: AppColors.darkLightText,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        side: BorderSide(color: AppColors.border(context)),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Helpers
// ═════════════════════════════════════════════════════════════════════

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var i = 0;
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[i]}';
}

String _formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  if (d.inHours > 0) {
    return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }
  return '${two(d.inMinutes)}:${two(d.inSeconds.remainder(60))}';
}
