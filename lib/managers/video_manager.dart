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

import 'user_status_manager.dart';

class VideoManager extends ChangeNotifier {
  static const _rawBaseName = 'raw_clips';
  static const _projectBaseName = 'vlog_projects';
  static const _vlogFoldersBaseName = 'vlog_folders';
  static const _systemClipAlbums = ['일상', '휴지통'];
  static const _systemVlogAlbums = ['기본', '휴지통'];
  static const _cloudUsageLimitBytes = 10 * 1024 * 1024 * 1024;
  static const _cloudSyncedKey = 'cloud_synced_paths';

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
  final Set<String> _cloudSyncedPaths = {};

  static const platform = MethodChannel('com.dk.three_sec/video_engine');

  Future<Directory> _docDir() async => await getApplicationDocumentsDirectory();

  Future<Directory> _rawBaseDir() async {
    final dir = Directory(p.join((await _docDir()).path, 'vlogs', _rawBaseName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _projectBaseDir() async {
    final dir = Directory(p.join((await _docDir()).path, 'vlogs', _projectBaseName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
  
  Future<Directory> _vlogFoldersBaseDir() async {
    final dir = Directory(p.join((await _docDir()).path, 'vlogs', _vlogFoldersBaseName));
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
    files.sort((a, b) => File(b.path).lastModifiedSync().compareTo(File(a.path).lastModifiedSync()));
    return files.map((f) => f.path).toList();
  }

  Future<Uint8List?> getThumbnail(String videoPath) async {
    if (thumbnailCache.containsKey(videoPath)) return thumbnailCache[videoPath];

    final docDir = await getApplicationDocumentsDirectory();
    final thumbDir = Directory(p.join(docDir.path, 'thumbnails'));
    if (!await thumbDir.exists()) await thumbDir.create(recursive: true);

    final thumbFile = File(p.join(thumbDir.path, "${p.basename(videoPath)}.jpg"));

    if (await thumbFile.exists()) {
      final data = await thumbFile.readAsBytes();
      thumbnailCache[videoPath] = data;
      return data;
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

  Future<void> convertPhotoToVideo(String imagePath, String targetAlbum) async {
    final outDir = await _rawAlbumDir(targetAlbum);
    final String outPath = p.join(outDir.path, "photo_${DateTime.now().millisecondsSinceEpoch}.mp4");

    final String result = await platform.invokeMethod('convertImageToVideo', {
      'imagePath': imagePath,
      'outputPath': outPath,
      'duration': 3,
    });

    if (result != "SUCCESS") {
      throw Exception("Native Conversion Error: $result");
    }
    await _updateAlbumClipCounts();
  }

  // 2. Vlog 추출 (Native Engine 호출)
  Future<String?> exportVlog({
    required List<String> videoPaths,
    required Map<String, double> audioConfig,
    String? bgmPath,
    double bgmVolume = 0.5,
    String quality = '1080p',
  }) async {
    try {
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
      // Use passed videoPaths
      if (videoPaths.isEmpty) {
        print("❌ Export Error: 병합할 영상이 없습니다.");
        return null;
      }

      print("🚀 Start Exporting... (Count: ${videoPaths.length})");
      print("   - Output: $outputPath");
      print("   - Quality: $quality");

      // 4. ⚡ Native Engine 호출
      final args = {
        'videoPaths': videoPaths, // ✅ Key 이름을 'videoPaths'로 변경
        'outputPath': outputPath,
        'audioChanges': audioConfig,
        'bgmPath': bgmPath,
        'bgmVolume': bgmVolume,
        'quality': quality,
      };

      final String? result = await platform.invokeMethod('mergeVideos', args);
      
      print("✅ Export Success: $result");
      
      // (선택) 갤러리에 저장하고 싶다면 gal 패키지 등을 사용
      // await Gal.putVideo(result!); 

      return result;

    } on PlatformException catch (e) {
      print("❌ Native Error: ${e.message}");
      return null;
    } catch (e) {
      print("❌ Unexpected Error: $e");
      return null;
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

    final dirs = [await _rawBaseDir(), await _projectBaseDir(), await _vlogFoldersBaseDir()];
    
    for (final dir in dirs) {
      if (await dir.exists()) {
         await for (final file in dir.list(recursive: true, followLinks: false)) {
           if (file is File) totalBytes += await file.length();
         }
      }
    }

    if (totalBytes < 1024) return "$totalBytes B";
    if (totalBytes < 1024 * 1024) return "${(totalBytes / 1024).toStringAsFixed(1)} KB";
    if (totalBytes < 1024 * 1024 * 1024) return "${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    return "${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB";
  }

  Future<void> initAlbumSystem() async {
    final rawBase = await _rawBaseDir();
    final vlogBase = await _vlogFoldersBaseDir();
    await _loadCloudSyncedPaths();
    
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
    await Directory(p.join((await _docDir()).path, 'thumbnails')).create(recursive: true);

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
      if (a.key == "기본") return -1;  // 기본 최상단
      if (b.key == "기본") return 1;
      if (a.key == "휴지통") return 1;  // 휴지통 최하단
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
    files.sort((a, b) => File(b).lastModifiedSync().compareTo(File(a).lastModifiedSync()));
    recordedVideoPaths = files;
    await _cleanupCloudSyncedPaths();
    notifyListeners();
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
    files.sort((a, b) => File(b).lastModifiedSync().compareTo(File(a).lastModifiedSync()));
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
      final docPath = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
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

  Future<void> moveClipsBatch(List<String> paths, String targetAlbum) async {
    final targetDir = await _rawAlbumDir(targetAlbum);
    for (var oldPath in paths) {
      final dest = p.join(targetDir.path, p.basename(oldPath));
      try {
        await File(oldPath).rename(dest);
      } catch (_) {
        await File(oldPath).copy(dest);
        await File(oldPath).delete();
      }
    }
    notifyListeners();
    await _updateAlbumClipCounts();
  }

  Future<void> deleteClipsBatch(List<String> paths) async {
    // ✅ 영구 삭제 (휴지통 전용)
    for (var path in paths) {
      await File(path).delete();
    }
    notifyListeners();
    await _updateAlbumClipCounts();
  }

  Future<void> saveRecordedVideo(XFile video) async {
    final albumDir = await _rawAlbumDir(currentAlbum);
    final savePath = p.join(albumDir.path, "clip_${DateTime.now().millisecondsSinceEpoch}.mp4");
    await File(video.path).copy(savePath);
    await loadClipsFromCurrentAlbum();
    await _updateAlbumClipCounts();
  }

  Future<void> markClipCloudSynced(String path) async {
    _cloudSyncedPaths.add(path);
    await _persistCloudSyncedPaths();
    notifyListeners();
  }

  bool isClipCloudSynced(String path) => _cloudSyncedPaths.contains(path);

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
          await file.rename(p.join(trashDir.path, "${name}__${p.basename(file.path)}"));
        }
        await dir.delete(recursive: true);
      }
    }
  }
  
  Future<void> deleteVlogAlbums(Set<String> names) async {
    final base = await _vlogFoldersBaseDir();
    for (var name in names) {
      if (_isReservedVlogAlbum(name)) continue;
      final dir = Directory(p.join(base.path, name));
      if (await dir.exists()) {
        for (var file in dir.listSync().whereType<File>()) {
          final trashDir = Directory(p.join(base.path, '휴지통'));
          if (!await trashDir.exists()) await trashDir.create(recursive: true);
          await file.rename(p.join(trashDir.path, "${name}__${p.basename(file.path)}"));
        }
        await dir.delete(recursive: true);
      }
    }
  }

  Future<void> moveToTrash(String path) async {
    final trashDir = Directory(p.join((await _rawBaseDir()).path, '휴지통'));
    if (!await trashDir.exists()) await trashDir.create(recursive: true);
    final destPath = p.join(trashDir.path, "${currentAlbum}__${p.basename(path)}");
    await File(path).copy(destPath);
    await File(path).delete();
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

    final newName = fileName.contains("__") ? fileName.split("__").sublist(1).join("__") : fileName;
    final destPath = p.join(base.path, target, newName);
    await File(trashPath).copy(destPath);
    await File(trashPath).delete();
    notifyListeners();
    await _updateAlbumClipCounts();
  }

  // ✅ Vlog Trash Support
  Future<void> moveVlogToTrash(String path) async {
    final trashDir = Directory(p.join((await _vlogFoldersBaseDir()).path, '휴지통'));
    if (!await trashDir.exists()) await trashDir.create(recursive: true);
    
    // Prefix with Origin Folder for Restore
    final origin = currentVlogFolder.isEmpty ? "기본" : currentVlogFolder;
    final destPath = p.join(trashDir.path, "${origin}__${p.basename(path)}");
    
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

    final newName = fileName.contains("__") ? fileName.split("__").sublist(1).join("__") : fileName;
    final destPath = p.join(base.path, target, newName);
    
    await File(trashPath).copy(destPath);
    await File(trashPath).delete();
    
    notifyListeners();
  }

  Future<void> executeTransfer(String target, bool isMove, List<String> list) async {
    if (isMove) {
      // 이동: 대상 폴더로 이동 (moveClipsBatch가 이미 rename 처리)
      await moveClipsBatch(list, target);
    } else {
      // 복사: 대상 폴더로 복사하고 원본 유지
      final targetDir = await _rawAlbumDir(target);
      for (var sourcePath in list) {
        final dest = p.join(targetDir.path, p.basename(sourcePath));
        await File(sourcePath).copy(dest);
      }
    }
    notifyListeners();
    await _updateAlbumClipCounts();
  }

  Future<String?> getFirstClipPath(String n) async {
    if (n == "Vlog") {
      if (vlogProjectPaths.isNotEmpty) return vlogProjectPaths.first;
      final projects = await _listProjectFiles();
      vlogProjectPaths = projects;
      return projects.isNotEmpty ? projects.first : null;
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
    final removed = _cloudSyncedPaths.where((path) => !File(path).existsSync()).toList();
    if (removed.isEmpty) return;
    _cloudSyncedPaths.removeAll(removed);
    await _persistCloudSyncedPaths();
  }

  Future<String> saveMergedProject(String sourcePath, String targetVlogFolder) async {
    final folderDir = await _vlogFolderDir(targetVlogFolder);
    final baseName = p.basename(sourcePath);
    String candidate = p.join(folderDir.path, baseName);
    final destFile = File(candidate);
    if (await destFile.exists()) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      candidate = p.join(folderDir.path, "${p.basenameWithoutExtension(baseName)}_$timestamp${p.extension(baseName)}");
    }
    await File(sourcePath).copy(candidate);
    await loadVlogsFromCurrentFolder();
    await markClipCloudSynced(candidate);
    return candidate;
  }

  Future<Directory> getAppDocDir() async => await getApplicationDocumentsDirectory();

  Future<void> saveExtractedClip(String sourcePath, String targetAlbum) async {
    final albumDir = await _rawAlbumDir(targetAlbum);
    final baseName = p.basename(sourcePath);
    String candidate = p.join(albumDir.path, baseName);
    
    // 타임스탬프로 이름 고유화
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    // clip_prefix 없으면 붙이기
    if (!baseName.startsWith("clip_")) {
      candidate = p.join(albumDir.path, "clip_${timestamp}_${p.basename(sourcePath)}");
    } else {
       // 이미 clip_ 형식이면 뒤에 랜덤 숫자만 더해서 충돌 방지
      candidate = p.join(albumDir.path, "${p.basenameWithoutExtension(baseName)}_$timestamp${p.extension(baseName)}");
    }

    await File(sourcePath).copy(candidate);
    
    // 현재 앨범이면 리스트 갱신
    if (currentAlbum == targetAlbum) {
      await loadClipsFromCurrentAlbum();
    }
    await _updateAlbumClipCounts();
  }

  Future<CloudUsage> getCloudUsage() async {
    final projectDir = await _projectBaseDir();
    final files = projectDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.mp4'))
        .toList();
    int used = 0;
    for (final file in files) {
      used += await file.length();
    }
    return CloudUsage(usedBytes: used, limitBytes: _cloudUsageLimitBytes);
  }
}

final VideoManager videoManager = VideoManager();

class CloudUsage {
  final int usedBytes;
  final int limitBytes;
  const CloudUsage({required this.usedBytes, required this.limitBytes});

  double get ratio => limitBytes == 0 ? 0.0 : usedBytes / limitBytes;
}
