const crypto = require('crypto');

const STANDARD_CLOUD_LIMIT_BYTES = 50 * 1024 * 1024 * 1024;
const MONTHLY_DOWNLOAD_SOFT_LIMIT_BYTES = 50 * 1024 * 1024 * 1024;
const MONTHLY_DOWNLOAD_HARD_LIMIT_BYTES = 100 * 1024 * 1024 * 1024;
const STANDARD_VIDEO_OBJECT_LIMIT_BYTES = 50 * 1024 * 1024;
const MAX_VIDEO_OBJECT_BYTES = 500 * 1024 * 1024;
const RESERVATION_TTL_MS = 30 * 60 * 1000;
const VIDEO_CONTENT_TYPE = 'video/mp4';
const VIDEOS_COLLECTION = 'videos';
const USERS_COLLECTION = 'users';
const USAGE_EVENTS_COLLECTION = 'usageEvents';
const METADATA_VERSION = 1;

function createCloudUploadReservationFunctions({
  functions,
  admin,
  region,
  serviceAccount,
}) {
  const runtime = functions.region(region).runWith({ serviceAccount });

  return {
    prepareCloudUpload: runtime.https.onCall(async (data, context) =>
      prepareCloudUpload({ data, context, functions, admin }),
    ),
    commitCloudUpload: runtime.https.onCall(async (data, context) =>
      commitCloudUpload({ data, context, functions, admin }),
    ),
    cancelCloudUpload: runtime.https.onCall(async (data, context) =>
      cancelCloudUpload({ data, context, functions, admin }),
    ),
    recordCloudDownload: runtime.https.onCall(async (data, context) =>
      recordCloudDownload({ data, context, functions, admin }),
    ),
  };
}

