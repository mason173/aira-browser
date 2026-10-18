export interface BrowserDefaultSeedSite {
  idSuffix: string;
  title: string;
  url: string;
}

const CORE_BROWSER_SEED_SITES: BrowserDefaultSeedSite[] = [
  {
    // This slot recommends the 声栖 app and opens its AppGallery page, and it keeps the
    // id of the shortcut it replaced on purpose: every install that already seeded that
    // id keeps its own shortcut untouched, and only a fresh install seeds this one.
    // Renaming the id would re-seed this slot as a brand-new shortcut on every device.
    idSuffix: 'zhihu',
    title: '声栖',
    url: 'https://appgallery.huawei.com/app/detail?id=com.noctide.sleep'
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
