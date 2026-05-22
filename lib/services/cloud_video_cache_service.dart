import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/cloud_cost_policy.dart';
import 'cloud_service.dart';

typedef CloudVideoCacheDownloader = Future<bool> Function(String localPath);

enum CloudVideoCacheFailureCode {
  downloadFailed,
  cacheFileMissing,
  cacheFileSizeMismatch,
  fileSystem,
}

class CloudVideoCacheMaterializeResult {
  final File? file;
  final bool cacheHit;
  final CloudVideoCacheFailureCode? failureCode;

  const CloudVideoCacheMaterializeResult._({
    required this.file,
    required this.cacheHit,
    required this.failureCode,
  });

  factory CloudVideoCacheMaterializeResult.success({
    required File file,
    required bool cacheHit,
  }) {
    return CloudVideoCacheMaterializeResult._(
      file: file,
      cacheHit: cacheHit,
      failureCode: null,
    );
  }

  factory CloudVideoCacheMaterializeResult.failure(
    CloudVideoCacheFailureCode code,
  ) {
    return CloudVideoCacheMaterializeResult._(
      file: null,
      cacheHit: false,
      failureCode: code,
    );
  }

  bool get isSuccess => file != null;
}

class CloudVideoCacheCleanupResult {
  final int deletedFileCount;
  final int skippedProtectedCount;
  final int failedDeleteCount;
  final int bytesBefore;
  final int bytesAfter;

  const CloudVideoCacheCleanupResult({
    required this.deletedFileCount,
    required this.skippedProtectedCount,
    required this.failedDeleteCount,
    required this.bytesBefore,
    required this.bytesAfter,
  });
}

class CloudVideoCacheService {
  static const cacheRootName = 'cloud_video_cache';
  static const canonicalFileName = 'standard.mp4';

  const CloudVideoCacheService();

  Directory cacheRoot(Directory appDocumentsDirectory) {
    return Directory(p.join(appDocumentsDirectory.path, cacheRootName));
  }

  String canonicalPath({
    required Directory appDocumentsDirectory,
    required String videoId,
  }) {
    return p.join(
      cacheRoot(appDocumentsDirectory).path,
      _safePathSegment(videoId),
      canonicalFileName,
    );
  }

  bool isCachePath({
    required Directory appDocumentsDirectory,
    required String path,
  }) {
    final root = p.normalize(cacheRoot(appDocumentsDirectory).path);
    final candidate = p.normalize(path);
    return p.isWithin(root, candidate) || candidate == root;
  }

  Future<File?> validCachedFile({
    required Directory appDocumentsDirectory,
    required VideoMetadata metadata,
  }) async {
    final file = File(
      canonicalPath(
        appDocumentsDirectory: appDocumentsDirectory,
        videoId: metadata.videoId,
      ),
    );
    if (!await file.exists()) return null;
    final actualSize = await file.length();
    if (actualSize != metadata.fileSize) return null;
    await _touch(file);
    return file;
  }

