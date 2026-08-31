export type BrowserDownloadPromptLeaseReleaseReason =
  'confirm' |
  'cancel' |
  'dismiss' |
  'disappear' |
  'replace' |
  'service_clear' |
  'route_transition';

export interface BrowserDownloadPromptLease {
  id: string;
  guid: string;
  url: string;
  createdAt: number;
  releasedAt: number;
  releaseReason: BrowserDownloadPromptLeaseReleaseReason | '';
}

export interface BrowserDownloadPromptLeasePrompt {
  guid: string;
  url: string;
}

export interface BrowserDownloadPromptLeasePresentation {
  shouldPresent: boolean;
  lease?: BrowserDownloadPromptLease;
  prompt?: BrowserDownloadPromptLeasePrompt;
}

const RELEASED_LEASE_RETENTION_MS = 2 * 60 * 1000;

export class BrowserDownloadPromptLeaseCoordinator {
  private activeLease?: BrowserDownloadPromptLease;
  private releasedLeaseByGuid: Record<string, BrowserDownloadPromptLease | undefined> = {};
  private nextSequence: number = 1;

  acquire(prompt?: BrowserDownloadPromptLeasePrompt, now: number = Date.now()): BrowserDownloadPromptLeasePresentation {
    this.pruneReleasedLeases(now);
    if (prompt === undefined) {
      this.releaseActive('service_clear', now);
      return {
        shouldPresent: false
      };
    }
    const guid = prompt.guid.trim();
    if (guid.length <= 0 || this.isReleasedGuid(guid, now)) {
      return {
        shouldPresent: false
      };
    }
    if (this.activeLease !== undefined && this.activeLease.guid === guid && this.activeLease.releasedAt <= 0) {
      return {
        shouldPresent: true,
        lease: this.activeLease,
        prompt: prompt
      };
    }
    if (this.activeLease !== undefined && this.activeLease.guid !== guid) {
      this.releaseActive('replace', now);
    }
    this.activeLease = {
      id: this.buildLeaseId(now),
      guid: guid,
      url: prompt.url.trim(),
      createdAt: now,
      releasedAt: 0,
      releaseReason: ''
    };
    return {
      shouldPresent: true,
      lease: this.activeLease,
      prompt: prompt
    };
  }

  releaseLease(leaseId: string, reason: BrowserDownloadPromptLeaseReleaseReason, now: number = Date.now()): void {
    if (this.activeLease === undefined || this.activeLease.id !== leaseId) {
      return;
    }
    this.releaseActive(reason, now);
  }

  releaseGuid(guid: string, reason: BrowserDownloadPromptLeaseReleaseReason, now: number = Date.now()): void {
    const normalizedGuid = guid.trim();
    if (normalizedGuid.length <= 0 || this.activeLease?.guid !== normalizedGuid) {
      return;
    }
    this.releaseActive(reason, now);
  }

  isLeaseActive(leaseId: string): boolean {
    const normalizedLeaseId = leaseId.trim();
    return normalizedLeaseId.length > 0 &&
      this.activeLease !== undefined &&
      this.activeLease.id === normalizedLeaseId &&
      this.activeLease.releasedAt <= 0;
  }

  private releaseActive(reason: BrowserDownloadPromptLeaseReleaseReason, now: number): void {
    if (this.activeLease === undefined) {
      return;
    }
    const releasedLease: BrowserDownloadPromptLease = {
      id: this.activeLease.id,
      guid: this.activeLease.guid,
      url: this.activeLease.url,
      createdAt: this.activeLease.createdAt,
      releasedAt: now,
      releaseReason: reason
    };
    this.releasedLeaseByGuid[releasedLease.guid] = releasedLease;
    this.activeLease = undefined;
  }

  private isReleasedGuid(guid: string, now: number): boolean {
    const releasedLease = this.releasedLeaseByGuid[guid];
    if (releasedLease === undefined) {
      return false;
    }
    if (now - releasedLease.releasedAt > RELEASED_LEASE_RETENTION_MS) {
      this.releasedLeaseByGuid[guid] = undefined;
      return false;
    }
    return true;
  }

  private pruneReleasedLeases(now: number): void {
    Object.keys(this.releasedLeaseByGuid).forEach((guid: string) => {
      const releasedLease = this.releasedLeaseByGuid[guid];
      if (releasedLease !== undefined && now - releasedLease.releasedAt > RELEASED_LEASE_RETENTION_MS) {
        this.releasedLeaseByGuid[guid] = undefined;
      }
    });
  }

  private buildLeaseId(now: number): string {
    const sequence = this.nextSequence;
    this.nextSequence += 1;
    return `download-prompt-lease-${now}-${sequence}`;
  }
}
