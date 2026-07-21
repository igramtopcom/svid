import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/binaries/binary_manager.dart';
import '../../data/datasources/ffmpeg_datasource.dart';
import '../../domain/usecases/trim_video_usecase.dart';

// ==================== TRIM MODE STATE ====================

/// Whether trim mode is active in the video player
final isTrimModeProvider = StateProvider<bool>((ref) => false);

/// In-point (start of trim range), null if not set
final trimStartProvider = StateProvider<Duration?>((ref) => null);

/// Out-point (end of trim range), null if not set
final trimEndProvider = StateProvider<Duration?>((ref) => null);

/// Selected trim mode (fast copy vs precise re-encode)
final trimModeSelectionProvider = StateProvider<TrimMode>((ref) => TrimMode.fast);

// ==================== COMPUTED ====================

/// Duration of the selected trim range
final trimDurationProvider = Provider<Duration?>((ref) {
  final start = ref.watch(trimStartProvider);
  final end = ref.watch(trimEndProvider);
  if (start == null || end == null) return null;
  if (end <= start) return null;
  return end - start;
});

/// Whether the current trim selection is valid for export
final canExportTrimProvider = Provider<bool>((ref) {
  final start = ref.watch(trimStartProvider);
  final end = ref.watch(trimEndProvider);
  if (start == null || end == null) return false;
  if (end <= start) return false;
  return (end - start).inSeconds >= 1;
});

// ==================== DI ====================

/// FFmpeg datasource provider
final ffmpegDatasourceProvider = Provider<FFmpegDatasource>((ref) {
  return FFmpegDatasource(BinaryManager());
});

/// Trim video use case provider
final trimVideoUseCaseProvider = Provider<TrimVideoUseCase>((ref) {
  return TrimVideoUseCase(
    ref.read(ffmpegDatasourceProvider),
    BinaryManager(),
  );
});
