export interface ReaderSiteAdapterRule {
  id: string;
  hostSuffixes: string[];
  sourceSelectors: string[];
  compositeSourceSelectors?: string[];
  contentBlockSelectors?: string[];
  requiredSourceSelectors?: string[];
  removeSelectors: string[];
  titleSelectors: string[];
  bylineSelectors: string[];
  publishedAtSelectors: string[];
  imageAttributes: string[];
  siteName: string;
}

export interface ReaderResolvedSiteAdapter {
  id: string;
  sourceSelectors: string[];
  compositeSourceSelectors: string[];
  contentBlockSelectors: string[];
  requiredSourceSelectors: string[];
  removeSelectors: string[];
  titleSelectors: string[];
  bylineSelectors: string[];
  publishedAtSelectors: string[];
  imageAttributes: string[];
  siteName: string;
}

const READER_SITE_ADAPTER_RULES: ReaderSiteAdapterRule[] = [
  {
    id: 'wechat_article',
    hostSuffixes: ['mp.weixin.qq.com'],
    sourceSelectors: ['#js_content', '.rich_media_content'],
    removeSelectors: ['#js_pc_qr_code', '.rich_media_tool', '.rich_media_meta_list', '.qr_code_pc_outer'],
    titleSelectors: ['#activity-name', '.rich_media_title'],
    bylineSelectors: ['#js_name', '.rich_media_meta_text.rich_media_meta_nickname'],
    publishedAtSelectors: ['#publish_time', '#js_publish_time'],
    imageAttributes: ['data-src', 'data-backsrc', 'data-original'],
    siteName: '微信公众号'
  },
  {
    id: 'zhihu_article',
    hostSuffixes: ['zhihu.com', 'zhuanlan.zhihu.com'],
    sourceSelectors: [
      'article',
      '.Post-RichTextContainer',
      '.Post-RichText',
      '.RichContent-inner',
      '.RichText',
      '.QuestionAnswer-content',
      '.QuestionAnswer-content .RichContent'
    ],
    removeSelectors: [
      '.Recommendations-Main',
      '.ContentItem-actions',
      '.Reward',
      '.Post-SideActions',
      '.Question-sideColumn',
      '.QuestionHeader-side',
      '.Pc-card'
    ],
    titleSelectors: ['.Post-Title', '.QuestionHeader-title', 'h1'],
    bylineSelectors: ['.AuthorInfo-name', '.UserLink-link', '.AuthorInfo-head'],
    publishedAtSelectors: ['time', '.ContentItem-time'],
    imageAttributes: ['data-original', 'data-actualsrc', 'data-src'],
    siteName: '知乎'
  },
  {
    id: 'juejin_article',
    hostSuffixes: ['juejin.cn'],
    sourceSelectors: ['article', '.article-content', '.markdown-body'],
    removeSelectors: ['.comment-list-box', '.recommended-area', '.sidebar', '.article-suspended-panel'],
    titleSelectors: ['.article-title', 'h1'],
    bylineSelectors: ['.author-name', '.username'],
    publishedAtSelectors: ['time', '.meta-box'],
    imageAttributes: ['data-src', 'data-original', 'src'],
    siteName: '稀土掘金'
  },
  {
    id: 'csdn_article',
    hostSuffixes: ['blog.csdn.net'],
    sourceSelectors: ['#article_content', 'article', '.blog-content-box'],
    removeSelectors: ['.recommend-box', '.comment-box', '.blog-footer-bottom', '.csdn-side-toolbar', '.toolbar-advert'],
    titleSelectors: ['.title-article', 'h1'],
    bylineSelectors: ['.follow-nickName', '.name'],
    publishedAtSelectors: ['.time', '.bar-content'],
    imageAttributes: ['data-src', 'data-original', 'src'],
    siteName: 'CSDN'
  },
  {
    id: 'segmentfault_article',
    hostSuffixes: ['segmentfault.com'],
    sourceSelectors: ['article', '.article__content', '.fmt'],
    removeSelectors: ['.widget-box', '.related-article', '.comment-area', '.side'],
    titleSelectors: ['h1'],
    bylineSelectors: ['.author', '.user-name'],
    publishedAtSelectors: ['time'],
    imageAttributes: ['data-src', 'data-original', 'src'],
    siteName: 'SegmentFault'
  },
  {
    id: 'sspai_article',
    hostSuffixes: ['sspai.com'],
    sourceSelectors: ['.article-body', '.normal-article .article-body', 'article.normal-article'],
    removeSelectors: [
      '.article-header',
      '.article-actionBar',
      '.article-side',
      '.article-copyrights',
      '.related__read__wrapper',
      '.comments__feed__dialog',
      '#btn-call-app'
    ],
    titleSelectors: ['#article-title', '.article-header .title', 'h1'],
    bylineSelectors: ['.article-author .nickname', '.ss__user__nickname'],
    publishedAtSelectors: ['time', '.article-info', '.meta'],
    imageAttributes: ['data-original', 'data-src', 'src'],
    siteName: '少数派'
  },
  {
    id: 'infoq_article',
    hostSuffixes: ['infoq.cn'],
    sourceSelectors: ['article', '.article-content', '.text-content'],
    removeSelectors: ['.recommend-read', '.comment-wrapper', '.right-box', '.article-operation'],
    titleSelectors: ['h1', '.article-title'],
    bylineSelectors: ['.author-name', '.article-author'],
    publishedAtSelectors: ['time', '.article-time'],
    imageAttributes: ['data-src', 'data-original', 'src'],
    siteName: 'InfoQ'
  },
  {
    id: 'baidu_baike_article',
    hostSuffixes: ['baike.baidu.com'],
    sourceSelectors: ['.J-summary', 'div.J-lemma-content', '[class*="lemmaSummary"]', '[class*="J-lemma-content"]'],
    compositeSourceSelectors: ['.J-summary', 'div.J-lemma-content', '[class*="lemmaSummary"]', '[class*="J-lemma-content"]'],
    contentBlockSelectors: ['[data-tag="header"]', '[data-tag="paragraph"]', 'table tr'],
    requiredSourceSelectors: ['.J-summary', 'div.J-lemma-content'],
    removeSelectors: ['[data-tts-catalog]', '.J-pgc-content'],
    titleSelectors: ['h1'],
    bylineSelectors: [],
    publishedAtSelectors: ['meta[itemprop="dateUpdate"]'],
    imageAttributes: ['data-src', 'data-original', 'src'],
    siteName: '百度百科'
  }
];

