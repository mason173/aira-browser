export interface BrowserDefaultSeedSite {
  idSuffix: string;
  title: string;
  url: string;
}

const CORE_BROWSER_SEED_SITES: BrowserDefaultSeedSite[] = [
  {
    idSuffix: 'zhihu',
    title: '知乎',
    url: 'https://www.zhihu.com/'
  },
  {
    idSuffix: 'sspai',
    title: '少数派',
    url: 'https://sspai.com/'
  },
  {
    idSuffix: 'juejin',
    title: '掘金',
    url: 'https://juejin.cn/'
  },
  {
    idSuffix: 'bilibili',
    title: '哔哩哔哩',
    url: 'https://www.bilibili.com/'
  }
];

export const DEFAULT_BROWSER_SEED_SITES: BrowserDefaultSeedSite[] = CORE_BROWSER_SEED_SITES;
