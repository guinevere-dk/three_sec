#!/usr/bin/env node

/**
 * Cloud Clip R4 migration/backfill inventory dry-run.
 *
 * Safety contract:
 * - Never writes Firestore documents.
 * - Never performs batch update/backfill.
 * - Never removes fallback fields or changes collection/path contracts.
 * - Produces a local JSON report only, with anonymized hashes/counts.
 */

const admin = require('firebase-admin');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const QUERY_VERSION = 'cloud_clip_r4_migration_backfill_inventory_v1';
const DEFAULT_LOGS_DIR = path.resolve(__dirname, '..', '..', 'logs');
const STORAGE_VIDEO_PATH_RE = /^users\/([^/]+)\/videos\/([^/]+)\/(.+)$/;

const COLLECTIONS = {
  users: 'users',
  videos: 'videos',
  projects: 'vlog_projects',
  folders: 'vlog_folders',
};

const VIDEO_FIELDS = [
  'uid',
  'videoId',
  'fileName',
  'storagePath',
  'storageTier',
  'lifecycleState',
  'cloudState',
  'originalStoragePath',
  'originalStorageTier',
  'localPath',
  'albumName',
  'isFavorite',
  'fileSize',
  'uploadStatus',
  'uploadProgress',
  'downloadUrl',
  'createdAt',
  'updatedAt',
  'completedAt',
  'trashed',
  'trashedAt',
  'trashedFromAlbumName',
  'originalAlbumName',
  'restoredAt',
  'deleted',
  'errorCode',
  'errorCopy',
];

const PROJECT_FIELDS = [
  'uid',
  'localProjectId',
  'title',
  'clipPaths',
  'clipCount',
  'folderName',
  'lockState',
  'clientCreatedAt',
  'clientUpdatedAt',
  'lastSyncedAt',
  'deleted',
  'cloudProjectId',
  'ownerAccountId',
];

const USER_FIELDS = [
  'subscriptionTier',
  'storageUsage',
  'lastUpdated',
  'nextTierEffectiveAt',
  'nextUserTier',
  'productId',
  'purchaseDate',
];

const FOLDER_FIELDS = [
  'uid',
  'folderName',
  'name',
  'ownerAccountId',
  'createdAt',
  'updatedAt',
  'deleted',
];

const KNOWN_CLOUD_STATES = new Set([
  '',
  'active',
  'cloud',
  'local_only',
  'queued',
  'pending',
  'uploading',
  'completed',
  'failed',
  'trash',
  'tombstone',
  'deleted',
  'restoring',
  'restore_pending',
  'copying',
  'copy_pending',
  'blocked_by_subscription',
]);

const KNOWN_LIFECYCLE_STATES = new Set([
  '',
  'active',
  'trash',
  'tombstone',
  'deleted',
  'restoring',
  'restore_pending',
]);

function printHelp() {
  console.log(`Cloud Clip R4 migration/backfill inventory dry-run

Usage:
  node functions/scripts/cloud_clip_r4_migration_backfill_inventory.js [options]

Options:
  --fixture <path>              Read fixture JSON instead of Firebase for local safety validation
  --out-dir <path>              Report output directory. Default: logs
  --include-folders             Include read-only scan of vlog_folders collection when available
  --limit <count>               Firestore query limit per collection for operator-controlled sampling
  --help                        Show this help

This tool is dry-run only. It does not mutate Firestore, run backfill, or remove fallbacks.`);
}

