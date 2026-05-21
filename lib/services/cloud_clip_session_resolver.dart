import 'dart:io';

import 'package:path/path.dart' as p;

import 'cloud_service.dart';

enum CloudClipSessionPurpose { edit, export }

enum CloudClipResolveFailureCode {
  invalidPlaceholder,
  metadataMissing,
  storagePathMissing,
  invalidFileSize,
  cachePathCollision,
  downloadFailed,
  cacheFileMissing,
  cacheFileSizeMismatch,
}

class CloudOnlyPlaceholderParts {
  final String albumName;
  final String videoId;
  final String fileName;

  const CloudOnlyPlaceholderParts({
    required this.albumName,
    required this.videoId,
    required this.fileName,
  });
}

class CloudClipResolveFailure {
  final CloudClipResolveFailureCode code;

  const CloudClipResolveFailure(this.code);
}

class CloudClipResolvedSource {
  final String originalClipPath;
  final String videoId;
  final String storagePath;
  final String sessionLocalPath;
  final int fileSize;
  final Duration? duration;
  final bool fromCache;

  const CloudClipResolvedSource({
    required this.originalClipPath,
    required this.videoId,
    required this.storagePath,
    required this.sessionLocalPath,
    required this.fileSize,
    required this.duration,
    required this.fromCache,
  });
}

class CloudClipSessionCleanupResult {
  final int deletedFileCount;
  final int skippedProtectedCount;
  final int skippedFreshCount;
  final int failedDeleteCount;

  const CloudClipSessionCleanupResult({
    required this.deletedFileCount,
    required this.skippedProtectedCount,
    required this.skippedFreshCount,
    required this.failedDeleteCount,
  });
}

class CloudClipSessionResolveResult {
  final CloudClipResolvedSource? source;
  final CloudClipResolveFailure? failure;

  const CloudClipSessionResolveResult._({this.source, this.failure});

  factory CloudClipSessionResolveResult.success(
    CloudClipResolvedSource source,
  ) {
    return CloudClipSessionResolveResult._(source: source);
  }

  factory CloudClipSessionResolveResult.failure(
    CloudClipResolveFailureCode code,
  ) {
    return CloudClipSessionResolveResult._(
      failure: CloudClipResolveFailure(code),
    );
  }

  bool get isSuccess => source != null;
}

abstract class CloudClipMetadataSource {
  VideoMetadata? metadataForCloudOnlyPath(String path);
}

class CallbackCloudClipMetadataSource implements CloudClipMetadataSource {
  final VideoMetadata? Function(String path) lookup;

  const CallbackCloudClipMetadataSource(this.lookup);

  @override
  VideoMetadata? metadataForCloudOnlyPath(String path) => lookup(path);
}

abstract class CloudClipSessionDownloadClient {
  Future<bool> downloadSessionCopy({
    required VideoMetadata metadata,
    required String localPath,
  });
}

class CloudServiceSessionDownloadClient
    implements CloudClipSessionDownloadClient {
  final CloudService cloudService;

  const CloudServiceSessionDownloadClient(this.cloudService);

  @override
  Future<bool> downloadSessionCopy({
    required VideoMetadata metadata,
    required String localPath,
  }) {
    return cloudService.downloadVideo(
      videoId: metadata.videoId,
      localPath: localPath,
    );
  }
}

class CloudClipSessionResolver {
  static const scheme = 'cloud_only://';
  static const cacheRootName = 'cloud_clip_session_cache';
  static const defaultSessionCacheTtl = Duration(hours: 24);

  final CloudClipMetadataSource metadataSource;
  final CloudClipSessionDownloadClient downloadClient;

  const CloudClipSessionResolver({
    required this.metadataSource,
    required this.downloadClient,
  });

  static bool isCloudOnlyPlaceholder(String path) => path.startsWith(scheme);

  static CloudOnlyPlaceholderParts? parsePlaceholder(String path) {
    if (!isCloudOnlyPlaceholder(path)) return null;
    final rest = path.substring(scheme.length);
    final firstSlash = rest.indexOf('/');
    if (firstSlash <= 0 || firstSlash == rest.length - 1) return null;

    final album = rest.substring(0, firstSlash).trim();
    final afterAlbum = rest.substring(firstSlash + 1);
    final secondSlash = afterAlbum.indexOf('/');
    if (secondSlash <= 0 || secondSlash == afterAlbum.length - 1) return null;

    final videoId = afterAlbum.substring(0, secondSlash).trim();
    final fileName = afterAlbum.substring(secondSlash + 1).trim();
    if (album.isEmpty || videoId.isEmpty || fileName.isEmpty) return null;

    return CloudOnlyPlaceholderParts(
      albumName: album,
      videoId: videoId,
      fileName: fileName,
    );
  }

  static String purposeDirectoryName(CloudClipSessionPurpose purpose) {
    return switch (purpose) {
      CloudClipSessionPurpose.edit => 'edit_session_cache',
      CloudClipSessionPurpose.export => 'export_session_cache',
    };
  }

  static String buildSessionLocalPath({
    required Directory appDocumentsDirectory,
    required CloudClipSessionPurpose purpose,
    required String videoId,
    required String fileName,
  }) {
    final safeVideoId = _safePathSegment(videoId);
    final safeFileName = _safeFileName(fileName);
    return p.join(
      appDocumentsDirectory.path,
      cacheRootName,
      purposeDirectoryName(purpose),
      safeVideoId,
      safeFileName,
    );
  }

  static Directory sessionCacheRoot(Directory appDocumentsDirectory) {
    return Directory(p.join(appDocumentsDirectory.path, cacheRootName));
  }

