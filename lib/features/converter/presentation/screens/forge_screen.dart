import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/binaries/binary_providers.dart';
import '../../../../core/binaries/binary_type.dart';
import '../../../../core/core.dart';
import '../../../../core/navigation/navigation_constants.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../../domain/entities/conversion_preset.dart';
import '../../domain/entities/conversion_status.dart';
import '../../domain/entities/media_info.dart';
import '../../domain/entities/conversion_job.dart';
import '../../domain/services/conversion_playback_adapter.dart';
import '../../../player/presentation/screens/audio_player_screen.dart';
import '../../../player/presentation/screens/image_viewer_screen.dart';
import '../../../player/presentation/screens/video_player_screen.dart';
import '../providers/conversion_queue_provider.dart';
import '../providers/converter_providers.dart';
import '../widgets/add_files_panel.dart';
import '../widgets/conversion_job_card.dart';
import '../widgets/converter_telemetry_bar.dart';
import '../widgets/ffmpeg_log_dialog.dart';
import '../widgets/media_info_card.dart';
import 'editor_screen.dart';
import 'forge_preset_view.dart';
import 'forge_config_view.dart';

/// The Forge — media converter & editor entry screen.
///
/// Three-state flow:
/// 1. Empty: Add files panel + preset mosaic grid
/// 2. File loaded: Preset grid with file info
/// 3. Preset selected: Configuration panel + convert button
///
/// Wide layout (≥1100px): Left (file + presets/config) | Right (queue)
/// Narrow layout: Single column scroll
class ForgeScreen extends ConsumerStatefulWidget {
  const ForgeScreen({super.key});

  @override
  ConsumerState<ForgeScreen> createState() => _ForgeScreenState();
}

class _ForgeScreenState extends ConsumerState<ForgeScreen> {
  MediaInfo? _selectedFileInfo;
  String? _selectedFilePath;
  String? _thumbnailPath;
  bool _isProbing = false;

  // Enhancement-specific state
  List<String> _concatFiles = [];
  String? _selectedColorEffectId;

  // Queue UX — collapse/expand the completed history section
  bool _historyExpanded = true;

  static const double _splitBreakpoint = 1100.0;

