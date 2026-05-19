#!/usr/bin/env node

/**
 * Cloud Clip Storage delete dry-run inventory.
 *
 * Safety contract:
 * - Never calls Storage delete APIs.
 * - Never writes Firestore documents.
 * - Never updates usage accounting.
 * - Produces a local JSON manifest only.
 */

const admin = require('firebase-admin');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const QUERY_VERSION = 'cloud_clip_delete_dry_run_inventory_v1';
const DEFAULT_RETENTION_DAYS = 90;
const DEFAULT_STORAGE_PREFIX = 'users/';
const DEFAULT_LOGS_DIR = path.resolve(__dirname, '..', '..', 'logs');
const STORAGE_VIDEO_PATH_RE = /^users\/([^/]+)\/videos\/([^/]+)\/(.+)$/;
const TRASH_STATES = new Set(['trash', 'tombstone', 'deleted']);
const PENDING_UPLOAD_STATUSES = new Set([
  'queued',
  'pending',
  'uploading',
  'retrying',
  'restoring',
  'restore_pending',
  'copying',
  'copy_pending',
]);

function printHelp() {
  console.log(`Cloud Clip Storage delete dry-run inventory

Usage:
  node functions/scripts/cloud_clip_delete_dry_run_inventory.js [options]

Options:
  --retention-days <days>       Retention window. Default: ${DEFAULT_RETENTION_DAYS}
  --cutoff <ISO datetime>       Explicit retention cutoff. Overrides --retention-days
  --bucket <name>               Firebase Storage bucket name. Defaults to admin SDK bucket
  --prefix <path>               Storage prefix to scan. Default: ${DEFAULT_STORAGE_PREFIX}
  --limit <count>               Maximum Storage objects to inspect
  --out-dir <path>              Manifest output directory. Default: logs
  --fixture <path>              Read fixture JSON instead of Firebase for local safety validation
  --include-orphans             Put metadata-missing objects into needsReview with orphan reason
  --help                        Show this help

This tool is dry-run only. It does not delete Storage objects, mutate Firestore, or decrement usage.`);
}

