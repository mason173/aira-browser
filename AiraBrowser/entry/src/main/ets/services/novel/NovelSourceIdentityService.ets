/** 小说来源 URL、书籍和章节身份的唯一规范化 owner。 */
export class NovelSourceIdentityService {
  normalizeUrl(url: string): string {
    let value: string = String(url ?? '').trim();
    let routedFragment: string = '';
    const hash: number = value.indexOf('#');
    if (hash >= 0) {
      const fragment: string = value.substring(hash + 1);
      if (fragment.startsWith('/') || fragment.startsWith('!/')) {
        routedFragment = fragment;
      }
      value = value.substring(0, hash);
    }
    if (value.startsWith('https://')) {
      value = value.substring(8);
    } else if (value.startsWith('http://')) {
      value = value.substring(7);
    }
    const pathStart: number = this.firstUrlSuffixIndex(value);
    let authority: string = pathStart >= 0 ? value.substring(0, pathStart) : value;
    const suffix: string = pathStart >= 0 ? value.substring(pathStart) : '';
    authority = authority.toLowerCase();
    if (authority.startsWith('www.')) {
      authority = authority.substring(4);
    }
    value = authority + suffix;
    if (routedFragment.length > 0) {
      const routedPathStart: number = this.firstUrlSuffixIndex(value);
      const host: string = routedPathStart >= 0 ? value.substring(0, routedPathStart) : value;
      while (routedFragment.endsWith('/') && routedFragment.length > 1) {
        routedFragment = routedFragment.substring(0, routedFragment.length - 1);
      }
      return host + '#' + routedFragment;
    }
    if (value.endsWith('/') && value.indexOf('?') < 0) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  parentDirectory(url: string): string {
    const slash: number = url.lastIndexOf('/');
    return slash > 8 ? url.substring(0, slash + 1) : '';
  }

  buildBookIdentity(catalogUrl: string, pageUrl: string): string {
    const sourceUrl: string = catalogUrl.length > 0 ? catalogUrl : this.parentDirectory(pageUrl);
    const normalized: string = this.normalizeUrl(sourceUrl.length > 0 ? sourceUrl : pageUrl);
    return `source-book:${normalized.length}:${normalized}`;
  }

  buildChapterIdentity(bookId: string, canonicalUrl: string): string {
    const normalizedUrl: string = this.normalizeUrl(canonicalUrl);
    return `${bookId.length}:${bookId}:${normalizedUrl.length}:${normalizedUrl}`;
  }

  normalizedAuthority(url: string): string {
    const normalized: string = this.normalizeUrl(url);
    const suffixIndex: number = this.firstUrlSuffixIndex(normalized);
    return suffixIndex >= 0 ? normalized.substring(0, suffixIndex) : normalized;
  }

  private firstUrlSuffixIndex(value: string): number {
    const slash: number = value.indexOf('/');
    const query: number = value.indexOf('?');
    if (slash < 0) {
      return query;
    }
    if (query < 0) {
      return slash;
    }
    return Math.min(slash, query);
  }
}

export const sharedNovelSourceIdentityService: NovelSourceIdentityService =
  new NovelSourceIdentityService();
