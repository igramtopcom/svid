import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../constants/app_spacing.dart';
import 'shimmer.dart';

/// Reusable cached image with shimmer loading and error fallback.
/// Supports both network URLs (http/https) and local file paths.
class AppCachedImage extends StatelessWidget {
  final String? imageUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? errorWidget;

  const AppCachedImage({
    super.key,
    required this.imageUrl,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.errorWidget,
  });

  static final RegExp _windowsDrivePattern = RegExp(r'^[a-zA-Z]:[\\/]');
  static final RegExp _windowsFileUriPathPattern = RegExp(r'^/[a-zA-Z]:[\\/]');

  static bool isLocalPath(String? url) {
    if (url == null || url.isEmpty) return false;
    if (url.startsWith('/') ||
        url.startsWith(r'\\') ||
        url.startsWith('file://')) {
      return true;
    }
    return _windowsDrivePattern.hasMatch(url);
  }

  static String localFilePath(String url) {
    if (!url.startsWith('file://')) {
      return url;
    }

    final uri = Uri.parse(url);
    final isWindowsFileUri = _windowsFileUriPathPattern.hasMatch(uri.path);
    return uri.toFilePath(windows: isWindowsFileUri);
  }

  static ImageProvider<Object>? imageProviderFor(String url) {
    if (isLocalPath(url)) {
      final file = File(localFilePath(url));
      if (!file.existsSync()) return null;
      return FileImage(file);
    }
    return CachedNetworkImageProvider(url);
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return errorWidget ?? _defaultError(context);
    }

    final Widget image;
    if (isLocalPath(imageUrl)) {
      final filePath = localFilePath(imageUrl!);
      final file = File(filePath);
      if (!file.existsSync()) {
        return errorWidget ?? _defaultError(context);
      }

      image = Image.file(
        file,
        width: width,
        height: height,
        fit: fit,
        errorBuilder:
            (context, error, stack) => errorWidget ?? _defaultError(context),
      );
    } else {
      image = CachedNetworkImage(
        imageUrl: imageUrl!,
        width: width,
        height: height,
        fit: fit,
        placeholder:
            (context, url) => ShimmerPlaceholder(width: width, height: height),
        errorWidget:
            (context, url, error) => errorWidget ?? _defaultError(context),
      );
    }

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return ClipRRect(borderRadius: AppRadius.borderRadius.card, child: image);
  }

  Widget _defaultError(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: borderRadius ?? AppRadius.borderRadius.card,
      ),
      child: Icon(
        Icons.image_not_supported_outlined,
        size: width * 0.3,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
