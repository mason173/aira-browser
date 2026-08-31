const { buildPublicError } = require('../errors');
const { historySyncRepository } = require('../repositories/history-sync-repository');

const OWNER_NAMESPACE = 'owner';
const FUNCTION_VERSION = '1.0.0';

const MAX_MUTATIONS = 200;
const DEFAULT_PULL_LIMIT = 200;
const MAX_PULL_LIMIT = 500;
const MAX_FUTURE_SKEW_MS = 24 * 60 * 60 * 1000;

async function handleHistoryExchange(body, device) {
  const clientId = normalizeClientId(body.clientId);
  assertDeviceClientIdentity(device, clientId);
  const cursor = normalizeNonNegativeInteger(body.cursor, 'invalid_history_cursor', '历史记录同步游标无效。');
  const mutations = normalizeMutations(body.mutations);
  const pullLimit = normalizeLimit(body.pullLimit, DEFAULT_PULL_LIMIT);
  const result = historySyncRepository.exchange({
    uid: OWNER_NAMESPACE,
    clientId,
    cursor,
    mutations,
    pullLimit,
    now: Date.now()
  });
  return {
    ok: true,
    code: 'history_sync_exchange',
    version: FUNCTION_VERSION,
    ...result
  };
}

async function handleHistoryBootstrap(body, device) {
  const clientId = normalizeClientId(body.clientId);
  assertDeviceClientIdentity(device, clientId);
  const bootstrapHead = body.bootstrapHead === undefined || body.bootstrapHead === null
    ? null
    : normalizeNonNegativeInteger(body.bootstrapHead, 'invalid_bootstrap_head', '历史记录初始化游标无效。');
  const afterUpdatedSeq = body.afterUpdatedSeq === undefined || body.afterUpdatedSeq === null
    ? 0
    : normalizeNonNegativeInteger(body.afterUpdatedSeq, 'invalid_bootstrap_key', '历史记录初始化分页位置无效。');
  const afterVisitId = normalizeOptionalString(body.afterVisitId, 512);
  if ((afterUpdatedSeq > 0) !== Boolean(afterVisitId)) {
    throw buildPublicError('invalid_bootstrap_key', '历史记录初始化分页位置不完整。');
  }
  const result = historySyncRepository.bootstrap({
    uid: OWNER_NAMESPACE,
    clientId,
    bootstrapHead,
    afterUpdatedSeq,
    afterVisitId,
    pageLimit: normalizeLimit(body.pageLimit, DEFAULT_PULL_LIMIT),
    now: Date.now()
  });
  return {
    ok: true,
    code: 'history_sync_bootstrap',
    version: FUNCTION_VERSION,
    ...result
  };
}

function normalizeMutations(value) {
  if (value === undefined || value === null) {
    return [];
  }
  if (!Array.isArray(value) || value.length > MAX_MUTATIONS) {
    throw buildPublicError('invalid_history_mutations', `单次最多提交 ${MAX_MUTATIONS} 条历史记录增量。`);
  }
  const seen = new Set();
  return value.map((raw) => {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
      throw buildPublicError('invalid_history_mutation', '历史记录增量格式不正确。');
    }
    const mutationId = normalizeRequiredString(raw.mutationId, 256, 'invalid_history_mutation_id', '历史记录增量 ID 无效。');
    if (seen.has(mutationId)) {
      throw buildPublicError('duplicate_history_mutation_id', '同一批次包含重复的历史记录增量 ID。');
    }
    seen.add(mutationId);
    const kind = String(raw.kind || '').trim();
    if (kind === 'upsert_visit') {
      return { mutationId, kind, visit: normalizeVisit(raw.visit) };
    }
    if (kind === 'delete_visit') {
      return { mutationId, kind, visitId: normalizeVisitId(raw.visitId) };
    }
    if (kind === 'delete_range') {
      const startedAt = normalizeTimestamp(raw.startedAt, 'invalid_history_range', '历史记录删除时间范围无效。');
      const endedAt = normalizeTimestamp(raw.endedAt, 'invalid_history_range', '历史记录删除时间范围无效。');
      if (startedAt > endedAt) {
        throw buildPublicError('invalid_history_range', '历史记录删除时间范围无效。');
      }
      return {
        mutationId,
        kind,
        url: normalizeUrl(raw.url),
        startedAt,
        endedAt
      };
    }
    if (kind === 'clear_before') {
      return {
        mutationId,
        kind,
        clearBefore: normalizeTimestamp(raw.clearBefore, 'invalid_clear_before', '历史记录清空时间无效。')
      };
    }
    throw buildPublicError('unsupported_history_mutation', '不支持的历史记录增量类型。');
  });
}

