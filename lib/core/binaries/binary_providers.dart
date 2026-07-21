import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/presentation/providers/settings_provider.dart';
import '../providers/backend_providers.dart';
import 'binary_downloader.dart';
import 'binary_manager.dart';
import 'binary_type.dart';
import 'binary_update_history_service.dart';
import 'update_schedule_service.dart';
import 'ytdlp_version_service.dart';

/// Provider for BinaryManager singleton
final binaryManagerProvider = Provider<BinaryManager>((ref) {
  final manager = BinaryManager();
  // DL-016 — repair-outcome telemetry: the per-device EVENT SEQUENCE
  // (`binary_missing_detected` → `binary_repair_outcome`) is the
  // instrument that confirms/refutes the AV-quarantine hypothesis for
  // the production missing-binary wave (repaired→vanished-again =
  // quarantine; failed = network/provisioning; repaired+silence =
  // transient).
  BinaryManager.telemetryListener = (event, props) {
    ref.read(analyticsServiceProvider).track(event, props);
  };
  ref.onDispose(() => manager.dispose());
  return manager;
});

/// Provider to check if all binaries are available
final allBinariesAvailableProvider = FutureProvider<bool>((ref) async {
  final manager = ref.watch(binaryManagerProvider);
  await manager.initialize();
  return manager.allBinariesAvailable();
});

/// Provider to get missing binaries
final missingBinariesProvider = FutureProvider<List<BinaryType>>((ref) async {
  final manager = ref.watch(binaryManagerProvider);
  await manager.initialize();
  return manager.getMissingBinaries();
});

/// Provider to check if a specific binary is available
final binaryAvailableProvider = FutureProvider.family<bool, BinaryType>((ref, type) async {
  final manager = ref.watch(binaryManagerProvider);
  await manager.initialize();
  return manager.isAvailable(type);
});

/// Provider to get binary path
final binaryPathProvider = FutureProvider.family<String?, BinaryType>((ref, type) async {
  final manager = ref.watch(binaryManagerProvider);
  await manager.initialize();
  return manager.getBinaryPath(type);
});

/// Provider to get binary version
final binaryVersionProvider = FutureProvider.family<String?, BinaryType>((ref, type) async {
  final manager = ref.watch(binaryManagerProvider);
  await manager.initialize();
  return manager.getVersion(type);
});

/// Notifier for tracking binary download progress
class BinaryDownloadNotifier extends StateNotifier<BinaryManagerProgress?> {
  final BinaryManager _manager;

  BinaryDownloadNotifier(this._manager) : super(null);

  /// Download all missing binaries
  Future<void> downloadAllMissing() async {
    await for (final progress in _manager.downloadAllMissing()) {
      state = progress;
    }
  }

  /// Download a specific binary
  Future<void> downloadBinary(BinaryType type) async {
    await for (final progress in _manager.downloadBinary(type)) {
      state = BinaryManagerProgress(
        currentBinary: type,
        currentProgress: progress,
        completedCount: 0,
        totalCount: 1,
        status: progress.status == BinaryDownloadStatus.completed
            ? BinaryManagerStatus.completed
            : progress.status == BinaryDownloadStatus.error
                ? BinaryManagerStatus.error
                : BinaryManagerStatus.downloading,
        error: progress.error,
      );
    }
  }

  void reset() {
    state = null;
  }
}

final binaryDownloadNotifierProvider =
    StateNotifierProvider<BinaryDownloadNotifier, BinaryManagerProgress?>((ref) {
  final manager = ref.watch(binaryManagerProvider);
  return BinaryDownloadNotifier(manager);
});

/// Provider to check if a binary needs update
final binaryNeedsUpdateProvider = FutureProvider.family<bool, BinaryType>((ref, type) async {
  final manager = ref.watch(binaryManagerProvider);
  await manager.initialize();
  return manager.needsUpdate(type);
});

/// Provider to get last update time for a binary
final binaryLastUpdatedProvider = FutureProvider.family<DateTime?, BinaryType>((ref, type) async {
  final manager = ref.watch(binaryManagerProvider);
  await manager.initialize();
  return manager.getLastUpdated(type);
});

/// Provider to trigger auto-update check
/// Call this on app start when autoUpdateYtdlp is enabled
final autoUpdateCheckProvider = FutureProvider<bool>((ref) async {
  final manager = ref.watch(binaryManagerProvider);
  return manager.autoUpdate(maxAgeDays: 7);
});

/// Provider for YtDlpVersionService
final ytdlpVersionServiceProvider = Provider<YtDlpVersionService>((ref) {
  final service = YtDlpVersionService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for UpdateScheduleService
final updateScheduleServiceProvider = Provider<UpdateScheduleService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return UpdateScheduleService(prefs);
});

/// Provider to check if yt-dlp update is available (respects cooldown)
final ytdlpUpdateAvailableProvider = FutureProvider<bool>((ref) async {
  final schedule = ref.watch(updateScheduleServiceProvider);

  // Respect update-check cooldown
  if (!schedule.shouldCheckForUpdate()) {
    return false;
  }

  final manager = ref.watch(binaryManagerProvider);
  await manager.initialize();
  final installedVersion = await manager.getVersion(BinaryType.ytDlp);

  final versionService = ref.watch(ytdlpVersionServiceProvider);
  final updateAvailable = await versionService.isUpdateAvailable(installedVersion);

  // Record check time regardless of result
  await schedule.recordCheckTime();

  return updateAvailable;
});

/// Provider to track yt-dlp update progress (non-null = update in progress)
final ytdlpUpdateProgressProvider = StateProvider<BinaryDownloadProgress?>((ref) => null);

/// Provider for BinaryUpdateHistoryService
final binaryUpdateHistoryServiceProvider = Provider<BinaryUpdateHistoryService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return BinaryUpdateHistoryService(prefs);
});
