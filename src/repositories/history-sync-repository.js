const { db } = require('../db/database');
const { buildPublicError } = require('../errors');

const DAY_MS = 24 * 60 * 60 * 1000;
const RETENTION_MS = 90 * DAY_MS;
const MAX_LIVE_VISITS = 10000;
const CLIENT_LEASE_MS = 30 * DAY_MS;
const RECEIPT_RETENTION_MS = 120 * DAY_MS;
const CHANGE_RETENTION_MS = 30 * DAY_MS;
const RETENTION_CHANGE_CHUNK = 500;

function createHistorySyncRepository(database) {
  const statements = prepareStatements(database);

  const exchangeTransaction = database.transaction((params) => {
    const now = params.now;
    ensureHead(statements, params.uid, now);
    pruneExpiredMetadata(statements, params.uid, now);
    const initialHead = getHead(statements, params.uid);
    assertCursorAvailable(statements, params.uid, params.cursor, initialHead.headSeq);

    const acknowledgements = [];
    params.mutations.forEach((mutation) => {
      const previous = statements.getReceipt.get(params.uid, params.clientId, mutation.mutationId);
      if (previous) {
        acknowledgements.push(toAcknowledgement(previous, mutation.mutationId));
        return;
      }
      const result = applyMutation(statements, params.uid, params.clientId, mutation, now);
      statements.insertReceipt.run(
        params.uid,
        params.clientId,
        mutation.mutationId,
        result.acceptedSeq,
        result.applied ? 1 : 0,
        now
      );
      acknowledgements.push({
        mutationId: mutation.mutationId,
        acceptedSeq: result.acceptedSeq,
        applied: result.applied
      });
    });

    applyRetention(statements, params.uid, now);
    const head = getHead(statements, params.uid);
    const rows = statements.listChanges.all(params.uid, params.cursor, params.pullLimit + 1);
    const hasMore = rows.length > params.pullLimit;
    const selected = hasMore ? rows.slice(0, params.pullLimit) : rows;
    const changes = selected.map(toChange);
    const nextCursor = changes.length > 0 ? changes[changes.length - 1].seq : params.cursor;
    touchClient(statements, params.uid, params.clientId, nextCursor, now);
    pruneChanges(statements, params.uid, now);
    return {
      acknowledgements,
      changes,
      nextCursor,
      headCursor: head.headSeq,
      hasMore
    };
  });

  const bootstrapTransaction = database.transaction((params) => {
    const now = params.now;
    ensureHead(statements, params.uid, now);
    pruneExpiredMetadata(statements, params.uid, now);
    const currentHead = getHead(statements, params.uid);
    const bootstrapHead = params.bootstrapHead === null ? currentHead.headSeq : params.bootstrapHead;
    if (bootstrapHead < 0 || bootstrapHead > currentHead.headSeq) {
      throw buildPublicError('invalid_bootstrap_head', '历史记录初始化游标无效，请重新开始初始化。');
    }
    const rows = statements.listBootstrapEntities.all({
      uid: params.uid,
      bootstrap_head: bootstrapHead,
      after_updated_seq: params.afterUpdatedSeq,
      after_visit_id: params.afterVisitId,
      has_key: params.afterVisitId ? 1 : 0,
      limit: params.pageLimit + 1
    });
    const hasMore = rows.length > params.pageLimit;
    const selected = hasMore ? rows.slice(0, params.pageLimit) : rows;
    const visits = selected.filter((row) => Number(row.deleted || 0) === 0).map(toVisit);
    const deletedVisitIds = selected
      .filter((row) => Number(row.deleted || 0) === 1)
      .map((row) => String(row.visit_id || ''));
    const last = selected.length > 0 ? selected[selected.length - 1] : null;
    const firstPage = !params.afterVisitId;
    const clearBefore = resolveClearBeforeAtHead(statements, params.uid, bootstrapHead, currentHead);
    const deleteRanges = firstPage
      ? statements.listDeleteRangesAtHead.all(params.uid, bootstrapHead, now - RETENTION_MS).map(toDeleteRange)
      : [];
    if (!hasMore) {
      touchClient(statements, params.uid, params.clientId, bootstrapHead, now);
    }
    return {
      bootstrapHead,
      headCursor: currentHead.headSeq,
      visits,
      deletedVisitIds,
      clearBefore,
      deleteRanges,
      nextKey: last ? {
        updatedSeq: Number(last.updated_seq || 0),
        visitId: String(last.visit_id || '')
      } : null,
      hasMore
    };
  });

  const deleteAccountTransaction = database.transaction((uid) => {
    const normalizedUid = String(uid || '').trim();
    let deleted = 0;
    deleted += statements.deleteReceiptsByUid.run(normalizedUid).changes;
    deleted += statements.deleteClientsByUid.run(normalizedUid).changes;
    deleted += statements.deleteRangesByUid.run(normalizedUid).changes;
    deleted += statements.deleteChangesByUid.run(normalizedUid).changes;
    deleted += statements.deleteEntitiesByUid.run(normalizedUid).changes;
    deleted += statements.deleteHeadByUid.run(normalizedUid).changes;
    return deleted;
  });

  return {
    bootstrap(params) {
      return bootstrapTransaction(params);
    },
    exchange(params) {
      return exchangeTransaction(params);
    },
    deleteAccount(uid) {
      return deleteAccountTransaction(uid);
    },
    countAccounts() {
      return Number(statements.countAccounts.get().count || 0);
    }
  };
}

