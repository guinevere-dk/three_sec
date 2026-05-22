#!/usr/bin/env node

/**
 * Cloud usage reconciliation dry-run.
 *
 * Safety contract:
 * - Never writes Firestore documents.
 * - Never calls Storage delete APIs.
 * - Never mutates usage accounting.
 * - Emits anonymized uid hashes only; raw uid/storagePath values are never
 *   included in the report.
 */

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const QUERY_VERSION = 'cloud_usage_reconcile_dry_run_v1';
const DEFAULT_LOGS_DIR = path.resolve(__dirname, '..', '..', 'logs');
const DEFAULT_HASH_SALT = 'moa_cloud_usage_reconcile_v1';
const USERS_COLLECTION = 'users';
const VIDEOS_COLLECTION = 'videos';
const RESERVATION_STATUSES = new Set(['reserved', 'uploading']);
const INACTIVE_STATES = new Set(['trash', 'tombstone', 'deleted']);

function printHelp() {
  console.log(`Cloud usage reconciliation dry-run

Usage:
  node functions/scripts/cloud_usage_reconcile_dry_run.js [options]

Options:
  --fixture <path>              Read fixture JSON instead of Firebase
  --project <id>                Firebase project id for Admin SDK initialization
  --limit <count>               Firestore query limit per collection
  --write-report                Write anonymized JSON report under logs/
  --out-dir <path>              Output directory under logs/. Default: logs
  --help                        Show this help

This tool is dry-run only. It does not mutate Firestore, delete Storage objects, or repair counters.`);
}

