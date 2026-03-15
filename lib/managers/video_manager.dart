import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as thum;
import 'package:gal/gal.dart';
import 'package:video_player/video_player.dart';

import 'dart:convert';
import 'user_status_manager.dart';
import '../models/vlog_project.dart';
import '../services/cloud_service.dart';
import '../services/local_index_service.dart';
import '../utils/quality_policy.dart';

enum ClipTransferUiState {
  pendingUpload,
  pendingDownload,
  failedUpload,
  failedDownload,
}

class VideoManager extends ChangeNotifier {
  static final VideoManager _instance = VideoManager._internal();
  factory VideoManager() => _instance;
  VideoManager._internal();
  static const int trimTimelineThumbCount = 3;
  static const int _timelineThumbMetaVersion = 1;

  static const _rawBaseName = 'raw_clips';
  static const _projectBaseName = 'vlog_projects';
  static const _vlogFoldersBaseName = 'vlog_folders';
  static const _systemClipAlbums = ['일상', '휴지통'];
  static const _systemVlogAlbums = ['기본', '휴지통'];
  static const _cloudSyncedKey = 'cloud_synced_paths';
  static const _clipDurationMetadataKey = 'clip_duration_metadata_v1';
  static const _clipOwnershipMetadataKey = 'clip_ownership_metadata_v1';
  static const List<String> _tutorialSampleAssets = [
    'assets/tutorial/videos/tutorial_clip_capture_day.mp4',
    'assets/tutorial/videos/tutorial_clip_capture_night.mp4',
  ];

  // ✅ 독립된 폴더 시스템
  String currentAlbum = "일상";
  String currentVlogFolder = "";
  List<String> clipAlbums = List.from(_systemClipAlbums);
  List<String> vlogAlbums = List.from(_systemVlogAlbums);
  List<String> recordedVideoPaths = [];
  List<String> vlogProjectPaths = [];
  Set<String> favorites = {};
  final Map<String, Uint8List> thumbnailCache = {};
  Map<String, int> albumCounts = {}; // Public variable for UI
  final Map<String, List<Uint8List>> _timelineCache =
      {}; // Cache for timeline thumbnails
  final Map<String, Duration> _durationCache = {}; // Cache for video durations
  final Map<String, int> _persistedDurationMs = {};
  final Set<String> _cloudSyncedPaths = {};
  final Map<String, ClipTransferUiState> _clipTransferUiStateByPath = {};
  final Map<String, String?> _clipOwnerAccountByPath = {};
  final LocalIndexService _localIndexService = LocalIndexService();

  // ✅ 프로젝트 리스트 (Phase 5)
  List<VlogProject> vlogProjects = [];

  // 앱 시작 시 호출 (initAlbumSystem 등에서 호출)
  Future<void> loadProjects() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final projectDir = Directory(p.join(appDir.path, 'vlog_projects'));

      if (!await projectDir.exists()) {
        await projectDir.create(recursive: true);
        vlogProjects = [];
      } else {
        // .json 파일 모두 읽기
        final files = projectDir.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.json'),
        );

        vlogProjects = files
            .map((file) {
              try {
                final jsonStr = file.readAsStringSync();
                return VlogProject.fromJson(jsonDecode(jsonStr));
              } catch (e) {
                print("Error parsing project: ${file.path}");
                return null;
              }
            })
            .whereType<VlogProject>()
            .toList();