  Future<CloudVideoCacheMaterializeResult> materialize({
    required Directory appDocumentsDirectory,
    required VideoMetadata metadata,
    required CloudVideoCacheDownloader downloader,
    int maxCacheBytes = kCloudVideoCacheMaxBytes,
    Iterable<String> protectedPaths = const <String>[],
  }) async {
    final cached = await validCachedFile(
      appDocumentsDirectory: appDocumentsDirectory,
      metadata: metadata,
    );
    if (cached != null) {
      return CloudVideoCacheMaterializeResult.success(
        file: cached,
        cacheHit: true,
      );
    }

    final target = File(
      canonicalPath(
        appDocumentsDirectory: appDocumentsDirectory,
        videoId: metadata.videoId,
      ),
    );
    final parent = target.parent;
    try {
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }

      if (await target.exists()) {
        await target.delete();
      }

      final tempFile = File(
        p.join(
          parent.path,
          '.${p.basename(target.path)}.${DateTime.now().microsecondsSinceEpoch}.tmp',
        ),
      );
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      final ok = await downloader(tempFile.path);
      if (!ok) {
        await _deleteIfExists(tempFile);
        return CloudVideoCacheMaterializeResult.failure(
          CloudVideoCacheFailureCode.downloadFailed,
        );
      }
      if (!await tempFile.exists()) {
        return CloudVideoCacheMaterializeResult.failure(
          CloudVideoCacheFailureCode.cacheFileMissing,
        );
      }
      final actualSize = await tempFile.length();
      if (actualSize != metadata.fileSize) {
        await _deleteIfExists(tempFile);
        return CloudVideoCacheMaterializeResult.failure(
          CloudVideoCacheFailureCode.cacheFileSizeMismatch,
        );
      }

      final finalFile = await tempFile.rename(target.path);
      await _touch(finalFile);
      await cleanupCache(
        appDocumentsDirectory: appDocumentsDirectory,
        maxCacheBytes: maxCacheBytes,
        protectedPaths: <String>[...protectedPaths, finalFile.path],
      );
      return CloudVideoCacheMaterializeResult.success(
        file: finalFile,
        cacheHit: false,
      );
    } catch (_) {
      return CloudVideoCacheMaterializeResult.failure(
        CloudVideoCacheFailureCode.fileSystem,
      );
    }
  }

  Future<CloudVideoCacheCleanupResult> cleanupCache({
    required Directory appDocumentsDirectory,
    int maxCacheBytes = kCloudVideoCacheMaxBytes,
    Iterable<String> protectedPaths = const <String>[],
  }) async {
    final root = cacheRoot(appDocumentsDirectory);
    if (!await root.exists()) {
      return const CloudVideoCacheCleanupResult(
        deletedFileCount: 0,
        skippedProtectedCount: 0,
        failedDeleteCount: 0,
        bytesBefore: 0,
        bytesAfter: 0,
      );
    }

    final rootPath = p.normalize(root.path);
    final protected = protectedPaths
        .map(p.normalize)
        .where((path) => p.isWithin(rootPath, path))
        .toSet();

    final files = <_CacheFileEntry>[];
    var totalBytes = 0;
    final entities = root.listSync(recursive: true, followLinks: false);
    for (final entity in entities.whereType<File>()) {
      final path = p.normalize(entity.path);
      if (!p.isWithin(rootPath, path)) continue;
      try {
        final size = await entity.length();
        final modified = await entity.lastModified();
        totalBytes += size;
        files.add(
          _CacheFileEntry(file: entity, size: size, modified: modified),
        );
      } catch (_) {
        // Ignore unreadable cache entries; they are non-authoritative local copies.
      }
    }

    final bytesBefore = totalBytes;
    var deleted = 0;
    var skippedProtected = 0;
    var failed = 0;

    files.sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in files) {
      if (totalBytes <= maxCacheBytes) break;
      final normalizedPath = p.normalize(entry.file.path);
      if (protected.contains(normalizedPath)) {
        skippedProtected++;
        continue;
      }
      try {
        await entry.file.delete();
        deleted++;
        totalBytes -= entry.size;
      } catch (_) {
        failed++;
      }
    }

    await _deleteEmptyCacheDirectories(root);
    return CloudVideoCacheCleanupResult(
      deletedFileCount: deleted,
      skippedProtectedCount: skippedProtected,
      failedDeleteCount: failed,
      bytesBefore: bytesBefore,
      bytesAfter: totalBytes,
    );
  }

  static String _safePathSegment(String value) {
    final sanitized = value.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return sanitized.isEmpty ? 'unknown' : sanitized;
  }

  static Future<void> _touch(File file) async {
    try {
      await file.setLastModified(DateTime.now());
    } catch (_) {
      // Last-modified is used as a local LRU hint only.
    }
  }

  static Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  static Future<void> _deleteEmptyCacheDirectories(Directory root) async {
    if (!await root.exists()) return;
    final dirs =
        root
            .listSync(recursive: true, followLinks: false)
            .whereType<Directory>()
            .toList()
          ..sort((a, b) => b.path.length.compareTo(a.path.length));

    for (final dir in dirs) {
      try {
        if (dir.listSync(followLinks: false).isEmpty) {
          await dir.delete();
        }
      } catch (_) {}
    }
  }
}

class _CacheFileEntry {
  final File file;
  final int size;
  final DateTime modified;

  const _CacheFileEntry({
    required this.file,
    required this.size,
    required this.modified,
  });
}