function prepareStatements(database) {
  return {
    ensureHead: database.prepare(`
      INSERT INTO history_sync_heads_v1(uid, head_seq, clear_before, clear_before_seq, updated_at)
      VALUES(?, 0, 0, 0, ?)
      ON CONFLICT(uid) DO NOTHING
    `),
    getHead: database.prepare(`
      SELECT head_seq, clear_before, clear_before_seq
      FROM history_sync_heads_v1
      WHERE uid = ?
    `),
    updateHeadSequence: database.prepare(`
      UPDATE history_sync_heads_v1 SET head_seq = ?, updated_at = ? WHERE uid = ?
    `),
    updateClearBefore: database.prepare(`
      UPDATE history_sync_heads_v1
      SET clear_before = ?, clear_before_seq = ?, updated_at = ?
      WHERE uid = ?
    `),
    getEntity: database.prepare(`
      SELECT * FROM history_sync_entities_v1 WHERE uid = ? AND visit_id = ?
    `),
    insertLiveEntity: database.prepare(`
      INSERT INTO history_sync_entities_v1(
        uid, visit_id, client_id, native_visit_id, url, title, visited_at, transition, referrer,
        device_name, source, deleted, deletion_kind, deleted_at, updated_seq, updated_at
      ) VALUES(
        @uid, @visit_id, @client_id, @native_visit_id, @url, @title, @visited_at, @transition, @referrer,
        @device_name, @source, 0, '', 0, @updated_seq, @updated_at
      )
    `),
    insertDeletedEntity: database.prepare(`
      INSERT INTO history_sync_entities_v1(
        uid, visit_id, client_id, native_visit_id, deleted, deletion_kind, deleted_at, updated_seq, updated_at
      ) VALUES(@uid, @visit_id, @client_id, @native_visit_id, 1, @deletion_kind, @deleted_at, @updated_seq, @updated_at)
    `),
    markEntityDeleted: database.prepare(`
      UPDATE history_sync_entities_v1
      SET deleted = 1, deletion_kind = ?, deleted_at = ?, updated_seq = ?, updated_at = ?
      WHERE uid = ? AND visit_id = ? AND deleted = 0
    `),
    markRangeDeleted: database.prepare(`
      UPDATE history_sync_entities_v1
      SET deleted = 1, deletion_kind = 'delete_range', deleted_at = @deleted_at,
        updated_seq = @updated_seq, updated_at = @updated_at
      WHERE uid = @uid AND deleted = 0 AND url = @url
        AND visited_at >= @started_at AND visited_at <= @ended_at
    `),
    markClearDeleted: database.prepare(`
      UPDATE history_sync_entities_v1
      SET deleted = 1, deletion_kind = 'clear_before', deleted_at = @deleted_at,
        updated_seq = @updated_seq, updated_at = @updated_at
      WHERE uid = @uid AND deleted = 0 AND visited_at <= @clear_before
    `),
    getMatchingDeleteRange: database.prepare(`
      SELECT range_id FROM history_sync_delete_ranges_v1
      WHERE uid = ? AND url = ? AND started_at <= ? AND ended_at >= ?
      LIMIT 1
    `),
    getDeleteRange: database.prepare(`
      SELECT * FROM history_sync_delete_ranges_v1 WHERE uid = ? AND range_id = ?
    `),
    insertDeleteRange: database.prepare(`
      INSERT INTO history_sync_delete_ranges_v1(
        uid, range_id, url, started_at, ended_at, created_seq, created_at
      ) VALUES(?, ?, ?, ?, ?, ?, ?)
    `),
    appendChange: database.prepare(`
      INSERT INTO history_sync_changes_v1(uid, seq, kind, visit_id, payload_json, created_at)
      VALUES(?, ?, ?, ?, ?, ?)
    `),
    listChanges: database.prepare(`
      SELECT seq, kind, visit_id, payload_json
      FROM history_sync_changes_v1
      WHERE uid = ? AND seq > ?
      ORDER BY seq ASC
      LIMIT ?
    `),
    getEarliestChange: database.prepare(`
      SELECT MIN(seq) AS seq FROM history_sync_changes_v1 WHERE uid = ?
    `),
    listBootstrapEntities: database.prepare(`
      SELECT visit_id, client_id, native_visit_id, url, title, visited_at, transition, referrer, device_name, source,
        deleted, updated_seq
      FROM history_sync_entities_v1
      WHERE uid = @uid AND updated_seq <= @bootstrap_head
        AND (deleted = 0 OR deletion_kind = 'delete_visit')
        AND (@has_key = 0 OR updated_seq < @after_updated_seq
          OR (updated_seq = @after_updated_seq AND visit_id < @after_visit_id))
      ORDER BY updated_seq DESC, visit_id DESC
      LIMIT @limit
    `),
    listDeleteRangesAtHead: database.prepare(`
      SELECT range_id, url, started_at, ended_at, created_seq
      FROM history_sync_delete_ranges_v1
      WHERE uid = ? AND created_seq <= ? AND ended_at >= ?
      ORDER BY created_seq ASC
    `),
    getLatestClearChangeAtHead: database.prepare(`
      SELECT payload_json FROM history_sync_changes_v1
      WHERE uid = ? AND kind = 'clear_before' AND seq <= ?
      ORDER BY seq DESC LIMIT 1
    `),
    getReceipt: database.prepare(`
      SELECT accepted_seq, applied FROM history_sync_mutation_receipts_v1
      WHERE uid = ? AND client_id = ? AND mutation_id = ?
    `),
    insertReceipt: database.prepare(`
      INSERT INTO history_sync_mutation_receipts_v1(
        uid, client_id, mutation_id, accepted_seq, applied, created_at
      ) VALUES(?, ?, ?, ?, ?, ?)
    `),
    touchClient: database.prepare(`
      INSERT INTO history_sync_clients_v1(uid, client_id, cursor, last_seen_at, expires_at)
      VALUES(?, ?, ?, ?, ?)
      ON CONFLICT(uid, client_id) DO UPDATE SET
        cursor = MAX(history_sync_clients_v1.cursor, excluded.cursor),
        last_seen_at = excluded.last_seen_at,
        expires_at = excluded.expires_at
    `),
    deleteExpiredClients: database.prepare(`DELETE FROM history_sync_clients_v1 WHERE expires_at < ?`),
    deleteExpiredReceipts: database.prepare(`DELETE FROM history_sync_mutation_receipts_v1 WHERE created_at < ?`),
    minActiveCursor: database.prepare(`
      SELECT MIN(cursor) AS cursor FROM history_sync_clients_v1 WHERE uid = ? AND expires_at >= ?
    `),
    pruneChanges: database.prepare(`
      DELETE FROM history_sync_changes_v1 WHERE uid = ? AND seq <= ? AND created_at < ?
    `),
    deleteExpiredRanges: database.prepare(`
      DELETE FROM history_sync_delete_ranges_v1 WHERE uid = ? AND ended_at < ?
    `),
    listRetentionAgeVictims: database.prepare(`
      SELECT visit_id FROM history_sync_entities_v1
      WHERE uid = ? AND deleted = 0 AND visited_at < ?
      ORDER BY visited_at ASC, visit_id ASC
    `),
    listRetentionOverflowVictims: database.prepare(`
      SELECT visit_id FROM history_sync_entities_v1
      WHERE uid = ? AND deleted = 0
      ORDER BY visited_at DESC, visit_id DESC
      LIMIT -1 OFFSET ?
    `),
    countAccounts: database.prepare(`SELECT COUNT(*) AS count FROM history_sync_heads_v1`),
    deleteReceiptsByUid: database.prepare(`DELETE FROM history_sync_mutation_receipts_v1 WHERE uid = ?`),
    deleteClientsByUid: database.prepare(`DELETE FROM history_sync_clients_v1 WHERE uid = ?`),
    deleteRangesByUid: database.prepare(`DELETE FROM history_sync_delete_ranges_v1 WHERE uid = ?`),
    deleteChangesByUid: database.prepare(`DELETE FROM history_sync_changes_v1 WHERE uid = ?`),
    deleteEntitiesByUid: database.prepare(`DELETE FROM history_sync_entities_v1 WHERE uid = ?`),
    deleteHeadByUid: database.prepare(`DELETE FROM history_sync_heads_v1 WHERE uid = ?`)
  };
}

