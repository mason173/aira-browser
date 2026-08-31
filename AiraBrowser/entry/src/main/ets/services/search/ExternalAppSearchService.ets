import { looksLikeUrl } from '../../common/utils/UrlUtils';
import {
  ALL_EXTERNAL_APP_SEARCH_TARGET_IDS,
  ExternalAppSearchIconTargetId,
  ExternalAppSearchPreferences,
  ExternalAppSearchTargetId
} from '../../common/models/BrowserModels';

export interface ExternalAppSearchTarget {
  id: ExternalAppSearchTargetId;
  title: string;
  accessibilityText: string;
  iconTargetId?: ExternalAppSearchIconTargetId;
  markText: string;
}

export interface ExternalAppSearchVisibilityInput {
  inputEditing: boolean;
  inputFocused: boolean;
  preferences: ExternalAppSearchPreferences;
}

export interface ExternalAppSearchAction {
  target: ExternalAppSearchTarget;
  query: string;
  nativeUrl: string;
  nativeTarget?: ExternalAppSearchNativeTarget;
  fallbackUrl: string;
  openMode: ExternalAppSearchOpenMode;
}

export type ExternalAppSearchOpenMode = 'external_app' | 'current_tab_web';

export interface ExternalAppSearchNativeTarget {
  bundleName: string;
  moduleName: string;
  abilityName: string;
  action?: string;
}

export interface ExternalAppSearchPrivateConfirmation {
  title: string;
  message: string;
  confirmLabel: string;
  cancelLabel: string;
}

interface ExternalAppSearchRouteDescriptor {
  urlPrefix: string;
  urlSuffix: string;
  schemes: string[];
  hosts: string[];
  usesQuery?: boolean;
}

interface ExternalAppSearchTargetDescriptor extends ExternalAppSearchTarget {
  nativeRoute: ExternalAppSearchRouteDescriptor;
  nativeTarget?: ExternalAppSearchNativeTarget;
  fallbackRoute: ExternalAppSearchRouteDescriptor;
  openMode?: ExternalAppSearchOpenMode;
}

