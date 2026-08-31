const shell = (title, mainContent, sideContent = '', headContent = '') => `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta property="og:title" content="${title}">
  <meta property="og:site_name" content="Aira Spike">
  ${headContent}
  <title>${title}</title>
  <style>
    body { font-family: sans-serif; margin: 0; }
    nav, footer, aside, main { display: block; }
    main { max-width: 760px; margin: 0 auto; }
  </style>
</head>
<body>
  <nav><a href="/membership">限时会员广告</a><a href="/topics">热门推荐第七条</a></nav>
  ${sideContent}
  ${mainContent}
  <footer>评论区置顶营销信息</footer>
</body>
</html>`;

const genericNews = shell('潮汐观测计划进入部署阶段', `
<main>
  <article class="story-body">
    <h1>潮汐观测计划进入部署阶段</h1>
    <p>苍穹计划在沿海城市部署十二座潮汐观测站。每座观测站都将连续记录水位、盐度、风速和气压，并使用统一时钟校准采样时间，从而让不同区域的数据能够直接比较。</p>
    <p>研究团队将公开全部原始数据与校准方法。公开内容还包括设备误差说明、异常样本标记和数据处理脚本，便于学校、公益机构与独立研究者复核结论。</p>
    <figure>
      <img src="https://fixture.aira.cool/tide-station.jpg" width="1200" height="800" alt="正在安装的潮汐观测设备">
      <figcaption>工程人员正在校准第一座观测站。</figcaption>
    </figure>
    <p>第一批观测结果预计在九月发布。项目组会先提供按小时整理的基础数据，随后补充潮汐周期分析以及跨区域对照报告，并持续修正公开数据中的已知问题。</p>
    <p>为了避免单一设备故障影响结果，每座站点还设置了独立供电和本地缓存。网络恢复后，缓存记录会按照采样序号补传，服务端只接受校验通过的完整批次。</p>
  </article>
</main>`, `<aside><a href="/related">热门推荐第七条：另外十篇海洋文章</a></aside>`, `
<meta name="author" content="林海研究组">
<meta property="article:published_time" content="2026-07-30T08:00:00+08:00">`);

const splitDocument = shell('山地水源调查记录', `
<div id="document-layout">
  <div class="chapter">
    <h1>山地水源调查记录</h1>
    <p>调查队沿着旧林道设置了第一组采样点，关键样本编号为青岚零四七。队员同时记录遮阴比例、岩层类型与取水时间，避免只用一次化验结果解释整个流域。</p>
    <p>所有容器在出发前完成空白对照，现场每隔三小时复核温度计。这样的重复记录能识别运输过程带来的变化，也能帮助后续团队重现采样条件。</p>
  </div>
  <div class="chapter">
    <h2>复核与发布</h2>
    <p>复核人员发现上游两个样本的标签顺序颠倒，随后通过定位轨迹和拍摄时间完成校正。修订记录保留原编号，不覆盖第一次提交的数据。</p>
    <p>完整调查记录将在冬季封山前公开，报告附带机器可读表格和逐项校验日志。任何后续修订都必须给出原因、责任人和新的校验摘要。</p>
  </div>
</div>`, `<aside class="recommendations">${Array.from({ length: 18 }, (_, index) =>
  `<a href="/long-related-${index}">热门推荐第七条：这是一段很长但不属于调查正文的关联导航文本 ${index}</a>`
).join('')}</aside>`);

const technicalDocument = shell('可靠重试协议说明', `
<main role="main">
  <article class="technical-document">
    <h1>可靠重试协议说明</h1>
    <p>初始化任务必须区分可重试失败和阻断失败。网络暂时不可用时保留原事务标记，能力缺失或云端明确拒绝时停止自动执行并等待人工处理。</p>
    <h2>退避序列</h2>
    <pre><code>retryDelays = [10, 30, 60, 120, 300]</code></pre>
    <p>每一次重试都从持久化事实重新读取状态，不能把上一次未确认的本地结果当作远端成功。确认步骤完成之前，界面只能展示等待状态。</p>
    <table>
      <thead><tr><th>分类</th><th>动作</th></tr></thead>
      <tbody><tr><td>blocked</td><td>blocked_failure_requires_manual_action</td></tr></tbody>
    </table>
    <ul>
      <li>缓存优先级必须低于持久事务标记。</li>
      <li>重试完成后必须重新执行远端确认。</li>
    </ul>
    <p>退避公式：<math><mi>d</mi><mo>=</mo><msup><mn>2</mn><mi>n</mi></msup></math>，并设置五分钟上限。</p>
    <blockquote>成功确认之后才能推进基线，失败不得伪装成无变化。</blockquote>
    <p>诊断记录必须包含执行代次、失败分类和确认耗时，但不得保存正文、账号令牌或其他不必要的页面隐私数据。</p>
  </article>
</main>`);

