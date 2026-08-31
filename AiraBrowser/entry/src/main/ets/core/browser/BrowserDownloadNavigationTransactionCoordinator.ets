import { BrowserTabState } from '../tabs/TabManager';

export type BrowserDownloadNavigationTransactionPhase =
  'navigating_candidate' |
  'download_detected' |
  'prompting' |
  'confirmed' |
  'canceled' |
  'promoted_document' |
  'restored' |
  'expired';

export interface BrowserDownloadNavigationTransaction {
  id: string;
  tabId: string;
  candidateUrl: string;
  normalizedCandidateUrl: string;
  previousRestorableUrl: string;
  previousRestorableTitle: string;
  previousSnapshotPath: string;
  promptGuid: string;
  downloadGuid: string;
  phase: BrowserDownloadNavigationTransactionPhase;
  createdAt: number;
  updatedAt: number;
  expiresAt: number;
  restoredAt: number;
  terminalAt: number;
}

export interface BrowserDownloadNavigationTransactionStartInput {
  tab: BrowserTabState;
  candidateUrl: string;
  fallbackUrl: string;
  fallbackTitle: string;
  promptGuid?: string;
  downloadGuid?: string;
  now?: number;
}

export interface BrowserDownloadNavigationTransactionLookup {
  transaction?: BrowserDownloadNavigationTransaction;
  isActive: boolean;
}

const DOWNLOAD_NAVIGATION_TRANSACTION_TTL_MS = 5 * 60 * 1000;
const TERMINAL_TRANSACTION_RETENTION_MS = 30 * 1000;

export class BrowserDownloadNavigationTransactionCoordinator {
  private transactionsById: Record<string, BrowserDownloadNavigationTransaction | undefined> = {};
  private activeTransactionIdByTabId: Record<string, string | undefined> = {};
  private transactionIdByNormalizedUrl: Record<string, string | undefined> = {};
  private nextSequence: number = 1;

  beginPromptingTransaction(input: BrowserDownloadNavigationTransactionStartInput): BrowserDownloadNavigationTransaction {
    const now = input.now ?? Date.now();
    this.pruneExpiredTransactions(now);
    const tabId = input.tab.id.trim();
    const normalizedCandidateUrl = this.normalizeUrl(input.candidateUrl);
    const existing = this.findReusableTransaction(tabId, normalizedCandidateUrl, now);
    if (existing !== undefined) {
      const nextExisting = this.copyTransaction(existing);
      nextExisting.phase = 'prompting';
      nextExisting.previousRestorableUrl = input.fallbackUrl.trim();
      nextExisting.previousRestorableTitle = input.fallbackTitle.trim();
      nextExisting.previousSnapshotPath = input.tab.webStatePath;
      nextExisting.promptGuid = input.promptGuid?.trim() ?? nextExisting.promptGuid;
      nextExisting.downloadGuid = input.downloadGuid?.trim() ?? nextExisting.downloadGuid;
      nextExisting.updatedAt = now;
      nextExisting.expiresAt = now + DOWNLOAD_NAVIGATION_TRANSACTION_TTL_MS;
      this.storeTransaction(nextExisting);
      return nextExisting;
    }
    const transaction: BrowserDownloadNavigationTransaction = {
      id: this.buildTransactionId(now),
      tabId: tabId,
      candidateUrl: input.candidateUrl.trim(),
      normalizedCandidateUrl: normalizedCandidateUrl,
      previousRestorableUrl: input.fallbackUrl.trim(),
      previousRestorableTitle: input.fallbackTitle.trim(),
      previousSnapshotPath: input.tab.webStatePath,
      promptGuid: input.promptGuid?.trim() ?? '',
      downloadGuid: input.downloadGuid?.trim() ?? '',
      phase: 'prompting',
      createdAt: now,
      updatedAt: now,
      expiresAt: now + DOWNLOAD_NAVIGATION_TRANSACTION_TTL_MS,
      restoredAt: 0,
      terminalAt: 0
    };
    this.storeTransaction(transaction);
    return transaction;
  }

  markDownloadDetected(tabId: string, candidateUrl: string, now: number = Date.now()): BrowserDownloadNavigationTransaction | undefined {
    return this.transitionByTabAndUrl(tabId, candidateUrl, 'download_detected', now, true);
  }

  markConfirmed(tabId: string, candidateUrl: string, downloadGuid: string = '', now: number = Date.now()): BrowserDownloadNavigationTransaction | undefined {
    const transaction = this.transitionByTabAndUrl(tabId, candidateUrl, 'confirmed', now, true);
    if (transaction === undefined) {
      return undefined;
    }
    const nextTransaction = this.copyTransaction(transaction);
    nextTransaction.downloadGuid = downloadGuid.trim().length > 0 ? downloadGuid.trim() : nextTransaction.downloadGuid;
    nextTransaction.updatedAt = now;
    this.storeTransaction(nextTransaction);
    return nextTransaction;
  }