const EXTERNAL_APP_SEARCH_TARGETS: ExternalAppSearchTargetDescriptor[] = [
  {
    id: 'zhihu',
    title: '知乎',
    accessibilityText: '在知乎搜索',
    iconTargetId: 'zhihu',
    markText: '知',
    nativeRoute: {
      urlPrefix: 'https://www.zhihu.com/search?type=content&q=',
      urlSuffix: '',
      schemes: ['https'],
      hosts: ['www.zhihu.com']
    },
    fallbackRoute: {
      urlPrefix: 'https://www.zhihu.com/search?type=content&q=',
      urlSuffix: '',
      schemes: ['https'],
      hosts: ['www.zhihu.com']
    }
  },
  {
    id: 'bilibili',
    title: '哔哩哔哩',
    accessibilityText: '在哔哩哔哩搜索',
    iconTargetId: 'bilibili',
    markText: '哔',
    nativeRoute: {
      urlPrefix: 'bilibili://search/?keyword=',
      urlSuffix: '',
      schemes: ['bilibili'],
      hosts: ['search']
    },
    fallbackRoute: {
      urlPrefix: 'https://search.bilibili.com/all?keyword=',
      urlSuffix: '',
      schemes: ['https'],
      hosts: ['search.bilibili.com']
    }
  },
  {
    id: 'douyin',
    title: '抖音',
    accessibilityText: '在抖音搜索',
    iconTargetId: 'douyin',
    markText: '抖',
    nativeRoute: {
      urlPrefix: 'snssdk1128://search?keyword=',
      urlSuffix: '',
      schemes: ['snssdk1128'],
      hosts: ['search']
    },
    fallbackRoute: {
      urlPrefix: 'https://www.douyin.com/search/',
      urlSuffix: '',
      schemes: ['https'],
      hosts: ['www.douyin.com']
    }
  },
  {
    id: 'xiaohongshu',
    title: '小红书',
    accessibilityText: '在小红书搜索',
    iconTargetId: 'xiaohongshu',
    markText: '红',
    nativeRoute: {
      urlPrefix: 'xhsdiscover://search/result?keyword=',
      urlSuffix: '',
      schemes: ['xhsdiscover'],
      hosts: ['search']
    },
    fallbackRoute: {
      urlPrefix: 'https://www.xiaohongshu.com/search_result/?keyword=',
      urlSuffix: '&source=web_search_result_notes',
      schemes: ['https'],
      hosts: ['www.xiaohongshu.com']
    }
  },
  {
    id: 'douban',
    title: '豆瓣',
    accessibilityText: '在豆瓣搜索',
    markText: '豆',
    nativeRoute: {
      urlPrefix: 'https://www.douban.com/doubanapp/dispatch?uri=douban%3A%2F%2Fdouban.com%2Fsearch%3Fq%3D',
      urlSuffix: '',
      schemes: ['https'],
      hosts: ['www.douban.com']
    },
    fallbackRoute: {
      urlPrefix: 'https://www.douban.com/search?q=',
      urlSuffix: '',
      schemes: ['https'],
      hosts: ['www.douban.com']
    }
  },
  {
    id: 'quark',
    title: '夸克',
    accessibilityText: '在夸克搜索',
    markText: '夸',
    nativeRoute: {
      urlPrefix: 'https://www.quark.cn/s?q=',
      urlSuffix: '&from=kkframenew&uc_param_str=dnntnwvepffrbijbprsvchgputdemennosstodcaaapcgidsdieinipikp',
      schemes: ['https'],
      hosts: ['www.quark.cn']
    },
    nativeTarget: {
      bundleName: 'com.quark.ohosbrowser',
      moduleName: 'quark',
      abilityName: 'EntryAbility',
      action: 'ohos.want.action.viewData'
    },
    fallbackRoute: {
      urlPrefix: 'https://m.sm.cn/s?q=',
      urlSuffix: '',
      schemes: ['https'],
      hosts: ['m.sm.cn']
    }
  },
  {
    id: 'appgallery',
    title: '应用市场',
    accessibilityText: '在华为应用市场搜索',
    markText: '华',
    nativeRoute: {
      urlPrefix: 'store://appgallery.huawei.com/app/search?id=',
      urlSuffix: '',
      schemes: ['store'],
      hosts: ['appgallery.huawei.com']
    },
    nativeTarget: {
      bundleName: 'com.huawei.hmsapp.appgallery',
      moduleName: 'entry',
      abilityName: 'MainAbility'
    },
    fallbackRoute: {
      urlPrefix: 'https://appgallery.huawei.com/search/',
      urlSuffix: '',
      schemes: ['https'],
      hosts: ['appgallery.huawei.com']
    }
  },
  {
    id: 'jd',
    title: '京东',
    accessibilityText: '在京东搜索',
    markText: '京',
    nativeRoute: {
      urlPrefix: 'openapp.jdmobile://virtual?params=%7B%22category%22%3A%22jump%22%2C%22des%22%3A%22search%22%2C%22keyWord%22%3A%22',
      urlSuffix: '%22%7D',
      schemes: ['openapp.jdmobile'],
      hosts: ['virtual']
    },
    fallbackRoute: {
      urlPrefix: 'https://search.jd.com/Search?keyword=',
      urlSuffix: '',
      schemes: ['https'],
      hosts: ['search.jd.com']
    }
  },
  {
    id: 'taobao',
    title: '淘宝',
    accessibilityText: '在淘宝搜索',
    markText: '淘',
    nativeRoute: {
      urlPrefix: 'tbopen://m.taobao.com/tbopen/index.html?h5Url=https://main.m.taobao.com/search/index.html?q=',
      urlSuffix: '',
      schemes: ['tbopen'],
      hosts: ['m.taobao.com']
    },
    nativeTarget: {
      bundleName: 'com.taobao.taobao4hmos',
      moduleName: 'taobao_main',
      abilityName: 'Taobao_mainAbility'
    },
    fallbackRoute: {
      urlPrefix: 'https://s.taobao.com/search?q=',
      urlSuffix: '',
      schemes: ['https'],
      hosts: ['s.taobao.com']
    }
  },
  {
    id: 'pinduoduo',
    title: '拼多多',
    accessibilityText: '在拼多多搜索',
    markText: '拼',
    nativeRoute: {
      urlPrefix: 'pinduoduo://com.xunmeng.pinduoduo/search_result.html?search_key=',
      urlSuffix: '',
      schemes: ['pinduoduo'],
      hosts: ['com.xunmeng.pinduoduo']
    },
    fallbackRoute: {
      urlPrefix: 'https://mobile.yangkeduo.com/search_result.html?search_key=',
      urlSuffix: '',
      schemes: ['https'],
      hosts: ['mobile.yangkeduo.com']
    }
  },
  {
    id: 'xianyu',
    title: '闲鱼',
    accessibilityText: '在闲鱼搜索',
    markText: '闲',
    nativeRoute: {
      urlPrefix: 'fleamarket://search_items?keyword=',
      urlSuffix: '',
      schemes: ['fleamarket'],
      hosts: ['search_items']
    },
    nativeTarget: {
      bundleName: 'com.taobao.idlefish4ohos',
      moduleName: 'entry',
      abilityName: 'EntryAbility'
    },
    fallbackRoute: {
      urlPrefix: 'https://www.goofish.com/search?q=',
      urlSuffix: '',
      schemes: ['https'],
      hosts: ['www.goofish.com']
    }
  },
  {
    id: 'meituan',
    title: '美团',
    accessibilityText: '在美团搜索',
    markText: '美',
    nativeRoute: {
      urlPrefix: 'imeituan://www.meituan.com/takeout/browser?inner_url=https%3A%2F%2Fh5.waimai.meituan.com%2Fwaimai%2Fmindex%2Fsearchresults%3FqueryType%3D12002%26keyword%3D',
      urlSuffix: '',
      schemes: ['imeituan'],
      hosts: ['www.meituan.com']
    },
    nativeTarget: {
      bundleName: 'com.sankuai.hmeituan',
      moduleName: 'meituan',
      abilityName: 'EntryAbility'
    },
    fallbackRoute: {
      urlPrefix: 'https://s.meituan.com/search?keyword=',
      urlSuffix: '',
      schemes: ['https'],
      hosts: ['s.meituan.com']
    }
  },
  {
    id: 'baidu_map',
    title: '百度地图',
    accessibilityText: '在百度地图搜索',
    markText: '百',
    nativeRoute: {
      urlPrefix: 'baidumap://map/place/search?query=',
      urlSuffix: '&src=aira.browser',
      schemes: ['baidumap'],
      hosts: ['map']
    },
    fallbackRoute: {
      urlPrefix: 'https://map.baidu.com/search/',
      urlSuffix: '',
      schemes: ['https'],
      hosts: ['map.baidu.com']
    }
  },
  {
    id: 'qqmusic',
    title: 'QQ音乐',
    accessibilityText: '在QQ音乐搜索',
    markText: 'Q',
    nativeRoute: {
      urlPrefix: 'qqmusic://qq.com/ui/search?p=',
      urlSuffix: '',
      schemes: ['qqmusic'],
      hosts: ['qq.com'],
      usesQuery: false
    },
    nativeTarget: {
      bundleName: 'com.tencent.hm.qqmusic',
      moduleName: 'entry',
      abilityName: 'EntryAbility'
    },
    fallbackRoute: {
      urlPrefix: 'https://y.qq.com/n/ryqq/search?w=',
      urlSuffix: '',
      schemes: ['https'],
      hosts: ['y.qq.com']
    }
  },
  {
    id: 'alipay',
    title: '支付宝',
    accessibilityText: '在支付宝搜索',
    markText: '支',
    nativeRoute: {
      urlPrefix: 'alipays://platformapi/startapp?appId=20001003&keyword=',
      urlSuffix: '',
      schemes: ['alipays'],
      hosts: ['platformapi']
    },
    fallbackRoute: {
      urlPrefix: 'https://www.alipay.com/?keyword=',
      urlSuffix: '',
      schemes: ['https'],
      hosts: ['www.alipay.com']
    }
  },
  {
    id: 'youdao',
    title: '有道词典',
    accessibilityText: '在网易有道词典搜索',
    markText: '有',
    nativeRoute: {
      urlPrefix: 'https://dict.youdao.com/m/result?word=',
      urlSuffix: '&lang=en',
      schemes: ['https'],
      hosts: ['dict.youdao.com']
    },
    fallbackRoute: {
      urlPrefix: 'https://dict.youdao.com/m/result?word=',
      urlSuffix: '&lang=en',
      schemes: ['https'],
      hosts: ['dict.youdao.com']
    },
    openMode: 'current_tab_web'
  }
];

