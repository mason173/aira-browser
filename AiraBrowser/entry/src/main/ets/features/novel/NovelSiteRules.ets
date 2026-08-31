/**
 * 站点规则表(逐站实地勘察得出,非猜测)。
 *
 * 三层结构:
 * 1. **黑名单**:TXT/EPUB 下载站,没有在线正文 → 连入口都不给,避免点进去白屏。
 * 2. **规则表**:命中 host 就用该站的精确选择器,准确率最高。
 * 3. **通用兜底**:不在表内的站,用 NovelExtractionService 的容器聚类打分算法;
 *    其候选选择器池已把本表所有站点的实测选择器并入(见 NOVEL_GENERIC_* 常量),
 *    所以"通用引擎"是从这些真实站点归纳出来的,不是拍脑袋写的。
 */

export interface NovelChapterSourceRule {
  /** 当前章节来源策略;策略实现由 NovelChapterAcquisitionEngine 统一拥有。 */
  kind: string;
  /** 从章节 URL 中提取书籍身份和章节序号的正则字符串。 */
  chapterIndexPattern: string;
  chapterIndexGroup: number;
  chapterIndexBase: number;
  targetBookIdentityGroups: number[];
  /** 当前页面的书籍元数据;必须与目标章节 URL 的身份一致。 */
  pageBookGlobal: string;
  pageBookIdentityFields: string[];
  pageBookTitleField: string;
  /** 当前页面已经加载的章节清单及其资源元数据。 */
  chapterListGlobal: string;
  chapterTitleField: string;
  resourceDomainGlobal: string;
  resourceHosts: string[];
  resourceKeyField: string;
  resourceLengthField: string;
  /** 只允许拼接相对资源路径,避免规则把页面值变成任意 URL。 */
  resourcePathTemplate: string;
  /** 外链脚本中的载荷变量及安全解码链。 */
  payloadVariable: string;
  payloadDecode: string;
  titlePath: string;
  contentPath: string;
}

/** 本地编译的同源目录分页 recipe；声明式规则只能选择 DOM，不能配置传输。 */
export interface NovelCatalogPageSourceRule {
  kind: string;
  tokenSelector: string;
  tokenAttribute: string;
  endpointPath: string;
  tokenQueryName: string;
  pageQueryName: string;
  orderQueryName: string;
  orderQueryValue: string;
  initialPage: number;
  pageSize: number;
}

/**
 * 漫画章节来源配方。配方实现只存在于本地引擎，规则只选择已审阅的算法。
 * `chapterPathPattern` 仅用于章节页识别，不能携带脚本或任意执行内容。
 */
export interface ComicChapterSourceRule {
  kind: string;
  imageSelector: string;
  imageAttributes: string[];
  chapterPathPattern: string;
}

/** 本地编译的漫画书籍详情配方；声明式规则不能配置接口或响应映射。 */
export interface ComicBookSourceRule {
  kind: string;
}

export interface NovelSiteRule {
  id: string;
  hosts: string[];
  pathPrefixes?: string[];
  requiresContentQualityGate?: boolean;
  kind: string;                    // 'novel' | 'comic'
  chapterLinkSelector: string;     // 目录页里的章节链接
  contentSelector: string;         // 章节正文容器
  chapterTitleSelector: string;
  prevSelector: string;            // 空串=靠文字兜底
  nextSelector: string;
  reverseCatalog: boolean;         // 页面上是倒序,需翻正
  bookTitleSelector: string;
  authorSelector: string;
  coverSelector: string;
  synopsisSelector: string;
  catalogIncomplete: boolean;      // 目录页 HTML 只有部分章节(需接口补全,见 notes)
  chapterSource?: NovelChapterSourceRule;
  comicBookSource?: ComicBookSourceRule;
  comicChapterSource?: ComicChapterSourceRule;
  catalogPageSource?: NovelCatalogPageSourceRule;
  notes: string;
}

export interface NovelSiteRuleRuntimePayload {
  kind: string;
  hasLocalChapterSource: boolean;
  requiresContentQualityGate: boolean;
  pathPrefixes: string[];
  chapterLinkSelector: string;
  contentSelector: string;
  chapterTitleSelector: string;
  prevSelector: string;
  nextSelector: string;
  reverseCatalog: boolean;
  bookTitleSelector: string;
  authorSelector: string;
  coverSelector: string;
  synopsisSelector: string;
  catalogIncomplete: boolean;
  comicChapterSource?: ComicChapterSourceRule;
}

interface NovelBlockedSiteRule {
  hosts: string[];
  pathPrefixes?: string[];
}

