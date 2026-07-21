import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../../core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/download_entity.dart';
import '../../domain/entities/download_status.dart';
import '../providers/collection_providers.dart';

/// Shows all downloads belonging to a single collection.
class CollectionDetailScreen extends ConsumerWidget {
  final String collectionId;

  const CollectionDetailScreen({super.key, required this.collectionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(collectionsProvider);
    final collectionIdx = collections.indexWhere((c) => c.id == collectionId);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (collectionIdx == -1) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBase,
        appBar: AppBar(
          backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBase,
          surfaceTintColor: Colors.transparent,
        ),
        body: Center(child: Text('collections.notFound'.tr())),
      );
    }
    final collection = collections[collectionIdx];
    final downloads = ref.watch(collectionDownloadsProvider(collectionId));

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBase,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBase,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(collection.name),
            if (downloads.isNotEmpty)
              Text(
                'collections.itemCount'
                    .tr(namedArgs: {'count': '${downloads.length}'}),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppOpacity.overlay),
                ),
              ),
          ],
        ),
      ),
      body: downloads.isEmpty
          ? AppEmptyWidget(
              icon: Icons.inbox_outlined,
              title: 'collections.noItems'.tr(),
              subtitle: 'collections.emptySubtitle'.tr(),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: downloads.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final d = downloads[index];
                return _CollectionDownloadTile(download: d, isDark: isDark);
              },
            ),
    );
  }
}

class _CollectionDownloadTile extends ConsumerWidget {
  final DownloadEntity download;
  final bool isDark;

  const _CollectionDownloadTile({required this.download, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.smMd),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface1 : AppColors.lightElevated,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: isDark ? Border.all(color: AppColors.darkElevated) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: AppOpacity.divider),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          _buildThumbnail(),
          const SizedBox(width: AppSpacing.smMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  download.title ?? download.filename,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  [
                    download.uploader ?? '',
                    download.platform,
                    download.qualityLabel ?? '',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: AppOpacity.overlay),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _buildStatus(context),
        ],
      ),
    );
  }

  Widget _buildThumbnail() {
    if (download.thumbnail != null && download.thumbnail!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: AppCachedImage(
          imageUrl: download.thumbnail,
          width: 56,
          height: 32,
          errorWidget: _FallbackIcon(isDark: isDark),
        ),
      );
    }
    return _FallbackIcon(isDark: isDark);
  }

  Widget _buildStatus(BuildContext context) {
    final color = switch (download.status) {
      DownloadStatus.completed => AppColors.statusCompleted(context),
      DownloadStatus.failed => AppColors.statusFailed(context),
      DownloadStatus.paused => AppColors.statusPaused(context),
      DownloadStatus.downloading => AppColors.statusActive(context),
      _ => Theme.of(context).colorScheme.onSurface.withValues(alpha: AppOpacity.medium),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppOpacity.pressed),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Text(
        download.status.name,
        style: AppTypography.compact.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _FallbackIcon extends StatelessWidget {
  final bool isDark;
  const _FallbackIcon({required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
        width: 56,
        height: 32,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkElevated : AppColors.lightSurface2,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Icon(Icons.video_file_outlined, size: 16,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppOpacity.medium)),
      );
}
