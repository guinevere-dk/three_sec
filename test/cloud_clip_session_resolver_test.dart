import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:three_s/services/cloud_clip_session_resolver.dart';
import 'package:three_s/services/cloud_service.dart';

void main() {
  late Directory tempDir;
  late FakeMetadataSource metadataSource;
  late FakeDownloadClient downloadClient;
  late CloudClipSessionResolver resolver;

  const placeholder = 'cloud_only://daily/video-123/clip.mp4';

  VideoMetadata metadata({
    String videoId = 'video-123',
    String fileName = 'clip.mp4',
    String storagePath = 'users/uid-redacted/videos/video-123/clip.mp4',
    int fileSize = 4,
    int? durationMs = 2100,
  }) {
    return VideoMetadata.fromMap(videoId, {
      'uid': 'uid-redacted',
      'videoId': videoId,
      'fileName': fileName,
      'storagePath': storagePath,
      'albumName': 'daily',
      'fileSize': fileSize,
      'uploadStatus': 'completed',
      if (durationMs != null) 'durationMs': durationMs,
    });
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'cloud_clip_session_resolver_',
    );
    metadataSource = FakeMetadataSource();
    downloadClient = FakeDownloadClient();
    resolver = CloudClipSessionResolver(
      metadataSource: metadataSource,
      downloadClient: downloadClient,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('parses valid cloud-only placeholder', () {
    final parsed = CloudClipSessionResolver.parsePlaceholder(
      'cloud_only://일상/video-123/clip.mp4',
    );

    expect(parsed, isNotNull);
    expect(parsed!.albumName, '일상');
    expect(parsed.videoId, 'video-123');
    expect(parsed.fileName, 'clip.mp4');
  });

  test('rejects invalid cloud-only placeholders', () {
    expect(
      CloudClipSessionResolver.parsePlaceholder('/local/clip.mp4'),
      isNull,
    );
    expect(CloudClipSessionResolver.parsePlaceholder('cloud_only://'), isNull);
    expect(
      CloudClipSessionResolver.parsePlaceholder('cloud_only://album/video-id'),
      isNull,
    );
    expect(
      CloudClipSessionResolver.parsePlaceholder('cloud_only://album//clip.mp4'),
      isNull,
    );
  });

  test('fails when metadata is missing', () async {
    final result = await resolver.resolve(
      placeholderPath: placeholder,
      appDocumentsDirectory: tempDir,
      purpose: CloudClipSessionPurpose.edit,
    );

    expect(result.isSuccess, isFalse);
    expect(result.failure!.code, CloudClipResolveFailureCode.metadataMissing);
  });

  test('fails when storage path is missing', () async {
    metadataSource.items[placeholder] = metadata(storagePath: '');

    final result = await resolver.resolve(
      placeholderPath: placeholder,
      appDocumentsDirectory: tempDir,
      purpose: CloudClipSessionPurpose.edit,
    );

    expect(result.isSuccess, isFalse);
    expect(
      result.failure!.code,
      CloudClipResolveFailureCode.storagePathMissing,
    );
  });

  test('fails when file size is invalid', () async {
    metadataSource.items[placeholder] = metadata(fileSize: 0);

    final result = await resolver.resolve(
      placeholderPath: placeholder,
      appDocumentsDirectory: tempDir,
      purpose: CloudClipSessionPurpose.edit,
    );

    expect(result.isSuccess, isFalse);
    expect(result.failure!.code, CloudClipResolveFailureCode.invalidFileSize);
  });

  test('builds separate edit and export session cache paths', () {
    final editPath = CloudClipSessionResolver.buildSessionLocalPath(
      appDocumentsDirectory: tempDir,
      purpose: CloudClipSessionPurpose.edit,
      videoId: 'video:123',
      fileName: '../clip.mp4',
    );
    final exportPath = CloudClipSessionResolver.buildSessionLocalPath(
      appDocumentsDirectory: tempDir,
      purpose: CloudClipSessionPurpose.export,
      videoId: 'video:123',
      fileName: '../clip.mp4',
    );

    expect(editPath, contains(CloudClipSessionResolver.cacheRootName));
    expect(editPath, contains('edit_session_cache'));
    expect(
      editPath,
      isNot(contains('vlogs${Platform.pathSeparator}raw_clips')),
    );
    expect(editPath, isNot(exportPath));
    expect(exportPath, contains('export_session_cache'));
  });

  test(
    'downloads a session copy without marking cloud clip as moved',
    () async {
      metadataSource.items[placeholder] = metadata(fileSize: 4);
      downloadClient.bytesToWrite = 4;

      final result = await resolver.resolve(
        placeholderPath: placeholder,
        appDocumentsDirectory: tempDir,
        purpose: CloudClipSessionPurpose.edit,
      );

      expect(result.isSuccess, isTrue);
      expect(result.source!.originalClipPath, placeholder);
      expect(result.source!.videoId, 'video-123');
      expect(result.source!.sessionLocalPath, contains('edit_session_cache'));
      expect(result.source!.duration, const Duration(milliseconds: 2100));
      expect(result.source!.fromCache, isFalse);
      expect(await File(result.source!.sessionLocalPath).length(), 4);
      expect(downloadClient.downloadCalls, 1);
      expect(downloadClient.markMovedToDeviceCalls, 0);
    },
  );

  test('reuses valid session cache without downloading again', () async {
    metadataSource.items[placeholder] = metadata(fileSize: 4);
    final cachedPath = CloudClipSessionResolver.buildSessionLocalPath(
      appDocumentsDirectory: tempDir,
      purpose: CloudClipSessionPurpose.export,
      videoId: 'video-123',
      fileName: 'clip.mp4',
    );
    final cachedFile = File(cachedPath);
    await cachedFile.parent.create(recursive: true);
    await cachedFile.writeAsBytes(const [1, 2, 3, 4], flush: true);

    final result = await resolver.resolve(
      placeholderPath: placeholder,
      appDocumentsDirectory: tempDir,
      purpose: CloudClipSessionPurpose.export,
    );

    expect(result.isSuccess, isTrue);
    expect(result.source!.sessionLocalPath, cachedPath);
    expect(result.source!.fromCache, isTrue);
    expect(downloadClient.downloadCalls, 0);
    expect(downloadClient.markMovedToDeviceCalls, 0);
  });

  test('fails on cache path collision with unexpected size', () async {
    metadataSource.items[placeholder] = metadata(fileSize: 4);
    final cachedPath = CloudClipSessionResolver.buildSessionLocalPath(
      appDocumentsDirectory: tempDir,
      purpose: CloudClipSessionPurpose.edit,
      videoId: 'video-123',
      fileName: 'clip.mp4',
    );
    final cachedFile = File(cachedPath);
    await cachedFile.parent.create(recursive: true);
    await cachedFile.writeAsBytes(const [1, 2], flush: true);

    final result = await resolver.resolve(
      placeholderPath: placeholder,
      appDocumentsDirectory: tempDir,
      purpose: CloudClipSessionPurpose.edit,
    );

    expect(result.isSuccess, isFalse);
    expect(
      result.failure!.code,
      CloudClipResolveFailureCode.cachePathCollision,
    );
    expect(downloadClient.downloadCalls, 0);
  });

  test('fails when download client returns false', () async {
    metadataSource.items[placeholder] = metadata(fileSize: 4);
    downloadClient.shouldSucceed = false;

    final result = await resolver.resolve(
      placeholderPath: placeholder,
      appDocumentsDirectory: tempDir,
      purpose: CloudClipSessionPurpose.export,
    );

    expect(result.isSuccess, isFalse);
    expect(result.failure!.code, CloudClipResolveFailureCode.downloadFailed);
    expect(downloadClient.downloadCalls, 1);
    expect(downloadClient.markMovedToDeviceCalls, 0);
  });

  test('fails when download client does not create a cache file', () async {
    metadataSource.items[placeholder] = metadata(fileSize: 4);

    final result = await resolver.resolve(
      placeholderPath: placeholder,
      appDocumentsDirectory: tempDir,
      purpose: CloudClipSessionPurpose.export,
    );

    expect(result.isSuccess, isFalse);
    expect(result.failure!.code, CloudClipResolveFailureCode.cacheFileMissing);
  });

  test(
    'fails when downloaded cache file size does not match metadata',
    () async {
      metadataSource.items[placeholder] = metadata(fileSize: 4);
      downloadClient.bytesToWrite = 3;

      final result = await resolver.resolve(
        placeholderPath: placeholder,
        appDocumentsDirectory: tempDir,
        purpose: CloudClipSessionPurpose.export,
      );

      expect(result.isSuccess, isFalse);
      expect(
        result.failure!.code,
        CloudClipResolveFailureCode.cacheFileSizeMismatch,
      );
    },
  );

  test('cleanup removes only expired session cache files', () async {
    final oldPath = CloudClipSessionResolver.buildSessionLocalPath(
      appDocumentsDirectory: tempDir,
      purpose: CloudClipSessionPurpose.edit,
      videoId: 'old-video',
      fileName: 'old.mp4',
    );
    final freshPath = CloudClipSessionResolver.buildSessionLocalPath(
      appDocumentsDirectory: tempDir,
      purpose: CloudClipSessionPurpose.export,
      videoId: 'fresh-video',
      fileName: 'fresh.mp4',
    );
    final oldFile = File(oldPath);
    final freshFile = File(freshPath);
    await oldFile.parent.create(recursive: true);
    await freshFile.parent.create(recursive: true);
    await oldFile.writeAsBytes(const [1], flush: true);
    await freshFile.writeAsBytes(const [1], flush: true);

    final now = DateTime(2026, 5, 21, 12);
    await oldFile.setLastModified(now.subtract(const Duration(hours: 25)));
    await freshFile.setLastModified(now.subtract(const Duration(hours: 2)));

    final result = await CloudClipSessionResolver.cleanupExpiredSessionCache(
      appDocumentsDirectory: tempDir,
      now: now,
    );

    expect(result.deletedFileCount, 1);
    expect(result.skippedFreshCount, 1);
    expect(await oldFile.exists(), isFalse);
    expect(await freshFile.exists(), isTrue);
  });

  test('cleanup preserves protected active session cache files', () async {
    final protectedPath = CloudClipSessionResolver.buildSessionLocalPath(
      appDocumentsDirectory: tempDir,
      purpose: CloudClipSessionPurpose.edit,
      videoId: 'active-video',
      fileName: 'active.mp4',
    );
    final protectedFile = File(protectedPath);
    await protectedFile.parent.create(recursive: true);
    await protectedFile.writeAsBytes(const [1], flush: true);

    final now = DateTime(2026, 5, 21, 12);
    await protectedFile.setLastModified(
      now.subtract(const Duration(hours: 25)),
    );

    final result = await CloudClipSessionResolver.cleanupExpiredSessionCache(
      appDocumentsDirectory: tempDir,
      protectedPaths: <String>[protectedPath],
      now: now,
    );

    expect(result.deletedFileCount, 0);
    expect(result.skippedProtectedCount, 1);
    expect(await protectedFile.exists(), isTrue);
  });

  test('session cache path guard only matches cache root', () {
    final cachePath = CloudClipSessionResolver.buildSessionLocalPath(
      appDocumentsDirectory: tempDir,
      purpose: CloudClipSessionPurpose.edit,
      videoId: 'video-123',
      fileName: 'clip.mp4',
    );
    final outsidePath =
        '${tempDir.path}${Platform.pathSeparator}vlog_projects'
        '${Platform.pathSeparator}edit_session_cache.mp4';

    expect(
      CloudClipSessionResolver.isSessionCachePath(
        appDocumentsDirectory: tempDir,
        path: cachePath,
      ),
      isTrue,
    );
    expect(
      CloudClipSessionResolver.isSessionCachePath(
        appDocumentsDirectory: tempDir,
        path: outsidePath,
      ),
      isFalse,
    );
  });
}

class FakeMetadataSource implements CloudClipMetadataSource {
  final items = <String, VideoMetadata>{};

  @override
  VideoMetadata? metadataForCloudOnlyPath(String path) => items[path];
}

class FakeDownloadClient implements CloudClipSessionDownloadClient {
  int downloadCalls = 0;
  int markMovedToDeviceCalls = 0;
  bool shouldSucceed = true;
  int? bytesToWrite;

  @override
  Future<bool> downloadSessionCopy({
    required VideoMetadata metadata,
    required String localPath,
  }) async {
    downloadCalls++;
    if (!shouldSucceed) return false;
    if (bytesToWrite == null) return true;

    final file = File(localPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List<int>.filled(bytesToWrite!, 1), flush: true);
    return true;
  }

  Future<bool> markVideoMovedToDevice(String videoId) async {
    markMovedToDeviceCalls++;
    return true;
  }
}