/** Package-owned exclusions for pages that must not enter Novel mode. */
const NOVEL_BLOCKED_SITE_RULES: NovelBlockedSiteRule[] = [
  {
    hosts: [
      'txt80.cc',            // 纯 TXT 打包下载
      '10000txt.com',        // 网盘索引(注意其"上/下一页"其实是上/下一本书)
      'mojimoon.github.io',  // wenku8 的 EPUB 下载索引表
      'benbenmh.com'         // 当前移动/桌面页面均被 Cloudflare 403,没有可验证的章节 DOM
    ]
  },
  {
    hosts: ['sspai.com', 'vgn.cn', 'vgnlab.com.cn', 'ithome.com', 'ifanr.com', '36kr.com', 'thepaper.cn',
      'toutiao.com']
  },
  {
    hosts: ['news.qq.com', 'news.sina.com.cn', 'news.163.com', 'xinhuanet.com', 'people.com.cn',
      'chinanews.com.cn', 'gmw.cn', 'cctv.com']
  },
  {
    hosts: ['v2ex.com', 'nga.cn', 'tieba.baidu.com', 'chiphell.com', 'reddit.com', 'zhihu.com']
  },
  {
    hosts: ['youtube.com', 'youtu.be', 'v.qq.com', 'v.youku.com', 'm.youku.com', 'douyin.com', 'kuaishou.com',
      'ixigua.com']
  },
  {
    hosts: ['bilibili.com'],
    pathPrefixes: ['/video/', '/bangumi/play/']
  },
  {
    hosts: ['iqiyi.com'],
    pathPrefixes: ['/v_', '/a_', '/w_', '/play/', '/lib/m_']
  },
  {
    hosts: ['twxgct.com', 'xgcartoon.com'],
    pathPrefixes: ['/video/']
  }
];

