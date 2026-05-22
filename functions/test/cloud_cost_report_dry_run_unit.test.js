const assert = require('node:assert/strict');
const path = require('node:path');
const test = require('node:test');

const { __test__ } = require('../scripts/cloud_cost_report_dry_run');

const gb = __test__.BYTES_PER_GB;

test('daily cost report uses usageEvents as source of truth and anonymizes users', () => {
  const report = __test__.buildDailyCostReport({
    users: [
      {
        id: 'user-standard-a',
        data: {
          subscriptionTier: 'standard',
          cloudUsedBytes: 10 * gb,
          monthlyDownloadBytes: 99 * gb,
          monthlyDownloadPeriodKey: '2026-05',
        },
      },
      {
        id: 'user-premium-b',
        data: {
          subscriptionTier: 'premium',
          storageUsage: 20 * gb,
          monthlyDownloadBytes: 1 * gb,
          monthlyDownloadPeriodKey: '2026-05',
        },
      },
      {
        id: 'user-free-c',
        data: {
          subscriptionTier: 'free',
          storageUsage: 5 * gb,
          monthlyDownloadBytes: 8 * gb,
          monthlyDownloadPeriodKey: '2026-05',
        },
      },
    ],
    usageEvents: [
      {
        id: 'download-a-miss',
        parentUid: 'user-standard-a',
        data: {
          uid: 'user-standard-a',
          eventType: 'download',
          periodKey: '2026-05',
          downloadDelta: 2 * gb,
          cacheHit: false,
        },
      },
      {
        id: 'download-a-hit',
        parentUid: 'user-standard-a',
        data: {
          uid: 'user-standard-a',
          eventType: 'download',
          periodKey: '2026-05',
          downloadDelta: 0,
          cacheHit: true,
          status: 'cache_hit',
        },
      },
      {
        id: 'download-b-miss',
        parentUid: 'user-premium-b',
        data: {
          uid: 'user-premium-b',
          eventType: 'download',
          periodKey: '2026-05',
          bytes: 1 * gb,
          cacheHit: false,
        },
      },
      {
        id: 'download-c-miss',
        parentUid: 'user-free-c',
        data: {
          uid: 'user-free-c',
          eventType: 'download',
          periodKey: '2026-05',
          downloadDelta: 3 * gb,
          cacheHit: false,
        },
      },
      {
        id: 'download-old',
        parentUid: 'user-standard-a',
        data: {
          uid: 'user-standard-a',
          eventType: 'download',
          periodKey: '2026-04',
          downloadDelta: 5 * gb,
          cacheHit: false,
        },
      },
    ],
  }, {
    fixture: true,
    hashSalt: 'unit-test-salt',
    periodKey: '2026-05',
    storageKrwPerGbMonth: 100,
    egressKrwPerGb: 200,
    nowMs: Date.parse('2026-05-22T00:00:00Z'),
  }, new Date('2026-05-22T00:00:00Z'));

  assert.equal(report.dryRun, true);
  assert.equal(report.policy.firestoreWrites, 0);
  assert.equal(report.policy.storageDeletes, 0);
  assert.equal(report.policy.accountingSourceOfTruth, 'usageEvents');
  assert.equal(report.summary.totalStandardUsers, 2);
  assert.equal(report.summary.totalCloudUsedBytes, 35 * gb);
  assert.equal(report.summary.totalMonthlyDownloadBytes, 6 * gb);
  assert.equal(report.summary.monthlyDownloadSummaryBytesTotal, 108 * gb);
  assert.equal(report.summary.monthlyDownloadSummaryDeltaBytes, -102 * gb);
  assert.equal(report.summary.cacheHitCount, 1);
  assert.equal(report.summary.cacheMissCount, 3);
  assert.equal(report.summary.cacheHitRatio, 0.25);
  assert.equal(report.summary.estimatedStorageCostKrw, 3500);
  assert.equal(report.summary.estimatedDownloadCostKrw, 1200);
  assert.equal(report.summary.estimatedTotalCostKrw, 4700);
  assert.equal(report.summary.estimatedCostPerStandardUserKrw, 2350);
  assert.equal(report.summary.riskLevel, 'YELLOW');
  assert.equal(report.summary.ignoredUsageEventCount, 1);
  assert.equal(report.topStorageUsers.length, 3);
  assert.equal(report.topDownloadUsers[0].bytes, 3 * gb);

  const serialized = JSON.stringify(report);
  assert.equal(serialized.includes('user-standard-a'), false);
  assert.equal(serialized.includes('user-premium-b'), false);
  assert.equal(serialized.includes('user-free-c'), false);
  assert.match(report.topStorageUsers[0].uidHash, /^[0-9a-f]{24}$/);
});

test('active standard count normalizes dormant premium but excludes expired states', () => {
  const nowMs = Date.parse('2026-05-22T00:00:00Z');

  assert.equal(
    __test__.isActiveStandardUser({ subscriptionTier: 'premium' }, nowMs),
    true,
  );
  assert.equal(
    __test__.isActiveStandardUser({ cloudAccessState: 'active_standard' }, nowMs),
    true,
  );
  assert.equal(
    __test__.isActiveStandardUser({
      subscriptionTier: 'standard',
      nextTier: 'free',
      nextTierEffectiveAt: nowMs + 1000,
    }, nowMs),
    true,
  );
  assert.equal(
    __test__.isActiveStandardUser({
      subscriptionTier: 'standard',
      nextTier: 'free',
      nextTierEffectiveAt: nowMs,
    }, nowMs),
    false,
  );
  assert.equal(
    __test__.isActiveStandardUser({
      subscriptionTier: 'standard',
      cloudAccessState: 'read_only_cloud',
    }, nowMs),
    false,
  );
});

test('risk level follows KRW per Standard user thresholds', () => {
  assert.equal(__test__.riskLevel(1500), 'GREEN');
  assert.equal(__test__.riskLevel(1500.01), 'YELLOW');
  assert.equal(__test__.riskLevel(2500), 'YELLOW');
  assert.equal(__test__.riskLevel(2500.01), 'RED');
});

test('period parser and output path guard are strict', () => {
  assert.equal(__test__.parsePeriodKey('2026-05'), '2026-05');
  assert.throws(() => __test__.parsePeriodKey('2026-13'), /month/);
  assert.throws(() => __test__.parsePeriodKey('202605'), /yyyy-MM/);

  const logsDir = path.resolve('/repo/logs');
  assert.equal(
    __test__.assertOutputDirUnderLogs('/repo/logs/cost-report', logsDir),
    path.resolve('/repo/logs/cost-report'),
  );
  assert.throws(
    () => __test__.assertOutputDirUnderLogs('/repo/outside', logsDir),
    /logs/,
  );
});
