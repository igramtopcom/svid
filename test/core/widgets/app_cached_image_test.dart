import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/widgets/app_cached_image.dart';

void main() {
  group('AppCachedImage local path handling', () {
    test('detects Windows drive-letter paths as local files', () {
      expect(
        AppCachedImage.isLocalPath(
          r'c:/Users/RIVERNET/AppData/Roaming/VidCombo/VidCombo/legacy_thumbnails/14.jpg',
        ),
        isTrue,
      );
      expect(
        AppCachedImage.imageProviderFor(
          r'c:/Users/RIVERNET/AppData/Roaming/VidCombo/VidCombo/legacy_thumbnails/14.jpg',
        ),
        isNull,
      );
    });

    test('detects file URIs as local files', () async {
      final tempDir = await Directory.systemTemp.createTemp('cached_image_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final imageFile = File('${tempDir.path}/thumb.jpg');
      imageFile.writeAsBytesSync(<int>[1, 2, 3]);

      final provider = AppCachedImage.imageProviderFor(
        imageFile.uri.toString(),
      );

      expect(provider, isA<FileImage>());
      final fileProvider = provider as FileImage;
      expect(fileProvider.file.path, imageFile.path);
    });

    testWidgets(
      'renders fallback instead of FileImage for missing local file',
      (tester) async {
        const fallbackKey = ValueKey<String>('missing-local-fallback');
        final missingPath =
            '${Directory.systemTemp.path}/legacy_thumbnails_missing_404.jpg';

        await tester.pumpWidget(
          MaterialApp(
            home: AppCachedImage(
              imageUrl: missingPath,
              width: 80,
              height: 45,
              errorWidget: const SizedBox(key: fallbackKey),
            ),
          ),
        );

        expect(find.byKey(fallbackKey), findsOneWidget);
        expect(find.byType(Image), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    test('keeps https thumbnails on the network path', () {
      expect(
        AppCachedImage.isLocalPath('https://i.ytimg.com/vi/demo/hqdefault.jpg'),
        isFalse,
      );
      expect(
        AppCachedImage.imageProviderFor(
          'https://i.ytimg.com/vi/demo/hqdefault.jpg',
        ),
        isA<CachedNetworkImageProvider>(),
      );
    });
  });
}
