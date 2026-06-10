import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:three_s/managers/video_manager.dart';
import 'package:three_s/models/vlog_project.dart';
import 'package:three_s/services/cloud_service.dart';
import 'package:three_s/services/local_index_service.dart';
import 'package:three_s/utils/brightness_adjustment_policy.dart';
import 'package:three_s/utils/color_filter_preset_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  const videoEngineChannel = MethodChannel('com.dk.three_sec/video_engine');
  const galChannel = MethodChannel('gal');

  late VideoManager manager;
  late Directory tempDir;

  Future<File> createClip(String name) async {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(<int>[0, 1, 2, 3], flush: true);
    return file;
  }

  Future<File> createRawAlbumClip(String albumName, String name) async {
    final albumDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}vlogs'
      '${Platform.pathSeparator}raw_clips${Platform.pathSeparator}$albumName',
    );
    await albumDir.create(recursive: true);
    final file = File('${albumDir.path}${Platform.pathSeparator}$name');
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(videoEngineChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(galChannel, null);
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

  test(
    'clearUserScopedLocalCache removes stale cloud-only local index entries',
    () async {
      const placeholder = 'cloud_only://album/video-id/file.mp4';
      final localClip = await createClip('local_retained.mp4');
      final index = LocalIndexService();
      await index.saveEntries([
        LocalIndexEntry(
          id: 'cloud-video-id',
          type: 'clip',
          pathOrKey: placeholder,
          ownerAccountId: 'old-uid',
          lockState: 'owned',
          updatedAt: DateTime.utc(2026),
          cloudVideoId: 'cloud-video-id',
          cloudStoragePath: 'users/old-uid/videos/cloud-video-id/file.mp4',
          cloudStorageTier: 'cloud',
          cloudState: 'completed',
          cloudFileName: 'file.mp4',
          cloudFileSize: 4,
          albumName: 'album',
        ),
        LocalIndexEntry(
          id: 'local-id',
          type: 'clip',
          pathOrKey: localClip.path,
          ownerAccountId: 'old-uid',
          lockState: 'owned',
          updatedAt: DateTime.utc(2026),
          albumName: 'album',
        ),
      ]);
      manager.recordedVideoPaths = [placeholder, localClip.path];

      await manager.clearUserScopedLocalCache(trigger: 'test');

      final entries = await index.loadEntries();
      expect(entries.map((entry) => entry.pathOrKey), [localClip.path]);
      expect(manager.recordedVideoPaths, [localClip.path]);
    },
  );

  test('cloud_only duration uses cloud metadata without local file', () async {
    const placeholder = 'cloud_only://album/video-id/file.mp4';
    manager.debugSetCloudMetadataForPath(
      placeholder,
      VideoMetadata.fromMap('video-id', const {
        'uid': 'uid-redacted',
        'fileName': 'file.mp4',
        'storagePath': 'storage/path/redacted',
        'albumName': 'album',
        'fileSize': 8,
        'uploadStatus': 'completed',
        'durationMs': 2100,
      }),
    );

    final duration = await manager.getVideoDuration(placeholder);

    expect(duration, const Duration(milliseconds: 2100));
  });

  test('getThumbnail uses completed cloud thumbnail metadata', () async {
    const placeholder = 'cloud_only://album/video-id/file.mp4';
    var fetchCount = 0;
    manager.debugSetCloudMetadataForPath(
      placeholder,
      VideoMetadata.fromMap('video-id', const {
        'uid': 'uid-redacted',
        'fileName': 'file.mp4',
        'storagePath': 'storage/path/redacted',
        'albumName': 'album',
        'fileSize': 8,
        'uploadStatus': 'completed',
        'thumbnailStoragePath': 'storage/path/thumb',
        'thumbnailStatus': 'completed',
      }),
    );
    manager.debugSetCloudThumbnailFetcher((_) async {
      fetchCount++;
      return Uint8List.fromList(const [7, 8, 9]);
    });

    final bytes = await manager.getThumbnail(placeholder);

    expect(bytes, const [7, 8, 9]);
    expect(fetchCount, 1);
    expect(
      manager
          .getCloudThumbnailRuntimeDebugCounts()['cloud_thumbnail_fetch_success_count'],
      1,
    );
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

  test(
    'reported count fixture keeps profile totals, folder tiles, and detail counts consistent',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            return null;
          });
      manager.clipAlbums = <String>['일상', '고덕스테이', '휴지통'];

      final dailyLocalPaths = <String>[];
      for (var i = 0; i < 7; i++) {
        dailyLocalPaths.add(
          (await createRawAlbumClip('일상', 'daily_local_$i.mp4')).path,
        );
      }
      final lodgeLocalPaths = <String>[];
      for (var i = 0; i < 15; i++) {
        lodgeLocalPaths.add(
          (await createRawAlbumClip('고덕스테이', 'lodge_local_$i.mp4')).path,
        );
      }
      final trashLocal = await createRawAlbumClip('휴지통', 'trash_local.mp4');

      final dailyCloudPaths = <String>[];
      for (var i = 0; i < 8; i++) {
        final videoId = 'daily-cloud-$i';
        final path = 'cloud_only://일상/$videoId/daily_cloud_$i.mp4';
        dailyCloudPaths.add(path);
        manager.debugSetCloudMetadataForPath(
          path,
          VideoMetadata.fromMap(videoId, {
            'uid': 'uid-redacted',
            'fileName': 'daily_cloud_$i.mp4',
            'storagePath': 'storage/path/redacted/$videoId',
            'albumName': '일상',
            'fileSize': 8,
            'uploadStatus': 'completed',
            'completedAt':
                '2026-06-${(i + 1).toString().padLeft(2, '0')}T10:00:00.000',
          }),
        );
      }

      await manager.debugRefreshAlbumClipCounts();

      expect(manager.albumCounts['일상'], 15);
      expect(manager.albumCounts['고덕스테이'], 15);
      expect(manager.albumCounts['휴지통'], 1);
      expect(manager.albumLocalCounts['일상'], 7);
      expect(manager.albumLocalCounts['고덕스테이'], 15);
      expect(manager.albumLocalCounts['휴지통'], 1);
      expect(manager.totalDeviceClipCount, 23);
      expect(manager.totalCloudClipCount, 8);
      expect(manager.totalClipCount, 31);

      manager.currentAlbum = '일상';
      await manager.loadClipsFromAlbum('일상');
      final dailyDetail = manager.getClipsInAlbum('일상');
      expect(dailyDetail, hasLength(15));
      expect(dailyDetail, containsAll(dailyLocalPaths));
      expect(dailyDetail, containsAll(dailyCloudPaths));
      expect(dailyDetail, isNot(contains(trashLocal.path)));
      for (final path in lodgeLocalPaths) {
        expect(dailyDetail, isNot(contains(path)));
      }
      expect(
        dailyDetail.where(
          (path) => manager.isClipVisibleByStorageFilter(path, 'all'),
        ),
        hasLength(15),
      );
      expect(
        dailyDetail.where(
          (path) => manager.isClipVisibleByStorageFilter(path, 'device'),
        ),
        hasLength(7),
      );
      expect(
        dailyDetail.where(
          (path) => manager.isClipVisibleByStorageFilter(path, 'cloud'),
        ),
        hasLength(8),
      );

      manager.currentAlbum = '고덕스테이';
      await manager.loadClipsFromAlbum('고덕스테이');
      final lodgeDetail = manager.getClipsInAlbum('고덕스테이');
      expect(lodgeDetail, hasLength(15));
      expect(lodgeDetail, containsAll(lodgeLocalPaths));
      for (final path in dailyLocalPaths.followedBy(dailyCloudPaths)) {
        expect(lodgeDetail, isNot(contains(path)));
      }
      expect(lodgeDetail, isNot(contains(trashLocal.path)));
      expect(
        lodgeDetail.where(
          (path) => manager.isClipVisibleByStorageFilter(path, 'all'),
        ),
        hasLength(15),
      );
      expect(
        lodgeDetail.where(
          (path) => manager.isClipVisibleByStorageFilter(path, 'device'),
        ),
        hasLength(15),
      );
      expect(
        lodgeDetail.where(
          (path) => manager.isClipVisibleByStorageFilter(path, 'cloud'),
        ),
        isEmpty,
      );

      manager.currentAlbum = '휴지통';
      await manager.loadClipsFromAlbum('휴지통');
      final trashDetail = manager.getClipsInAlbum('휴지통');
      expect(trashDetail, [trashLocal.path]);
      for (final path in dailyLocalPaths.followedBy(dailyCloudPaths)) {
        expect(trashDetail, isNot(contains(path)));
      }
      for (final path in lodgeLocalPaths) {
        expect(trashDetail, isNot(contains(path)));
      }
      expect(
        trashDetail.where(
          (path) => manager.isClipVisibleByStorageFilter(path, 'all'),
        ),
        hasLength(1),
      );
      expect(
        trashDetail.where(
          (path) => manager.isClipVisibleByStorageFilter(path, 'device'),
        ),
        hasLength(1),
      );
      expect(
        trashDetail.where(
          (path) => manager.isClipVisibleByStorageFilter(path, 'cloud'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'loadClipsFromAlbum reconciles stale aggregate counts for opened album',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            return null;
          });
      manager.clipAlbums = <String>['일상', '고덕스테이', '휴지통'];
      final dailyLocal = await createRawAlbumClip('일상', 'daily_local.mp4');
      manager.albumCounts = <String, int>{'일상': 1, '고덕스테이': 15, '휴지통': 1};
      manager.albumLocalCounts = <String, int>{'일상': 1, '고덕스테이': 15, '휴지통': 1};
      manager.debugSetCloudMetadataForPath(
        'cloud_only://일상/seed-cloud/seed_cloud.mp4',
        VideoMetadata.fromMap('seed-cloud', const {
          'uid': 'uid-redacted',
          'fileName': 'seed_cloud.mp4',
          'storagePath': 'storage/path/redacted/seed-cloud',
          'albumName': '일상',
          'fileSize': 8,
          'uploadStatus': 'completed',
          'lifecycleState': 'tombstone',
          'cloudState': 'tombstone',
        }),
      );

      manager.currentAlbum = '고덕스테이';
      await manager.loadClipsFromAlbum('고덕스테이');

      expect(manager.getClipsInAlbum('고덕스테이'), isEmpty);
      expect(
        manager.albumCounts['고덕스테이'],
        0,
        reason:
            'Opening an album with no visible clips must reconcile the root '
            'tile count instead of leaving a stale aggregate value.',
      );
      expect(manager.albumLocalCounts['고덕스테이'], 0);
      expect(manager.totalDeviceClipCount, 2);
      expect(manager.totalCloudClipCount, 0);

      manager.currentAlbum = '일상';
      await manager.loadClipsFromAlbum('일상');
      expect(manager.getClipsInAlbum('일상'), [dailyLocal.path]);
      expect(manager.albumCounts['일상'], 1);
      expect(manager.albumLocalCounts['일상'], 1);
    },
  );

  test(
    'loadClipsFromCurrentAlbum interleaves local and cloud-only clips by date',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            return null;
          });
      manager.currentAlbum = '일상';
      manager.clipAlbums = <String>['일상'];

      final albumDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}vlogs'
        '${Platform.pathSeparator}raw_clips${Platform.pathSeparator}일상',
      );
      await albumDir.create(recursive: true);
      final oldLocal = File(
        '${albumDir.path}${Platform.pathSeparator}local_old.mp4',
      );
      final newLocal = File(
        '${albumDir.path}${Platform.pathSeparator}local_new.mp4',
      );
      await oldLocal.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
      await newLocal.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
      await oldLocal.setLastModified(DateTime(2026, 6, 1, 10));
      await newLocal.setLastModified(DateTime(2026, 6, 3, 10));

      const cloudPath = 'cloud_only://일상/cloud-mid/cloud_mid.mp4';
      manager.debugSetCloudMetadataForPath(
        cloudPath,
        VideoMetadata.fromMap('cloud-mid', const {
          'uid': 'uid-redacted',
          'fileName': 'cloud_mid.mp4',
          'storagePath': 'storage/path/redacted',
          'albumName': '일상',
          'fileSize': 8,
          'uploadStatus': 'completed',
          'completedAt': '2026-06-02T10:00:00.000',
        }),
      );

      await manager.loadClipsFromCurrentAlbum();

      expect(manager.recordedVideoPaths, [
        newLocal.path,
        cloudPath,
        oldLocal.path,
      ]);
    },
  );

  test(
    'loadClipsFromCurrentAlbum publishes all-source album paths in one notification',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            return null;
          });
      manager.currentAlbum = '일상';
      manager.clipAlbums = <String>['일상'];

      final albumDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}vlogs'
        '${Platform.pathSeparator}raw_clips${Platform.pathSeparator}일상',
      );
      await albumDir.create(recursive: true);
      final local = File('${albumDir.path}${Platform.pathSeparator}local.mp4');
      await local.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
      await local.setLastModified(DateTime(2026, 6, 2, 10));

      const cloudPath = 'cloud_only://일상/cloud-new/cloud_new.mp4';
      manager.debugSetCloudMetadataForPath(
        cloudPath,
        VideoMetadata.fromMap('cloud-new', const {
          'uid': 'uid-redacted',
          'fileName': 'cloud_new.mp4',
          'storagePath': 'storage/path/redacted',
          'albumName': '일상',
          'fileSize': 8,
          'uploadStatus': 'completed',
          'completedAt': '2026-06-03T10:00:00.000',
        }),
      );

      final publishedPaths = <List<String>>[];
      void recordPublishedPaths() {
        publishedPaths.add(List<String>.from(manager.recordedVideoPaths));
      }

      manager.addListener(recordPublishedPaths);
      try {
        await manager.loadClipsFromCurrentAlbum();
      } finally {
        manager.removeListener(recordPublishedPaths);
      }

      expect(manager.recordedVideoPaths, [cloudPath, local.path]);
      expect(
        publishedPaths,
        everyElement(containsAll(<String>[cloudPath, local.path])),
        reason:
            'Library detail must not publish the local-only count before the '
            'cloud-only placeholders are merged.',
      );
      expect(
        publishedPaths,
        isNotEmpty,
        reason:
            'The album load should still notify the UI when the list lands.',
      );
    },
  );

  test('loadClipsFromCurrentAlbum publishes local-only albums once', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return tempDir.path;
          }
          return null;
        });
    manager.currentAlbum = '고덕스테이';
    manager.clipAlbums = <String>['고덕스테이'];

    final albumDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}vlogs'
      '${Platform.pathSeparator}raw_clips${Platform.pathSeparator}고덕스테이',
    );
    await albumDir.create(recursive: true);
    final local = File('${albumDir.path}${Platform.pathSeparator}local.mp4');
    await local.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
    manager.debugSetCloudMetadataForPath(
      'cloud_only://일상/other-album/other.mp4',
      VideoMetadata.fromMap('other-album', const {
        'uid': 'uid-redacted',
        'fileName': 'other.mp4',
        'storagePath': 'storage/path/redacted',
        'albumName': '일상',
        'fileSize': 8,
        'uploadStatus': 'completed',
      }),
    );

    var publishCount = 0;
    void countPublish() {
      publishCount++;
    }

    manager.addListener(countPublish);
    try {
      await manager.loadClipsFromCurrentAlbum();
    } finally {
      manager.removeListener(countPublish);
    }

    expect(manager.recordedVideoPaths, [local.path]);
    expect(
      publishCount,
      1,
      reason:
          'A local-only album should not emit duplicate detail-count updates.',
    );
  });

  test(
    'loadClipsFromCurrentAlbum isolates consecutive library albums',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            return null;
          });
      manager.clipAlbums = <String>['일상', '고덕스테이', '휴지통'];

      final dailyDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}vlogs'
        '${Platform.pathSeparator}raw_clips${Platform.pathSeparator}일상',
      );
      final lodgeDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}vlogs'
        '${Platform.pathSeparator}raw_clips${Platform.pathSeparator}고덕스테이',
      );
      await dailyDir.create(recursive: true);
      await lodgeDir.create(recursive: true);

      final dailyLocal = File(
        '${dailyDir.path}${Platform.pathSeparator}daily_local.mp4',
      );
      final lodgeLocal = File(
        '${lodgeDir.path}${Platform.pathSeparator}lodge_local.mp4',
      );
      await dailyLocal.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
      await lodgeLocal.writeAsBytes(<int>[5, 6, 7, 8], flush: true);

      const dailyCloud = 'cloud_only://일상/daily-cloud/daily_cloud.mp4';
      const lodgeCloud = 'cloud_only://고덕스테이/lodge-cloud/lodge_cloud.mp4';
      manager.debugSetCloudMetadataForPath(
        dailyCloud,
        VideoMetadata.fromMap('daily-cloud', const {
          'uid': 'uid-redacted',
          'fileName': 'daily_cloud.mp4',
          'storagePath': 'storage/path/redacted/daily',
          'albumName': '일상',
          'fileSize': 8,
          'uploadStatus': 'completed',
          'completedAt': '2026-06-01T10:00:00.000',
        }),
      );
      manager.debugSetCloudMetadataForPath(
        lodgeCloud,
        VideoMetadata.fromMap('lodge-cloud', const {
          'uid': 'uid-redacted',
          'fileName': 'lodge_cloud.mp4',
          'storagePath': 'storage/path/redacted/lodge',
          'albumName': '고덕스테이',
          'fileSize': 8,
          'uploadStatus': 'completed',
          'completedAt': '2026-06-02T10:00:00.000',
        }),
      );

      manager.currentAlbum = '일상';
      await manager.loadClipsFromCurrentAlbum();
      expect(manager.getClipsInAlbum('일상'), contains(dailyLocal.path));
      expect(manager.getClipsInAlbum('일상'), contains(dailyCloud));
      expect(manager.getClipsInAlbum('일상'), isNot(contains(lodgeLocal.path)));
      expect(manager.getClipsInAlbum('일상'), isNot(contains(lodgeCloud)));

      manager.currentAlbum = '고덕스테이';
      expect(
        manager.getClipsInAlbum('고덕스테이'),
        isNot(contains(dailyLocal.path)),
        reason: 'Opening 고덕스테이 must not render stale 일상 local clips.',
      );
      expect(
        manager.getClipsInAlbum('고덕스테이'),
        isNot(contains(dailyCloud)),
        reason: 'Opening 고덕스테이 must not render stale 일상 cloud clips.',
      );

      await manager.loadClipsFromCurrentAlbum();
      expect(manager.getClipsInAlbum('고덕스테이'), contains(lodgeLocal.path));
      expect(manager.getClipsInAlbum('고덕스테이'), contains(lodgeCloud));
      expect(
        manager.getClipsInAlbum('고덕스테이'),
        isNot(contains(dailyLocal.path)),
      );
      expect(manager.getClipsInAlbum('고덕스테이'), isNot(contains(dailyCloud)));

      manager.currentAlbum = '일상';
      expect(
        manager.getClipsInAlbum('일상'),
        isNot(contains(lodgeLocal.path)),
        reason: 'Reopening 일상 must not render stale 고덕스테이 local clips.',
      );
      expect(
        manager.getClipsInAlbum('일상'),
        isNot(contains(lodgeCloud)),
        reason: 'Reopening 일상 must not render stale 고덕스테이 cloud clips.',
      );

      await manager.loadClipsFromCurrentAlbum();
      expect(manager.getClipsInAlbum('일상'), contains(dailyLocal.path));
      expect(manager.getClipsInAlbum('일상'), contains(dailyCloud));
      expect(manager.getClipsInAlbum('일상'), isNot(contains(lodgeLocal.path)));
      expect(manager.getClipsInAlbum('일상'), isNot(contains(lodgeCloud)));
    },
  );

  test('isClipPathInAlbum recognizes raw clip album path segments', () {
    const posixLodgePath =
        '/data/user/0/com.dk.three_sec/app_flutter/vlogs/raw_clips/고덕스테이/moa_qa_lodge.mp4';
    const encodedLodgePath =
        '/data/user/0/com.dk.three_sec/app_flutter/vlogs/raw_clips/%EA%B3%A0%EB%8D%95%EC%8A%A4%ED%85%8C%EC%9D%B4/moa_qa_lodge.mp4';
    const windowsLodgePath =
        r'C:\tmp\moa\vlogs\raw_clips\고덕스테이\moa_qa_lodge.mp4';
    const dailyPath =
        '/data/user/0/com.dk.three_sec/app_flutter/vlogs/raw_clips/일상/daily.mp4';

    expect(manager.isClipPathInAlbum(posixLodgePath, '고덕스테이'), isTrue);
    expect(manager.isClipPathInAlbum(encodedLodgePath, '고덕스테이'), isTrue);
    expect(manager.isClipPathInAlbum(windowsLodgePath, '고덕스테이'), isTrue);
    expect(manager.isClipPathInAlbum(dailyPath, '고덕스테이'), isFalse);
    expect(manager.isClipPathInAlbum(posixLodgePath, '일상'), isFalse);
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

  test(
    'saveProject restores cloud placeholder before persisting session cache path',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            return null;
          });

      const placeholder = 'cloud_only://album/video-id/file.mp4';
      final metadata = VideoMetadata.fromMap('video-id', const {
        'uid': 'uid-redacted',
        'fileName': 'file.mp4',
        'storagePath': 'storage/path/redacted',
        'albumName': 'album',
        'fileSize': 8,
        'uploadStatus': 'completed',
      });
      manager.debugSetCloudMetadataForPath(placeholder, metadata);

      final cachePath =
          '${tempDir.path}${Platform.pathSeparator}cloud_clip_session_cache'
          '${Platform.pathSeparator}edit_session_cache'
          '${Platform.pathSeparator}video-id'
          '${Platform.pathSeparator}file.mp4';
      final now = DateTime(2026, 5, 21);
      final project = VlogProject(
        id: 'project-session-cache',
        title: 'Session Cache Guard',
        clips: <VlogClip>[VlogClip(path: cachePath)],
        createdAt: now,
        updatedAt: now,
      );

      final result = await manager.saveProject(
        project,
        reason: 'test_session_cache_guard',
      );
      expect(result.localStatus, ProjectSaveLocalStatus.success);
      expect(result.cloudStatus, ProjectSaveCloudStatus.skippedGuest);
      expect(result.localSaved, isTrue);
      expect(result.cloudSaved, isFalse);

      final file = File(
        '${tempDir.path}${Platform.pathSeparator}vlog_projects'
        '${Platform.pathSeparator}${project.id}.json',
      );
      expect(await file.exists(), isTrue);

      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final clips = json['clips'] as List<Object?>;
      final firstClip = clips.first as Map<String, Object?>;
      expect(firstClip['path'], placeholder);
      expect('${firstClip['path']}', isNot(contains('edit_session_cache')));
      expect(project.clips.first.path, placeholder);
    },
  );

  test(
    'saveProject restores cloud placeholder before persisting canonical cache path',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            return null;
          });

      const placeholder = 'cloud_only://album/video-id/file.mp4';
      final metadata = VideoMetadata.fromMap('video-id', const {
        'uid': 'uid-redacted',
        'fileName': 'file.mp4',
        'storagePath': 'storage/path/redacted',
        'albumName': 'album',
        'fileSize': 8,
        'uploadStatus': 'completed',
      });
      manager.debugSetCloudMetadataForPath(placeholder, metadata);

      final cachePath =
          '${tempDir.path}${Platform.pathSeparator}cloud_video_cache'
          '${Platform.pathSeparator}video-id'
          '${Platform.pathSeparator}standard.mp4';
      final now = DateTime(2026, 5, 21);
      final project = VlogProject(
        id: 'project-canonical-cache',
        title: 'Canonical Cache Guard',
        clips: <VlogClip>[VlogClip(path: cachePath)],
        createdAt: now,
        updatedAt: now,
      );

      final result = await manager.saveProject(
        project,
        reason: 'test_canonical_cache_guard',
      );

      expect(result.localStatus, ProjectSaveLocalStatus.success);
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}vlog_projects'
        '${Platform.pathSeparator}${project.id}.json',
      );
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final clips = json['clips'] as List<Object?>;
      final firstClip = clips.first as Map<String, Object?>;
      expect(firstClip['path'], placeholder);
      expect('${firstClip['path']}', isNot(contains('cloud_video_cache')));
      expect(project.clips.first.path, placeholder);
    },
  );

  test('saveProject blocks unresolved export session cache paths', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return tempDir.path;
          }
          return null;
        });

    final cachePath =
        '${tempDir.path}${Platform.pathSeparator}export_session_cache'
        '${Platform.pathSeparator}detached-video'
        '${Platform.pathSeparator}file.mp4';
    final now = DateTime(2026, 5, 21);
    final project = VlogProject(
      id: 'project-unresolved-session-cache',
      title: 'Unresolved Session Cache Guard',
      clips: <VlogClip>[VlogClip(path: cachePath)],
      createdAt: now,
      updatedAt: now,
    );

    final result = await manager.saveProject(
      project,
      reason: 'test_unresolved_session_cache_guard',
    );

    expect(result.localStatus, ProjectSaveLocalStatus.blocked);
    expect(
      result.cloudStatus,
      ProjectSaveCloudStatus.skippedSessionCachePathGuard,
    );
    expect(result.localSaved, isFalse);
    expect(result.cloudSaved, isFalse);
    expect(project.clips.first.path, cachePath);

    final file = File(
      '${tempDir.path}${Platform.pathSeparator}vlog_projects'
      '${Platform.pathSeparator}${project.id}.json',
    );
    expect(await file.exists(), isFalse);
  });

  test('copyProjectToFolder preserves clip-specific brightness for reopen', () {
    final now = DateTime(2026, 5, 21);
    final project = VlogProject(
      id: 'project-brightness-copy',
      title: 'Brightness Copy',
      clips: <VlogClip>[
        VlogClip(
          id: 'clip-a',
          path: 'clip_a.mp4',
          brightnessAdjustments: const {'brightness': 28},
        ),
        VlogClip(
          id: 'clip-b',
          path: 'clip_b.mp4',
          brightnessAdjustments: const {'contrast': -18},
        ),
      ],
      brightnessAdjustmentScope: kBrightnessAdjustmentScopeClipSpecific,
      brightnessAdjustments: const {'exposure': 12},
      createdAt: now,
      updatedAt: now,
    );

    final copied = debugBuildCopiedProjectForFolder(
      project: project,
      targetFolder: '기본',
      timestamp: now,
    );
    final reopened = VlogProject.fromJson(copied.toJson());

    expect(
      reopened.brightnessAdjustmentScope,
      kBrightnessAdjustmentScopeClipSpecific,
    );
    expect(reopened.brightnessAdjustments['exposure'], 12);
    expect(reopened.clips[0].brightnessAdjustments['brightness'], 28);
    expect(reopened.clips[1].brightnessAdjustments['contrast'], -18);
  });

  test(
    'exportVlog sends index-based audio changes for duplicate source paths',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            return null;
          });

      final clip = await createClip('duplicate_source.mp4');
      final capturedMergeCalls = <Map<Object?, Object?>>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(videoEngineChannel, (call) async {
            if (call.method == 'mergeVideos') {
              final args = Map<Object?, Object?>.from(
                call.arguments as Map<Object?, Object?>,
              );
              capturedMergeCalls.add(args);
              final outputPath = args['outputPath']! as String;
              await File(outputPath).writeAsBytes(<int>[9, 8, 7, 6]);
              return outputPath;
            }
            if (call.method == 'getVideoDurationMs') {
              return 2000;
            }
            return null;
          });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(galChannel, (call) async {
            if (call.method == 'requestAccess') {
              return true;
            }
            if (call.method == 'putVideo') {
              return null;
            }
            return null;
          });

      final result = await manager.exportVlog(
        clips: <VlogClip>[
          VlogClip(path: clip.path, volume: 0.25),
          VlogClip(path: clip.path, volume: 0.75),
        ],
        audioConfig: <String, double>{clip.path: 0.75},
        audioConfigByClipIndex: const <double>[0.25, 0.75],
        bgmVolume: 0,
      );

      expect(result, isNotNull);
      expect(capturedMergeCalls, hasLength(1));

      final firstCall = capturedMergeCalls.single;
      expect(firstCall['videoPaths'], <String>[clip.path, clip.path]);
      expect(firstCall['audioChanges'], <String, double>{clip.path: 0.75});
      expect(firstCall['audioChangesByClipIndex'], <double>[0.25, 0.75]);
      expect(firstCall['forceMuteOriginal'], isFalse);
    },
  );

  test(
    'exportVlog sends clip-specific brightness and silent audio args',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            return null;
          });

      final firstClip = await createClip('brightness_first.mp4');
      final secondClip = await createClip('brightness_second.mp4');
      final capturedMergeCalls = <Map<Object?, Object?>>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(videoEngineChannel, (call) async {
            if (call.method == 'mergeVideos') {
              final args = Map<Object?, Object?>.from(
                call.arguments as Map<Object?, Object?>,
              );
              capturedMergeCalls.add(args);
              final outputPath = args['outputPath']! as String;
              await File(outputPath).writeAsBytes(<int>[1, 2, 3, 4]);
              return outputPath;
            }
            if (call.method == 'getVideoDurationMs') {
              return 2000;
            }
            return null;
          });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(galChannel, (call) async {
            if (call.method == 'requestAccess') {
              return true;
            }
            if (call.method == 'putVideo') {
              return null;
            }
            return null;
          });

      final result = await manager.exportVlog(
        clips: <VlogClip>[
          VlogClip(
            path: firstClip.path,
            brightnessAdjustments: const <String, double>{'brightness': 30},
          ),
          VlogClip(
            path: secondClip.path,
            brightnessAdjustments: const <String, double>{'contrast': -20},
          ),
        ],
        audioConfig: <String, double>{firstClip.path: 0, secondClip.path: 0},
        audioConfigByClipIndex: const <double>[0, 0],
        bgmPath: 'bgm_should_be_omitted.mp3',
        bgmVolume: 0,
        forceMuteOriginal: true,
        brightnessAdjustments: const <String, double>{'brightness': 5},
        colorFilterPresetId: kColorFilterPresetWarmSunset,
        colorFilterIntensity: 0.75,
      );

      expect(result, isNotNull);
      expect(capturedMergeCalls, hasLength(1));

      final args = capturedMergeCalls.single;
      expect(args['audioChangesByClipIndex'], <double>[0, 0]);
      expect(args['forceMuteOriginal'], isTrue);
      expect(args['bgmPath'], isNull);
      expect(args['bgmVolume'], 0.0);

      final globalVideoEffects = Map<Object?, Object?>.from(
        args['videoEffects']! as Map,
      );
      expect(
        globalVideoEffects['colorFilterPresetId'],
        kColorFilterPresetWarmSunset,
      );
      expect(globalVideoEffects.containsKey('brightness'), isFalse);

      final clipEffects = args['videoEffectsByClipIndex']! as List<Object?>;
      expect(clipEffects, hasLength(2));

      final firstEffects = Map<Object?, Object?>.from(clipEffects[0]! as Map);
      final secondEffects = Map<Object?, Object?>.from(clipEffects[1]! as Map);
      expect(firstEffects['brightness'], 30.0);
      expect(firstEffects['colorFilterPresetId'], kColorFilterPresetWarmSunset);
      expect(secondEffects['contrast'], -20.0);
      expect(
        secondEffects['colorFilterPresetId'],
        kColorFilterPresetWarmSunset,
      );
    },
  );

  test(
    'exportVlog sends clip-local color filters per clip when they differ',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            return null;
          });

      final firstClip = await createClip('color_first.mp4');
      final secondClip = await createClip('color_second.mp4');
      final capturedMergeCalls = <Map<Object?, Object?>>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(videoEngineChannel, (call) async {
            if (call.method == 'mergeVideos') {
              final args = Map<Object?, Object?>.from(
                call.arguments as Map<Object?, Object?>,
              );
              capturedMergeCalls.add(args);
              final outputPath = args['outputPath']! as String;
              await File(outputPath).writeAsBytes(<int>[1, 2, 3, 4]);
              return outputPath;
            }
            if (call.method == 'getVideoDurationMs') {
              return 2000;
            }
            return null;
          });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(galChannel, (call) async {
            if (call.method == 'requestAccess') {
              return true;
            }
            if (call.method == 'putVideo') {
              return null;
            }
            return null;
          });

      final result = await manager.exportVlog(
        clips: <VlogClip>[
          VlogClip(
            path: firstClip.path,
            colorFilterPresetId: kColorFilterPresetClearSky,
            colorFilterIntensity: 0.8,
          ),
          VlogClip(
            path: secondClip.path,
            colorFilterPresetId: kColorFilterPresetFilmGreen,
            colorFilterIntensity: 0.35,
          ),
        ],
        audioConfig: <String, double>{firstClip.path: 0, secondClip.path: 0},
        audioConfigByClipIndex: const <double>[0, 0],
        forceMuteOriginal: true,
        colorFilterPresetId: kColorFilterPresetWarmSunset,
        colorFilterIntensity: 0.75,
      );

      expect(result, isNotNull);
      expect(capturedMergeCalls, hasLength(1));

      final args = capturedMergeCalls.single;
      final globalVideoEffects = Map<Object?, Object?>.from(
        args['videoEffects']! as Map,
      );
      expect(globalVideoEffects.containsKey('colorFilterPresetId'), isFalse);

      final clipEffects = args['videoEffectsByClipIndex']! as List<Object?>;
      expect(clipEffects, hasLength(2));

      final firstEffects = Map<Object?, Object?>.from(clipEffects[0]! as Map);
      final secondEffects = Map<Object?, Object?>.from(clipEffects[1]! as Map);
      expect(firstEffects['colorFilterPresetId'], kColorFilterPresetClearSky);
      expect(firstEffects['colorFilterIntensity'], 0.8);
      expect(secondEffects['colorFilterPresetId'], kColorFilterPresetFilmGreen);
      expect(secondEffects['colorFilterIntensity'], 0.35);
    },
  );
}
