type UserScriptTabSnapshot = Record<string, Object | string | number | boolean | null>;

export class UserScriptTabStorageService {
  private tabsByKey: Record<string, UserScriptTabSnapshot | undefined> = {};

  getTab(scriptId: string, tabId: string): UserScriptTabSnapshot {
    return this.cloneSnapshot(this.tabsByKey[this.buildKey(scriptId, tabId)] ?? {});
  }

  saveTab(scriptId: string, tabId: string, value: UserScriptTabSnapshot | undefined): void {
    this.tabsByKey[this.buildKey(scriptId, tabId)] = this.cloneSnapshot(value ?? {});
  }

  getTabs(scriptId: string): Record<string, UserScriptTabSnapshot> {
    const prefix = `${scriptId.trim()}::`;
    const results: Record<string, UserScriptTabSnapshot> = {};
    Object.keys(this.tabsByKey).forEach((key: string) => {
      if (!key.startsWith(prefix)) {
        return;
      }
      const tabId = key.slice(prefix.length);
      results[tabId] = this.cloneSnapshot(this.tabsByKey[key] ?? {});
    });
    return results;
  }

  private buildKey(scriptId: string, tabId: string): string {
    return `${scriptId.trim()}::${tabId.trim()}`;
  }

  private cloneSnapshot(value: UserScriptTabSnapshot): UserScriptTabSnapshot {
    try {
      return JSON.parse(JSON.stringify(value)) as UserScriptTabSnapshot;
    } catch (_error) {
      return {};
    }
  }
}