async function prepareCloudUpload({ data, context, functions, admin }) {
  const uid = requireAuth(context, functions);
  const payload = normalizePayload(data);
  const requestId = requireSafeId(payload.requestId, 'requestId', functions);
  const requestedVideoId = optionalSafeId(payload.videoId);
  const fileSize = requirePositiveInt(payload.fileSize, 'fileSize', functions);
  const contentType = sanitizeString(payload.contentType).toLowerCase();
  const fileName = sanitizeStorageFileName(payload.fileName);
  const albumName = sanitizeString(payload.albumName) || 'Cloud';
  const source = sanitizeString(payload.source) || 'library_upload';
  const isFavorite = payload.isFavorite === true;
  const clientMetadata = sanitizeClientMetadata(payload.metadata);

  if (contentType !== VIDEO_CONTENT_TYPE) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Standard Cloud uploads must use normalized MP4 video.',
    );
  }

  if (fileSize > MAX_VIDEO_OBJECT_BYTES) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Video object exceeds the per-object upload limit.',
    );
  }

  if (!canUploadStandardVideoObjectBytes(fileSize)) {
    throw new functions.https.HttpsError(
      'resource-exhausted',
      'Standard Cloud video object exceeds the Standard per-object limit.',
    );
  }

  if (!isStandardVideoMetadata(clientMetadata)) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Cloud upload preflight metadata is missing or not Standard-compatible.',
    );
  }

  const db = admin.firestore();
  await releaseExpiredReservationsForUser({ db, admin, uid });
  let recycledVideoRef = null;

  const existing = await db
    .collection(VIDEOS_COLLECTION)
    .where('uid', '==', uid)
    .where('uploadRequestId', '==', requestId)
    .limit(1)
    .get();

  if (!existing.empty) {
    const doc = existing.docs[0];
    const current = doc.data() || {};
    const status = sanitizeString(current.uploadStatus).toLowerCase();
    if (status === 'completed') {
      return {
        videoId: doc.id,
        storagePath: current.storagePath || null,
        thumbnailStoragePath: current.thumbnailStoragePath || buildThumbnailPath(uid, doc.id),
        reservationId: current.uploadReservationId || requestId,
        reservationExpiresAt: timestampToMillis(current.reservationExpiresAt),
        uploadStatus: 'completed',
        reused: true,
      };
    }

    if (isReservationExpired(current.reservationExpiresAt, Date.now())) {
      await expireReservation({
        db,
        admin,
        uid,
        videoRef: doc.ref,
        videoData: current,
        reason: 'prepare_existing_expired',
      });
      recycledVideoRef = doc.ref;
    } else if (isReusableUploadMetadata(current)) {
      recycledVideoRef = doc.ref;
    } else {
      return {
        videoId: doc.id,
        storagePath: current.storagePath || null,
        thumbnailStoragePath: current.thumbnailStoragePath || buildThumbnailPath(uid, doc.id),
        reservationId: current.uploadReservationId || requestId,
        reservationExpiresAt: timestampToMillis(current.reservationExpiresAt),
        uploadStatus: status || 'reserved',
        reused: true,
      };
    }
  }

  const videoRef = recycledVideoRef || (requestedVideoId
    ? db.collection(VIDEOS_COLLECTION).doc(requestedVideoId)
    : db.collection(VIDEOS_COLLECTION).doc());
  const videoId = videoRef.id;
  const storagePath = buildVideoPath(uid, videoId, fileName);
  const thumbnailStoragePath = buildThumbnailPath(uid, videoId);
  const reservationId = requestId;
  const now = admin.firestore.Timestamp.now();
  const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + RESERVATION_TTL_MS);
  const userRef = db.collection(USERS_COLLECTION).doc(uid);
  const reserveEventRef = userRef
    .collection(USAGE_EVENTS_COLLECTION)
    .doc(`upload_reserve_${videoId}`);

  await db.runTransaction(async (tx) => {
    const [userSnap, videoSnap, reserveEventSnap] = await Promise.all([
      tx.get(userRef),
      tx.get(videoRef),
      tx.get(reserveEventRef),
    ]);

    if (videoSnap.exists) {
      const existingData = videoSnap.data() || {};
      const canReuse = existingData.uid === uid && isReusableUploadMetadata(existingData);
      const sameActiveRequest =
        existingData.uid === uid &&
        sanitizeString(existingData.uploadRequestId) === requestId &&
        !canReuse;
      if (sameActiveRequest) {
        return;
      }
      if (!canReuse) {
        throw new functions.https.HttpsError(
          'already-exists',
          'Requested video id is already used by another upload.',
        );
      }
    }

    const userData = userSnap.exists ? userSnap.data() || {} : {};
    if (!isPaidUploadEntitled(userData, Date.now())) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Active Standard subscription is required to upload Cloud clips.',
      );
    }

    const usedBytes = nonNegativeInt(
      userData.cloudUsedBytes !== undefined ? userData.cloudUsedBytes : userData.storageUsage,
    );
    const reservedBytes = nonNegativeInt(userData.cloudReservedUploadBytes);
    if (!canReserveUploadBytes(usedBytes, reservedBytes, fileSize, STANDARD_CLOUD_LIMIT_BYTES)) {
      throw new functions.https.HttpsError(
        'resource-exhausted',
        'Cloud storage quota exceeded.',
      );
    }

    const nextReserved = reservedBytes + fileSize;
    tx.set(userRef, {
      cloudLimitBytes: STANDARD_CLOUD_LIMIT_BYTES,
      cloudUsedBytes: usedBytes,
      storageUsage: usedBytes,
      cloudReservedUploadBytes: nextReserved,
      cloudUsageUpdatedAt: now,
      cloudUsageVersion: METADATA_VERSION,
      lastUpdated: now,
    }, { merge: true });

    tx.set(videoRef, {
      uid,
      videoId,
      fileName,
      storagePath,
      albumName,
      isFavorite,
      fileSize,
      uploadStatus: 'reserved',
      uploadProgress: 0,
      thumbnailStatus: 'pending',
      thumbnailStoragePath,
      assetType: 'standard_video',
      cloudState: 'reserved',
      storageTier: 'cloud',
      uploadRequestId: requestId,
      uploadReservationId: reservationId,
      reservationExpiresAt: expiresAt,
      reservedFileSize: fileSize,
      contentType,
      source,
      ...clientMetadata,
      createdAt: now,
      updatedAt: now,
    });

    if (!reserveEventSnap.exists) {
      tx.set(reserveEventRef, {
        uid,
        videoId,
        eventType: 'upload_reserve',
        source,
        bytes: fileSize,
        storageDelta: 0,
        uploadDelta: fileSize,
        requestId,
        periodKey: periodKeyForDate(new Date()),
        status: 'reserved',
        createdAt: now,
        metadataVersion: METADATA_VERSION,
      });
    }
  });

  return {
    videoId,
    storagePath,
    thumbnailStoragePath,
    reservationId,
    reservationExpiresAt: expiresAt.toMillis(),
    uploadStatus: 'reserved',
    reused: false,
  };
}

