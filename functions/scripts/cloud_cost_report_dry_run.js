#!/usr/bin/env node

/**
 * Daily Cloud cost control report dry-run.
 *
 * Safety contract:
 * - Never writes Firestore documents.
 * - Never calls Storage APIs.
 * - Never mutates usage accounting.
 * - Emits anonymized uid hashes only.
 */

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const QUERY_VERSION = 'cloud_cost_control_daily_report_v1';
const DEFAULT_LOGS_DIR = path.resolve(__dirname, '..', '..', 'logs');
const DEFAULT_HASH_SALT = 'moa_cloud_cost_report_v1';
const USERS_COLLECTION = 'users';
const USAGE_EVENTS_COLLECTION = 'usageEvents';
const BYTES_PER_GB = 1024 * 1024 * 1024;
const DEFAULT_STORAGE_KRW_PER_GB_MONTH = 40;
const DEFAULT_EGRESS_KRW_PER_GB = 160;

function printHelp() {
  console.log(`Daily Cloud cost control report dry-run

Usage:
  node functions/scripts/cloud_cost_report_dry_run.js [options]

Options:
  --fixture <path>                    Read fixture JSON instead of Firebase
  --project <id>                      Firebase project id for Admin SDK initialization
  --limit <count>                     Firestore query limit per collection/group
  --period <yyyy-MM>                  Usage period. Default: current UTC month
  --storage-krw-per-gb-month <value>  Estimated storage unit cost. Default: ${DEFAULT_STORAGE_KRW_PER_GB_MONTH}
  --egress-krw-per-gb <value>         Estimated egress unit cost. Default: ${DEFAULT_EGRESS_KRW_PER_GB}
  --write-report                      Write anonymized JSON report under logs/
  --out-dir <path>                    Output directory under logs/. Default: logs
  --help                              Show this help

This tool is dry-run only. It does not mutate Firestore, delete Storage objects, or deploy Functions.`);
}

function parseArgs(argv) {
  const options = {
    fixture: null,
    project: null,
    limit: null,
    periodKey: currentUtcPeriodKey(),
    storageKrwPerGbMonth: readNumberEnv(
      'MOA_STORAGE_KRW_PER_GB_MONTH',
      DEFAULT_STORAGE_KRW_PER_GB_MONTH,
    ),
    egressKrwPerGb: readNumberEnv(
      'MOA_EGRESS_KRW_PER_GB',
      DEFAULT_EGRESS_KRW_PER_GB,
    ),
    writeReport: false,
    outDir: DEFAULT_LOGS_DIR,
    help: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = () => {
      i += 1;
      if (i >= argv.length) throw new Error(`Missing value for ${arg}`);
      return argv[i];
    };

    switch (arg) {
      case '--fixture':
        options.fixture = path.resolve(process.cwd(), next());
        break;
      case '--project':
        options.project = normalizeString(next());
        break;
      case '--limit':
        options.limit = parsePositiveInteger(next(), '--limit');
        break;
      case '--period':
        options.periodKey = parsePeriodKey(next());
        break;
      case '--storage-krw-per-gb-month':
        options.storageKrwPerGbMonth = parseNonNegativeNumber(
          next(),
          '--storage-krw-per-gb-month',
        );
        break;
      case '--egress-krw-per-gb':
        options.egressKrwPerGb = parseNonNegativeNumber(
          next(),
          '--egress-krw-per-gb',
        );
        break;
      case '--write-report':
        options.writeReport = true;
        break;
      case '--out-dir':
        options.outDir = path.resolve(process.cwd(), next());
        break;
      case '--help':
      case '-h':
        options.help = true;
        break;
      default:
        throw new Error(`Unknown option: ${arg}`);
    }
  }

  return options;
}

function parsePositiveInteger(raw, name) {
  const value = Number(raw);
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }
  return value;
}

function parseNonNegativeNumber(raw, name) {
  const value = Number(raw);
  if (!Number.isFinite(value) || value < 0) {
    throw new Error(`${name} must be a non-negative number`);
  }
  return value;
}

function parsePeriodKey(raw) {
  const value = normalizeString(raw);
  if (!/^\d{4}-\d{2}$/.test(value)) {
    throw new Error('--period must use yyyy-MM format');
  }
  const month = Number(value.slice(5, 7));
  if (month < 1 || month > 12) {
    throw new Error('--period month must be between 01 and 12');
  }
  return value;
}

function readNumberEnv(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === null || raw === '') return fallback;
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
}