export class ExternalAppSearchService {
  listAllTargets(targetOrder: ExternalAppSearchTargetId[] = ALL_EXTERNAL_APP_SEARCH_TARGET_IDS): ExternalAppSearchTarget[] {
    const targets: ExternalAppSearchTarget[] = [];
    const addedTargetIds: ExternalAppSearchTargetId[] = [];
    targetOrder.forEach((targetId: ExternalAppSearchTargetId) => {
      const target = this.findTarget(targetId);
      if (target !== undefined && addedTargetIds.indexOf(target.id) < 0) {
        targets.push(this.buildPublicTarget(target));
        addedTargetIds.push(target.id);
      }
    });
    EXTERNAL_APP_SEARCH_TARGETS.forEach((target: ExternalAppSearchTargetDescriptor) => {
      if (addedTargetIds.indexOf(target.id) < 0) {
        targets.push(this.buildPublicTarget(target));
      }
    });
    return targets;
  }

  listVisibleTargets(input: ExternalAppSearchVisibilityInput): ExternalAppSearchTarget[] {
    if (!this.shouldShowTargets(input)) {
      return [];
    }
    const targets: ExternalAppSearchTarget[] = [];
    this.listAllTargets(input.preferences.targetOrder).forEach((target: ExternalAppSearchTarget) => {
      if (input.preferences.selectedTargetIds.indexOf(target.id) >= 0) {
        targets.push(target);
      }
    });
    return targets;
  }

