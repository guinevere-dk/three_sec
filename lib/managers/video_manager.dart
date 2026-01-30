import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as thum;

class VideoManager extends ChangeNotifier {
  static const _rawBaseName = 'raw_clips';
  static const _projectBaseName = 'vlog_projects';
  static const _systemAlbums = ['일상', '휴지통', 'Vlog'];
  static const _cloudUsageLimitBytes = 10 * 1024 * 1024 * 1024;
  static const _cloudSyncedKey = 'cloud_synced_paths';

  String currentAlbum = "일상";
  List<String> albums = List.from(_systemAlbums);
  List<String> recordedVideoPaths = [];
  List<String> vlogProjectPaths = [];
  Set<String> favorites = {};
  final Map<String, Uint8List> thumbnailCache = {};
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

  Future<Directory> _rawAlbumDir(String album) async {
    final base = await _rawBaseDir();
    final dir = Directory(p.join(base.path, album));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  bool _isReservedAlbum(String name) => _systemAlbums.contains(name);

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
      thumbFile.writeAsBytes(data).catchError((_) => null);
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
  }

  Future<void> initAlbumSystem() async {
    final rawBase = await _rawBaseDir();
    await _loadCloudSyncedPaths();
    for (final systemName in ['일상', '휴지통']) {
      final dir = Directory(p.join(rawBase.path, systemName));
      if (!await dir.exists()) await dir.create(recursive: true);
    }
    await _projectBaseDir();
    await Directory(p.join((await _docDir()).path, 'thumbnails')).create(recursive: true);

    final entities = rawBase.listSync().whereType<Directory>().toList();
    final albumWithTime = <MapEntry<String, DateTime>>[];
    for (final entity in entities) {
      final name = p.basename(entity.path);
      final stat = await entity.stat();
      albumWithTime.add(MapEntry(name, stat.changed));
    }

    albumWithTime.sort((a, b) {
      if (a.key == "일상") return -1;
      if (b.key == "일상") return 1;
      if (a.key == "휴지통") return 1;
      if (b.key == "휴지통") return -1;
      return a.value.compareTo(b.value);
    });

    final sortedNames = albumWithTime.map((e) => e.key).toList();
    if (!sortedNames.contains("일상")) sortedNames.insert(0, "일상");
    if (!sortedNames.contains("휴지통")) sortedNames.add("휴지통");
    if (!sortedNames.contains("Vlog")) sortedNames.add("Vlog");
    albums = sortedNames;
    await loadVlogProjects(notify: false);
    notifyListeners();
  }

  void clearClips() {
    recordedVideoPaths = [];
    notifyListeners();
  }

  Future<void> loadClipsFromCurrentAlbum() async {
    recordedVideoPaths = [];
    if (currentAlbum == "Vlog") {
      final projects = await _listProjectFiles();
      vlogProjectPaths = projects;
      recordedVideoPaths = List.from(projects);
      await _cleanupCloudSyncedPaths();
      notifyListeners();
      return;
    }

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

  Future<void> loadVlogProjects({bool notify = true}) async {
    vlogProjectPaths = await _listProjectFiles();
    await _cleanupCloudSyncedPaths();
    if (notify) notifyListeners();
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
  }

  Future<void> deleteClipsBatch(List<String> paths) async {
    for (var path in paths) {
      await moveToTrash(path);
    }
  }

  Future<void> saveRecordedVideo(XFile video) async {
    final albumDir = await _rawAlbumDir(currentAlbum);
    final savePath = p.join(albumDir.path, "clip_${DateTime.now().millisecondsSinceEpoch}.mp4");
    await File(video.path).copy(savePath);
    await loadClipsFromCurrentAlbum();
  }

  Future<void> markClipCloudSynced(String path) async {
    _cloudSyncedPaths.add(path);
    await _persistCloudSyncedPaths();
    notifyListeners();
  }

  bool isClipCloudSynced(String path) => _cloudSyncedPaths.contains(path);

  Future<void> createNewAlbum(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (_isReservedAlbum(trimmed)) return;

    final safeName = trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final base = await _rawBaseDir();
    final target = Directory(p.join(base.path, safeName));
    if (await target.exists()) return;
    await target.create(recursive: true);
    await initAlbumSystem();
  }

  Future<void> deleteAlbums(Set<String> names) async {
    final base = await _rawBaseDir();
    for (var name in names) {
      if (_isReservedAlbum(name)) continue;
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
  }

  Future<void> executeTransfer(String target, bool isMove, List<String> list) async {
    await moveClipsBatch(list, target);
    if (isMove) {
      for (var path in list) {
        await File(path).delete().catchError((_) {});
      }
    }
    notifyListeners();
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

  Future<String> saveMergedProject(String sourcePath) async {
    final projectDir = await _projectBaseDir();
    final baseName = p.basename(sourcePath);
    String candidate = p.join(projectDir.path, baseName);
    final destFile = File(candidate);
    if (await destFile.exists()) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      candidate = p.join(projectDir.path, "${p.basenameWithoutExtension(baseName)}_$timestamp${p.extension(baseName)}");
    }
    await File(sourcePath).copy(candidate);
    await loadVlogProjects();
    await markClipCloudSynced(candidate);
    return candidate;
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
