const fs = require('node:fs');
const path = require('node:path');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'three-sec-vlog-thumbnail-storage-rules-test';
const THUMBNAIL_PATH = 'users/userA/videos/videoA/thumbnails/poster.jpg';
const MAX_THUMBNAIL_BYTES = 10 * 1024 * 1024;

function rulesPath(fileName) {
  return path.join(__dirname, '..', '..', 'firebase', fileName);
}

function jpegBytes(size = 3) {
  return new Uint8Array(size).fill(1);
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    storage: {
      rules: fs.readFileSync(rulesPath('storage.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 9199,
    },
  });

  try {
    const userA = testEnv.authenticatedContext('userA');
    const userB = testEnv.authenticatedContext('userB');
    const anon = testEnv.unauthenticatedContext();
    const storageA = userA.storage();
    const storageB = userB.storage();
    const storageAnon = anon.storage();

    await assertSucceeds(
      storageA.ref(THUMBNAIL_PATH).put(jpegBytes(), {
        contentType: 'image/jpeg',
      }),
    );

    await assertSucceeds(storageA.ref(THUMBNAIL_PATH).getDownloadURL());

    await assertFails(storageAnon.ref(THUMBNAIL_PATH).getDownloadURL());
    await assertFails(
      storageAnon.ref(THUMBNAIL_PATH).put(jpegBytes(), {
        contentType: 'image/jpeg',
      }),
    );

    await assertFails(
      storageB.ref(THUMBNAIL_PATH).put(jpegBytes(), {
        contentType: 'image/jpeg',
      }),
    );

    await assertFails(
      storageA.ref(THUMBNAIL_PATH).put(jpegBytes(), {
        contentType: 'text/plain',
      }),
    );

    await assertFails(
      storageA.ref(THUMBNAIL_PATH).put(jpegBytes(MAX_THUMBNAIL_BYTES + 1), {
        contentType: 'image/jpeg',
      }),
    );

    await assertFails(
      storageA.ref('users/userA/videos/videoA/other/poster.jpg').put(jpegBytes(), {
        contentType: 'image/jpeg',
      }),
    );

    await assertFails(
      storageA.ref('users/userA/videos/videoA/thumbnails/not-poster.jpg').put(jpegBytes(), {
        contentType: 'image/jpeg',
      }),
    );

    await assertFails(storageA.ref(THUMBNAIL_PATH).delete());

    console.log('[Thumbnail storage rules] allow/deny tests passed');
  } finally {
    await testEnv.cleanup();
  }
}

main().catch((error) => {
  console.error('[Thumbnail storage rules] failed');
  console.error(error);
  process.exit(1);
});
