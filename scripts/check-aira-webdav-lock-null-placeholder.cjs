#!/usr/bin/env node
'use strict';

// Runs the production WebDAV sync stores against a provider that materialises a
// "lock-null" resource: `LOCK` on a path that does not exist yet creates it as a
// 0-byte file. NAS appliances (fnOS, and everything built on SabreDAV's Locks
// plugin) behave this way even though RFC 4918 dropped the lock-null concept, and
// the same providers ignore `If-None-Match`, `If-Match` and `MOVE Overwrite: F`.
// That combination is what makes Aira publish a snapshot under an exclusive LOCK:
// LOCK -> re-read under the lock -> PUT -> UNLOCK.
//
// The re-read used to parse the 0-byte placeholder that the LOCK itself had just
// created, so the very first write failed with "WebDAV 个性化同步快照无法解析。",
// left the placeholder behind, and wedged every later sync on the same empty file.
// This check executes the real stores over the real request sequence:
//
//   1. first write to a provider that creates LOCK placeholders must publish content
//   2. a leftover 0-byte snapshot (what the old build left on the NAS) must read as
//      "no remote snapshot" and be overwritten instead of blocking the sync
//   3. an unreadable-but-present remote body must still be a hard parse failure
//   4. a stale revision must still be rejected (the fix must not weaken compare-and-swap)
//   5. the same must hold for the bookmark domain's own snapshot path
//
// No device, account, or production endpoint is used.

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');

const ETS_ROOT = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const DAV_PREFIX = '/dav';
const USERNAME = 'aira';
const PASSWORD = 'aira-check';
const PERSONALIZATION_WRITE_CONFLICT = 'personalization-sync-write-conflict';

// ---------------------------------------------------------------------------
// A WebDAV provider with the two behaviours that matter: it creates a 0-byte
// resource for LOCK on an unmapped path, and it ignores the HTTP conditional
// headers plus `MOVE Overwrite: F`.
// ---------------------------------------------------------------------------

