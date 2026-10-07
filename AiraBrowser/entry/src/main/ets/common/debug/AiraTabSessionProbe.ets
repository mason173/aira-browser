/**
 * Tab-session forensics probe (temporary).
 *
 * Reported symptom: with several tabs open, killing the app and relaunching comes back with the tab
 * list empty. The write path (persistence coordinator -> repository -> RDB), the ability's
 * kill-time snapshot flush and the cold-start restore chain all already compute everything needed
 * to explain that, but several of them discard failure details: the write path swallows errors, the
 * startup chain aborts on its first rejection and its catch ignores the error, and the RDB read
 * returns an empty list when its query fails. From the outside a skipped write, a failed write and
 * an aborted restore are therefore indistinguishable. This probe records each stage's own decision
 * under one tag so a single capture answers which stage lost the tabs.
 *
 * This module deliberately imports no platform kit: several build guards load core/data modules in a
 * sandbox that rejects platform dependencies. The platform writer (HiLog) is installed once from the
 * ability through {@link AiraTabSessionProbe.install}.
 *
 * Everything recorded is a count, a flag or an internal identifier (window / profile / tab id).
 * Page URLs and titles are deliberately never recorded. Remove this probe together with its call
 * sites once the stage is identified.
 */
export type AiraTabSessionWriter = (line: string) => void;

const MAX_IDS: number = 8;
const MAX_DETAIL_CHARS: number = 200;

export class AiraTabSessionProbe {
  private static writer: AiraTabSessionWriter | undefined = undefined;
  private static sequence: number = 0;

  static install(writer: AiraTabSessionWriter): void {
    AiraTabSessionProbe.writer = writer;
  }

  static log(event: string, detail: string): void {
    const writer = AiraTabSessionProbe.writer;
    if (writer === undefined) {
      return;
    }
    AiraTabSessionProbe.sequence += 1;
    try {
      writer(`seq=${AiraTabSessionProbe.sequence} t=${Date.now()} event=${event} ${detail}`);
    } catch (_error) {
    }
  }

  static describeError(error: Error | undefined): string {
    if (error === undefined) {
      return 'unknown';
    }
    return AiraTabSessionProbe.truncate(AiraTabSessionProbe.flatten(JSON.stringify(error) ?? String(error)));
  }

  static describeIds(ids: string[]): string {
    const head = ids.slice(0, MAX_IDS).join(',');
    return ids.length > MAX_IDS ? `${head},+${ids.length - MAX_IDS}` : head;
  }

  /** Ability / shell lifecycle boundaries around the kill. */
  static logLifecycle(source: string, windowId: string): void {
    AiraTabSessionProbe.log('lifecycle', `source=${source} window=${windowId}`);
  }

  /** What the in-memory last-known snapshot holds (the ability's kill-time flush source). */
  static logRuntimeSnapshot(status: string, windowId: string, profileId: string, records: number): void {
    AiraTabSessionProbe.log(
      'runtime_snapshot',
      `status=${status} window=${windowId} profile=${profileId} records=${records}`
    );
  }

  static logPersistSkip(windowId: string, reason: string): void {
    AiraTabSessionProbe.log('persist_skip', `window=${windowId} reason=${reason}`);
  }

  static logPersistBegin(
    windowId: string,
    profileId: string,
    tabs: number,
    persistable: number,
    droppedEphemeral: number,
    droppedAutoClosed: number,
    persistPrivateTabs: boolean
  ): void {
    AiraTabSessionProbe.log(
      'persist_begin',
      `window=${windowId} profile=${profileId} tabs=${tabs} persistable=${persistable} ` +
        `dropped_ephemeral=${droppedEphemeral} dropped_autoclose=${droppedAutoClosed} ` +
        `private_policy=${persistPrivateTabs ? 1 : 0}`
    );
  }

  static logPersistWrite(profileId: string, submitted: number, written: number, status: string, detail: string): void {
    AiraTabSessionProbe.log(
      'persist_write',
      `profile=${profileId} submitted=${submitted} written=${written} status=${status} ${detail}`
    );
  }

  static logDbOpen(status: string, detail: string): void {
    AiraTabSessionProbe.log('db_open', `status=${status} ${detail}`);
  }

  static logDbList(windowId: string, profileId: string, count: number, status: string, detail: string): void {
    AiraTabSessionProbe.log(
      'db_list',
      `window=${windowId} profile=${profileId} count=${count} status=${status} ${detail}`
    );
  }

  static logDbReplace(
    windowId: string,
    profileId: string,
    next: number,
    existing: number,
    deleted: number,
    status: string,
    detail: string
  ): void {
    AiraTabSessionProbe.log(
      'db_replace',
      `window=${windowId} profile=${profileId} next=${next} existing=${existing} deleted=${deleted} ` +
        `status=${status} ${detail}`
    );
  }

  static logRepoInit(status: string, detail: string): void {
    AiraTabSessionProbe.log('repo_init', `status=${status} ${detail}`);
  }

  static logRepoRefresh(
    windowId: string,
    profileId: string,
    cacheBefore: number,
    fromDb: number,
    cacheAfter: number,
    status: string
  ): void {
    AiraTabSessionProbe.log(
      'repo_refresh',
      `window=${windowId} profile=${profileId} cache_before=${cacheBefore} from_db=${fromDb} ` +
        `cache_after=${cacheAfter} status=${status}`
    );
  }

  /** The ability's kill-time flush: the last line of defence before process termination. */
  static logAbilityFlush(
    source: string,
    status: string,
    records: number,
    windowId: string,
    profileId: string,
    detail: string
  ): void {
    AiraTabSessionProbe.log(
      'ability_flush',
      `source=${source} status=${status} records=${records} window=${windowId} profile=${profileId} ${detail}`
    );
  }

  /** One step of the cold-start chain; a rejection here aborts the tab read entirely. */
  static logStartupStep(name: string, status: string, detail: string): void {
    AiraTabSessionProbe.log('startup_step', `name=${name} status=${status} ${detail}`);
  }

  static logStartupRecords(
    windowId: string,
    profileId: string,
    total: number,
    ephemeral: number,
    ids: string[]
  ): void {
    AiraTabSessionProbe.log(
      'startup_records',
      `window=${windowId} profile=${profileId} total=${total} ephemeral=${ephemeral} ids=${AiraTabSessionProbe.describeIds(ids)}`
    );
  }

  static logStartupApplied(
    tabs: number,
    hadStoredRecords: boolean,
    openHome: boolean,
    skipped: number,
    ids: string[]
  ): void {
    AiraTabSessionProbe.log(
      'startup_applied',
      `tabs=${tabs} had_records=${hadStoredRecords ? 1 : 0} open_home=${openHome ? 1 : 0} ` +
        `skipped=${skipped} ids=${AiraTabSessionProbe.describeIds(ids)}`
    );
  }

  static logStartupFailed(source: string, detail: string): void {
    AiraTabSessionProbe.log('startup_failed', `source=${source} ${detail}`);
  }

  private static flatten(text: string): string {
    return text.replace(/[\r\n\t]+/g, ' ').trim();
  }

  private static truncate(text: string): string {
    return text.length > MAX_DETAIL_CHARS ? `${text.slice(0, MAX_DETAIL_CHARS)}...` : text;
  }
}
