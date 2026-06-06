import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:three_s/managers/user_status_manager.dart';
import 'package:three_s/managers/video_manager.dart';
import 'package:three_s/models/vlog_project.dart';
import 'package:three_s/services/cloud_service.dart';
import 'package:three_s/services/cloud_usage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ownerUid = 'user-standard-1';
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final fallbackTimestamp = DateTime.utc(2026, 6, 6, 1, 0);

  late VideoManager manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    manager = VideoManager();
    manager.debugSetAutoCloudUploadUploader(null);
    manager.recordedVideoPaths = <String>[];
    manager.currentAlbum = '일상';
    manager.vlogProjects = <VlogProject>[];
    manager.currentVlogFolder = '';
    manager.vlogAlbums = <String>['기본', '휴지통'];
    final userStatus = UserStatusManager();
    await userStatus.resetToFree();
    await userStatus.initialize();
  });

  tearDown(() async {
    manager.debugSetAutoCloudUploadUploader(null);
    for (final path in manager.recordedVideoPaths) {
      manager.clearClipTransferUiState(path);
      await manager.unmarkClipCloudSynced(path);
    }
    manager.recordedVideoPaths = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  ProjectCloudMetadata cloudProject({
    String projectId = 'cloud-project-1',
    String localProjectId = 'local-project-1',
    String uid = ownerUid,
    String title = 'Cloud Project',
    List<String> clipPaths = const <String>[],
    String folderName = '기본',
    String lockState = 'unlocked',
    DateTime? clientCreatedAt,
    DateTime? clientUpdatedAt,
    DateTime? lastSyncedAt,
    bool deleted = false,
  }) {
    return ProjectCloudMetadata(
      projectId: projectId,
      localProjectId: localProjectId,
      uid: uid,
      title: title,
      clipPaths: clipPaths,
      clipCount: clipPaths.length,
      folderName: folderName,
      lockState: lockState,
      clientCreatedAt: clientCreatedAt,
      clientUpdatedAt: clientUpdatedAt,
      lastSyncedAt: lastSyncedAt,
      deleted: deleted,
    );
  }

  VideoMetadata cloudVideo({
    String videoId = 'cloud-video-1',
    String localPath = 'C:/device-a/raw/clip_a.mp4',
    String fileName = 'clip_a.mp4',
    String albumName = '일상',
    String uploadStatus = 'completed',
    int durationMs = 2100,
  }) {
    return VideoMetadata.fromMap(videoId, <String, dynamic>{
      'uid': ownerUid,
      'fileName': fileName,
      'storagePath': 'users/$ownerUid/videos/$videoId/$fileName',
      'localPath': localPath,
      'albumName': albumName,
      'isFavorite': false,
      'fileSize': 1024,
      'uploadStatus': uploadStatus,
      'uploadProgress': 100,
      'durationMs': durationMs,
    });
  }

  VlogProject localProject({
    String id = 'local-project-1',
    String title = 'Local Project',
    String folderName = '기본',
    String ownerAccountId = ownerUid,
    String clipPath = 'C:/device-a/raw/local.mp4',
    DateTime? updatedAt,
  }) {
    final timestamp = updatedAt ?? DateTime.utc(2026, 6, 5, 10, 0);
    return VlogProject(
      id: id,
      title: title,
      clips: <VlogClip>[VlogClip(path: clipPath)],
      folderName: folderName,
      ownerAccountId: ownerAccountId,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  test(
    'recorded fallback save starts one auto cloud upload with captured album',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'recorded_fallback_upload_',
      );
      try {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProviderChannel, (call) async {
              if (call.method == 'getApplicationDocumentsDirectory') {
                return tempDir.path;
              }
              return null;
            });

        final userStatus = UserStatusManager();
        await userStatus.setUserId(ownerUid);
        await userStatus.setTier(
          UserTier.standard,
          productId: '3s_standard_monthly',
          purchaseDate: DateTime.now(),
        );

        const targetAlbum = '촬영앨범';
        manager.currentAlbum = '일상';
        final sourceFile = File(
          '${tempDir.path}${Platform.pathSeparator}source.mp4',
        );
        await sourceFile.writeAsBytes(<int>[1, 2, 3, 4], flush: true);

        final outputDir = Directory(
          '${tempDir.path}${Platform.pathSeparator}vlogs'
          '${Platform.pathSeparator}raw_clips'
          '${Platform.pathSeparator}$targetAlbum',
        );
        await outputDir.create(recursive: true);
        final outputFile = File(
          '${outputDir.path}${Platform.pathSeparator}recorded.mp4',
        );

        final uploadAlbums = <String>[];
        final uploadPaths = <String>[];
        manager.debugSetAutoCloudUploadUploader(({
          required videoFile,
          required albumName,
          required isFavorite,
          required localPath,
        }) async {
          uploadAlbums.add(albumName);
          uploadPaths.add(localPath);
          return 'cloud-video-id';
        });

        final saved = await manager.debugSaveRecordedVideoFallbackForTesting(
          sourcePath: sourceFile.path,
          outputPath: outputFile.path,
          albumName: targetAlbum,
          sourceDurationMs: 2100,
        );
        await pumpEventQueue();

        expect(saved, isTrue);
        expect(uploadAlbums, <String>[targetAlbum]);
        expect(uploadPaths, <String>[outputFile.path]);
        expect(outputFile.existsSync(), isTrue);
        expect(manager.isClipCloudSynced(outputFile.path), isTrue);
        expect(manager.getClipTransferUiState(outputFile.path), isNull);
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );

  test(
    'auto cloud upload ignores concurrent duplicate enqueue while pending',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'auto_upload_duplicate_',
      );
      try {
        final userStatus = UserStatusManager();
        await userStatus.setUserId(ownerUid);
        await userStatus.setTier(
          UserTier.standard,
          productId: '3s_standard_monthly',
          purchaseDate: DateTime.now(),
        );

        final videoFile = File(
          '${tempDir.path}${Platform.pathSeparator}clip.mp4',
        );
        await videoFile.writeAsBytes(<int>[1, 2, 3, 4], flush: true);

        var uploadCount = 0;
        final uploadStarted = Completer<void>();
        final finishUpload = Completer<String?>();
        manager.debugSetAutoCloudUploadUploader(({
          required videoFile,
          required albumName,
          required isFavorite,
          required localPath,
        }) async {
          uploadCount++;
          if (!uploadStarted.isCompleted) uploadStarted.complete();
          return finishUpload.future;
        });

        final first = manager
            .debugEnqueueAutoCloudUploadAfterLocalSaveForTesting(
              path: videoFile.path,
              albumName: '일상',
            );
        await uploadStarted.future;
        final second = manager
            .debugEnqueueAutoCloudUploadAfterLocalSaveForTesting(
              path: videoFile.path,
              albumName: '일상',
            );
        await pumpEventQueue();

        expect(uploadCount, 1);
        finishUpload.complete('cloud-video-id');
        await Future.wait(<Future<void>>[first, second]);

        expect(uploadCount, 1);
        expect(manager.isClipCloudSynced(videoFile.path), isTrue);
        expect(manager.getClipTransferUiState(videoFile.path), isNull);
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );

  test(
    'successful cloud move does not leave deleted local path marker',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'auto_upload_cleanup_',
      );
      try {
        final userStatus = UserStatusManager();
        await userStatus.setUserId(ownerUid);
        await userStatus.setTier(
          UserTier.standard,
          productId: '3s_standard_monthly',
          purchaseDate: DateTime.now(),
        );

        final videoFile = File(
          '${tempDir.path}${Platform.pathSeparator}clip.mp4',
        );
        await videoFile.writeAsBytes(<int>[1, 2, 3, 4], flush: true);

        manager.debugSetAutoCloudUploadUploader(({
          required videoFile,
          required albumName,
          required isFavorite,
          required localPath,
        }) async {
          await videoFile.delete();
          return 'cloud-video-id';
        });

        await manager.debugEnqueueAutoCloudUploadAfterLocalSaveForTesting(
          path: videoFile.path,
          albumName: '일상',
        );

        expect(videoFile.existsSync(), isFalse);
        expect(manager.isClipCloudSynced(videoFile.path), isFalse);
        expect(manager.getClipTransferUiState(videoFile.path), isNull);
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );

  test('ProjectCloudMetadata parses existing Firestore project fields', () {
    final createdAt = DateTime.utc(2026, 6, 1, 9, 0);
    final updatedAt = DateTime.utc(2026, 6, 2, 9, 0);
    final syncedAt = DateTime.utc(2026, 6, 3, 9, 0);

    final metadata = ProjectCloudMetadata.fromMap('cloud-project-9', {
      'localProjectId': 'local-project-9',
      'uid': ownerUid,
      'title': 'Trip',
      'clipPaths': ['C:/clips/a.mp4', 'C:/clips/b.mp4'],
      'clipCount': 2,
      'folderName': '기본',
      'lockState': 'locked',
      'clientCreatedAt': createdAt.toIso8601String(),
      'clientUpdatedAt': updatedAt.toIso8601String(),
      'lastSyncedAt': syncedAt.toIso8601String(),
      'deleted': false,
    });

    expect(metadata.projectId, 'cloud-project-9');
    expect(metadata.localProjectId, 'local-project-9');
    expect(metadata.uid, ownerUid);
    expect(metadata.title, 'Trip');
    expect(metadata.clipPaths, ['C:/clips/a.mp4', 'C:/clips/b.mp4']);
    expect(metadata.clipCount, 2);
    expect(metadata.folderName, '기본');
    expect(metadata.lockState, 'locked');
    expect(metadata.clientCreatedAt, createdAt);
    expect(metadata.clientUpdatedAt, updatedAt);
    expect(metadata.lastSyncedAt, syncedAt);
    expect(metadata.deleted, isFalse);
  });

  test('cloud project metadata excludes deleted and other owner rows', () {
    final merged = mergeCloudProjectsForProjectList(
      localProjects: const <VlogProject>[],
      cloudProjects: <ProjectCloudMetadata>[
        cloudProject(projectId: 'other-owner', uid: 'user-standard-2'),
        cloudProject(projectId: 'deleted', deleted: true),
        cloudProject(projectId: 'valid', localProjectId: 'valid-local'),
      ],
      cloudVideos: const <VideoMetadata>[],
      ownerAccountId: ownerUid,
      fallbackTimestamp: fallbackTimestamp,
    );

    expect(merged, hasLength(1));
    expect(merged.single.id, 'valid-local');
    expect(merged.single.cloudProjectId, 'valid');
  });

  test(
    'cloud project without local JSON appears in same account project list',
    () {
      const localClipPath = 'C:/device-a/raw/clip_a.mp4';

      final merged = mergeCloudProjectsForProjectList(
        localProjects: const <VlogProject>[],
        cloudProjects: <ProjectCloudMetadata>[
          cloudProject(
            projectId: 'cloud-project-1',
            localProjectId: 'local-project-1',
            title: 'Morning',
            clipPaths: const <String>[localClipPath],
            folderName: '기본',
            lastSyncedAt: DateTime.utc(2026, 6, 6, 2, 0),
          ),
        ],
        cloudVideos: <VideoMetadata>[
          cloudVideo(localPath: localClipPath, durationMs: 2100),
        ],
        ownerAccountId: ownerUid,
        fallbackTimestamp: fallbackTimestamp,
      );

      expect(merged, hasLength(1));
      final project = merged.single;
      expect(project.id, 'local-project-1');
      expect(project.cloudProjectId, 'cloud-project-1');
      expect(project.ownerAccountId, ownerUid);
      expect(project.folderName, '기본');
      expect(project.clips, hasLength(1));
      expect(project.clips.single.path, startsWith('cloud_only://'));
      expect(project.clips.single.path, contains('cloud-video-1'));
      expect(project.clips.single.originalDuration.inMilliseconds, 2100);
      expect(project.clips.single.endTime.inMilliseconds, 2100);
    },
  );

  test(
    'cloud project without completed video metadata appears without source device path clips',
    () {
      const sourceDevicePath = 'C:/device-a/raw/missing.mp4';
      final merged = mergeCloudProjectsForProjectList(
        localProjects: const <VlogProject>[],
        cloudProjects: <ProjectCloudMetadata>[
          cloudProject(
            projectId: 'cloud-project-with-unresolved-clip',
            localProjectId: 'local-project-with-unresolved-clip',
            title: 'Visible Cloud Project',
            clipPaths: const <String>[sourceDevicePath],
          ),
        ],
        cloudVideos: const <VideoMetadata>[],
        ownerAccountId: ownerUid,
        fallbackTimestamp: fallbackTimestamp,
      );

      expect(merged, hasLength(1));
      expect(merged.single.title, 'Visible Cloud Project');
      expect(merged.single.clips, isEmpty);
      expect(
        merged.single.toJson().toString(),
        isNot(contains(sourceDevicePath)),
      );
    },
  );

  test(
    'materialized cloud project remaps missing source-device path when video metadata arrives',
    () {
      const sourceDevicePath = 'C:/__moa_missing__/device-a/raw/clip_a.mp4';

      final merged = mergeCloudProjectsForProjectList(
        localProjects: <VlogProject>[
          localProject(
            id: 'local-project-1',
            title: 'Previously Materialized',
            clipPath: sourceDevicePath,
          ),
        ],
        cloudProjects: <ProjectCloudMetadata>[
          cloudProject(
            projectId: 'cloud-project-1',
            localProjectId: 'local-project-1',
            clipPaths: const <String>[sourceDevicePath],
            lastSyncedAt: DateTime.utc(2026, 6, 6, 2, 0),
          ),
        ],
        cloudVideos: <VideoMetadata>[
          cloudVideo(localPath: sourceDevicePath, durationMs: 2200),
        ],
        ownerAccountId: ownerUid,
        fallbackTimestamp: fallbackTimestamp,
      );

      expect(merged, hasLength(1));
      expect(merged.single.title, 'Previously Materialized');
      expect(merged.single.clips.single.path, startsWith('cloud_only://'));
      expect(merged.single.clips.single.path, contains('cloud-video-1'));
      expect(merged.single.clips.single.originalDuration.inMilliseconds, 2200);
    },
  );

  test(
    'ambiguous duplicate filenames keep project shell without basename materialization',
    () {
      final merged = mergeCloudProjectsForProjectList(
        localProjects: const <VlogProject>[],
        cloudProjects: <ProjectCloudMetadata>[
          cloudProject(
            projectId: 'cloud-project-duplicate-name',
            localProjectId: 'local-project-duplicate-name',
            clipPaths: const <String>['C:/other-device/raw/shared.mp4'],
          ),
        ],
        cloudVideos: <VideoMetadata>[
          cloudVideo(
            videoId: 'cloud-video-a',
            localPath: 'C:/device-a/raw/shared.mp4',
            fileName: 'shared.mp4',
          ),
          cloudVideo(
            videoId: 'cloud-video-b',
            localPath: 'C:/device-b/raw/shared.mp4',
            fileName: 'shared.mp4',
          ),
        ],
        ownerAccountId: ownerUid,
        fallbackTimestamp: fallbackTimestamp,
      );

      expect(merged, hasLength(1));
      expect(merged.single.clips, isEmpty);
    },
  );

  test('cloud-only project clip path matches embedded video id', () {
    final merged = mergeCloudProjectsForProjectList(
      localProjects: const <VlogProject>[],
      cloudProjects: <ProjectCloudMetadata>[
        cloudProject(
          projectId: 'cloud-project-placeholder',
          localProjectId: 'local-project-placeholder',
          clipPaths: const <String>['cloud_only://일상/cloud-video-b/shared.mp4'],
        ),
      ],
      cloudVideos: <VideoMetadata>[
        cloudVideo(
          videoId: 'cloud-video-a',
          localPath: 'C:/device-a/raw/shared.mp4',
          fileName: 'shared.mp4',
        ),
        cloudVideo(
          videoId: 'cloud-video-b',
          localPath: 'C:/device-b/raw/shared.mp4',
          fileName: 'shared.mp4',
        ),
      ],
      ownerAccountId: ownerUid,
      fallbackTimestamp: fallbackTimestamp,
    );

    expect(merged, hasLength(1));
    expect(merged.single.clips.single.path, contains('cloud-video-b'));
  });

  test(
    'local project and cloud project with same localProjectId merge without duplicate cards',
    () {
      final localUpdatedAt = DateTime.utc(2026, 6, 5, 10, 0);
      final merged = mergeCloudProjectsForProjectList(
        localProjects: <VlogProject>[
          localProject(
            id: 'local-project-1',
            title: 'Local Title Wins',
            folderName: '기본',
            updatedAt: localUpdatedAt,
          ),
        ],
        cloudProjects: <ProjectCloudMetadata>[
          cloudProject(
            projectId: 'cloud-project-1',
            localProjectId: 'local-project-1',
            title: 'Cloud Title',
            folderName: 'Travel',
            lockState: 'locked',
            lastSyncedAt: DateTime.utc(2026, 6, 6, 2, 0),
          ),
        ],
        cloudVideos: const <VideoMetadata>[],
        ownerAccountId: ownerUid,
        fallbackTimestamp: fallbackTimestamp,
      );

      expect(merged, hasLength(1));
      final project = merged.single;
      expect(project.id, 'local-project-1');
      expect(project.title, 'Local Title Wins');
      expect(project.folderName, '기본');
      expect(project.lockState, 'unlocked');
      expect(project.cloudProjectId, 'cloud-project-1');
      expect(project.cloudSyncedAt, DateTime.utc(2026, 6, 6, 2, 0));
      expect(project.updatedAt, localUpdatedAt);
    },
  );

  test(
    'cloud project with session cache clip path is not persisted or materialized',
    () {
      final merged = mergeCloudProjectsForProjectList(
        localProjects: const <VlogProject>[],
        cloudProjects: <ProjectCloudMetadata>[
          cloudProject(
            projectId: 'unsafe-cloud-project',
            localProjectId: 'unsafe-local-project',
            clipPaths: const <String>[
              'C:/app/edit_session_cache/session-1/clip.mp4',
            ],
          ),
        ],
        cloudVideos: const <VideoMetadata>[],
        ownerAccountId: ownerUid,
        fallbackTimestamp: fallbackTimestamp,
      );

      expect(merged, isEmpty);
    },
  );

  test(
    'cloud project with remote clip path is not materialized by basename',
    () {
      final merged = mergeCloudProjectsForProjectList(
        localProjects: const <VlogProject>[],
        cloudProjects: <ProjectCloudMetadata>[
          cloudProject(
            projectId: 'remote-cloud-project',
            localProjectId: 'remote-local-project',
            clipPaths: const <String>[
              'https://cdn.example.invalid/users/user/videos/video-a/clip_a.mp4',
              'gs://bucket/users/user/videos/video-a/clip_a.mp4',
              'users/user/videos/video-a/clip_a.mp4',
            ],
          ),
        ],
        cloudVideos: <VideoMetadata>[
          cloudVideo(videoId: 'video-a', fileName: 'clip_a.mp4'),
        ],
        ownerAccountId: ownerUid,
        fallbackTimestamp: fallbackTimestamp,
      );

      expect(merged, isEmpty);
    },
  );

  test(
    'default project folder count remains stable across loadProjects refresh',
    () {
      final manager = VideoManager();
      manager.vlogProjects = <VlogProject>[
        localProject(id: 'default-1', folderName: '기본'),
        localProject(id: 'default-2', folderName: '기본'),
        localProject(id: 'default-3', folderName: '기본'),
        for (var index = 0; index < 7; index++)
          localProject(id: 'travel-$index', folderName: 'Travel'),
      ];
      manager.currentVlogFolder = '기본';

      final beforeGridCount = manager.projectCountInFolder('기본');
      final beforeDetailCount = manager.filteredProjects.length;

      manager.vlogProjects = mergeCloudProjectsForProjectList(
        localProjects: manager.vlogProjects,
        cloudProjects: const <ProjectCloudMetadata>[],
        cloudVideos: const <VideoMetadata>[],
        ownerAccountId: ownerUid,
        fallbackTimestamp: fallbackTimestamp,
      );

      expect(beforeGridCount, 3);
      expect(beforeDetailCount, 3);
      expect(manager.projectCountInFolder('기본'), 3);
      expect(manager.filteredProjects, hasLength(3));
    },
  );

  test(
    'empty current project folder never renders as default folder detail',
    () {
      final manager = VideoManager();
      manager.vlogProjects = <VlogProject>[
        localProject(id: 'default-1', folderName: '기본'),
        localProject(id: 'default-2', folderName: '기본'),
        localProject(id: 'default-3', folderName: '기본'),
        for (var index = 0; index < 7; index++)
          localProject(id: 'travel-$index', folderName: 'Travel'),
      ];

      manager.currentVlogFolder = '';
      expect(manager.filteredProjects, isEmpty);
      expect(manager.projectCountInFolder('기본'), 3);

      manager.currentVlogFolder = '기본';
      expect(manager.filteredProjects, hasLength(3));
    },
  );

  test('project folders include cloud-only project folders', () {
    final folders = mergeProjectFoldersForProjectList(
      existingFolders: const <String>['기본', '휴지통'],
      projects: <VlogProject>[
        localProject(id: 'default-1', folderName: '기본'),
        localProject(id: 'cloud-travel-1', folderName: 'Travel'),
        localProject(id: 'cloud-default-1', folderName: '기본'),
      ],
    );

    expect(folders, <String>['기본', 'Travel', '휴지통']);
  });

  test('cloud api unavailable classification excludes policy failures', () {
    expect(
      CloudService.isCloudApiUnavailableReservationError(
        const CloudUsageServiceException(
          code: 'invalid_response',
          message: 'not json',
        ),
      ),
      isFalse,
    );
    expect(
      CloudService.isCloudApiUnavailableReservationError(
        const CloudUsageServiceException(
          code: 'not-found',
          message: 'domain row missing',
        ),
      ),
      isFalse,
    );
    expect(
      CloudService.isCloudApiUnavailableReservationError(
        const CloudUsageServiceException(
          code: 'unimplemented',
          message: 'function missing',
        ),
      ),
      isTrue,
    );
    expect(
      CloudService.isCloudApiUnavailableReservationError(
        const CloudUsageServiceException(
          code: 'http_404',
          message: 'function missing',
        ),
      ),
      isTrue,
    );
    expect(
      CloudService.isCloudApiUnavailableReservationError(
        const CloudUsageServiceException(
          code: 'permission-denied',
          message: 'not entitled',
        ),
      ),
      isFalse,
    );
    expect(
      CloudService.isCloudApiUnavailableReservationError(
        const CloudUsageServiceException(
          code: 'resource-exhausted',
          message: 'quota exceeded',
        ),
      ),
      isFalse,
    );
    expect(
      CloudService.isCloudApiUnavailableReservationError(
        const CloudUsageServiceException(
          code: 'failed-precondition',
          message: 'metadata rejected',
        ),
      ),
      isFalse,
    );
  });
}