function createLockNullWebdav() {
  const files = new Map();
  const directories = new Set(['/']);
  const locks = new Map();
  const requestLog = [];
  const state = { lockNullCreations: 0 };

  const etagOf = (body) => `"${crypto.createHash('sha256').update(body).digest('hex')}"`;
  const parentOf = (target) => {
    const index = target.lastIndexOf('/');
    return index <= 0 ? '/' : target.slice(0, index);
  };
  const normalize = (rawPath) => {
    const decoded = decodeURIComponent(rawPath);
    const trimmed = decoded.replace(/\/+$/, '');
    const relative = trimmed.startsWith(DAV_PREFIX) ? trimmed.slice(DAV_PREFIX.length) : trimmed;
    return relative.length === 0 ? '/' : `/${relative.replace(/^\/+/, '')}`;
  };

  function send(response, status, headers = {}, body) {
    response.writeHead(status, headers);
    response.end(body);
  }

  function unauthorized(request) {
    const header = String(request.headers.authorization || '');
    if (!header.startsWith('Basic ')) {
      return true;
    }
    const decoded = Buffer.from(header.slice('Basic '.length), 'base64').toString('utf8');
    return decoded !== `${USERNAME}:${PASSWORD}`;
  }

  async function handle(request, response) {
    if (unauthorized(request)) {
      send(response, 401, { 'WWW-Authenticate': 'Basic realm="aira-check"' });
      return;
    }
    const target = normalize(new URL(request.url, 'http://localhost').pathname);
    const body = await new Promise((resolve, reject) => {
      const chunks = [];
      request.on('data', (chunk) => chunks.push(chunk));
      request.on('end', () => resolve(Buffer.concat(chunks)));
      request.on('error', reject);
    });
    requestLog.push({
      method: request.method,
      path: target,
      bodyLength: body.length,
      conditional: {
        if: String(request.headers.if || ''),
        ifMatch: String(request.headers['if-match'] || ''),
        ifNoneMatch: String(request.headers['if-none-match'] || ''),
        overwrite: String(request.headers.overwrite || ''),
        depth: String(request.headers.depth || '')
      }
    });

    if (request.method === 'OPTIONS') {
      send(response, 200, { DAV: '1, 2', Allow: 'OPTIONS, GET, PUT, DELETE, MKCOL, MOVE, LOCK, UNLOCK' });
      return;
    }
    if (request.method === 'MKCOL') {
      if (directories.has(target) || files.has(target)) {
        send(response, 405);
        return;
      }
      if (!directories.has(parentOf(target))) {
        send(response, 409);
        return;
      }
      directories.add(target);
      send(response, 201);
      return;
    }
    if (request.method === 'GET') {
      const stored = files.get(target);
      if (stored === undefined) {
        send(response, 404);
        return;
      }
      send(response, 200, {
        'Content-Type': 'application/json; charset=utf-8',
        'Content-Length': stored.length,
        ETag: etagOf(stored)
      }, stored);
      return;
    }
    if (request.method === 'PUT') {
      const heldLock = locks.get(target);
      const presented = String(request.headers.if || '');
      if (heldLock !== undefined && !presented.includes(heldLock)) {
        send(response, 423);
        return;
      }
      if (!directories.has(parentOf(target))) {
        send(response, 409);
        return;
      }
      // Deliberately ignores If-None-Match and If-Match: this is why Aira has to
      // serialize with LOCK instead of a conditional PUT.
      const created = !files.has(target);
      files.set(target, body);
      send(response, created ? 201 : 204, { ETag: etagOf(body) });
      return;
    }
    if (request.method === 'MOVE') {
      if (!files.has(target)) {
        send(response, 404);
        return;
      }
      const destinationHeader = String(request.headers.destination || '');
      if (destinationHeader.length === 0) {
        send(response, 400);
        return;
      }
      const destination = normalize(new URL(destinationHeader, 'http://localhost').pathname);
      if (!directories.has(parentOf(destination))) {
        send(response, 409);
        return;
      }
      // Deliberately ignores `Overwrite: F`, so the move-based first write is unusable.
      const existed = files.has(destination);
      const moved = files.get(target);
      files.delete(target);
      files.set(destination, moved);
      send(response, existed ? 204 : 201, { ETag: etagOf(moved) });
      return;
    }
    if (request.method === 'DELETE') {
      if (files.delete(target)) {
        locks.delete(target);
        send(response, 204);
        return;
      }
      if (target !== '/' && directories.delete(target)) {
        send(response, 204);
        return;
      }
      send(response, 404);
      return;
    }
    if (request.method === 'LOCK') {
      if (locks.has(target)) {
        send(response, 423);
        return;
      }
      const created = !files.has(target) && !directories.has(target);
      if (created) {
        // The lock-null placeholder: a lock creates the resource as an empty file.
        files.set(target, Buffer.alloc(0));
        state.lockNullCreations += 1;
      }
      const token = `opaquelocktoken:${crypto.randomUUID()}`;
      locks.set(target, token);
      send(response, created ? 201 : 200, { 'Lock-Token': `<${token}>` });
      return;
    }
    if (request.method === 'UNLOCK') {
      const presented = String(request.headers['lock-token'] || '').replace(/[<>]/g, '');
      if (locks.get(target) !== presented) {
        send(response, 409);
        return;
      }
      locks.delete(target);
      send(response, 204);
      return;
    }
    send(response, 405);
  }

  return new Promise((resolve) => {
    const server = http.createServer((request, response) => {
      handle(request, response).catch((error) => {
        response.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
        response.end(error && error.message ? error.message : String(error));
      });
    });
    server.listen(0, '127.0.0.1', () => {
      const port = server.address().port;
      resolve({
        endpoint: `http://127.0.0.1:${port}${DAV_PREFIX}`,
        files,
        state,
        requestLog,
        read: (davPath) => files.get(davPath),
        write: (davPath, content) => files.set(davPath, Buffer.from(content, 'utf8')),
        close: () => new Promise((done) => server.close(done))
      });
    });
  });
}