export const NOVEL_BUNDLED_SITE_RULES: NovelSiteRule[] = [
  {
    id: 'site.bimidu',
    hosts: ['bimidu.com'],
    kind: 'novel',
    chapterLinkSelector: 'div.newzjlist ul.dirlist li.xl6 a',
    contentSelector: '#nr',
    chapterTitleSelector: 'div.play-title h1.chatit',
    prevSelector: '',
    nextSelector: '',
    reverseCatalog: false,
    bookTitleSelector: 'div.info h2',
    authorSelector: "div.info a[href^='/author/']",
    coverSelector: 'div.detail-body-body-img img',
    synopsisSelector: 'p.part.text-indent',
    catalogIncomplete: false,
    notes: 'GBK 编码;目录预览块是 li.xl12,正式目录是 li.xl6;到头时上下章 href 是 0.html 哨兵需过滤'
  },
  {
    id: 'site.linovelib',
    hosts: ['linovelib.com'],
    kind: 'novel',
    chapterLinkSelector: '#volume-list .volume ul.chapter-list li a',
    contentSelector: '#TextContent',
    chapterTitleSelector: '#mlfy_main_text h1',
    prevSelector: '',
    nextSelector: '',
    reverseCatalog: false,
    bookTitleSelector: 'h1.book-name',
    authorSelector: '.book-author .au-name a',
    coverSelector: '.book-img img',
    synopsisSelector: '.book-dec.Jbook-dec > p',
    catalogIncomplete: false,
    notes: '唯一单章分页的站(_2.html…);需桌面 UA,否则正文被截断'
  },
  {
    id: 'site.bilinovel',
    hosts: ['bilinovel.com'],
    kind: 'novel',
    chapterLinkSelector: '.jsChapter > a.chapter-li-a',
    contentSelector: '#acontent',
    chapterTitleSelector: '#atitle',
    prevSelector: '',
    nextSelector: '',
    reverseCatalog: false,
    bookTitleSelector: '.book-title',
    authorSelector: '.authorname a',
    coverSelector: 'img.book-cover',
    synopsisSelector: '#bookSummary',
    catalogIncomplete: false,
    notes: '移动站目录同时包含卷标题与章节链接;必须限定 .jsChapter 直属章节链接;' +
      '章节正文和分页由通用获取质量门与静态 HTML 回退处理'
  },
  {
    id: 'site.bqgnovels',
    hosts: ['bqgnovels.com'],
    pathPrefixes: ['/book/'],
    requiresContentQualityGate: true,
    kind: 'novel',
    chapterLinkSelector: '.v-list.list a[href]',
    contentSelector: '.container .text',
    chapterTitleSelector: 'h1.text_tit',
    prevSelector: '',
    nextSelector: '',
    reverseCatalog: false,
    bookTitleSelector: '.detail_rt > h1',
    authorSelector: '.detail_bt > p.author',
    coverSelector: '.detail > img.img',
    synopsisSelector: '.des > .des_content',
    catalogIncomplete: true,
    notes: 'Nuxt/Vuetify 站点;书籍页首屏只提供有界目录;' +
      '部分书籍使用 N、标题,站点 Profile 提供精确 DOM 证据但不绕过结构质量门'
  },
  {
    id: 'site.80dzs',
    hosts: ['80dzs.cc'],
    pathPrefixes: ['/novel/', '/dir/'],
    requiresContentQualityGate: true,
    kind: 'novel',
    chapterLinkSelector: '',
    contentSelector: '.articlecon.font-normal',
    chapterTitleSelector: '.titlename',
    prevSelector: '',
    nextSelector: '',
    reverseCatalog: false,
    bookTitleSelector: '',
    authorSelector: '',
    coverSelector: '',
    synopsisSelector: '',
    catalogIncomplete: true,
    notes: '详情与正文在 /novel/，稳定目录身份在 /dir/；声明式选择器必须保持完整同源范围'
  },
  {
    id: 'site.mayitxt',
    hosts: ['mayitxt.info'],
    pathPrefixes: ['/book/', '/showclist/', '/chapter/'],
    requiresContentQualityGate: true,
    kind: 'novel',
    chapterLinkSelector: '.mulu_uld > li > a',
    contentSelector: '.textarticle',
    chapterTitleSelector: '.read_tit h4',
    prevSelector: '.chapter a.zjBtn:first-of-type',
    nextSelector: '.chapter a.zjBtn:last-of-type',
    reverseCatalog: false,
    bookTitleSelector: '.book_inf h3',
    authorSelector: '.book_inf .aut',
    coverSelector: '.book_cov img',
    synopsisSelector: '',
    catalogIncomplete: false,
    notes: '包内站点规则覆盖书籍、目录与章节路由，并保留同源路径质量门。'
  },
  {
    id: 'site.trxsw',
    hosts: ['trxsw.com'],
    pathPrefixes: ['/tangren_', '/tangren/'],
    requiresContentQualityGate: true,
    kind: 'novel',
    chapterLinkSelector: '.vlist > li:not(.now) > a, .read > li > a',
    contentSelector: '.content',
    chapterTitleSelector: 'h1.headline',
    prevSelector: '.pager a:first-of-type',
    nextSelector: '.pager a:nth-of-type(3)',
    reverseCatalog: false,
    bookTitleSelector: '.detail .name strong',
    authorSelector: '.detail .author a',
    coverSelector: '.detail > img',
    synopsisSelector: '.intro',
    catalogIncomplete: false,
    notes: '包内站点规则覆盖两套唐人小说路由，并保留同源路径质量门。'
  },
  {
    id: 'site.80ge',
    hosts: ['wap.80ge.info'],
    pathPrefixes: ['/'],
    requiresContentQualityGate: true,
    kind: 'novel',
    chapterLinkSelector: '.chapter > li > a, .book_last dd > a',
    contentSelector: '#nr1',
    chapterTitleSelector: '#_bqgmb_h1',
    prevSelector: '',
    nextSelector: '',
    reverseCatalog: false,
    bookTitleSelector: '#bqgmb_h1',
    authorSelector: '.block_txt2 p:nth-of-type(3)',
    coverSelector: '.block_img2 img',
    synopsisSelector: '.intro_info',
    catalogIncomplete: false,
    notes: '包内移动站点规则覆盖详情、目录与章节页面，并保留内容质量门。'
  },
  {
    id: 'site.wuxianbook',
    hosts: ['wuxianbook.com'],
    kind: 'novel',
    chapterLinkSelector: 'section.load_list ul.list li a',
    contentSelector: '#text',
    chapterTitleSelector: 'h2#title',
    prevSelector: '#pre2',
    nextSelector: '#next2',
    reverseCatalog: false,
    bookTitleSelector: 'h2.detail-book-title',
    authorSelector: 'p.detail-book-author a',
    coverSelector: '.detail-header-img img',
    synopsisSelector: '.cover-xs-mate .cover-book-desc p',
    catalogIncomplete: true,
    catalogPageSource: {
      kind: 'numbered_json_list',
      tokenSelector: '#bookDetails[data-bookid]',
      tokenAttribute: 'data-bookid',
      endpointPath: '/e/extend/bookpage/pages.php',
      tokenQueryName: 'id',
      pageQueryName: 'pageNum',
      orderQueryName: 'dz',
      orderQueryValue: 'asc',
      initialPage: 0,
      pageSize: 10
    },
    notes: '书籍页 HTML 恒定只有前10章；展开100章范围时直接请求对应 pages.php 分页'
  },
  {
    id: 'site.huanmengacg',
    hosts: ['huanmengacg.com'],
    kind: 'novel',
    chapterLinkSelector: '#all-chapters-raw > li > a',
    contentSelector: '#article #content',
    chapterTitleSelector: '.text_title p.style_h1',
    prevSelector: '',
    nextSelector: '',
    reverseCatalog: false,
    bookTitleSelector: '.title-xs h1.name',
    authorSelector: '.zx-xinxi .zx-zuozhe',
    coverSelector: '.pic-img img',
    synopsisSelector: '.kan-jianjie',
    catalogIncomplete: false,
    notes: 'Cloudflare 挡后台请求 → 必须在 WebView 会话里取(当前页抽取可用,跨章 fetch 可能被挡)'
  },
  {
    id: 'site.xiaoshuo84',
    hosts: ['xiaoshuo84.cc'],
    kind: 'novel',
    chapterLinkSelector: '.pt-chapter-cont-detail.full a',
    contentSelector: '.pt-read-cont #pt-pop, .pt-read-cont .pt-read-text',
    chapterTitleSelector: '.pt-read-title h1',
    prevSelector: 'a.pt-prechapter',
    nextSelector: 'a.pt-nextchapter',
    reverseCatalog: false,
    bookTitleSelector: 'h1.novelname a',
    authorSelector: "a[href^='/author/']",
    coverSelector: 'img.pt-bookdetail-img',
    synopsisSelector: '.pt-bookdetail-intro',
    catalogIncomplete: false,
    notes: '靠 .full 这个额外 class 区分正式目录与预览块;转码聚合站,正文常年"转码失败"需兜底判空'
  },
  {
    id: 'site.guihualianpian',
    hosts: ['guihualianpian.cn'],
    kind: 'novel',
    chapterLinkSelector: '#main-list .chapter-item > a.chapter-link',
    contentSelector: '#read-content',
    chapterTitleSelector: '.chapter-info .chapter-name',
    prevSelector: '',
    nextSelector: '',
    reverseCatalog: false,
    bookTitleSelector: '.novel-detail h1.novel-title',
    authorSelector: '#author-name',
    coverSelector: '.novel-info img',
    synopsisSelector: '#novel-intro',
    catalogIncomplete: true,
    notes: '目录在 HTML 里是空占位,需走 ajax_catalog_light.php(待接);上下章是 button 无 href,只能靠目录索引推导'
  },
  {
    id: 'site.mianfei22',
    hosts: ['mianfei22.com'],
    kind: 'novel',
    chapterLinkSelector: '#add_chapter_list_link li a.chapter',
    contentSelector: '#nr1',
    chapterTitleSelector: 'h1#nr_title',
    prevSelector: 'a#pb_prev',
    nextSelector: 'a#pb_next',
    reverseCatalog: false,
    bookTitleSelector: '#add_info h1',
    authorSelector: '#add_info p:nth-of-type(1)',
    coverSelector: '',
    synopsisSelector: '#add_intro',
    catalogIncomplete: false,
    chapterSource: {
      kind: 'encoded_script_payload',
      chapterIndexPattern: '#/v3/([0-9]+)/([0-9]+)/([0-9]+)\\.html(?:[?#]|$)',
      chapterIndexGroup: 3,
      chapterIndexBase: 1,
      targetBookIdentityGroups: [1, 2],
      pageBookGlobal: 'bk',
      pageBookIdentityFields: ['keyword_id', 'book_id'],
      pageBookTitleField: 'book_name',
      chapterListGlobal: 'chapter_list',
      chapterTitleField: 'name',
      resourceDomainGlobal: 'js_domain',
      resourceHosts: ['dmit.xsjs.cc'],
      resourceKeyField: 'url_kv',
      resourceLengthField: 'len',
      resourcePathTemplate: '/load_chapter/{key}.js?t={length}&tk=0404',
      payloadVariable: 'chapter_data_str',
      payloadDecode: 'base64_uri_json',
      titlePath: 'chapter_kv.name',
      contentPath: 'chapter_kv.content'
    },
    notes: 'hash 路由伪SPA:当前页活DOM可抽,跨章不能只改hash(不监听hashchange)需整页加载;预览块 id 为 _new'
  },
  {
    id: 'site.wmanhua',
    hosts: ['wmanhua.com'],
    kind: 'comic',
    chapterLinkSelector: '.chapter-list .flex a.chaper-btn',
    contentSelector: '',
    chapterTitleSelector: '',
    prevSelector: '.footer-toolbar a:first-child',
    nextSelector: '#nextChapter',
    reverseCatalog: true,
    bookTitleSelector: '.comic-info .info h1',
    authorSelector: '.comic-info .info .author:first-of-type',
    coverSelector: '.comic-info img.cover',
    synopsisSelector: '.comic-info p.description',
    catalogIncomplete: true,
    notes: '漫画;图片靠内联脚本 num+pasd 拼;目录页只 24 章,全量需 POST /comic/{id};章节列表必须限定 .chapter-list 容器(信息区复用同 class)'
  },
  {
    id: 'site.manhuatuan',
    hosts: ['manhuatuan.com'],
    kind: 'comic',
    chapterLinkSelector: '.chapter-list a',
    contentSelector: '.chapter-images',
    chapterTitleSelector: '.center-title',
    prevSelector: '.chapter-btn .prev',
    nextSelector: '.chapter-btn .next',
    reverseCatalog: false,
    bookTitleSelector: '.comic-hero-detail h1.title',
    authorSelector: '.comic-container .info .author',
    coverSelector: '.comic-hero img.bg',
    synopsisSelector: '.comic-container .detail',
    catalogIncomplete: false,
    comicChapterSource: {
      kind: 'cms_encrypted_params',
      imageSelector: '.chapter-images img, .chapter-image img',
      imageAttributes: ['data-src', 'data-original', 'src'],
      chapterPathPattern: '^/chapter/'
    },
    notes: '已核验 CMS.chapter.decrypt(params);图片由 images_hosts + chapter_images 生成,仅调用当前页已加载的 CMS/CryptoJS 全局。'
  },
  {
    id: 'site.duokanmh',
    hosts: ['duokanmh.com'],
    kind: 'comic',
    chapterLinkSelector: '.chapter-list a',
    contentSelector: '.chapter-images',
    chapterTitleSelector: '.chapter-title',
    prevSelector: '.chapter-toolbar a:first-child',
    nextSelector: '.chapter-toolbar a:last-child',
    reverseCatalog: false,
    bookTitleSelector: '.comic-detail h1.title span:first-child',
    authorSelector: '.comic-detail .data:nth-of-type(2)',
    coverSelector: '.comic-cover img',
    synopsisSelector: '.comic-detail .desc',
    catalogIncomplete: false,
    comicChapterSource: {
      kind: 'cms_encrypted_params',
      imageSelector: '.chapter-images img, .chapter-image img',
      imageAttributes: ['data-src', 'data-original', 'src'],
      chapterPathPattern: '^/manhua/[^/]+/\\d+\\.html$'
    },
    notes: '与 manhuatuan 共用 CMS 解密协议;章节路径和目录结构已核验。'
  },
  {
    id: 'site.manmanapp',
    hosts: ['manmanapp.com'],
    kind: 'comic',
    chapterLinkSelector: '.cartoon_catalog a[href*="/comic/detail-"]',
    contentSelector: '.cartoon_chapter',
    chapterTitleSelector: '.chapter_head .title, .cartoon_chapter h1',
    prevSelector: 'a.prev',
    nextSelector: 'a.next',
    reverseCatalog: true,
    bookTitleSelector: '.cartoon_introduce .title',
    authorSelector: '.cartoon_introduce .author',
    coverSelector: '.cartoon_introduce .cover .pic img',
    synopsisSelector: '.cartoon_introduce .introduce p',
    catalogIncomplete: true,
    comicChapterSource: {
      kind: 'dom_images',
      imageSelector: '.cartoon_chapter img',
      imageAttributes: ['data-original', 'data-src', 'src'],
      chapterPathPattern: '^/comic/detail-\\d+\\.html$'
    },
    notes: '章节页静态包含 data-original 图片;目录页只展示最近一段并有点击加载更多。'
  },
  {
    id: 'site.dongmanhi',
    hosts: ['dongmanhi.com'],
    kind: 'comic',
    chapterLinkSelector: '#chapterlistload a.detail-list-form-item, .detail-list-form-con a',
    contentSelector: '.reader-content, .comic-reader',
    chapterTitleSelector: '.reader-title a[title], .reader-title',
    prevSelector: '.reader-prev',
    nextSelector: '.reader-next',
    reverseCatalog: true,
    bookTitleSelector: '.detail-info-title',
    authorSelector: '.detail-info-author, .detail-info-tip',
    coverSelector: '.detail-info-cover',
    synopsisSelector: '.detail-info-content',
    catalogIncomplete: false,
    comicChapterSource: {
      kind: 'dom_images',
      imageSelector: 'img.lazyload[data-original], .lazyBox img',
      imageAttributes: ['data-original', 'data-src', 'src'],
      chapterPathPattern: '^/manhua/\\d+/\\d+\\.html$'
    },
    notes: '章节页已核验 img.lazyload[data-original] 直出 img.dongmanhi.com 资源。'
  },
  {
    id: 'site.manben',
    hosts: ['manben.com'],
    kind: 'comic',
    chapterLinkSelector: '.chapterList a',
    contentSelector: '#cp_img',
    chapterTitleSelector: '#title',
    prevSelector: '.toolBar li:first-child a',
    nextSelector: '.toolBar li:last-child a',
    reverseCatalog: false,
    bookTitleSelector: '.detailTop .info .title',
    authorSelector: '.detailTop .info .subtitle:first-of-type',
    coverSelector: '.detailTop .content > img.cover',
    synopsisSelector: '.detailContent > p',
    catalogIncomplete: false,
    comicChapterSource: {
      kind: 'packer_inline_array',
      imageSelector: '#cp_img img',
      imageAttributes: ['src', 'data-src'],
      chapterPathPattern: '^/m\\d+/$'
    },
    notes: '移动详情模板使用 .chapterList 与 .detailTop;章节页 P.A.C.K.E.R. 内联脚本解码后得到 var newImgs 数组;禁止执行 eval。'
  },
  {
    id: 'site.dm5',
    hosts: ['dm5.com'],
    kind: 'comic',
    chapterLinkSelector: '.detail-list-2 a.chapteritem, #detail-list-select-1 a.chapteritem',
    contentSelector: '#cp_img, .view-content',
    chapterTitleSelector: '.view-fix-top-bar-title, .view-title',
    prevSelector: 'a.view-bottom-bar-item:first-child',
    nextSelector: 'a.view-bottom-bar-item[href*="/m"]',
    reverseCatalog: false,
    bookTitleSelector: '.detail-main-info-title, .detail-main-title, .book-title',
    authorSelector: '.detail-main-info-author, .author, .book-author',
    coverSelector: '.detail-main-cover img, .detail-main-bg, .book-cover img',
    synopsisSelector: '.detail-desc, .book-intro, meta[name="Description"]',
    catalogIncomplete: true,
    comicChapterSource: {
      kind: 'packer_inline_array',
      imageSelector: '#cp_img img, .view-content img',
      imageAttributes: ['src', 'data-src'],
      chapterPathPattern: '^/m\\d+/$'
    },
    notes: '与 manben 共用 P.A.C.K.E.R. newImgs 形状;章节目录可能分页。'
  },
  {
    id: 'site.zaimanhua',
    hosts: ['zaimanhua.com'],
    pathPrefixes: ['/info/', '/details/', '/view/', '/pages/comic/detail', '/pages/comic/page'],
    kind: 'comic',
    chapterLinkSelector: '.zj_list_con a[href*="/view/"], .chapter-list a[href*="/view/"], a[href*="/view/"]',
    contentSelector: '.comic_wraCon, .chapter-reader, .reader-content',
    chapterTitleSelector: '.hotrmtexth1, h1, .chapter-title',
    prevSelector: 'a.btm_chapter_btn.fl, a[rel="prev"], .prev',
    nextSelector: 'a.btm_chapter_btn.fr, a[rel="next"], .next',
    reverseCatalog: false,
    bookTitleSelector: '.comic_deCon h1 a, .comic_deCon h1, h1, .comic-title',
    authorSelector: '.comic_info .comic_info_1:nth-of-type(1) div:nth-child(2), .author, [class*="author"]',
    coverSelector: '.comic_i_img img, img[alt*="封面"], .cover img',
    synopsisSelector: '.comic_deCon_d, .description, .intro',
    catalogIncomplete: false,
    comicBookSource: {
      kind: 'zaiman_detail_json_api'
    },
    comicChapterSource: {
      kind: 'zaiman_json_api',
      imageSelector: '.chapter-reader img, .reader-content img',
      imageAttributes: ['src', 'data-src'],
      chapterPathPattern: '^(?:/view/[^/]+/\\d+/\\d+|/pages/comic/page)$'
    },
    notes: 'Nuxt 详情 DOM 不作为数据源;本地详情 API 配方覆盖桌面拼音和移动数字 ID 路由;' +
      '桌面 /view/ 与移动 /pages/comic/page 分别使用各自同源接口获取签名图片。'
  },
  {
    id: 'site.mkzhan',
    hosts: ['mkzhan.com'],
    kind: 'comic',
    chapterLinkSelector: '.chapter-item[data-href], .j-catalog-item[data-href]',
    contentSelector: '#mainView .comic-list',
    chapterTitleSelector: '.top-tool-bar .comic-name, .read-pos',
    prevSelector: '.prev-chapter',
    nextSelector: '.next-chapter',
    reverseCatalog: false,
    bookTitleSelector: '.banner__info--title, .comic-name',
    authorSelector: '.banner__info--author',
    coverSelector: '.banner__cover',
    synopsisSelector: '.comic-intro',
    catalogIncomplete: false,
    comicChapterSource: {
      kind: 'mkzhan_json_api',
      imageSelector: '#mainView .comic-list img, .comic-list img',
      imageAttributes: ['src', 'data-src'],
      chapterPathPattern: '^/\\d+/\\d+\\.html$'
    },
    notes: '已核验 comic.mkzcdn.com/chapter/content/v1 与 chapter/v1;免费章节可取,付费内容服从站点鉴权。'
  },
  {
    id: 'site.tuku',
    hosts: ['tuku.cc'],
    kind: 'comic',
    chapterLinkSelector: '.chapter-wrap a.chapter-item',
    contentSelector: '.chapter-content, .chapter-wrap',
    chapterTitleSelector: '.chapter-title, h1',
    prevSelector: 'a.prev, a[rel="prev"]',
    nextSelector: 'a.next, a[rel="next"]',
    reverseCatalog: false,
    bookTitleSelector: '.info-bg .title, .manga-title',
    authorSelector: '.info-bg .author, .author',
    coverSelector: '.info-bg img',
    synopsisSelector: '.manga-title + p, .manga-intro',
    catalogIncomplete: false,
    comicChapterSource: {
      kind: 'dom_images',
      imageSelector: 'img.no-drag.lazy.w-full[data-original], .chapter-content img',
      imageAttributes: ['data-original', 'data-src', 'src'],
      chapterPathPattern: '^/chapter\\d+/$'
    },
    notes: '章节页已核验 img.no-drag.lazy.w-full[data-original] 与签名 image*.tuku.cc 资源。'
  },
  {
    id: 'site.jjmh',
    hosts: ['jjmh.top'],
    kind: 'comic',
    chapterLinkSelector: '.chapter-list a, .book-chapter a',
    contentSelector: '.comic-content, .chapter-content',
    chapterTitleSelector: 'h1, .chapter-title',
    prevSelector: 'a[rel="prev"], .prev',
    nextSelector: 'a[rel="next"], .next',
    reverseCatalog: false,
    bookTitleSelector: '.book-title, h1',
    authorSelector: '.author, [class*="author"]',
    coverSelector: '.book-cover img, .cover img',
    synopsisSelector: '.intro, .description',
    catalogIncomplete: false,
    comicChapterSource: {
      kind: 'dom_images',
      imageSelector: 'img.lazy[data-original], .comic-content img, .chapter-content img',
      imageAttributes: ['data-original', 'data-src', 'src'],
      chapterPathPattern: '^/chapter/\\d+$'
    },
    notes: '章节页已核验大量 img.lazy[data-original];目录和章节均为同源 HTML。'
  }
];