  markCanceled(tabId: string, candidateUrl: string, now: number = Date.now()): BrowserDownloadNavigationTransaction | undefined {
    return this.transitionByTabAndUrl(tabId, candidateUrl, 'canceled', now, false);
  }

  markRestored(tabId: string, candidateUrl: string, now: number = Date.now()): BrowserDownloadNavigationTransaction | undefined {
    const transaction = this.transitionByTabAndUrl(tabId, candidateUrl, 'restored', now, false);
    if (transaction === undefined) {
      return undefined;
    }
    const nextTransaction = this.copyTransaction(transaction);
    nextTransaction.restoredAt = now;
    nextTransaction.terminalAt = now;
    nextTransaction.expiresAt = now + TERMINAL_TRANSACTION_RETENTION_MS;
    this.storeTransaction(nextTransaction);
    return nextTransaction;
  }

  markStableDocumentPromoted(tabId: string, url: string, now: number = Date.now()): void {
    this.pruneExpiredTransactions(now);
    const normalizedUrl = this.normalizeUrl(url);
    const activeTransaction = this.getActiveTransaction(tabId);
    if (activeTransaction === undefined) {
      return;
    }
    if (activeTransaction.normalizedCandidateUrl === normalizedUrl) {
      return;
    }
    const nextTransaction = this.copyTransaction(activeTransaction);
    nextTransaction.phase = 'promoted_document';
    nextTransaction.updatedAt = now;
    nextTransaction.terminalAt = now;
    nextTransaction.expiresAt = now + TERMINAL_TRANSACTION_RETENTION_MS;
    this.storeTransaction(nextTransaction);
    this.activeTransactionIdByTabId[nextTransaction.tabId] = undefined;
  }

  markCandidateDocumentPromoted(tabId: string, url: string, now: number = Date.now()): void {
    this.pruneExpiredTransactions(now);
    const lookup = this.lookupByTabAndUrl(tabId, url, now);
    if (lookup.transaction === undefined) {
      return;
    }
    const nextTransaction = this.copyTransaction(lookup.transaction);
    nextTransaction.phase = 'promoted_document';
    nextTransaction.updatedAt = now;
    nextTransaction.terminalAt = 0;
    nextTransaction.expiresAt = now + TERMINAL_TRANSACTION_RETENTION_MS;
    this.storeTransaction(nextTransaction);
    this.activeTransactionIdByTabId[nextTransaction.tabId] = undefined;
  }

  lookupByTabAndUrl(tabId: string, url: string, now: number = Date.now()): BrowserDownloadNavigationTransactionLookup {
    this.pruneExpiredTransactions(now);
    const normalizedTabId = tabId.trim();
    const normalizedUrl = this.normalizeUrl(url);
    const transactionId = this.transactionIdByNormalizedUrl[normalizedUrl];
    const transaction = transactionId !== undefined ? this.transactionsById[transactionId] : undefined;
    if (transaction === undefined || transaction.tabId !== normalizedTabId) {
      return {
        isActive: false
      };
    }
    return {
      transaction: transaction,
      isActive: !this.isTerminalPhase(transaction.phase)
    };
  }

  getActiveTransaction(tabId: string, now: number = Date.now()): BrowserDownloadNavigationTransaction | undefined {
    this.pruneExpiredTransactions(now);
    const transactionId = this.activeTransactionIdByTabId[tabId.trim()];
    if (transactionId === undefined) {
      return undefined;
    }
    return this.transactionsById[transactionId];
  }

  shouldSuppressNavigation(tabId: string, url: string, now: number = Date.now()): boolean {
    const lookup = this.lookupByTabAndUrl(tabId, url, now);
    if (lookup.transaction === undefined) {
      return false;
    }
    return lookup.isActive || this.isRecentlyTerminal(lookup.transaction, now);
  }

  shouldSuppressUrl(url: string, now: number = Date.now()): boolean {
    this.pruneExpiredTransactions(now);
    const transactionId = this.transactionIdByNormalizedUrl[this.normalizeUrl(url)];
    if (transactionId === undefined) {
      return false;
    }
    const transaction = this.transactionsById[transactionId];
    if (transaction === undefined) {
      return false;
    }
    return !this.isTerminalPhase(transaction.phase) || this.isRecentlyTerminal(transaction, now);
  }

  shouldSkipSnapshotPersistence(tabId: string, now: number = Date.now()): boolean {
    const activeTransaction = this.getActiveTransaction(tabId, now);
    return activeTransaction !== undefined && !this.isTerminalPhase(activeTransaction.phase);
  }

  shouldSkipTabStatePersistence(tabId: string, url: string, now: number = Date.now()): boolean {
    return this.shouldSuppressNavigation(tabId, url, now);
  }