const EMPTY_READER_SITE_ADAPTER: ReaderResolvedSiteAdapter = {
  id: '',
  sourceSelectors: [],
  compositeSourceSelectors: [],
  contentBlockSelectors: [],
  requiredSourceSelectors: [],
  removeSelectors: [],
  titleSelectors: [],
  bylineSelectors: [],
  publishedAtSelectors: [],
  imageAttributes: [],
  siteName: ''
};

export class ReaderSiteAdapterRegistry {
  listRules(): ReaderSiteAdapterRule[] {
    return READER_SITE_ADAPTER_RULES.map((rule: ReaderSiteAdapterRule) => this.cloneRule(rule));
  }

  resolveForUrl(url: string): ReaderResolvedSiteAdapter {
    return this.resolveForHost(this.extractHost(url));
  }

  resolveForHost(host: string): ReaderResolvedSiteAdapter {
    const normalizedHost = this.normalizeHost(host);
    if (normalizedHost.length <= 0) {
      return this.cloneResolvedAdapter(EMPTY_READER_SITE_ADAPTER);
    }
    const rule = READER_SITE_ADAPTER_RULES.find((item: ReaderSiteAdapterRule) => {
      return item.hostSuffixes.some((suffix: string) => this.matchesHostSuffix(normalizedHost, suffix));
    });
    if (rule === undefined) {
      return this.cloneResolvedAdapter(EMPTY_READER_SITE_ADAPTER);
    }
    return {
      id: rule.id,
      sourceSelectors: [...rule.sourceSelectors],
      compositeSourceSelectors: [...(rule.compositeSourceSelectors ?? [])],
      contentBlockSelectors: [...(rule.contentBlockSelectors ?? [])],
      requiredSourceSelectors: [...(rule.requiredSourceSelectors ?? [])],
      removeSelectors: [...rule.removeSelectors],
      titleSelectors: [...rule.titleSelectors],
      bylineSelectors: [...rule.bylineSelectors],
      publishedAtSelectors: [...rule.publishedAtSelectors],
      imageAttributes: [...rule.imageAttributes],
      siteName: rule.siteName
    };
  }

  buildScriptRulePayload(): string {
    return JSON.stringify(READER_SITE_ADAPTER_RULES);
  }

  private matchesHostSuffix(host: string, suffix: string): boolean {
    const normalizedSuffix = this.normalizeHost(suffix);
    return host === normalizedSuffix || host.endsWith(`.${normalizedSuffix}`);
  }

  private extractHost(url: string): string {
    const trimmed = url.trim();
    const schemeIndex = trimmed.indexOf('://');
    if (schemeIndex < 0) {
      return trimmed;
    }
    const hostStart = schemeIndex + 3;
    const slashIndex = trimmed.indexOf('/', hostStart);
    const hostWithPort = slashIndex >= 0 ? trimmed.substring(hostStart, slashIndex) : trimmed.substring(hostStart);
    const atIndex = hostWithPort.lastIndexOf('@');
    const withoutUserInfo = atIndex >= 0 ? hostWithPort.substring(atIndex + 1) : hostWithPort;
    const colonIndex = withoutUserInfo.indexOf(':');
    return colonIndex >= 0 ? withoutUserInfo.substring(0, colonIndex) : withoutUserInfo;
  }

  private normalizeHost(host: string): string {
    return host.trim().toLowerCase().replace(/^www\./, '');
  }

  private cloneRule(rule: ReaderSiteAdapterRule): ReaderSiteAdapterRule {
    return {
      id: rule.id,
      hostSuffixes: [...rule.hostSuffixes],
      sourceSelectors: [...rule.sourceSelectors],
      compositeSourceSelectors: [...(rule.compositeSourceSelectors ?? [])],
      contentBlockSelectors: [...(rule.contentBlockSelectors ?? [])],
      requiredSourceSelectors: [...(rule.requiredSourceSelectors ?? [])],
      removeSelectors: [...rule.removeSelectors],
      titleSelectors: [...rule.titleSelectors],
      bylineSelectors: [...rule.bylineSelectors],
      publishedAtSelectors: [...rule.publishedAtSelectors],
      imageAttributes: [...rule.imageAttributes],
      siteName: rule.siteName
    };
  }

  private cloneResolvedAdapter(adapter: ReaderResolvedSiteAdapter): ReaderResolvedSiteAdapter {
    return {
      id: adapter.id,
      sourceSelectors: [...adapter.sourceSelectors],
      compositeSourceSelectors: [...adapter.compositeSourceSelectors],
      contentBlockSelectors: [...adapter.contentBlockSelectors],
      requiredSourceSelectors: [...adapter.requiredSourceSelectors],
      removeSelectors: [...adapter.removeSelectors],
      titleSelectors: [...adapter.titleSelectors],
      bylineSelectors: [...adapter.bylineSelectors],
      publishedAtSelectors: [...adapter.publishedAtSelectors],
      imageAttributes: [...adapter.imageAttributes],
      siteName: adapter.siteName
    };
  }
}
