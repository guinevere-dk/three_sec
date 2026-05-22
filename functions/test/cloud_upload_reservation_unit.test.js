const assert = require('node:assert/strict');
const test = require('node:test');

const { __test__ } = require('../cloud_upload_reservations');

test('Standard and dormant Premium tiers can reserve uploads while Free cannot', () => {
  const now = Date.UTC(2026, 4, 22);

  assert.equal(
    __test__.isPaidUploadEntitled({ subscriptionTier: 'standard' }, now),
    true,
  );
  assert.equal(
    __test__.isPaidUploadEntitled({ subscriptionTier: 'premium' }, now),
    true,
  );
  assert.equal(
    __test__.isPaidUploadEntitled({ subscriptionTier: 'free' }, now),
    false,
  );
});

test('Scheduled downgrade stays upload-entitled until the effective date', () => {
  const now = Date.UTC(2026, 4, 22);

  assert.equal(
    __test__.isPaidUploadEntitled({
      subscriptionTier: 'standard',
      nextTier: 'free',
      nextTierEffectiveAt: now + 1000,
    }, now),
    true,
  );
  assert.equal(
    __test__.resolveCloudAccessState({
      subscriptionTier: 'standard',
      nextTier: 'free',
      nextTierEffectiveAt: now + 1000,
    }, now),
    'active_standard',
  );
  assert.equal(
    __test__.isPaidUploadEntitled({
      subscriptionTier: 'standard',
      nextTier: 'free',
      nextTierEffectiveAt: now,
    }, now),
    false,
  );
  assert.equal(
    __test__.resolveCloudAccessState({
      subscriptionTier: 'standard',
      nextTier: 'free',
      nextTierEffectiveAt: now,
    }, now),
    'expired_grace_period',
  );
});

test('Expired or read-only Cloud states cannot start new upload reservations', () => {
  const now = Date.UTC(2026, 4, 22);

  assert.equal(
    __test__.isPaidUploadEntitled({
      subscriptionTier: 'standard',
      lastKnownPaidExpiryAt: now - 1,
    }, now),
    false,
  );
  assert.equal(
    __test__.resolveCloudAccessState({
      subscriptionTier: 'standard',
      lastKnownPaidExpiryAt: now - 1,
    }, now),
    'expired_grace_period',
  );
  assert.equal(
    __test__.isPaidUploadEntitled({
      subscriptionTier: 'standard',
      cloudAccessState: 'expired_grace_period',
    }, now),
    false,
  );
  assert.equal(
    __test__.canReadExistingCloudClips({
      subscriptionTier: 'standard',
      cloudAccessState: 'expired_grace_period',
    }, now),
    true,
  );
  assert.equal(
    __test__.canReadExistingCloudClips({
      subscriptionTier: 'standard',
      cloudAccessState: 'scheduled_for_cleanup',
    }, now),
    false,
  );
});

test('Free users with paid history can read only during the 30-day grace window', () => {
  const now = Date.UTC(2026, 4, 22);

  assert.equal(
    __test__.resolveCloudAccessState({
      subscriptionTier: 'free',
      lastKnownPaidExpiryAt: now - 10 * 24 * 60 * 60 * 1000,
    }, now),
    'read_only_cloud',
  );
  assert.equal(
    __test__.canReadExistingCloudClips({
      subscriptionTier: 'free',
      lastKnownPaidExpiryAt: now - 10 * 24 * 60 * 60 * 1000,
    }, now),
    true,
  );
  assert.equal(
    __test__.resolveCloudAccessState({
      subscriptionTier: 'free',
      lastKnownPaidExpiryAt: now - 31 * 24 * 60 * 60 * 1000,
    }, now),
    'scheduled_for_cleanup',
  );
  assert.equal(
    __test__.canReadExistingCloudClips({
      subscriptionTier: 'free',
      lastKnownPaidExpiryAt: now - 31 * 24 * 60 * 60 * 1000,
    }, now),
    false,
  );
  assert.equal(
    __test__.resolveCloudAccessState({ subscriptionTier: 'free' }, now),
    'deleted',
  );
});

test('50GB quota includes already used and reserved upload bytes', () => {
  const gb = 1024 * 1024 * 1024;
  assert.equal(__test__.canReserveUploadBytes(49 * gb, 0, 500 * 1024 * 1024, 50 * gb), true);
  assert.equal(
    __test__.canReserveUploadBytes(
      Math.trunc(49.8 * gb),
      0,
      500 * 1024 * 1024,
      50 * gb,
    ),
    false,
  );
  assert.equal(__test__.canReserveUploadBytes(49 * gb, 800 * 1024 * 1024, 500 * 1024 * 1024, 50 * gb), false);
});