function applyMutation(statements, uid, clientId, mutation, now) {
  if (mutation.kind === 'upsert_visit') {
    return applyUpsert(statements, uid, mutation.visit, now);
  }
  if (mutation.kind === 'delete_visit') {
    return applyDeleteVisit(statements, uid, mutation.visitId, now);
  }
  if (mutation.kind === 'delete_range') {
    return applyDeleteRange(statements, uid, clientId, mutation, now);
  }
  return applyClearBefore(statements, uid, mutation.clearBefore, now);
}

function applyUpsert(statements, uid, visit, now) {
  const existing = statements.getEntity.get(uid, visit.visitId);
  if (existing) {
    if (existing.deleted) {
      return { acceptedSeq: Number(existing.updated_seq || 0), applied: false };
    }
    // visitId is the durable event identity. The first accepted row remains
    // canonical; stale retries from older clients are acknowledged as no-ops.
    return { acceptedSeq: Number(existing.updated_seq || 0), applied: false };
  }
  const head = getHead(statements, uid);
  if (visit.visitedAt <= head.clearBefore ||
      statements.getMatchingDeleteRange.get(uid, visit.url, visit.visitedAt, visit.visitedAt)) {
    return { acceptedSeq: head.headSeq, applied: false };
  }
  const seq = nextSequence(statements, uid, now);
  statements.insertLiveEntity.run({
    uid,
    visit_id: visit.visitId,
    client_id: visit.clientId,
    native_visit_id: visit.nativeVisitId,
    url: visit.url,
    title: visit.title,
    visited_at: visit.visitedAt,
    transition: visit.transition,
    referrer: visit.referrer,
    device_name: visit.deviceName,
    source: visit.source,
    updated_seq: seq,
    updated_at: now
  });
  appendChange(statements, uid, seq, 'upsert_visit', visit.visitId, { visit }, now);
  return { acceptedSeq: seq, applied: true };
}

