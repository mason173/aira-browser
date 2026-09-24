import { UserScriptExactInstallAlias } from './UserScriptExactInstallAlias';
import { UserScriptGforkProxyInstallUrl } from './UserScriptGforkProxyInstallUrl';
import { UserScriptInstallSourceAdapter } from './UserScriptInstallSourceAdapter';
import { UserScriptScriptCatPreviewInstallUrl } from './UserScriptScriptCatPreviewInstallUrl';

export class UserScriptInstallSourceResolver {
  private adapters: UserScriptInstallSourceAdapter[] = [
    new UserScriptExactInstallAlias(),
    new UserScriptGforkProxyInstallUrl(),
    new UserScriptScriptCatPreviewInstallUrl()
  ];

  resolveSourceUrls(url: string): string[] {
    const trimmed = url.trim();
    for (let index = 0; index < this.adapters.length; index++) {
      const resolved = this.adapters[index].resolveSourceUrls(trimmed);
      if (resolved.length > 0) {
        return resolved;
      }
    }
    return [trimmed];
  }
}