function parseArgs(argv) {
  const options = {
    fixture: null,
    outDir: DEFAULT_LOGS_DIR,
    includeFolders: false,
    limit: null,
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
      case '--out-dir':
        options.outDir = path.resolve(process.cwd(), next());
        break;
      case '--include-folders':
        options.includeFolders = true;
        break;
      case '--limit':
        options.limit = parsePositiveInteger(next(), '--limit');
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

function sha256(value) {
  return crypto.createHash('sha256').update(String(value || '')).digest('hex');
}

function shortHash(value) {
  return sha256(value).slice(0, 24);
}

function normalizeString(value) {
  return value === undefined || value === null ? '' : String(value).trim();
}

function normalizeState(value) {
  return normalizeString(value).toLowerCase();
}

function isMissing(value) {
  return value === undefined || value === null || (typeof value === 'string' && value.trim() === '');
}

function parseTimestamp(value) {
  if (!value) return null;
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value;
  if (typeof value.toDate === 'function') {
    const date = value.toDate();
    return Number.isNaN(date.getTime()) ? null : date;
  }
  if (typeof value._seconds === 'number') {
    return new Date(value._seconds * 1000 + Math.floor((value._nanoseconds || 0) / 1000000));
  }
  if (typeof value.seconds === 'number') {
    return new Date(value.seconds * 1000 + Math.floor((value.nanoseconds || 0) / 1000000));
  }
  if (typeof value === 'string' || typeof value === 'number') {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

function parseStorageVideoPath(storagePath) {
  const match = STORAGE_VIDEO_PATH_RE.exec(normalizeString(storagePath));
  if (!match) return null;
  return {
    uid: match[1],
    videoId: match[2],
    fileName: match[3],
  };
}

function typeName(value) {
  if (value === null) return 'null';
  if (Array.isArray(value)) return 'array';
  if (parseTimestamp(value)) return 'timestamp';
  return typeof value;
}

function createFieldDistribution(fields) {
  return fields.reduce((acc, field) => {
    acc[field] = {
      present: 0,
      missing: 0,
      nullOrEmpty: 0,
      types: {},
      values: {},
    };
    return acc;
  }, {});
}

function increment(map, key, by = 1) {
  map[key] = (map[key] || 0) + by;
}

function recordValue(dist, value) {
  increment(dist.types, typeName(value));
  if (typeof value === 'string' || typeof value === 'boolean' || typeof value === 'number') {
    const key = String(value).trim().toLowerCase();
    if (key && Object.keys(dist.values).length < 80) increment(dist.values, key);
  }
}

function updateFieldDistribution(distribution, data) {
  for (const [field, dist] of Object.entries(distribution)) {
    if (!Object.prototype.hasOwnProperty.call(data, field)) {
      dist.missing += 1;
      continue;
    }
    dist.present += 1;
    if (isMissing(data[field])) dist.nullOrEmpty += 1;
    recordValue(dist, data[field]);
  }
}

function redactDoc(collection, doc, reasonCodes) {
  const data = doc.data || {};
  return {
    collection,
    documentIdHash: shortHash(doc.id || ''),
    uidHash: data.uid ? shortHash(data.uid) : null,
    videoIdHash: data.videoId ? shortHash(data.videoId) : null,
    localProjectIdHash: data.localProjectId ? shortHash(data.localProjectId) : null,
    storagePathHash: data.storagePath ? shortHash(data.storagePath) : null,
    reasonCodes,
  };
}

function classifyVideo(doc) {
  const data = doc.data || {};
  const reasons = [];
  const storagePath = normalizeString(data.storagePath);
  const uid = normalizeString(data.uid);
  const videoId = normalizeString(data.videoId || doc.id);
  const lifecycleState = normalizeState(data.lifecycleState);
  const cloudState = normalizeState(data.cloudState);
  const uploadStatus = normalizeState(data.uploadStatus);
  const isTrash = data.trashed === true || ['trash', 'tombstone', 'deleted'].includes(lifecycleState) || ['trash', 'tombstone', 'deleted'].includes(cloudState);

  if (storagePath && isMissing(data.storageTier) && isMissing(data.originalStorageTier)) {
    reasons.push('missing_storage_tier_with_storage_path');
  }
  if (isMissing(data.lifecycleState)) reasons.push('missing_lifecycle_state');
  if (isMissing(data.cloudState)) reasons.push('missing_cloud_state');
  if (!storagePath && !cloudState && (uploadStatus === 'completed' || data.downloadUrl)) {
    reasons.push('legacy_local_only_without_cloud_state');
  }
  if (cloudState && !KNOWN_CLOUD_STATES.has(cloudState)) reasons.push('unknown_cloud_state');
  if (lifecycleState && !KNOWN_LIFECYCLE_STATES.has(lifecycleState)) reasons.push('unknown_lifecycle_state');

  if (storagePath) {
    const parsed = parseStorageVideoPath(storagePath);
    if (!parsed) {
      reasons.push('storage_path_invalid_prefix');
    } else {
      if (uid && parsed.uid !== uid) reasons.push('storage_path_owner_mismatch');
      if (videoId && parsed.videoId !== videoId) reasons.push('storage_path_video_id_mismatch');
    }
  }

  if (isTrash && isMissing(data.originalStoragePath) && storagePath) {
    reasons.push('trash_missing_original_storage_path');
  }
  if (isTrash && isMissing(data.originalStorageTier) && (storagePath || data.originalStoragePath)) {
    reasons.push('trash_missing_original_storage_tier');
  }
  if (isMissing(data.uid)) reasons.push('owner_uid_missing');
  if (isMissing(data.createdAt) || isMissing(data.updatedAt)) reasons.push('timestamp_missing');
  if (data.createdAt && !parseTimestamp(data.createdAt)) reasons.push('timestamp_invalid');
  if (data.updatedAt && !parseTimestamp(data.updatedAt)) reasons.push('timestamp_invalid');
  if (!isMissing(data.fileSize) && (!Number.isFinite(Number(data.fileSize)) || Number(data.fileSize) < 0)) {
    reasons.push('file_size_invalid');
  }

  return Array.from(new Set(reasons));
}

function classifyProject(doc, folderNames) {
  const data = doc.data || {};
  const reasons = [];
  if (isMissing(data.uid)) reasons.push('owner_uid_missing');
  if (isMissing(data.localProjectId)) reasons.push('project_ref_missing');
  if (isMissing(data.folderName)) reasons.push('folder_ref_missing');
  if (!Array.isArray(data.clipPaths)) reasons.push('clip_paths_missing_or_invalid');
  if (!Number.isFinite(Number(data.clipCount))) reasons.push('clip_count_missing_or_invalid');
  if (Array.isArray(data.clipPaths) && Number.isFinite(Number(data.clipCount)) && data.clipPaths.length !== Number(data.clipCount)) {
    reasons.push('clip_count_mismatch');
  }
  if (data.folderName && folderNames.size > 0 && !folderNames.has(data.folderName)) reasons.push('folder_ref_missing');
  if (isMissing(data.clientCreatedAt) || isMissing(data.clientUpdatedAt)) reasons.push('timestamp_missing');
  if (data.clientCreatedAt && !parseTimestamp(data.clientCreatedAt)) reasons.push('timestamp_invalid');
  if (data.clientUpdatedAt && !parseTimestamp(data.clientUpdatedAt)) reasons.push('timestamp_invalid');
  return Array.from(new Set(reasons));
}

function classifyUser(doc) {
  const data = doc.data || {};
  const reasons = [];
  if (isMissing(data.subscriptionTier)) reasons.push('subscription_tier_missing');
  if (!isMissing(data.storageUsage) && (!Number.isFinite(Number(data.storageUsage)) || Number(data.storageUsage) < 0)) {
    reasons.push('storage_usage_invalid');
  }
  if (data.lastUpdated && !parseTimestamp(data.lastUpdated)) reasons.push('timestamp_invalid');
  return Array.from(new Set(reasons));
}

function classifyFolder(doc) {
  const data = doc.data || {};
  const reasons = [];
  if (isMissing(data.uid) && isMissing(data.ownerAccountId)) reasons.push('owner_uid_missing');
  if (isMissing(data.folderName) && isMissing(data.name)) reasons.push('folder_ref_missing');
  if (data.createdAt && !parseTimestamp(data.createdAt)) reasons.push('timestamp_invalid');
  if (data.updatedAt && !parseTimestamp(data.updatedAt)) reasons.push('timestamp_invalid');
  return Array.from(new Set(reasons));
}

function buildCandidateList(reasonSummary) {
  const candidates = [];
  const add = (reasonCode, minimalFields, rationale, risk, fallbackAvailable, stagedRolloutRequired) => {
    const count = reasonSummary[reasonCode] || 0;
    if (count <= 0) return;
    candidates.push({
      reasonCode,
      affectedAnonymousDocCount: count,
      proposedMinimalFields: minimalFields,
      rationale,
      risk,
      fallbackAvailable,
      stagedRolloutRequired,
      execution: 'proposal_only_no_write_code',
    });
  };

  add(
    'missing_storage_tier_with_storage_path',
    ['storageTier'],
    'storagePath가 있는 cloud metadata에서 tier 판정 fallback을 명시화할 수 있는 최소 후보입니다.',
    'medium',
    true,
    true,
  );
  add(
    'missing_lifecycle_state',
    ['lifecycleState'],
    'Trash/restore와 삭제 후보 판정에서 active/trash 구분의 기본값 후보입니다.',
    'medium',
    true,
    true,
  );
  add(
    'missing_cloud_state',
    ['cloudState'],
    'Cloud placeholder와 upload 상태 표시를 보수적으로 안정화할 수 있는 최소 후보입니다.',
    'medium',
    true,
    true,
  );
  add(
    'trash_missing_original_storage_path',
    ['originalStoragePath'],
    'Trash 복원 시 원본 Storage path 보존에 필요한 후보입니다. storagePath 근거가 명확한 문서만 허용해야 합니다.',
    'high',
    false,
    true,
  );
  add(
    'trash_missing_original_storage_tier',
    ['originalStorageTier'],
    'Trash 복원 시 원래 cloud/local tier 판정에 필요한 후보입니다.',
    'high',
    false,
    true,
  );
  add(
    'project_ref_missing',
    ['localProjectId'],
    'Project metadata 연결에 필요한 최소 후보이나, doc id와 client local id 관계가 확실한 경우에만 가능합니다.',
    'high',
    true,
    true,
  );
  add(
    'folder_ref_missing',
    ['folderName'],
    'Project/folder 표시 fallback을 명시화할 후보이나 기본 폴더 추론이 불확실하면 backfill하지 않습니다.',
    'medium',
    true,
    true,
  );

  return candidates;
}

async function loadFirebaseInventory(options) {
  if (admin.apps.length === 0) admin.initializeApp();
  const firestore = admin.firestore();
  const readCollection = async (name) => {
    let query = firestore.collection(name);
    if (options.limit) query = query.limit(options.limit);
    const snapshot = await query.get();
    return snapshot.docs.map((doc) => ({ id: doc.id, data: doc.data() }));
  };

  const inventory = {
    users: await readCollection(COLLECTIONS.users),
    videos: await readCollection(COLLECTIONS.videos),
    projects: await readCollection(COLLECTIONS.projects),
    folders: [],
  };

  if (options.includeFolders) {
    inventory.folders = await readCollection(COLLECTIONS.folders);
  }
  return inventory;
}

function loadFixtureInventory(fixturePath) {
  const raw = fs.readFileSync(fixturePath, 'utf8');
  const parsed = JSON.parse(raw);
  return {
    users: Array.isArray(parsed.users) ? parsed.users : [],
    videos: Array.isArray(parsed.videos) ? parsed.videos : [],
    projects: Array.isArray(parsed.projects) ? parsed.projects : [],
    folders: Array.isArray(parsed.folders) ? parsed.folders : [],
  };
}

function buildInventoryReport(inventory, options, startedAt) {
  const fieldDistribution = {
    users: createFieldDistribution(USER_FIELDS),
    videos: createFieldDistribution(VIDEO_FIELDS),
    projects: createFieldDistribution(PROJECT_FIELDS),
    folders: createFieldDistribution(FOLDER_FIELDS),
  };
  const reasonSummary = {};
  const anomalies = [];
  const fieldCombinationSummary = {};
  const uidHashes = new Set();
  const storagePathHashes = new Set();
  const folderNames = new Set(inventory.folders.map((doc) => doc.data?.folderName || doc.data?.name).filter(Boolean));

  const handleReasons = (collection, doc, reasons) => {
    for (const reason of reasons) increment(reasonSummary, reason);
    if (reasons.length > 0 && anomalies.length < 200) anomalies.push(redactDoc(collection, doc, reasons));
  };

  for (const doc of inventory.users) {
    updateFieldDistribution(fieldDistribution.users, doc.data || {});
    if (doc.id) uidHashes.add(shortHash(doc.id));
    handleReasons('users', doc, classifyUser(doc));
  }

  for (const doc of inventory.videos) {
    const data = doc.data || {};
    updateFieldDistribution(fieldDistribution.videos, data);
    if (data.uid) uidHashes.add(shortHash(data.uid));
    if (data.storagePath) storagePathHashes.add(shortHash(data.storagePath));
    const combination = [
      data.storagePath ? 'storagePath' : 'noStoragePath',
      data.storageTier || data.originalStorageTier ? 'tier' : 'noTier',
      data.lifecycleState ? `lifecycle:${normalizeState(data.lifecycleState)}` : 'noLifecycle',
      data.cloudState ? `cloud:${normalizeState(data.cloudState)}` : 'noCloudState',
      data.trashed === true ? 'trashed' : 'notTrashed',
    ].join('|');
    increment(fieldCombinationSummary, combination);
    handleReasons('videos', doc, classifyVideo(doc));
  }

  for (const doc of inventory.projects) {
    updateFieldDistribution(fieldDistribution.projects, doc.data || {});
    if (doc.data?.uid) uidHashes.add(shortHash(doc.data.uid));
    handleReasons('vlog_projects', doc, classifyProject(doc, folderNames));
  }

  for (const doc of inventory.folders) {
    updateFieldDistribution(fieldDistribution.folders, doc.data || {});
    if (doc.data?.uid) uidHashes.add(shortHash(doc.data.uid));
    handleReasons('vlog_folders', doc, classifyFolder(doc));
  }

  return {
    reportId: `cloud_clip_r4_migration_backfill_inventory_${startedAt.toISOString().replace(/[:.]/g, '-')}_${crypto.randomUUID().slice(0, 8)}`,
    generatedAt: new Date().toISOString(),
    dryRun: true,
    queryVersion: QUERY_VERSION,
    environment: {
      nodeVersion: process.version,
      platform: process.platform,
      fixtureMode: Boolean(options.fixture),
      includeFolders: options.includeFolders,
      limit: options.limit,
    },
    policy: {
      mutationProhibited: true,
      firestoreWrites: 0,
      batchUpdates: 0,
      fallbackRemoval: 0,
      collectionRenames: 0,
      storagePathChanges: 0,
    },
    summary: {
      scannedCollections: {
        users: inventory.users.length,
        videos: inventory.videos.length,
        vlog_projects: inventory.projects.length,
        vlog_folders: inventory.folders.length,
      },
      uniqueAnonymousUidHashCount: uidHashes.size,
      uniqueStoragePathHashCount: storagePathHashes.size,
      reasonSummary,
      backfillCandidateReasonCount: buildCandidateList(reasonSummary).length,
    },
    fieldDistribution,
    fieldCombinationSummary,
    anomalies,
    backfillCandidateList: buildCandidateList(reasonSummary),
    stagedRolloutPlan: [
      'no-op/dry-run report review only',
      'fixture and emulator validation before any write preview',
      'sample cohort selected by anonymous hash bucket after approval',
      'write disabled by default and protected by explicit feature flag',
      'export target docs before write preview',
      'keep dual-read fallback until old/new client compatibility is verified',
    ],
    rollbackPlan: [
      'current dry-run stage is no-op and requires no data rollback',
      'before future mutation, export existing values for every proposed field',
      'never overwrite existing non-empty fields; only consider missing/null fields',
      'disable feature flag and stop batches on anomaly increase',
      'restore exported values or remove newly added optional fields if rollback is approved',
      'keep fallback reads active during and after rollback',
    ],
  };
}

function writeReport(report, outDir) {
  fs.mkdirSync(outDir, { recursive: true });
  const filePath = path.join(outDir, `${report.reportId}.json`);
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

  const inventory = options.fixture ? loadFixtureInventory(options.fixture) : await loadFirebaseInventory(options);
  const report = buildInventoryReport(inventory, options, startedAt);
  const reportPath = writeReport(report, options.outDir);

  console.log(JSON.stringify({
    success: true,
    dryRun: true,
    reportPath,
    scannedCollections: report.summary.scannedCollections,
    reasonSummary: report.summary.reasonSummary,
    backfillCandidateReasonCount: report.summary.backfillCandidateReasonCount,
  }, null, 2));
}

main().catch((error) => {
  console.error(JSON.stringify({
    success: false,
    dryRun: true,
    error: error.message,
  }, null, 2));
  process.exitCode = 1;
});
