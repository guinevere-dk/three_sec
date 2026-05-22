import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../constants/clip_policy.dart';
import '../utils/cloud_cost_policy.dart';
import '../utils/quality_policy.dart';

enum CloudUploadPreflightDecision {
  readyOriginal,
  normalizedCopy,
  blocked,
  failed,
}

class CloudUploadVideoProbe {
  final int durationMs;
  final int width;
  final int height;
  final int fileSize;
  final int? estimatedBitrate;

  const CloudUploadVideoProbe({
    required this.durationMs,
    required this.width,
    required this.height,
    required this.fileSize,
    this.estimatedBitrate,
  });

  int get longestSide => width > height ? width : height;
  int get shortestSide => width > height ? height : width;

  bool get isWithin1080pEnvelope => longestSide <= 1920 && shortestSide <= 1080;
}

class CloudUploadPreflightResult {
  final CloudUploadPreflightDecision decision;
  final File sourceFile;
  final File? uploadFile;
  final CloudUploadVideoProbe? sourceProbe;
  final CloudUploadVideoProbe? uploadProbe;
  final String reason;
  final String? errorCode;

  const CloudUploadPreflightResult({
    required this.decision,
    required this.sourceFile,
    required this.reason,
    this.uploadFile,
    this.sourceProbe,
    this.uploadProbe,
    this.errorCode,
  });

  bool get canUpload =>
      decision == CloudUploadPreflightDecision.readyOriginal ||
      decision == CloudUploadPreflightDecision.normalizedCopy;

  bool get usesTemporaryUploadFile =>
      uploadFile != null && uploadFile!.path != sourceFile.path;

  int get sourceFileSize => sourceProbe?.fileSize ?? 0;
  int get uploadFileSize => uploadProbe?.fileSize ?? sourceFileSize;

  Map<String, Object> toFirestoreMetadata() {
    final metadata = <String, Object>{
      'assetType': 'standard_video',
      'normalizedForStandard': usesTemporaryUploadFile,
      'sourceFileSize': sourceFileSize,
      'normalizedFileSize': uploadFileSize,
      'sourceDurationMs': sourceProbe?.durationMs ?? 0,
      'durationMs': uploadProbe?.durationMs ?? sourceProbe?.durationMs ?? 0,
      'width': uploadProbe?.width ?? sourceProbe?.width ?? 0,
      'height': uploadProbe?.height ?? sourceProbe?.height ?? 0,
      'targetFps': kQualityTargetFps,
      'targetBitrate': kQuality1080pTargetBitrate,
      'normalizedQuality': kQuality1080p,
      'normalizedVideoCodec': kQualityVideoCodecH264,
      'cloudPreflightDecision': decision.name,
      'cloudPreflightReason': reason,
    };

    final bitrate =
        uploadProbe?.estimatedBitrate ?? sourceProbe?.estimatedBitrate;
    if (bitrate != null && bitrate > 0) {
      metadata['bitrate'] = bitrate;
    }
    return metadata;
  }
}

typedef CloudUploadProbeReader =
    Future<CloudUploadVideoProbe?> Function(File file);
typedef CloudUploadNormalizer =
    Future<File?> Function(File sourceFile, File outputFile);
typedef CloudUploadCacheDirProvider = Future<Directory> Function();

class CloudUploadPreflightService {
  static const String cacheDirectoryName = 'cloud_upload_preflight_cache';
  static const int maxStandardBitrate = kQuality1080pMaxBitrate;
  static const MethodChannel _platform = MethodChannel(
    'com.dk.three_sec/video_engine',
  );

  final CloudUploadProbeReader _probeReader;
  final CloudUploadNormalizer _normalizer;
  final CloudUploadCacheDirProvider _cacheDirProvider;

  CloudUploadPreflightService({
    CloudUploadProbeReader? probeReader,
    CloudUploadNormalizer? normalizer,
    CloudUploadCacheDirProvider? cacheDirProvider,
  }) : _probeReader = probeReader ?? _defaultProbeReader,
       _normalizer = normalizer ?? _defaultNormalizer,
       _cacheDirProvider = cacheDirProvider ?? _defaultCacheDirProvider;

