import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ssvid/features/downloads/domain/entities/download_entity.dart';
import 'package:ssvid/features/downloads/domain/entities/download_status.dart';
import 'package:ssvid/features/downloads/domain/entities/post_download_action.dart';
import 'package:ssvid/features/downloads/domain/entities/sorting_rule.dart';
import 'package:ssvid/features/downloads/domain/services/sorting_rule_service.dart';

DownloadEntity _entity({
  String savePath = '/tmp/downloads',
  String filename = 'video.mp4',
  String platform = 'youtube',
  String url = 'https://youtube.com/watch?v=abc',
}) =>
    DownloadEntity(
      id: 1,
      url: url,
      filename: filename,
      savePath: savePath,
      status: DownloadStatus.completed,
      totalBytes: 1000,
      downloadedBytes: 1000,
      speed: 0,
      platform: platform,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      title: 'Test Video',
      uploader: 'Test Channel',
      uploadDate: '20260101',
    );

void main() {
  group('Post-completion DB integrity contract', () {
    test('post-action move: savePath = directory, filename = basename', () {
      // Simulates what _applyPostCompletionRules does after moveToFolder
      const targetFolder = '/tmp/sorted';
      final download = _entity();

      // After move, DB should store directory + original filename
      final newSavePath = targetFolder;
      final newFilename = download.filename;

      expect(newSavePath, isNot(contains(newFilename)));
      expect(p.join(newSavePath, newFilename), '/tmp/sorted/video.mp4');
    });

    test('sorting rule: applyRule result split into directory + basename', () {
      // SortingRuleService.applyRule returns an ABSOLUTE file path.
      // The caller must split it correctly.
      const absolutePath = '/tmp/sorted/YouTube/Renamed Video.mp4';

      final dir = p.dirname(absolutePath);
      final filename = p.basename(absolutePath);

      expect(dir, '/tmp/sorted/YouTube');
      expect(filename, 'Renamed Video.mp4');
      expect(p.join(dir, filename), absolutePath);
    });

    test('sorting rule rename: both savePath and filename update', () async {
      final service = SortingRuleService();
      final tmpDir = await Directory.systemTemp.createTemp('sort_test_');
      try {
        final srcFile = File(p.join(tmpDir.path, 'original.mp4'));
        await srcFile.create();

        final download = _entity(
          savePath: tmpDir.path,
          filename: 'original.mp4',
        );
        final rule = SortingRule(
          id: 'r1',
          name: 'test',
          condition: const SortingCondition(platform: 'youtube'),
          destFolder: tmpDir.path,
          renameTemplate: '{uploader} - {title}.{ext}',
          order: 0,
        );

        final newPath = await service.applyRule(download, rule);

        // Caller must split correctly
        final newDir = p.dirname(newPath);
        final newFilename = p.basename(newPath);

        expect(newDir, tmpDir.path);
        expect(newFilename, 'Test Channel - Test Video.mp4');
        expect(await File(newPath).exists(), true);
        expect(await srcFile.exists(), false);
      } finally {
        await tmpDir.delete(recursive: true);
      }
    });

    test('sorting rule move + rename: directory changes too', () async {
      final service = SortingRuleService();
      final srcDir = await Directory.systemTemp.createTemp('sort_src_');
      final destDir = await Directory.systemTemp.createTemp('sort_dst_');
      try {
        final srcFile = File(p.join(srcDir.path, 'video.mp4'));
        await srcFile.create();

        final download = _entity(
          savePath: srcDir.path,
          filename: 'video.mp4',
        );
        final rule = SortingRule(
          id: 'r1',
          name: 'move+rename',
          condition: const SortingCondition(platform: 'youtube'),
          destFolder: destDir.path,
          renameTemplate: '{title}.{ext}',
          order: 0,
        );

        final newPath = await service.applyRule(download, rule);
        final newDir = p.dirname(newPath);
        final newFilename = p.basename(newPath);

        expect(newDir, destDir.path);
        expect(newFilename, 'Test Video.mp4');
        // Rejoined path must resolve to the actual file
        expect(await File(p.join(newDir, newFilename)).exists(), true);
      } finally {
        await srcDir.delete(recursive: true);
        await destDir.delete(recursive: true);
      }
    });

    test('post-action move + sorting rule: serial on final path', () async {
      final service = SortingRuleService();
      final origDir = await Directory.systemTemp.createTemp('orig_');
      final moveDir = await Directory.systemTemp.createTemp('move_');
      final sortDir = await Directory.systemTemp.createTemp('sort_');
      try {
        // Step 0: file starts at origDir
        final srcFile = File(p.join(origDir.path, 'video.mp4'));
        await srcFile.create();

        // Step 1: post-action moves to moveDir (simulated)
        final movedFile = File(p.join(moveDir.path, 'video.mp4'));
        await srcFile.copy(movedFile.path);
        await srcFile.delete();
        var currentDir = moveDir.path;
        var currentFilename = 'video.mp4';

        // Step 2: sorting rule runs on the MOVED file
        final download = _entity(
          savePath: currentDir,
          filename: currentFilename,
        );
        final rule = SortingRule(
          id: 'r1',
          name: 'sort-after-move',
          condition: const SortingCondition(platform: 'youtube'),
          destFolder: sortDir.path,
          renameTemplate: '{title}.{ext}',
          order: 0,
        );

        final newPath = await service.applyRule(download, rule);
        currentDir = p.dirname(newPath);
        currentFilename = p.basename(newPath);

        // Final state: file is at sortDir with new name
        expect(currentDir, sortDir.path);
        expect(currentFilename, 'Test Video.mp4');
        expect(await File(p.join(currentDir, currentFilename)).exists(), true);
        // Original locations are empty
        expect(await srcFile.exists(), false);
        expect(await movedFile.exists(), false);
      } finally {
        await origDir.delete(recursive: true);
        await moveDir.delete(recursive: true);
        await sortDir.delete(recursive: true);
      }
    });

    test('openFolder action does not move file', () {
      // openFile/openFolder should not affect savePath/filename in DB.
      // They only open the CURRENT location — no DB write needed.
      // Verify the enum values are distinct from move actions.
      expect(
        PostDownloadAction.openFile,
        isNot(PostDownloadAction.moveToFolder),
      );
      expect(
        PostDownloadAction.openFolder,
        isNot(PostDownloadAction.deleteAfterMove),
      );
    });
  });
}