function parseArgs(argv) {
  const options = {
    fixture: null,
    project: null,
    limit: null,
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

function normalizeString(value) {
  return value === undefined || value === null ? '' : String(value).trim();
}

function normalizeState(value) {
  return normalizeString(value).toLowerCase();
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

function hasInactiveState(data) {
  return data.deleted === true ||
    data.trashed === true ||
    INACTIVE_STATES.has(normalizeState(data.lifecycleState)) ||
    INACTIVE_STATES.has(normalizeState(data.cloudState));
}

function isActiveCompletedVideo(data) {
  if (!data || typeof data !== 'object') return false;
  if (!normalizeString(data.uid)) return false;
  if (normalizeState(data.uploadStatus) !== 'completed') return false;
  if (hasInactiveState(data)) return false;
  if (!normalizeString(data.storagePath)) return false;
  return nonNegativeInt(data.fileSize) > 0;
}

function isActiveReservation(data) {
  if (!data || typeof data !== 'object') return false;
  if (!normalizeString(data.uid)) return false;
  if (data.reservationReleased === true) return false;
  return RESERVATION_STATUSES.has(normalizeState(data.uploadStatus));
}

function isMissingFileSizeForActiveVideo(data) {
  if (!data || typeof data !== 'object') return false;
  if (!normalizeString(data.uid)) return false;
  if (normalizeState(data.uploadStatus) !== 'completed') return false;
  if (hasInactiveState(data)) return false;
  if (!normalizeString(data.storagePath)) return false;
  return nonNegativeInt(data.fileSize) <= 0;
}

function isMissingStoragePathForActiveVideo(data) {
  if (!data || typeof data !== 'object') return false;
  if (!normalizeString(data.uid)) return false;
  if (normalizeState(data.uploadStatus) !== 'completed') return false;
  if (hasInactiveState(data)) return false;
  return !normalizeString(data.storagePath);
}

function isMetadataOrphanCandidate(data) {
  if (!data || typeof data !== 'object') return false;
  if (!normalizeString(data.uid)) return false;
  if (!normalizeString(data.storagePath)) return false;
  if (normalizeState(data.uploadStatus) === 'completed' && !hasInactiveState(data)) {
    return false;
  }
  return !isActiveCompletedVideo(data) && !isActiveReservation(data);
}

function createAccumulator(uid, userData = null) {
  const storageUsage = nonNegativeInt(userData?.storageUsage);
  const cloudUsedBytes = userData && userData.cloudUsedBytes !== undefined
    ? nonNegativeInt(userData.cloudUsedBytes)
    : storageUsage;
  return {
    uid,
    userDocumentExists: Boolean(userData),
    storageUsage,
    cloudUsedBytes,
    reservedBytesFromUser: nonNegativeInt(userData?.cloudReservedUploadBytes),
    completedActiveVideoBytes: 0,
    reservedBytesFromVideos: 0,
    videoDocumentCount: 0,
    activeCompletedVideoCount: 0,
    activeReservationCount: 0,
    missingFileSizeCount: 0,
    missingStoragePathCount: 0,
    orphanCandidateCount: 0,
  };
}

function sortedRows(rows) {
  return rows.sort((a, b) => {
    const aDelta = Math.abs(a.suggestedStorageUsageDelta) +
      Math.abs(a.suggestedReservedBytesDelta);
    const bDelta = Math.abs(b.suggestedStorageUsageDelta) +
      Math.abs(b.suggestedReservedBytesDelta);
    if (aDelta !== bDelta) return bDelta - aDelta;
    return a.uidHash.localeCompare(b.uidHash);
  });
}

function finalizeAccumulator(acc, hashSalt) {
  const suggestedStorageUsageDelta = acc.completedActiveVideoBytes - acc.storageUsage;
  const suggestedCloudUsedBytesDelta = acc.completedActiveVideoBytes - acc.cloudUsedBytes;
  const suggestedReservedBytesDelta = acc.reservedBytesFromVideos - acc.reservedBytesFromUser;

  return {
    uidHash: shortHash(acc.uid, hashSalt),
    userDocumentExists: acc.userDocumentExists,
    storageUsage: acc.storageUsage,
    cloudUsedBytes: acc.cloudUsedBytes,
    completedActiveVideoBytes: acc.completedActiveVideoBytes,
    reservedBytesFromVideos: acc.reservedBytesFromVideos,
    reservedBytesFromUser: acc.reservedBytesFromUser,
    missingFileSizeCount: acc.missingFileSizeCount,
    missingStoragePathCount: acc.missingStoragePathCount,
    orphanCandidateCount: acc.orphanCandidateCount,
    videoDocumentCount: acc.videoDocumentCount,
    activeCompletedVideoCount: acc.activeCompletedVideoCount,
    activeReservationCount: acc.activeReservationCount,
    suggestedStorageUsageDelta,
    suggestedCloudUsedBytesDelta,
    suggestedReservedBytesDelta,
    hasStorageUsageDivergence: suggestedStorageUsageDelta !== 0,
    hasReservedBytesDivergence: suggestedReservedBytesDelta !== 0,
  };
}

function summarizeRows(rows) {
  const summary = {
    anonymousUserRowCount: rows.length,
    storageUsageTotal: 0,
    cloudUsedBytesTotal: 0,
    completedActiveVideoBytesTotal: 0,
    reservedBytesFromVideosTotal: 0,
    reservedBytesFromUsersTotal: 0,
    missingFileSizeCount: 0,
    missingStoragePathCount: 0,
    orphanCandidateCount: 0,
    storageUsageDivergentUserCount: 0,
    reservedBytesDivergentUserCount: 0,
    missingUserDocumentCount: 0,
  };

  for (const row of rows) {
    summary.storageUsageTotal += row.storageUsage;
    summary.cloudUsedBytesTotal += row.cloudUsedBytes;
    summary.completedActiveVideoBytesTotal += row.completedActiveVideoBytes;
    summary.reservedBytesFromVideosTotal += row.reservedBytesFromVideos;
    summary.reservedBytesFromUsersTotal += row.reservedBytesFromUser;
    summary.missingFileSizeCount += row.missingFileSizeCount;
    summary.missingStoragePathCount += row.missingStoragePathCount;
    summary.orphanCandidateCount += row.orphanCandidateCount;
    if (row.hasStorageUsageDivergence) summary.storageUsageDivergentUserCount += 1;
    if (row.hasReservedBytesDivergence) summary.reservedBytesDivergentUserCount += 1;
    if (!row.userDocumentExists) summary.missingUserDocumentCount += 1;
  }

  return summary;
}

function buildUsageReconciliationReport(inventory, options = {}, startedAt = new Date()) {
  const hashSalt = options.hashSalt || process.env.MOA_REPORT_HASH_SALT || DEFAULT_HASH_SALT;
  const byUid = new Map();
  const videos = Array.isArray(inventory.videos) ? inventory.videos : [];
  const users = Array.isArray(inventory.users) ? inventory.users : [];
  let missingVideoUidCount = 0;

  for (const user of users) {
    const uid = normalizeString(user.id);
    if (!uid) continue;
    byUid.set(uid, createAccumulator(uid, user.data || {}));
  }

  const ensureAccumulator = (uid) => {
    if (!byUid.has(uid)) byUid.set(uid, createAccumulator(uid, null));
    return byUid.get(uid);
  };

  for (const video of videos) {
    const data = video.data || {};
    const uid = normalizeString(data.uid);
    if (!uid) {
      missingVideoUidCount += 1;
      continue;
    }

    const acc = ensureAccumulator(uid);
    acc.videoDocumentCount += 1;

    if (isActiveCompletedVideo(data)) {
      acc.activeCompletedVideoCount += 1;
      acc.completedActiveVideoBytes += nonNegativeInt(data.fileSize);
    }

    if (isActiveReservation(data)) {
      acc.activeReservationCount += 1;
      acc.reservedBytesFromVideos += nonNegativeInt(data.reservedFileSize || data.fileSize);
    }

    if (isMissingFileSizeForActiveVideo(data)) acc.missingFileSizeCount += 1;
    if (isMissingStoragePathForActiveVideo(data)) acc.missingStoragePathCount += 1;
    if (isMetadataOrphanCandidate(data)) acc.orphanCandidateCount += 1;
  }

  const rows = sortedRows(
    Array.from(byUid.values()).map((acc) => finalizeAccumulator(acc, hashSalt)),
  );

  return {
    reportId: `cloud_usage_reconcile_dry_run_${startedAt.toISOString().replace(/[:.]/g, '-')}_${crypto.randomUUID().slice(0, 8)}`,
    generatedAt: new Date().toISOString(),
    dryRun: true,
    queryVersion: QUERY_VERSION,
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
      usageAccountingWrites: 0,
      userIdentifiers: 'sha256_24char_hash_only',
      storagePaths: 'omitted',
      accountingSourceOfTruth: 'usageEvents',
      currentDryRunBasis: 'completed_active_video_metadata',
      repairAuthority: 'usageEvents_must_win_before_any_future_mutation',
      userMonthlyDownloadBytesRole: 'denormalized_summary',
      reportPurpose: 'storageUsage_vs_completed_active_video_metadata_dry_run',
    },
    scannedCollections: {
      users: users.length,
      videos: videos.length,
    },
    summary: {
      ...summarizeRows(rows),
      missingVideoUidCount,
    },
    users: rows,
  };
}

function loadFixtureInventory(fixturePath) {
  const raw = fs.readFileSync(fixturePath, 'utf8');
  const parsed = JSON.parse(raw);
  return {
    users: Array.isArray(parsed.users) ? parsed.users : [],
    videos: Array.isArray(parsed.videos) ? parsed.videos : [],
  };
}

async function loadFirebaseInventory(options) {
  const admin = require('firebase-admin');
  if (admin.apps.length === 0) {
    admin.initializeApp(options.project ? { projectId: options.project } : undefined);
  }

  const firestore = admin.firestore();
  const readCollection = async (name) => {
    let query = firestore.collection(name);
    if (options.limit) query = query.limit(options.limit);
    const snapshot = await query.get();
    return snapshot.docs.map((doc) => ({ id: doc.id, data: doc.data() }));
  };

  const [users, videos] = await Promise.all([
    readCollection(USERS_COLLECTION),
    readCollection(VIDEOS_COLLECTION),
  ]);
  return { users, videos };
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
  const report = buildUsageReconciliationReport(inventory, options, startedAt);
  const reportPath = options.writeReport ? writeReport(report, options.outDir) : null;

  console.log(JSON.stringify({
    success: true,
    dryRun: true,
    reportPath,
    queryVersion: report.queryVersion,
    scannedCollections: report.scannedCollections,
    summary: report.summary,
    users: report.users,
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
    buildUsageReconciliationReport,
    assertOutputDirUnderLogs,
    hasInactiveState,
    isActiveCompletedVideo,
    isActiveReservation,
    isMetadataOrphanCandidate,
    normalizeString,
    nonNegativeInt,
    shortHash,
  },
};