// ---------------------------------------------------------------------------
// `@ohos.net.http` over node:http, so the production stores drive a real socket.
// ---------------------------------------------------------------------------

function createOhosHttp() {
  function requestOnce(url, options) {
    return new Promise((resolve, reject) => {
      const target = new URL(url);
      const body = options.extraData;
      const headers = {};
      const source = options.header || {};
      Object.keys(source).forEach((name) => {
        if (source[name] !== undefined && source[name] !== null) {
          headers[name] = String(source[name]);
        }
      });
      if (body !== undefined) {
        headers['Content-Length'] = Buffer.byteLength(String(body));
      }
      const request = http.request({
        host: target.hostname,
        port: target.port,
        method: String(options.method),
        path: `${target.pathname}${target.search}`,
        headers
      }, (response) => {
        const chunks = [];
        response.on('data', (chunk) => chunks.push(chunk));
        response.on('end', () => {
          resolve({
            responseCode: response.statusCode,
            result: Buffer.concat(chunks).toString('utf8'),
            header: response.headers
          });
        });
      });
      request.on('error', reject);
      if (body !== undefined) {
        request.end(String(body));
      } else {
        request.end();
      }
    });
  }

  const RequestMethod = {
    OPTIONS: 'OPTIONS',
    GET: 'GET',
    HEAD: 'HEAD',
    POST: 'POST',
    PUT: 'PUT',
    DELETE: 'DELETE',
    TRACE: 'TRACE',
    CONNECT: 'CONNECT'
  };

  return {
    default: {
      createHttp: () => ({
        request: requestOnce,
        destroy: () => {}
      }),
      RequestMethod,
      HttpDataType: { STRING: 'string', OBJECT: 'object', ARRAY_BUFFER: 'arraybuffer' }
    },
    createHttp: () => ({
      request: requestOnce,
      destroy: () => {}
    }),
    RequestMethod,
    HttpDataType: { STRING: 'string', OBJECT: 'object', ARRAY_BUFFER: 'arraybuffer' }
  };
}

// ---------------------------------------------------------------------------
// Load the production ArkTS stores with `transpileModule`, as the other sync
// checks do. Only value imports are resolved; type-only imports are elided.
// ---------------------------------------------------------------------------

const loadedModules = new Map();
const stubModules = {
  '@ohos.net.http': createOhosHttp(),
  '@ohos.buffer': (() => {
    const wrapper = { from: (value, encoding) => Buffer.from(value, encoding) };
    return Object.assign({ default: wrapper }, wrapper);
  })(),
  '@kit.PerformanceAnalysisKit': { hilog: { error() {}, warn() {}, info() {} } },
  '@kit.ArkData': { preferences: { async getPreferences() { throw new Error('not used'); } } },
  '@kit.CryptoArchitectureKit': {
    cryptoFramework: { createMd() { throw new Error('not used'); } }
  },
  '@kit.ArkTS': { util: { TextEncoder: { create: () => new TextEncoder() } } }
};

function resolveEts(fromFile, specifier) {
  return path.relative(ETS_ROOT, path.resolve(path.dirname(fromFile), `${specifier}.ets`));
}

function loadEts(relativePath) {
  if (loadedModules.has(relativePath)) {
    return loadedModules.get(relativePath);
  }
  const filename = path.join(ETS_ROOT, relativePath);
  const module = { exports: {} };
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
    fileName: filename
  }).outputText;
  loadedModules.set(relativePath, module.exports);
  vm.runInNewContext(code, {
    module,
    exports: module.exports,
    Error,
    JSON,
    Math,
    Date,
    Number,
    String,
    Boolean,
    Object,
    Array,
    Map,
    Set,
    Promise,
    RegExp,
    isNaN,
    parseInt,
    parseFloat,
    setTimeout,
    clearTimeout,
    require(name) {
      if (stubModules[name] !== undefined) {
        return stubModules[name];
      }
      if (name.startsWith('.')) {
        return loadEts(resolveEts(filename, name));
      }
      throw new Error(`Unexpected dependency: ${name}`);
    }
  }, { filename });
  return module.exports;
}

