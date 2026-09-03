const { fail } = require('./errors');

const BOOKMARK_SYNC_PROTOCOL = 'aira-cloud-bookmarks-v4';
const BOOKMARK_SYNC_VERSION = 4;

function assertBookmarkSyncProtocol(body) {
  if (String(body && body.protocol || '').trim() !== BOOKMARK_SYNC_PROTOCOL) {
    fail(
      426,
      'client_update_required',
      '当前个人服务器书签同步协议已停止，请升级到支持统一同步的最新 Aira 客户端。'
    );
  }
}

module.exports = {
  BOOKMARK_SYNC_PROTOCOL,
  BOOKMARK_SYNC_VERSION,
  assertBookmarkSyncProtocol
};
