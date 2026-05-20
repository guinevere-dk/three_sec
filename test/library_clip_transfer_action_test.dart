import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:three_s/managers/video_manager.dart';
import 'package:three_s/screens/library_screen.dart';

void main() {
  test('localOnly selection resolves to upload action and icon', () {
    final action = resolveLibraryClipTransferAction(const [
      ClipStorageState.localOnly,
    ]);

    expect(action, LibraryClipTransferAction.upload);
    expect(
      libraryClipTransferIconForAction(action),
      Icons.cloud_upload_rounded,
    );
  });

  test('cloudOnly selection resolves to download action and icon', () {
    final action = resolveLibraryClipTransferAction(const [
      ClipStorageState.cloudOnly,
    ]);

    expect(action, LibraryClipTransferAction.download);
    expect(libraryClipTransferIconForAction(action), Icons.download_rounded);
  });

  test('cloudSyncedLocal selection resolves to cloud done disabled state', () {
    final action = resolveLibraryClipTransferAction(const [
      ClipStorageState.cloudSyncedLocal,
    ]);

    expect(action, LibraryClipTransferAction.cloudDone);
    expect(libraryClipTransferIconForAction(action), Icons.cloud_done_rounded);
  });

  test('mixed selection resolves to disabled action', () {
    final action = resolveLibraryClipTransferAction(const [
      ClipStorageState.localOnly,
      ClipStorageState.cloudOnly,
    ]);

    expect(action, LibraryClipTransferAction.disabled);
    expect(
      libraryClipTransferIconForAction(action),
      Icons.download_for_offline_rounded,
    );
  });

  test('failedUpload selection resolves to upload retry action', () {
    final action = resolveLibraryClipTransferAction(const [
      ClipStorageState.failedUpload,
    ]);

    expect(action, LibraryClipTransferAction.upload);
    expect(
      libraryClipTransferIconForAction(action),
      Icons.cloud_upload_rounded,
    );
  });

  test('pendingUpload selection resolves to progress disabled action', () {
    final action = resolveLibraryClipTransferAction(const [
      ClipStorageState.pendingUpload,
    ]);

    expect(action, LibraryClipTransferAction.progress);
    expect(libraryClipTransferIconForAction(action), Icons.sync_rounded);
  });

  test(
    'pre-pending localOnly target remains upload eligible after pending UI marker',
    () {
      const prePendingState = ClipStorageState.localOnly;
      const runtimeStateAfterUiMarker = ClipStorageState.pendingUpload;

      expect(isUploadMoveEligibleFromPrePendingState(prePendingState), isTrue);
      expect(
        resolveLibraryClipTransferAction(const [runtimeStateAfterUiMarker]),
        LibraryClipTransferAction.progress,
      );
    },
  );

  test('pre-pending failedUpload target remains upload retry eligible', () {
    expect(
      isUploadMoveEligibleFromPrePendingState(ClipStorageState.failedUpload),
      isTrue,
    );
  });

  test('pre-pending non-upload states are not upload eligible', () {
    for (final state in const [
      ClipStorageState.cloudOnly,
      ClipStorageState.cloudSyncedLocal,
      ClipStorageState.pendingUpload,
      ClipStorageState.failedDownload,
    ]) {
      expect(isUploadMoveEligibleFromPrePendingState(state), isFalse);
    }
  });
}
