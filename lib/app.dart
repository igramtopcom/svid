import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import 'core/core.dart';
import 'core/binaries/binaries.dart';
import 'core/providers/backend_providers.dart';
import 'core/providers/notification_center_provider.dart';
import 'core/services/error_reporter_service.dart';
import 'core/services/notification_center_service.dart';
import 'core/services/windows_backdrop_service.dart';
import 'core/widgets/update_dialog.dart';
import 'features/floating_capture/data/datasources/desktop_multi_window_floating_window.dart';
import 'features/floating_capture/presentation/providers/floating_capture_providers.dart';
import 'features/settings/presentation/providers/settings_provider.dart';

/// svid Desktop Application
/// High-performance video downloader powered by Rust + Flutter
class SvidApp extends ConsumerWidget {
  const SvidApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final errorReporter = ref.read(errorReporterServiceProvider);
    final navObserver = errorReporter.navigationObserver;
    unawaited(WindowsBackdropService.instance.syncThemeMode(themeMode));

    // ── Locale wiring (per reviewer Codex round-8 finding) ─────────────
    // EasyLocalization owns the user-selected locale, but `intl`
    // (DateFormat etc.) and the floating-capture popup engine read from
    // separate stores. Mirror the in-app locale into both whenever
    // build() runs (which fires on locale change because we depend on
    // context.locale below).
    final code = context.locale.languageCode;
    intl.Intl.defaultLocale = context.locale.toLanguageTag();
    // Push to the popup engine — the supported set is clamped inside
    // the floating window adapter so unsupported codes degrade to en.
    try {
      final fw = ref.read(floatingWindowProvider);
      if (fw is DesktopMultiWindowFloatingWindow) {
        fw.localeCode = const {
          'en','vi','es','pt','ja','ko','zh','de','fr','ru',
          'ar','hi','id','th','tr',
        }.contains(code) ? code : 'en';
      }
    } catch (_) {
      // Floating window provider not yet initialized at first frame —
      // safe to skip; spawn-time fallback uses Platform.localeName.
    }

    return MaterialApp(
      title: AppConstants.appName,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      navigatorObservers: [if (navObserver != null) navObserver],

      // Localization support
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,

      home: const _AppEntryPoint(),
    );
  }
}

/// Entry point that checks binary availability before showing main app
class _AppEntryPoint extends ConsumerStatefulWidget {
  const _AppEntryPoint();

  @override
  ConsumerState<_AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends ConsumerState<_AppEntryPoint> {
  bool _binariesReady = false;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkBinaries();
  }

  Future<void> _checkBinaries() async {
    final manager = ref.read(binaryManagerProvider);
    await manager.initialize();

    final allAvailable = await manager.allBinariesAvailable();

    if (mounted) {
      setState(() {
        _binariesReady = allAvailable;
        _isChecking = false;
      });

      // If binaries are available, trigger background auto-update check
      if (allAvailable) {
        _triggerAutoUpdateIfEnabled();
      }

      // Orphan cleanup (.part/.ytdl) is NOT run on startup to avoid
      // macOS TCC permission prompts. Users can clean up manually via
      // Settings → Downloads → "Orphaned Files" section.
    }
  }

  /// Smart auto-update: 2h cooldown → GitHub API version check → safe download
  void _triggerAutoUpdateIfEnabled() {
    final settings = ref.read(settingsProvider);
    if (!settings.autoUpdateYtdlp) return;

    _performSmartUpdate();
  }