        // 최신순 정렬
        vlogProjects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      }

      await _hydrateProjectCloudMetadata();
      notifyListeners();
    } catch (e) {
      print("Error loading projects: $e");
    }
  }

  Future<void> _hydrateProjectCloudMetadata() async {
    final cloudMap = await CloudService().getUserVlogProjectMetadataMap();
    if (cloudMap.isEmpty) return;

    bool changed = false;
    vlogProjects = vlogProjects.map((project) {
      final cloud = cloudMap[project.id];
      if (cloud == null) return project;

      final bool sameId = project.cloudProjectId == cloud.projectId;
      final bool sameTime = project.cloudSyncedAt == cloud.lastSyncedAt;
      if (sameId && sameTime) return project;

      changed = true;
      return project.copyWith(
        cloudProjectId: cloud.projectId,
        cloudSyncedAt: cloud.lastSyncedAt,
        updatedAt: project.updatedAt,
      );
    }).toList();

    if (!changed) return;

    for (final project in vlogProjects) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final projectDir = Directory(p.join(appDir.path, 'vlog_projects'));
        if (!await projectDir.exists()) {
          await projectDir.create(recursive: true);
        }
        final file = File(p.join(projectDir.path, '${project.id}.json'));
        await file.writeAsString(jsonEncode(project.toJson()));
      } catch (_) {
        // 로컬 보정 저장 실패는 무시하고 UI 반영 우선
      }
    }
  }

  // 현재 폴더에 맞는 프로젝트 필터링
  List<VlogProject> get filteredProjects {
    if (currentVlogFolder == '휴지통') {
      return vlogProjects.where((p) => p.folderName == '휴지통').toList();
    }
    // 휴지통이 아닌 경우: 해당 폴더인 것만 (단, '기본'의 경우 null도 포괄 가능하지만, 모델 기본값이 '기본'이므로 일치 비교)
    // 폴더 이동 시 '휴지통'으로 보내지 않은 프로젝트만 보여야 함 (휴지통 기능이 폴더 필드로 통합됨)
    // 만약 currentVlogFolder가 비어있으면(전체보기?) -> 요구사항은 currentVlogFolder 사용
    if (currentVlogFolder.isEmpty)
      return vlogProjects
          .where((p) => p.folderName != '휴지통')
          .toList(); // Fallback

    return vlogProjects
        .where((p) => p.folderName == currentVlogFolder)
        .toList();
  }

  // 프로젝트 폴더 이동
  Future<void> moveProjectToFolder(
    VlogProject project,
    String targetFolder,
  ) async {
    final updatedProject = project.copyWith(
      folderName: targetFolder,
      trashedFromFolderName: null,
    );
    await saveProject(updatedProject);
    notifyListeners();
  }

  Future<void> restoreProjectFromTrash(VlogProject project) async {
    final base = await _vlogFoldersBaseDir();
    final origin = project.trashedFromFolderName?.trim();
    String targetFolder = '기본';

    if (origin != null &&
        origin.isNotEmpty &&
        origin != '휴지통' &&
        origin != '일상') {
      final originDir = Directory(p.join(base.path, origin));
      if (await originDir.exists()) {
        targetFolder = origin;
      }
    }

    final restoredProject = project.copyWith(
      folderName: targetFolder,
      trashedFromFolderName: null,
    );
    await saveProject(restoredProject);
    notifyListeners();
  }

  Future<void> copyProjectToFolder(
    VlogProject project,
    String targetFolder,
  ) async {
    final timestamp = DateTime.now();
    final copiedProject = VlogProject(
      id: '${timestamp.microsecondsSinceEpoch}_${project.id.hashCode}',
      title: '${project.title} (Copy)',
      clips: project.clips
          .map(
            (clip) => clip.copyWith(
              id: '${timestamp.microsecondsSinceEpoch}_${clip.id.hashCode}',
            ),
          )
          .toList(),
      audioConfig: Map<String, double>.from(project.audioConfig),
      bgmPath: project.bgmPath,
      bgmVolume: project.bgmVolume,
      quality: project.quality,
      isFavorite: project.isFavorite,
      folderName: targetFolder,
      ownerAccountId: project.ownerAccountId,
      lockState: project.lockState,
      trashedFromFolderName: null,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    vlogProjects.insert(0, copiedProject);
    await saveProject(copiedProject);
    notifyListeners();
  }

  // 새 프로젝트 생성
  Future<VlogProject> createProject(List<String> videoPaths) async {
    final timestamp = DateTime.now();
    final ownerUid = UserStatusManager().userId;
    // 현재 폴더가 휴지통이면 '기본'으로 생성, 아니면 현재 폴더 사용
    final folder = (currentVlogFolder == '휴지통' || currentVlogFolder.isEmpty)
        ? '기본'
        : currentVlogFolder;

    // Create initial clips from paths
    final clips = videoPaths.map((path) => VlogClip(path: path)).toList();

    // Pre-cache durations for all clips (so edit screen doesn't need temp controllers)
    for (final clip in clips) {
      final duration = await getVideoDuration(clip.path);
      clip.originalDuration = duration; // Store original duration
      if (clip.endTime == Duration.zero) {
        clip.endTime = duration;
      }
      if (duration > Duration.zero) {
        await ensureTimelineThumbnailMetadataForClip(
          clip,
          durationMs: duration.inMilliseconds,
          count: trimTimelineThumbCount,
        );
      }
    }
    debugPrint('[VideoManager] Pre-cached durations for ${clips.length} clips');

    final newProject = VlogProject(
      id: timestamp.millisecondsSinceEpoch.toString(),
      title: "Vlog_${timestamp.year}${timestamp.month}${timestamp.day}",
      clips: clips, // Use clips instead of videoPaths
      folderName: folder,
      ownerAccountId: ownerUid,
      lockState: 'unlocked',
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    vlogProjects.insert(0, newProject); // 리스트 맨 앞에 추가
    await saveProject(newProject);
    notifyListeners();
    return newProject;
  }

  // 프로젝트 저장 (파일 덮어쓰기)
  Future<void> saveProject(VlogProject project) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final projectDir = Directory(p.join(appDir.path, 'vlog_projects'));
      if (!await projectDir.exists()) await projectDir.create(recursive: true);

      var projectToSave = project;

      final cloudMeta = await CloudService().upsertVlogProjectMetadata(project);
      if (cloudMeta != null) {
        projectToSave = project.copyWith(
          cloudProjectId: cloudMeta.projectId,
          cloudSyncedAt: cloudMeta.lastSyncedAt,
          updatedAt: project.updatedAt,
        );
      }

      final file = File(p.join(projectDir.path, '${project.id}.json'));
      await file.writeAsString(jsonEncode(projectToSave.toJson()));

      // 리스트 내 상태 업데이트 (필요 시)
      final index = vlogProjects.indexWhere((p) => p.id == project.id);
      if (index != -1) {
        vlogProjects[index] = projectToSave;
      }

      await _upsertLocalIndexProject(projectToSave);
    } catch (e) {
      print("Error saving project: $e");
    }
  }

  // 프로젝트 삭제
  Future<void> deleteProject(String id) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final file = File(p.join(appDir.path, 'vlog_projects', '$id.json'));

      VlogProject? target;
      for (final p in vlogProjects) {
        if (p.id == id) {
          target = p;
          break;
        }
      }
      await CloudService().deleteVlogProjectMetadata(
        localProjectId: id,
        cloudProjectId: target?.cloudProjectId,
      );

      if (await file.exists()) {
        await file.delete();
      }

      vlogProjects.removeWhere((p) => p.id == id);
      await _removeLocalIndexByKey(id);
      notifyListeners();
    } catch (e) {
      print("Error deleting project: $e");
    }
  }

  static const platform = MethodChannel('com.dk.three_sec/video_engine');
  static const int _targetRecordingDurationMs = 3000;
  static const String _recordingTrimMode = 'center';

  Future<Directory> _docDir() async => await getApplicationDocumentsDirectory();

  Future<Directory> _rawBaseDir() async {
    final dir = Directory(
      p.join((await _docDir()).path, 'vlogs', _rawBaseName),
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _projectBaseDir() async {
    final dir = Directory(
      p.join((await _docDir()).path, 'vlogs', _projectBaseName),
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _vlogFoldersBaseDir() async {
    final dir = Directory(
      p.join((await _docDir()).path, 'vlogs', _vlogFoldersBaseName),
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _rawAlbumDir(String album) async {
    final base = await _rawBaseDir();
    final dir = Directory(p.join(base.path, album));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _vlogFolderDir(String folderName) async {
    final base = await _vlogFoldersBaseDir();
    final dir = Directory(p.join(base.path, folderName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  bool _isReservedClipAlbum(String name) => _systemClipAlbums.contains(name);
  bool _isReservedVlogAlbum(String name) => _systemVlogAlbums.contains(name);

  Future<void> _updateAlbumClipCounts() async {
    final rawBase = await _rawBaseDir();
    final newCounts = <String, int>{};

    // 전체 앨범 순회
    for (final albumName in clipAlbums) {
      final albumDir = Directory(p.join(rawBase.path, albumName));
      if (await albumDir.exists()) {
        final count = albumDir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.mp4'))
            .length;
        newCounts[albumName] = count;
      } else {
        newCounts[albumName] = 0;
      }
    }

    albumCounts = newCounts;
    notifyListeners();
  }

  Future<List<String>> _listProjectFiles() async {
    final projectDir = await _projectBaseDir();
    final files = projectDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.mp4'))
        .toList();
    files.sort(
      (a, b) => File(
        b.path,
      ).lastModifiedSync().compareTo(File(a.path).lastModifiedSync()),
    );
    return files.map((f) => f.path).toList();
  }

  Future<Uint8List?> getThumbnail(String videoPath) async {
    if (thumbnailCache.containsKey(videoPath)) return thumbnailCache[videoPath];

    final docDir = await getApplicationDocumentsDirectory();
    final thumbDir = Directory(p.join(docDir.path, 'thumbnails'));
    if (!await thumbDir.exists()) await thumbDir.create(recursive: true);

    final thumbFile = File(
      p.join(thumbDir.path, "${p.basename(videoPath)}.jpg"),
    );

    if (await thumbFile.exists()) {
      final data = await thumbFile.readAsBytes();
      thumbnailCache[videoPath] = data;
      return data;
    }

    if (!await File(videoPath).exists()) {
      return null;
    }

    final data = await thum.VideoThumbnail.thumbnailData(
      video: videoPath,
      imageFormat: thum.ImageFormat.JPEG,
      maxWidth: 400,
      quality: 70,
    );

    if (data != null) {
      thumbnailCache[videoPath] = data;
      thumbFile.writeAsBytes(data).catchError((_) => thumbFile);
    }
    return data;
  }

  // Get multiple thumbnails distributed evenly across duration
  /// Get cached video duration. Creates a temporary controller only on first call.
  Future<Duration> getVideoDuration(String videoPath) async {
    if (_durationCache.containsKey(videoPath)) {
      return _durationCache[videoPath]!;
    }

    final persistedMs = _persistedDurationMs[videoPath];
    if (persistedMs != null && persistedMs > 0) {
      final persisted = Duration(milliseconds: persistedMs);
      _durationCache[videoPath] = persisted;
      return persisted;
    }

    final file = File(videoPath);
    if (!await file.exists()) return Duration.zero;

    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(file);
      await controller.initialize();
      final duration = controller.value.duration;
      await _setDurationCacheForPath(videoPath, duration);
      debugPrint(
        '[VideoManager] Cached duration for ${videoPath.split('/').last}: $duration',
      );
      return duration;
    } catch (e) {
      debugPrint('[VideoManager] Error getting duration: $e');
      return Duration.zero;
    } finally {
      await controller?.dispose();
      // Brief delay to allow native codec cleanup
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<List<Uint8List>> getTimelineThumbnails(
    String videoPath,
    int durationMs,
    int count, {
    VlogClip? clip,
  }) async {
    final List<Uint8List> thumbnails = [];
    if (durationMs <= 0 || count <= 0) return thumbnails;

    // Check memory cache
    final String cacheKey = "${videoPath}_${count}_$durationMs";
    if (_timelineCache.containsKey(cacheKey)) {
      return _timelineCache[cacheKey]!;
    }

    if (clip != null) {
      final fromMeta = await _loadTimelineThumbnailsFromClipMetadata(
        clip,
        durationMs: durationMs,
        count: count,
      );
      if (fromMeta.length == count) {
        _timelineCache[cacheKey] = fromMeta;
        return fromMeta;
      }
    }

    final interval = durationMs ~/ count;

    for (int i = 0; i < count; i++) {
      final timeMs = (interval * i) + (interval ~/ 2);
      try {
        final data = await thum.VideoThumbnail.thumbnailData(
          video: videoPath,
          imageFormat: thum.ImageFormat.JPEG,
          maxWidth: 150, // Small width for timeline
          quality: 50, // Lower quality for performance
          timeMs: timeMs,
        );
        if (data != null) {
          thumbnails.add(data);
        }
      } catch (e) {
        debugPrint("Error generating timeline thumb $i: $e");
      }
    }

    // Save to cache
    if (thumbnails.isNotEmpty) {
      _timelineCache[cacheKey] = thumbnails;
    }

    if (clip != null && thumbnails.length == count) {
      await _persistTimelineThumbMetadata(
        clip,
        videoPath: videoPath,
        durationMs: durationMs,
        count: count,
        bytesList: thumbnails,
      );
    }

    return thumbnails;
  }

  Future<bool> ensureTimelineThumbnailMetadataForClip(
    VlogClip clip, {
    required int durationMs,
    int count = trimTimelineThumbCount,
  }) async {
    final oldVersion = clip.timelineThumbMetaVersion;
    final oldDuration = clip.timelineThumbDurationMs;
    final oldCount = clip.timelineThumbCount;
    final oldPaths = List<String>.from(clip.timelineThumbPaths);

    await getTimelineThumbnails(clip.path, durationMs, count, clip: clip);

    return oldVersion != clip.timelineThumbMetaVersion ||
        oldDuration != clip.timelineThumbDurationMs ||
        oldCount != clip.timelineThumbCount ||
        !_listEquals(oldPaths, clip.timelineThumbPaths);
  }

  Future<List<Uint8List>> _loadTimelineThumbnailsFromClipMetadata(
    VlogClip clip, {
    required int durationMs,
    required int count,
  }) async {
    final metaValid =
        clip.timelineThumbMetaVersion == _timelineThumbMetaVersion &&
        clip.timelineThumbDurationMs == durationMs &&
        clip.timelineThumbCount == count &&
        clip.timelineThumbPaths.length == count;
    if (!metaValid) return const [];

    final loaded = <Uint8List>[];
    for (final path in clip.timelineThumbPaths) {
      final file = File(path);
      if (!await file.exists()) {
        return const [];
      }
      loaded.add(await file.readAsBytes());
    }
    return loaded;
  }

  Future<void> _persistTimelineThumbMetadata(
    VlogClip clip, {
    required String videoPath,
    required int durationMs,
    required int count,
    required List<Uint8List> bytesList,
  }) async {
    final thumbDir = await _timelineThumbDir();
    final baseKey = _timelineThumbBaseKey(videoPath);
    final newPaths = <String>[];

    for (var i = 0; i < bytesList.length; i++) {
      final filePath = p.join(
        thumbDir.path,
        '${baseKey}_v${_timelineThumbMetaVersion}_${durationMs}_${count}_$i.jpg',
      );
      final file = File(filePath);
      await file.writeAsBytes(bytesList[i], flush: false);
      newPaths.add(filePath);
    }

    clip.timelineThumbMetaVersion = _timelineThumbMetaVersion;
    clip.timelineThumbDurationMs = durationMs;
    clip.timelineThumbCount = count;
    clip.timelineThumbPaths = newPaths;
  }

  Future<Directory> _timelineThumbDir() async {
    final dir = Directory(
      p.join((await _docDir()).path, 'thumbnails', 'timeline'),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _timelineThumbBaseKey(String videoPath) {
    final name = p
        .basenameWithoutExtension(videoPath)
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final hash = _stablePathHash(videoPath);
    return '${name}_$hash';
  }

  String _stablePathHash(String input) {
    var hash = 0;
    for (final code in input.codeUnits) {
      hash = ((hash * 31) + code) & 0x7fffffff;
    }
    return hash.toRadixString(16);
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> convertPhotoToVideo(String imagePath, String targetAlbum) async {
    final outDir = await _rawAlbumDir(targetAlbum);
    final String outPath = p.join(
      outDir.path,
      "photo_${DateTime.now().millisecondsSinceEpoch}.mp4",
    );

    final String result = await platform.invokeMethod('convertImageToVideo', {
      'imagePath': imagePath,
      'outputPath': outPath,
      'duration': 3,
    });

    if (result != "SUCCESS") {
      throw Exception("Native Conversion Error: $result");
    }
    await _setClipOwnership(
      outPath,
      ownerAccountId: UserStatusManager().userId,
    );
    await _updateAlbumClipCounts();
  }

  // 2. Vlog 추출 (Native Engine 호출)
  Future<String?> exportVlog({
    required List<VlogClip> clips, // Changed to List<VlogClip>
    required Map<String, double> audioConfig,
    String? bgmPath,
    double bgmVolume = 0.5,
    String quality = '1080p',
    String userTier = 'free',
  }) async {
    try {
      final normalizedTier = normalizeUserTierKey(userTier);
      final clampedQuality = clampExportQualityForTier(
        requestedQuality: normalizeExportQuality(quality),
        tier: userTierFromKey(normalizedTier),
      );

      // 1. 🛡️ 권한 체크 (Android 13 대응)
      bool hasPermission = false;

      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (androidInfo.version.sdkInt >= 33) {
          // Android 13 이상: 세분화된 미디어 권한 필요
          final videos = await Permission.videos.request();
          final audio = await Permission.audio.request();
          // photos 권한은 이미지/비디오 혼합 시 필요할 수 있음
          final photos = await Permission.photos.request();

          hasPermission = videos.isGranted || photos.isGranted;
        } else {
          // Android 12 이하: 저장소 권한 필요
          final storage = await Permission.storage.request();
          hasPermission = storage.isGranted;
        }
      } else {
        // iOS
        hasPermission = true; // 보통 갤러리 접근 시 자동 처리되거나 별도 로직
      }

      if (!hasPermission) {
        print("❌ Export Error: 권한이 거부되었습니다.");
        // UI에서 처리를 위해 예외 발생 또는 null 리턴
        return null;
      }

      // 2. 📂 경로 설정
      final docDir = await getApplicationDocumentsDirectory();
      final vlogDir = Directory(p.join(docDir.path, 'Vlogs'));
      if (!await vlogDir.exists()) {
        await vlogDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = p.join(vlogDir.path, 'vlog_$timestamp.mp4');

      // 3. 🎞️ 대상 파일 준비
      if (clips.isEmpty) {
        print("❌ Export Error: 병합할 영상이 없습니다.");
        return null;
      }

      print("🚀 Start Exporting... (Count: ${clips.length})");
      print("   - Output: $outputPath");
      print("   - Quality: $clampedQuality");
      print("   - User Tier: $normalizedTier");

      // Extract data for native call
      final videoPaths = clips.map((c) => c.path).toList();
      final startTimes = clips.map((c) => c.startTime.inMilliseconds).toList();
      final endTimes = clips.map((c) => c.endTime.inMilliseconds).toList();

      // 4. ⚡ Native Engine 호출
      final args = {
        'videoPaths': videoPaths,
        'startTimes': startTimes, // Pass start times
        'endTimes': endTimes, // Pass end times
        'outputPath': outputPath,
        'audioChanges': audioConfig,
        'bgmPath': bgmPath,
        'bgmVolume': bgmVolume,
        'quality': clampedQuality,
        'userTier': normalizedTier,
      };

      final String? result = await platform.invokeMethod('mergeVideos', args);

      print("✅ Export Success: $result");

      // 갤러리에 저장 (Gal 패키지 사용)
      if (result != null) {
        try {
          await Gal.putVideo(result, album: '3S_Vlogs');
          print("✅ Saved to Gallery (Album: 3S_Vlogs)");
        } catch (e) {
          print("❌ Failed to save to gallery: $e");
        }
      }

      return result;
    } on PlatformException catch (e) {
      print("❌ Native Error: ${e.message}");
      return null;
    } catch (e) {
      print("❌ Unexpected Error: $e");
      return null;
    }
  }

  // 휴지통으로 이동
  Future<void> moveProjectToTrash(String projectId) async {
    final index = vlogProjects.indexWhere((p) => p.id == projectId);
    if (index != -1) {
      final project = vlogProjects[index];
      final currentFolder = project.folderName;
      final updated = project.copyWith(
        folderName: '휴지통',
        trashedFromFolderName: currentFolder == '휴지통'
            ? project.trashedFromFolderName
            : currentFolder,
      );
      await saveProject(updated);
      notifyListeners();
    }
  }

  // ✅ Data Statistics Getters & Methods
  int get totalClipCount {
    int count = 0;
    for (var c in albumCounts.values) {
      count += c;
    }
    return count;
  }

  int get totalVlogCount => _vlogProjectCountCache;
  int _vlogProjectCountCache = 0;

  Future<void> _updateVlogProjectCount() async {
    final files = await _listProjectFiles();
    _vlogProjectCountCache = files.length;
    notifyListeners();
  }

  Future<String> calculateStorageUsage() async {
    int totalBytes = 0;

    final dirs = [
      await _rawBaseDir(),
      await _projectBaseDir(),
      await _vlogFoldersBaseDir(),
    ];

    for (final dir in dirs) {
      if (await dir.exists()) {
        await for (final file in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (file is File) totalBytes += await file.length();
        }
      }
    }

    if (totalBytes < 1024) return "$totalBytes B";
    if (totalBytes < 1024 * 1024)
      return "${(totalBytes / 1024).toStringAsFixed(1)} KB";
    if (totalBytes < 1024 * 1024 * 1024)
      return "${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    return "${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB";
  }

  Future<void> initAlbumSystem() async {
    final rawBase = await _rawBaseDir();
    final vlogBase = await _vlogFoldersBaseDir();
    await _loadCloudSyncedPaths();
    await _loadClipDurationMetadata();
    await _loadClipOwnershipMetadata();

    // ✅ 2. 독립 휴지통 생성
    // 라이브러리 시스템 폴더
    for (final systemName in _systemClipAlbums) {
      final dir = Directory(p.join(rawBase.path, systemName));
      if (!await dir.exists()) await dir.create(recursive: true);
    }

    // Vlog 시스템 폴더
    for (final systemName in _systemVlogAlbums) {
      final dir = Directory(p.join(vlogBase.path, systemName));
      if (!await dir.exists()) await dir.create(recursive: true);
    }

    await _projectBaseDir();
    await Directory(
      p.join((await _docDir()).path, 'thumbnails'),
    ).create(recursive: true);

    // 라이브러리 앨범 로드
    final clipEntities = rawBase.listSync().whereType<Directory>().toList();
    final clipAlbumWithTime = <MapEntry<String, DateTime>>[];
    for (final entity in clipEntities) {
      final name = p.basename(entity.path);
      final stat = await entity.stat();
      clipAlbumWithTime.add(MapEntry(name, stat.changed));
    }

    clipAlbumWithTime.sort((a, b) {
      if (a.key == "일상") return -1;
      if (b.key == "일상") return 1;
      if (a.key == "휴지통") return 1;
      if (b.key == "휴지통") return -1;
      return a.value.compareTo(b.value);
    });

    final sortedClipNames = clipAlbumWithTime.map((e) => e.key).toList();
    if (!sortedClipNames.contains("일상")) sortedClipNames.insert(0, "일상");
    if (!sortedClipNames.contains("휴지통")) sortedClipNames.add("휴지통");
    clipAlbums = sortedClipNames;

    // ✅ 앨범별 클립 수 캐시 업데이트
    await _updateAlbumClipCounts();

    // Vlog 앨범 로드
    final vlogEntities = vlogBase.listSync().whereType<Directory>().toList();
    final vlogAlbumWithTime = <MapEntry<String, DateTime>>[];
    for (final entity in vlogEntities) {
      final name = p.basename(entity.path);
      // ✅ "일상" 폴더는 클립 전용이므로 제외
      if (name == "일상") continue;
      final stat = await entity.stat();
      vlogAlbumWithTime.add(MapEntry(name, stat.changed));
    }

    vlogAlbumWithTime.sort((a, b) {
      if (a.key == "기본") return -1; // 기본 최상단
      if (b.key == "기본") return 1;
      if (a.key == "휴지통") return 1; // 휴지통 최하단
      if (b.key == "휴지통") return -1;
      return a.value.compareTo(b.value);
    });

    final sortedVlogNames = vlogAlbumWithTime.map((e) => e.key).toList();
    if (!sortedVlogNames.contains("기본")) sortedVlogNames.insert(0, "기본");
    if (!sortedVlogNames.contains("휴지통")) sortedVlogNames.add("휴지통");
    vlogAlbums = sortedVlogNames;

    // await loadVlogProjects(notify: false); // Deprecated or not used?
    // Using _updateVlogProjectCount instead for stats
    await _updateVlogProjectCount();

    // Phase 5: 프로젝트 로드
    await loadProjects();
    await _cleanupClipOwnershipMetadata();

    // notifyListeners(); // _updateVlogProjectCount calls notifyListeners
  }

  void clearClips() {
    recordedVideoPaths = [];
    notifyListeners();
  }

  Future<void> loadClipsFromCurrentAlbum() async {
    recordedVideoPaths = [];
    final albumDir = await _rawAlbumDir(currentAlbum);
    final files = albumDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.mp4'))
        .map((file) => file.path)
        .toList();
    files.sort(
      (a, b) =>
          File(b).lastModifiedSync().compareTo(File(a).lastModifiedSync()),
    );
    recordedVideoPaths = files;
    unawaited(_preloadClipDurationsForPaths(recordedVideoPaths));
    await _cleanupCloudSyncedPaths();
    await _cleanupClipOwnershipMetadata();
    notifyListeners();
  }

  Future<List<String>> ensureTutorialSampleClips({
    String targetAlbum = '일상',
  }) async {
    final albumDir = await _rawAlbumDir(targetAlbum);
    final ensuredPaths = <String>[];

    for (final assetPath in _tutorialSampleAssets) {
      final fileName = 'clip_${p.basename(assetPath)}';
      final destinationPath = p.join(albumDir.path, fileName);
      final destinationFile = File(destinationPath);

      try {
        if (!await destinationFile.exists()) {
          final data = await rootBundle.load(assetPath);
          await destinationFile.writeAsBytes(
            data.buffer.asUint8List(),
            flush: true,
          );
        }

        await _setClipOwnership(
          destinationPath,
          ownerAccountId: UserStatusManager().userId,
        );
        await _upsertLocalIndexClip(destinationPath);
        await _removeDurationCacheForPath(destinationPath);
        ensuredPaths.add(destinationPath);
      } catch (e) {
        debugPrint(
          '[VideoManager][TutorialSample] ensure_failed '
          'asset=$assetPath target=$destinationPath error=$e',
        );
      }
    }

    await _updateAlbumClipCounts();
    if (currentAlbum == targetAlbum) {
      await loadClipsFromCurrentAlbum();
    }
    return ensuredPaths;
  }

  Future<void> _preloadClipDurationsForPaths(List<String> paths) async {
    final unresolved = paths
        .where(
          (path) =>
              !_durationCache.containsKey(path) &&
              !_persistedDurationMs.containsKey(path),
        )
        .toList();
    if (unresolved.isEmpty) return;

    for (final path in unresolved) {
      try {
        await getVideoDuration(path);
      } catch (_) {
        // Ignore per-file preload failure. UI fallback handles this case.
      }
    }
  }

  Future<void> loadVlogsFromCurrentFolder() async {
    if (currentVlogFolder.isEmpty) {
      vlogProjectPaths = [];
      notifyListeners();
      return;
    }

    final folderDir = await _vlogFolderDir(currentVlogFolder);
    final files = folderDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.mp4'))
        .map((file) => file.path)
        .toList();
    files.sort(
      (a, b) =>
          File(b).lastModifiedSync().compareTo(File(a).lastModifiedSync()),
    );
    vlogProjectPaths = files;
    await _cleanupCloudSyncedPaths();
    notifyListeners();
  }

  Future<void> loadVlogProjects({bool notify = true}) async {
    vlogProjectPaths = await _listProjectFiles();
    await _cleanupCloudSyncedPaths();
    if (notify) notifyListeners();
  }

  /// 특정 앨범의 클립 목록 반환 (캐시 우선)
  List<String> getClipsInAlbum(String albumName) {
    // 현재 앨범이면 캐시된 데이터 사용
    if (currentAlbum == albumName) {
      return recordedVideoPaths;
    }
    // 다른 앨범은 빈 리스트 (UI에서는 getClipCountSync 사용)
    return [];
  }

  /// 특정 앨범의 클립 수를 실시간 조회 (동기적, 파일 시스템)
  int getClipCountSync(String albumName) {
    try {
      // 동기적으로 DocumentsDirectory 경로 구성
      final docPath =
          Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '';
      if (docPath.isEmpty) return 0;

      // Android/iOS 환경에서는 getApplicationDocumentsDirectory 경로 사용
      // 여기서는 간단히 처리 - 실제로는 비동기 필요하므로 캐시 맵 사용
      return albumCounts[albumName] ?? 0;
    } catch (_) {
      return 0;
    }
  }

  void toggleFavoritesBatch(List<String> paths) {
    for (var path in paths) {
      if (favorites.contains(path)) {
        favorites.remove(path);
      } else {
        favorites.add(path);
      }
    }
  }

  Future<void> toggleProjectFavoritesBatch(List<String> projectIds) async {
    if (projectIds.isEmpty) return;

    final selected = vlogProjects
        .where((project) => projectIds.contains(project.id))
        .toList();
    if (selected.isEmpty) return;

    final bool shouldFavorite = selected.any((project) => !project.isFavorite);
    for (final project in selected) {
      final updated = project.copyWith(isFavorite: shouldFavorite);
      await saveProject(updated);
    }

    notifyListeners();
  }

  Future<void> moveClipsBatch(List<String> paths, String targetAlbum) async {
    final targetDir = await _rawAlbumDir(targetAlbum);
    for (var oldPath in paths) {
      final dest = await _buildUniqueFilePath(
        targetDir.path,
        p.basename(oldPath),
      );
      try {
        await File(oldPath).rename(dest);
        await _moveClipOwnershipPath(oldPath, dest);
        await _moveDurationCachePath(oldPath, dest);
      } catch (_) {
        await File(oldPath).copy(dest);
        await File(oldPath).delete();
        await _moveClipOwnershipPath(oldPath, dest);
        await _moveDurationCachePath(oldPath, dest);
      }
    }
    notifyListeners();
    await _updateAlbumClipCounts();
  }

  Future<void> deleteClipsBatch(List<String> paths) async {
    // ✅ 영구 삭제 (휴지통 전용)
    for (var path in paths) {
      await File(path).delete();
      await _removeClipOwnershipForPath(path);
      await _removeDurationCacheForPath(path);
    }
    notifyListeners();
    await _updateAlbumClipCounts();
  }

  Future<void> saveRecordedVideo(XFile video) async {
    final albumDir = await _rawAlbumDir(currentAlbum);
    final savePath = p.join(
      albumDir.path,
      "clip_${DateTime.now().millisecondsSinceEpoch}.mp4",
    );
    final currentPath = savePath;

    final sourceDurationMs = await _getVideoDurationMsNative(video.path);
    final expectedClipMs = sourceDurationMs != null
        ? (sourceDurationMs < _targetRecordingDurationMs
              ? sourceDurationMs
              : _targetRecordingDurationMs)
        : _targetRecordingDurationMs;
    debugPrint(
      '[VideoManager] saveRecordedVideo '
      'sourceDurationMs=$sourceDurationMs '
      'targetDurationMs=$_targetRecordingDurationMs '
      'expectedClipMs=$expectedClipMs '
      'trimMode=$_recordingTrimMode '
      'normalize=always',
    );

    final normalized = await _normalizeRecordedVideo(video.path, currentPath);
    if (!normalized) {
      try {
        await File(video.path).copy(currentPath);
        debugPrint(
          '[VideoManager] normalize fallback(copy) source=${video.path.split('/').last} '
          'target=${currentPath.split('/').last}',
        );
      } catch (e) {
        debugPrint('[VideoManager] Copy fallback failed: $e');
        return;
      }
    }

    await _setClipOwnership(
      currentPath,
      ownerAccountId: UserStatusManager().userId,
    );
    await _upsertLocalIndexClip(currentPath);

    await _removeDurationCacheForPath(currentPath);
    await loadClipsFromCurrentAlbum();
    await _updateAlbumClipCounts();
  }

  Future<int?> _getVideoDurationMsNative(String inputPath) async {
    try {
      final result = await platform.invokeMethod('getVideoDurationMs', {
        'inputPath': inputPath,
      });
      if (result is int) {
        return result;
      }
      if (result is num) {
        return result.toInt();
      }
      if (result is String) {
        return int.tryParse(result);
      }
    } catch (e) {
      debugPrint('[VideoManager] getVideoDurationMs failed: $e');
    }
    return null;
  }

  Future<bool> _normalizeRecordedVideo(
    String sourcePath,
    String outputPath,
  ) async {
    try {
      final result = await platform.invokeMethod('normalizeVideoDuration', {
        'inputPath': sourcePath,
        'outputPath': outputPath,
        'targetDurationMs': _targetRecordingDurationMs,
        'trimMode': _recordingTrimMode,
      });

      return result == 'SUCCESS';
    } catch (e) {
      debugPrint('[VideoManager] normalizeRecordedVideo failed: $e');
      return false;
    }
  }

  Future<void> markClipCloudSynced(String path) async {
    _cloudSyncedPaths.add(path);
    await _persistCloudSyncedPaths();
    notifyListeners();
  }

  Future<void> unmarkClipCloudSynced(String path) async {
    final removed = _cloudSyncedPaths.remove(path);
    if (!removed) return;
    await _persistCloudSyncedPaths();
    notifyListeners();
  }

  bool isClipCloudSynced(String path) => _cloudSyncedPaths.contains(path);

  void markClipTransferPendingUpload(String path) {
    _clipTransferUiStateByPath[path] = ClipTransferUiState.pendingUpload;
    notifyListeners();
  }

  void markClipTransferPendingDownload(String path) {
    _clipTransferUiStateByPath[path] = ClipTransferUiState.pendingDownload;
    notifyListeners();
  }

  void markClipTransferUploadFailed(String path) {
    _clipTransferUiStateByPath[path] = ClipTransferUiState.failedUpload;
    notifyListeners();
  }

  void markClipTransferDownloadFailed(String path) {
    _clipTransferUiStateByPath[path] = ClipTransferUiState.failedDownload;
    notifyListeners();
  }

  void clearClipTransferUiState(String path) {
    if (_clipTransferUiStateByPath.remove(path) != null) {
      notifyListeners();
    }
  }

  ClipTransferUiState? getClipTransferUiState(String path) =>
      _clipTransferUiStateByPath[path];

  /// 사용자 전환(로그아웃/계정 변경) 시 사용자 종속 로컬 캐시 초기화
  Future<void> clearUserScopedLocalCache() async {
    _cloudSyncedPaths.clear();
    await _persistCloudSyncedPaths();
    notifyListeners();
  }

  Future<void> createNewClipAlbum(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (_isReservedClipAlbum(trimmed)) return;

    final safeName = trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final base = await _rawBaseDir();
    final target = Directory(p.join(base.path, safeName));
    if (await target.exists()) return;
    await target.create(recursive: true);
    await initAlbumSystem();
  }

  Future<void> createNewVlogAlbum(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (_isReservedVlogAlbum(trimmed)) return;

    final safeName = trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final base = await _vlogFoldersBaseDir();
    final target = Directory(p.join(base.path, safeName));
    if (await target.exists()) return;
    await target.create(recursive: true);
    await initAlbumSystem();
  }

  Future<void> deleteClipAlbums(Set<String> names) async {
    final base = await _rawBaseDir();
    for (var name in names) {
      if (_isReservedClipAlbum(name)) continue;
      final dir = Directory(p.join(base.path, name));
      if (await dir.exists()) {
        for (var file in dir.listSync().whereType<File>()) {
          final trashDir = Directory(p.join(base.path, '휴지통'));
          if (!await trashDir.exists()) await trashDir.create(recursive: true);
          final trashName = "${name}__${p.basename(file.path)}";
          final destPath = await _buildUniqueFilePath(trashDir.path, trashName);
          try {
            await file.rename(destPath);
          } catch (_) {
            await file.copy(destPath);
            await file.delete();
          }
        }
        await dir.delete(recursive: true);
      }
    }
  }

  Future<void> deleteVlogAlbums(Set<String> names) async {
    final base = await _vlogFoldersBaseDir();
    final movableFolders = names
        .where((name) => !_isReservedVlogAlbum(name))
        .toSet();

    // 프로젝트 메타데이터도 함께 보정 (폴더 삭제 시 휴지통으로 이동)
    final projectsToTrash = vlogProjects
        .where((p) => movableFolders.contains(p.folderName))
        .toList();
    for (final project in projectsToTrash) {
      await saveProject(
        project.copyWith(
          folderName: '휴지통',
          trashedFromFolderName: project.folderName,
        ),
      );
    }

    for (var name in names) {
      if (_isReservedVlogAlbum(name)) continue;
      final dir = Directory(p.join(base.path, name));
      if (await dir.exists()) {
        for (var file in dir.listSync().whereType<File>()) {
          final trashDir = Directory(p.join(base.path, '휴지통'));
          if (!await trashDir.exists()) await trashDir.create(recursive: true);
          final trashName = "${name}__${p.basename(file.path)}";
          final destPath = await _buildUniqueFilePath(trashDir.path, trashName);
          try {
            await file.rename(destPath);
          } catch (_) {
            await file.copy(destPath);
            await file.delete();
          }
        }
        await dir.delete(recursive: true);
      }
    }

    notifyListeners();
  }

  Future<void> moveToTrash(String path) async {
    final trashDir = Directory(p.join((await _rawBaseDir()).path, '휴지통'));
    if (!await trashDir.exists()) await trashDir.create(recursive: true);
    final trashName = "${currentAlbum}__${p.basename(path)}";
    final destPath = await _buildUniqueFilePath(trashDir.path, trashName);
    await File(path).copy(destPath);
    await File(path).delete();
    await _moveClipOwnershipPath(path, destPath);
    await _moveDurationCachePath(path, destPath);
    notifyListeners();
    await _updateAlbumClipCounts();
  }

  Future<void> restoreClip(String trashPath) async {
    final base = await _rawBaseDir();
    final fileName = p.basename(trashPath);
    String target = "일상";

    if (fileName.contains("__")) {
      final parts = fileName.split("__");
      final originAlbum = parts[0];
      final dir = Directory(p.join(base.path, originAlbum));
      if (await dir.exists()) {
        target = originAlbum;
      }
    }

    final newName = fileName.contains("__")
        ? fileName.split("__").sublist(1).join("__")
        : fileName;
    final targetDir = Directory(p.join(base.path, target));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final destPath = await _buildUniqueFilePath(targetDir.path, newName);
    await File(trashPath).copy(destPath);
    await File(trashPath).delete();
    await _moveClipOwnershipPath(trashPath, destPath);
    await _moveDurationCachePath(trashPath, destPath);
    notifyListeners();
    await _updateAlbumClipCounts();
  }

  // ✅ Vlog Trash Support
  Future<void> moveVlogToTrash(String path) async {
    final trashDir = Directory(
      p.join((await _vlogFoldersBaseDir()).path, '휴지통'),
    );
    if (!await trashDir.exists()) await trashDir.create(recursive: true);

    // Prefix with Origin Folder for Restore
    final origin = currentVlogFolder.isEmpty ? "기본" : currentVlogFolder;
    final trashName = "${origin}__${p.basename(path)}";
    final destPath = await _buildUniqueFilePath(trashDir.path, trashName);

    await File(path).copy(destPath);
    await File(path).delete();

    notifyListeners();
    // Refresh list if needed (handled by screen)
  }

  Future<void> restoreVlog(String trashPath) async {
    final base = await _vlogFoldersBaseDir();
    final fileName = p.basename(trashPath);
    String target = "기본";

    if (fileName.contains("__")) {
      final parts = fileName.split("__");
      final originFolder = parts[0];
      final dir = Directory(p.join(base.path, originFolder));
      if (await dir.exists()) {
        target = originFolder;
      }
    }

    final newName = fileName.contains("__")
        ? fileName.split("__").sublist(1).join("__")
        : fileName;
    final targetDir = Directory(p.join(base.path, target));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final destPath = await _buildUniqueFilePath(targetDir.path, newName);

    await File(trashPath).copy(destPath);
    await File(trashPath).delete();

    notifyListeners();
  }

  Future<void> executeTransfer(
    String target,
    bool isMove,
    List<String> list,
  ) async {
    if (isMove) {
      // 이동: 대상 폴더로 이동 (moveClipsBatch가 이미 rename 처리)
      await moveClipsBatch(list, target);
    } else {
      // 복사: 대상 폴더로 복사하고 원본 유지
      final targetDir = await _rawAlbumDir(target);
      for (var sourcePath in list) {
        final dest = await _buildUniqueFilePath(
          targetDir.path,
          p.basename(sourcePath),
        );
        await File(sourcePath).copy(dest);
        await _copyClipOwnershipPath(sourcePath, dest);
        await _copyDurationCachePath(sourcePath, dest);
      }
    }
    notifyListeners();
    await _updateAlbumClipCounts();
  }

  Future<String> _buildUniqueFilePath(String dirPath, String baseName) async {
    String candidate = p.join(dirPath, baseName);
    if (!await File(candidate).exists()) return candidate;

    final name = p.basenameWithoutExtension(baseName);
    final ext = p.extension(baseName);
    int index = 1;
    while (true) {
      candidate = p.join(dirPath, '${name}_$index$ext');
      if (!await File(candidate).exists()) return candidate;
      index++;
    }
  }

  Future<String?> getFirstClipPath(String n) async {
    if (n == "Vlog") {
      if (vlogProjectPaths.isNotEmpty) {
        final project = vlogProjects.firstWhere(
          (p) => p.id == vlogProjectPaths.first,
          orElse: () => vlogProjects.first,
        );
        return project.clips.isNotEmpty ? project.clips.first.path : null;
      }
      final projects = await _listProjectFiles();
      vlogProjectPaths = projects;
      // We can't easily get the first clip path without loading the project json.
      // For now, return null or try loading the first project.
      // Optimization: assuming loadProjects() was called.
      if (vlogProjects.isNotEmpty) {
        return vlogProjects.first.clips.isNotEmpty
            ? vlogProjects.first.clips.first.path
            : null;
      }
      return null;
    }
    final dir = Directory(p.join((await _rawBaseDir()).path, n));
    if (!await dir.exists()) return null;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.mp4'))
        .toList();
    return files.isNotEmpty ? files.first.path : null;
  }

  Future<int> getClipCount(String name) async {
    if (name == "Vlog") {
      return vlogProjectPaths.length;
    }
    final dir = Directory(p.join((await _rawBaseDir()).path, name));
    if (!await dir.exists()) return 0;
    return dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.mp4'))
        .length;
  }

  Future<void> deletePermanently(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    _clipTransferUiStateByPath.remove(path);
    await _removeClipOwnershipForPath(path);
    await _removeLocalIndexByKey(path);
    await _removeDurationCacheForPath(path);
    notifyListeners();
    await _updateAlbumClipCounts();
  }

  Future<void> _loadCloudSyncedPaths() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_cloudSyncedKey) ?? [];
    _cloudSyncedPaths
      ..clear()
      ..addAll(stored.where((path) => File(path).existsSync()));
  }

  Future<void> _persistCloudSyncedPaths() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_cloudSyncedKey, _cloudSyncedPaths.toList());
  }

  Future<void> _cleanupCloudSyncedPaths() async {
    final removed = _cloudSyncedPaths
        .where((path) => !File(path).existsSync())
        .toList();
    if (removed.isEmpty) return;
    _cloudSyncedPaths.removeAll(removed);
    await _persistCloudSyncedPaths();
  }

  String? getClipOwnerAccountId(String path) => _clipOwnerAccountByPath[path];

  String getClipLockState(String path) => 'unlocked';

  bool isClipLocked(String path) => false;

  String getClipStatusBadge(String path) {
    final transferState = getClipTransferUiState(path);
    switch (transferState) {
      case ClipTransferUiState.pendingUpload:
      case ClipTransferUiState.pendingDownload:
        return '로딩중';
      case ClipTransferUiState.failedUpload:
      case ClipTransferUiState.failedDownload:
        return '동기화 실패';
      case null:
        break;
    }

    if (isClipCloudSynced(path)) return '동기화됨';
    return '기기';
  }

  bool isClipVisibleByStorageFilter(String path, String filter) {
    switch (filter) {
      case 'device':
        return !isClipCloudSynced(path);
      case 'cloud':
        return isClipCloudSynced(path);
      case 'all':
      default:
        return true;
    }
  }

  Future<void> recalculateLockStatesForAccount(String? currentUid) async {
    // Deprecated: clip lock feature removed.
    notifyListeners();
  }

  Future<void> handleLogoutLocalData({
    required String? ownerAccountId,
    required String policy,
  }) async {
    if (ownerAccountId == null) return;

    if (policy == 'delete') {
      final allClips = await _listAllClipPaths();
      for (final path in allClips) {
        if (_clipOwnerAccountByPath[path] != ownerAccountId) continue;
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
        await _removeClipOwnershipForPath(path);
      }

      final ownedProjects = vlogProjects
          .where((p) => p.ownerAccountId == ownerAccountId)
          .map((p) => p.id)
          .toList();
      for (final id in ownedProjects) {
        await deleteProject(id);
      }
      await _updateAlbumClipCounts();
      return;
    }

    // Deprecated policy: clip lock feature removed.
  }

  Future<List<String>> _listAllClipPaths() async {
    final base = await _rawBaseDir();
    return base
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.mp4'))
        .map((file) => file.path)
        .toList();
  }

  Future<String> saveMergedProject(
    String sourcePath,
    String targetVlogFolder,
  ) async {
    final folderDir = await _vlogFolderDir(targetVlogFolder);
    final baseName = p.basename(sourcePath);
    String candidate = p.join(folderDir.path, baseName);
    final destFile = File(candidate);
    if (await destFile.exists()) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      candidate = p.join(
        folderDir.path,
        "${p.basenameWithoutExtension(baseName)}_$timestamp${p.extension(baseName)}",
      );
    }
    await File(sourcePath).copy(candidate);
    await loadVlogsFromCurrentFolder();
    await markClipCloudSynced(candidate);
    return candidate;
  }

  Future<Directory> getAppDocDir() async =>
      await getApplicationDocumentsDirectory();

  Future<void> saveExtractedClip(String sourcePath, String targetAlbum) async {
    final albumDir = await _rawAlbumDir(targetAlbum);
    final baseName = p.basename(sourcePath);
    String candidate = p.join(albumDir.path, baseName);

    // 타임스탬프로 이름 고유화
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    // clip_prefix 없으면 붙이기
    if (!baseName.startsWith("clip_")) {
      candidate = p.join(
        albumDir.path,
        "clip_${timestamp}_${p.basename(sourcePath)}",
      );
    } else {
      // 이미 clip_ 형식이면 뒤에 랜덤 숫자만 더해서 충돌 방지
      candidate = p.join(
        albumDir.path,
        "${p.basenameWithoutExtension(baseName)}_$timestamp${p.extension(baseName)}",
      );
    }

    await File(sourcePath).copy(candidate);
    final sourceOwner = getClipOwnerAccountId(sourcePath);
    if (sourceOwner != null) {
      await _copyClipOwnershipPath(sourcePath, candidate);
    } else {
      await _setClipOwnership(
        candidate,
        ownerAccountId: UserStatusManager().userId,
      );
    }
    await _copyDurationCachePath(sourcePath, candidate);

    // 현재 앨범이면 리스트 갱신
    if (currentAlbum == targetAlbum) {
      await loadClipsFromCurrentAlbum();
    }
    await _updateAlbumClipCounts();
  }

  Future<void> _setClipOwnership(
    String path, {
    required String? ownerAccountId,
  }) async {
    _clipOwnerAccountByPath[path] = ownerAccountId;
    await _persistClipOwnershipMetadata();
  }

  Future<void> _removeClipOwnershipForPath(String path) async {
    final changed = _clipOwnerAccountByPath.remove(path) != null;
    if (changed) {
      await _persistClipOwnershipMetadata();
    }
  }

  Future<void> _moveClipOwnershipPath(String oldPath, String newPath) async {
    final owner = _clipOwnerAccountByPath[oldPath];
    await _removeClipOwnershipForPath(oldPath);
    _clipOwnerAccountByPath[newPath] = owner;
    await _persistClipOwnershipMetadata();
    await _removeLocalIndexByKey(oldPath);
    await _upsertLocalIndexClip(newPath);
  }

  Future<void> _copyClipOwnershipPath(
    String sourcePath,
    String targetPath,
  ) async {
    _clipOwnerAccountByPath[targetPath] = _clipOwnerAccountByPath[sourcePath];
    await _persistClipOwnershipMetadata();
    await _upsertLocalIndexClip(targetPath);
  }

  Future<void> _upsertLocalIndexClip(String path) async {
    final entries = await _localIndexService.loadEntries();
    final owner = getClipOwnerAccountId(path) ?? UserStatusManager().userId;

    final entry = LocalIndexEntry(
      id: path,
      type: 'clip',
      pathOrKey: path,
      ownerAccountId: owner,
      lockState: 'unlocked',
      updatedAt: DateTime.now(),
    );

    final index = entries.indexWhere(
      (e) => e.pathOrKey == path && e.type == 'clip',
    );
    if (index == -1) {
      entries.add(entry);
    } else {
      entries[index] = entry;
    }
    await _localIndexService.saveEntries(entries);
  }

  Future<void> _upsertLocalIndexProject(VlogProject project) async {
    final entries = await _localIndexService.loadEntries();
    final entry = LocalIndexEntry(
      id: project.id,
      type: 'project',
      pathOrKey: project.id,
      ownerAccountId: project.ownerAccountId,
      lockState: project.lockState,
      updatedAt: DateTime.now(),
    );
    final index = entries.indexWhere(
      (e) => e.pathOrKey == project.id && e.type == 'project',
    );
    if (index == -1) {
      entries.add(entry);
    } else {
      entries[index] = entry;
    }
    await _localIndexService.saveEntries(entries);
  }

  Future<void> _removeLocalIndexByKey(String key) async {
    final entries = await _localIndexService.loadEntries();
    entries.removeWhere((e) => e.pathOrKey == key);
    await _localIndexService.saveEntries(entries);
  }

  Future<void> _loadClipOwnershipMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_clipOwnershipMetadataKey);
    _clipOwnerAccountByPath.clear();
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((key, value) {
        if (key is! String || value is! Map) return;
        final owner = value['ownerAccountId'];
        _clipOwnerAccountByPath[key] = owner is String ? owner : null;
      });
    } catch (e) {
      debugPrint('[VideoManager] Failed to load clip ownership metadata: $e');
    }
  }

  Future<void> _persistClipOwnershipMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = <String, Map<String, dynamic>>{};
    for (final entry in _clipOwnerAccountByPath.entries) {
      final path = entry.key;
      encoded[path] = {'ownerAccountId': entry.value};
    }
    await prefs.setString(_clipOwnershipMetadataKey, jsonEncode(encoded));
  }

  Future<void> _cleanupClipOwnershipMetadata() async {
    final allPaths = await _listAllClipPaths();
    final existing = allPaths.toSet();
    final removeTargets = _clipOwnerAccountByPath.keys
        .where((path) => !existing.contains(path))
        .toList();
    if (removeTargets.isEmpty) return;
    for (final path in removeTargets) {
      _clipOwnerAccountByPath.remove(path);
    }
    await _persistClipOwnershipMetadata();
  }

  Future<void> _loadClipDurationMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_clipDurationMetadataKey);
    if (raw == null || raw.isEmpty) {
      _persistedDurationMs.clear();
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final loaded = <String, int>{};
      decoded.forEach((key, value) {
        if (key is String && value is num && value > 0) {
          loaded[key] = value.toInt();
        }
      });

      // 파일이 사라진 엔트리 정리
      loaded.removeWhere((path, _) => !File(path).existsSync());

      _persistedDurationMs
        ..clear()
        ..addAll(loaded);

      // 메모리 캐시에 바로 채워서 첫 화면 표시 속도 개선
      _persistedDurationMs.forEach((path, ms) {
        _durationCache[path] = Duration(milliseconds: ms);
      });

      await prefs.setString(
        _clipDurationMetadataKey,
        jsonEncode(_persistedDurationMs),
      );
    } catch (e) {
      debugPrint('[VideoManager] Failed to load clip duration metadata: $e');
    }
  }

  Future<void> _persistClipDurationMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _clipDurationMetadataKey,
      jsonEncode(_persistedDurationMs),
    );
  }

  Future<void> _setDurationCacheForPath(
    String path,
    Duration duration, {
    bool persist = true,
  }) async {
    if (duration <= Duration.zero) return;
    _durationCache[path] = duration;
    if (!persist) return;

    _persistedDurationMs[path] = duration.inMilliseconds;
    await _persistClipDurationMetadata();
  }

  Future<void> _removeDurationCacheForPath(String path) async {
    _durationCache.remove(path);
    if (_persistedDurationMs.remove(path) != null) {
      await _persistClipDurationMetadata();
    }
  }

  Future<void> _moveDurationCachePath(String oldPath, String newPath) async {
    final duration =
        _durationCache[oldPath] ??
        (_persistedDurationMs[oldPath] != null
            ? Duration(milliseconds: _persistedDurationMs[oldPath]!)
            : null);

    await _removeDurationCacheForPath(oldPath);
    if (duration != null) {
      await _setDurationCacheForPath(newPath, duration);
    }
  }

  Future<void> _copyDurationCachePath(
    String sourcePath,
    String targetPath,
  ) async {
    final duration =
        _durationCache[sourcePath] ??
        (_persistedDurationMs[sourcePath] != null
            ? Duration(milliseconds: _persistedDurationMs[sourcePath]!)
            : null);
    if (duration == null) return;
    await _setDurationCacheForPath(targetPath, duration);
  }
}

final VideoManager videoManager = VideoManager();
