const assert = require('node:assert/strict');
const path = require('node:path');
const test = require('node:test');

const { __test__ } = require('../scripts/cloud_usage_reconcile_dry_run');

test('usage reconciliation report is dry-run and anonymized', () => {
  const report = __test__.buildUsageReconciliationReport({
    users: [
      {
        id: 'user-a',
        data: {
          storageUsage: 100,
          cloudUsedBytes: 100,
          cloudReservedUploadBytes: 50,
        },
      },
      {
        id: 'user-b',
        data: {
          storageUsage: 40,
          cloudReservedUploadBytes: 0,
        },
      },
    ],
    videos: [
      {
        id: 'video-active-a',
        data: {
          uid: 'user-a',
          uploadStatus: 'completed',
          cloudState: 'active',
          fileSize: 100,
          storagePath: 'users/user-a/videos/video-active-a/clip.mp4',
        },
      },
      {
        id: 'video-reserved-a',
        data: {
          uid: 'user-a',
          uploadStatus: 'reserved',
          fileSize: 50,
          storagePath: 'users/user-a/videos/video-reserved-a/clip.mp4',
        },
      },
      {
        id: 'video-missing-size-a',
        data: {
          uid: 'user-a',
          uploadStatus: 'completed',
          fileSize: 0,
          storagePath: 'users/user-a/videos/video-missing-size-a/clip.mp4',
        },
      },
      {
        id: 'video-missing-path-a',
        data: {
          uid: 'user-a',
          uploadStatus: 'completed',
          fileSize: 25,
        },
      },
      {
        id: 'video-orphan-b',
        data: {
          uid: 'user-b',
          uploadStatus: 'failed',
          fileSize: 10,
          storagePath: 'users/user-b/videos/video-orphan-b/clip.mp4',
        },
      },
      {
        id: 'video-user-c',
        data: {
          uid: 'user-c',
          uploadStatus: 'completed',
          cloudState: 'active',
          fileSize: 20,
          storagePath: 'users/user-c/videos/video-user-c/clip.mp4',
        },
      },
      {
        id: 'video-no-uid',
        data: {
          uploadStatus: 'completed',
          fileSize: 5,
          storagePath: 'users/unknown/videos/video-no-uid/clip.mp4',
        },
      },
    ],
  }, { hashSalt: 'unit-test-salt', fixture: true }, new Date('2026-05-22T00:00:00Z'));

  assert.equal(report.dryRun, true);
  assert.equal(report.policy.firestoreWrites, 0);
  assert.equal(report.policy.storageDeletes, 0);
  assert.equal(report.policy.accountingSourceOfTruth, 'usageEvents');
  assert.equal(
    report.policy.repairAuthority,
    'usageEvents_must_win_before_any_future_mutation',
  );
  assert.equal(report.summary.completedActiveVideoBytesTotal, 120);
  assert.equal(report.summary.storageUsageTotal, 140);
  assert.equal(report.summary.reservedBytesFromVideosTotal, 50);
  assert.equal(report.summary.reservedBytesFromUsersTotal, 50);
  assert.equal(report.summary.missingFileSizeCount, 1);
  assert.equal(report.summary.missingStoragePathCount, 1);
  assert.equal(report.summary.orphanCandidateCount, 1);
  assert.equal(report.summary.missingUserDocumentCount, 1);
  assert.equal(report.summary.missingVideoUidCount, 1);

  const serialized = JSON.stringify(report);
  assert.equal(serialized.includes('user-a'), false);
  assert.equal(serialized.includes('user-b'), false);
  assert.equal(serialized.includes('user-c'), false);
  assert.equal(serialized.includes('users/user-a/videos'), false);
  assert.match(report.users[0].uidHash, /^[0-9a-f]{24}$/);
});

test('usage reconciliation row deltas distinguish storage and reserved summaries', () => {
  const report = __test__.buildUsageReconciliationReport({
    users: [
      {
        id: 'user-a',
        data: {
          storageUsage: 90,
          cloudUsedBytes: 80,
          cloudReservedUploadBytes: 5,
        },
      },
    ],
    videos: [
      {
        id: 'video-active-a',
        data: {
          uid: 'user-a',
          uploadStatus: 'completed',
          fileSize: 100,
          storagePath: 'users/user-a/videos/video-active-a/clip.mp4',
        },
      },
      {
        id: 'video-reserved-a',
        data: {
          uid: 'user-a',
          uploadStatus: 'uploading',
          reservedFileSize: 25,
          fileSize: 10,
          storagePath: 'users/user-a/videos/video-reserved-a/clip.mp4',
        },
      },
    ],
  }, { hashSalt: 'unit-test-salt' }, new Date('2026-05-22T00:00:00Z'));

  const row = report.users[0];
  assert.equal(row.storageUsage, 90);
  assert.equal(row.cloudUsedBytes, 80);
  assert.equal(row.completedActiveVideoBytes, 100);
  assert.equal(row.reservedBytesFromVideos, 25);
  assert.equal(row.reservedBytesFromUser, 5);
  assert.equal(row.suggestedStorageUsageDelta, 10);
  assert.equal(row.suggestedCloudUsedBytesDelta, 20);
  assert.equal(row.suggestedReservedBytesDelta, 20);
  assert.equal(row.hasStorageUsageDivergence, true);
  assert.equal(row.hasReservedBytesDivergence, true);
});

test('report output path must remain under logs', () => {
  const logsDir = path.resolve('/repo/logs');
  assert.equal(
    __test__.assertOutputDirUnderLogs('/repo/logs/cloud-usage', logsDir),
    path.resolve('/repo/logs/cloud-usage'),
  );
  assert.equal(
    __test__.assertOutputDirUnderLogs('/repo/logs', logsDir),
    path.resolve('/repo/logs'),
  );
  assert.throws(
    () => __test__.assertOutputDirUnderLogs('/repo/tmp', logsDir),
    /logs/,
  );
});
