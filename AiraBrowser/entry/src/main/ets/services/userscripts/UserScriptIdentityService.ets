import {
  InstalledUserScriptState,
  UserScriptPackageCandidate
} from '../../features/userscripts/UserScriptMetadataModels';

type UserScriptIdentityState = InstalledUserScriptState | UserScriptPackageCandidate;

export class UserScriptIdentityService {
  findDuplicateScript(
    candidate: UserScriptPackageCandidate,
    installedScripts: InstalledUserScriptState[],
    excludedScriptId: string = ''
  ): InstalledUserScriptState | undefined {
    const excludedId = excludedScriptId.trim();
    for (let index = 0; index < installedScripts.length; index++) {
      const installed = installedScripts[index];
      if (excludedId.length > 0 && installed.id === excludedId) {
        continue;
      }
      if (this.isSameScript(candidate, installed)) {
        return installed;
      }
    }
    return undefined;
  }

  private isSameScript(left: UserScriptIdentityState, right: UserScriptIdentityState): boolean {
    if (this.hasSameNameAndNamespace(left, right)) {
      return true;
    }
    return this.hasSharedRemoteIdentity(left, right);
  }

  private hasSameNameAndNamespace(left: UserScriptIdentityState, right: UserScriptIdentityState): boolean {
    const leftName = left.name.trim();
    const rightName = right.name.trim();
    if (leftName.length === 0 || rightName.length === 0 || leftName !== rightName) {
      return false;
    }
    return left.namespace.trim() === right.namespace.trim();
  }

  private hasSharedRemoteIdentity(left: UserScriptIdentityState, right: UserScriptIdentityState): boolean {
    const leftUrls = this.buildIdentityUrls(left);
    const rightUrls = this.buildIdentityUrls(right);
    for (let leftIndex = 0; leftIndex < leftUrls.length; leftIndex++) {
      for (let rightIndex = 0; rightIndex < rightUrls.length; rightIndex++) {
        if (leftUrls[leftIndex] === rightUrls[rightIndex]) {
          return true;
        }
      }
    }
    return false;
  }

  private buildIdentityUrls(record: UserScriptIdentityState): string[] {
    const urls: string[] = [];
    this.appendUrl(urls, record.updateUrl);
    this.appendUrl(urls, record.downloadUrl);
    this.appendUrl(urls, record.sourceUrl);
    return urls;
  }

  private appendUrl(urls: string[], value: string): void {
    const normalized = value.trim();
    if (normalized.length > 0 && normalized !== 'none' && !urls.includes(normalized)) {
      urls.push(normalized);
    }
  }
}