function applyDeleteVisit(statements, uid, visitId, now) {
  const existing = statements.getEntity.get(uid, visitId);
  if (existing && existing.deleted) {
    return { acceptedSeq: Number(existing.updated_seq || 0), applied: false };
  }
  const seq = nextSequence(statements, uid, now);
  if (existing) {
    statements.markEntityDeleted.run('delete_visit', now, seq, now, uid, visitId);
  } else {
    const identity = splitVisitId(visitId);
    statements.insertDeletedEntity.run({
      uid,
      visit_id: visitId,
      client_id: identity.clientId,
      native_visit_id: identity.nativeVisitId,
      deletion_kind: 'delete_visit',
      deleted_at: now,
      updated_seq: seq,
      updated_at: now
    });
  }
  appendChange(statements, uid, seq, 'delete_visit', visitId, { visitId }, now);
  return { acceptedSeq: seq, applied: true };
}

function applyDeleteRange(statements, uid, clientId, mutation, now) {
  const rangeId = `h1r:${clientId}:${mutation.mutationId}`;
  const existing = statements.getDeleteRange.get(uid, rangeId);
  if (existing) {
    return { acceptedSeq: Number(existing.created_seq || 0), applied: false };
  }
  const seq = nextSequence(statements, uid, now);
  statements.insertDeleteRange.run(
    uid,
    rangeId,
    mutation.url,
    mutation.startedAt,
    mutation.endedAt,
    seq,
    now
  );
  statements.markRangeDeleted.run({
    uid,
    url: mutation.url,
    started_at: mutation.startedAt,
    ended_at: mutation.endedAt,
    deleted_at: now,
    updated_seq: seq,
    updated_at: now
  });
  appendChange(statements, uid, seq, 'delete_range', '', {
    rangeId,
    url: mutation.url,
    startedAt: mutation.startedAt,
    endedAt: mutation.endedAt
  }, now);
  return { acceptedSeq: seq, applied: true };
}