async function commitCloudUpload({ data, context, functions, admin }) {
  const uid = requireAuth(context, functions);
  const payload = normalizePayload(data);
  const videoId = requireSafeId(payload.videoId, 'videoId', functions);
  const requestId = requireSafeId(payload.requestId, 'requestId', functions);
  const downloadUrl = sanitizeString(payload.downloadUrl);
  const thumbnailStoragePath = sanitizeString(payload.thumbnailStoragePath);
  const thumbnailWidth = optionalNonNegativeInt(payload.thumbnailWidth);
  const thumbnailHeight = optionalNonNegativeInt(payload.thumbnailHeight);
  const durationMs = optionalNonNegativeInt(payload.durationMs);
  const clientMetadata = sanitizeClientMetadata(payload.metadata);

  const db = admin.firestore();
  const bucket = admin.storage().bucket();
  const videoRef = db.collection(VIDEOS_COLLECTION).doc(videoId);
  const videoSnap = await videoRef.get();
  if (!videoSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Upload reservation not found.');
  }

  const videoData = videoSnap.data() || {};
  assertOwnerAndRequest({ videoData, uid, requestId, functions });

  if (sanitizeString(videoData.uploadStatus).toLowerCase() === 'completed') {
    return {
      videoId,
      status: 'completed',
      alreadyCommitted: true,
      storageUsageCommitted: false,
    };
  }

  if (isReservationExpired(videoData.reservationExpiresAt, Date.now())) {
    await expireReservation({
      db,
      admin,
      uid,
      videoRef,
      videoData,
      reason: 'commit_expired',
    });
    throw new functions.https.HttpsError(
      'deadline-exceeded',
      'Upload reservation has expired.',
    );
  }

  const storagePath = sanitizeString(videoData.storagePath);
  if (!storagePath.startsWith(`users/${uid}/videos/${videoId}/`)) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Reserved storage path is invalid.',
    );
  }

  const [exists] = await bucket.file(storagePath).exists();
  if (!exists) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Uploaded storage object was not found.',
    );
  }

  const [objectMetadata] = await bucket.file(storagePath).getMetadata();
  const objectSize = nonNegativeInt(objectMetadata.size);
  const objectContentType = sanitizeString(objectMetadata.contentType).toLowerCase();
  const reservedFileSize = nonNegativeInt(videoData.reservedFileSize || videoData.fileSize);
  if (objectSize !== reservedFileSize) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Uploaded storage object size does not match the reservation.',
    );
  }
  if (objectContentType !== VIDEO_CONTENT_TYPE) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Uploaded storage object content type is invalid.',
    );
  }

  if (!thumbnailStoragePath.startsWith(`users/${uid}/videos/${videoId}/thumbnails/`)) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Thumbnail storage path is invalid.',
    );
  }

  const [thumbnailExists] = await bucket.file(thumbnailStoragePath).exists();
  if (!thumbnailExists) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Thumbnail storage object was not found.',
    );
  }

  const now = admin.firestore.Timestamp.now();
  const userRef = db.collection(USERS_COLLECTION).doc(uid);
  const commitEventRef = userRef
    .collection(USAGE_EVENTS_COLLECTION)
    .doc(`upload_commit_${videoId}`);

  let storageUsageCommitted = false;
  await db.runTransaction(async (tx) => {
    const [userSnap, latestVideoSnap, commitEventSnap] = await Promise.all([
      tx.get(userRef),
      tx.get(videoRef),
      tx.get(commitEventRef),
    ]);
    const latestVideoData = latestVideoSnap.data() || {};
    assertOwnerAndRequest({ videoData: latestVideoData, uid, requestId, functions });

    if (sanitizeString(latestVideoData.uploadStatus).toLowerCase() === 'completed') {
      return;
    }

    if (isReservationExpired(latestVideoData.reservationExpiresAt, Date.now())) {
      throw new functions.https.HttpsError(
        'deadline-exceeded',
        'Upload reservation has expired.',
      );
    }

    const userData = userSnap.exists ? userSnap.data() || {} : {};
    const usedBytes = nonNegativeInt(
      userData.cloudUsedBytes !== undefined ? userData.cloudUsedBytes : userData.storageUsage,
    );
    const reservedBytes = nonNegativeInt(userData.cloudReservedUploadBytes);
    const nextReserved = Math.max(0, reservedBytes - reservedFileSize);
    const nextUsed = commitEventSnap.exists ? usedBytes : usedBytes + reservedFileSize;

    if (nextUsed > STANDARD_CLOUD_LIMIT_BYTES) {
      throw new functions.https.HttpsError(
        'resource-exhausted',
        'Cloud storage quota exceeded at commit.',
      );
    }

    tx.set(userRef, {
      cloudLimitBytes: STANDARD_CLOUD_LIMIT_BYTES,
      cloudUsedBytes: nextUsed,
      storageUsage: nextUsed,
      cloudReservedUploadBytes: nextReserved,
      monthlyUploadBytes:
        nonNegativeInt(userData.monthlyUploadBytes) +
        (commitEventSnap.exists ? 0 : reservedFileSize),
      cloudUsageUpdatedAt: now,
      cloudUsageVersion: METADATA_VERSION,
      lastUpdated: now,
    }, { merge: true });

    tx.set(videoRef, {
      uploadStatus: 'completed',
      uploadProgress: 100,
      cloudState: 'active',
      fileSize: reservedFileSize,
      contentType: objectContentType,
      storageVerifiedAt: now,
      downloadUrl: downloadUrl || null,
      thumbnailStatus: 'completed',
      thumbnailStoragePath,
      ...(thumbnailWidth === null ? {} : { thumbnailWidth }),
      ...(thumbnailHeight === null ? {} : { thumbnailHeight }),
      ...(durationMs === null ? {} : { durationMs }),
      ...clientMetadata,
      completedAt: now,
      updatedAt: now,
      usageCommitEventId: commitEventRef.id,
      reservationReleased: true,
      reservationReleasedAt: now,
    }, { merge: true });

    if (!commitEventSnap.exists) {
      tx.set(commitEventRef, {
        uid,
        videoId,
        eventType: 'upload_commit',
        source: sanitizeString(latestVideoData.source) || 'library_upload',
        bytes: reservedFileSize,
        storageDelta: reservedFileSize,
        uploadDelta: reservedFileSize,
        requestId,
        periodKey: periodKeyForDate(new Date()),
        status: 'committed',
        createdAt: now,
        committedAt: now,
        metadataVersion: METADATA_VERSION,
      });
      storageUsageCommitted = true;
    }
  });

  return {
    videoId,
    status: 'completed',
    alreadyCommitted: false,
    storageUsageCommitted,
  };
}