const { WebdavPersonalizationSyncStore } = loadEts('data/sync/WebdavPersonalizationSyncStore.ets');
const { AiraWebdavRemoteStore } = loadEts('services/sync/AiraWebdavRemoteStore.ets');

function buildWebdavConfig(endpoint) {
  return { endpoint, username: USERNAME, password: PASSWORD, rootPath: '' };
}

function buildPersonalizationSnapshot(deviceId, generatedAt) {
  const sections = {};
  ['home_shortcuts', 'core_preferences', 'activity_heatmap', 'search'].forEach((id) => {
    sections[id] = { enabled: false, updatedAt: 0, payload: {} };
  });
  return {
    meta: { version: 2, deviceId, generatedAt },
    sections,
    checksum: JSON.stringify(sections)
  };
}

function buildBookmarkSnapshot(deviceId, generatedAt) {
  return {
    meta: { version: 2, deviceId, generatedAt },
    bookmarkFolders: [],
    bookmarkItems: [],
    bookmarkOrders: [],
    tombstones: []
  };
}

function buildBookmarkHistory() {
  return {
    version: 1,
    epochId: 'bookmark-history-v1-lock-null-check',
    retainedFrom: new Date(0).toISOString()
  };
}

const PERSONALIZATION_FILE = '/aira/g2/personalization/snapshot.json';
const BOOKMARK_FILE = '/aira/g3/bookmarks/snapshot.json';
const PROBE_PREFIXES = ['cas-probe-', 'lock-probe-', 'move-probe-', '.create-'];

function probeResidue(webdav) {
  return Array.from(webdav.files.keys()).filter((davPath) => {
    const name = davPath.slice(davPath.lastIndexOf('/') + 1);
    return PROBE_PREFIXES.some((prefix) => name.startsWith(prefix));
  });
}

async function withProvider(run) {
  const webdav = await createLockNullWebdav();
  try {
    await run(webdav);
  } finally {
    await webdav.close();
  }
}

test('a first WebDAV personalization write publishes through a LOCK-created placeholder', async () => {
  await withProvider(async (webdav) => {
    const store = new WebdavPersonalizationSyncStore(buildWebdavConfig(webdav.endpoint));
    const snapshot = buildPersonalizationSnapshot('device-lock-null', '2026-01-01T00:00:00.000Z');
    const result = await store.writeSnapshot('device-lock-null', snapshot, '');
    assert.ok(result.revision.trim().length > 0, 'write must confirm a revision');
    const published = webdav.read(PERSONALIZATION_FILE);
    assert.ok(published !== undefined, 'the snapshot file must exist');
    assert.equal(published.length > 0, true, 'the published snapshot must not be a 0-byte placeholder');
    assert.deepEqual(JSON.parse(published.toString('utf8')), snapshot);
    assert.equal(webdav.state.lockNullCreations > 0, true,
      'the provider must have created the file through LOCK, otherwise this check no longer reproduces the report');
    assert.deepEqual(probeResidue(webdav), [], 'capability probes must clean up after themselves');
    const state = await store.readState();
    assert.deepEqual(state.snapshot, snapshot);
    assert.equal(state.revision.trim(), result.revision.trim());
  });
});

test('a 0-byte snapshot left by an older build reads as absent and is overwritten', async () => {
  await withProvider(async (webdav) => {
    webdav.write(PERSONALIZATION_FILE, '');
    assert.equal(webdav.read(PERSONALIZATION_FILE).length, 0, 'the residue must start as 0 bytes');
    const store = new WebdavPersonalizationSyncStore(buildWebdavConfig(webdav.endpoint));
    const before = await store.readState();
    assert.equal(before.snapshot, null, 'a 0-byte body is not a snapshot');
    assert.equal(before.revision.trim(), '', 'an unreadable body must not hand out a revision to write against');
    const snapshot = buildPersonalizationSnapshot('device-heal', '2026-01-02T00:00:00.000Z');
    await store.writeSnapshot('device-heal', snapshot, before.revision);
    const published = webdav.read(PERSONALIZATION_FILE);
    assert.ok(published.length > 0, 'the residue must be replaced by real content');
    assert.deepEqual(JSON.parse(published.toString('utf8')), snapshot);
  });
});