  @override
  void initState() {
    super.initState();
    // Auto-probe file if navigated from download context menu "Convert" action
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final inputFile = ref.read(converterInputFileProvider);
      if (inputFile != null) {
        ref.read(converterInputFileProvider.notifier).state = null;
        _onFilesSelected([inputFile], ref);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? AppColors.homeDarkAppBg : AppColors.lightBase;

    return Scaffold(
      backgroundColor: background,
      body: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: background)),
          Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= _splitBreakpoint;
                    if (isWide) {
                      return _buildWideLayout(context);
                    }
                    return _buildNarrowLayout(context);
                  },
                ),
              ),
              const ConverterTelemetryBar(),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Wide layout: Left (content) + Right (queue)
  // ══════════════════════════════════════════════════════════════

  Widget _buildWideLayout(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ffmpegAvailable = ref.watch(
      binaryAvailableProvider(BinaryType.ffmpeg),
    );
    final jobs = ref.watch(conversionQueueProvider);
    final hasQueue = jobs.isNotEmpty;

    return Column(
      children: [
        // Fixed header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: _buildHeaderRow(context, cs, tt),
        ),
        if (ffmpegAvailable.valueOrNull == false)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: _buildFfmpegWarning(tt),
          ),
        const SizedBox(height: 12),

        // Split body
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // LEFT — file input + presets/config
              Expanded(
                flex: hasQueue ? 55 : 100,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 14, 20),
                  child: _buildMainContent(context, cs, tt),
                ),
              ),

              // Divider + RIGHT queue panel (only when jobs exist)
              if (hasQueue) ...[
                Container(
                  width: 1,
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? AppColors.homeDarkBorderStrong
                          : AppColors.border(context).withValues(alpha: 0.55),
                ),
                Expanded(
                  flex: 45,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 4, 20, 20),
                    child: _buildQueueSection(context, cs, tt),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Narrow layout: single column
  // ══════════════════════════════════════════════════════════════

  Widget _buildNarrowLayout(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ffmpegAvailable = ref.watch(
      binaryAvailableProvider(BinaryType.ffmpeg),
    );
    final jobs = ref.watch(conversionQueueProvider);

    return CustomScrollView(
      slivers: [
        // Header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _buildHeaderRow(context, cs, tt),
          ),
        ),

        // FFmpeg warning
        if (ffmpegAvailable.valueOrNull == false)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: _buildFfmpegWarning(tt),
            ),
          ),

        // Main content
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: _buildMainContent(context, cs, tt),
          ),
        ),

        // Queue section
        if (jobs.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: _buildQueueSection(context, cs, tt),
            ),
          ),

        // Empty state
        if (jobs.isEmpty && _selectedFilePath == null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyState(cs, tt),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Main content — file + presets/config (shared by both layouts)
  // ══════════════════════════════════════════════════════════════

  Widget _buildMainContent(BuildContext context, ColorScheme cs, TextTheme tt) {
    final selectedPreset = ref.watch(selectedPresetProvider);
    final hasFile = _selectedFilePath != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Add files panel
        AddFilesPanel(onFilesSelected: (paths) => _onFilesSelected(paths, ref)),

        // File info + thumbnail preview
        if (_selectedFileInfo != null) ...[
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final stackPreview =
                  _thumbnailPath != null && constraints.maxWidth < 560;
              final preview =
                  _thumbnailPath == null
                      ? null
                      : ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        child: SizedBox(
                          width: stackPreview ? double.infinity : 172,
                          height: stackPreview ? 120 : null,
                          child: Image.file(
                            File(_thumbnailPath!),
                            fit: BoxFit.cover,
                            errorBuilder:
                                (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      );
              final infoCard = MediaInfoCard(
                info: _selectedFileInfo!,
                footer: FilledButton.icon(
                  onPressed: () => _openInEditor(context),
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: Text(
                    'converter.editor.openInEditor'.tr(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentHighlight,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    minimumSize: const Size(0, 38),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    alignment: Alignment.center,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                  ),
                ),
                onRemove:
                    () => setState(() {
                      _selectedFileInfo = null;
                      _selectedFilePath = null;
                      _thumbnailPath = null;
                    }),
              );

              if (stackPreview) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (preview != null) ...[
                      preview,
                      const SizedBox(height: 10),
                    ],
                    infoCard,
                  ],
                );
              }

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (preview != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: preview,
                      ),
                    Expanded(child: infoCard),
                  ],
                ),
              );
            },
          ),
        ],

        // Probing indicator
        if (_isProbing) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                'converter.analyzing'.tr(),
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],

        // Preset grid (always visible — select preset before or after adding file)
        const SizedBox(height: 14),
        ForgePresetView(
          onPresetSelected:
              (preset) =>
                  _onPresetSelected(preset, ref, ref.read(isPremiumProvider)),
        ),

        // Configuration panel (visible after preset + file selection)
        if (selectedPreset != null && hasFile) ...[
          const SizedBox(height: 14),
          ForgeConfigView(
            selectedPreset: selectedPreset,
            selectedFileInfo: _selectedFileInfo,
            concatFiles: _concatFiles,
            selectedColorEffectId: _selectedColorEffectId,
            onConcatFilesChanged: (files) {
              setState(() => _concatFiles = files);
              ref
                  .read(conversionConfigProvider.notifier)
                  .setConfig(
                    ref
                        .read(conversionConfigProvider)
                        .copyWith(
                          concatFiles: files.isEmpty ? null : files,
                          clearConcatFiles: files.isEmpty,
                        ),
                  );
            },
            onColorEffectChanged:
                (id) => setState(() => _selectedColorEffectId = id),
            onStartConversion: () => _startConversion(ref),
          ),
        ],
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Queue section
  // ══════════════════════════════════════════════════════════════

  Widget _buildQueueSection(
    BuildContext context,
    ColorScheme cs,
    TextTheme tt,
  ) {
    final jobs = ref.watch(conversionQueueProvider);
    final activeJobs = jobs.where((j) => !j.status.isTerminal).toList();
    final completedJobs = jobs.where((j) => j.status.isTerminal).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Queue header
        Row(
          children: [
            Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.statusDownloading,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'converter.activeConversions'.tr(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
                color: cs.onSurface,
              ),
            ),
            if (activeJobs.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.statusDownloading.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${activeJobs.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.statusDownloading,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),

        // Active jobs
        if (activeJobs.isNotEmpty)
          ...activeJobs.asMap().entries.map((entry) {
            final i = entry.key;
            final job = entry.value;
            final queue = ref.read(conversionQueueProvider.notifier);
            return Padding(
              padding: EdgeInsets.only(top: i > 0 ? 6 : 0),
              child: ConversionJobCard(
                job: job,
                onCancel: () => queue.cancelJob(job.id),
                onViewLog: () => _showJobLog(job.id, job.inputFilename),
                onMoveToTop:
                    job.status == ConversionStatus.queued
                        ? () => queue.moveJobToTop(job.id)
                        : null,
                onMoveUp:
                    job.status == ConversionStatus.queued
                        ? () => queue.moveJobUp(job.id)
                        : null,
                onMoveDown:
                    job.status == ConversionStatus.queued
                        ? () => queue.moveJobDown(job.id)
                        : null,
              ),
            );
          })
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                'converter.noConversions'.tr(),
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),

        // Completed / History
        if (completedJobs.isNotEmpty) ...[
          const SizedBox(height: 18),
          _HistoryHeader(
            count: completedJobs.length,
            expanded: _historyExpanded,
            onToggle:
                () => setState(() => _historyExpanded = !_historyExpanded),
            onClear: () => _clearCompleted(ref),
          ),
          if (_historyExpanded) ...[
            const SizedBox(height: 8),
            ...completedJobs.asMap().entries.map((entry) {
              final i = entry.key;
              final job = entry.value;
              final queue = ref.read(conversionQueueProvider.notifier);
              return Padding(
                padding: EdgeInsets.only(top: i > 0 ? 6 : 0),
                child: ConversionJobCard(
                  job: job,
                  onRetry: () => queue.retryJob(job.id),
                  onRemove: () => queue.removeJob(job.id),
                  onPlay:
                      job.status == ConversionStatus.completed &&
                              FileUtils.isMediaFile(job.outputFilename)
                          ? () => _playConvertedOutput(job)
                          : null,
                  onRevealFile:
                      job.status == ConversionStatus.completed
                          ? () => queue.revealOutputFile(job.id)
                          : null,
                  onOpenFolder:
                      job.status == ConversionStatus.completed
                          ? () => queue.openOutputFolder(job.id)
                          : null,
                  onViewLog: () => _showJobLog(job.id, job.inputFilename),
                ),
              );
            }),
          ],
        ],
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Shared UI pieces
  // ══════════════════════════════════════════════════════════════

  Widget _buildHeaderRow(BuildContext context, ColorScheme cs, TextTheme tt) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Accent bar
        Container(
          width: 3,
          height: 22,
          decoration: BoxDecoration(
            color: AppColors.accentHighlight,
            borderRadius: BorderRadius.circular(1),
            boxShadow: [
              BoxShadow(
                color: AppColors.accentHighlight.withValues(alpha: 0.5),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'converter.title'.tr(),
              style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
                color: cs.onSurface,
                height: 1.1,
              ),
            ),
          ],
        ),
        const Spacer(),
      ],
    );
  }

  Widget _buildFfmpegWarning(TextTheme tt) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.warningAmber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border(
          left: BorderSide(
            color: AppColors.warningAmber.withValues(alpha: 0.9),
            width: 2.5,
          ),
          top: BorderSide(color: AppColors.warningAmber.withValues(alpha: 0.2)),
          right: BorderSide(
            color: AppColors.warningAmber.withValues(alpha: 0.2),
          ),
          bottom: BorderSide(
            color: AppColors.warningAmber.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: AppColors.warningAmber,
          ),
          const SizedBox(width: 8),
          Text(
            'converter.ffmpegMissingBadge'.tr(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
              color: AppColors.warningAmber,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'converter.ffmpegMissing'.tr(),
              style: tt.bodySmall?.copyWith(
                color: AppColors.warningAmber.withValues(alpha: 0.9),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs, TextTheme tt) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.transform_rounded,
            size: 48,
            color: cs.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'converter.noConversions'.tr(),
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'converter.noConversionsHint'.tr(),
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Business logic (preserved from converter_screen.dart)
  // ══════════════════════════════════════════════════════════════

  void _showJobLog(String jobId, String filename) {
    final repo = ref.read(conversionRepositoryProvider);
    final log = repo.getJobLog(jobId);
    showDialog<void>(
      context: context,
      builder: (_) => FfmpegLogDialog(filename: filename, log: log),
    );
  }

  void _playConvertedOutput(ConversionJob job) {
    final file = File(job.outputPath);
    if (!file.existsSync()) {
      AppSnackBar.error(
        context,
        message: AppLocalizations.converterConvertedFileNotFound,
      );
      return;
    }

    final playbackItem = ConversionPlaybackAdapter.toDownloadEntity(job);
    if (FileUtils.isVideoFile(playbackItem.filename)) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(download: playbackItem),
        ),
      );
      return;
    }

    if (FileUtils.isAudioFile(playbackItem.filename)) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AudioPlayerScreen(download: playbackItem),
        ),
      );
      return;
    }

    if (FileUtils.isImageFile(playbackItem.filename)) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImageViewerScreen(download: playbackItem),
        ),
      );
      return;
    }

    AppSnackBar.warning(
      context,
      message: AppLocalizations.converterFileNotPlayable,
    );
  }

  Future<void> _onFilesSelected(List<String> paths, WidgetRef ref) async {
    if (paths.isEmpty) return;

    final validPaths = <String>[];
    for (final path in paths) {
      if (await File(path).exists()) {
        validPaths.add(path);
      }
    }
    if (validPaths.isEmpty) {
      if (mounted) {
        AppSnackBar.error(context, message: 'converter.fileNotFound'.tr());
      }
      return;
    }

    if (validPaths.length == 1) {
      final path = validPaths.first;
      setState(() {
        _selectedFilePath = path;
        _isProbing = true;
        _selectedFileInfo = null;
        _thumbnailPath = null;
      });

      try {
        final probeUseCase = ref.read(probeMediaUseCaseProvider);
        final result = await probeUseCase.call(path);
        result.when(
          success: (info) {
            if (mounted) {
              setState(() {
                _selectedFileInfo = info;
                _isProbing = false;
              });
              // Extract thumbnail in background
              if (info.hasVideo) {
                ref
                    .read(conversionDatasourceProvider)
                    .getOrExtractInputThumbnail(path)
                    .then((thumbPath) {
                      if (mounted && thumbPath != null) {
                        setState(() => _thumbnailPath = thumbPath);
                      }
                    });
              }
            }
          },
          failure: (error) {
            if (mounted) {
              setState(() => _isProbing = false);
              AppSnackBar.error(
                context,
                message: '${'converter.probeFailed'.tr()}: $error',
              );
            }
          },
        );
      } catch (e) {
        if (mounted) {
          setState(() => _isProbing = false);
          appLogger.error('[Forge] Probe failed', e);
        }
      }
    } else {
      final config = ref.read(conversionConfigProvider);
      final preset = ref.read(selectedPresetProvider);
      final queue = ref.read(conversionQueueProvider.notifier);

      int successCount = 0;
      final errors = <String>[];

      for (final path in validPaths) {
        try {
          await queue.addToQueue(
            inputPath: path,
            config: config,
            presetName: preset?.name,
          );
          successCount++;
        } catch (e) {
          errors.add('${p.basename(path)}: $e');
          appLogger.error('[Forge] Batch add failed for $path', e);
        }
      }

      if (mounted) {
        if (successCount > 0) {
          AppSnackBar.success(
            context,
            message: 'converter.addedToQueue'.tr(
              namedArgs: {'count': '$successCount'},
            ),
          );
        }
        if (errors.isNotEmpty) {
          AppSnackBar.warning(
            context,
            message: 'converter.batchErrors'.tr(
              namedArgs: {'count': '${errors.length}'},
            ),
            duration: const Duration(seconds: 5),
          );
        }
      }
    }
  }

  void _onPresetSelected(
    ConversionPreset preset,
    WidgetRef ref,
    bool isPremium,
  ) {
    if (preset.isPremium && !isPremium) {
      AppSnackBar.premium(
        context,
        message: 'converter.premiumPreset'.tr(),
        action: SnackBarAction(
          label: 'converter.upgrade'.tr(),
          onPressed: () {
            ref
                .read(navigationProvider.notifier)
                .navigateToTab(NavigationConstants.premiumIndex);
          },
        ),
      );
      return;
    }

    ref.read(selectedPresetProvider.notifier).state = preset;
    ref.read(conversionConfigProvider.notifier).setConfig(preset.config);

    setState(() {
      _selectedColorEffectId = null;
      if (preset.id != 'merge_join') _concatFiles = [];
    });
  }

  Future<void> _startConversion(WidgetRef ref) async {
    final filePath = _selectedFilePath;
    if (filePath == null) return;

    final config = ref.read(conversionConfigProvider);
    final preset = ref.read(selectedPresetProvider);
    final queue = ref.read(conversionQueueProvider.notifier);
    final isPremium = ref.read(isPremiumProvider);

    if (preset != null && preset.isPremium && !isPremium) {
      AppSnackBar.premium(context, message: 'converter.premiumRequired'.tr());
      return;
    }

    if (preset?.id == 'merge_join') {
      if (_concatFiles.length < 2) {
        AppSnackBar.warning(
          context,
          message: 'converter.enhance.needTwoFiles'.tr(),
        );
        return;
      }
    }

    if (preset?.id == 'watermark' && config.watermarkPath == null) {
      AppSnackBar.warning(
        context,
        message: 'converter.enhance.selectImage'.tr(),
      );
      return;
    }

    if (preset?.id == 'burn_subtitles' && config.subtitlePath == null) {
      AppSnackBar.warning(
        context,
        message: 'converter.enhance.selectSubtitle'.tr(),
      );
      return;
    }

    try {
      await queue.addToQueue(
        inputPath: filePath,
        config: config,
        mediaInfo: _selectedFileInfo,
        presetName: preset?.name,
        outputDir: ref.read(converterOutputDirProvider),
      );

      setState(() {
        _selectedFilePath = null;
        _selectedFileInfo = null;
        _concatFiles = [];
        _selectedColorEffectId = null;
      });

      if (mounted) {
        AppSnackBar.success(context, message: 'converter.startConversion'.tr());
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(
          context,
          message: '${'converter.conversionError'.tr()}: $e',
        );
      }
    }
  }

  void _openInEditor(BuildContext context) {
    if (_selectedFilePath == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => EditorScreen(
              filePath: _selectedFilePath!,
              mediaInfo: _selectedFileInfo,
            ),
      ),
    );
  }

  void _clearCompleted(WidgetRef ref) {
    ref.read(conversionQueueProvider.notifier).clearCompleted();
  }
}

/// History section header with count badge, expand/collapse, clear button.
class _HistoryHeader extends StatelessWidget {
  final int count;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onClear;

  const _HistoryHeader({
    required this.count,
    required this.expanded,
    required this.onToggle,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            AnimatedRotation(
              turns: expanded ? 0.0 : -0.25,
              duration: const Duration(milliseconds: 180),
              child: Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'converter.history'.tr(),
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.cleaning_services_rounded, size: 14),
              label: Text(
                'converter.clearCompleted'.tr(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