/** 通用兜底用的正文容器候选池(并入了上表所有站点的实测选择器)。 */
export const NOVEL_GENERIC_CONTENT_IDS: string[] = [
  'chaptercontent', 'content', 'nr', 'nr1', 'text', 'TextContent',
  'read-content', 'article', 'pt-pop', 'booktext', 'BookText', 'htmlContent', 'txt'
];

/** 通用兜底用的目录链接候选池。 */
export const NOVEL_GENERIC_CATALOG_SELECTORS: string[] = [
  '#list dd a', '.listmain dd a', '.chapter-list a', 'ul.dirlist li a',
  'section.load_list ul.list li a', '#all-chapters-raw > li > a',
  '.pt-chapter-cont-detail.full a', '#volume-list ul.chapter-list li a',
  '.chapter-item > a', '#chapterlist a', 'dd a'
];

function normalizeHost(url: string): string {
  const trimmed: string = url.trim().toLowerCase();
  const schemeIndex: number = trimmed.indexOf('://');
  if (schemeIndex < 0) {
    return '';
  }
  const hostStart: number = schemeIndex + 3;
  const slashIndex: number = trimmed.indexOf('/', hostStart);
  let host: string = slashIndex >= 0 ? trimmed.substring(hostStart, slashIndex) : trimmed.substring(hostStart);
  const colonIndex: number = host.indexOf(':');
  if (colonIndex >= 0) {
    host = host.substring(0, colonIndex);
  }
  if (host.startsWith('www.')) {
    host = host.substring(4);
  }
  return host;
}

