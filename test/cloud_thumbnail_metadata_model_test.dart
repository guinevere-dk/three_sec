import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:three_s/services/cloud_service.dart';
import 'package:three_s/services/local_index_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('VideoMetadata parses thumbnail fields when present', () {
    final metadata = VideoMetadata.fromMap('video-id', const {
      'uid': 'uid-redacted',
      'fileName': 'redacted.mp4',
      'storagePath': 'storage/path/redacted',
      'albumName': 'album',
      'fileSize': 1234,
      'uploadStatus': 'completed',
      'uploadProgress': 100,
      'thumbnailStoragePath': 'storage/path/thumb',
      'thumbnailStatus': 'completed',
      'thumbnailWidth': 320,
      'thumbnailHeight': 180,
      'durationMs': 2100,
    });

    expect(metadata.thumbnailStoragePath, 'storage/path/thumb');
    expect(metadata.thumbnailStatus, 'completed');
    expect(metadata.thumbnailWidth, 320);
    expect(metadata.thumbnailHeight, 180);
    expect(metadata.durationMs, 2100);
    expect(metadata.hasCompletedThumbnail, isTrue);
    expect(metadata.hasFailedThumbnail, isFalse);
  });

  test('VideoMetadata tolerates legacy documents without thumbnail fields', () {
    final metadata = VideoMetadata.fromMap('legacy-video-id', const {
      'uid': 'uid-redacted',
      'fileName': 'legacy.mp4',
      'storagePath': 'storage/path/legacy',
      'albumName': 'album',
      'fileSize': 1234,
      'uploadStatus': 'completed',
      'uploadProgress': 100,
    });

    expect(metadata.thumbnailStoragePath, isNull);
    expect(metadata.thumbnailStatus, isNull);
    expect(metadata.thumbnailWidth, isNull);
    expect(metadata.thumbnailHeight, isNull);
    expect(metadata.durationMs, isNull);
    expect(metadata.hasCompletedThumbnail, isFalse);
  });

  test('completed thumbnail metadata is required for upload move success', () {
    final completed = VideoMetadata.fromMap('video-id', const {
      'uid': 'uid-redacted',
      'fileName': 'redacted.mp4',
      'storagePath': 'storage/path/redacted',
      'albumName': 'album',
      'fileSize': 1234,
      'uploadStatus': 'completed',
      'uploadProgress': 100,
      'thumbnailStoragePath': 'storage/path/thumb',
      'thumbnailStatus': 'completed',
      'thumbnailWidth': 320,
      'thumbnailHeight': 180,
      'durationMs': 2100,
    });
    final missingThumbnail = VideoMetadata.fromMap('video-id', const {
      'uid': 'uid-redacted',
      'fileName': 'redacted.mp4',
      'storagePath': 'storage/path/redacted',
      'albumName': 'album',
      'fileSize': 1234,
      'uploadStatus': 'completed',
      'uploadProgress': 100,
    });

    expect(CloudService.isCompletedCloudMoveMetadata(completed), isTrue);
    expect(
      CloudService.isCompletedCloudMoveMetadata(missingThumbnail),
      isFalse,
    );
  });

  test('local cleanup is gated by video, thumbnail, and metadata success', () {
    expect(
      CloudService.shouldRunLocalCleanupAfterUploadMove(
        videoUploadSucceeded: true,
        thumbnailGenerated: true,
        thumbnailUploaded: true,
        metadataCommitted: true,
      ),
      isTrue,
    );
    expect(
      CloudService.shouldRunLocalCleanupAfterUploadMove(
        videoUploadSucceeded: false,
        thumbnailGenerated: true,
        thumbnailUploaded: true,
        metadataCommitted: true,
      ),
      isFalse,
    );
    expect(
      CloudService.shouldRunLocalCleanupAfterUploadMove(
        videoUploadSucceeded: true,
        thumbnailGenerated: false,
        thumbnailUploaded: true,
        metadataCommitted: true,
      ),
      isFalse,
    );
    expect(
      CloudService.shouldRunLocalCleanupAfterUploadMove(
        videoUploadSucceeded: true,
        thumbnailGenerated: true,
        thumbnailUploaded: false,
        metadataCommitted: true,
      ),
      isFalse,
    );
    expect(
      CloudService.shouldRunLocalCleanupAfterUploadMove(
        videoUploadSucceeded: true,
        thumbnailGenerated: true,
        thumbnailUploaded: true,
        metadataCommitted: false,
      ),
      isFalse,
    );
  });

  test('LocalIndexEntry preserves nullable thumbnail fields', () async {
    SharedPreferences.setMockInitialValues({});
    final service = LocalIndexService();
    final entry = LocalIndexEntry(
      id: 'cloud_only://album/video/redacted.mp4',
      type: 'clip',
      pathOrKey: 'cloud_only://album/video/redacted.mp4',
      ownerAccountId: 'uid-redacted',
      lockState: 'unlocked',
      updatedAt: DateTime.utc(2026, 5, 20),
      cloudVideoId: 'video-id',
      cloudStoragePath: 'storage/path/redacted',
      cloudStorageTier: 'cloud',
      cloudState: 'active',
      cloudFileName: 'redacted.mp4',
      cloudFileSize: 1234,
      albumName: 'album',
      thumbnailStoragePath: 'storage/path/thumb',
      thumbnailStatus: 'completed',
      thumbnailWidth: 320,
      thumbnailHeight: 180,
      durationMs: 2100,
    );

    await service.saveEntries(<LocalIndexEntry>[entry]);
    final loaded = await service.loadEntries();

    expect(loaded, hasLength(1));
    expect(loaded.single.thumbnailStoragePath, 'storage/path/thumb');
    expect(loaded.single.thumbnailStatus, 'completed');
    expect(loaded.single.thumbnailWidth, 320);
    expect(loaded.single.thumbnailHeight, 180);
    expect(loaded.single.durationMs, 2100);
  });
}
