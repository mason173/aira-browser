const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'aira-server-check-'));
const port = 19000 + crypto.randomInt(1000);
const child = spawn(process.execPath, ['src/server.js'], {
  cwd: path.resolve(__dirname, '..'),
  env: { ...process.env, AIRA_DATA_DIR: dataDir, AIRA_PORT: String(port), AIRA_HOST: '127.0.0.1' },
  stdio: ['ignore', 'pipe', 'inherit'],
});

let output = '';
child.stdout.on('data', (chunk) => { output += chunk; });

async function run() {
  try {
    await waitForHealth();
    const discovery = await json('GET', '/.well-known/aira');
    assert(discovery.protocolVersion === 1 && discovery.instanceId, 'discovery');
    const setupCode = fs.readFileSync(path.join(dataDir, 'setup-code'), 'utf8').trim();
    const first = await json('POST', '/v1/pairing/exchange', {
      code: setupCode, deviceId: 'check-device-1', deviceName: 'Check Device 1',
    });
    assert(first.token && first.instanceId === discovery.instanceId, 'first pairing');
    let firstToken = first.token;
    const pairing = await json('POST', '/v1/pairing/codes', {}, firstToken);
    const second = await json('POST', '/v1/pairing/exchange', {
      code: pairing.code, deviceId: 'check-device-2', deviceName: 'Check Device 2',
    });
    assert(second.token, 'second pairing');
    const generatedAt = new Date().toISOString();
    const bookmarkWrite = await json('POST', '/v1/sync/bookmarks/write', {
      parentCommitId: null,
      deviceId: 'check-device-1',
      createdAt: generatedAt,
      history: { version: 1, epochId: 'check', retainedFrom: 0 },
      snapshot: { meta: { generatedAt }, bookmarkFolders: [], bookmarkItems: [] },
    }, firstToken);
    const bookmarkRead = await json('POST', '/v1/sync/bookmarks/read', {}, second.token);
    assert(bookmarkWrite.commitId && bookmarkRead.commitId === bookmarkWrite.commitId, 'bookmark sync');
    const write = await json('POST', '/v1/sync/personalization/write', {
      expectedRevision: '', deviceId: 'check-device-1', snapshot: { meta: { generatedAt: new Date().toISOString() } },
    }, firstToken);
    const read = await json('POST', '/v1/sync/personalization/read', {}, second.token);
    assert(write.revision === '1' && read.revision === '1', 'multi-device snapshot');
    const personalizationConflict = await raw('POST', '/v1/sync/personalization/write', {
      expectedRevision: '', deviceId: 'check-device-2', snapshot: { meta: { generatedAt } },
    }, second.token);
    assert(personalizationConflict.status === 409, 'snapshot compare-and-swap');
    const novelWrite = await json('POST', '/v1/sync/novel-bookshelf/write', {
      expectedRevision: '', deviceId: 'check-device-1', snapshot: { meta: { generatedAt }, books: [] },
    }, firstToken);
    const novelRead = await json('POST', '/v1/sync/novel-bookshelf/read', {}, second.token);
    assert(novelWrite.revision === '1' && novelRead.revision === '1', 'novel bookshelf sync');
    const historyWrite = await json('POST', '/v1/sync/history/exchange', {
      clientId: 'check-device-1', cursor: 0, pullLimit: 200, mutations: [{
        mutationId: 'check-mutation-1',
        kind: 'upsert_visit',
        visit: {
          visitId: 'h1:check-device-1:visit-1',
          url: 'https://example.com/',
          title: 'Example',
          visitedAt: Date.now(),
          transition: 'typed',
          referrer: '',
          deviceName: 'Check Device 1',
          source: 'app',
        },
      }],
    }, firstToken);
    assert(historyWrite.acknowledgements.length === 1, 'history upload');
    const historyRead = await json('POST', '/v1/sync/history/bootstrap', {
      clientId: 'check-device-2', pageLimit: 200,
    }, second.token);
    assert(historyRead.visits.some((visit) => visit.visitId === 'h1:check-device-1:visit-1') &&
      historyRead.hasMore === false, 'history cross-device bootstrap');
    const historyIncremental = await json('POST', '/v1/sync/history/exchange', {
      clientId: 'check-device-2', cursor: historyRead.bootstrapHead, pullLimit: 200, mutations: [],
    }, second.token);
    assert(historyIncremental.nextCursor === historyRead.bootstrapHead, 'history incremental continuation');
    const rotated = await json('POST', '/v1/device/rotate', {}, firstToken);
    assert(rotated.token && rotated.credentialId, 'credential rotation');
    const oldCredential = await raw('GET', '/v1/devices', undefined, firstToken);
    assert(oldCredential.status === 401, 'rotated credential invalidation');
    firstToken = rotated.token;
    const devices = await json('GET', '/v1/devices', undefined, firstToken);
    assert(devices.devices.length === 2, 'device list');
    await json('POST', '/v1/devices/check-device-2/revoke', {}, firstToken);
    const revokedStatus = await raw('POST', '/v1/sync/personalization/read', {}, second.token);
    assert(revokedStatus.status === 401, 'revocation');
    console.log('Aira Personal Server install check passed.');
  } finally {
    child.kill('SIGTERM');
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}

async function waitForHealth() {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/health`);
      if (response.ok) return;
    } catch (_error) {}
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(`Server did not become healthy. Output: ${output}`);
}

async function raw(method, route, body, token) {
  return fetch(`http://127.0.0.1:${port}${route}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: method === 'GET' ? undefined : JSON.stringify(body || {}),
  });
}

async function json(method, route, body, token) {
  const response = await raw(method, route, body, token);
  const value = await response.json();
  if (!response.ok) throw new Error(`${route}: ${response.status} ${JSON.stringify(value)}`);
  return value;
}

function assert(condition, label) {
  if (!condition) throw new Error(`Install check failed: ${label}`);
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