function normalizePath(url: string): string {
  const trimmed: string = url.trim();
  const schemeIndex: number = trimmed.indexOf('://');
  if (schemeIndex < 0) {
    return '';
  }
  const hostStart: number = schemeIndex + 3;
  const slashIndex: number = trimmed.indexOf('/', hostStart);
  if (slashIndex < 0) {
    return '/';
  }
  let pathEnd: number = trimmed.length;
  const queryIndex: number = trimmed.indexOf('?', slashIndex);
  const hashIndex: number = trimmed.indexOf('#', slashIndex);
  if (queryIndex >= 0) {
    pathEnd = queryIndex;
  }
  if (hashIndex >= 0 && hashIndex < pathEnd) {
    pathEnd = hashIndex;
  }
  return trimmed.substring(slashIndex, pathEnd) || '/';
}

function hostMatches(host: string, suffix: string): boolean {
  return host === suffix || host.endsWith('.' + suffix);
}

function siteScopeMatches(hosts: string[], pathPrefixes: string[], url: string): boolean {
  const host: string = normalizeHost(url);
  if (host.length === 0) {
    return false;
  }
  let matchedHost: boolean = false;
  for (let index: number = 0; index < hosts.length; index += 1) {
    if (hostMatches(host, hosts[index])) {
      matchedHost = true;
      break;
    }
  }
  if (!matchedHost) {
    return false;
  }
  if (pathPrefixes.length === 0) {
    return true;
  }
  const path: string = normalizePath(url);
  for (let index: number = 0; index < pathPrefixes.length; index += 1) {
    if (path.startsWith(pathPrefixes[index])) {
      return true;
    }
  }
  return false;
}