function currentUtcPeriodKey(date = new Date()) {
  const month = String(date.getUTCMonth() + 1).padStart(2, '0');
  return `${date.getUTCFullYear()}-${month}`;
}

function normalizeString(value) {
  return value === undefined || value === null ? '' : String(value).trim();
}

function normalizeState(value) {
  return normalizeString(value).toLowerCase();
}

function normalizeRuntimeTier(value) {
  const tier = normalizeState(value);
  if (tier === 'premium') return 'standard';
  if (tier === 'standard' || tier === 'free') return tier;
  return '';
}

function nonNegativeInt(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) return 0;
  return Math.trunc(parsed);
}

function hashValue(value, salt = process.env.MOA_REPORT_HASH_SALT || DEFAULT_HASH_SALT) {
  return crypto
    .createHash('sha256')
    .update(`${salt}:${String(value || '')}`)
    .digest('hex');
}

function shortHash(value, salt) {
  return hashValue(value, salt).slice(0, 24);
}

function readMillis(value) {
  if (value === null || value === undefined || value === '') return null;
  if (typeof value === 'number' && Number.isFinite(value)) return Math.trunc(value);
  if (typeof value === 'string') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return Math.trunc(parsed);
    const dateMs = Date.parse(value);
    return Number.isFinite(dateMs) ? dateMs : null;
  }
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value.toDate === 'function') {
    const date = value.toDate();
    return Number.isNaN(date.getTime()) ? null : date.getTime();
  }
  if (typeof value.seconds === 'number') {
    return value.seconds * 1000 + Math.trunc((value.nanoseconds || 0) / 1000000);
  }
  if (typeof value._seconds === 'number') {
    return value._seconds * 1000 + Math.trunc((value._nanoseconds || 0) / 1000000);
  }
  return null;
}

function firstMillis(values) {
  for (const value of values) {
    const millis = readMillis(value);
    if (millis !== null && millis > 0) return millis;
  }
  return null;
}

function normalizeCloudAccessState(value) {
  const state = normalizeState(value);
  if ([
    'active_standard',
    'expired_grace_period',
    'read_only_cloud',
    'scheduled_for_cleanup',
    'deleted',
  ].includes(state)) {
    return state;
  }
  return '';
}

function isActiveStandardUser(data, nowMs) {
  const explicitState = normalizeCloudAccessState(data?.cloudAccessState);
  if (explicitState === 'active_standard') return true;
  if ([
    'expired_grace_period',
    'read_only_cloud',
    'scheduled_for_cleanup',
    'deleted',
  ].includes(explicitState)) {
    return false;
  }

  const tier = normalizeRuntimeTier(data?.subscriptionTier);
  if (tier !== 'standard') return false;

  const nextTier = normalizeRuntimeTier(data?.nextTier || data?.nextUserTier);
  const nextTierEffectiveAt = readMillis(data?.nextTierEffectiveAt);
  const explicitExpiry = firstMillis([
    data?.subscriptionExpiresAt,
    data?.subscriptionExpiryAt,
    data?.expiryTimeMillis,
    data?.expiryAt,
    data?.lastKnownPaidExpiryAt,
  ]);
  const paidExpiry = nextTier === 'free' && nextTierEffectiveAt !== null
    ? (explicitExpiry === null ? nextTierEffectiveAt : Math.min(explicitExpiry, nextTierEffectiveAt))
    : explicitExpiry;

  return paidExpiry === null || paidExpiry > nowMs;
}

function gb(bytes) {
  return bytes / BYTES_PER_GB;
}