function normalizeVisit(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw buildPublicError('invalid_history_visit', '历史访问记录格式不正确。');
  }
  const visitId = normalizeVisitId(value.visitId);
  const identity = parseHistoryVisitIdentity(visitId);
  return {
    visitId,
    clientId: identity.clientId,
    nativeVisitId: identity.nativeVisitId,
    url: normalizeUrl(value.url),
    title: normalizeOptionalString(value.title, 2048),
    visitedAt: normalizeTimestamp(value.visitedAt, 'invalid_visited_at', '历史访问时间无效。'),
    transition: normalizeOptionalString(value.transition, 64),
    referrer: normalizeOptionalUrl(value.referrer),
    deviceName: normalizeOptionalString(value.deviceName, 128),
    source: normalizeOptionalString(value.source, 64)
  };
}

function parseHistoryVisitIdentity(visitId) {
  const separator = visitId.indexOf(':', 3);
  return {
    clientId: visitId.slice(3, separator),
    nativeVisitId: visitId.slice(separator + 1),
  };
}

function normalizeVisitId(value) {
  const visitId = normalizeRequiredString(value, 512, 'invalid_history_visit_id', '历史访问 ID 无效。');
  if (!/^h1:[A-Za-z0-9._-]{1,160}:.+$/.test(visitId)) {
    throw buildPublicError('invalid_history_visit_id', '历史访问 ID 无效。');
  }
  return visitId;
}

function normalizeClientId(value) {
  const clientId = normalizeRequiredString(value, 160, 'missing_history_client_id', '缺少历史同步设备标识。');
  if (!/^[A-Za-z0-9._-]+$/.test(clientId)) {
    throw buildPublicError('invalid_history_client_id', '历史同步设备标识无效。');
  }
  return clientId;
}

function assertDeviceClientIdentity(device, clientId) {
  if (!device || device.deviceId !== clientId) {
    throw buildPublicError('history_client_mismatch', 'History client ID must match the paired device credential.');
  }
}

function normalizeUrl(value) {
  const raw = normalizeRequiredString(value, 8192, 'invalid_history_url', '历史记录 URL 无效。');
  let parsed;
  try {
    parsed = new URL(raw);
  } catch (_error) {
    throw buildPublicError('invalid_history_url', '历史记录 URL 无效。');
  }
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    throw buildPublicError('invalid_history_url', '历史记录仅同步 HTTP 或 HTTPS 地址。');
  }
  return parsed.toString();
}

function normalizeOptionalUrl(value) {
  const raw = normalizeOptionalString(value, 8192);
  return raw ? normalizeUrl(raw) : '';
}

function normalizeTimestamp(value, code, message) {
  const timestamp = normalizeNonNegativeInteger(value, code, message);
  if (timestamp <= 0 || timestamp > Date.now() + MAX_FUTURE_SKEW_MS) {
    throw buildPublicError(code, message);
  }
  return timestamp;
}

function normalizeLimit(value, fallback) {
  const number = Number(value === undefined || value === null ? fallback : value);
  if (!Number.isInteger(number) || number <= 0) {
    throw buildPublicError('invalid_history_page_limit', '历史记录分页大小无效。');
  }
  return Math.min(number, MAX_PULL_LIMIT);
}

function normalizeNonNegativeInteger(value, code, message) {
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < 0) {
    throw buildPublicError(code, message);
  }
  return number;
}

function normalizeRequiredString(value, maxLength, code, message) {
  const normalized = String(value || '').trim();
  if (!normalized || normalized.length > maxLength) {
    throw buildPublicError(code, message);
  }
  return normalized;
}

function normalizeOptionalString(value, maxLength) {
  const normalized = String(value || '').trim();
  if (normalized.length > maxLength) {
    throw buildPublicError('history_field_too_long', '历史记录字段过长。');
  }
  return normalized;
}

function normalizeSource(value, fallback) {
  const normalized = String(value || '').trim();
  return normalized.slice(0, 80) || fallback;
}

module.exports = {
  handleHistoryBootstrap,
  handleHistoryExchange
};