/** Package-owned exclusions do not receive a Novel mode entry. */
export function isBlockedNovelSite(url: string): boolean {
  for (let index: number = 0; index < NOVEL_BLOCKED_SITE_RULES.length; index += 1) {
    const rule: NovelBlockedSiteRule = NOVEL_BLOCKED_SITE_RULES[index];
    if (siteScopeMatches(rule.hosts, rule.pathPrefixes ?? [], url)) {
      return true;
    }
  }
  return false;
}

export function novelSiteRuleMatches(rule: NovelSiteRule, url: string): boolean {
  return siteScopeMatches(rule.hosts, rule.pathPrefixes ?? [], url);
}

/** 取该 URL 命中的内置站点规则;没有则返回 undefined(走通用算法)。 */
export function resolveBundledNovelSiteRule(url: string): NovelSiteRule | undefined {
  for (let index: number = 0; index < NOVEL_BUNDLED_SITE_RULES.length; index += 1) {
    const rule: NovelSiteRule = NOVEL_BUNDLED_SITE_RULES[index];
    if (novelSiteRuleMatches(rule, url)) {
      return rule;
    }
  }
  return undefined;
}

export function resolveBundledNovelSiteRuleById(id: string): NovelSiteRule | undefined {
  for (let index: number = 0; index < NOVEL_BUNDLED_SITE_RULES.length; index += 1) {
    if (NOVEL_BUNDLED_SITE_RULES[index].id === id) {
      return NOVEL_BUNDLED_SITE_RULES[index];
    }
  }
  return undefined;
}

/** 仅投影页面抽取所需字段，作者备注和本地获取策略不会进入网页上下文。 */
export function buildNovelSiteRulePayload(rule: NovelSiteRule | undefined): string {
  if (rule === undefined) {
    return 'null';
  }
  const payload: NovelSiteRuleRuntimePayload = {
    kind: rule.kind,
    hasLocalChapterSource: rule.chapterSource !== undefined,
    requiresContentQualityGate: rule.requiresContentQualityGate === true,
    pathPrefixes: rule.pathPrefixes ?? [],
    chapterLinkSelector: rule.chapterLinkSelector,
    contentSelector: rule.contentSelector,
    chapterTitleSelector: rule.chapterTitleSelector,
    prevSelector: rule.prevSelector,
    nextSelector: rule.nextSelector,
    reverseCatalog: rule.reverseCatalog,
    bookTitleSelector: rule.bookTitleSelector,
    authorSelector: rule.authorSelector,
    coverSelector: rule.coverSelector,
    synopsisSelector: rule.synopsisSelector,
    catalogIncomplete: rule.catalogIncomplete,
    comicChapterSource: rule.comicChapterSource
  };
  return JSON.stringify(payload);
}
