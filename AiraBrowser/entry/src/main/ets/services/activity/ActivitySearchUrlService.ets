const MAX_SEARCH_URL_SCAN_LENGTH: number = 2048;

export class ActivitySearchUrlService {
  isSearchResultUrl(url: string): boolean {
    if (url.length <= 0 || url.length > MAX_SEARCH_URL_SCAN_LENGTH) {
      return false;
    }
    const normalized = url.trim().toLowerCase();
    if (normalized.length <= 0) {
      return false;
    }
    return this.matchesBing(normalized) ||
      this.matchesGoogle(normalized) ||
      this.matchesDuckDuckGo(normalized) ||
      this.matchesBaidu(normalized);
  }

  private matchesBing(url: string): boolean {
    return url.indexOf('://www.bing.com/search?') > 0 && this.hasQueryParam(url, 'q');
  }

  private matchesGoogle(url: string): boolean {
    const hostMatched = url.indexOf('://www.google.') > 0 || url.indexOf('://google.') > 0;
    return hostMatched && url.indexOf('/search?') > 0 && this.hasQueryParam(url, 'q');
  }

  private matchesDuckDuckGo(url: string): boolean {
    return (url.indexOf('://duckduckgo.com/?') > 0 || url.indexOf('://www.duckduckgo.com/?') > 0) &&
      this.hasQueryParam(url, 'q');
  }

  private matchesBaidu(url: string): boolean {
    return url.indexOf('://www.baidu.com/s?') > 0 &&
      (this.hasQueryParam(url, 'wd') || this.hasQueryParam(url, 'word'));
  }

  private hasQueryParam(url: string, name: string): boolean {
    const queryStart = url.indexOf('?');
    if (queryStart < 0 || queryStart >= url.length - 1) {
      return false;
    }
    const hashStart = url.indexOf('#', queryStart + 1);
    const query = url.substring(queryStart + 1, hashStart >= 0 ? hashStart : url.length);
    const prefix = `${name.toLowerCase()}=`;
    let start = 0;
    while (start < query.length) {
      const end = query.indexOf('&', start);
      const partEnd = end >= 0 ? end : query.length;
      if (query.substring(start, partEnd).toLowerCase().startsWith(prefix)) {
        return true;
      }
      if (end < 0) {
        break;
      }
      start = end + 1;
    }
    return false;
  }
}