function applyClearBefore(statements, uid, clearBefore, now) {
  const head = getHead(statements, uid);
  if (clearBefore <= head.clearBefore) {
    return { acceptedSeq: head.clearBeforeSeq, applied: false };
  }
  const seq = nextSequence(statements, uid, now);
  statements.updateClearBefore.run(clearBefore, seq, now, uid);
  statements.markClearDeleted.run({
    uid,
    clear_before: clearBefore,
    deleted_at: now,
    updated_seq: seq,
    updated_at: now
  });
  appendChange(statements, uid, seq, 'clear_before', '', { clearBefore }, now);
  return { acceptedSeq: seq, applied: true };
}

function applyRetention(statements, uid, now) {
  const cutoff = now - RETENTION_MS;
  const ids = new Set();
  statements.listRetentionAgeVictims.all(uid, cutoff).forEach((row) => ids.add(row.visit_id));
  statements.listRetentionOverflowVictims.all(uid, MAX_LIVE_VISITS).forEach((row) => ids.add(row.visit_id));
  const victims = Array.from(ids);
  for (let offset = 0; offset < victims.length; offset += RETENTION_CHANGE_CHUNK) {
    const visitIds = victims.slice(offset, offset + RETENTION_CHANGE_CHUNK);
    const seq = nextSequence(statements, uid, now);
    visitIds.forEach((visitId) => {
      statements.markEntityDeleted.run('retention', now, seq, now, uid, visitId);
    });
    appendChange(statements, uid, seq, 'retention_prune', '', { visitIds, cutoff }, now);
  }
  statements.deleteExpiredRanges.run(uid, cutoff);
}

function appendChange(statements, uid, seq, kind, visitId, payload, now) {
  statements.appendChange.run(uid, seq, kind, visitId || '', JSON.stringify(payload), now);
}

function nextSequence(statements, uid, now) {
  const head = getHead(statements, uid);
  const next = head.headSeq + 1;
  statements.updateHeadSequence.run(next, now, uid);
  return next;
}