  Future<CloudUploadPreflightResult> prepareForStandardUpload(
    File sourceFile,
  ) async {
    if (!await sourceFile.exists()) {
      return CloudUploadPreflightResult(
        decision: CloudUploadPreflightDecision.blocked,
        sourceFile: sourceFile,
        reason: 'source_missing',
        errorCode: 'source_missing',
      );
    }

    final sourceProbe = await _probeReader(sourceFile);
    if (sourceProbe == null || sourceProbe.fileSize <= 0) {
      return CloudUploadPreflightResult(
        decision: CloudUploadPreflightDecision.failed,
        sourceFile: sourceFile,
        sourceProbe: sourceProbe,
        reason: 'source_probe_failed',
        errorCode: 'source_probe_failed',
      );
    }

    if (isStandardUploadReady(sourceFile, sourceProbe)) {
      return CloudUploadPreflightResult(
        decision: CloudUploadPreflightDecision.readyOriginal,
        sourceFile: sourceFile,
        uploadFile: sourceFile,
        sourceProbe: sourceProbe,
        uploadProbe: sourceProbe,
        reason: 'source_already_standard',
      );
    }

    final outputFile = await _buildNormalizedOutputFile(sourceFile);
    final normalizedFile = await _normalizer(sourceFile, outputFile);
    if (normalizedFile == null || !await normalizedFile.exists()) {
      return CloudUploadPreflightResult(
        decision: CloudUploadPreflightDecision.failed,
        sourceFile: sourceFile,
        sourceProbe: sourceProbe,
        reason: 'normalization_failed',
        errorCode: 'normalization_failed',
      );
    }

    final normalizedProbe = await _probeReader(normalizedFile);
    if (normalizedProbe == null ||
        !isStandardUploadReady(normalizedFile, normalizedProbe)) {
      return CloudUploadPreflightResult(
        decision: CloudUploadPreflightDecision.failed,
        sourceFile: sourceFile,
        uploadFile: normalizedFile,
        sourceProbe: sourceProbe,
        uploadProbe: normalizedProbe,
        reason: 'normalized_output_not_standard',
        errorCode: 'normalized_output_not_standard',
      );
    }

    return CloudUploadPreflightResult(
      decision: CloudUploadPreflightDecision.normalizedCopy,
      sourceFile: sourceFile,
      uploadFile: normalizedFile,
      sourceProbe: sourceProbe,
      uploadProbe: normalizedProbe,
      reason: 'normalized_for_standard_cloud',
    );
  }

  bool isStandardUploadReady(File file, CloudUploadVideoProbe probe) {
    if (probe.fileSize <= 0) return false;
    if (!isWithinStandardCloudVideoObjectLimit(probe.fileSize)) return false;
    if (!isClipDurationWithinTargetContract(probe.durationMs)) return false;
    if (!probe.isWithin1080pEnvelope) return false;
    final bitrate = probe.estimatedBitrate;
    if (bitrate != null && bitrate > maxStandardBitrate) return false;
    return p.extension(file.path).toLowerCase() == '.mp4';
  }

  Future<void> cleanupTemporaryResult(
    CloudUploadPreflightResult? result,
  ) async {
    if (result == null || !result.usesTemporaryUploadFile) return;
    final file = result.uploadFile;
    if (file == null) return;
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cache cleanup. Cloud source and local library files remain canonical.
    }
  }

  Future<File> _buildNormalizedOutputFile(File sourceFile) async {
    final dir = await _cacheDirProvider();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final safeBase = _safeFileStem(p.basenameWithoutExtension(sourceFile.path));
    final now = DateTime.now().microsecondsSinceEpoch;
    return File(p.join(dir.path, '${safeBase}_${now}_standard.mp4'));
  }

  static String _safeFileStem(String raw) {
    final sanitized = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    if (sanitized.trim().isEmpty) return 'clip';
    return sanitized.length > 48 ? sanitized.substring(0, 48) : sanitized;
  }

  static Future<Directory> _defaultCacheDirProvider() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory(p.join(appDir.path, cacheDirectoryName));
  }

  static Future<CloudUploadVideoProbe?> _defaultProbeReader(File file) async {
    VideoPlayerController? controller;
    try {
      final fileSize = await file.length();
      controller = VideoPlayerController.file(file);
      await controller.initialize();
      final value = controller.value;
      final durationMs = value.duration.inMilliseconds;
      final width = value.size.width.round();
      final height = value.size.height.round();
      if (durationMs <= 0 || width <= 0 || height <= 0) return null;
      final estimatedBitrate = (fileSize * 8 * 1000 / durationMs).round();
      return CloudUploadVideoProbe(
        durationMs: durationMs,
        width: width,
        height: height,
        fileSize: fileSize,
        estimatedBitrate: estimatedBitrate,
      );
    } catch (_) {
      return null;
    } finally {
      await controller?.dispose();
    }
  }

  static Future<File?> _defaultNormalizer(
    File sourceFile,
    File outputFile,
  ) async {
    try {
      final result = await _platform.invokeMethod('normalizeVideoDuration', {
        'inputPath': sourceFile.path,
        'outputPath': outputFile.path,
        'targetDurationMs': kTargetClipMs,
        'padToTarget': true,
        'trimMode': 'center',
        'aspectPreset': 'r9_16',
        'quality': kQuality1080p,
        'targetFps': kQualityTargetFps,
        'targetBitrate': kQuality1080pTargetBitrate,
        'videoCodec': kQualityVideoCodecH264,
      });
      if (result == 'SUCCESS' && await outputFile.exists()) {
        return outputFile;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