  private transitionByTabAndUrl(
    tabId: string,
    candidateUrl: string,
    phase: BrowserDownloadNavigationTransactionPhase,
    now: number,
    keepActive: boolean
  ): BrowserDownloadNavigationTransaction | undefined {
    const lookup = this.lookupByTabAndUrl(tabId, candidateUrl, now);
    if (lookup.transaction === undefined) {
      return undefined;
    }
    const transaction = this.copyTransaction(lookup.transaction);
    transaction.phase = phase;
    transaction.updatedAt = now;
    if (!keepActive || this.isTerminalPhase(phase)) {
      transaction.terminalAt = now;
      transaction.expiresAt = now + TERMINAL_TRANSACTION_RETENTION_MS;
      this.activeTransactionIdByTabId[transaction.tabId] = undefined;
    } else {
      transaction.expiresAt = now + DOWNLOAD_NAVIGATION_TRANSACTION_TTL_MS;
    }
    this.storeTransaction(transaction);
    return transaction;
  }

  private findReusableTransaction(
    tabId: string,
    normalizedCandidateUrl: string,
    now: number
  ): BrowserDownloadNavigationTransaction | undefined {
    const activeTransaction = this.getActiveTransaction(tabId, now);
    if (activeTransaction !== undefined && activeTransaction.normalizedCandidateUrl === normalizedCandidateUrl) {
      return activeTransaction;
    }
    const transactionId = this.transactionIdByNormalizedUrl[normalizedCandidateUrl];
    if (transactionId === undefined) {
      return undefined;
    }
    const transaction = this.transactionsById[transactionId];
    if (transaction === undefined || transaction.tabId !== tabId || this.isTerminalPhase(transaction.phase)) {
      return undefined;
    }
    return transaction;
  }

  private storeTransaction(transaction: BrowserDownloadNavigationTransaction): void {
    this.transactionsById[transaction.id] = transaction;
    this.transactionIdByNormalizedUrl[transaction.normalizedCandidateUrl] = transaction.id;
    if (!this.isTerminalPhase(transaction.phase)) {
      this.activeTransactionIdByTabId[transaction.tabId] = transaction.id;
    }
  }

  private pruneExpiredTransactions(now: number): void {
    Object.keys(this.transactionsById).forEach((transactionId: string) => {
      const transaction = this.transactionsById[transactionId];
      if (transaction === undefined || transaction.expiresAt > now) {
        return;
      }
      this.transactionsById[transactionId] = undefined;
      if (transaction.normalizedCandidateUrl.length > 0 &&
        this.transactionIdByNormalizedUrl[transaction.normalizedCandidateUrl] === transactionId) {
        this.transactionIdByNormalizedUrl[transaction.normalizedCandidateUrl] = undefined;
      }
      if (this.activeTransactionIdByTabId[transaction.tabId] === transactionId) {
        this.activeTransactionIdByTabId[transaction.tabId] = undefined;
      }
    });
  }

  private isTerminalPhase(phase: BrowserDownloadNavigationTransactionPhase): boolean {
    return phase === 'canceled' || phase === 'promoted_document' || phase === 'restored' || phase === 'expired';
  }

  private isRecentlyTerminal(transaction: BrowserDownloadNavigationTransaction, now: number): boolean {
    return this.isTerminalPhase(transaction.phase) && transaction.terminalAt > 0 && transaction.expiresAt > now;
  }

  private buildTransactionId(now: number): string {
    const sequence = this.nextSequence;
    this.nextSequence += 1;
    return `download-navigation-${now}-${sequence}`;
  }

  private copyTransaction(
    transaction: BrowserDownloadNavigationTransaction
  ): BrowserDownloadNavigationTransaction {
    return {
      id: transaction.id,
      tabId: transaction.tabId,
      candidateUrl: transaction.candidateUrl,
      normalizedCandidateUrl: transaction.normalizedCandidateUrl,
      previousRestorableUrl: transaction.previousRestorableUrl,
      previousRestorableTitle: transaction.previousRestorableTitle,
      previousSnapshotPath: transaction.previousSnapshotPath,
      promptGuid: transaction.promptGuid,
      downloadGuid: transaction.downloadGuid,
      phase: transaction.phase,
      createdAt: transaction.createdAt,
      updatedAt: transaction.updatedAt,
      expiresAt: transaction.expiresAt,
      restoredAt: transaction.restoredAt,
      terminalAt: transaction.terminalAt
    };
  }

  private normalizeUrl(url: string): string {
    const trimmed = url.trim().toLowerCase();
    if (trimmed.length <= 0) {
      return '';
    }
    const hashIndex = trimmed.indexOf('#');
    const withoutHash = hashIndex >= 0 ? trimmed.substring(0, hashIndex) : trimmed;
    return withoutHash.endsWith('/') ? withoutHash.substring(0, withoutHash.length - 1) : withoutHash;
  }
}
