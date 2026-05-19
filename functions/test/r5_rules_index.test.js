const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  doc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
  deleteDoc,
  collection,
  query,
  where,
  orderBy,
  serverTimestamp,
} = require('firebase/firestore');

const PROJECT_ID = 'three-sec-vlog-r5-rules-test';

function rulesPath(fileName) {
  return path.join(__dirname, '..', '..', 'firebase', fileName);
}

const videoPayload = (uid, videoId, overrides = {}) => ({
  uid,
  videoId,
  fileName: `${videoId}.mp4`,
  storagePath: `users/${uid}/videos/${videoId}/${videoId}.mp4`,
  albumName: '일상',
  isFavorite: false,
  fileSize: 1024,
  uploadStatus: 'completed',
  uploadProgress: 100,
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  ...overrides,
});

async function seedFirestore(testEnv) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'users/userA'), {
      uid: 'userA',
      subscriptionTier: 'standard',
      storageUsage: 1024,
      lastUpdated: serverTimestamp(),
    });
    await setDoc(doc(db, 'users/userB'), {
      uid: 'userB',
      subscriptionTier: 'standard',
      storageUsage: 2048,
      lastUpdated: serverTimestamp(),
    });
    await setDoc(doc(db, 'videos/videoA'), videoPayload('userA', 'videoA'));
    await setDoc(doc(db, 'videos/videoB'), videoPayload('userB', 'videoB'));
    await setDoc(doc(db, 'vlog_projects/projectA'), {
      uid: 'userA',
      localProjectId: 'localProjectA',
      title: 'Project A',
      clipPaths: [],
      clipCount: 0,
      folderName: '기본',
      lockState: 'unlocked',
      clientCreatedAt: serverTimestamp(),
      clientUpdatedAt: serverTimestamp(),
      deleted: false,
    });
  });
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(rulesPath('firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
    storage: {
      rules: fs.readFileSync(rulesPath('storage.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 9199,
    },
  });

  try {
    await seedFirestore(testEnv);

    const userA = testEnv.authenticatedContext('userA');
    const userB = testEnv.authenticatedContext('userB');
    const anon = testEnv.unauthenticatedContext();
    const dbA = userA.firestore();
    const dbB = userB.firestore();
    const dbAnon = anon.firestore();

    await assertSucceeds(getDoc(doc(dbA, 'users/userA')));
    await assertFails(getDoc(doc(dbA, 'users/userB')));
    await assertFails(getDoc(doc(dbAnon, 'users/userA')));

    await assertSucceeds(getDoc(doc(dbA, 'videos/videoA')));
    await assertFails(getDoc(doc(dbA, 'videos/videoB')));
    await assertFails(updateDoc(doc(dbA, 'videos/videoB'), { albumName: '침해' }));
    await assertFails(
      setDoc(doc(dbA, 'videos/mismatch'), videoPayload('userB', 'mismatch')),
    );

    await assertSucceeds(
      getDocs(query(collection(dbA, 'videos'), where('uid', '==', 'userA'))),
    );
    await assertSucceeds(
      getDocs(
        query(
          collection(dbA, 'videos'),
          where('uid', '==', 'userA'),
          orderBy('createdAt', 'desc'),
        ),
      ),
    );
    await assertFails(
      getDocs(query(collection(dbA, 'videos'), where('uid', '==', 'userB'))),
    );

    await assertSucceeds(
      setDoc(doc(dbA, 'users/userA/usageEvents/upload_completed_videoA'), {
        uid: 'userA',
        videoId: 'videoA',
        reason: 'upload_completed',
        deltaRequested: 1024,
        deltaApplied: 1024,
        createdAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(dbA, 'users/userA/usageEvents/mismatch'), {
        uid: 'userB',
        videoId: 'videoA',
        reason: 'upload_completed',
        deltaRequested: 1024,
        deltaApplied: 1024,
        createdAt: serverTimestamp(),
      }),
    );
    await assertFails(deleteDoc(doc(dbA, 'users/userA/usageEvents/upload_completed_videoA')));
    await assertFails(getDoc(doc(dbB, 'users/userA/usageEvents/upload_completed_videoA')));

    const storageA = userA.storage();
    const storageB = userB.storage();
    await assertSucceeds(
      storageA.ref('users/userA/videos/videoA/videoA.mp4').put(new Uint8Array([1, 2, 3]), {
        contentType: 'video/mp4',
      }),
    );
    await assertFails(storageA.ref('users/userB/videos/videoB/videoB.mp4').getDownloadURL());
    await assertFails(
      storageB.ref('users/userA/videos/videoA/videoA.mp4').put(new Uint8Array([1, 2, 3]), {
        contentType: 'video/mp4',
      }),
    );
    await assertFails(
      storageA.ref('users/userA/videos/videoBad/file.txt').put(new Uint8Array([1, 2, 3]), {
        contentType: 'text/plain',
      }),
    );

    const indexes = JSON.parse(fs.readFileSync(rulesPath('firestore.indexes.json'), 'utf8'));
    const indexSignatures = indexes.indexes.map((idx) =>
      `${idx.collectionGroup}:${idx.fields.map((f) => `${f.fieldPath}:${f.order}`).join(',')}`,
    );
    assert(indexSignatures.includes('videos:uid:ASCENDING,createdAt:DESCENDING'));
    assert(indexSignatures.includes('videos:uid:ASCENDING,albumName:ASCENDING,createdAt:DESCENDING'));
    assert(indexSignatures.includes('videos:uid:ASCENDING,isFavorite:ASCENDING,createdAt:DESCENDING'));
    assert(indexSignatures.includes('videos:uid:ASCENDING,albumName:ASCENDING,isFavorite:ASCENDING,createdAt:DESCENDING'));

    console.log('[R5 rules/index] allow/deny rules tests passed');
  } finally {
    await testEnv.cleanup();
  }
}

main().catch((error) => {
  console.error('[R5 rules/index] failed');
  console.error(error);
  process.exit(1);
});