async function cancelCloudUpload({ data, context, functions, admin }) {
  const uid = requireAuth(context, functions);
  const payload = normalizePayload(data);
  const videoId = requireSafeId(payload.videoId, 'videoId', functions);
  const requestId = requireSafeId(payload.requestId, 'requestId', functions);
  const reason = sanitizeString(payload.reason) || 'client_cancelled';
  const db = admin.firestore();
  const videoRef = db.collection(VIDEOS_COLLECTION).doc(videoId);
  const videoSnap = await videoRef.get();

  if (!videoSnap.exists) {
    return { videoId, status: 'not_found', releasedBytes: 0 };
  }

  const videoData = videoSnap.data() || {};
  assertOwnerAndRequest({ videoData, uid, requestId, functions });

  const status = sanitizeString(videoData.uploadStatus).toLowerCase();
  if (status === 'completed') {
    return { videoId, status: 'completed', releasedBytes: 0 };
  }

  const releasedBytes = await releaseReservation({
    db,
    admin,
    uid,
    videoRef,
    videoData,
    status: 'cancelled',
    reason,
    eventType: 'upload_cancel',
  });

  return { videoId, status: 'cancelled', releasedBytes };
}

async function recordCloudDownload({ data, context, functions, admin }) {
  const uid = requireAuth(context, functions);
  const payload = normalizePayload(data);
  const videoId = requireSafeId(payload.videoId, 'videoId', functions);
  const source = sanitizeUsageSource(payload.source) || 'cloud_backup_restore';
  const requestedBytes = optionalNonNegativeInt(payload.bytes);
  const cacheHit = payload.cacheHit === true;
  const cacheMissId = sanitizeString(payload.cacheMissId) || `${Date.now()}`;
  const hardLimitEnabled =
    payload.enforceHardLimit === true ||
    parseBooleanEnv('MOA_ENFORCE_DOWNLOAD_HARD_LIMIT', false);

  const db = admin.firestore();
  const videoRef = db.collection(VIDEOS_COLLECTION).doc(videoId);
  const userRef = db.collection(USERS_COLLECTION).doc(uid);
  const nowDate = new Date();
  const eventId = buildDownloadEventId({
    videoId,
    source,
    cacheMissId,
    date: nowDate,
  });
  const eventRef = userRef.collection(USAGE_EVENTS_COLLECTION).doc(eventId);

  let response = null;
  await db.runTransaction(async (tx) => {
    const [videoSnap, userSnap, eventSnap] = await Promise.all([
      tx.get(videoRef),
      tx.get(userRef),
      tx.get(eventRef),
    ]);

    if (!videoSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Cloud video not found.');
    }

    const videoData = videoSnap.data() || {};
    if (videoData.uid !== uid) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Cloud video owner mismatch.',
      );
    }

    const fileSize = nonNegativeInt(videoData.fileSize);
    const bytes = cacheHit ? 0 : (requestedBytes === null ? fileSize : requestedBytes);
    if (!cacheHit && bytes <= 0) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Download bytes must be a positive integer for cache misses.',
      );
    }

    const now = admin.firestore.Timestamp.fromDate(nowDate);
    const mutation = buildDownloadUsageMutation({
      uid,
      videoId,
      source,
      bytes,
      cacheHit,
      hardLimitEnabled,
      userData: userSnap.exists ? userSnap.data() || {} : {},
      videoData,
      now,
      nowDate,
      requestId: cacheMissId,
      eventId,
    });

    if (mutation.hardBlocked) {
      throw new functions.https.HttpsError(
        'resource-exhausted',
        'Monthly Cloud download limit exceeded.',
        {
          monthlyDownloadBytes: mutation.monthlyDownloadBytes,
          hardLimitBytes: MONTHLY_DOWNLOAD_HARD_LIMIT_BYTES,
          hardLimitEnforced: true,
        },
      );
    }

    if (eventSnap.exists) {
      response = {
        videoId,
        eventId,
        recorded: false,
        duplicate: true,
        cacheHit,
        bytesRecorded: 0,
        monthlyDownloadBytes: mutation.currentMonthlyDownloadBytes,
        softLimitExceeded: mutation.currentMonthlyDownloadBytes >= MONTHLY_DOWNLOAD_SOFT_LIMIT_BYTES,
        hardLimitEnforced: hardLimitEnabled,
        hardLimitExceeded: mutation.currentMonthlyDownloadBytes >= MONTHLY_DOWNLOAD_HARD_LIMIT_BYTES,
      };
      return;
    }

    tx.set(userRef, mutation.userMerge, { merge: true });
    tx.set(videoRef, mutation.videoMerge, { merge: true });
    tx.set(eventRef, mutation.eventData);
    response = mutation.response;
  });

  return response;
}

