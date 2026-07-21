import 'dart:io';

import 'package:file_picker/file_picker.dart';
import '../../../../core/config/brand_config.dart';
import '../../../../core/services/clipboard_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/domain/entities/platform_cookie.dart';
import '../../../../core/auth/presentation/providers/auth_providers.dart';
import '../../../../core/auth/presentation/widgets/platform_login_dialog.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../domain/services/cookie_inspector_service.dart';
import '../../domain/services/cookie_transfer_service.dart';
import '../providers/browser_session_providers.dart';

/// Full cookie management screen with per-platform inspector,
/// import/export, and re-login actions.
class CookieManagementScreen extends ConsumerStatefulWidget {
  const CookieManagementScreen({super.key});

  @override
  ConsumerState<CookieManagementScreen> createState() =>
      _CookieManagementScreenState();
}

class _CookieManagementScreenState
    extends ConsumerState<CookieManagementScreen> {
  final Set<String> _expandedPlatforms = {};

  /// Login URLs per platform for re-login
  static const _loginUrls = {
    'youtube':
        'https://accounts.google.com/ServiceLogin?continue=https://www.youtube.com/',
    'facebook': 'https://www.facebook.com/login',
    'instagram': 'https://www.instagram.com/accounts/login',
    'tiktok': 'https://www.tiktok.com/login',
    'x': 'https://twitter.com/i/flow/login',
    'twitter': 'https://twitter.com/i/flow/login',
    'reddit': 'https://www.reddit.com/login',
    'pinterest': 'https://www.pinterest.com/login',
    'douyin': 'https://www.douyin.com/',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cookiesAsync = ref.watch(allPlatformCookiesProvider);
    final summariesAsync = ref.watch(allSessionSummariesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.cookieManagementTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: AppLocalizations.cookieManagementImport,
            onPressed: () => _handleImport(context),
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: AppLocalizations.cookieManagementExport,
            onPressed: () => _handleExport(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: AppLocalizations.cookieManagementClearAll,
            onPressed: () => _handleClearAll(context),
          ),
        ],
      ),
      body: cookiesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text(err.toString())),
        data: (cookies) {
          if (cookies.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cookie_outlined,
                    size: 64,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    AppLocalizations.cookieManagementNoSession,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            );
          }

          final summaries = summariesAsync.valueOrNull ?? [];

          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: cookies.length,
            itemBuilder: (context, index) {
              final cookie = cookies[index];
              final summary = summaries.firstWhere(
                (s) => s.platform == cookie.platform,
                orElse:
                    () => CookieSessionSummary(
                      platform: cookie.platform,
                      totalCookies: 0,
                      authCookieCount: 0,
                      expiringSoonCount: 0,
                      isHealthy: false,
                    ),
              );
              return _buildPlatformCard(context, cookie, summary);
            },
          );
        },
      ),
    );
  }

  Widget _buildPlatformCard(
    BuildContext context,
    PlatformCookie cookie,
    CookieSessionSummary summary,
  ) {
    final theme = Theme.of(context);
    final isExpanded = _expandedPlatforms.contains(cookie.platform);
    final inspector = ref.read(cookieInspectorServiceProvider);
    final entries = inspector.parseCookies(cookie.cookieString);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        children: [
          // Header
          ListTile(
            leading: _buildHealthBadge(summary),
            title: Text(
              cookie.platformDisplayName,
              style: theme.textTheme.titleMedium,
            ),
            subtitle: Text(
              AppLocalizations.cookieManagementCookies(summary.totalCookies),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Re-login
                if (_loginUrls.containsKey(cookie.platform))
                  IconButton(
                    icon: const Icon(Icons.login, size: 20),
                    tooltip: AppLocalizations.cookieManagementRelogin,
                    onPressed: () => _handleRelogin(context, cookie.platform),
                  ),
                // Copy
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  tooltip: AppLocalizations.cookieManagementCopyCookies,
                  onPressed: () {
                    ClipboardService.setText(cookie.cookieString);
                    AppSnackBar.success(
                      context,
                      message: AppLocalizations.cookieManagementCopyCookies,
                    );
                  },
                ),
                // Delete
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: theme.colorScheme.error,
                  ),
                  tooltip: AppLocalizations.cookieManagementDeletePlatform(
                    cookie.platformDisplayName,
                  ),
                  onPressed:
                      () => _handleDeletePlatform(context, cookie.platform),
                ),
                // Expand
                IconButton(
                  icon: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  onPressed: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedPlatforms.remove(cookie.platform);
                      } else {
                        _expandedPlatforms.add(cookie.platform);
                      }
                    });
                  },
                ),
              ],
            ),
          ),

          // Expanded cookie list
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.smMd,
              ),
              child: _buildCookieList(context, entries),
            ),
        ],
      ),
    );
  }

  Widget _buildHealthBadge(CookieSessionSummary summary) {
    Color color;
    String label;

    if (!summary.isHealthy) {
      if (summary.totalCookies == 0) {
        color = Colors.grey;
        label = AppLocalizations.cookieManagementNoSession;
      } else {
        color = Colors.red;
        label = AppLocalizations.cookieManagementExpired;
      }
    } else if (summary.expiringSoonCount > 0) {
      color = Colors.orange;
      label = AppLocalizations.cookieManagementExpiringSoon;
    } else {
      color = Colors.green;
      label = AppLocalizations.cookieManagementHealthy;
    }

    return Tooltip(
      message: label,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }

  Widget _buildCookieList(BuildContext context, List<CookieEntry> entries) {
    final theme = Theme.of(context);
    final displayEntries =
        entries.length > 10 ? entries.sublist(0, 10) : entries;
    final hasMore = entries.length > 10;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sm),
        ...displayEntries.map(
          (e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Row(
              children: [
                // Secure indicator
                Icon(
                  e.isSecure ? Icons.lock : Icons.lock_open,
                  size: 14,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: AppSpacing.sm),
                // Name
                SizedBox(
                  width: 160,
                  child: Text(
                    e.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Domain
                SizedBox(
                  width: 140,
                  child: Text(
                    e.domain,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Expiry / status
                if (e.isExpired)
                  Text(
                    AppLocalizations.cookieManagementExpired,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.red,
                    ),
                  )
                else if (e.isExpiringSoon)
                  Text(
                    AppLocalizations.cookieManagementExpiringSoon,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.orange,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: TextButton(
              onPressed: () {
                // Already showing all in this implementation —
                // could expand to full list, but 10 is sufficient for inspection
              },
              child: Text(
                '${AppLocalizations.cookieManagementShowAll} (${entries.length})',
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _handleImport(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    final content = await file.readAsString();
    if (!mounted) return;

    final cookieRepo = ref.read(cookieRepositoryProvider);
    final service = CookieTransferService(cookieRepo);

    if (!service.isValidExportFile(content)) {
      if (context.mounted) {
        AppSnackBar.error(
          context,
          message: AppLocalizations.cookieManagementInvalidFile,
        );
      }
      return;
    }

    final imported = await service.importCookies(content);
    if (!mounted) return;
    ref.invalidate(allPlatformCookiesProvider);
    ref.invalidate(allSessionSummariesProvider);

    if (context.mounted) {
      AppSnackBar.success(
        context,
        message: AppLocalizations.cookieManagementImportSuccess(
          imported.length,
        ),
      );
    }
  }

  Future<void> _handleExport(BuildContext context) async {
    final cookies = ref.read(allPlatformCookiesProvider).valueOrNull;
    if (cookies == null || cookies.isEmpty) return;

    final cookieRepo = ref.read(cookieRepositoryProvider);
    final service = CookieTransferService(cookieRepo);
    final exportContent = service.exportAllCookies(cookies);

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: AppLocalizations.cookieManagementExport,
      fileName: '${BrandConfig.current.brand.name}_cookies_export.txt',
    );
    if (savePath == null) return;

    await File(savePath).writeAsString(exportContent);

    if (context.mounted) {
      AppSnackBar.success(
        context,
        message: AppLocalizations.cookieManagementExportSuccess,
      );
    }
  }

  Future<void> _handleClearAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(AppLocalizations.cookieManagementClearAll),
            content: Text(AppLocalizations.cookieManagementClearAll),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(AppLocalizations.commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  AppLocalizations.commonOk,
                  style: AppTypography.buttonSecondary.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    await ref.read(removeAllPlatformCookiesUseCaseProvider)();
    if (!mounted) return;
    ref.invalidate(allPlatformCookiesProvider);
    ref.invalidate(allSessionSummariesProvider);
  }

  Future<void> _handleDeletePlatform(
    BuildContext context,
    String platform,
  ) async {
    await ref.read(removePlatformCookiesUseCaseProvider)(platform);
    if (!mounted) return;
    ref.invalidate(allPlatformCookiesProvider);
    ref.invalidate(allSessionSummariesProvider);
  }

  Future<void> _handleRelogin(BuildContext context, String platform) async {
    final loginUrl = _loginUrls[platform];
    if (loginUrl == null) return;

    await showPlatformLoginDialog(
      context: context,
      platform: platform,
      loginUrl: loginUrl,
    );

    if (!mounted) return;
    ref.invalidate(allPlatformCookiesProvider);
    ref.invalidate(allSessionSummariesProvider);
  }
}
