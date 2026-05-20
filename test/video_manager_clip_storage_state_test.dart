import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:three_s/managers/video_manager.dart';
import 'package:three_s/services/cloud_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  late VideoManager manager;
  late Directory tempDir;

  Future<File> createClip(String name) async {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(<int>[0, 1, 2, 3], flush: true);
    return file;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    manager = VideoManager();
    await manager.clearUserScopedLocalCache();
    manager.recordedVideoPaths = <String>[];
    manager.debugSetCloudThumbnailFetcher(null);
    manager.debugResetCloudThumbnailRuntimeDebugCounts();
    manager.debugClearCloudThumbnailMemoryCache();
    tempDir = await Directory.systemTemp.createTemp('clip_storage_state_');
  });

  tearDown(() async {
    for (final path in manager.recordedVideoPaths) {
      manager.clearClipTransferUiState(path);
      await manager.unmarkClipCloudSynced(path);
    }
    manager.recordedVideoPaths = <String>[];
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  test('local file exists with no marker is localOnly', () async {
    final clip = await createClip('local_only.mp4');

    expect(manager.getClipStorageState(clip.path), ClipStorageState.localOnly);
    expect(manager.isLocalOnlyClip(clip.path), isTrue);
    expect(manager.isUploadableClip(clip.path), isTrue);
  });

  test(
    'local file with legacy cloud_synced marker is cloudSyncedLocal',
    () async {
      final clip = await createClip('synced.mp4');

      await manager.markClipCloudSynced(clip.path);

      expect(
        manager.getClipStorageState(clip.path),
        ClipStorageState.cloudSyncedLocal,
      );
      expect(manager.isCloudSyncedLocalClip(clip.path), isTrue);
      expect(manager.isUploadableClip(clip.path), isFalse);
    },
  );

  test('cloud_only placeholder is cloudOnly and not a local file', () {
    const placeholder = 'cloud_only://album/video-id/file.mp4';

    expect(
      manager.getClipStorageState(placeholder),
      ClipStorageState.cloudOnly,
    );
    expect(manager.isCloudOnlyClip(placeholder), isTrue);

    final counts = manager.getStorageStateDebugCounts(
      paths: const [placeholder],
    );
    expect(counts['localFileCount'], 0);
    expect(counts['cloudOnlyCount'], 1);
  });

  test('album clip counts include local and cloud-only clips', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return tempDir.path;
          }
          return null;
        });
    manager.clipAlbums = <String>['일상'];

    final albumDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}vlogs'
      '${Platform.pathSeparator}raw_clips${Platform.pathSeparator}일상',
    );
    await albumDir.create(recursive: true);
    final local = File('${albumDir.path}${Platform.pathSeparator}local.mp4');
    await local.writeAsBytes(<int>[1, 2, 3, 4], flush: true);

    manager.debugSetCloudMetadataForPath(
      'cloud_only://일상/cloud-only/cloud_only.mp4',
      VideoMetadata.fromMap('cloud-only', const {
        'uid': 'uid-redacted',
        'fileName': 'cloud_only.mp4',
        'storagePath': 'storage/path/redacted',
        'albumName': '일상',
        'fileSize': 8,
        'uploadStatus': 'completed',
      }),
    );
    manager.debugSetCloudMetadataForPath(
      'cloud_only://일상/duplicate/local.mp4',
      VideoMetadata.fromMap('duplicate', {
        'uid': 'uid-redacted',
        'fileName': 'local.mp4',
        'storagePath': 'storage/path/redacted',
        'albumName': '일상',
        'fileSize': await local.length(),
        'uploadStatus': 'completed',
      }),
    );

    await manager.debugRefreshAlbumClipCounts();

    expect(manager.albumCounts['일상'], 2);
    expect(manager.albumLocalCounts['일상'], 1);
    expect(await manager.getClipCount('일상'), 2);
    expect(manager.totalDeviceClipCount, 1);
    expect(manager.totalCloudClipCount, 1);
    expect(manager.totalClipCount, 2);
  });

  test('trash album counts cloud-only trash placeholders', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return tempDir.path;
          }
          return null;
        });
    manager.clipAlbums = <String>['일상', '휴지통'];

    final trashDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}vlogs'
      '${Platform.pathSeparator}raw_clips${Platform.pathSeparator}휴지통',
    );
    await trashDir.create(recursive: true);
    final localTrash = File(
      '${trashDir.path}${Platform.pathSeparator}local_trash.mp4',
    );
    await localTrash.writeAsBytes(<int>[1, 2, 3, 4], flush: true);

    manager.debugSetCloudMetadataForPath(
      'cloud_only://휴지통/cloud-trash/cloud_trash.mp4',
      VideoMetadata.fromMap('cloud-trash', const {
        'uid': 'uid-redacted',
        'fileName': 'cloud_trash.mp4',
        'storagePath': 'storage/path/redacted',
        'albumName': '일상',
        'fileSize': 8,
        'uploadStatus': 'completed',
        'lifecycleState': 'trash',
        'cloudState': 'trash',
        'trashed': true,
      }),
    );

    await manager.debugRefreshAlbumClipCounts();

    expect(manager.albumCounts['일상'], 0);
    expect(manager.albumCounts['휴지통'], 2);
    expect(await manager.getClipCount('휴지통'), 2);
  });

  test('tombstone cloud placeholders are not counted in any album', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return tempDir.path;
          }
          return null;
        });
    manager.clipAlbums = <String>['일상', '휴지통'];

    manager.debugSetCloudMetadataForPath(
      'cloud_only://휴지통/tombstone-cloud/tombstone_cloud.mp4',
      VideoMetadata.fromMap('tombstone-cloud', const {
        'uid': 'uid-redacted',
        'fileName': 'tombstone_cloud.mp4',
        'storagePath': 'storage/path/redacted',
        'albumName': '일상',
        'fileSize': 8,
        'uploadStatus': 'completed',
        'lifecycleState': 'tombstone',
        'cloudState': 'tombstone',
        'trashed': false,
      }),
    );

    await manager.debugRefreshAlbumClipCounts();

    expect(manager.albumCounts['일상'], 0);
    expect(manager.albumCounts['휴지통'], 0);
    expect(await manager.getClipCount('휴지통'), 0);
    expect(manager.totalCloudClipCount, 0);
  });

  test('deleted cloud placeholders are not counted in trash album', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return tempDir.path;
          }
          return null;
        });
    manager.clipAlbums = <String>['일상', '휴지통'];

    manager.debugSetCloudMetadataForPath(
      'cloud_only://휴지통/deleted-cloud/deleted_cloud.mp4',
      VideoMetadata.fromMap('deleted-cloud', const {
        'uid': 'uid-redacted',
        'fileName': 'deleted_cloud.mp4',
        'storagePath': 'storage/path/redacted',
        'albumName': '일상',
        'fileSize': 8,
        'uploadStatus': 'completed',
        'lifecycleState': 'deleted',
        'cloudState': 'deleted',
        'deleted': true,
      }),
    );

    await manager.debugRefreshAlbumClipCounts();

    expect(manager.albumCounts['일상'], 0);
    expect(manager.albumCounts['휴지통'], 0);
    expect(await manager.getClipCount('휴지통'), 0);
  });

  test('cloud thumbnail debug counts distinguish ready and missing', () {
    const ready = 'cloud_only://album/ready/file.mp4';
    const missing = 'cloud_only://album/missing/file.mp4';
    const failed = 'cloud_only://album/failed/file.mp4';

    manager.recordedVideoPaths = <String>[ready, missing, failed];
    manager.debugSetCloudMetadataForPath(
      ready,
      VideoMetadata.fromMap('ready', const {
        'uid': 'uid-redacted',
        'fileName': 'redacted.mp4',
        'storagePath': 'storage/path/redacted',
        'albumName': 'album',
        'fileSize': 1,
        'uploadStatus': 'completed',
        'thumbnailStoragePath': 'storage/path/thumb',
        'thumbnailStatus': 'completed',
      }),
    );
    manager.debugSetCloudMetadataForPath(
      missing,
      VideoMetadata.fromMap('missing', const {
        'uid': 'uid-redacted',
        'fileName': 'redacted.mp4',
        'storagePath': 'storage/path/redacted',
        'albumName': 'album',
        'fileSize': 1,
        'uploadStatus': 'completed',
      }),
    );
    manager.debugSetCloudMetadataForPath(
      failed,
      VideoMetadata.fromMap('failed', const {
        'uid': 'uid-redacted',
        'fileName': 'redacted.mp4',
        'storagePath': 'storage/path/redacted',
        'albumName': 'album',
        'fileSize': 1,
        'uploadStatus': 'completed',
        'thumbnailStatus': 'failed',
      }),
    );

    final counts = manager.getCloudThumbnailDebugCounts();

    expect(counts['completedCloudCount'], 3);
    expect(counts['thumbnailReadyCount'], 1);
    expect(counts['thumbnailMissingCount'], 1);
    expect(counts['thumbnailFailedCount'], 1);
    expect(counts['fallbackCloudCardCount'], 2);
    expect(manager.hasCompletedCloudThumbnail(ready), isTrue);
    expect(manager.isCloudThumbnailRepairNeeded(missing), isTrue);
  });

  test(
    'completed cloud thumbnail metadata fetches Storage bytes once',
    () async {
      const placeholder = 'cloud_only://album/ready-fetch/file.mp4';
      var fetchCount = 0;
      manager.debugSetCloudMetadataForPath(
        placeholder,
        VideoMetadata.fromMap('ready-fetch', const {
          'uid': 'uid-redacted',
          'fileName': 'redacted.mp4',
          'storagePath': 'storage/path/redacted',
          'albumName': 'album',
          'fileSize': 1,
          'uploadStatus': 'completed',
          'thumbnailStoragePath': 'storage/path/thumb',
          'thumbnailStatus': 'completed',
        }),
      );
      manager.debugSetCloudThumbnailFetcher((_) async {
        fetchCount++;
        return Uint8List.fromList(const [9, 8, 7]);
      });

      final first = await manager.getCloudThumbnail(placeholder);
      final second = await manager.getCloudThumbnail(placeholder);
      final counts = manager.getCloudThumbnailRuntimeDebugCounts();

      expect(first, const [9, 8, 7]);
      expect(second, const [9, 8, 7]);
      expect(fetchCount, 1);
      expect(counts['cloud_thumbnail_fetch_attempt_count'], 1);
      expect(counts['cloud_thumbnail_fetch_success_count'], 1);
      expect(counts['cloud_thumbnail_cache_hit_count'], 1);
    },
  );

  test('missing cloud thumbnail metadata does not fetch Storage', () async {
    const placeholder = 'cloud_only://album/missing-fetch/file.mp4';
    var fetchCount = 0;
    manager.debugSetCloudMetadataForPath(
      placeholder,
      VideoMetadata.fromMap('missing-fetch', const {
        'uid': 'uid-redacted',
        'fileName': 'redacted.mp4',
        'storagePath': 'storage/path/redacted',
        'albumName': 'album',
        'fileSize': 1,
        'uploadStatus': 'completed',
      }),
    );
    manager.debugSetCloudThumbnailFetcher((_) async {
      fetchCount++;
      return Uint8List.fromList(const [1]);
    });

    final bytes = await manager.getCloudThumbnail(placeholder);
    final counts = manager.getCloudThumbnailRuntimeDebugCounts();

    expect(bytes, isNull);
    expect(fetchCount, 0);
    expect(counts['cloud_thumbnail_fetch_attempt_count'], 0);
  });

  test('failed cloud thumbnail status does not fetch Storage', () async {
    const placeholder = 'cloud_only://album/failed-fetch/file.mp4';
    var fetchCount = 0;
    manager.debugSetCloudMetadataForPath(
      placeholder,
      VideoMetadata.fromMap('failed-fetch', const {
        'uid': 'uid-redacted',
        'fileName': 'redacted.mp4',
        'storagePath': 'storage/path/redacted',
        'albumName': 'album',
        'fileSize': 1,
        'uploadStatus': 'completed',
        'thumbnailStoragePath': 'storage/path/thumb',
        'thumbnailStatus': 'failed',
      }),
    );
    manager.debugSetCloudThumbnailFetcher((_) async {
      fetchCount++;
      return Uint8List.fromList(const [1]);
    });

    final bytes = await manager.getCloudThumbnail(placeholder);
    final counts = manager.getCloudThumbnailRuntimeDebugCounts();

    expect(bytes, isNull);
    expect(fetchCount, 0);
    expect(counts['cloud_thumbnail_fetch_attempt_count'], 0);
  });

  test('Storage fetch failure returns null for fallback', () async {
    const placeholder = 'cloud_only://album/fetch-fail/file.mp4';
    manager.debugSetCloudMetadataForPath(
      placeholder,
      VideoMetadata.fromMap('fetch-fail', const {
        'uid': 'uid-redacted',
        'fileName': 'redacted.mp4',
        'storagePath': 'storage/path/redacted',
        'albumName': 'album',
        'fileSize': 1,
        'uploadStatus': 'completed',
        'thumbnailStoragePath': 'storage/path/thumb',
        'thumbnailStatus': 'completed',
      }),
    );
    manager.debugSetCloudThumbnailFetcher((_) async {
      throw StateError('simulated');
    });

    final bytes = await manager.getCloudThumbnail(placeholder);
    final counts = manager.getCloudThumbnailRuntimeDebugCounts();

    expect(bytes, isNull);
    expect(counts['cloud_thumbnail_fetch_attempt_count'], 1);
    expect(counts['cloud_thumbnail_fetch_failure_count'], 1);
  });

  test('localOnly clip does not use cloud thumbnail loader', () async {
    final clip = await createClip('local_display.mp4');
    var fetchCount = 0;
    manager.debugSetCloudThumbnailFetcher((_) async {
      fetchCount++;
      return Uint8List.fromList(const [1]);
    });

    final bytes = await manager.getCloudThumbnail(clip.path);
    final counts = manager.getCloudThumbnailRuntimeDebugCounts();

    expect(bytes, isNull);
    expect(fetchCount, 0);
    expect(counts['cloud_thumbnail_fetch_attempt_count'], 0);
    expect(manager.getClipStorageState(clip.path), ClipStorageState.localOnly);
  });

  test('pending upload state wins over local marker state', () async {
    final clip = await createClip('pending.mp4');
    await manager.markClipCloudSynced(clip.path);

    manager.markClipTransferPendingUpload(clip.path);

    expect(
      manager.getClipStorageState(clip.path),
      ClipStorageState.pendingUpload,
    );
    expect(manager.isUploadableClip(clip.path), isFalse);
  });

  test('failed upload state wins and remains uploadable', () async {
    final clip = await createClip('failed_upload.mp4');
    await manager.markClipCloudSynced(clip.path);

    manager.markClipTransferUploadFailed(clip.path);

    expect(
      manager.getClipStorageState(clip.path),
      ClipStorageState.failedUpload,
    );
    expect(manager.isUploadableClip(clip.path), isTrue);
  });

  test('failed download state wins', () async {
    final clip = await createClip('failed_download.mp4');

    manager.markClipTransferDownloadFailed(clip.path);

    expect(
      manager.getClipStorageState(clip.path),
      ClipStorageState.failedDownload,
    );
    expect(manager.isUploadableClip(clip.path), isFalse);
  });

  test('debug counts are count-only and include uploadable states', () async {
    final localOnly = await createClip('local.mp4');
    final synced = await createClip('synced.mp4');
    final failedUpload = await createClip('failed.mp4');
    final pending = await createClip('pending.mp4');
    const placeholder = 'cloud_only://album/video-id/file.mp4';

    await manager.markClipCloudSynced(synced.path);
    manager.markClipTransferUploadFailed(failedUpload.path);
    manager.markClipTransferPendingUpload(pending.path);

    final counts = manager.getStorageStateDebugCounts(
      paths: <String>[
        localOnly.path,
        synced.path,
        failedUpload.path,
        pending.path,
        placeholder,
      ],
    );

    expect(counts['localFileCount'], 4);
    expect(counts['localOnlyCount'], 1);
    expect(counts['cloudSyncedLocalCount'], 1);
    expect(counts['cloudOnlyCount'], 1);
    expect(counts['pendingUploadCount'], 1);
    expect(counts['failedUploadCount'], 1);
    expect(counts['uploadableCount'], 2);
  });

  test('status badge only exposes device or cloud copy', () async {
    final localOnly = await createClip('badge_local.mp4');
    final synced = await createClip('badge_synced.mp4');
    final pending = await createClip('badge_pending.mp4');
    final failedUpload = await createClip('badge_failed_upload.mp4');
    final failedDownload = await createClip('badge_failed_download.mp4');
    const placeholder = 'cloud_only://album/video-id/file.mp4';

    await manager.markClipCloudSynced(synced.path);
    manager.markClipTransferPendingUpload(pending.path);
    manager.markClipTransferUploadFailed(failedUpload.path);
    manager.markClipTransferDownloadFailed(failedDownload.path);

    expect(manager.getClipStatusBadge(localOnly.path), '기기');
    expect(manager.getClipStatusBadge(synced.path), '기기');
    expect(manager.getClipStatusBadge(pending.path), '로딩중');
    expect(manager.getClipStatusBadge(failedUpload.path), '기기');
    expect(manager.getClipStatusBadge(failedDownload.path), 'Cloud');
    expect(manager.getClipStatusBadge(placeholder), 'Cloud');
  });

  test(
    'pending transfer badges render as loading for upload and download',
    () async {
      final pendingUpload = await createClip('badge_pending_upload.mp4');
      const pendingDownload = 'cloud_only://album/video-id/loading.mp4';

      manager.markClipTransferPendingUpload(pendingUpload.path);
      manager.markClipTransferPendingDownload(pendingDownload);

      expect(manager.getClipStatusBadge(pendingUpload.path), '로딩중');
      expect(manager.getClipStatusBadge(pendingDownload), '로딩중');
    },
  );

  test(
    'cloud-to-device finalize removes cloud marker and leaves localOnly',
    () async {
      final restored = await createClip('restored_move.mp4');
      const placeholder = 'cloud_only://album/video-id/restored_move.mp4';
      final metadata = VideoMetadata.fromMap('video-id', {
        'uid': 'uid-redacted',
        'fileName': 'restored_move.mp4',
        'storagePath': 'storage/path/redacted',
        'albumName': manager.currentAlbum,
        'fileSize': await restored.length(),
        'uploadStatus': 'completed',
        'cloudState': 'active',
      });

      manager.recordedVideoPaths = <String>[placeholder];
      manager.debugSetCloudMetadataForPath(placeholder, metadata);
      await manager.markClipCloudSynced(placeholder);
      await manager.markClipCloudSynced(restored.path);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            return null;
          });

      expect(
        manager.getClipStorageState(restored.path),
        ClipStorageState.cloudSyncedLocal,
      );

      await manager.registerCloudMovedToDeviceClip(
        path: restored.path,
        albumName: '다른앨범',
        cloudMetadata: metadata,
      );

      expect(manager.recordedVideoPaths, isNot(contains(placeholder)));
      expect(manager.isClipCloudSynced(restored.path), isFalse);
      expect(
        manager.getClipStorageState(restored.path),
        ClipStorageState.localOnly,
      );

      final counts = manager.getStorageStateDebugCounts(paths: [restored.path]);
      expect(counts['localOnlyCount'], 1);
      expect(counts['cloudOnlyCount'], 0);
      expect(counts['cloudSyncedLocalCount'], 0);
      expect(counts['uploadableCount'], 1);
    },
  );
}