function roundNumber(value, digits = 2) {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function riskLevel(costPerStandardUserKrw) {
  if (costPerStandardUserKrw <= 1500) return 'GREEN';
  if (costPerStandardUserKrw <= 2500) return 'YELLOW';
  return 'RED';
}

function eventUid(event) {
  return normalizeString(event.parentUid || event.uid || event.data?.uid);
}

function isDownloadEventForPeriod(event, periodKey) {
  const data = event.data || {};
  return normalizeState(data.eventType) === 'download' &&
    normalizeString(data.periodKey) === periodKey;
}

function eventDownloadBytes(event) {
  const data = event.data || {};
  if (data.cacheHit === true || normalizeState(data.status) === 'cache_hit') {
    return 0;
  }
  if (data.downloadDelta !== undefined) return nonNegativeInt(data.downloadDelta);
  return nonNegativeInt(data.bytes);
}

function eventCacheKind(event) {
  const data = event.data || {};
  if (data.cacheHit === true || normalizeState(data.status) === 'cache_hit') {
    return 'hit';
  }
  return 'miss';
}

function createUserRow(uid, data = null, options = {}) {
  const storageBytes = data && data.cloudUsedBytes !== undefined
    ? nonNegativeInt(data.cloudUsedBytes)
    : nonNegativeInt(data?.storageUsage);
  const monthlySummaryPeriodKey = normalizeString(data?.monthlyDownloadPeriodKey);
  const monthlySummaryBytes = monthlySummaryPeriodKey === '' ||
    monthlySummaryPeriodKey === options.periodKey
    ? nonNegativeInt(data?.monthlyDownloadBytes)
    : 0;

  return {
    uid,
    userDocumentExists: Boolean(data),
    activeStandard: isActiveStandardUser(data || {}, options.nowMs || Date.now()),
    cloudUsedBytes: storageBytes,
    monthlyDownloadSummaryBytes: monthlySummaryBytes,
    monthlyDownloadEventBytes: 0,
    monthlyDownloadEventCount: 0,
    cacheHitCount: 0,
    cacheMissCount: 0,
  };
}

function getOrCreateRow(rowsByUid, uid, data, options) {
  if (!rowsByUid.has(uid)) {
    rowsByUid.set(uid, createUserRow(uid, data, options));
  }
  return rowsByUid.get(uid);
}

function publicUserRow(row, hashSalt) {
  const summaryDelta = row.monthlyDownloadEventBytes - row.monthlyDownloadSummaryBytes;
  return {
    uidHash: shortHash(row.uid, hashSalt),
    userDocumentExists: row.userDocumentExists,
    activeStandard: row.activeStandard,
    cloudUsedBytes: row.cloudUsedBytes,
    cloudUsedGB: roundNumber(gb(row.cloudUsedBytes), 3),
    monthlyDownloadBytesFromUsageEvents: row.monthlyDownloadEventBytes,
    monthlyDownloadGBFromUsageEvents: roundNumber(gb(row.monthlyDownloadEventBytes), 3),
    monthlyDownloadSummaryBytes: row.monthlyDownloadSummaryBytes,
    monthlyDownloadSummaryDeltaBytes: summaryDelta,
    monthlyDownloadEventCount: row.monthlyDownloadEventCount,
    cacheHitCount: row.cacheHitCount,
    cacheMissCount: row.cacheMissCount,
  };
}

function topUsers(rows, field, hashSalt, limit = 10) {
  return rows
    .filter((row) => row[field] > 0)
    .sort((a, b) => b[field] - a[field])
    .slice(0, limit)
    .map((row) => ({
      uidHash: shortHash(row.uid, hashSalt),
      bytes: row[field],
      gb: roundNumber(gb(row[field]), 3),
      activeStandard: row.activeStandard,
    }));
}

function buildDailyCostReport(inventory, options = {}, startedAt = new Date()) {
  const periodKey = options.periodKey || currentUtcPeriodKey(startedAt);
  const nowMs = options.nowMs || startedAt.getTime();
  const hashSalt = options.hashSalt || process.env.MOA_REPORT_HASH_SALT || DEFAULT_HASH_SALT;
  const storageKrwPerGbMonth = options.storageKrwPerGbMonth ?? DEFAULT_STORAGE_KRW_PER_GB_MONTH;
  const egressKrwPerGb = options.egressKrwPerGb ?? DEFAULT_EGRESS_KRW_PER_GB;
  const users = Array.isArray(inventory.users) ? inventory.users : [];
  const usageEvents = Array.isArray(inventory.usageEvents) ? inventory.usageEvents : [];
  const rowsByUid = new Map();
  let downloadEventsMissingUidCount = 0;
  let ignoredUsageEventCount = 0;

  for (const user of users) {
    const uid = normalizeString(user.id || user.uid);
    if (!uid) continue;
    rowsByUid.set(uid, createUserRow(uid, user.data || {}, {
      periodKey,
      nowMs,
    }));
  }

  for (const event of usageEvents) {
    if (!isDownloadEventForPeriod(event, periodKey)) {
      ignoredUsageEventCount += 1;
      continue;
    }
    const uid = eventUid(event);
    if (!uid) {
      downloadEventsMissingUidCount += 1;
      continue;
    }

    const row = getOrCreateRow(rowsByUid, uid, null, { periodKey, nowMs });
    const bytes = eventDownloadBytes(event);
    row.monthlyDownloadEventBytes += bytes;
    row.monthlyDownloadEventCount += 1;
    if (eventCacheKind(event) === 'hit') {
      row.cacheHitCount += 1;
    } else {
      row.cacheMissCount += 1;
    }
  }

  const privateRows = Array.from(rowsByUid.values());
  const activeStandardRows = privateRows.filter((row) => row.activeStandard);
  const totalStandardUsers = activeStandardRows.length;
  const totalCloudUsedBytes = privateRows.reduce((sum, row) => sum + row.cloudUsedBytes, 0);
  const totalMonthlyDownloadBytes = privateRows.reduce(
    (sum, row) => sum + row.monthlyDownloadEventBytes,
    0,
  );
  const totalMonthlyDownloadSummaryBytes = privateRows.reduce(
    (sum, row) => sum + row.monthlyDownloadSummaryBytes,
    0,
  );
  const totalCacheHitCount = privateRows.reduce((sum, row) => sum + row.cacheHitCount, 0);
  const totalCacheMissCount = privateRows.reduce((sum, row) => sum + row.cacheMissCount, 0);
  const totalCacheEvents = totalCacheHitCount + totalCacheMissCount;
  const estimatedStorageCostKrw = gb(totalCloudUsedBytes) * storageKrwPerGbMonth;
  const estimatedDownloadCostKrw = gb(totalMonthlyDownloadBytes) * egressKrwPerGb;
  const estimatedTotalCostKrw = estimatedStorageCostKrw + estimatedDownloadCostKrw;
  const estimatedCostPerStandardUserKrw = totalStandardUsers > 0
    ? estimatedTotalCostKrw / totalStandardUsers
    : 0;

  const publicRows = privateRows
    .map((row) => publicUserRow(row, hashSalt))
    .sort((a, b) => {
      const aCostBytes = a.cloudUsedBytes + a.monthlyDownloadBytesFromUsageEvents;
      const bCostBytes = b.cloudUsedBytes + b.monthlyDownloadBytesFromUsageEvents;
      if (aCostBytes !== bCostBytes) return bCostBytes - aCostBytes;
      return a.uidHash.localeCompare(b.uidHash);
    });

  return {
    reportId: `cloud_cost_control_daily_${startedAt.toISOString().replace(/[:.]/g, '-')}_${crypto.randomUUID().slice(0, 8)}`,
    generatedAt: new Date().toISOString(),
    dryRun: true,
    queryVersion: QUERY_VERSION,
    periodKey,
    environment: {
      nodeVersion: process.version,
      platform: process.platform,
      fixtureMode: Boolean(options.fixture),
      limit: options.limit || null,
    },
    policy: {
      mutationProhibited: true,
      firestoreWrites: 0,
      storageDeletes: 0,
      deploys: 0,
      userIdentifiers: 'sha256_24char_hash_only',
      rawStoragePaths: 'omitted',
      accountingSourceOfTruth: 'usageEvents',
      monthlyDownloadBytesRole: 'denormalized_summary_for_divergence_check',
      riskThresholdsKrwPerStandardUser: {
        greenMax: 1500,
        yellowMax: 2500,
      },
    },
    pricingModel: {
      currency: 'KRW',
      storageKrwPerGbMonth,
      egressKrwPerGb,
      operatorEstimate: true,
    },
    scannedCollections: {
      users: users.length,
      usageEvents: usageEvents.length,
    },
    summary: {
      totalStandardUsers,
      reportUserRowCount: publicRows.length,
      totalCloudUsedBytes,
      totalCloudUsedGB: roundNumber(gb(totalCloudUsedBytes), 3),
      averageCloudUsedGBPerStandardUser: totalStandardUsers > 0
        ? roundNumber(gb(totalCloudUsedBytes) / totalStandardUsers, 3)
        : 0,
      totalMonthlyDownloadBytes,
      totalMonthlyDownloadGB: roundNumber(gb(totalMonthlyDownloadBytes), 3),
      averageMonthlyDownloadGBPerStandardUser: totalStandardUsers > 0
        ? roundNumber(gb(totalMonthlyDownloadBytes) / totalStandardUsers, 3)
        : 0,
      monthlyDownloadSummaryBytesTotal: totalMonthlyDownloadSummaryBytes,
      monthlyDownloadSummaryDeltaBytes:
        totalMonthlyDownloadBytes - totalMonthlyDownloadSummaryBytes,
      cacheHitCount: totalCacheHitCount,
      cacheMissCount: totalCacheMissCount,
      cacheHitRatio: totalCacheEvents > 0
        ? roundNumber(totalCacheHitCount / totalCacheEvents, 4)
        : 0,
      estimatedStorageCostKrw: roundNumber(estimatedStorageCostKrw, 2),
      estimatedDownloadCostKrw: roundNumber(estimatedDownloadCostKrw, 2),
      estimatedTotalCostKrw: roundNumber(estimatedTotalCostKrw, 2),
      estimatedCostPerStandardUserKrw: roundNumber(
        estimatedCostPerStandardUserKrw,
        2,
      ),
      riskLevel: riskLevel(estimatedCostPerStandardUserKrw),
      downloadEventsMissingUidCount,
      ignoredUsageEventCount,
    },
    topStorageUsers: topUsers(privateRows, 'cloudUsedBytes', hashSalt),
    topDownloadUsers: topUsers(privateRows, 'monthlyDownloadEventBytes', hashSalt),
    users: publicRows,
  };
}

function loadFixtureInventory(fixturePath) {
  const raw = fs.readFileSync(fixturePath, 'utf8');
  const parsed = JSON.parse(raw);
  return {
    users: Array.isArray(parsed.users) ? parsed.users : [],
    usageEvents: Array.isArray(parsed.usageEvents) ? parsed.usageEvents : [],
  };
}

async function loadFirebaseInventory(options) {
  const admin = require('firebase-admin');
  if (admin.apps.length === 0) {
    admin.initializeApp(options.project ? { projectId: options.project } : undefined);
  }

  const firestore = admin.firestore();
  let userQuery = firestore.collection(USERS_COLLECTION);
  let usageEventQuery = firestore.collectionGroup(USAGE_EVENTS_COLLECTION);
  if (options.limit) {
    userQuery = userQuery.limit(options.limit);
    usageEventQuery = usageEventQuery.limit(options.limit);
  }

  const [userSnapshot, usageEventSnapshot] = await Promise.all([
    userQuery.get(),
    usageEventQuery.get(),
  ]);

  return {
    users: userSnapshot.docs.map((doc) => ({ id: doc.id, data: doc.data() })),
    usageEvents: usageEventSnapshot.docs.map((doc) => ({
      id: doc.id,
      parentUid: doc.ref.parent.parent ? doc.ref.parent.parent.id : null,
      data: doc.data(),
    })),
  };
}

function resolveLogsDir() {
  return path.resolve(DEFAULT_LOGS_DIR);
}

function assertOutputDirUnderLogs(outDir, logsDir = resolveLogsDir()) {
  const resolvedOutDir = path.resolve(outDir);
  const resolvedLogsDir = path.resolve(logsDir);
  const relative = path.relative(resolvedLogsDir, resolvedOutDir);
  if (relative === '') return resolvedOutDir;
  if (relative.startsWith('..') || path.isAbsolute(relative)) {
    throw new Error('Report output must stay under logs/');
  }
  return resolvedOutDir;
}

function writeReport(report, outDir) {
  const safeOutDir = assertOutputDirUnderLogs(outDir);
  fs.mkdirSync(safeOutDir, { recursive: true });
  const filePath = path.join(safeOutDir, `${report.reportId}.json`);
  fs.writeFileSync(filePath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  return filePath;
}

async function main() {
  const startedAt = new Date();
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    printHelp();
    return;
  }

  const inventory = options.fixture
    ? loadFixtureInventory(options.fixture)
    : await loadFirebaseInventory(options);
  const report = buildDailyCostReport(inventory, options, startedAt);
  const reportPath = options.writeReport ? writeReport(report, options.outDir) : null;

  console.log(JSON.stringify({
    success: true,
    dryRun: true,
    reportPath,
    queryVersion: report.queryVersion,
    periodKey: report.periodKey,
    summary: report.summary,
    topStorageUsers: report.topStorageUsers,
    topDownloadUsers: report.topDownloadUsers,
  }, null, 2));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(JSON.stringify({
      success: false,
      dryRun: true,
      error: error.message,
    }, null, 2));
    process.exitCode = 1;
  });
}

module.exports = {
  __test__: {
    QUERY_VERSION,
    DEFAULT_LOGS_DIR,
    BYTES_PER_GB,
    buildDailyCostReport,
    assertOutputDirUnderLogs,
    currentUtcPeriodKey,
    eventDownloadBytes,
    isActiveStandardUser,
    normalizeRuntimeTier,
    parsePeriodKey,
    riskLevel,
    shortHash,
  },
};