async function releaseExpiredReservationsForUser({ db, admin, uid, limit = 20 }) {
  const nowMs = Date.now();
  const candidates = await db
    .collection(VIDEOS_COLLECTION)
    .where('uid', '==', uid)
    .limit(Math.max(limit * 4, 40))
    .get();

  const expired = candidates.docs
    .filter((doc) => {
      const data = doc.data() || {};
      const status = sanitizeString(data.uploadStatus).toLowerCase();
      return (
        ['reserved', 'uploading'].includes(status) &&
        isReservationExpired(data.reservationExpiresAt, nowMs)
      );
    })
    .slice(0, limit);

  for (const doc of expired) {
    await expireReservation({
      db,
      admin,
      uid,
      videoRef: doc.ref,
      videoData: doc.data() || {},
      reason: 'opportunistic_prepare_cleanup',
    });
  }
}

async function expireReservation({ db, admin, uid, videoRef, videoData, reason }) {
  return releaseReservation({
    db,
    admin,
    uid,
    videoRef,
    videoData,
    status: 'expired',
    reason,
    eventType: 'upload_cancel',
  });
}

async function releaseReservation({
  db,
  admin,
  uid,
  videoRef,
  videoData,
  status,
  reason,
  eventType,
}) {
  const videoId = videoRef.id;
  const reservedFileSize = nonNegativeInt(videoData.reservedFileSize || videoData.fileSize);
  const requestId = sanitizeString(videoData.uploadRequestId);
  const userRef = db.collection(USERS_COLLECTION).doc(uid);
  const eventRef = userRef
    .collection(USAGE_EVENTS_COLLECTION)
    .doc(`${eventType}_${videoId}_${status}`);
  const now = admin.firestore.Timestamp.now();
  let releasedBytes = 0;

  await db.runTransaction(async (tx) => {
    const [userSnap, latestVideoSnap, eventSnap] = await Promise.all([
      tx.get(userRef),
      tx.get(videoRef),
      tx.get(eventRef),
    ]);
    const latestVideoData = latestVideoSnap.data() || {};
    const latestStatus = sanitizeString(latestVideoData.uploadStatus).toLowerCase();
    if (latestStatus === 'completed' || latestVideoData.reservationReleased === true) {
      return;
    }

    const userData = userSnap.exists ? userSnap.data() || {} : {};
    const reservedBytes = nonNegativeInt(userData.cloudReservedUploadBytes);
    const nextReserved = Math.max(0, reservedBytes - reservedFileSize);
    releasedBytes = reservedBytes - nextReserved;

    tx.set(userRef, {
      cloudReservedUploadBytes: nextReserved,
      cloudUsageUpdatedAt: now,
      cloudUsageVersion: METADATA_VERSION,
      lastUpdated: now,
    }, { merge: true });

    tx.set(videoRef, {
      uploadStatus: status,
      cloudState: status,
      errorCode: status === 'expired' ? 'reservation_expired' : 'upload_cancelled',
      errorPhase: reason,
      reservationReleased: true,
      reservationReleasedAt: now,
      updatedAt: now,
    }, { merge: true });

    if (!eventSnap.exists) {
      tx.set(eventRef, {
        uid,
        videoId,
        eventType,
        source: sanitizeString(latestVideoData.source) || 'library_upload',
        bytes: reservedFileSize,
        storageDelta: 0,
        uploadDelta: 0,
        requestId,
        periodKey: periodKeyForDate(new Date()),
        status,
        reason,
        createdAt: now,
        metadataVersion: METADATA_VERSION,
      });
    }
  });

  return releasedBytes;
}