  static bool isSessionCachePath({
    required Directory appDocumentsDirectory,
    required String path,
  }) {
    final root = p.normalize(sessionCacheRoot(appDocumentsDirectory).path);
    final candidate = p.normalize(path);
    return p.isWithin(root, candidate) || candidate == root;
  }

  static Future<CloudClipSessionCleanupResult> cleanupExpiredSessionCache({
    required Directory appDocumentsDirectory,
    Duration ttl = defaultSessionCacheTtl,
    Iterable<String> protectedPaths = const <String>[],
    DateTime? now,
  }) async {
    final root = sessionCacheRoot(appDocumentsDirectory);
    if (!await root.exists()) {
      return const CloudClipSessionCleanupResult(
        deletedFileCount: 0,
        skippedProtectedCount: 0,
        skippedFreshCount: 0,
        failedDeleteCount: 0,
      );
    }

    final rootPath = p.normalize(root.path);
    final protected = protectedPaths
        .map(p.normalize)
        .where((path) => p.isWithin(rootPath, path))
        .toSet();
    final cutoff = (now ?? DateTime.now()).subtract(ttl);
    var deleted = 0;
    var skippedProtected = 0;
    var skippedFresh = 0;
    var failed = 0;

    final entities = root.listSync(recursive: true, followLinks: false);
    for (final entity in entities.whereType<File>()) {
      final filePath = p.normalize(entity.path);
      if (!p.isWithin(rootPath, filePath)) continue;
      if (protected.contains(filePath)) {
        skippedProtected++;
        continue;
      }

      try {
        final modified = await entity.lastModified();
        if (modified.isAfter(cutoff) || modified.isAtSameMomentAs(cutoff)) {
          skippedFresh++;
          continue;
        }
        await entity.delete();
        deleted++;
      } catch (_) {
        failed++;
      }
    }

    await _deleteEmptyCacheDirectories(root);
    return CloudClipSessionCleanupResult(
      deletedFileCount: deleted,
      skippedProtectedCount: skippedProtected,
      skippedFreshCount: skippedFresh,
      failedDeleteCount: failed,
    );
  }

  Future<CloudClipSessionResolveResult> resolve({
    required String placeholderPath,
    required Directory appDocumentsDirectory,
    required CloudClipSessionPurpose purpose,
  }) async {
    final parsed = parsePlaceholder(placeholderPath);
    if (parsed == null) {
      return CloudClipSessionResolveResult.failure(
        CloudClipResolveFailureCode.invalidPlaceholder,
      );
    }

    final metadata = metadataSource.metadataForCloudOnlyPath(placeholderPath);
    if (metadata == null || metadata.videoId.trim().isEmpty) {
      return CloudClipSessionResolveResult.failure(
        CloudClipResolveFailureCode.metadataMissing,
      );
    }
    final storagePath = metadata.storagePath.trim();
    if (storagePath.isEmpty) {
      return CloudClipSessionResolveResult.failure(
        CloudClipResolveFailureCode.storagePathMissing,
      );
    }
    if (metadata.fileSize <= 0) {
      return CloudClipSessionResolveResult.failure(
        CloudClipResolveFailureCode.invalidFileSize,
      );
    }

    final sessionPath = buildSessionLocalPath(
      appDocumentsDirectory: appDocumentsDirectory,
      purpose: purpose,
      videoId: metadata.videoId,
      fileName: metadata.fileName.trim().isEmpty
          ? parsed.fileName
          : metadata.fileName,
    );
    final sessionFile = File(sessionPath);
    final parent = sessionFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    if (await sessionFile.exists()) {
      final actualSize = await sessionFile.length();
      if (actualSize == metadata.fileSize) {
        return CloudClipSessionResolveResult.success(
          _source(
            placeholderPath: placeholderPath,
            metadata: metadata,
            sessionPath: sessionPath,
            fromCache: true,
          ),
        );
      }
      return CloudClipSessionResolveResult.failure(
        CloudClipResolveFailureCode.cachePathCollision,
      );
    }

    final ok = await downloadClient.downloadSessionCopy(
      metadata: metadata,
      localPath: sessionPath,
    );
    if (!ok) {
      return CloudClipSessionResolveResult.failure(
        CloudClipResolveFailureCode.downloadFailed,
      );
    }
    if (!await sessionFile.exists()) {
      return CloudClipSessionResolveResult.failure(
        CloudClipResolveFailureCode.cacheFileMissing,
      );
    }
    final actualSize = await sessionFile.length();
    if (actualSize != metadata.fileSize) {
      return CloudClipSessionResolveResult.failure(
        CloudClipResolveFailureCode.cacheFileSizeMismatch,
      );
    }

    return CloudClipSessionResolveResult.success(
      _source(
        placeholderPath: placeholderPath,
        metadata: metadata,
        sessionPath: sessionPath,
        fromCache: false,
      ),
    );
  }

  static CloudClipResolvedSource _source({
    required String placeholderPath,
    required VideoMetadata metadata,
    required String sessionPath,
    required bool fromCache,
  }) {
    return CloudClipResolvedSource(
      originalClipPath: placeholderPath,
      videoId: metadata.videoId,
      storagePath: metadata.storagePath,
      sessionLocalPath: sessionPath,
      fileSize: metadata.fileSize,
      duration: metadata.durationMs == null || metadata.durationMs! <= 0
          ? null
          : Duration(milliseconds: metadata.durationMs!),
      fromCache: fromCache,
    );
  }

  static String _safePathSegment(String value) {
    final sanitized = value.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return sanitized.isEmpty ? 'unknown' : sanitized;
  }

  static String _safeFileName(String value) {
    final baseName = p.basename(value.trim());
    final sanitized = baseName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return sanitized.toLowerCase().endsWith('.mp4')
        ? sanitized
        : '${sanitized.isEmpty ? 'clip' : sanitized}.mp4';
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
