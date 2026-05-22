import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:three_s/services/cloud_service.dart';
import 'package:three_s/services/cloud_video_cache_service.dart';

void main() {
  late Directory tempDir;
  late CloudVideoCacheService service;

  VideoMetadata metadata({String videoId = 'video-123', int fileSize = 4}) {
    return VideoMetadata.fromMap(videoId, {
      'uid': 'uid-redacted',
      'videoId': videoId,
      'fileName': 'clip.mp4',
      'storagePath': 'users/uid-redacted/videos/$videoId/clip.mp4',
      'albumName': 'daily',
      'fileSize': fileSize,
      'uploadStatus': 'completed',
    });
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cloud_video_cache_');
    service = const CloudVideoCacheService();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('cache hit returns canonical local file without download', () async {
    final meta = metadata(fileSize: 4);
    final cachePath = service.canonicalPath(
      appDocumentsDirectory: tempDir,
      videoId: meta.videoId,
    );
    final cachedFile = File(cachePath);
    await cachedFile.parent.create(recursive: true);
    await cachedFile.writeAsBytes(const [1, 2, 3, 4], flush: true);

    var downloadCalls = 0;
    final result = await service.materialize(
      appDocumentsDirectory: tempDir,
      metadata: meta,
      downloader: (_) async {
        downloadCalls++;
        return false;
      },
    );

    expect(result.isSuccess, isTrue);
    expect(result.cacheHit, isTrue);
    expect(result.file!.path, cachePath);
    expect(downloadCalls, 0);
  });

  test('cache miss downloads once into canonical cache', () async {
    final meta = metadata(fileSize: 4);
    var downloadCalls = 0;

    final result = await service.materialize(
      appDocumentsDirectory: tempDir,
      metadata: meta,
      downloader: (localPath) async {
        downloadCalls++;
        await File(localPath).writeAsBytes(const [1, 2, 3, 4], flush: true);
        return true;
      },
    );

    expect(result.isSuccess, isTrue);
    expect(result.cacheHit, isFalse);
    expect(downloadCalls, 1);
    expect(result.file!.path, contains(CloudVideoCacheService.cacheRootName));
    expect(await result.file!.length(), 4);
  });

  test('corrupt cache size mismatch redownloads canonical file', () async {
    final meta = metadata(fileSize: 4);
    final cachePath = service.canonicalPath(
      appDocumentsDirectory: tempDir,
      videoId: meta.videoId,
    );
    final cachedFile = File(cachePath);
    await cachedFile.parent.create(recursive: true);
    await cachedFile.writeAsBytes(const [1, 2], flush: true);

    var downloadCalls = 0;
    final result = await service.materialize(
      appDocumentsDirectory: tempDir,
      metadata: meta,
      downloader: (localPath) async {
        downloadCalls++;
        await File(localPath).writeAsBytes(const [1, 2, 3, 4], flush: true);
        return true;
      },
    );

    expect(result.isSuccess, isTrue);
    expect(result.cacheHit, isFalse);
    expect(downloadCalls, 1);
    expect(await File(cachePath).length(), 4);
  });

  test('downloaded size mismatch fails and removes temp file', () async {
    final meta = metadata(fileSize: 4);

    final result = await service.materialize(
      appDocumentsDirectory: tempDir,
      metadata: meta,
      downloader: (localPath) async {
        await File(localPath).writeAsBytes(const [1, 2, 3], flush: true);
        return true;
      },
    );

    expect(result.isSuccess, isFalse);
    expect(
      result.failureCode,
      CloudVideoCacheFailureCode.cacheFileSizeMismatch,
    );
    final root = service.cacheRoot(tempDir);
    final tempFiles = root.existsSync()
        ? root.listSync(recursive: true).whereType<File>().toList()
        : const <File>[];
    expect(tempFiles, isEmpty);
  });

  test(
    'LRU cleanup evicts oldest files and preserves protected files',
    () async {
      final now = DateTime(2026, 5, 22, 12);
      Future<File> writeCacheFile(
        String videoId,
        int size,
        DateTime modified,
      ) async {
        final path = service.canonicalPath(
          appDocumentsDirectory: tempDir,
          videoId: videoId,
        );
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(List<int>.filled(size, 1), flush: true);
        await file.setLastModified(modified);
        return file;
      }

      final protected = await writeCacheFile(
        'old-protected',
        4,
        now.subtract(const Duration(hours: 3)),
      );
      final old = await writeCacheFile(
        'old',
        4,
        now.subtract(const Duration(hours: 2)),
      );
      final fresh = await writeCacheFile(
        'fresh',
        4,
        now.subtract(const Duration(minutes: 5)),
      );

      final result = await service.cleanupCache(
        appDocumentsDirectory: tempDir,
        maxCacheBytes: 8,
        protectedPaths: <String>[protected.path],
      );

      expect(result.bytesBefore, 12);
      expect(result.bytesAfter, 8);
      expect(result.deletedFileCount, 1);
      expect(result.skippedProtectedCount, 1);
      expect(await protected.exists(), isTrue);
      expect(await old.exists(), isFalse);
      expect(await fresh.exists(), isTrue);
    },
  );
}