function requireAuth(context, functions) {
  const uid = sanitizeString(context?.auth?.uid);
  if (!uid) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Authentication is required.',
    );
  }
  return uid;
}

function assertOwnerAndRequest({ videoData, uid, requestId, functions }) {
  if (videoData.uid !== uid) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Upload reservation owner mismatch.',
    );
  }
  if (sanitizeString(videoData.uploadRequestId) !== requestId) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Upload request id mismatch.',
    );
  }
}

function normalizeCloudAccessState(value) {
  const state = sanitizeString(value).toLowerCase();
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

function resolveCloudAccessState(userData, nowMs) {
  const data = userData || {};
  const explicitState = normalizeCloudAccessState(data.cloudAccessState);
  if ([
    'expired_grace_period',
    'read_only_cloud',
    'scheduled_for_cleanup',
    'deleted',
  ].includes(explicitState)) {
    return explicitState;
  }

  const tier = normalizeRuntimeTier(data.subscriptionTier);
  const nextTier = normalizeRuntimeTier(data.nextTier);
  const nextTierEffectiveAt = readMillis(data.nextTierEffectiveAt);
  const explicitExpiry = firstMillis([
    data.subscriptionExpiresAt,
    data.subscriptionExpiryAt,
    data.expiryTimeMillis,
    data.expiryAt,
    data.lastKnownPaidExpiryAt,
  ]);
  const paidExpiry = nextTier === 'free' && nextTierEffectiveAt !== null
    ? (explicitExpiry === null ? nextTierEffectiveAt : Math.min(explicitExpiry, nextTierEffectiveAt))
    : explicitExpiry;

  if (tier === 'standard') {
    if (paidExpiry === null || paidExpiry > nowMs) {
      return 'active_standard';
    }
    return nowMs < paidExpiry + (30 * 24 * 60 * 60 * 1000)
      ? 'expired_grace_period'
      : 'scheduled_for_cleanup';
  }

  const lastKnownPaidExpiryAt = firstMillis([
    data.lastKnownPaidExpiryAt,
    data.subscriptionExpiresAt,
    data.subscriptionExpiryAt,
    data.expiryTimeMillis,
    data.expiryAt,
  ]);
  if (tier === 'free' && lastKnownPaidExpiryAt !== null && lastKnownPaidExpiryAt <= nowMs) {
    return nowMs < lastKnownPaidExpiryAt + (30 * 24 * 60 * 60 * 1000)
      ? 'read_only_cloud'
      : 'scheduled_for_cleanup';
  }

  return 'deleted';
}

function isPaidUploadEntitled(userData, nowMs) {
  return resolveCloudAccessState(userData, nowMs) === 'active_standard';
}

function canReadExistingCloudClips(userData, nowMs) {
  return [
    'active_standard',
    'expired_grace_period',
    'read_only_cloud',
  ].includes(resolveCloudAccessState(userData, nowMs));
}

function normalizeRuntimeTier(value) {
  const tier = sanitizeString(value).toLowerCase();
  if (tier === 'premium') return 'standard';
  if (tier === 'standard' || tier === 'free') return tier;
  return '';
}

function canReserveUploadBytes(usedBytes, reservedBytes, incomingBytes, limitBytes) {
  if (incomingBytes <= 0 || limitBytes <= 0) return false;
  return usedBytes + reservedBytes + incomingBytes <= limitBytes;
}

function canUploadStandardVideoObjectBytes(fileSize) {
  return fileSize > 0 && fileSize <= STANDARD_VIDEO_OBJECT_LIMIT_BYTES;
}

function isStandardVideoMetadata(metadata) {
  if (!metadata || metadata.assetType !== 'standard_video') return false;
  const decision = sanitizeString(metadata.cloudPreflightDecision);
  if (!['readyOriginal', 'normalizedCopy'].includes(decision)) return false;
  const normalizedQuality = sanitizeString(metadata.normalizedQuality).toLowerCase();
  if (normalizedQuality && normalizedQuality !== '1080p') return false;
  const normalizedFileSize = optionalNonNegativeInt(metadata.normalizedFileSize);
  if (
    normalizedFileSize !== null &&
    normalizedFileSize > 0 &&
    !canUploadStandardVideoObjectBytes(normalizedFileSize)
  ) {
    return false;
  }
  const width = optionalNonNegativeInt(metadata.width);
  const height = optionalNonNegativeInt(metadata.height);
  if (width !== null && height !== null && width > 0 && height > 0) {
    const longest = Math.max(width, height);
    const shortest = Math.min(width, height);
    if (longest > 1920 || shortest > 1080) return false;
  }
  return true;
}

function sanitizeClientMetadata(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    return {};
  }

  const allowedKeys = [
    'assetType',
    'normalizedForStandard',
    'sourceFileSize',
    'normalizedFileSize',
    'sourceDurationMs',
    'durationMs',
    'width',
    'height',
    'fps',
    'targetFps',
    'targetBitrate',
    'codec',
    'bitrate',
    'normalizedQuality',
    'normalizedVideoCodec',
    'cloudPreflightDecision',
    'cloudPreflightReason',
  ];

  const result = {};
  for (const key of allowedKeys) {
    const value = raw[key];
    if (typeof value === 'string') {
      const sanitized = sanitizeString(value);
      if (sanitized) result[key] = sanitized.slice(0, 160);
    } else if (typeof value === 'number' && Number.isFinite(value)) {
      result[key] = Math.max(0, Math.trunc(value));
    } else if (typeof value === 'boolean') {
      result[key] = value;
    }
  }
  return result;
}