function parseArgs(argv) {
  const options = {
    retentionDays: DEFAULT_RETENTION_DAYS,
    cutoff: null,
    bucket: null,
    prefix: DEFAULT_STORAGE_PREFIX,
    limit: null,
    outDir: DEFAULT_LOGS_DIR,
    fixture: null,
    includeOrphans: false,
    help: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = () => {
      i += 1;
      if (i >= argv.length) {
        throw new Error(`Missing value for ${arg}`);
      }
      return argv[i];
    };

    switch (arg) {
      case '--retention-days':
        options.retentionDays = parsePositiveInteger(next(), '--retention-days');
        break;
      case '--cutoff':
        options.cutoff = parseDate(next(), '--cutoff');
        break;
      case '--bucket':
        options.bucket = next();
        break;
      case '--prefix':
        options.prefix = next();
        break;
      case '--limit':
        options.limit = parsePositiveInteger(next(), '--limit');
        break;
      case '--out-dir':
        options.outDir = path.resolve(process.cwd(), next());
        break;
      case '--fixture':
        options.fixture = path.resolve(process.cwd(), next());
        break;
      case '--include-orphans':
        options.includeOrphans = true;
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

function parseDate(raw, name) {
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`${name} must be an ISO datetime`);
  }
  return date;
}

function sha256(value) {
  return crypto.createHash('sha256').update(String(value || '')).digest('hex');
}

function shortHash(value) {
  return sha256(value).slice(0, 24);
}

function toIsoOrNull(value) {
  const date = parseTimestamp(value);
  return date ? date.toISOString() : null;
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

function normalizeString(value) {
  return value === undefined || value === null ? '' : String(value).trim();
}

function normalizeState(value) {
  return normalizeString(value).toLowerCase();
}

function normalizeNumber(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return Math.trunc(value);
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.trunc(parsed) : 0;
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

function hasTrashState(data) {
  return data.deleted === true ||
    data.trashed === true ||
    TRASH_STATES.has(normalizeState(data.lifecycleState)) ||
    TRASH_STATES.has(normalizeState(data.cloudState));
}

function getLifecycleTimestamp(data) {
  return parseTimestamp(data.trashedAt) ||
    parseTimestamp(data.deletedAt) ||
    parseTimestamp(data.tombstonedAt) ||
    parseTimestamp(data.updatedAt);
}

function isPendingState(data) {
  const uploadStatus = normalizeState(data.uploadStatus);
  const cloudState = normalizeState(data.cloudState);
  const lifecycleState = normalizeState(data.lifecycleState);
  return PENDING_UPLOAD_STATUSES.has(uploadStatus) ||
    PENDING_UPLOAD_STATUSES.has(cloudState) ||
    PENDING_UPLOAD_STATUSES.has(lifecycleState) ||
    data.restorePending === true ||
    data.copyPending === true ||
    data.uploadPending === true;
}

async function loadFirebaseInventory(options) {
  if (admin.apps.length === 0) {
    admin.initializeApp(options.bucket ? { storageBucket: options.bucket } : undefined);
  }

  const bucket = options.bucket
    ? admin.storage().bucket(options.bucket)
    : admin.storage().bucket();
  const firestore = admin.firestore();

  const [files] = await bucket.getFiles({
    prefix: options.prefix,
    autoPaginate: true,
    ...(options.limit ? { maxResults: options.limit } : {}),
  });

  const objects = files
    .filter((file) => !file.name.endsWith('/'))
    .map((file) => ({
      name: file.name,
      size: normalizeNumber(file.metadata?.size),
      contentType: file.metadata?.contentType || null,
      updated: file.metadata?.updated || null,
      generation: file.metadata?.generation || null,
    }));

  const snapshot = await firestore.collection('videos').get();
  const videos = snapshot.docs.map((doc) => ({
    id: doc.id,
    data: doc.data(),
  }));

  return { objects, videos };
}

function loadFixtureInventory(fixturePath) {
  const raw = fs.readFileSync(fixturePath, 'utf8');
  const parsed = JSON.parse(raw);
  return {
    objects: Array.isArray(parsed.objects) ? parsed.objects : [],
    videos: Array.isArray(parsed.videos) ? parsed.videos : [],
  };
}

function buildVideoIndexes(videos) {
  const byStoragePath = new Map();
  const duplicateStoragePaths = new Set();

  for (const video of videos) {
    const data = video.data || {};
    const storagePath = normalizeString(data.storagePath);
    if (!storagePath) continue;
    if (byStoragePath.has(storagePath)) {
      duplicateStoragePaths.add(storagePath);
      continue;
    }
    byStoragePath.set(storagePath, video);
  }

  return { byStoragePath, duplicateStoragePaths };
}

function redactObject(object, parsedPath, reasonCode, details = {}) {
  return {
    reasonCode,
    uidHash: parsedPath ? shortHash(parsedPath.uid) : null,
    videoIdHash: parsedPath ? shortHash(parsedPath.videoId) : null,
    storagePathHash: shortHash(object.name),
    fileNameHash: parsedPath ? shortHash(parsedPath.fileName) : null,
    storagePathShape: parsedPath ? 'users/{uid}/videos/{videoId}/{fileName}' : 'invalid_or_unsupported',
    objectSizeBytes: normalizeNumber(object.size),
    objectUpdatedAt: toIsoOrNull(object.updated),
    generationHash: object.generation ? shortHash(object.generation) : null,
    ...details,
  };
}

function redactCandidate(object, parsedPath, video, expectedUsageDeltaBytes, lifecycleAt, reasonCode) {
  const data = video.data || {};
  return {
    reasonCode,
    uidHash: shortHash(parsedPath.uid),
    videoIdHash: shortHash(parsedPath.videoId),
    storagePathHash: shortHash(object.name),
    fileNameHash: shortHash(parsedPath.fileName),
    storagePathShape: 'users/{uid}/videos/{videoId}/{fileName}',
    firestoreDocumentIdHash: shortHash(video.id),
    objectSizeBytes: normalizeNumber(object.size),
    metadataFileSizeBytes: normalizeNumber(data.fileSize),
    expectedUsageDeltaBytes,
    uploadStatus: normalizeState(data.uploadStatus) || null,
    lifecycleState: normalizeState(data.lifecycleState) || null,
    cloudState: normalizeState(data.cloudState) || null,
    trashed: data.trashed === true,
    lifecycleMarkedAt: lifecycleAt.toISOString(),
    objectUpdatedAt: toIsoOrNull(object.updated),
    generationHash: object.generation ? shortHash(object.generation) : null,
  };
}

function classifyObject(object, indexes, cutoff, options) {
  const parsedPath = parseStorageVideoPath(object.name);
  if (!parsedPath) {
    return {
      bucket: 'excluded',
      item: redactObject(object, null, 'invalid_prefix_excluded'),
    };
  }

  const video = indexes.byStoragePath.get(object.name);
  if (!video) {
    const item = redactObject(object, parsedPath, 'orphan_storage_object_metadata_missing', {
      reviewRequired: true,
      expectedUsageDeltaBytes: 0,
    });
    return {
      bucket: options.includeOrphans ? 'needsReview' : 'excluded',
      item,
    };
  }

  if (indexes.duplicateStoragePaths.has(object.name)) {
    return {
      bucket: 'needsReview',
      item: redactObject(object, parsedPath, 'duplicate_metadata_storage_path_needs_review', {
        firestoreDocumentIdHash: shortHash(video.id),
        expectedUsageDeltaBytes: 0,
      }),
    };
  }

  const data = video.data || {};
  const metadataUid = normalizeString(data.uid);
  const metadataVideoId = normalizeString(data.videoId || video.id);
  const metadataStoragePath = normalizeString(data.storagePath);
  const expectedPrefix = `users/${metadataUid}/videos/${metadataVideoId}/`;

  if (!metadataUid || !metadataVideoId || !metadataStoragePath) {
    return {
      bucket: 'needsReview',
      item: redactObject(object, parsedPath, 'metadata_required_field_missing_needs_review', {
        firestoreDocumentIdHash: shortHash(video.id),
        hasUid: Boolean(metadataUid),
        hasVideoId: Boolean(metadataVideoId),
        hasStoragePath: Boolean(metadataStoragePath),
        expectedUsageDeltaBytes: 0,
      }),
    };
  }

  if (parsedPath.uid !== metadataUid || parsedPath.videoId !== metadataVideoId || metadataStoragePath !== object.name || !object.name.startsWith(expectedPrefix)) {
    return {
      bucket: 'needsReview',
      item: redactObject(object, parsedPath, 'metadata_storage_path_mismatch', {
        firestoreDocumentIdHash: shortHash(video.id),
        uidMatches: parsedPath.uid === metadataUid,
        videoIdMatches: parsedPath.videoId === metadataVideoId,
        storagePathMatches: metadataStoragePath === object.name,
        prefixMatches: object.name.startsWith(expectedPrefix),
        expectedUsageDeltaBytes: 0,
      }),
    };
  }

  if (isPendingState(data)) {
    return {
      bucket: 'excluded',
      item: redactObject(object, parsedPath, 'active_or_pending_upload_excluded', {
        firestoreDocumentIdHash: shortHash(video.id),
        uploadStatus: normalizeState(data.uploadStatus) || null,
        lifecycleState: normalizeState(data.lifecycleState) || null,
        cloudState: normalizeState(data.cloudState) || null,
        expectedUsageDeltaBytes: 0,
      }),
    };
  }

  if (!hasTrashState(data)) {
    return {
      bucket: 'excluded',
      item: redactObject(object, parsedPath, 'active_metadata_excluded', {
        firestoreDocumentIdHash: shortHash(video.id),
        uploadStatus: normalizeState(data.uploadStatus) || null,
        lifecycleState: normalizeState(data.lifecycleState) || null,
        cloudState: normalizeState(data.cloudState) || null,
        expectedUsageDeltaBytes: 0,
      }),
    };
  }

  const lifecycleAt = getLifecycleTimestamp(data);
  if (!lifecycleAt) {
    return {
      bucket: 'needsReview',
      item: redactObject(object, parsedPath, 'trash_timestamp_missing_needs_review', {
        firestoreDocumentIdHash: shortHash(video.id),
        expectedUsageDeltaBytes: 0,
      }),
    };
  }

  if (lifecycleAt > cutoff) {
    return {
      bucket: 'excluded',
      item: redactObject(object, parsedPath, 'trash_retention_not_elapsed_excluded', {
        firestoreDocumentIdHash: shortHash(video.id),
        lifecycleMarkedAt: lifecycleAt.toISOString(),
        expectedUsageDeltaBytes: 0,
      }),
    };
  }

  const objectSize = normalizeNumber(object.size);
  const metadataFileSize = normalizeNumber(data.fileSize);
  if (objectSize <= 0 || metadataFileSize <= 0) {
    return {
      bucket: 'needsReview',
      item: redactObject(object, parsedPath, 'file_size_missing_needs_review', {
        firestoreDocumentIdHash: shortHash(video.id),
        objectSizeBytes: objectSize,
        metadataFileSizeBytes: metadataFileSize,
        expectedUsageDeltaBytes: 0,
      }),
    };
  }

  if (objectSize !== metadataFileSize) {
    return {
      bucket: 'needsReview',
      item: redactObject(object, parsedPath, 'file_size_mismatch_needs_review', {
        firestoreDocumentIdHash: shortHash(video.id),
        objectSizeBytes: objectSize,
        metadataFileSizeBytes: metadataFileSize,
        expectedUsageDeltaBytes: 0,
      }),
    };
  }

  return {
    bucket: 'candidates',
    item: redactCandidate(
      object,
      parsedPath,
      video,
      -metadataFileSize,
      lifecycleAt,
      'trash_retention_elapsed_with_metadata',
    ),
  };
}

function increment(map, key) {
  map[key] = (map[key] || 0) + 1;
}

function summarizeReasonCodes(items) {
  const summary = {};
  for (const item of items) {
    increment(summary, item.reasonCode || 'unknown');
  }
  return summary;
}

function buildManifest(inventory, options, startedAt, cutoff) {
  const indexes = buildVideoIndexes(inventory.videos);
  const candidates = [];
  const excluded = [];
  const needsReview = [];

  for (const object of inventory.objects) {
    const classified = classifyObject(object, indexes, cutoff, options);
    if (classified.bucket === 'candidates') candidates.push(classified.item);
    if (classified.bucket === 'excluded') excluded.push(classified.item);
    if (classified.bucket === 'needsReview') needsReview.push(classified.item);
  }

  const expectedUsageDecrementBytes = candidates.reduce(
    (sum, item) => sum + Math.abs(normalizeNumber(item.expectedUsageDeltaBytes)),
    0,
  );
  const candidateObjectSizeBytes = candidates.reduce(
    (sum, item) => sum + normalizeNumber(item.objectSizeBytes),
    0,
  );
  const uidHashSet = new Set(candidates.map((item) => item.uidHash).filter(Boolean));

  return {
    manifestId: `cloud_clip_delete_dry_run_${startedAt.toISOString().replace(/[:.]/g, '-')}_${crypto.randomUUID().slice(0, 8)}`,
    generatedAt: new Date().toISOString(),
    dryRun: true,
    queryVersion: QUERY_VERSION,
    environment: {
      nodeVersion: process.version,
      platform: process.platform,
      fixtureMode: Boolean(options.fixture),
      storageBucket: options.bucket || null,
      storagePrefix: options.prefix,
    },
    policy: {
      retentionDays: options.retentionDays,
      retentionCutoff: cutoff.toISOString(),
      mutationProhibited: true,
      deleteObjectCalls: 0,
      firestoreWrites: 0,
      usageAccountingWrites: 0,
    },
    approval: {
      requiredBeforeExecute: true,
      approvedBy: null,
      approvedAt: null,
      approvedScope: null,
    },
    summary: {
      scannedObjectCount: inventory.objects.length,
      scannedVideoMetadataCount: inventory.videos.length,
      candidateCount: candidates.length,
      candidateObjectSizeBytes,
      expectedUsageDecrementBytes,
      needsReviewCount: needsReview.length,
      excludedCount: excluded.length,
      uniqueCandidateUidHashCount: uidHashSet.size,
      candidatesByReasonCode: summarizeReasonCodes(candidates),
      needsReviewByReasonCode: summarizeReasonCodes(needsReview),
      excludedByReasonCode: summarizeReasonCodes(excluded),
    },
    candidates,
    needsReview,
    excluded,
  };
}

function writeManifest(manifest, outDir) {
  fs.mkdirSync(outDir, { recursive: true });
  const fileName = `${manifest.manifestId}.json`;
  const filePath = path.join(outDir, fileName);
  fs.writeFileSync(filePath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
  return filePath;
}

async function main() {
  const startedAt = new Date();
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    printHelp();
    return;
  }

  const cutoff = options.cutoff || new Date(startedAt.getTime() - options.retentionDays * 24 * 60 * 60 * 1000);
  const inventory = options.fixture
    ? loadFixtureInventory(options.fixture)
    : await loadFirebaseInventory(options);
  const manifest = buildManifest(inventory, options, startedAt, cutoff);
  const manifestPath = writeManifest(manifest, options.outDir);

  console.log(JSON.stringify({
    success: true,
    dryRun: true,
    manifestPath,
    candidateCount: manifest.summary.candidateCount,
    expectedUsageDecrementBytes: manifest.summary.expectedUsageDecrementBytes,
    needsReviewCount: manifest.summary.needsReviewCount,
    excludedCount: manifest.summary.excludedCount,
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