test('Standard video object cap is separate from the legacy global safety cap', () => {
  assert.equal(__test__.STANDARD_VIDEO_OBJECT_LIMIT_BYTES, 50 * 1024 * 1024);
  assert.equal(__test__.MAX_VIDEO_OBJECT_BYTES, 500 * 1024 * 1024);
  assert.equal(
    __test__.canUploadStandardVideoObjectBytes(
      __test__.STANDARD_VIDEO_OBJECT_LIMIT_BYTES,
    ),
    true,
  );
  assert.equal(
    __test__.canUploadStandardVideoObjectBytes(
      __test__.STANDARD_VIDEO_OBJECT_LIMIT_BYTES + 1,
    ),
    false,
  );
  assert.equal(__test__.canUploadStandardVideoObjectBytes(0), false);
});

test('Standard upload metadata must be explicit and within 1080p envelope', () => {
  assert.equal(
    __test__.isStandardVideoMetadata({
      assetType: 'standard_video',
      cloudPreflightDecision: 'readyOriginal',
      normalizedQuality: '1080p',
      normalizedFileSize: 3 * 1024 * 1024,
      width: 1080,
      height: 1920,
    }),
    true,
  );
  assert.equal(
    __test__.isStandardVideoMetadata({
      assetType: 'raw_original',
      cloudPreflightDecision: 'readyOriginal',
      normalizedQuality: '1080p',
    }),
    false,
  );
  assert.equal(
    __test__.isStandardVideoMetadata({
      assetType: 'standard_video',
      cloudPreflightDecision: 'readyOriginal',
      normalizedQuality: '4K',
      width: 2160,
      height: 3840,
    }),
    false,
  );
  assert.equal(
    __test__.isStandardVideoMetadata({
      assetType: 'standard_video',
      cloudPreflightDecision: 'normalizedCopy',
      normalizedQuality: '1080p',
      normalizedFileSize: __test__.STANDARD_VIDEO_OBJECT_LIMIT_BYTES + 1,
      width: 1080,
      height: 1920,
    }),
    false,
  );
});

test('Storage file names are path-stripped and normalized to mp4', () => {
  assert.equal(__test__.sanitizeStorageFileName('C:\\tmp\\clip.mov'), 'clip.mov.mp4');
  assert.equal(__test__.sanitizeStorageFileName('../my clip.mp4'), 'my_clip.mp4');
  assert.equal(__test__.sanitizeStorageFileName(''), 'clip.mp4');
});

test('download usage mutation increments bytes only on cache miss', () => {
  const nowDate = new Date(Date.UTC(2026, 4, 22));
  const now = { seconds: Math.trunc(nowDate.getTime() / 1000), nanoseconds: 0 };

  const miss = __test__.buildDownloadUsageMutation({
    uid: 'user-a',
    videoId: 'video-a',
    source: 'edit_materialize',
    bytes: 1024,
    cacheHit: false,
    hardLimitEnabled: false,
    userData: { monthlyDownloadBytes: 2048, monthlyDownloadPeriodKey: '2026-05' },
    videoData: { downloadCount: 3 },
    now,
    nowDate,
    requestId: 'miss-1',
    eventId: 'event-1',
  });

  assert.equal(miss.userMerge.monthlyDownloadBytes, 3072);
  assert.equal(miss.userMerge.monthlyDownloadCacheMissCount, 1);
  assert.equal(miss.eventData.downloadDelta, 1024);
  assert.equal(miss.response.bytesRecorded, 1024);

  const hit = __test__.buildDownloadUsageMutation({
    uid: 'user-a',
    videoId: 'video-a',
    source: 'edit_materialize',
    bytes: 1024,
    cacheHit: true,
    hardLimitEnabled: false,
    userData: { monthlyDownloadBytes: 2048, monthlyDownloadPeriodKey: '2026-05' },
    videoData: { downloadCount: 3 },
    now,
    nowDate,
    requestId: 'hit-1',
    eventId: 'event-2',
  });

  assert.equal(hit.userMerge.monthlyDownloadBytes, 2048);
  assert.equal(hit.userMerge.monthlyDownloadCacheHitCount, 1);
  assert.equal(hit.eventData.downloadDelta, 0);
  assert.equal(hit.response.bytesRecorded, 0);
});

test('download event id is deterministic and includes source/day/hash', () => {
  const date = new Date(Date.UTC(2026, 4, 22));
  const first = __test__.buildDownloadEventId({
    videoId: 'video-a',
    source: 'export_materialize',
    cacheMissId: 'same-cache-miss',
    date,
  });
  const second = __test__.buildDownloadEventId({
    videoId: 'video-a',
    source: 'export_materialize',
    cacheMissId: 'same-cache-miss',
    date,
  });
  const third = __test__.buildDownloadEventId({
    videoId: 'video-a',
    source: 'export_materialize',
    cacheMissId: 'other-cache-miss',
    date,
  });

  assert.equal(first, second);
  assert.match(first, /^download_video-a_export_materialize_20260522_[0-9a-f]{16}$/);
  assert.notEqual(first, third);
});