function ensureHead(statements, uid, now) {
  statements.ensureHead.run(uid, now);
}

function getHead(statements, uid) {
  const row = statements.getHead.get(uid);
  return {
    headSeq: Number(row ? row.head_seq : 0),
    clearBefore: Number(row ? row.clear_before : 0),
    clearBeforeSeq: Number(row ? row.clear_before_seq : 0)
  };
}

function assertCursorAvailable(statements, uid, cursor, headSeq) {
  if (cursor > headSeq) {
    throw buildPublicError('history_cursor_ahead', '历史记录同步游标超前，请重新初始化。');
  }
  if (headSeq === 0) {
    return;
  }
  const earliest = statements.getEarliestChange.get(uid);
  const earliestSeq = Number(earliest && earliest.seq || 0);
  if (cursor === 0 || (earliestSeq > 0 && cursor < earliestSeq - 1)) {
    throw buildPublicError('history_cursor_expired', '历史记录同步游标已过期，请执行分页初始化。');
  }
}

function touchClient(statements, uid, clientId, cursor, now) {
  statements.touchClient.run(uid, clientId, cursor, now, now + CLIENT_LEASE_MS);
}

function pruneExpiredMetadata(statements, uid, now) {
  statements.deleteExpiredClients.run(now);
  statements.deleteExpiredReceipts.run(now - RECEIPT_RETENTION_MS);
}

function pruneChanges(statements, uid, now) {
  const active = statements.minActiveCursor.get(uid, now);
  if (active && active.cursor !== null && active.cursor !== undefined) {
    statements.pruneChanges.run(uid, Math.max(0, Number(active.cursor) - 1), now - CHANGE_RETENTION_MS);
  }
}

function resolveClearBeforeAtHead(statements, uid, bootstrapHead, currentHead) {
  if (bootstrapHead >= currentHead.clearBeforeSeq) {
    return currentHead.clearBefore;
  }
  const row = statements.getLatestClearChangeAtHead.get(uid, bootstrapHead);
  if (!row) {
    return 0;
  }
  const payload = parsePayload(row.payload_json);
  return Number(payload.clearBefore || 0);
}

function splitVisitId(visitId) {
  const value = String(visitId || '');
  const secondColon = value.indexOf(':', 3);
  return {
    clientId: secondColon > 3 ? value.slice(3, secondColon) : '',
    nativeVisitId: secondColon > 3 ? value.slice(secondColon + 1) : ''
  };
}

function toAcknowledgement(row, mutationId) {
  return {
    mutationId,
    acceptedSeq: Number(row.accepted_seq || 0),
    applied: Number(row.applied || 0) === 1
  };
}

function toChange(row) {
  return {
    seq: Number(row.seq || 0),
    kind: String(row.kind || ''),
    visitId: String(row.visit_id || ''),
    ...parsePayload(row.payload_json)
  };
}

function toVisit(row) {
  return {
    visitId: String(row.visit_id || ''),
    clientId: String(row.client_id || ''),
    nativeVisitId: String(row.native_visit_id || ''),
    url: String(row.url || ''),
    title: String(row.title || ''),
    visitedAt: Number(row.visited_at || 0),
    transition: String(row.transition || ''),
    referrer: String(row.referrer || ''),
    deviceName: String(row.device_name || ''),
    source: String(row.source || '')
  };
}

function toDeleteRange(row) {
  return {
    rangeId: String(row.range_id || ''),
    url: String(row.url || ''),
    startedAt: Number(row.started_at || 0),
    endedAt: Number(row.ended_at || 0),
    seq: Number(row.created_seq || 0)
  };
}

function parsePayload(value) {
  try {
    return JSON.parse(String(value || '{}'));
  } catch (_error) {
    throw buildPublicError('stored_history_change_invalid', '服务器保存的历史记录增量无法解析。');
  }
}

module.exports = {
  createHistorySyncRepository,
  historySyncRepository: createHistorySyncRepository(db)
};
