export class UserScriptInstallUrlService {
  resolveInstallUrl(targetUrl: string): string {
    const normalizedUrl = targetUrl.trim();
    return this.canInstallFromUrl(normalizedUrl) ? normalizedUrl : '';
  }

  canInstallFromUrl(url: string): boolean {
    const normalized = url.trim().toLowerCase();
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      return false;
    }
    return /\.user\.js(?:[?#]|$)/i.test(normalized);
  }
}