  shouldShowTargets(input: ExternalAppSearchVisibilityInput): boolean {
    if (!input.inputEditing || !input.inputFocused) {
      return false;
    }
    return input.preferences.enabled && input.preferences.selectedTargetIds.length > 0;
  }

  canSubmitQuery(rawQuery: string): boolean {
    const query = this.normalizeQuery(rawQuery);
    return query.length > 0 && !looksLikeUrl(query);
  }

  buildAction(targetId: ExternalAppSearchTargetId, rawQuery: string): ExternalAppSearchAction | undefined {
    const target = this.findTarget(targetId);
    const query = this.normalizeQuery(rawQuery);
    if (target === undefined || !this.canSubmitQuery(rawQuery)) {
      return undefined;
    }
    const encodedQuery = encodeURIComponent(query);
    const nativeUrl = this.buildRouteUrl(target.nativeRoute, encodedQuery);
    const fallbackUrl = this.buildRouteUrl(target.fallbackRoute, encodedQuery);
    if (!this.hasAllowedRoute(nativeUrl, target.nativeRoute) ||
      !this.hasAllowedRoute(fallbackUrl, target.fallbackRoute)) {
      return undefined;
    }
    return {
      target: this.buildPublicTarget(target),
      query: query,
      nativeUrl: nativeUrl,
      nativeTarget: target.nativeTarget,
      fallbackUrl: fallbackUrl,
      openMode: target.openMode ?? 'external_app'
    };
  }

  buildPrivateConfirmation(target: ExternalAppSearchTarget): ExternalAppSearchPrivateConfirmation {
    return {
      title: '离开无痕模式搜索',
      message: `继续后，当前搜索词会发送给${target.title}，并由第三方应用或网站处理。`,
      confirmLabel: '继续搜索',
      cancelLabel: '取消'
    };
  }

  buildDiagnosticLine(
    action: ExternalAppSearchAction,
    phase: string,
    status: string = '',
    errorCode: string = ''
  ): string {
    const normalizedPhase = this.sanitizeDiagnosticValue(phase);
    const normalizedStatus = this.sanitizeDiagnosticValue(status);
    const normalizedErrorCode = this.sanitizeDiagnosticValue(errorCode);
    return `target=${action.target.id} phase=${normalizedPhase} status=${normalizedStatus} ` +
      `errorCode=${normalizedErrorCode} queryRedacted=1`;
  }

  private findTarget(targetId: ExternalAppSearchTargetId): ExternalAppSearchTargetDescriptor | undefined {
    for (let index = 0; index < EXTERNAL_APP_SEARCH_TARGETS.length; index += 1) {
      if (EXTERNAL_APP_SEARCH_TARGETS[index].id === targetId) {
        return EXTERNAL_APP_SEARCH_TARGETS[index];
      }
    }
    return undefined;
  }

  private normalizeQuery(value: string): string {
    return value.trim().replace(/\s+/g, ' ');
  }

  private buildPublicTarget(target: ExternalAppSearchTargetDescriptor): ExternalAppSearchTarget {
    return {
      id: target.id,
      title: target.title,
      accessibilityText: target.accessibilityText,
      iconTargetId: target.id,
      markText: target.markText
    };
  }

  private buildRouteUrl(route: ExternalAppSearchRouteDescriptor, encodedQuery: string): string {
    const routeQuery = route.usesQuery === false ? '' : encodedQuery;
    return `${route.urlPrefix}${routeQuery}${route.urlSuffix}`;
  }

  private hasAllowedRoute(url: string, route: ExternalAppSearchRouteDescriptor): boolean {
    const normalized = url.trim().toLowerCase();
    for (let schemeIndex = 0; schemeIndex < route.schemes.length; schemeIndex += 1) {
      const scheme = route.schemes[schemeIndex].toLowerCase();
      for (let hostIndex = 0; hostIndex < route.hosts.length; hostIndex += 1) {
        const prefix = `${scheme}://${route.hosts[hostIndex].toLowerCase()}`;
        if (normalized === prefix || normalized.startsWith(`${prefix}/`) || normalized.startsWith(`${prefix}?`)) {
          return true;
        }
      }
    }
    return false;
  }

  private sanitizeDiagnosticValue(value: string): string {
    return value.trim().replace(/\s+/g, '_').substring(0, 80);
  }
}
