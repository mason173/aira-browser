import {
  AiraAdditionalBackupIntervalDays,
  AiraSyncDomainId,
  AiraSyncProviderKind,
  AiraSyncSettings,
  resolveAiraSyncDomainRuntimeState
} from '../../common/models/AiraSyncModels';

const DAY_MS: number = 24 * 60 * 60 * 1000;

export class SyncAdditionalBackupPolicyService {
  isEnabled(settings: AiraSyncSettings): boolean {
    return settings.additionalBackupEnabled === true && this.resolveBackupKinds(settings).length > 0;
  }

  resolveIntervalDays(settings: AiraSyncSettings): AiraAdditionalBackupIntervalDays {
    const value = settings.additionalBackupIntervalDays;
    if (value === 1 || value === 3 || value === 7) {
      return value;
    }
    return 7;
  }

  resolveIntervalLabel(settings: AiraSyncSettings): string {
    const days = this.resolveIntervalDays(settings);
    return days === 1 ? '每天一次' : `每 ${days} 天一次`;
  }

  shouldWriteBackups(
    settings: AiraSyncSettings,
    domain: AiraSyncDomainId,
    force: boolean = false,
    now: number = Date.now()
  ): boolean {
    const backupKinds = this.resolveBackupKinds(settings);
    if (backupKinds.length <= 0) {
      return false;
    }
    if (force) {
      return true;
    }
    if (!this.isEnabled(settings)) {
      return false;
    }
    const lastBackupAt = this.resolveDomainLastBackupAt(settings, domain);
    if (lastBackupAt <= 0) {
      return true;
    }
    return now - lastBackupAt >= this.resolveIntervalDays(settings) * DAY_MS;
  }

  resolveLastCompleteBackupAt(settings: AiraSyncSettings): number {
    const domains: AiraSyncDomainId[] = [];
    if (settings.bookmarkSyncEnabled === true) {
      domains.push('bookmarks');
    }
    if (settings.personalizationSyncEnabled === true) {
      domains.push('personalization');
    }
    if (domains.length <= 0 || this.resolveBackupKinds(settings).length <= 0) {
      return 0;
    }
    let completedAt = Number.MAX_SAFE_INTEGER;
    for (let index = 0; index < domains.length; index += 1) {
      const domainAt = this.resolveDomainLastBackupAt(settings, domains[index]);
      if (domainAt <= 0) {
        return 0;
      }
      completedAt = Math.min(completedAt, domainAt);
    }
    return completedAt === Number.MAX_SAFE_INTEGER ? 0 : completedAt;
  }

  private resolveDomainLastBackupAt(settings: AiraSyncSettings, domain: AiraSyncDomainId): number {
    const backupKinds = this.resolveBackupKinds(settings);
    let completedAt = Number.MAX_SAFE_INTEGER;
    for (let index = 0; index < backupKinds.length; index += 1) {
      const lastSuccessAt = resolveAiraSyncDomainRuntimeState(
        settings,
        backupKinds[index],
        domain === 'personalization' ? 'personalization_backup' : 'bookmark_backup'
      ).lastSuccessAt;
      if (lastSuccessAt <= 0) {
        return 0;
      }
      completedAt = Math.min(completedAt, lastSuccessAt);
    }
    return completedAt === Number.MAX_SAFE_INTEGER ? 0 : completedAt;
  }

  private resolveBackupKinds(settings: AiraSyncSettings): AiraSyncProviderKind[] {
    return (settings.additionalBackupRemoteKinds ?? []).filter((kind: AiraSyncProviderKind): boolean => {
      return kind === 'webdav';
    });
  }
}
