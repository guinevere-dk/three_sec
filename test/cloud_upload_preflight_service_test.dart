import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:three_s/constants/clip_policy.dart';
import 'package:three_s/services/cloud_upload_preflight_service.dart';
import 'package:three_s/utils/cloud_cost_policy.dart';
import 'package:three_s/utils/quality_policy.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('moa_cloud_preflight_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> writeFile(String name, int bytes) async {
    final file = File(p.join(tempDir.path, name));
    await file.writeAsBytes(List<int>.filled(bytes, 1));
    return file;
  }

  group('CloudUploadPreflightService', () {
    test(
      'accepts an already-standard MOA clip without normalization',
      () async {
        var normalizerCalled = false;
        final source = await writeFile('standard.mp4', 3 * 1024 * 1024);
        final service = CloudUploadPreflightService(
          cacheDirProvider: () async => tempDir,
          probeReader: (file) async => CloudUploadVideoProbe(
            durationMs: kTargetClipMs,
            width: 1080,
            height: 1920,
            fileSize: await file.length(),
            estimatedBitrate: kQuality1080pTargetBitrate,
          ),
          normalizer: (_, _) async {
            normalizerCalled = true;
            return null;
          },
        );

        final result = await service.prepareForStandardUpload(source);

        expect(result.decision, CloudUploadPreflightDecision.readyOriginal);
        expect(result.uploadFile?.path, source.path);
        expect(result.usesTemporaryUploadFile, isFalse);
        expect(normalizerCalled, isFalse);
        expect(result.toFirestoreMetadata()['normalizedForStandard'], isFalse);
      },
    );

    test('normalizes long or high-resolution input before upload', () async {
      final source = await writeFile('raw_4k.mov', 8 * 1024 * 1024);
      final service = CloudUploadPreflightService(
        cacheDirProvider: () async => tempDir,
        probeReader: (file) async {
          if (file.path == source.path) {
            return CloudUploadVideoProbe(
              durationMs: 12000,
              width: 3840,
              height: 2160,
              fileSize: await file.length(),
              estimatedBitrate: 22 * 1000 * 1000,
            );
          }
          return CloudUploadVideoProbe(
            durationMs: kTargetClipMs,
            width: 1080,
            height: 1920,
            fileSize: await file.length(),
            estimatedBitrate: kQuality1080pTargetBitrate,
          );
        },
        normalizer: (_, outputFile) async {
          await outputFile.writeAsBytes(List<int>.filled(3 * 1024 * 1024, 2));
          return outputFile;
        },
      );

      final result = await service.prepareForStandardUpload(source);

      expect(result.decision, CloudUploadPreflightDecision.normalizedCopy);
      expect(result.uploadFile?.path, isNot(source.path));
      expect(result.uploadFile?.path.endsWith('_standard.mp4'), isTrue);
      expect(result.uploadFileSize, 3 * 1024 * 1024);
      expect(result.toFirestoreMetadata()['normalizedForStandard'], isTrue);
      expect(result.toFirestoreMetadata()['sourceFileSize'], 8 * 1024 * 1024);
      expect(result.toFirestoreMetadata()['assetType'], 'standard_video');
    });

    test('normalizes otherwise-standard input above object cap', () async {
      final source = await writeFile('oversized_standard.mp4', 1024);
      var normalizerCalled = false;
      final service = CloudUploadPreflightService(
        cacheDirProvider: () async => tempDir,
        probeReader: (file) async {
          if (file.path == source.path) {
            return CloudUploadVideoProbe(
              durationMs: kTargetClipMs,
              width: 1080,
              height: 1920,
              fileSize: kStandardCloudVideoObjectLimitBytes + 1,
              estimatedBitrate: kQuality1080pTargetBitrate,
            );
          }
          return CloudUploadVideoProbe(
            durationMs: kTargetClipMs,
            width: 1080,
            height: 1920,
            fileSize: 3 * 1024 * 1024,
            estimatedBitrate: kQuality1080pTargetBitrate,
          );
        },
        normalizer: (_, outputFile) async {
          normalizerCalled = true;
          await outputFile.writeAsBytes(List<int>.filled(1024, 2));
          return outputFile;
        },
      );

      final result = await service.prepareForStandardUpload(source);

      expect(result.decision, CloudUploadPreflightDecision.normalizedCopy);
      expect(normalizerCalled, isTrue);
      expect(result.uploadFile?.path, isNot(source.path));
      expect(result.uploadFileSize, 3 * 1024 * 1024);
    });

    test('blocks normalized output above Standard object cap', () async {
      final source = await writeFile('raw_long.mp4', 1024);
      final service = CloudUploadPreflightService(
        cacheDirProvider: () async => tempDir,
        probeReader: (file) async {
          if (file.path == source.path) {
            return CloudUploadVideoProbe(
              durationMs: 9000,
              width: 1920,
              height: 1080,
              fileSize: 8 * 1024 * 1024,
              estimatedBitrate: kQuality1080pMaxBitrate,
            );
          }
          return CloudUploadVideoProbe(
            durationMs: kTargetClipMs,
            width: 1080,
            height: 1920,
            fileSize: kStandardCloudVideoObjectLimitBytes + 1,
            estimatedBitrate: kQuality1080pTargetBitrate,
          );
        },
        normalizer: (_, outputFile) async {
          await outputFile.writeAsBytes(List<int>.filled(1024, 2));
          return outputFile;
        },
      );

      final result = await service.prepareForStandardUpload(source);

      expect(result.decision, CloudUploadPreflightDecision.failed);
      expect(result.canUpload, isFalse);
      expect(result.errorCode, 'normalized_output_not_standard');
      expect(await source.exists(), isTrue);
    });

    test(
      'failed normalization blocks upload and preserves local source',
      () async {
        final source = await writeFile('raw_long.mp4', 8 * 1024 * 1024);
        final service = CloudUploadPreflightService(
          cacheDirProvider: () async => tempDir,
          probeReader: (file) async => CloudUploadVideoProbe(
            durationMs: 9000,
            width: 1920,
            height: 1080,
            fileSize: await file.length(),
            estimatedBitrate: kQuality1080pMaxBitrate,
          ),
          normalizer: (_, _) async => null,
        );

        final result = await service.prepareForStandardUpload(source);

        expect(result.decision, CloudUploadPreflightDecision.failed);
        expect(result.canUpload, isFalse);
        expect(result.errorCode, 'normalization_failed');
        expect(await source.exists(), isTrue);
      },
    );

    test('cleans only temporary normalized output', () async {
      final source = await writeFile('raw_long.mp4', 8 * 1024 * 1024);
      final service = CloudUploadPreflightService(
        cacheDirProvider: () async => tempDir,
        probeReader: (file) async {
          if (file.path == source.path) {
            return CloudUploadVideoProbe(
              durationMs: 9000,
              width: 1920,
              height: 1080,
              fileSize: await file.length(),
              estimatedBitrate: kQuality1080pMaxBitrate,
            );
          }
          return CloudUploadVideoProbe(
            durationMs: kTargetClipMs,
            width: 1080,
            height: 1920,
            fileSize: await file.length(),
            estimatedBitrate: kQuality1080pTargetBitrate,
          );
        },
        normalizer: (_, outputFile) async {
          await outputFile.writeAsBytes(List<int>.filled(1024, 2));
          return outputFile;
        },
      );

      final result = await service.prepareForStandardUpload(source);
      final uploadFile = result.uploadFile;
      expect(uploadFile, isNotNull);
      expect(await uploadFile!.exists(), isTrue);

      await service.cleanupTemporaryResult(result);

      expect(await uploadFile.exists(), isFalse);
      expect(await source.exists(), isTrue);
    });
  });
}