function normalizePayload(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    return {};
  }
  return data;
}

function requirePositiveInt(value, fieldName, functions) {
  const parsed = nonNegativeInt(value);
  if (parsed <= 0) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `${fieldName} must be a positive integer.`,
    );
  }
  return parsed;
}

function requireSafeId(value, fieldName, functions) {
  const normalized = sanitizeString(value);
  if (!/^[A-Za-z0-9._:-]{6,180}$/.test(normalized)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `${fieldName} is invalid.`,
    );
  }
  return normalized;
}

function optionalSafeId(value) {
  const normalized = sanitizeString(value);
  if (!normalized) return null;
  return /^[A-Za-z0-9_-]{6,128}$/.test(normalized) ? normalized : null;
}

function sanitizeStorageFileName(value) {
  const raw = sanitizeString(value).replace(/\\/g, '/').split('/').pop() || 'clip.mp4';
  const sanitized = raw.replace(/[^A-Za-z0-9._-]+/g, '_').replace(/_+/g, '_');
  const compact = sanitized.replace(/^\.+/, '').slice(0, 96);
  if (!compact || compact === '.mp4') return 'clip.mp4';
  return compact.toLowerCase().endsWith('.mp4') ? compact : `${compact}.mp4`;
}

function buildVideoPath(uid, videoId, fileName) {
  return `users/${uid}/videos/${videoId}/${fileName}`;
}

function buildThumbnailPath(uid, videoId) {
  return `users/${uid}/videos/${videoId}/thumbnails/poster.jpg`;
}

function isReservationExpired(value, nowMs) {
  const millis = readMillis(value);
  return millis !== null && millis <= nowMs;
}

function isReusableUploadMetadata(data) {
  if (!data || typeof data !== 'object') return false;
  if (data.reservationReleased === true) return true;
  const status = sanitizeString(data.uploadStatus).toLowerCase();
  return ['', 'queued', 'failed', 'cancelled', 'expired'].includes(status);
}

function timestampToMillis(value) {
  return readMillis(value);
}

function readMillis(value) {
  if (value === null || value === undefined) return null;
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === 'string' && value.trim()) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return Math.trunc(parsed);
    const dateMs = Date.parse(value);
    return Number.isFinite(dateMs) ? dateMs : null;
  }
  if (typeof value.toMillis === 'function') {
    return value.toMillis();
  }
  if (typeof value.seconds === 'number') {
    return value.seconds * 1000 + Math.trunc((value.nanoseconds || 0) / 1000000);
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

function optionalNonNegativeInt(value) {
  if (value === null || value === undefined || value === '') return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) return null;
  return Math.trunc(parsed);
}

function nonNegativeInt(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) return 0;
  return Math.trunc(parsed);
}

function sanitizeString(value) {
  if (value === null || value === undefined) return '';
  return String(value).trim();
}

function sanitizeUsageSource(value) {
  return sanitizeString(value)
    .replace(/[^A-Za-z0-9_-]+/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 64);
}

function parseBooleanEnv(name, defaultValue) {
  const raw = process.env[name];
  if (raw === undefined || raw === null) return defaultValue;
  const normalized = String(raw).trim().toLowerCase();
  if (['1', 'true', 'yes', 'y', 'on'].includes(normalized)) return true;
  if (['0', 'false', 'no', 'n', 'off', 'disabled'].includes(normalized)) {
    return false;
  }
  return defaultValue;
}