  Future<void> _performSmartUpdate() async {
    try {
      // Step 1: Check 2h cooldown
      final schedule = ref.read(updateScheduleServiceProvider);
      if (!schedule.shouldCheckForUpdate()) {
        debugPrint('⏳ [App] yt-dlp update check skipped (cooldown active)');
        return;
      }

      // Step 2: Compare installed vs latest version
      final manager = ref.read(binaryManagerProvider);
      await manager.initialize();
      final installedVersion = await manager.getVersion(BinaryType.ytDlp);

      final versionService = ref.read(ytdlpVersionServiceProvider);
      final updateAvailable = await versionService.isUpdateAvailable(
        installedVersion,
      );

      // Record check time regardless of result
      await schedule.recordCheckTime();

      if (!updateAvailable) {
        debugPrint('✅ [App] yt-dlp is up to date ($installedVersion)');
        return;
      }

      debugPrint('🔄 [App] yt-dlp update available, starting safe update...');

      // Step 3: Perform safe update with progress tracking
      await for (final progress in manager.updateBinarySafely(
        BinaryType.ytDlp,
      )) {
        if (mounted) {
          ref.read(ytdlpUpdateProgressProvider.notifier).state = progress;
        }

        if (progress.status == BinaryDownloadStatus.completed) {
          // Get new version for notification
          final newVersion = await manager.getVersion(BinaryType.ytDlp);
          debugPrint('✅ [App] yt-dlp updated to $newVersion');

          // Invalidate version providers
          ref.invalidate(binaryVersionProvider(BinaryType.ytDlp));

          // Log success to history
          if (mounted) {
            final historyService = ref.read(binaryUpdateHistoryServiceProvider);
            historyService.addSuccess(
              binaryType: BinaryType.ytDlp,
              oldVersion: installedVersion,
              newVersion: newVersion,
            );
          }

          // Send success notification
          if (mounted) {
            final notificationService = ref.read(
              notificationCenterServiceProvider,
            );
            notificationService.add(
              AppNotificationType.ytdlpUpdateCompleted,
              AppLocalizations.ytdlpUpdateCompleted,
              AppLocalizations.ytdlpUpdateCompletedBody(
                newVersion ?? 'unknown',
              ),
            );
          }
        } else if (progress.status == BinaryDownloadStatus.error) {
          final errorCode = BinaryUpdateErrorCodeX.classify(
            progress.error ?? '',
          );
          debugPrint(
            '⚠️ [App] yt-dlp update failed: ${progress.error} (code: ${errorCode.name})',
          );

          // Log failure to history
          if (mounted) {
            final historyService = ref.read(binaryUpdateHistoryServiceProvider);
            historyService.addFailure(
              binaryType: BinaryType.ytDlp,
              errorCode: errorCode,
              oldVersion: installedVersion,
              errorDetail: progress.error,
            );
          }

          // Send failure notification with hint
          if (mounted) {
            final notificationService = ref.read(
              notificationCenterServiceProvider,
            );
            final body =
                '${progress.error ?? AppLocalizations.ytdlpUpdateFailedBody}\n${errorCode.hint}';
            notificationService.add(
              AppNotificationType.ytdlpUpdateFailed,
              AppLocalizations.ytdlpUpdateFailed,
              body,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ [App] Smart auto-update failed: $e');
    } finally {
      // Clear progress indicator
      if (mounted) {
        ref.read(ytdlpUpdateProgressProvider.notifier).state = null;
      }
    }
  }

  void _onSetupComplete() {
    setState(() {
      _binariesReady = true;
    });

    // After setup complete, also trigger auto-update check
    _triggerAutoUpdateIfEnabled();
  }

  @override
  Widget build(BuildContext context) {
    // Show branded splash while validating binaries (few hundred ms).
    // A bare spinner looks broken; the logo makes cold start feel intentional.
    if (_isChecking) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/brands/${BrandConfig.current.brand.name}/app_icon.png',
                width: 64,
                height: 64,
              ),
              const SizedBox(height: 16),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ),
        ),
      );
    }

    // Show setup screen if binaries are missing
    if (!_binariesReady) {
      return BinarySetupScreen(onSetupComplete: _onSetupComplete);
    }

    // Show main app. Mandatory app updates are enforced globally here so
    // users cannot bypass a required release by navigating away from Home.
    return const _MandatoryUpdateGate(child: AppScaffold());
  }
}

class _MandatoryUpdateGate extends ConsumerWidget {
  const _MandatoryUpdateGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(appUpdateProvider);
    if (update == null || !update.updateAvailable || !update.isMandatory) {
      return child;
    }

    return Stack(
      children: [
        child,
        ModalBarrier(
          dismissible: false,
          color: Colors.black.withValues(alpha: 0.64),
        ),
        Center(
          child: UpdateDialog(
            currentVersion: update.currentVersion,
            latestVersion: update.latestVersion ?? '',
            releaseNotes: update.releaseNotes,
            downloadUrl: update.downloadUrl,
            checksum: update.checksum,
            isMandatory: true,
          ),
        ),
      ],
    );
  }
}