test('a present but unreadable remote body stays a hard failure', async () => {
  await withProvider(async (webdav) => {
    webdav.write(PERSONALIZATION_FILE, '{"meta":');
    const store = new WebdavPersonalizationSyncStore(buildWebdavConfig(webdav.endpoint));
    await assert.rejects(
      () => store.readState(),
      /个性化同步快照无法解析/,
      'truncated JSON must not be silently treated as an empty remote'
    );
    webdav.write(PERSONALIZATION_FILE, '{"meta":{"version":2,"deviceId":"d","generatedAt":"2026-01-01T00:00:00.000Z"}}');
    await assert.rejects(
      () => store.readState(),
      /个性化同步快照(格式无效|内容不完整)/,
      'an incomplete snapshot must keep failing validation'
    );
  });
});

test('a stale revision is still rejected against a lock-created placeholder', async () => {
  await withProvider(async (webdav) => {
    const store = new WebdavPersonalizationSyncStore(buildWebdavConfig(webdav.endpoint));
    const first = buildPersonalizationSnapshot('device-a', '2026-01-03T00:00:00.000Z');
    const written = await store.writeSnapshot('device-a', first, '');
    const other = new WebdavPersonalizationSyncStore(buildWebdavConfig(webdav.endpoint));
    const second = buildPersonalizationSnapshot('device-b', '2026-01-04T00:00:00.000Z');
    await other.writeSnapshot('device-b', second, written.revision.trim());
    const third = buildPersonalizationSnapshot('device-a', '2026-01-05T00:00:00.000Z');
    await assert.rejects(
      () => store.writeSnapshot('device-a', third, written.revision.trim()),
      (error) => error.message === PERSONALIZATION_WRITE_CONFLICT,
      'an outdated revision must not overwrite a newer remote snapshot'
    );
    assert.deepEqual(JSON.parse(webdav.read(PERSONALIZATION_FILE).toString('utf8')), second);
  });
});

test('the bookmark domain survives the same LOCK-created placeholder', async () => {
  await withProvider(async (webdav) => {
    const store = new AiraWebdavRemoteStore(
      Object.assign(buildWebdavConfig(webdav.endpoint), { rootPath: 'aira/g3/bookmarks' }),
      'aira/g3/bookmarks'
    );
    const snapshot = buildBookmarkSnapshot('device-bookmarks', '2026-01-06T00:00:00.000Z');
    const history = buildBookmarkHistory();
    const written = await store.writeState({
      snapshot,
      history,
      deviceId: 'device-bookmarks',
      parentCommitId: null,
      createdAt: '2026-01-06T00:00:00.000Z'
    });
    assert.ok(written.commitId.trim().length > 0);
    const published = webdav.read(BOOKMARK_FILE);
    assert.ok(published !== undefined && published.length > 0,
      'the bookmark snapshot must not stay a 0-byte placeholder');
    const envelope = JSON.parse(published.toString('utf8'));
    assert.equal(envelope.version, 2);
    assert.deepEqual(envelope.snapshot, snapshot);
    assert.deepEqual(envelope.history, history);
    assert.deepEqual(probeResidue(webdav), [], 'capability probes must clean up after themselves');
    const state = await store.readState();
    assert.deepEqual(state.snapshot, snapshot);
    assert.equal(state.commitId, written.commitId);
    const next = buildBookmarkSnapshot('device-bookmarks', '2026-01-07T00:00:00.000Z');
    const rewritten = await store.writeState({
      snapshot: next,
      history,
      deviceId: 'device-bookmarks',
      parentCommitId: written.commitId,
      createdAt: '2026-01-07T00:00:00.000Z'
    });
    assert.notEqual(rewritten.commitId, written.commitId);
    assert.deepEqual(JSON.parse(webdav.read(BOOKMARK_FILE).toString('utf8')).snapshot, next);
  });
});