function periodKeyForDate(date) {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, '0');
  return `${year}-${month}`;
}

function dayKeyForDate(date) {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, '0');
  const day = String(date.getUTCDate()).padStart(2, '0');
  return `${year}${month}${day}`;
}

function shortHash(value) {
  return crypto
    .createHash('sha256')
    .update(String(value || ''))
    .digest('hex')
    .slice(0, 16);
}

function buildDownloadEventId({ videoId, source, cacheMissId, date }) {
  const safeSource = sanitizeUsageSource(source) || 'download';
  return `download_${videoId}_${safeSource}_${dayKeyForDate(date)}_${shortHash(cacheMissId)}`;
}

function buildDownloadUsageMutation({
  uid,
  videoId,
  source,
  bytes,
  cacheHit,
  hardLimitEnabled,
  userData,
  videoData,
  now,
  nowDate,
  requestId,
  eventId,
}) {
  const periodKey = periodKeyForDate(nowDate);
  const currentPeriodKey = sanitizeString(userData.monthlyDownloadPeriodKey);
  const samePeriod = currentPeriodKey === '' || currentPeriodKey === periodKey;
  const currentMonthlyDownloadBytes = samePeriod
    ? nonNegativeInt(userData.monthlyDownloadBytes)
    : 0;
  const currentCacheHitCount = samePeriod
    ? nonNegativeInt(userData.monthlyDownloadCacheHitCount)
    : 0;
  const currentCacheMissCount = samePeriod
    ? nonNegativeInt(userData.monthlyDownloadCacheMissCount)
    : 0;
  const downloadDelta = cacheHit ? 0 : nonNegativeInt(bytes);
  const monthlyDownloadBytes = currentMonthlyDownloadBytes + downloadDelta;
  const hardLimitExceeded =
    !cacheHit && monthlyDownloadBytes >= MONTHLY_DOWNLOAD_HARD_LIMIT_BYTES;
  const hardBlocked = hardLimitEnabled && hardLimitExceeded;
  const downloadCount = nonNegativeInt(videoData.downloadCount) + 1;
  const softLimitExceeded =
    monthlyDownloadBytes >= MONTHLY_DOWNLOAD_SOFT_LIMIT_BYTES;

  const eventData = {
    uid,
    videoId,
    eventType: 'download',
    source,
    bytes: downloadDelta,
    storageDelta: 0,
    downloadDelta,
    uploadDelta: 0,
    requestId,
    periodKey,
    status: cacheHit ? 'cache_hit' : 'committed',
    cacheHit,
    createdAt: now,
    committedAt: now,
    metadataVersion: METADATA_VERSION,
  };

  return {
    currentMonthlyDownloadBytes,
    monthlyDownloadBytes,
    hardBlocked,
    userMerge: {
      monthlyDownloadPeriodKey: periodKey,
      monthlyDownloadBytes,
      monthlyDownloadCacheHitCount: currentCacheHitCount + (cacheHit ? 1 : 0),
      monthlyDownloadCacheMissCount: currentCacheMissCount + (cacheHit ? 0 : 1),
      cloudUsageUpdatedAt: now,
      lastUpdated: now,
    },
    videoMerge: {
      downloadCount,
      lastDownloadedAt: now,
      monthlyDownloadBytesAtLastEvent: monthlyDownloadBytes,
      updatedAt: now,
    },
    eventData,
    response: {
      videoId,
      eventId,
      recorded: true,
      duplicate: false,
      cacheHit,
      bytesRecorded: downloadDelta,
      monthlyDownloadBytes,
      softLimitExceeded,
      hardLimitEnforced: hardLimitEnabled,
      hardLimitExceeded,
    },
  };
}

module.exports = {
  createCloudUploadReservationFunctions,
  __test__: {
    STANDARD_CLOUD_LIMIT_BYTES,
    MONTHLY_DOWNLOAD_SOFT_LIMIT_BYTES,
    MONTHLY_DOWNLOAD_HARD_LIMIT_BYTES,
    STANDARD_VIDEO_OBJECT_LIMIT_BYTES,
    MAX_VIDEO_OBJECT_BYTES,
    RESERVATION_TTL_MS,
    VIDEO_CONTENT_TYPE,
    canUploadStandardVideoObjectBytes,
    canReserveUploadBytes,
    canReadExistingCloudClips,
    isPaidUploadEntitled,
    isStandardVideoMetadata,
    isReusableUploadMetadata,
    normalizeCloudAccessState,
    normalizeRuntimeTier,
    periodKeyForDate,
    readMillis,
    resolveCloudAccessState,
    sanitizeClientMetadata,
    sanitizeStorageFileName,
    buildDownloadEventId,
    buildDownloadUsageMutation,
  },
};