const shortParagraphs = shell('城市夜间巴士观察', `
<main>
  <article>
    <h1>城市夜间巴士观察</h1>
    <p>末班车在二十三点十五分驶出总站。</p>
    <p>第一站有四名乘客上车，没有人下车。</p>
    <p>司机在跨江大桥前再次检查车门状态。</p>
    <p>车内报站音量随环境噪声自动降低。</p>
    <p>观察员记录了每一站的到达和离开时间。</p>
    <p>雨势增大后，车辆平均停站时间增加。</p>
    <p>终点站仍有两条接驳线路保持运营。</p>
    <p>连续七晚记录显示周五客流最高。</p>
    <p>完整夜间巴士记录将交给交通研究组。</p>
    <p>原始表格同时保留异常值和天气备注。</p>
    <p>研究组不会用单日晚点推断长期趋势。</p>
    <p>下一轮观察将覆盖节假日和大型活动。</p>
  </article>
</main>`);

const dynamicDocument = shell('动态研究简报', `
<main>
  <article id="dynamic-article">
    <h1>动态研究简报</h1>
    <p>页面正在加载研究简报。</p>
  </article>
</main>
<script>
  setTimeout(() => {
    const article = document.querySelector('#dynamic-article');
    article.innerHTML = '<h1>动态研究简报</h1>' +
      '<p>动态正文标记为远山渲染四十二号，内容在 DOMContentLoaded 之后写入页面。</p>' +
      '<p>第二段用于确认抽取器读取的是稳定后的 live DOM，而不是初始加载占位文本。</p>' +
      '<p>第三段提供足够正文长度，避免短内容阈值掩盖动态渲染验证。</p>';
  }, 60);
</script>`);

const wechatFixture = shell('微信公众号适配器样本', `
<h1 id="activity-name">微信公众号适配器样本</h1>
<span id="js_name">Aira 研究组</span>
<span id="publish_time">2026-07-31</span>
<div id="js_content" class="rich_media_content">
  <p>微信适配器必须优先选择 js_content 容器，即使页面外围存在更长的推荐列表和二维码说明。</p>
  <p>适配器正文校验标记为海风样本二十六号，它只应出现在最后得到的阅读内容中。</p>
  <p>图片延迟地址应继续交给 Aira 的图片属性与质量处理链路，而不是由通用引擎决定最终缓存策略。</p>
  <img data-src="https://fixture.aira.cool/wechat-lazy.jpg" alt="微信延迟图片">
</div>
<div id="js_pc_qr_code">微信二维码推广噪声</div>`, `<aside>${'微信外围推荐噪声 '.repeat(80)}</aside>`);

const baikeFixture = shell('百科组合正文样本', `
<h1>百科组合正文样本</h1>
<div class="J-summary">
  <div data-tag="paragraph">百科摘要标记为星河词条九号，用于确认组合源能保留摘要而不是只读取后续章节。</div>
</div>
<div class="J-lemma-content">
  <div data-tag="header" data-level="2">定义</div>
  <div data-tag="paragraph">百科章节说明该概念由三个相互独立的步骤组成，并要求每个步骤都保留可追溯来源。</div>
  <table><tr><td>结构化表格标记</td><td>百科校验完成</td></tr></table>
</div>
<div data-tts-catalog>百科目录推广噪声</div>`, `<aside>${'百科外围导航噪声 '.repeat(80)}</aside>`);

