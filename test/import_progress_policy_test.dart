import 'package:flutter_test/flutter_test.dart';
import 'package:three_s/constants/clip_policy.dart';
import 'package:three_s/models/clip_save_job_state.dart';
import 'package:three_s/models/import_state.dart';
import 'package:three_s/utils/clip_extraction_exit_policy.dart';
import 'package:three_s/utils/media_import_order_policy.dart';

void main() {
  group('import progress policy', () {
    test('ImportState exposes terminal percent and percent text', () {
      final now = DateTime(2026, 6, 6, 12);
      final state = ImportState(
        total: 4,
        inProgress: 1,
        completed: 1,
        failed: 1,
        skipped: 1,
        canceled: 0,
        items: <String, ImportItemState>{
          '1': ImportItemState.queued(
            id: '1',
            path: 'a.mp4',
            filename: 'a.mp4',
            index: 0,
            now: now,
          ).copyWith(status: ImportItemStatus.completed),
          '2': ImportItemState.queued(
            id: '2',
            path: 'b.mp4',
            filename: 'b.mp4',
            index: 1,
            now: now,
          ).copyWith(status: ImportItemStatus.failed, error: 'extract_failed'),
          '3': ImportItemState.queued(
            id: '3',
            path: 'c.mp4',
            filename: 'c.mp4',
            index: 2,
            now: now,
          ).copyWith(status: ImportItemStatus.skipped),
          '4': ImportItemState.queued(
            id: '4',
            path: 'd.mp4',
            filename: 'd.mp4',
            index: 3,
            now: now,
          ).copyWith(status: ImportItemStatus.processing),
        },
        updatedAt: now,
        cancelRequested: false,
      );

      expect(state.terminalCount, 3);
      expect(state.progressValue, 0.75);
      expect(state.percentText(), '75%');
      expect(state.progressText(), contains('75%'));
      expect(state.progressText(), contains('실패 1'));
    });

    test('ClipSaveJobState exposes save percent and active state', () {
      final now = DateTime(2026, 6, 6, 12);
      ClipSaveJob job(String id, ClipSaveJobStatus status) {
        return ClipSaveJob.queued(
          id: id,
          sourcePath: '$id-source.mp4',
          destinationPath: '$id-destination.mp4',
          startMs: 0,
          endMs: 2000,
          durationMs: 2000,
          now: now,
        ).copyWith(status: status);
      }

      final state = ClipSaveJobState(
        total: 4,
        running: 1,
        completed: 2,
        failed: 1,
        skipped: 0,
        canceled: 0,
        queue: <ClipSaveJob>[
          job('1', ClipSaveJobStatus.success),
          job('2', ClipSaveJobStatus.success),
          job('3', ClipSaveJobStatus.failed),
          job('4', ClipSaveJobStatus.running),
        ],
        activeJobs: <ClipSaveJob>[job('4', ClipSaveJobStatus.running)],
        cancelRequested: false,
      );

      expect(state.terminalCount, 3);
      expect(state.progressValue, 0.75);
      expect(state.percentText(), '75%');
      expect(state.progressText(), contains('75%'));
      expect(state.progressText(), contains('실행중 1'));
    });

    test('zero-total states remain deterministic instead of indeterminate', () {
      final importState = ImportState.initial(now: DateTime(2026, 6, 6, 12));
      final clipSaveState = ClipSaveJobState.initial();

      expect(importState.terminalCount, 0);
      expect(importState.progressValue, 0.0);
      expect(importState.percentText(), '0%');
      expect(clipSaveState.terminalCount, 0);
      expect(clipSaveState.progressValue, 0.0);
      expect(clipSaveState.percentText(), '0%');
    });

    test('system back and app bar close share the active save exit guard', () {
      expect(
        shouldBlockClipExtractionExit(
          isExporting: true,
          hasActiveTrackedSaves: false,
        ),
        isTrue,
      );
      expect(
        shouldBlockClipExtractionExit(
          isExporting: false,
          hasActiveTrackedSaves: true,
        ),
        isTrue,
      );
      expect(
        shouldBlockClipExtractionExit(
          isExporting: false,
          hasActiveTrackedSaves: false,
        ),
        isFalse,
      );
    });

    test('clip extraction validation allows encoder metadata drift', () {
      expect(kTargetClipMinAcceptableMs, 2090);
      expect(isClipDurationWithinTargetContract(2097), isTrue);
      expect(isClipDurationWithinTargetContract(2099), isTrue);
      expect(isClipDurationWithinTargetContract(2089), isFalse);
    });

    test('imported clip segments register newest selected segment first', () {
      expect(
        orderImportedClipSegmentsForAlbumRegistration(const [0, 2100]),
        const [2100, 0],
      );
      expect(
        orderImportedClipSegmentsForAlbumRegistration(const [0, 2100, 4200]),
        const [4200, 2100, 0],
      );
    });

    test('media import videos preserve picker-returned effective order', () {
      final ordered = orderMediaImportItemsForProcessing(const [
        'video_3.mp4',
        'video_2.mp4',
        'video_1.mp4',
      ]);

      expect(ordered.map((entry) => entry.item), const [
        'video_3.mp4',
        'video_2.mp4',
        'video_1.mp4',
      ]);
      expect(ordered.map((entry) => entry.effectiveIndex), const [0, 1, 2]);
      expect(ordered.map((entry) => entry.originalIndex), const [0, 1, 2]);
    });
  });
}
