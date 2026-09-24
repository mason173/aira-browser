export interface UserScriptInstallSourceAdapter {
  resolveSourceUrls(url: string): string[];
}
