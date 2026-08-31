import {
  buildNovelSiteRulePayload,
  isBlockedNovelSite,
  NovelSiteRule,
  resolveBundledNovelSiteRule
} from '../../features/novel/NovelSiteRules';

/** Package-owned Novel extraction rules. Synchronous resolution never performs I/O. */
export class NovelRuleCatalog {
  resolveRule(url: string): NovelSiteRule | undefined {
    return this.isBlocked(url) ? undefined : resolveBundledNovelSiteRule(url);
  }

  resolveContentKind(url: string): 'novel' | 'comic' {
    return resolveBundledNovelSiteRule(url)?.kind === 'comic' ? 'comic' : 'novel';
  }

  isBlocked(url: string): boolean {
    return isBlockedNovelSite(url);
  }

  buildRuntimePayload(url: string): string {
    return buildNovelSiteRulePayload(this.resolveRule(url));
  }
}

export const sharedNovelRuleCatalog: NovelRuleCatalog = new NovelRuleCatalog();
