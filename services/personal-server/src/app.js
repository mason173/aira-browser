const { publicBaseUrl } = require('./config');
const { readJson, writeJson } = require('./http');
const { toPublicError, fail } = require('./errors');
const {
  authenticate,
  createPairingCode,
  exchangePairingCode,
  getInstance,
  listDevices,
  revokeDevice,
  rotateCredential,
} = require('./instance');
const { readBookmark, readBookmarkHead, readSnapshot, writeBookmark, writeSnapshot } = require('./snapshot-store');
const { handleHistoryBootstrap, handleHistoryExchange } = require('./routes/history-routes');
const pagePush = require('./page-push');
const crossDeviceTabs = require('./cross-device-tabs');

const VERSION = '0.2.0';

async function handleRequest(request, response) {
  try {
    const url = new URL(request.url, 'http://localhost');
    if (request.method === 'GET' && url.pathname === '/health') {
      return writeJson(response, 200, { ok: true, version: VERSION, instanceId: getInstance().instanceId });
    }
    if (request.method === 'GET' && url.pathname === '/.well-known/aira') {
      return writeJson(response, 200, discovery());
    }
    if (request.method === 'POST' && url.pathname === '/v1/pairing/exchange') {
      return writeJson(response, 201, { ok: true, ...exchangePairingCode(await readJson(request)) });
    }

    const device = authenticate(request);
    if (request.method === 'POST' && url.pathname === '/v1/pairing/codes') {
      return writeJson(response, 201, { ok: true, ...createPairingCode(device) });
    }
    if (request.method === 'GET' && url.pathname === '/v1/devices') {
      return writeJson(response, 200, { ok: true, devices: listDevices() });
    }
    if (request.method === 'POST' && url.pathname === '/v1/device/rotate') {
      return writeJson(response, 200, { ok: true, ...rotateCredential(device) });
    }
    const revokeMatch = url.pathname.match(/^\/v1\/devices\/([^/]+)\/revoke$/);
    if (request.method === 'POST' && revokeMatch) {
      revokeDevice(decodeURIComponent(revokeMatch[1]));
      return writeJson(response, 200, { ok: true });
    }

    const body = request.method === 'POST' ? await readJson(request) : {};
    if (request.method === 'POST' && url.pathname === '/v1/page-push/enqueue') {
      return writeJson(response, 201, { ok: true, code: 'page_push_queued', ...pagePush.enqueue(body, device) });
    }
    if (request.method === 'POST' && url.pathname === '/v1/page-push/poll') {
      const result = await pagePush.poll(body, device);
      return writeJson(response, 200, {
        ok: true,
        code: result.task ? 'page_push_task' : 'page_push_empty',
        ...result,
      });
    }
    if (request.method === 'POST' && url.pathname === '/v1/page-push/ack') {
      return writeJson(response, 200, { ok: true, code: 'page_push_acknowledged', ...pagePush.acknowledge(body, device) });
    }
    if (request.method === 'POST' && url.pathname === '/v1/device-tabs/publish') {
      return writeJson(response, 200, { ok: true, code: 'cross_device_tabs_published', ...crossDeviceTabs.publish(body, device) });
    }
    if (request.method === 'POST' && url.pathname === '/v1/device-tabs/list') {
      return writeJson(response, 200, { ok: true, code: 'cross_device_tabs_listed', ...crossDeviceTabs.list(device) });
    }
    if (request.method === 'POST' && url.pathname === '/v1/device-tabs/clear') {
      return writeJson(response, 200, { ok: true, code: 'cross_device_tabs_cleared', ...crossDeviceTabs.clear(device) });
    }
    if (request.method === 'POST' && url.pathname === '/v1/sync/bookmarks/read') {
      return writeJson(response, 200, { ok: true, code: 'bookmark_sync_state', ...readBookmark() });
    }
    if (request.method === 'POST' && url.pathname === '/v1/sync/bookmarks/head') {
      return writeJson(response, 200, { ok: true, code: 'bookmark_sync_head', ...readBookmarkHead() });
    }
    if (request.method === 'POST' && url.pathname === '/v1/sync/bookmarks/write') {
      return writeJson(response, 200, { ok: true, code: 'bookmark_sync_written', ...writeBookmark(body, device) });
    }
    if (request.method === 'POST' && url.pathname === '/v1/sync/personalization/read') {
      return writeJson(response, 200, { ok: true, code: 'personalization_sync_state', ...readSnapshot('personalization') });
    }
    if (request.method === 'POST' && url.pathname === '/v1/sync/personalization/write') {
      return writeJson(response, 200, { ok: true, code: 'personalization_sync_written', ...writeSnapshot('personalization', body, device) });
    }
    if (request.method === 'POST' && url.pathname === '/v1/sync/novel-bookshelf/read') {
      return writeJson(response, 200, { ok: true, code: 'novel_bookshelf_sync_state', ...readSnapshot('novel_bookshelf') });
    }
    if (request.method === 'POST' && url.pathname === '/v1/sync/novel-bookshelf/write') {
      return writeJson(response, 200, { ok: true, code: 'novel_bookshelf_sync_written', ...writeSnapshot('novel_bookshelf', body, device) });
    }
    if (request.method === 'POST' && url.pathname === '/v1/sync/history/exchange') {
      return writeJson(response, 200, await handleHistoryExchange(body, device));
    }
    if (request.method === 'POST' && url.pathname === '/v1/sync/history/bootstrap') {
      return writeJson(response, 200, await handleHistoryBootstrap(body, device));
    }
    fail(404, 'not_found', 'Route not found.');
  } catch (error) {
    const failure = toPublicError(error);
    writeJson(response, failure.status, failure.body);
  }
}

function discovery() {
  const instance = getInstance();
  return {
    ok: true,
    product: 'aira-personal-server',
    version: VERSION,
    protocolVersion: 1,
    minimumClientProtocolVersion: 1,
    instanceId: instance.instanceId,
    baseUrl: publicBaseUrl,
    auth: { mode: 'paired_device_bearer', pairingExchangePath: '/v1/pairing/exchange' },
    capabilities: {
      bookmarks: { version: 3, path: '/v1/sync/bookmarks' },
      history: { version: 1, path: '/v1/sync/history' },
      personalization: { version: 2, path: '/v1/sync/personalization' },
      novelBookshelf: { version: 2, path: '/v1/sync/novel-bookshelf' },
      deviceManagement: { version: 1, path: '/v1/devices' },
      pagePush: { version: 1, path: '/v1/page-push' },
      crossDeviceTabs: { version: 1, path: '/v1/device-tabs' },
    },
  };
}

module.exports = { handleRequest };
