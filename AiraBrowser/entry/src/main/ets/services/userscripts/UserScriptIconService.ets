export class UserScriptIconService {
  resolveIconUrl(iconValue: string, sourceUrl: string = ''): string {
    const icon = iconValue.trim();
    if (icon.length === 0) {
      return '';
    }
    if (/^(https?:|data:|file:|resource:)/i.test(icon)) {
      return icon;
    }
    if (icon.startsWith('//')) {
      return `https:${icon}`;
    }
    const source = sourceUrl.trim();
    const originMatch = /^(https?:\/\/[^/]+)/i.exec(source);
    if (icon.startsWith('/') && originMatch !== null) {
      return `${originMatch[1]}${icon}`;
    }
    const directoryMatch = /^(https?:\/\/.*\/)[^/]*$/i.exec(source);
    if (directoryMatch !== null) {
      return `${directoryMatch[1]}${icon.replace(/^\.\//, '')}`;
    }
    return icon;
  }

  recoverIconUrl(source: string, sourceUrl: string = ''): string {
    const header = this.extractHeader(source);
    const iconValues: string[] = [];
    header.split('\n').forEach((line: string) => {
      const match = /^\s*\/\/\s*@(icon|iconURL|iconUrl|defaulticon)\s+(.+)\s*$/.exec(line);
      if (match !== null) {
        iconValues.push(match[2].trim());
      }
    });
    return this.resolveIconUrl(iconValues.find((value: string) => value.length > 0) ?? '', sourceUrl);
  }

  private extractHeader(source: string): string {
    const start = source.indexOf('// ==UserScript==');
    const end = source.indexOf('// ==/UserScript==');
    if (start < 0 || end <= start) {
      return '';
    }
    return source.slice(start, end);
  }
}