export const deterministicCorpus = [
  {
    id: 'generic-news',
    category: 'generic',
    url: 'https://fixture.aira.cool/generic-news',
    html: genericNews,
    required: [
      '苍穹计划在沿海城市部署十二座潮汐观测站',
      '研究团队将公开全部原始数据与校准方法',
      '第一批观测结果预计在九月发布',
      '工程人员正在校准第一座观测站'
    ],
    forbidden: ['限时会员广告', '热门推荐第七条', '评论区置顶营销信息'],
    expectedMetadata: {
      title: '潮汐观测计划进入部署阶段',
      byline: '林海研究组',
      publishedAt: '2026-07-30T08:00:00+08:00',
      siteName: 'Aira Spike'
    },
    expectedImageCount: 1,
    expectedCaptionCount: 1,
    expectedAiraBlocks: [
      { type: 'image', marker: '工程人员正在校准第一座观测站' }
    ],
    expectedReadabilityBlocks: [
      { type: 'img', marker: '正在安装的潮汐观测设备' },
      { type: 'figcaption', marker: '工程人员正在校准第一座观测站' }
    ]
  },
  {
    id: 'split-document',
    category: 'generic',
    url: 'https://fixture.aira.cool/split-document',
    html: splitDocument,
    required: ['关键样本编号为青岚零四七', '复核人员发现上游两个样本的标签顺序颠倒', '完整调查记录将在冬季封山前公开'],
    forbidden: ['限时会员广告', '热门推荐第七条', '评论区置顶营销信息']
  },
  {
    id: 'technical-document',
    category: 'generic',
    url: 'https://fixture.aira.cool/technical-document',
    html: technicalDocument,
    required: [
      'retryDelays = [10, 30, 60, 120, 300]',
      'blocked_failure_requires_manual_action',
      '缓存优先级必须低于持久事务标记',
      'd=2n',
      '成功确认之后才能推进基线'
    ],
    forbidden: ['限时会员广告', '热门推荐第七条', '评论区置顶营销信息'],
    expectedAiraBlocks: [
      { type: 'code', marker: 'retryDelays = [10, 30, 60, 120, 300]' },
      { type: 'list_item', marker: '缓存优先级必须低于持久事务标记' },
      { type: 'paragraph', marker: 'blocked_failure_requires_manual_action' },
      { type: 'paragraph', marker: 'd=2n' }
    ],
    expectedReadabilityBlocks: [
      { type: 'pre', marker: 'retryDelays = [10, 30, 60, 120, 300]' },
      { type: 'li', marker: '缓存优先级必须低于持久事务标记' },
      { type: 'table', marker: 'blocked_failure_requires_manual_action' },
      { type: 'math', marker: 'd=2n' }
    ]
  },
  {
    id: 'short-chinese-paragraphs',
    category: 'generic',
    url: 'https://fixture.aira.cool/short-chinese-paragraphs',
    html: shortParagraphs,
    required: ['末班车在二十三点十五分驶出总站', '完整夜间巴士记录将交给交通研究组', '下一轮观察将覆盖节假日和大型活动'],
    forbidden: ['限时会员广告', '热门推荐第七条', '评论区置顶营销信息']
  },
  {
    id: 'dynamic-live-dom',
    category: 'generic',
    url: 'https://fixture.aira.cool/dynamic-live-dom',
    html: dynamicDocument,
    settleMs: 140,
    dynamic: true,
    required: [
      '动态正文标记为远山渲染四十二号',
      '抽取器读取的是稳定后的 live DOM',
      '第三段提供足够正文长度'
    ],
    forbidden: ['限时会员广告', '热门推荐第七条', '评论区置顶营销信息', '页面正在加载研究简报']
  },
  {
    id: 'wechat-adapter',
    category: 'adapter',
    url: 'https://mp.weixin.qq.com/s/aira-reader-spike',
    html: wechatFixture,
    required: ['微信适配器必须优先选择 js_content 容器', '适配器正文校验标记为海风样本二十六号', '图片延迟地址应继续交给 Aira'],
    forbidden: ['微信二维码推广噪声', '微信外围推荐噪声']
  },
  {
    id: 'baike-adapter',
    category: 'adapter',
    url: 'https://baike.baidu.com/item/aira-reader-spike',
    html: baikeFixture,
    required: ['百科摘要标记为星河词条九号', '百科章节说明该概念由三个相互独立的步骤组成', '结构化表格标记'],
    forbidden: ['百科目录推广噪声', '百科外围导航噪声']
  }
];

export const liveCorpus = [
  {
    id: 'mdn-javascript-guide',
    url: 'https://developer.mozilla.org/zh-CN/docs/Web/JavaScript/Guide/Introduction'
  },
  {
    id: 'wikipedia-harmonyos',
    url: 'https://zh.wikipedia.org/wiki/HarmonyOS'
  },
  {
    id: 'w3c-accessibility-intro',
    url: 'https://www.w3.org/WAI/fundamentals/accessibility-intro/'
  },
  {
    id: 'mozilla-reader-view-support',
    url: 'https://support.mozilla.org/en-US/kb/firefox-reader-view-clutter-free-web-pages'
  },
  {
    id: 'huawei-webview-controller',
    url: 'https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-webview-webviewcontroller'
  }
];
