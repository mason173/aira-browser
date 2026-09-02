#!/usr/bin/env node
'use strict';

const http = require('http');
const os = require('os');
const crypto = require('crypto');
const { URL } = require('url');

const host = process.env.HOST || '0.0.0.0';
const port = Number.parseInt(process.env.PORT || '8787', 10);

function buildDownloadPayload(size, label) {
  const seed = Buffer.from(`${label}:Aira download fixture\n`, 'utf8');
  const payload = Buffer.alloc(size);
  for (let index = 0; index < size; index += 1) {
    payload[index] = seed[index % seed.length] ^ (index % 251);
  }
  return payload;
}

const downloadFixtures = {
  ctfileLike: {
    path: '/download-fixture/ctfile-like',
    fileName: '1488-苏菲的世界（贾德名作系列三部曲）.zip',
    contentType: 'application/zip',
    body: buildDownloadPayload(Math.round(4.74 * 1024 * 1024), 'ctfile-like')
  },
  plain: {
    path: '/download-fixture/plain',
    fileName: 'aira-test-64kb.txt',
    contentType: 'text/plain; charset=utf-8',
    body: buildDownloadPayload(64 * 1024, 'plain')
  },
  binary: {
    path: '/download-fixture/binary',
    fileName: 'aira-test-256kb.bin',
    contentType: 'application/octet-stream',
    body: buildDownloadPayload(256 * 1024, 'binary')
  },
  chunked: {
    path: '/download-fixture/chunked',
    fileName: 'aira-test-chunked-128kb.bin',
    contentType: 'application/octet-stream',
    body: buildDownloadPayload(128 * 1024, 'chunked')
  }
};

function esc(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function js(value) {
  return JSON.stringify(String(value ?? ''))
    .replace(/</g, '\\u003c')
    .replace(/>/g, '\\u003e')
    .replace(/&/g, '\\u0026')
    .replace(/\u2028/g, '\\u2028')
    .replace(/\u2029/g, '\\u2029');
}

function nowIso() {
  return new Date().toISOString();
}

function requestUrl(req) {
  return new URL(req.url, `http://${req.headers.host || `127.0.0.1:${port}`}`);
}

function absolute(req, path) {
  const u = requestUrl(req);
  return `${u.protocol}//${u.host}${path}`;
}

function send(res, status, body, headers = {}) {
  res.writeHead(status, {
    'Cache-Control': 'no-store',
    'X-Aira-Lab': 'manual-navigation',
    ...headers,
  });
  res.end(body);
}

const UI_TRANSLATIONS = [
  ['Navigation Lab', '导航靶场'],
  ['Page event log', '页面事件日志'],
  ['page loaded', '页面已加载'],
  ['Aira Navigation Training Target', 'Aira 导航训练靶场'],
  ['Local manual lab for messy real-world link and ArkWeb navigation behavior.', '本地手动靶场：专门模拟真实网站里乱七八糟的链接、回调、弹窗和 ArkWeb 导航行为。'],
  ['Core navigation', '基础导航'],
  ['Same-tab basics', '同标签基础跳转'],
  ['Plain links, query strings, fragments, protocol-relative links, and encoded callback-looking URLs.', '普通链接、查询参数、锚点、协议相对链接，以及长得像登录回调的编码 URL。'],
  ['Plain link', '普通链接'],
  ['Encoded URL', '编码 URL'],
  ['Protocol-relative', '协议相对链接'],
  ['Redirect chains', '重定向链路'],
  ['30x, cookies through hops, loop-like chains, HTTP Refresh, meta refresh, and JS redirects.', '30x 多跳、跨跳 cookie、类似循环的跳转、HTTP Refresh、meta refresh 和 JS 跳转。'],
  ['Loop-like x3', '类似循环 x3'],
  ['HTTP Refresh', 'HTTP Refresh 跳转'],
  ['Meta refresh', 'Meta refresh 跳转'],
  ['JS redirect', 'JS 跳转'],
  ['Errors and MIME oddities', '错误页和 MIME 怪相'],
  ['Status pages, no-content, text/plain HTML, JSON, and PDF-ish content.', '404/500/204、text/plain 里的 HTML、JSON、PDF 类内容。'],
  ['Auth, callback, and payment shapes', '登录、回调、支付形态'],
  ['OAuth / SSO', 'OAuth / SSO 登录'],
  ['Consent, popup, postMessage to opener, redirect chain, and callback URL cleanup with history.replaceState.', '授权页、弹窗、给 opener 发消息、多段重定向，以及回调后用 history.replaceState 清理地址栏。'],
  ['Open OAuth lab', '打开 OAuth 靶场'],
  ['POST and payment', 'POST 表单和支付'],
  ['POST form login, 303 after POST, 307 method-preserving redirect, and payment return pages.', 'POST 登录表单、POST 后 303、保留方法的 307，以及支付返回页。'],
  ['Open POST lab', '打开 POST 靶场'],
  ['Open payment lab', '打开支付靶场'],
  ['History API / SPA', 'History API / 单页应用'],
  ['pushState, replaceState, hash changes, transient auth parameters, and late route hydration.', 'pushState、replaceState、hash 变化、临时登录参数和延迟路由渲染。'],
  ['Open SPA lab', '打开 SPA 靶场'],
  ['Callback cleanup', '回调地址清理'],
  ['New windows, popups, and opener flows', '新窗口、弹窗和 opener'],
  ['Window open matrix', '新窗口矩阵'],
  ['target=_blank, window.open, about:blank document.write, delayed popup navigation, and opener messages.', 'target=_blank、window.open、about:blank 写入、延迟弹窗跳转和 opener 消息。'],
  ['Open popup lab', '打开弹窗靶场'],
  ['Frames', 'iframe 子框架'],
  ['Main-frame versus sub-frame links, iframe target=_blank, iframe custom scheme attempts, and frame-to-parent messages.', '主框架/子框架链接、iframe 里的 target=_blank、自定义 scheme 和 frame 给 parent 发消息。'],
  ['Open frame lab', '打开 iframe 靶场'],
  ['External schemes', '外部 App / 非 Web scheme'],
  ['User-click versus automatic non-Web schemes, fallback URLs, and common mobile app scheme shapes.', '用户点击触发和自动触发的非 Web scheme、fallback URL，以及常见移动 App scheme。'],
  ['Open scheme lab', '打开外链靶场'],
  ['Runtime hot paths', 'Web runtime 热路径'],
  ['Dialogs', 'JS 弹窗'],
  ['alert, confirm, prompt, nested dialogs, and beforeunload-style navigation guard.', 'alert、confirm、prompt、连续弹窗和 beforeunload 离开确认。'],
  ['Open dialog lab', '打开弹窗靶场'],
  ['Load lifecycle', '加载生命周期'],
  ['Slow first byte, streaming chunks, late title, late favicon, and delayed same-document visual changes.', '慢首包、流式分块、延迟 title、延迟 favicon，以及同文档延迟视觉变化。'],
  ['Slow response', '慢响应'],
  ['Streaming page', '流式页面'],
  ['Late title/favicon', '延迟标题/图标'],
  ['Scroll and sampling', '滚动和视觉采样'],
  ['Long scroll, nested scrollable content, sticky areas, color bands, and visual theme sampling.', '长滚动、嵌套滚动、固定区域、色块和页面视觉主题采样。'],
  ['Scroll lab', '滚动靶场'],
  ['Visual sampling lab', '视觉采样靶场'],
  ['Snapshot lab', '快照靶场'],
  ['Search result page', '搜索结果页'],
  ['A dense page with repeated terms for browser find/searchResultReceive verification.', '高密度重复词页面，用来验证浏览器查找/searchResultReceive。'],
  ['Search results', '搜索结果'],
  ['Downloads and weird links', '下载和怪链接'],
  ['Downloads', '下载'],
  ['Content-Disposition attachment, inline data, redirect-to-download, HTML download attribute, and blob URL download.', 'Content-Disposition 附件、内联数据、重定向到下载、HTML download 属性和 Blob URL 下载。'],
  ['Open download lab', '打开下载靶场'],
  ['URL edge cases', 'URL 边界情况'],
  ['Very long URLs, encoded redirects, @ signs, repeated params, empty fragments, and callback-like values.', '超长 URL、编码重定向、@ 符号、重复参数、空锚点和像回调的参数。'],
  ['Very long URL', '超长 URL'],
  ['Open weird links', '打开怪链接'],
  ['Optional public outbound', '可选公网外跳'],
  ['These leave the local lab and are useful for http(s) AppLinking heuristics when the phone has internet.', '这些会离开本地靶场；手机有网时可用来观察 http(s) AppLinking/外部打开策略。'],
  ['Manual note', '手动说明'],
  ['This is a manual navigation target, not an automated test suite. Open it in Aira on the phone, tap through each section, and watch whether Aira keeps normal Web navigations in Web, shows prompts for external schemes, keeps popup/opener flows alive, and updates URL/title/progress/visual state at the right time.', '这是手动导航靶场，不是自动化测试套件。用手机上的 Aira 打开后逐项点击，重点看：普通 Web 跳转是否留在 Web 内、外部 scheme 是否有提示或 fallback、popup/opener 是否不断、URL/标题/进度/视觉状态是否按时更新。'],
  ['Landing Page', '落地页'],
  ['A stable target used by redirects, popups, callbacks, and fallback flows.', '稳定落地点：重定向、弹窗、回调和 fallback 都会跳到这里。'],
  ['Received parameters', '收到的参数'],
  ['No query parameters.', '没有查询参数。'],
  ['More actions', '更多操作'],
  ['Back to index', '回到首页'],
  ['Redirect again', '再重定向一次'],
  ['Go to SPA hash', '跳到 SPA hash'],
  ['HTTP Refresh Redirect', 'HTTP Refresh 重定向'],
  ['Waiting for HTTP Refresh navigation.', '等待 HTTP Refresh 自动跳转。'],
  ['Tap fallback now', '立即点击 fallback'],
  ['Meta Refresh Redirect', 'Meta Refresh 重定向'],
  ['This page uses a meta refresh after', '这个页面会在'],
  ['JavaScript Redirect', 'JavaScript 重定向'],
  ['This page calls location.assign after', '这个页面会在延迟后调用 location.assign，延迟'],
  ['Status', '状态码'],
  ['Intentional status response for error and load lifecycle handling.', '故意返回这个状态码，用来观察错误页和加载生命周期处理。'],
  ['This endpoint responded with HTTP', '这个端点返回了 HTTP'],
  ['OAuth / SSO Lab', 'OAuth / SSO 靶场'],
  ['Real sites mix redirects, popups, opener messages, and URL cleanup after login.', '真实登录站点经常混合重定向、弹窗、opener 消息和登录后 URL 清理。'],
  ['Same-tab flows', '同标签流程'],
  ['Same-tab consent', '同标签授权'],
  ['User click on provider, then 302 callback with code/state.', '用户点击授权页，然后 302 回调并带上 code/state。'],
  ['Start same-tab', '开始同标签流程'],
  ['Redirect-chain callback', '多段重定向回调'],
  ['Consent redirects through multiple hops before landing on callback.', '授权后先经过多段跳转，再落到 callback。'],
  ['Start chain', '开始多段跳转'],
  ['A loaded callback removes code/state with history.replaceState after content is visible.', 'callback 内容已经显示后，再用 history.replaceState 移除 code/state。'],
  ['Open callback', '打开 callback'],
  ['Popup flows', '弹窗流程'],
  ['Provider opens in a new tab/window and callback posts a message to opener.', '授权页在新标签/新窗口打开，回调后给 opener 发消息。'],
  ['Open target blank', 'target blank 打开'],
  ['Explicit window.open from a user gesture.', '用户点击后显式调用 window.open。'],
  ['Delayed popup', '延迟弹窗'],
  ['window.open after 1600ms tests recent action windows and popup eligibility.', '点击后 1600ms 才 window.open，用来测最近用户动作窗口和 popup 允许策略。'],
  ['Identity Provider', '模拟身份提供方'],
  ['Simulates an SSO provider consent page.', '模拟一个 SSO 授权确认页。'],
  ['Approve and continue', '同意并继续'],
  ['Deny', '拒绝'],
  ['OAuth Callback', 'OAuth 回调页'],
  ['Callback page with transient code/state and optional opener postMessage.', '带临时 code/state 的回调页，可选给 opener 发 postMessage。'],
  ['This page will keep visible content while optionally cleaning the address bar.', '页面内容会保留可见，同时可选择清理地址栏里的临时参数。'],
  ['Go to clean session', '进入干净会话页'],
  ['OAuth Session', 'OAuth 会话页'],
  ['Clean URL after callback parameters have been removed.', '回调参数已移除后的干净 URL。'],
  ['The address should no longer contain transient code parameters.', '地址栏里不应该再有临时 code 参数。'],
  ['Back to OAuth lab', '回到 OAuth 靶场'],
  ['POST / Form Lab', 'POST / 表单靶场'],
  ['POST bodies, 303-after-POST, 307 preserve-method redirect, and form callbacks.', 'POST body、POST 后 303、307 保留方法重定向和表单回调。'],
  ['POST then 303', 'POST 后 303'],
  ['Most login forms redirect with 303/302 to a GET callback.', '很多登录表单会用 303/302 跳到 GET 回调。'],
  ['Username', '用户名'],
  ['Return URL', '返回 URL'],
  ['Submit POST 303', '提交 POST 303'],
  ['POST then 307', 'POST 后 307'],
  ['Method-preserving redirect is rarer but can break shell replay logic.', '保留方法的重定向更少见，但容易打爆壳层重放逻辑。'],
  ['Payload', '提交内容'],
  ['Submit POST 307', '提交 POST 307'],
  ['POST Landing', 'POST 落地页'],
  ['Reached after a method-preserving redirect.', '保留方法重定向后到达这里。'],
  ['Back to POST lab', '回到 POST 靶场'],
  ['Payment Redirect Lab', '支付跳转靶场'],
  ['Payment providers often mix POST, JS redirect, deep links, and callback cleanup.', '支付站点经常混合 POST、JS 跳转、deeplink 和回调清理。'],
  ['Web payment return', 'Web 支付返回'],
  ['Provider page redirects back after a delay.', '支付提供方页面延迟后跳回。'],
  ['Start web payment', '开始 Web 支付'],
  ['Payment with app fallback', 'App 支付 + fallback'],
  ['Button tries an app scheme, then returns to a Web fallback callback.', '按钮先尝试 App scheme，然后回到 Web fallback callback。'],
  ['Start scheme payment', '开始 scheme 支付'],
  ['Failed payment', '失败支付'],
  ['Provider redirects to an error callback.', '支付提供方跳到错误回调。'],
  ['Start failed payment', '开始失败支付'],
  ['Payment Provider', '模拟支付提供方'],
  ['Try app pay', '尝试 App 支付'],
  ['Return now', '立即返回'],
  ['Payment Callback', '支付回调页'],
  ['Callback with status and optional replaceState cleanup.', '带支付状态的回调页，可选 replaceState 清理。'],
  ['Open receipt', '打开收据页'],
  ['Payment Receipt', '支付收据页'],
  ['Clean receipt URL after payment callback.', '支付回调后的干净收据 URL。'],
  ['Back to payment lab', '回到支付靶场'],
  ['SPA / History API Lab', 'SPA / History API 靶场'],
  ['Same-document URL updates without full page loads.', '不完整刷新页面，只更新同文档 URL。'],
  ['History actions', 'History 操作'],
  ['pushState product', 'pushState 商品页'],
  ['pushState search', 'pushState 搜索页'],
  ['replaceState session', 'replaceState 会话页'],
  ['Change hash', '修改 hash'],
  ['Hydration simulator', '延迟渲染模拟'],
  ['Initial SPA content.', '初始 SPA 内容。'],
  ['Transient Callback Cleanup', '临时回调参数清理'],
  ['Visible content appears before transient auth parameters are removed.', '先显示可见内容，再移除临时登录参数。'],
  ['After 900ms this page calls history.replaceState.', '900ms 后此页面会调用 history.replaceState。'],
  ['New Window / Popup Lab', '新窗口 / 弹窗靶场'],
  ['Exercise target=_blank, window.open, about:blank, delayed navigation, and opener communication.', '测试 target=_blank、window.open、about:blank、延迟跳转和 opener 通信。'],
  ['target blank', 'target blank'],
  ['Plain anchor with target=_blank.', '普通 target=_blank 链接。'],
  ['window.open direct', '直接 window.open'],
  ['User-gesture direct new tab.', '用户手势触发的新标签。'],
  ['about:blank document.write', 'about:blank 写入'],
  ['Creates about:blank, writes same-origin content, then navigates later.', '先创建 about:blank，写入同源内容，再延迟跳转。'],
  ['Open about:blank write', '打开 about:blank 写入'],
  ['Delayed navigation popup', '延迟跳转弹窗'],
  ['Popup starts as blank then navigates after 1400ms.', '弹窗先是空白页，1400ms 后再跳转。'],
  ['Open delayed nav', '打开延迟跳转'],
  ['Popup opener message', '弹窗 opener 消息'],
  ['Child posts a message to opener after it loads.', '子窗口加载后给 opener 发消息。'],
  ['Open message child', '打开消息子窗口'],
  ['Burst of popups', '连续弹窗'],
  ['Creates several popups to see queueing/block behavior.', '连续创建多个弹窗，用来观察队列或拦截行为。'],
  ['Open burst', '连续打开'],
  ['Popup Child', '弹窗子页'],
  ['Child window that talks to opener and can close itself.', '会和 opener 通信、也能尝试关闭自己的子窗口。'],
  ['postMessage opener', '给 opener 发消息'],
  ['External Scheme Lab', '外部 scheme 靶场'],
  ['Compare user-clicked schemes, automatic schemes, fallback URLs, and sub-frame attempts.', '对比用户点击 scheme、自动 scheme、fallback URL 和子框架触发。'],
  ['User-click schemes', '用户点击触发'],
  ['Phone and mail', '电话和邮件'],
  ['System schemes from direct user gestures.', '直接用户手势触发的系统 scheme。'],
  ['Common app schemes', '常见 App scheme'],
  ['Custom schemes that may or may not be installed on the phone.', '手机上可能安装、也可能没安装的自定义 scheme。'],
  ['Fallback page', 'fallback 页面'],
  ['Button navigates to a scheme and then to a Web fallback.', '按钮先跳 scheme，再回到 Web fallback。'],
  ['Open fallback lab', '打开 fallback 靶场'],
  ['Automatic scheme', '自动 scheme'],
  ['Page attempts a non-Web scheme on load. This should usually be blocked or prompted differently.', '页面加载后自动尝试非 Web scheme；通常应该被拦截或以不同方式提示。'],
  ['Open auto scheme', '打开自动 scheme'],
  ['Frame scheme attempt', 'iframe scheme 尝试'],
  ['Automatic Scheme Attempt', '自动 scheme 尝试页'],
  ['This page calls location.href to a non-Web scheme shortly after load.', '此页面加载后很快会把 location.href 改成非 Web scheme。'],
  ['Manual fallback', '手动 fallback'],
  ['Scheme With Web Fallback', 'scheme + Web fallback'],
  ['Tap the button to try a scheme, then fall back to a Web URL.', '点击按钮先尝试 scheme，然后回落到 Web URL。'],
  ['Try scheme then fallback', '尝试 scheme 后 fallback'],
  ['Frame Lab', 'iframe 靶场'],
  ['Sub-frame navigations should not be confused with main-frame navigation policy.', '子框架导航不应该被误当成主框架导航策略。'],
  ['Interactive child frame', '可交互子框架'],
  ['Auto scheme child frame', '自动 scheme 子框架'],
  ['Child Frame', '子框架页面'],
  ['This is inside an iframe.', '这是 iframe 里的页面。'],
  ['Same-frame nav', '同框架跳转'],
  ['custom scheme', '自定义 scheme'],
  ['post parent', '给父页面发消息'],
  ['Auto Scheme Frame', '自动 scheme iframe'],
  ['This iframe attempts a custom scheme after load.', '这个 iframe 加载后会尝试自定义 scheme。'],
  ['Iframe auto scheme attempt starts after 1200ms.', 'iframe 会在 1200ms 后自动尝试 scheme。'],
  ['Frame fallback', 'iframe fallback'],
  ['JS Dialog Lab', 'JS 弹窗靶场'],
  ['nested dialogs', '连续弹窗'],
  ['beforeunload navigation guard', 'beforeunload 离开保护'],
  ['Nested sequence', '连续弹窗序列'],
  ['Before unload', '离开前确认'],
  ['Enable beforeunload guard', '开启离开确认'],
  ['Navigate away', '离开页面'],
  ['Slow Response', '慢响应页面'],
  ['Server waited', '服务器等待了'],
  ['before sending HTML.', '后才发送 HTML。'],
  ['This page is useful for progress, stale navigation, and late callback handling.', '这个页面用来观察进度、过期导航事件和晚到回调处理。'],
  ['Continue', '继续'],
  ['Streaming Page', '流式页面'],
  ['HTML arrives in chunks; title and body update while loading.', 'HTML 分块到达，加载过程中 body 会继续更新。'],
  ['Chunk 1 arrived.', '第 1 块已到达。'],
  ['Initial Title', '初始标题'],
  ['Title, favicon, and theme color change after load.', '标题、favicon 和 theme-color 会在加载后变化。'],
  ['Waiting for late title/favicon update.', '等待延迟标题和图标更新。'],
  ['Open favicon SVG', '打开 favicon SVG'],
  ['Scroll Interaction Lab', '滚动交互靶场'],
  ['Long page with nested scrollable content and touch-heavy bands.', '带嵌套滚动和大色块的长页面。'],
  ['Scroll slowly, fling quickly, switch tabs, return home, then come back.', '可以慢慢滚、快速甩动、切标签、回首页再回来观察。'],
  ['Nested scroll row', '嵌套滚动行'],
  ['inner scrolling should not confuse the outer Web page state.', '内部滚动不应该干扰外层 Web 页面状态。'],
  ['Scroll band', '滚动色块'],
  ['Watch toolbar, pageVisible, and visual sampling.', '观察工具栏、pageVisible 和视觉采样。'],
  ['Visual Sampling Lab', '视觉采样靶场'],
  ['Large above-the-fold color changes, theme-color changes, and delayed hero swaps.', '首屏大色块、theme-color 和延迟首屏变化。'],
  ['Initial green hero', '初始绿色首屏'],
  ['Blue section', '蓝色区域'],
  ['Warm section', '暖色区域'],
  ['Swap hero immediately', '立即切换首屏'],
  ['Delayed swap', '延迟切换'],
  ['Snapshot / Late Content Lab', '快照 / 延迟内容靶场'],
  ['Use this to inspect stored snapshots after content changes and navigation.', '用来观察内容变化和导航后的快照表现。'],
  ['Initial above-the-fold content.', '初始首屏内容。'],
  ['Mutate content', '改变内容'],
  ['Result', '结果'],
  ['navigation callback sample', '导航回调样本'],
  ['appears here with login redirect, popup, deep link, history API, scroll sampling, and download keywords.', '会和登录重定向、弹窗、deeplink、History API、滚动采样、下载关键词一起出现。'],
  ['Dense page for browser find/search result callbacks.', '高密度页面，用来观察浏览器查找和搜索结果回调。'],
  ['Query', '搜索词'],
  ['Search', '搜索'],
  ['Download Lab', '下载靶场'],
  ['Attachments, redirects to attachment, inline MIME, download attribute, and blob downloads.', '附件下载、重定向到附件、内联 MIME、download 属性和 Blob 下载。'],
  ['Server attachments', '服务端附件'],
  ['Content-Disposition attachment from the server.', '服务端返回 Content-Disposition 附件。'],
  ['TXT attachment', 'TXT 附件'],
  ['BIN attachment', 'BIN 附件'],
  ['Redirect to download', '重定向到下载'],
  ['Inline resources', '内联资源'],
  ['Resources that may render inline instead of download.', '可能直接渲染、也可能被当作下载的资源。'],
  ['Inline JSON', '内联 JSON'],
  ['PDF-like inline', '类 PDF 内联'],
  ['Client-side download', '客户端下载'],
  ['Blob URL and download attribute generated in page JS.', '页面 JS 生成的 Blob URL 和 download 属性。'],
  ['download attribute', 'download 属性'],
  ['Blob download', 'Blob 下载'],
  ['Weird Link Lab', '怪链接靶场'],
  ['Odd URL shapes often appear in ad, auth, payment, and tracking links.', '广告、登录、支付、追踪链接里经常出现这些奇怪 URL 形态。'],
  ['Query tricks', '查询参数花活'],
  ['Repeated params, @ signs, empty values, fragments, and callback-looking values.', '重复参数、@ 符号、空值、锚点和像回调的参数。'],
  ['Repeated params', '重复参数'],
  ['@ and nested URL', '@ 和嵌套 URL'],
  ['Encoded callback', '编码 callback'],
  ['Redirect wrappers', '重定向包装器'],
  ['Redirectors that hide callback targets inside encoded query parameters.', '把真实 callback 目标藏在编码参数里的跳转器。'],
  ['Encoded redirect wrapper', '编码重定向包装'],
  ['JS wrapper', 'JS 包装跳转'],
  ['Hash-heavy routes', 'Hash 路由'],
  ['Client routes and fragments with encoded path state.', '带编码路径状态的客户端路由和锚点。'],
  ['Hash callback', 'Hash callback'],
  ['Encoded fragment', '编码锚点'],
  ['Not Found', '未找到页面'],
  ['No route exists for this manual lab URL.', '这个靶场 URL 没有对应路由。'],
];

function localizeUi(markup) {
  const scriptChunks = [];
  const protectedMarkup = markup.replace(/<script\b[\s\S]*?<\/script>/gi, (chunk) => {
    const token = `__AIRA_LAB_SCRIPT_${scriptChunks.length}__`;
    scriptChunks.push(chunk);
    return token;
  });
  let localized = protectedMarkup.split(/(<[^>]+>)/g).map((chunk) => {
    if (chunk.startsWith('<')) {
      return chunk;
    }
    let text = chunk;
    for (const [source, target] of UI_TRANSLATIONS) {
      text = text.split(source).join(target);
    }
    return text;
  }).join('');
  return localized.replace(/__AIRA_LAB_SCRIPT_(\d+)__/g, (_match, index) => {
    return scriptChunks[Number(index)] ?? '';
  });
}

function html(req, title, subtitle, body, options = {}) {
  const extraHead = options.head || '';
  const extraScript = options.script || '';
  const current = requestUrl(req);
  const markup = `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <meta name="theme-color" content="${esc(options.themeColor || '#1f7a64')}">
  <title>${esc(title)}</title>
  <style>
    :root {
      color-scheme: light dark;
      --bg: #f6f7f8;
      --panel: #ffffff;
      --ink: #18211f;
      --muted: #60706c;
      --line: #d8dfdc;
      --accent: #1f7a64;
      --accent-2: #b94f33;
      --accent-3: #315f9f;
      --warn: #9a6b12;
      --danger: #aa3636;
      --shadow: 0 8px 24px rgba(20, 35, 32, .08);
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #101716;
        --panel: #18211f;
        --ink: #edf3f1;
        --muted: #a7b8b3;
        --line: #2d3d39;
        --shadow: 0 10px 28px rgba(0, 0, 0, .26);
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: var(--bg);
      color: var(--ink);
      line-height: 1.45;
    }
    header {
      position: sticky;
      top: 0;
      z-index: 10;
      border-bottom: 1px solid var(--line);
      background: color-mix(in srgb, var(--panel) 92%, transparent);
      backdrop-filter: blur(18px);
    }
    .topbar {
      display: flex;
      align-items: center;
      gap: 10px;
      min-height: 52px;
      padding: 8px 16px;
    }
    .brand {
      display: grid;
      width: 32px;
      height: 32px;
      place-items: center;
      border-radius: 8px;
      color: white;
      background: linear-gradient(135deg, var(--accent), var(--accent-3));
      font-weight: 800;
    }
    .topbar a { color: var(--accent); text-decoration: none; font-weight: 650; }
    main { max-width: 1120px; margin: 0 auto; padding: 18px 16px 42px; }
    h1 { margin: 10px 0 6px; font-size: clamp(26px, 6vw, 46px); line-height: 1.05; letter-spacing: 0; }
    h2 { margin: 28px 0 12px; font-size: 20px; }
    h3 { margin: 0 0 8px; font-size: 17px; }
    p { margin: 0 0 12px; color: var(--muted); }
    code, .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
    .hero {
      padding: 18px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      box-shadow: var(--shadow);
    }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(245px, 1fr)); gap: 12px; }
    .card {
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      padding: 14px;
      box-shadow: var(--shadow);
    }
    .stack { display: grid; gap: 10px; }
    .row { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
    a.action, button, input[type="submit"] {
      display: inline-flex;
      min-height: 38px;
      align-items: center;
      justify-content: center;
      border: 1px solid color-mix(in srgb, var(--accent) 72%, var(--line));
      border-radius: 8px;
      background: color-mix(in srgb, var(--accent) 12%, var(--panel));
      color: var(--accent);
      padding: 8px 11px;
      font: inherit;
      font-weight: 700;
      text-decoration: none;
      cursor: pointer;
    }
    a.action.secondary, button.secondary {
      border-color: var(--line);
      background: var(--panel);
      color: var(--ink);
    }
    a.action.warn, button.warn { color: var(--warn); border-color: color-mix(in srgb, var(--warn) 55%, var(--line)); }
    a.action.danger, button.danger { color: var(--danger); border-color: color-mix(in srgb, var(--danger) 55%, var(--line)); }
    input, textarea, select {
      width: 100%;
      min-height: 38px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      color: var(--ink);
      padding: 8px 10px;
      font: inherit;
    }
    label { display: grid; gap: 5px; color: var(--muted); font-size: 13px; }
    .note {
      border-left: 3px solid var(--accent);
      padding: 8px 10px;
      background: color-mix(in srgb, var(--accent) 8%, transparent);
      color: var(--muted);
    }
    .log {
      min-height: 110px;
      max-height: 210px;
      overflow: auto;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: color-mix(in srgb, var(--panel) 82%, #000 2%);
      padding: 10px;
      font-size: 12px;
      white-space: pre-wrap;
    }
    .pill {
      display: inline-flex;
      align-items: center;
      border: 1px solid var(--line);
      border-radius: 999px;
      padding: 4px 9px;
      color: var(--muted);
      font-size: 12px;
    }
    iframe {
      width: 100%;
      min-height: 230px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
    }
    .band {
      min-height: 76vh;
      display: grid;
      place-items: center;
      padding: 24px;
      color: white;
      font-size: 28px;
      font-weight: 850;
      text-align: center;
    }
    .compact-list a { display: inline-flex; margin: 4px 4px 4px 0; }
    .verdict {
      border: 1px solid color-mix(in srgb, var(--accent) 42%, var(--line));
      border-left: 5px solid var(--accent);
      border-radius: 8px;
      background: color-mix(in srgb, var(--accent) 10%, var(--panel));
      padding: 14px;
      margin: 18px 0;
    }
    .verdict h2 { margin-top: 0; }
    .verdict strong { color: var(--accent); }
    .grandma-result {
      min-height: 58px;
      border: 1px dashed var(--line);
      border-radius: 8px;
      padding: 12px;
      color: var(--muted);
      background: color-mix(in srgb, var(--panel) 92%, var(--bg));
      font-weight: 700;
    }
    .grandma-result.pass {
      border-color: color-mix(in srgb, var(--accent) 70%, var(--line));
      background: color-mix(in srgb, var(--accent) 12%, var(--panel));
      color: var(--accent);
    }
    .grandma-result.fail {
      border-color: color-mix(in srgb, var(--danger) 70%, var(--line));
      background: color-mix(in srgb, var(--danger) 10%, var(--panel));
      color: var(--danger);
    }
    .grandma-result.watch {
      border-color: color-mix(in srgb, var(--warn) 70%, var(--line));
      background: color-mix(in srgb, var(--warn) 10%, var(--panel));
      color: var(--warn);
    }
    .progressShell { height: 10px; border-radius: 999px; background: #e8edf5; overflow: hidden; margin-top: 12px; }
    .progressBar { height: 100%; width: 0%; background: var(--accent-3); transition: width .15s ease; }
    .modalMask { position: fixed; inset: 0; display: none; align-items: center; justify-content: center; background: rgba(15, 23, 42, .28); padding: 18px; z-index: 30; }
    .modalMask.show { display: flex; }
    .sheet { width: min(520px, 100%); background: var(--panel); border-radius: 8px; padding: 20px; box-shadow: 0 24px 64px rgba(15, 23, 42, .18); }
    .sheetHeader { display: flex; gap: 14px; align-items: flex-start; }
    .check { width: 52px; height: 52px; border-radius: 50%; background: color-mix(in srgb, var(--accent) 18%, var(--panel)); color: var(--accent); display: flex; align-items: center; justify-content: center; font-size: 30px; font-weight: 800; flex: 0 0 auto; }
    .close { margin-left: auto; font-size: 32px; line-height: 1; color: var(--ink); background: transparent; padding: 0 4px; border: 0; min-height: 32px; }
    .sheetTitle { font-size: 24px; font-weight: 800; margin: 0; color: var(--ink); }
    .sheetSub { font-size: 17px; margin: 4px 0 0; color: var(--muted); }
    .fileCard { display: flex; gap: 16px; align-items: center; border: 1px solid var(--line); border-radius: 8px; padding: 18px; margin: 22px 0; background: color-mix(in srgb, var(--panel) 92%, var(--bg)); }
    .fileIcon { width: 62px; height: 62px; border-radius: 8px; background: color-mix(in srgb, var(--accent-3) 12%, var(--panel)); color: var(--accent-3); display: flex; align-items: center; justify-content: center; font-size: 30px; flex: 0 0 auto; }
    .fileName { font-size: 18px; font-weight: 800; color: var(--ink); word-break: break-all; }
    .fileSize { font-size: 16px; color: var(--muted); margin-top: 6px; }
    .hint { font-size: 15px; color: var(--muted); margin-bottom: 18px; }
    .actions { display: grid; gap: 10px; }
  </style>
  ${extraHead}
</head>
<body>
  <header>
    <div class="topbar">
      <div class="brand">A</div>
      <a href="/">Aira 导航靶场</a>
      <span class="pill">${esc(current.pathname)}</span>
    </div>
  </header>
  <main>
    <section class="hero">
      <h1>${esc(title)}</h1>
      <p>${esc(subtitle)}</p>
      <p class="mono">${esc(current.href)}</p>
    </section>
    ${body}
    <h2>页面事件日志</h2>
    <div class="log" data-event-log>${esc(nowIso())} 页面已加载
</div>
  </main>
  <script>
    (function () {
      var box = document.querySelector('[data-event-log]');
      function log(message) {
        if (!box) return;
        box.textContent += new Date().toISOString() + ' ' + message + '\\n';
        box.scrollTop = box.scrollHeight;
        console.log('[aira-lab] ' + message);
      }
      window.labLog = log;
      window.addEventListener('hashchange', function () { log('hashchange -> ' + location.href); });
      window.addEventListener('popstate', function () { log('popstate -> ' + location.href); });
      window.addEventListener('pageshow', function (event) { log('pageshow persisted=' + event.persisted); });
      window.addEventListener('pagehide', function (event) { log('pagehide persisted=' + event.persisted); });
      document.addEventListener('visibilitychange', function () { log('visibility=' + document.visibilityState); });
      window.addEventListener('message', function (event) {
        log('message from ' + event.origin + ': ' + JSON.stringify(event.data));
      });
    })();
  </script>
  ${extraScript}
</body>
</html>`;
  return localizeUi(markup);
}

function sendHtml(req, res, title, subtitle, body, options = {}) {
  send(res, options.status || 200, html(req, title, subtitle, body, options), {
    'Content-Type': 'text/html; charset=utf-8',
    ...(options.headers || {}),
  });
}

function action(path, label, cls = '') {
  return `<a class="action ${esc(cls)}" href="${esc(path)}">${esc(label)}</a>`;
}

function card(title, text, controls) {
  return `<article class="card"><h3>${esc(title)}</h3><p>${esc(text)}</p><div class="compact-list">${controls}</div></article>`;
}

function parseIntParam(u, name, fallback, min = 0, max = 20000) {
  const n = Number.parseInt(u.searchParams.get(name) || '', 10);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, n));
}

function randomId(prefix) {
  return `${prefix}-${crypto.randomBytes(4).toString('hex')}`;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => {
      body += chunk;
      if (body.length > 1024 * 1024) {
        reject(new Error('Request body too large'));
        req.destroy();
      }
    });
    req.on('end', () => resolve(body));
    req.on('error', reject);
  });
}

function index(req, res) {
  const current = requestUrl(req);
  const protoRelative = `//${current.host}/landing?source=protocol-relative`;
  const longUrl = `/weird/long-url?size=4200&next=${encodeURIComponent('/landing?source=long-url')}`;
  const publicCandidates = [
    'https://maps.google.com/?q=Aira+Navigation+Lab',
    'https://m.tb.cn/',
    'https://ulink.alipay.com/',
    'https://weixin.qq.com/',
  ];
  const body = `
    <section class="verdict">
      <h2>先点这里：奶奶模式</h2>
      <p><strong>如果你不想判断技术细节，就用这个。</strong>它会把很多项目改成“点一下，然后页面直接告诉你成功还是失败”。</p>
      <p>${action('/guided', '打开奶奶模式：自动告诉我成功/失败')}</p>
    </section>

    <h2>怎么判断成功</h2>
    <div class="grid">
      ${card('普通网页跳转', '点普通链接、重定向、登录/支付回调时，Aira 应该留在网页里正常加载；地址栏、标题、进度和返回栈要跟着真实页面变化。',
        '<span class="pill">成功：页面到达预期落地页</span><span class="pill">异常：空白、回退、外部 App 抢走、地址栏还停在旧 URL</span>')}
      ${card('新窗口和弹窗', '点 target blank、window.open、about:blank 写入时，Aira 应该创建可用的新标签/子窗口；OAuth 弹窗要能给 opener 发回消息。',
        '<span class="pill">成功：新页打开且目标 URL 没丢</span><span class="pill">异常：卡住、打不开、打开空白、opener 消息收不到</span>')}
      ${card('外部 App / scheme', '点 tel/mail/weixin/alipay/自定义 scheme 时，用户点击触发可以提示或尝试打开；页面自动触发、iframe 触发不应静默劫持当前网页。',
        '<span class="pill">成功：有确认、失败能 fallback</span><span class="pill">异常：自动跳走、取消后网页状态乱了、fallback 不回来</span>')}
      ${card('SPA、慢加载和滚动', '点 SPA、慢响应、流式页面、滚动色块时，Aira 应该正确处理 history 地址变化、晚到 title/favicon、视觉采样、pageVisible 和快照。',
        '<span class="pill">成功：地址/标题/工具栏按页面变化</span><span class="pill">异常：旧标题、旧颜色、进度卡住、切回标签内容错乱</span>')}
      ${card('下载和异常 MIME', '点附件、重定向下载、Blob 下载、JSON/PDF/text/plain HTML 时，Aira 应该按下载/预览策略处理，不应该把下载当普通网页乱重放。',
        '<span class="pill">成功：下载提示或正确预览</span><span class="pill">异常：无限加载、错误打开、重复下载、返回栈异常</span>')}
      ${card('页面事件日志怎么看', '每个页面底部都有“页面事件日志”。它不是最终判定，但能帮你看到 hashchange、popstate、pageshow/pagehide、visibility、postMessage 有没有发生。',
        '<span class="pill">有问题时截图/描述当前卡片 + 地址栏 + 日志最后几行</span>')}
    </div>

    <h2>Core navigation</h2>
    <div class="grid">
      ${card('Same-tab basics', 'Plain links, query strings, fragments, protocol-relative links, and encoded callback-looking URLs.',
        action('/landing?source=same-tab&next=https%3A%2F%2Fexample.com%2Fcallback%3Fcode%3Dabc%26state%3Dxyz#frag', 'Plain link') +
        action('/landing?encoded=%E4%B8%AD%E6%96%87%20space%20%26%20symbols', 'Encoded URL') +
        action(protoRelative, 'Protocol-relative'))}
      ${card('Redirect chains', '30x, cookies through hops, loop-like chains, HTTP Refresh, meta refresh, and JS redirects.',
        action('/redirect/chain?steps=4&to=/landing%3Fsource%3Dredirect-chain', '302 x4') +
        action('/redirect/loop?i=0&max=3', 'Loop-like x3') +
        action('/redirect/refresh?seconds=2&to=/landing%3Fsource%3Dhttp-refresh', 'HTTP Refresh') +
        action('/redirect/meta?seconds=1&to=/landing%3Fsource%3Dmeta-refresh', 'Meta refresh') +
        action('/redirect/js?delay=900&to=/landing%3Fsource%3Djs-redirect', 'JS redirect'))}
      ${card('Errors and MIME oddities', 'Status pages, no-content, text/plain HTML, JSON, and PDF-ish content.',
        action('/status?code=404', '404') +
        action('/status?code=500', '500') +
        action('/status?code=204', '204 无内容（页面不变正常）') +
        action('/mime/plain-html', 'text/plain HTML（原样显示成功）') +
        action('/mime/json', 'JSON') +
        action('/mime/pdf', 'PDF-like'))}
    </div>

    <h2>Auth, callback, and payment shapes</h2>
    <div class="grid">
      ${card('OAuth / SSO', 'Consent, popup, postMessage to opener, redirect chain, and callback URL cleanup with history.replaceState.',
        action('/oauth/start', 'Open OAuth lab'))}
      ${card('POST and payment', 'POST form login, 303 after POST, 307 method-preserving redirect, and payment return pages.',
        action('/post-form', 'Open POST lab') +
        action('/payment/start', 'Open payment lab'))}
      ${card('History API / SPA', 'pushState, replaceState, hash changes, transient auth parameters, and late route hydration.',
        action('/spa', 'Open SPA lab') +
        action('/history-clean?code=abc123&state=s-' + Date.now(), 'Callback cleanup'))}
    </div>

    <h2>New windows, popups, and opener flows</h2>
    <div class="grid">
      ${card('Window open matrix', 'target=_blank, window.open, about:blank document.write, delayed popup navigation, and opener messages.',
        action('/new-window', 'Open popup lab'))}
      ${card('Frames', 'Main-frame versus sub-frame links, iframe target=_blank, iframe custom scheme attempts, and frame-to-parent messages.',
        action('/frames', 'Open frame lab'))}
      ${card('External schemes', 'User-click versus automatic non-Web schemes, fallback URLs, and common mobile app scheme shapes.',
        action('/external', 'Open scheme lab'))}
    </div>

    <h2>Runtime hot paths</h2>
    <div class="grid">
      ${card('Dialogs', 'alert, confirm, prompt, nested dialogs, and beforeunload-style navigation guard.',
        action('/dialogs', 'Open dialog lab'))}
      ${card('Load lifecycle', 'Slow first byte, streaming chunks, late title, late favicon, and delayed same-document visual changes.',
        action('/slow?delay=2400', 'Slow response') +
        action('/stream', 'Streaming page') +
        action('/late-title', 'Late title/favicon'))}
      ${card('Scroll and sampling', 'Long scroll, nested scrollable content, sticky areas, color bands, and visual theme sampling.',
        action('/scroll', 'Scroll lab') +
        action('/visual-sampling', 'Visual sampling lab') +
        action('/snapshot', 'Snapshot lab'))}
      ${card('Search result page', 'A dense page with repeated terms for browser find/searchResultReceive verification.',
        action('/search/results?q=aira', 'Search results'))}
    </div>

    <h2>Downloads and weird links</h2>
    <div class="grid">
      ${card('Downloads', 'Content-Disposition attachment, inline data, redirect-to-download, HTML download attribute, and blob URL download.',
        action('/downloads', 'Open download lab'))}
      ${card('URL edge cases', 'Very long URLs, encoded redirects, @ signs, repeated params, empty fragments, and callback-like values.',
        action(longUrl, 'Very long URL') +
        action('/weird-links', 'Open weird links'))}
      ${card('Optional public outbound', 'These leave the local lab and are useful for http(s) AppLinking heuristics when the phone has internet.',
        publicCandidates.map((href, index) => `<a class="action secondary" href="${esc(href)}">Public ${index + 1}</a>`).join(''))}
    </div>
    <h2>Manual note</h2>
    <p class="note">This is a manual navigation target, not an automated test suite. Open it in Aira on the phone, tap through each section, and watch whether Aira keeps normal Web navigations in Web, shows prompts for external schemes, keeps popup/opener flows alive, and updates URL/title/progress/visual state at the right time.</p>
  `;
  sendHtml(req, res, 'Aira Navigation Training Target', 'Local manual lab for messy real-world link and ArkWeb navigation behavior.', body);
}

function guided(req, res) {
  sendHtml(req, res, 'Aira 导航测试', '不用懂技术词。点按钮后，只看页面上的“大字结果”。', `
    <section class="verdict">
      <h2>怎么用</h2>
      <p><strong>每张卡只点一个按钮。</strong>点完后，如果页面写绿色“成功”，就算通过；如果写红色“失败”，就把这一页截图给我；黄色表示它会告诉你接下来该看什么。</p>
      <p>看不懂支付、登录、回调这些词也没关系，卡片里会直接写“点完应该看到什么”。</p>
      <p>${action('/expert', '打开专家模式', 'secondary')}</p>
    </section>

    <div class="grid">
      <article class="card stack">
        <h3>普通网页跳转</h3>
        <p>点后应该进入落地页，落地页顶部会直接写“这个场景当前算成功”。</p>
        ${action('/landing?source=guided-normal-link', '点我：普通跳转')}
        <div class="grandma-result">点按钮后看新页面顶部的“判断结果”。</div>
      </article>

      <article class="card stack">
        <h3>JS 自动跳转</h3>
        <p>点后等待一下，应该自动跳到落地页，并显示成功。</p>
        ${action('/redirect/js?delay=700&to=/landing%3Fsource%3Dguided-js-redirect', '点我：JS 自动跳转')}
        <div class="grandma-result">如果最后看到“这个场景当前算成功”，就是通过。</div>
      </article>

      <article class="card stack">
        <h3>多段重定向</h3>
        <p>点后会连续跳几次，最后到落地页并显示成功。</p>
        ${action('/redirect/chain?steps=4&to=/landing%3Fsource%3Dguided-redirect-chain', '点我：多段重定向')}
        <div class="grandma-result">如果中间没有空白、没有跳外部 App，最后成功就是通过。</div>
      </article>

      <article class="card stack">
        <h3>204 无内容</h3>
        <p>204 的技术含义就是“服务器说没有新页面”。所以真正成功的表现就是：请求成功，但当前页面不跳走。</p>
        <button onclick="runNoContentCheck()">点我：自动检查 204</button>
        <div id="result-204" class="grandma-result">还没点。</div>
      </article>

      <article class="card stack">
        <h3>text/plain HTML</h3>
        <p>这项不是要把 HTML 变成网页，而是要确认浏览器尊重 text/plain，把标签原样当文字显示。</p>
        <button onclick="runPlainHtmlCheck()">点我：自动检查 text/plain</button>
        <div id="result-plain" class="grandma-result">还没点。</div>
        ${action('/mime/plain-html', '我想亲眼看看原样文本', 'secondary')}
      </article>

      <article class="card stack">
        <h3>弹窗 / 新窗口</h3>
        <p>点后应该打开一个新页。能打开、不是空白、目标页显示成功，就算通过。</p>
        <button onclick="runPopupCheck()">点我：打开新窗口</button>
        <div id="result-popup" class="grandma-result">还没点。</div>
      </article>

      <article class="card stack">
        <h3>外部 App scheme</h3>
        <p>这项可能弹系统提示，也可能失败后回网页。重点：不要无声无息把你当前网页劫走。</p>
        <button onclick="runSchemeCheck()">点我：尝试外部 App</button>
        <div id="result-scheme" class="grandma-result">还没点。</div>
      </article>

      <article class="card stack">
        <h3>SPA 地址变化</h3>
        <p>点后停在同一页，但地址和内容会变。页面会自己告诉你是否成功。</p>
        <button onclick="runSpaCheck()">点我：自动检查 SPA</button>
        <div id="result-spa" class="grandma-result">还没点。</div>
      </article>

      <article class="card stack">
        <h3>登录回调：同一个页面跳回来</h3>
        <p>正常反应：先看到一个“模拟身份提供方”页面，再点“同意并继续”，最后看到绿色“登录回调成功”。</p>
        ${action('/oauth/authorize?mode=same', '点我：模拟登录回调')}
        <div class="grandma-result">最后看到绿色成功就是通过；如果空白、回不来、地址乱跳，就是失败。</div>
      </article>

      <article class="card stack">
        <h3>登录弹窗：新页面打开登录</h3>
        <p>正常反应：打开一个新页面登录；点“同意并继续”后，新页面显示绿色“登录回调成功”。</p>
        <a class="action" target="_blank" rel="opener" href="/oauth/authorize?mode=popup">点我：模拟登录弹窗</a>
        <div class="grandma-result">能打开新页并显示成功，就是通过；打不开、空白、卡住，就是失败。</div>
      </article>

      <article class="card stack">
        <h3>表单提交：登录表单那种</h3>
        <p>正常反应：打开表单，点提交，最后看到落地页绿色成功。</p>
        ${action('/post-form', '点我：打开表单提交')}
        <div class="grandma-result">到落地页显示成功就是通过；提交后空白或卡住就是失败。</div>
      </article>

      <article class="card stack">
        <h3>支付：网页支付后返回</h3>
        <p>正常反应：打开一个模拟支付页，等一秒多自动返回，最后看到绿色“支付回调成功”。</p>
        ${action('/payment/provider?mode=web', '点我：模拟网页支付')}
        <div class="grandma-result">等它自己跳回成功页；不要手动返回。</div>
      </article>

      <article class="card stack">
        <h3>支付：尝试打开 App 后回网页</h3>
        <p>正常反应：进入支付页后点“尝试 App 支付”，可能弹系统提示，也可能失败；最后应该回到网页并显示绿色“支付回调成功”。</p>
        ${action('/payment/provider?mode=scheme', '点我：模拟 App 支付 fallback')}
        <div class="grandma-result">如果取消/失败后还能回到成功页，就是通过；如果网页丢了或回不来，就是失败。</div>
      </article>

      <article class="card stack">
        <h3>JS 弹窗</h3>
        <p>正常反应：点 alert/confirm/prompt 时，Aira 应该正常弹出对话框，不应该卡死页面。</p>
        ${action('/dialogs', '点我：打开弹窗测试')}
        <div class="grandma-result">弹窗能显示、能关闭，页面还能继续操作，就是通过。</div>
      </article>

      <article class="card stack">
        <h3>慢加载页面</h3>
        <p>正常反应：等两秒左右，页面最后显示出来；进度不应该一直卡死。</p>
        ${action('/slow?delay=2400', '点我：模拟慢加载')}
        <div class="grandma-result">最后页面出来就是通过；一直白屏或进度不动就是失败。</div>
      </article>

      <article class="card stack">
        <h3>下载</h3>
        <p>正常反应：Aira 应该按下载处理，可能弹下载提示；不应该无限加载或重复下载。</p>
        ${action('/downloads', '点我：打开下载测试')}
        <div class="grandma-result">看到下载提示或正常预览就是通过；无限加载、疯狂重复弹，就是失败。</div>
      </article>
    </div>
  `, {
    script: `<script>
      function setResult(id, kind, text) {
        var box = document.getElementById(id);
        if (!box) return;
        box.className = 'grandma-result ' + kind;
        box.textContent = text;
      }

      function runNoContentCheck() {
        setResult('result-204', 'watch', '正在检查 204...');
        fetch('/status?code=204', { cache: 'no-store' }).then(function (response) {
          if (response.status === 204) {
            setResult('result-204', 'pass', '成功：204 本来就是“没有新内容”。请求成功，而且当前页面没有跳走，这就是正确结果。');
          } else {
            setResult('result-204', 'fail', '失败：预期状态码 204，但实际是 ' + response.status + '。');
          }
        }).catch(function (error) {
          setResult('result-204', 'fail', '失败：204 请求出错：' + error.message);
        });
      }

      function runPlainHtmlCheck() {
        setResult('result-plain', 'watch', '正在检查 text/plain...');
        fetch('/mime/plain-html', { cache: 'no-store' }).then(function (response) {
          return response.text().then(function (text) {
            var type = response.headers.get('content-type') || '';
            if (type.indexOf('text/plain') >= 0 && text.indexOf('<h1>This looks like HTML') >= 0) {
              setResult('result-plain', 'pass', '成功：服务器明确返回 text/plain，HTML 标签应该原样显示成文字。你看到 <h1> 这种标签本身，就是正确结果。');
            } else {
              setResult('result-plain', 'fail', '失败：没有按 text/plain 原样返回，或者内容不对。');
            }
          });
        }).catch(function (error) {
          setResult('result-plain', 'fail', '失败：text/plain 请求出错：' + error.message);
        });
      }

      function runPopupCheck() {
        setResult('result-popup', 'watch', '已尝试打开新窗口。请看是否出现新页面：如果新页面不是空白，并显示落地页成功，就算成功。');
        var w = window.open('/landing?source=guided-popup', '_blank');
        if (!w) {
          setResult('result-popup', 'fail', '失败：window.open 被拦截或没有创建新页面。');
        }
      }

      function runSchemeCheck() {
        setResult('result-scheme', 'watch', '现在会尝试一个假的外部 App scheme。正常情况：可以弹提示、可以失败，但不能静默把当前网页弄丢。2 秒后会回到成功页。');
        location.href = 'aira-lab://guided/open';
        setTimeout(function () {
          location.href = '/landing?source=guided-scheme-fallback';
        }, 2000);
      }

      function runSpaCheck() {
        var target = '/guided/spa-result?ok=1';
        history.pushState({ guided: true }, '', target);
        setResult('result-spa', 'pass', '成功：页面没有完整刷新，但地址已经变成 /guided/spa-result?ok=1。这说明 SPA 地址变化生效。');
        labLog('guided SPA success -> ' + location.href);
      }
    </script>`,
  });
}

function landing(req, res) {
  const u = requestUrl(req);
  const source = u.searchParams.get('source') || '';
  const verdict = source
    ? `<section class="verdict">
        <h2>判断结果</h2>
        <p><strong>这个场景当前算成功。</strong></p>
        <p>原因：页面已经到达落地页，并且收到了 <span class="mono">source=${esc(source)}</span>。这说明前面的跳转链路没有被外部 App 抢走，也没有卡在旧页面或空白页。</p>
        <p>如果你看到的是空白页、地址栏还停在旧 URL、Aira 自己回退、或者跳去了外部 App 回不来，那才算异常。</p>
      </section>`
    : `<section class="verdict">
        <h2>判断结果</h2>
        <p><strong>这是普通落地页。</strong></p>
        <p>如果你是从某个按钮跳过来的，重点看上方 URL 和下面“收到的参数”是否符合你刚才点的场景。</p>
      </section>`;
  const rows = Array.from(u.searchParams.entries())
    .map(([key, value]) => `<p><strong>${esc(key)}</strong>: <span class="mono">${esc(value)}</span></p>`)
    .join('') || '<p>No query parameters.</p>';
  sendHtml(req, res, 'Landing Page', 'A stable target used by redirects, popups, callbacks, and fallback flows.', `
    ${verdict}
    <h2>Received parameters</h2>
    <div class="card">${rows}<p><strong>Hash</strong>: <span class="mono">${esc(u.hash || '(none)')}</span></p></div>
    <h2>More actions</h2>
    <div class="row">
      ${action('/', 'Back to index')}
      ${action('/redirect/chain?steps=2&to=/landing%3Fsource%3Dlanding-chain', 'Redirect again', 'secondary')}
      ${action('/spa#landing-fragment', 'Go to SPA hash', 'secondary')}
    </div>
  `);
}

function redirectChain(req, res, u) {
  const steps = parseIntParam(u, 'steps', 1, 0, 20);
  const hop = parseIntParam(u, 'hop', 0, 0, 20);
  const target = u.searchParams.get('to') || '/landing?source=redirect-chain-final';
  if (steps <= 0) {
    send(res, 302, '', { Location: target, 'Set-Cookie': `labRedirectFinal=${hop}; Path=/; SameSite=Lax` });
    return;
  }
  const next = `/redirect/chain?steps=${steps - 1}&hop=${hop + 1}&to=${encodeURIComponent(target)}`;
  send(res, 302, '', { Location: next, 'Set-Cookie': `labHop${hop}=${Date.now()}; Path=/; SameSite=Lax` });
}

function redirectLoop(req, res, u) {
  const i = parseIntParam(u, 'i', 0, 0, 10);
  const max = parseIntParam(u, 'max', 3, 0, 10);
  if (i >= max) {
    send(res, 302, '', { Location: `/landing?source=loop-ended&hops=${i}` });
    return;
  }
  send(res, 302, '', { Location: `/redirect/loop?i=${i + 1}&max=${max}` });
}

function refreshRedirect(req, res, u) {
  const seconds = parseIntParam(u, 'seconds', 2, 0, 10);
  const target = u.searchParams.get('to') || '/landing?source=http-refresh';
  sendHtml(req, res, 'HTTP Refresh Redirect', `This page sends Refresh: ${seconds}; url=${target}.`, `
    <div class="card">
      <p>Waiting for HTTP Refresh navigation.</p>
      ${action(target, 'Tap fallback now')}
    </div>
  `, { headers: { Refresh: `${seconds}; url=${target}` } });
}

function metaRedirect(req, res, u) {
  const seconds = parseIntParam(u, 'seconds', 1, 0, 10);
  const target = u.searchParams.get('to') || '/landing?source=meta-refresh';
  sendHtml(req, res, 'Meta Refresh Redirect', `This page uses a meta refresh after ${seconds}s.`, `
    <div class="card"><p>Meta refresh target: <span class="mono">${esc(target)}</span></p>${action(target, 'Tap fallback now')}</div>
  `, { head: `<meta http-equiv="refresh" content="${seconds}; url=${esc(target)}">` });
}

function jsRedirect(req, res, u) {
  const delay = parseIntParam(u, 'delay', 700, 0, 10000);
  const target = u.searchParams.get('to') || '/landing?source=js-redirect';
  sendHtml(req, res, 'JavaScript Redirect', `This page calls location.assign after ${delay}ms.`, `
    <div class="card"><p>JS target: <span class="mono">${esc(target)}</span></p>${action(target, 'Tap fallback now')}</div>
  `, { script: `<script>setTimeout(function(){ labLog('location.assign(${esc(target)})'); location.assign(${js(target)}); }, ${delay});</script>` });
}

function statusPage(req, res, u) {
  const code = parseIntParam(u, 'code', 404, 100, 599);
  if (code === 204) {
    send(res, 204, '', { 'Content-Type': 'text/plain; charset=utf-8' });
    return;
  }
  sendHtml(req, res, `Status ${code}`, 'Intentional status response for error and load lifecycle handling.', `
    <div class="card">
      <p>This endpoint responded with HTTP ${code}.</p>
      ${action('/', 'Back to index')}
    </div>
  `, { status: code });
}

function oauthStart(req, res) {
  sendHtml(req, res, 'OAuth / SSO Lab', 'Real sites mix redirects, popups, opener messages, and URL cleanup after login.', `
    <h2>Same-tab flows</h2>
    <div class="grid">
      ${card('Same-tab consent', 'User click on provider, then 302 callback with code/state.', action('/oauth/authorize?mode=same', 'Start same-tab'))}
      ${card('Redirect-chain callback', 'Consent redirects through multiple hops before landing on callback.', action('/oauth/authorize?mode=chain', 'Start chain'))}
      ${card('Callback cleanup', 'A loaded callback removes code/state with history.replaceState after content is visible.', action('/oauth/callback?mode=same&clean=1&code=manual-code&state=manual-state', 'Open callback'))}
    </div>
    <h2>Popup flows</h2>
    <div class="grid">
      ${card('target=_blank provider', 'Provider opens in a new tab/window and callback posts a message to opener.', '<a class="action" target="_blank" rel="opener" href="/oauth/authorize?mode=popup">Open target blank</a>')}
      ${card('window.open provider', 'Explicit window.open from a user gesture.', '<button onclick="openOAuthPopup()">window.open OAuth</button>')}
      ${card('Delayed popup', 'window.open after 1600ms tests recent action windows and popup eligibility.', '<button onclick="delayedOAuthPopup()">Delayed popup</button>')}
    </div>
  `, {
    script: `<script>
      function openOAuthPopup() {
        var w = window.open('/oauth/authorize?mode=popup', '_blank', 'popup,width=520,height=640');
        labLog('window.open OAuth -> ' + !!w);
      }
      function delayedOAuthPopup() {
        labLog('delayed popup scheduled');
        setTimeout(openOAuthPopup, 1600);
      }
    </script>`,
  });
}

function oauthAuthorize(req, res, u) {
  const mode = u.searchParams.get('mode') || 'same';
  const state = randomId('state');
  const code = randomId('code');
  const callback = `/oauth/callback?mode=${encodeURIComponent(mode)}&clean=1&code=${encodeURIComponent(code)}&state=${encodeURIComponent(state)}`;
  const approveTarget = mode === 'chain'
    ? `/redirect/chain?steps=3&to=${encodeURIComponent(callback)}`
    : callback;
  sendHtml(req, res, 'Identity Provider', `Mode: ${mode}. Simulates an SSO provider consent page.`, `
    <div class="card">
      <p>State: <span class="mono">${esc(state)}</span></p>
      <p>Code: <span class="mono">${esc(code)}</span></p>
      ${action(approveTarget, 'Approve and continue')}
      ${action('/oauth/callback?error=access_denied&state=' + encodeURIComponent(state), 'Deny', 'warn')}
    </div>
  `);
}

function oauthCallback(req, res, u) {
  const mode = u.searchParams.get('mode') || 'same';
  const clean = u.searchParams.get('clean') === '1';
  const code = u.searchParams.get('code') || '';
  const state = u.searchParams.get('state') || '';
  const cleanPath = `/oauth/session?state=${encodeURIComponent(state || 'none')}`;
  sendHtml(req, res, 'OAuth Callback', 'Callback page with transient code/state and optional opener postMessage.', `
    <section class="verdict">
      <h2>判断结果</h2>
      <p><strong>登录回调成功。</strong></p>
      <p>你已经从模拟登录页回到了回调页，并且页面没有空白、没有丢失、没有被外部 App 抢走。这就是正常结果。</p>
      <p>如果等一下地址栏里的 code/state 自动消失，但页面还留在这里，也仍然是成功：这叫“回调参数清理”。</p>
    </section>
    <div class="card">
      <p>Mode: <span class="mono">${esc(mode)}</span></p>
      <p>Code: <span class="mono">${esc(code)}</span></p>
      <p>State: <span class="mono">${esc(state)}</span></p>
      <p>This page will keep visible content while optionally cleaning the address bar.</p>
      ${action(cleanPath, 'Go to clean session')}
    </div>
  `, {
    script: `<script>
      setTimeout(function () {
        if (${clean ? 'true' : 'false'}) {
          history.replaceState({ lab: 'oauth-clean' }, '', ${js(cleanPath)});
          labLog('history.replaceState cleaned callback URL');
        }
        if (window.opener) {
          window.opener.postMessage({ type: 'aira-lab-oauth', code: ${js(code)}, state: ${js(state)}, cleaned: ${clean ? 'true' : 'false'} }, location.origin);
          labLog('posted OAuth result to opener');
        }
      }, 700);
    </script>`,
  });
}

function oauthSession(req, res) {
  sendHtml(req, res, 'OAuth Session', 'Clean URL after callback parameters have been removed.', `
    <section class="verdict">
      <h2>判断结果</h2>
      <p><strong>登录回调清理成功。</strong></p>
      <p>地址栏里的临时 code 已经被清掉，页面内容还在，没有回退到旧页面，这就是正常结果。</p>
    </section>
    <div class="card">
      <p>The address should no longer contain transient code parameters.</p>
      ${action('/oauth/start', 'Back to OAuth lab')}
    </div>
  `);
}

async function postForm(req, res, u) {
  if (req.method === 'GET') {
    sendHtml(req, res, 'POST / Form Lab', 'POST bodies, 303-after-POST, 307 preserve-method redirect, and form callbacks.', `
      <div class="grid">
        <form class="card" method="post" action="/post-submit?kind=303">
          <h3>POST then 303</h3>
          <p>Most login forms redirect with 303/302 to a GET callback.</p>
          <label>Username<input name="username" value="manual-user"></label>
          <label>Return URL<input name="returnTo" value="/landing?source=post-303"></label>
          <input type="submit" value="Submit POST 303">
        </form>
        <form class="card" method="post" action="/post-submit?kind=307">
          <h3>POST then 307</h3>
          <p>Method-preserving redirect is rarer but can break shell replay logic.</p>
          <label>Payload<textarea name="payload">large form payload for navigation lab</textarea></label>
          <input type="submit" value="Submit POST 307">
        </form>
      </div>
    `);
    return;
  }
  sendHtml(req, res, 'POST Lab', 'Use GET /post-form to open the form.', `${action('/post-form', 'Open form')}`);
}

async function postSubmit(req, res, u) {
  const body = req.method === 'POST' ? await readBody(req) : '';
  const fields = new URLSearchParams(body);
  const kind = u.searchParams.get('kind') || '303';
  if (kind === '307') {
    send(res, 307, '', { Location: '/post-landing?kind=307' });
    return;
  }
  const returnTo = fields.get('returnTo') || '/landing?source=post-303';
  send(res, 303, '', { Location: returnTo });
}

async function postLanding(req, res) {
  const body = req.method === 'POST' ? await readBody(req) : '';
  sendHtml(req, res, 'POST Landing', 'Reached after a method-preserving redirect.', `
    <section class="verdict">
      <h2>判断结果</h2>
      <p><strong>表单提交成功。</strong></p>
      <p>表单提交后还能到达这个页面，说明 POST 跳转没有被浏览器壳层弄丢。方法显示成 POST 或 GET 都可能是不同重定向策略下的正常现象。</p>
    </section>
    <div class="card">
      <p>Method: <span class="mono">${esc(req.method)}</span></p>
      <p>Body:</p>
      <pre class="mono">${esc(body || '(empty)')}</pre>
      ${action('/post-form', 'Back to POST lab')}
    </div>
  `);
}

function paymentStart(req, res) {
  sendHtml(req, res, 'Payment Redirect Lab', 'Payment providers often mix POST, JS redirect, deep links, and callback cleanup.', `
    <div class="grid">
      ${card('Web payment return', 'Provider page redirects back after a delay.', action('/payment/provider?mode=web', 'Start web payment'))}
      ${card('Payment with app fallback', 'Button tries an app scheme, then returns to a Web fallback callback.', action('/payment/provider?mode=scheme', 'Start scheme payment'))}
      ${card('Failed payment', 'Provider redirects to an error callback.', action('/payment/provider?mode=fail', 'Start failed payment', 'warn'))}
    </div>
  `);
}

function paymentProvider(req, res, u) {
  const mode = u.searchParams.get('mode') || 'web';
  const trade = randomId('trade');
  let script = '';
  let controls = '';
  if (mode === 'scheme') {
    controls = `<button onclick="payInApp()">尝试 App 支付</button>`;
    script = `<script>
      function payInApp() {
        labLog('navigating to alipay://platformapi/startapp with fallback');
        location.href = 'alipay://platformapi/startapp?appId=20000067&url=' + encodeURIComponent(location.origin + '/payment/callback?trade=${trade}&status=paid-via-fallback');
        setTimeout(function () { location.href = '/payment/callback?trade=${trade}&status=fallback-web'; }, 1800);
      }
    </script>`;
  } else {
    const status = mode === 'fail' ? 'failed' : 'paid';
    script = `<script>setTimeout(function(){ location.href = '/payment/callback?trade=${trade}&status=${status}&clean=1'; }, 1200);</script>`;
    controls = action(`/payment/callback?trade=${trade}&status=${status}&clean=1`, '不想等，立即返回');
  }
  sendHtml(req, res, 'Payment Provider', `Mode: ${mode}.`, `
    <section class="verdict">
      <h2>现在发生什么</h2>
      <p><strong>这是模拟支付页。</strong></p>
      <p>${mode === 'scheme'
        ? '请点下面“尝试 App 支付”。正常情况是：可能弹外部 App 提示，也可能失败；但最后应该回到网页并显示“支付回调成功”。'
        : '不用操作，等一秒多，它会自动跳回支付回调页。最后看到“支付回调成功”就是通过。'}</p>
    </section>
    <div class="card"><p>Trade: <span class="mono">${trade}</span></p>${controls}</div>
  `, { script });
}

function paymentCallback(req, res, u) {
  const clean = u.searchParams.get('clean') === '1';
  const trade = u.searchParams.get('trade') || '';
  const status = u.searchParams.get('status') || 'unknown';
  const cleanPath = `/payment/receipt?trade=${encodeURIComponent(trade)}&status=${encodeURIComponent(status)}`;
  sendHtml(req, res, 'Payment Callback', 'Callback with status and optional replaceState cleanup.', `
    <section class="verdict">
      <h2>判断结果</h2>
      <p><strong>支付回调成功。</strong></p>
      <p>你已经从模拟支付页回到了网页回调页。只要这里不是空白、没有卡死、没有丢到外部 App 回不来，就算通过。</p>
      <p>如果等一下地址栏从 callback 变成 receipt，但页面内容还在，也是成功：这是支付回调后的地址清理。</p>
    </section>
    <div class="card">
      <p>Trade: <span class="mono">${esc(trade)}</span></p>
      <p>Status: <span class="mono">${esc(status)}</span></p>
      ${action(cleanPath, 'Open receipt')}
    </div>
  `, {
    script: `<script>
      if (${clean ? 'true' : 'false'}) {
        setTimeout(function () {
          history.replaceState({ lab: 'payment-clean' }, '', ${js(cleanPath)});
          labLog('payment callback URL cleaned');
        }, 650);
      }
    </script>`,
  });
}

function paymentReceipt(req, res) {
  sendHtml(req, res, 'Payment Receipt', 'Clean receipt URL after payment callback.', `
    <section class="verdict">
      <h2>判断结果</h2>
      <p><strong>支付回调清理成功。</strong></p>
      <p>支付 callback 后地址栏已经清理成 receipt 页面，内容没有丢，这就是正常结果。</p>
    </section>
    ${action('/payment/start', 'Back to payment lab')}
  `);
}

function spa(req, res) {
  sendHtml(req, res, 'SPA / History API Lab', 'Same-document URL updates without full page loads.', `
    <div class="grid">
      <div class="card stack">
        <h3>History actions</h3>
        <button onclick="pushRoute('/spa/products?id=42&tab=details')">pushState product</button>
        <button onclick="pushRoute('/spa/search?q=aira&filter=history')">pushState search</button>
        <button onclick="replaceRoute('/spa/session')">replaceState session</button>
        <button onclick="location.hash = 'fragment-' + Date.now()">Change hash</button>
        <button onclick="history.back()">history.back</button>
      </div>
      <div class="card">
        <h3>Hydration simulator</h3>
        <p id="spa-content">Initial SPA content.</p>
      </div>
    </div>
  `, {
    script: `<script>
      function render(label) {
        document.getElementById('spa-content').textContent = label + ' at ' + new Date().toISOString();
      }
      function pushRoute(path) {
        history.pushState({ path: path }, '', path);
        render('pushState ' + path);
        labLog('pushState ' + path);
      }
      function replaceRoute(path) {
        history.replaceState({ path: path }, '', path);
        render('replaceState ' + path);
        labLog('replaceState ' + path);
      }
      window.addEventListener('popstate', function () { render('popstate ' + location.pathname + location.search + location.hash); });
      setTimeout(function () { render('late hydration for ' + location.href); document.title = 'SPA hydrated'; }, 1400);
    </script>`,
  });
}

function historyClean(req, res, u) {
  const code = u.searchParams.get('code') || '';
  const state = u.searchParams.get('state') || '';
  const next = `/history-clean/session?state=${encodeURIComponent(state)}`;
  sendHtml(req, res, 'Transient Callback Cleanup', 'Visible content appears before transient auth parameters are removed.', `
    <div class="card">
      <p>Code: <span class="mono">${esc(code)}</span></p>
      <p>State: <span class="mono">${esc(state)}</span></p>
      <p>After 900ms this page calls history.replaceState.</p>
    </div>
  `, {
    script: `<script>setTimeout(function(){ history.replaceState({ cleaned: true }, '', ${js(next)}); labLog('cleaned transient callback params'); }, 900);</script>`,
  });
}

function newWindow(req, res) {
  sendHtml(req, res, 'New Window / Popup Lab', 'Exercise target=_blank, window.open, about:blank, delayed navigation, and opener communication.', `
    <div class="grid">
      ${card('target blank', 'Plain anchor with target=_blank.', '<a class="action" target="_blank" rel="opener" href="/landing?source=target-blank">Open target blank</a>')}
      ${card('window.open direct', 'User-gesture direct new tab.', '<button onclick="openDirect()">window.open direct</button>')}
      ${card('about:blank document.write', 'Creates about:blank, writes same-origin content, then navigates later.', '<button onclick="openAboutBlank()">Open about:blank write</button>')}
      ${card('Delayed navigation popup', 'Popup starts as blank then navigates after 1400ms.', '<button onclick="openDelayedNav()">Open delayed nav</button>')}
      ${card('Popup opener message', 'Child posts a message to opener after it loads.', '<button onclick="openMessageChild()">Open message child</button>')}
      ${card('Burst of popups', 'Creates several popups to see queueing/block behavior.', '<button class="warn" onclick="openBurst()">Open burst</button>')}
    </div>
  `, {
    script: `<script>
      function openDirect() {
        var w = window.open('/landing?source=window-open-direct', '_blank');
        labLog('direct window.open -> ' + !!w);
      }
      function openAboutBlank() {
        var w = window.open('about:blank', '_blank');
        labLog('about:blank window.open -> ' + !!w);
        if (!w) return;
        w.document.write('<!doctype html><title>Written popup</title><h1>Written about:blank popup</h1><p>This page was document.write() from opener.</p><button onclick="window.opener.postMessage({type:\\'written-popup\\'}, location.origin)">postMessage opener</button>');
        w.document.close();
        setTimeout(function () {
          try { w.location.href = '/landing?source=aboutblank-written-delayed'; } catch (err) { labLog('delayed popup nav failed ' + err.message); }
        }, 1400);
      }
      function openDelayedNav() {
        var w = window.open('about:blank', '_blank');
        if (!w) return;
        setTimeout(function () { try { w.location.href = '/landing?source=delayed-popup-location'; } catch (err) {} }, 1400);
      }
      function openMessageChild() {
        window.open('/popup-child?message=hello-opener', '_blank');
      }
      function openBurst() {
        for (var i = 0; i < 4; i += 1) {
          window.open('/landing?source=popup-burst-' + i, '_blank');
        }
      }
    </script>`,
  });
}

function popupChild(req, res, u) {
  const message = u.searchParams.get('message') || 'hello';
  sendHtml(req, res, 'Popup Child', 'Child window that talks to opener and can close itself.', `
    <div class="card">
      <p>Message: <span class="mono">${esc(message)}</span></p>
      <button onclick="sendMessage()">postMessage opener</button>
      <button class="secondary" onclick="window.close()">window.close</button>
    </div>
  `, {
    script: `<script>
      function sendMessage() {
        if (window.opener) {
          window.opener.postMessage({ type: 'aira-lab-popup', message: ${js(message)}, href: location.href }, location.origin);
          labLog('message posted');
        } else {
          labLog('no opener');
        }
      }
      setTimeout(sendMessage, 700);
    </script>`,
  });
}

function external(req, res) {
  const autoTarget = encodeURIComponent('aira-lab://auto/open?fallback=' + absolute(req, '/landing?source=auto-scheme-fallback'));
  const fallbackTarget = encodeURIComponent('weixin://scanqrcode');
  const fallback = encodeURIComponent('/landing?source=scheme-fallback');
  sendHtml(req, res, 'External Scheme Lab', 'Compare user-clicked schemes, automatic schemes, fallback URLs, and sub-frame attempts.', `
    <h2>User-click schemes</h2>
    <div class="grid">
      ${card('Phone and mail', 'System schemes from direct user gestures.',
        '<a class="action" href="tel:10086">tel:</a>' +
        '<a class="action" href="sms:10086">sms:</a>' +
        '<a class="action" href="mailto:hello@example.com?subject=Aira%20Lab">mailto:</a>')}
      ${card('Common app schemes', 'Custom schemes that may or may not be installed on the phone.',
        '<a class="action" href="weixin://scanqrcode">weixin://</a>' +
        '<a class="action" href="alipay://platformapi/startapp?appId=20000067">alipay://</a>' +
        '<a class="action" href="market://details?id=com.example.fake">market://</a>' +
        '<a class="action" href="aira-lab://open/path?x=1">aira-lab://</a>')}
      ${card('Fallback page', 'Button navigates to a scheme and then to a Web fallback.',
        action(`/scheme/fallback?target=${fallbackTarget}&fallback=${fallback}`, 'Open fallback lab'))}
      ${card('Automatic scheme', 'Page attempts a non-Web scheme on load. This should usually be blocked or prompted differently.',
        action(`/scheme/auto?target=${autoTarget}`, 'Open auto scheme', 'warn'))}
    </div>
    <h2>Frame scheme attempt</h2>
    <iframe src="/frame/auto-scheme"></iframe>
  `);
}

function schemeAuto(req, res, u) {
  const target = u.searchParams.get('target') || 'aira-lab://auto';
  sendHtml(req, res, 'Automatic Scheme Attempt', 'This page calls location.href to a non-Web scheme shortly after load.', `
    <div class="card">
      <p>Target: <span class="mono">${esc(target)}</span></p>
      ${action('/landing?source=auto-scheme-manual-fallback', 'Manual fallback')}
    </div>
  `, { script: `<script>setTimeout(function(){ labLog('auto scheme -> ${esc(target)}'); location.href = ${js(target)}; }, 700);</script>` });
}

function schemeFallback(req, res, u) {
  const target = u.searchParams.get('target') || 'aira-lab://fallback';
  const fallback = u.searchParams.get('fallback') || '/landing?source=scheme-fallback';
  sendHtml(req, res, 'Scheme With Web Fallback', 'Tap the button to try a scheme, then fall back to a Web URL.', `
    <div class="card">
      <p>Scheme: <span class="mono">${esc(target)}</span></p>
      <p>Fallback: <span class="mono">${esc(fallback)}</span></p>
      <button onclick="go()">Try scheme then fallback</button>
    </div>
  `, {
    script: `<script>
      function go() {
        labLog('scheme fallback begin');
        location.href = ${js(target)};
        setTimeout(function () { labLog('fallback navigation'); location.href = ${js(fallback)}; }, 1600);
      }
    </script>`,
  });
}

function frames(req, res) {
  sendHtml(req, res, 'Frame Lab', 'Sub-frame navigations should not be confused with main-frame navigation policy.', `
    <div class="grid">
      <div class="card"><h3>Interactive child frame</h3><iframe src="/frame/child?name=interactive"></iframe></div>
      <div class="card"><h3>Auto scheme child frame</h3><iframe src="/frame/auto-scheme"></iframe></div>
    </div>
  `);
}

function frameChild(req, res, u) {
  const name = u.searchParams.get('name') || 'child';
  sendHtml(req, res, 'Child Frame', `Frame name: ${name}.`, `
    <div class="card">
      <p>This is inside an iframe.</p>
      <div class="row">
        ${action('/landing?source=iframe-same-frame', 'Same-frame nav')}
        <a class="action" target="_blank" href="/landing?source=iframe-target-blank">target blank</a>
        <a class="action warn" href="aira-lab://iframe-click">custom scheme</a>
        <button onclick="parent.postMessage({type:'aira-lab-frame', href: location.href}, location.origin)">post parent</button>
      </div>
    </div>
  `);
}

function frameAutoScheme(req, res) {
  sendHtml(req, res, 'Auto Scheme Frame', 'This iframe attempts a custom scheme after load.', `
    <div class="card">
      <p>Iframe auto scheme attempt starts after 1200ms.</p>
      ${action('/frame/child?name=after-auto', 'Frame fallback')}
    </div>
  `, { script: `<script>setTimeout(function(){ labLog('iframe custom scheme attempt'); location.href = 'aira-lab://iframe-auto'; }, 1200);</script>` });
}

function dialogs(req, res) {
  sendHtml(req, res, 'JS Dialog Lab', 'alert, confirm, prompt, nested dialogs, and beforeunload navigation guard.', `
    <section class="verdict">
      <h2>怎么判断</h2>
      <p><strong>点按钮后应该马上弹出系统对话框。</strong>如果页面只显示“已点击”，但没有任何弹窗，那这项就是失败，要截图给我。</p>
      <p>连续弹窗的正常顺序是：先出现第一个提示框，关掉后出现确认框，再出现输入框。</p>
    </section>
    <div class="grid">
      <div class="card stack">
        <h3>JS 弹窗</h3>
        <p><strong>先按顺序点这三步。</strong>这样能分清是靶场没收到点击，还是 Aira 没弹 JS 对话框。</p>
        <div id="dialog-result" class="grandma-result">还没点。点任意按钮后，这里会告诉你下一步怎么看。</div>
        ${action('/landing?source=dialog-normal-link', '第 0 步：普通链接能不能打开')}
        <a class="action" href="javascript:runClickOnly()">第 1 步 A：javascript 链接，只改文字</a>
        <button onclick="runClickOnly()">第 1 步 B：button，只改文字</button>
        <a class="action" href="javascript:runAlert()">第 2 步 A：javascript 链接，弹提示框</a>
        <button onclick="runAlert()">第 2 步 B：button，弹提示框</button>
        <a class="action" href="javascript:nestedDialogs()">第 3 步 A：javascript 链接，连续弹窗</a>
        <button onclick="nestedDialogs()">第 3 步 B：button，连续弹窗</button>
        <a class="action secondary" href="javascript:runConfirm()">单独测：确认框</a>
        <a class="action secondary" href="javascript:runPrompt()">单独测：输入框</a>
      </div>
      <div class="card stack">
        <h3>离开页面确认</h3>
        <p>勾选后再点“离开页面”，正常应该出现离开确认；没有确认就算异常。</p>
        <label><input id="guard" type="checkbox"> 开启离开确认</label>
        ${action('/landing?source=after-beforeunload', 'Navigate away')}
      </div>
    </div>
  `, {
    script: `<script>
      function setDialogResult(kind, text) {
        var box = document.getElementById('dialog-result');
        if (!box) return;
        box.className = 'grandma-result ' + kind;
        box.textContent = text;
      }
      function runClickOnly() {
        setDialogResult('pass', '第 1 步成功：网页已经收到你的点击，普通 JS 也能执行。接下来点第 2 步。如果第 2 步不弹窗，就是 Aira 的 JS dialog 链路问题。');
        labLog('dialog click-only canary passed');
      }
      function runAlert() {
        setDialogResult('watch', '已收到点击。现在应该马上弹出一个提示框；如果完全没弹，就是失败。');
        alert('这是普通提示框。看到它就说明 alert 能弹出来。');
        setDialogResult('pass', '成功：普通提示框已经执行完。');
      }
      function runConfirm() {
        setDialogResult('watch', '已收到点击。现在应该马上弹出确认框；如果完全没弹，就是失败。');
        var ok = confirm('这是确认框。点确定或取消都可以。');
        setDialogResult('pass', '成功：确认框已经执行完，你刚才选择的是：' + (ok ? '确定' : '取消') + '。');
      }
      function runPrompt() {
        setDialogResult('watch', '已收到点击。现在应该马上弹出输入框；如果完全没弹，就是失败。');
        var value = prompt('这是输入框。随便输入，也可以直接确定。', 'hello');
        setDialogResult('pass', '成功：输入框已经执行完，返回值是：' + String(value) + '。');
      }
      function nestedDialogs() {
        setDialogResult('watch', '已收到点击。现在应该依次弹出：提示框 -> 确认框 -> 输入框。如果一个都没弹，就是失败。');
        alert('第一步：提示框。关掉后应该出现确认框。');
        if (confirm('第二步：确认框。点确定后应该出现输入框。')) {
          var value = prompt('第三步：输入框。随便输入一点内容。', 'value');
          labLog('nested prompt -> ' + value);
          setDialogResult('pass', '成功：连续弹窗序列跑完了。');
        } else {
          setDialogResult('pass', '成功：连续弹窗至少弹出了提示框和确认框；你在确认框点了取消，所以没有继续输入框。');
        }
      }
      window.addEventListener('beforeunload', function (event) {
        var guard = document.getElementById('guard');
        if (guard && guard.checked) {
          event.preventDefault();
          event.returnValue = '';
          return '';
        }
      });
    </script>`,
  });
}

async function slow(req, res, u) {
  const delay = parseIntParam(u, 'delay', 2200, 0, 10000);
  await new Promise(resolve => setTimeout(resolve, delay));
  sendHtml(req, res, 'Slow Response', `Server waited ${delay}ms before sending HTML.`, `
    <div class="card">
      <p>This page is useful for progress, stale navigation, and late callback handling.</p>
      ${action('/landing?source=slow-response', 'Continue')}
    </div>
  `);
}

async function stream(req, res) {
  res.writeHead(200, {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Aira-Lab': 'manual-navigation',
  });
  const initialHtml = html(req, 'Streaming Page', 'HTML arrives in chunks; title and body update while loading.', `
    <div class="card"><p>Chunk 1 arrived.</p><div id="chunks"></div></div>
  `).replace(/\s*<\/body>\s*<\/html>\s*$/i, '');
  res.write(initialHtml);
  for (let i = 2; i <= 5; i += 1) {
    await new Promise(resolve => setTimeout(resolve, 650));
    res.write(`<script>document.getElementById('chunks').insertAdjacentHTML('beforeend', '<p>Chunk ${i} arrived.</p>'); labLog('chunk ${i}');</script>`);
  }
  res.end('\n</body>\n</html>');
}

function lateTitle(req, res) {
  sendHtml(req, res, 'Initial Title', 'Title, favicon, and theme color change after load.', `
    <div class="card">
      <p id="late-title-state">Waiting for late title/favicon update.</p>
      ${action('/favicon.svg?color=315f9f', 'Open favicon SVG')}
    </div>
  `, {
    head: `<link id="dynamic-favicon" rel="icon" href="/favicon.svg?color=1f7a64">`,
    script: `<script>
      setTimeout(function () {
        document.title = 'Late Title Applied';
        document.querySelector('meta[name="theme-color"]').setAttribute('content', '#b94f33');
        document.getElementById('dynamic-favicon').setAttribute('href', '/favicon.svg?color=b94f33&v=' + Date.now());
        document.getElementById('late-title-state').textContent = 'Late title, favicon, and theme-color applied.';
        labLog('late title/favicon/theme updated');
      }, 1700);
    </script>`,
  });
}

function scrollLab(req, res) {
  const bands = Array.from({ length: 10 }, (_, i) => {
    const colors = ['#1f7a64', '#315f9f', '#b94f33', '#5d6d2f', '#7d3d76'];
    const color = colors[i % colors.length];
    return `<section class="band" style="background:${color}">Scroll band ${i + 1}<br><span style="font-size:16px;font-weight:500">Watch toolbar, pageVisible, and visual sampling.</span></section>`;
  }).join('');
  sendHtml(req, res, 'Scroll Interaction Lab', 'Long page with nested scrollable content and touch-heavy bands.', `
    <div class="card">
      <p>Scroll slowly, fling quickly, switch tabs, return home, then come back.</p>
      <div style="height:180px;overflow:auto;border:1px solid var(--line);border-radius:8px;padding:10px;background:var(--bg)">
        ${Array.from({ length: 20 }, (_, i) => `<p>Nested scroll row ${i + 1}: inner scrolling should not confuse the outer Web page state.</p>`).join('')}
      </div>
    </div>
    ${bands}
  `);
}

function visualSampling(req, res) {
  sendHtml(req, res, 'Visual Sampling Lab', 'Large above-the-fold color changes, theme-color changes, and delayed hero swaps.', `
    <section id="hero" class="band" style="background:#1f7a64;min-height:72vh">Initial green hero</section>
    <section class="band" style="background:#315f9f">Blue section</section>
    <section class="band" style="background:#b94f33">Warm section</section>
    <div class="card">
      <button onclick="swapHero()">Swap hero immediately</button>
      <button onclick="delayedSwap()">Delayed swap</button>
    </div>
  `, {
    script: `<script>
      function applyColor(color, label) {
        document.getElementById('hero').style.background = color;
        document.getElementById('hero').textContent = label;
        document.querySelector('meta[name="theme-color"]').setAttribute('content', color);
        labLog('visual color -> ' + color);
      }
      function swapHero() { applyColor('#7d3d76', 'Purple hero after click'); }
      function delayedSwap() { setTimeout(function(){ applyColor('#315f9f', 'Delayed blue hero'); }, 1400); }
      setTimeout(function(){ applyColor('#b94f33', 'Automatic warm hero'); }, 2400);
    </script>`,
  });
}

function snapshot(req, res) {
  sendHtml(req, res, 'Snapshot / Late Content Lab', 'Use this to inspect stored snapshots after content changes and navigation.', `
    <div class="card">
      <p id="snapshot-state">Initial above-the-fold content.</p>
      <button onclick="mutate()">Mutate content</button>
      ${action('/landing?source=snapshot-next', 'Navigate away')}
    </div>
    <div id="snapshot-grid" class="grid"></div>
  `, {
    script: `<script>
      function mutate() {
        document.getElementById('snapshot-state').textContent = 'Mutated at ' + new Date().toISOString();
        var grid = document.getElementById('snapshot-grid');
        for (var i = 0; i < 12; i += 1) {
          var node = document.createElement('div');
          node.className = 'card';
          node.innerHTML = '<h3>Late card ' + (i + 1) + '</h3><p>Snapshot content generated after user action.</p>';
          grid.appendChild(node);
        }
        labLog('snapshot content mutated');
      }
      setTimeout(mutate, 1800);
    </script>`,
  });
}

function searchResults(req, res, u) {
  const q = u.searchParams.get('q') || 'aira';
  const repeated = Array.from({ length: 36 }, (_, i) => `
    <article class="card">
      <h3>Result ${i + 1}: ${esc(q)} navigation callback sample</h3>
      <p>${esc(q)} appears here with login redirect, popup, deep link, history API, scroll sampling, and download keywords.</p>
    </article>
  `).join('');
  sendHtml(req, res, 'Search Results', `Dense page for browser find/search result callbacks. Query: ${q}.`, `
    <form class="card" action="/search/results">
      <label>Query<input name="q" value="${esc(q)}"></label>
      <input type="submit" value="Search">
    </form>
    <div class="grid">${repeated}</div>
  `);
}

function downloads(req, res) {
  sendHtml(req, res, 'Download Lab', 'Attachments, redirects to attachment, inline MIME, download attribute, and blob downloads.', `
    <section class="verdict">
      <h2>下载专项入口</h2>
      <p><strong>城通网盘保存复现页已经合并到这个统一靶场里。</strong>以后只开这一个服务器就够了。</p>
      <p>${action('/download-fixture', '打开：网页内下载保存测试')}</p>
    </section>
    <div class="grid">
      ${card('Server attachments', 'Content-Disposition attachment from the server.',
        action('/download/file?name=aira-lab.txt&type=text/plain', 'TXT attachment') +
        action('/download/file?name=aira-lab.bin&type=application/octet-stream', 'BIN attachment') +
        action('/download/redirect', 'Redirect to download') +
        action(downloadFixtures.binary.path, '256KB binary fixture') +
        action(downloadFixtures.chunked.path, '128KB chunked fixture'))}
      ${card('Inline resources', 'Resources that may render inline instead of download.',
        action('/mime/json', 'Inline JSON') +
        action('/mime/pdf', 'PDF-like inline'))}
      ${card('Client-side download', 'Blob URL and download attribute generated in page JS.',
        '<a class="action" download="aira-lab-anchor.txt" href="/download/file?name=anchor.txt&type=text/plain">download attribute</a>' +
        '<button onclick="blobDownload()">Blob download</button>')}
    </div>
  `, {
    script: `<script>
      function blobDownload() {
        var blob = new Blob(['Aira blob download at ' + new Date().toISOString() + '\\n'], { type: 'text/plain' });
        var a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = 'aira-lab-blob.txt';
        document.body.appendChild(a);
        a.click();
        setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 1200);
        labLog('blob download clicked');
      }
    </script>`,
  });
}

function prettyBytes(bytes) {
  return bytes >= 1024 * 1024
    ? `${(bytes / 1024 / 1024).toFixed(2)} MB`
    : `${Math.round(bytes / 1024)} KB`;
}

function downloadFixture(req, res) {
  const rows = Object.values(downloadFixtures)
    .filter((fixture) => fixture.path !== downloadFixtures.ctfileLike.path)
    .map((fixture) => `<li><a href="${fixture.path}">${esc(fixture.fileName)}</a> - ${prettyBytes(fixture.body.length)}</li>`)
    .join('\n');
  sendHtml(req, res, '网页内下载保存测试', '模拟城通网盘：网页内先下载完成，再弹出“保存到设备”。', `
    <section class="verdict">
      <h2>怎么判断</h2>
      <p><strong>先点“模拟点击下载”。</strong>进度跑完后应该出现“下载完成”弹层。再点“保存到设备”，正常应该唤起系统保存位置选择，保存出来的文件不应该是 0KB。</p>
      <p>如果弹层没有出现、保存后文件是 0KB、或者点保存没反应，就是下载保存链路有问题。</p>
    </section>
    <section class="card stack">
      <h3>城通网盘保存复现页</h3>
      <p>这个页面模拟：网页自己 fetch 文件，下载完后用浏览器能力保存到设备。</p>
      <button id="ctStart">模拟点击下载</button>
      <div class="progressShell"><div id="ctProgress" class="progressBar"></div></div>
      <pre id="ctLog" class="log">等待开始</pre>
    </section>
    <section class="card stack">
      <h3>普通附件链接（对照组）</h3>
      <p>下面这些会走浏览器原生下载，用来和网页内保存路径对比。</p>
      <ul>${rows}
        <li><a href="/download-fixture/redirect">aira-test-redirect-64kb.txt - redirect 64 KB</a></li>
      </ul>
    </section>
    <div id="ctModal" class="modalMask" role="dialog" aria-modal="true">
      <div class="sheet">
        <div class="sheetHeader">
          <div class="check">✓</div>
          <div>
            <h2 class="sheetTitle">下载完成</h2>
            <p class="sheetSub">请选择接下来的保存方式。</p>
          </div>
          <button id="ctClose" class="close" aria-label="关闭">×</button>
        </div>
        <div class="fileCard">
          <div class="fileIcon">⇥</div>
          <div>
            <div id="ctFileName" class="fileName">${esc(downloadFixtures.ctfileLike.fileName)}</div>
            <div id="ctFileSize" class="fileSize">${prettyBytes(downloadFixtures.ctfileLike.body.length)}</div>
          </div>
        </div>
        <p class="hint">在完成保存或分享前，请不要清除浏览器站点数据。</p>
        <div class="actions">
          <button id="ctSave" class="primary">保存到设备</button>
          <button id="ctBlobSave" class="secondary">Blob 链接保存（备用）</button>
          <button id="ctCancel" class="secondary">关闭</button>
        </div>
      </div>
    </div>
  `, {
    script: `<script>
      (function () {
        var startButton = document.getElementById('ctStart');
        var saveButton = document.getElementById('ctSave');
        var blobSaveButton = document.getElementById('ctBlobSave');
        var closeButton = document.getElementById('ctClose');
        var cancelButton = document.getElementById('ctCancel');
        var modal = document.getElementById('ctModal');
        var progress = document.getElementById('ctProgress');
        var log = document.getElementById('ctLog');
        var preparedBlob = null;
        var preparedFile = null;
        var preparedName = ${js(downloadFixtures.ctfileLike.fileName)};
        function writeLog(text) {
          log.textContent += '\\n' + new Date().toLocaleTimeString() + ' ' + text;
          log.scrollTop = log.scrollHeight;
        }
        function showModal() { modal.classList.add('show'); }
        function hideModal() { modal.classList.remove('show'); }
        function prettyBytesClient(bytes) { return (bytes / 1024 / 1024).toFixed(2) + ' MB'; }
        async function readResponseBytes(response) {
          var total = Number(response.headers.get('content-length') || 0);
          var received = 0;
          var chunks = [];
          if (response.body && response.body.getReader) {
            var reader = response.body.getReader();
            while (true) {
              var item = await reader.read();
              if (item.done) break;
              chunks.push(item.value);
              received += item.value.length;
              if (total > 0) progress.style.width = Math.min(100, Math.round(received / total * 100)) + '%';
              writeLog('downloaded ' + received + '/' + total);
            }
          } else {
            var fallback = new Uint8Array(await response.arrayBuffer());
            chunks.push(fallback);
            received = fallback.length;
            progress.style.width = '100%';
          }
          return new Blob(chunks, { type: 'application/octet-stream' });
        }
        async function stageLikeCtfile(blob) {
          if (!navigator.storage || typeof navigator.storage.getDirectory !== 'function') {
            writeLog('OPFS unavailable, using memory blob');
            return blob;
          }
          try {
            var root = await navigator.storage.getDirectory();
            var tempName = 'ctfile-' + Date.now() + '-' + preparedName;
            var handle = await root.getFileHandle(tempName, { create: true });
            var writable = await handle.createWritable();
            await writable.write(blob);
            await writable.close();
            var staged = await handle.getFile();
            writeLog('OPFS staged file size=' + staged.size);
            return new File([staged], preparedName, {
              type: staged.type || 'application/octet-stream',
              lastModified: staged.lastModified || Date.now()
            });
          } catch (error) {
            writeLog('OPFS stage failed: ' + (error && (error.message || String(error))));
            return blob;
          }
        }
        async function writeBlobToWritable(blob, writable) {
          try {
            if (blob.stream && blob.stream().getReader) {
              var reader = blob.stream().getReader();
              while (true) {
                var item = await reader.read();
                if (item.done) break;
                await writable.write(item.value);
              }
            } else {
              await writable.write(await blob.arrayBuffer());
            }
            await writable.close();
          } catch (error) {
            if (writable.abort) {
              try { await writable.abort(); } catch (abortError) {}
            }
            throw error;
          }
        }
        function saveWithBlobAnchor(blob) {
          var url = URL.createObjectURL(blob);
          var anchor = document.createElement('a');
          anchor.href = url;
          anchor.download = preparedName;
          document.body.appendChild(anchor);
          writeLog('clicking blob download url=' + url + ' size=' + blob.size);
          anchor.click();
          anchor.remove();
          setTimeout(function () {
            URL.revokeObjectURL(url);
            writeLog('revoked blob url');
          }, 60000);
        }
        startButton.addEventListener('click', async function () {
          startButton.disabled = true;
          preparedBlob = null;
          preparedFile = null;
          progress.style.width = '0%';
          hideModal();
          log.textContent = '开始网页内下载';
          writeLog('showSaveFilePicker=' + (typeof window.showSaveFilePicker));
          writeLog('navigator.storage.getDirectory=' + (navigator.storage && typeof navigator.storage.getDirectory));
          try {
            var response = await fetch(${js(downloadFixtures.ctfileLike.path)} + '?mode=in-page', { cache: 'no-store' });
            if (!response.ok) throw new Error('HTTP ' + response.status);
            preparedBlob = await readResponseBytes(response);
            writeLog('prepared blob size=' + preparedBlob.size);
            preparedFile = await stageLikeCtfile(preparedBlob);
            writeLog('prepared export object size=' + preparedFile.size);
            document.getElementById('ctFileSize').textContent = prettyBytesClient(preparedFile.size || preparedBlob.size);
            progress.style.width = '100%';
            showModal();
          } catch (error) {
            writeLog('failed: ' + (error && (error.message || String(error))));
          } finally {
            startButton.disabled = false;
          }
        });
        saveButton.addEventListener('click', async function () {
          var target = preparedFile || preparedBlob;
          if (!target) {
            writeLog('no prepared file');
            return;
          }
          if (typeof window.showSaveFilePicker === 'function') {
            try {
              writeLog('opening showSaveFilePicker size=' + target.size);
              var handle = await window.showSaveFilePicker({ suggestedName: preparedName });
              var writable = await handle.createWritable();
              await writeBlobToWritable(target, writable);
              writeLog('showSaveFilePicker write complete size=' + target.size);
              return;
            } catch (error) {
              writeLog('showSaveFilePicker failed: ' + (error && (error.name || '') + ' ' + (error.message || String(error))));
            }
          }
          saveWithBlobAnchor(target);
        });
        blobSaveButton.addEventListener('click', function () {
          var target = preparedFile || preparedBlob;
          if (!target) {
            writeLog('no prepared file');
            return;
          }
          saveWithBlobAnchor(target);
        });
        closeButton.addEventListener('click', hideModal);
        cancelButton.addEventListener('click', hideModal);
      })();
    </script>`,
  });
}

function sendDownloadFixture(res, fixture, chunked = false) {
  const encodedFileName = encodeURIComponent(fixture.fileName);
  const headers = {
    'Content-Type': fixture.contentType,
    'Content-Disposition': `attachment; filename="download.bin"; filename*=UTF-8''${encodedFileName}`,
    'Cache-Control': 'no-store',
    'X-Aira-Fixture-Size': String(fixture.body.length)
  };
  if (!chunked) {
    headers['Content-Length'] = String(fixture.body.length);
    send(res, 200, fixture.body, headers);
    return;
  }
  res.writeHead(200, headers);
  let offset = 0;
  const timer = setInterval(() => {
    if (offset >= fixture.body.length) {
      clearInterval(timer);
      res.end();
      return;
    }
    const nextOffset = Math.min(offset + 8192, fixture.body.length);
    res.write(fixture.body.subarray(offset, nextOffset));
    offset = nextOffset;
  }, 20);
}

function downloadFile(req, res, u) {
  const name = (u.searchParams.get('name') || 'aira-lab.txt').replace(/[^a-zA-Z0-9._-]/g, '_');
  const type = u.searchParams.get('type') || 'text/plain';
  const body = `Aira manual navigation lab download\nname=${name}\ntime=${nowIso()}\n`;
  send(res, 200, body, {
    'Content-Type': type,
    'Content-Disposition': `attachment; filename="${name}"`,
    'Content-Length': Buffer.byteLength(body),
  });
}

function downloadRedirect(req, res) {
  send(res, 302, '', { Location: '/download/file?name=redirected-download.txt&type=text/plain' });
}

function weirdLinks(req, res) {
  const encodedRedirect = `/redirect/chain?steps=1&to=${encodeURIComponent('/landing?source=encoded-redirect&next=https%3A%2F%2Fexample.com%2Fcb%3Fcode%3D1%26state%3D2')}`;
  sendHtml(req, res, 'Weird Link Lab', 'Odd URL shapes often appear in ad, auth, payment, and tracking links.', `
    <div class="grid">
      ${card('Query tricks', 'Repeated params, @ signs, empty values, fragments, and callback-looking values.',
        action('/landing?a=1&a=2&empty=&email=user@example.com#', 'Repeated params') +
        action('/landing?url=https://user@example.com/path?code=abc&state=xyz', '@ and nested URL') +
        action('/landing?next=%2Foauth%2Fcallback%3Fcode%3Dabc%26state%3Dxyz', 'Encoded callback'))}
      ${card('Redirect wrappers', 'Redirectors that hide callback targets inside encoded query parameters.',
        action(encodedRedirect, 'Encoded redirect wrapper') +
        action('/redirect/js?delay=300&to=' + encodeURIComponent('/landing?source=encoded-js&ticket=t123'), 'JS wrapper'))}
      ${card('Hash-heavy routes', 'Client routes and fragments with encoded path state.',
        action('/spa#/oauth/callback?code=hash-code&state=hash-state', 'Hash callback') +
        action('/landing#%2Fdeep%2Froute%3Fid%3D42', 'Encoded fragment'))}
    </div>
  `);
}

function longUrl(req, res, u) {
  const size = parseIntParam(u, 'size', 4200, 100, 12000);
  const next = u.searchParams.get('next') || '/landing?source=long-url';
  const filler = 'x'.repeat(size);
  sendHtml(req, res, 'Very Long URL', `Current URL includes a ${size}-character filler parameter.`, `
    <div class="card">
      <p>Filler length: <span class="mono">${size}</span></p>
      ${action(`${next}&fillerLength=${size}`, 'Continue to target')}
    </div>
  `, {
    script: `<script>
      if (!location.search.includes('filler=')) {
        var url = new URL(location.href);
        url.searchParams.set('filler', ${js(filler)});
        history.replaceState({ long: true }, '', url.pathname + url.search + url.hash);
        labLog('inserted long filler into current URL');
      }
    </script>`,
  });
}

function mimePlainHtml(req, res) {
  send(res, 200, [
    '判断结果：如果你看到这一整页都是纯文本，并且下面的 <h1> / <a> 标签没有被渲染成大标题和可点击链接，这个场景就是成功。',
    '',
    '原因：服务器返回的 Content-Type 是 text/plain；浏览器应该尊重 MIME，把内容当普通文本显示，而不是当 HTML 执行。',
    '',
    '异常信号：如果下面变成了真正的大标题，或者 link text 变成了可点击网页链接，才说明 text/plain 被错误地当 HTML 渲染了。',
    '',
    '<h1>This looks like HTML but is text/plain</h1>',
    '<a href="/landing?source=plain-html">link text</a>',
    '',
  ].join('\n'), {
    'Content-Type': 'text/plain; charset=utf-8',
  });
}

function mimeJson(req, res) {
  send(res, 200, JSON.stringify({ lab: 'aira-navigation', time: nowIso(), links: ['/landing', '/redirect/chain?steps=1'] }, null, 2), {
    'Content-Type': 'application/json; charset=utf-8',
  });
}

function mimePdf(req, res) {
  const body = `%PDF-1.1
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Count 1 /Kids [3 0 R] >> endobj
3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R >> endobj
4 0 obj << /Length 44 >> stream
BT /F1 18 Tf 30 100 Td (Aira Lab PDF) Tj ET
endstream endobj
trailer << /Root 1 0 R >>
%%EOF
`;
  send(res, 200, body, { 'Content-Type': 'application/pdf' });
}

function favicon(req, res, u) {
  const color = (u.searchParams.get('color') || '1f7a64').replace(/[^0-9a-fA-F]/g, '').slice(0, 6) || '1f7a64';
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><rect width="64" height="64" rx="14" fill="#${color}"/><path fill="#fff" d="M32 9l21 46h-9l-4-9H24l-4 9h-9L32 9zm0 17l-6 14h12l-6-14z"/></svg>`;
  send(res, 200, svg, { 'Content-Type': 'image/svg+xml; charset=utf-8' });
}

async function route(req, res) {
  const u = requestUrl(req);
  const path = u.pathname;
  if (path === '/' || path === '/guided' || path === '/guided/spa-result') return guided(req, res);
  if (path === '/expert') return index(req, res);
  if (path === '/landing') return landing(req, res);
  if (path === '/redirect/chain') return redirectChain(req, res, u);
  if (path === '/redirect/loop') return redirectLoop(req, res, u);
  if (path === '/redirect/refresh') return refreshRedirect(req, res, u);
  if (path === '/redirect/meta') return metaRedirect(req, res, u);
  if (path === '/redirect/js') return jsRedirect(req, res, u);
  if (path === '/status') return statusPage(req, res, u);
  if (path === '/oauth/start') return oauthStart(req, res);
  if (path === '/oauth/authorize') return oauthAuthorize(req, res, u);
  if (path === '/oauth/callback') return oauthCallback(req, res, u);
  if (path === '/oauth/session') return oauthSession(req, res);
  if (path === '/post-form') return postForm(req, res, u);
  if (path === '/post-submit') return postSubmit(req, res, u);
  if (path === '/post-landing') return postLanding(req, res);
  if (path === '/payment/start') return paymentStart(req, res);
  if (path === '/payment/provider') return paymentProvider(req, res, u);
  if (path === '/payment/callback') return paymentCallback(req, res, u);
  if (path === '/payment/receipt') return paymentReceipt(req, res);
  if (path === '/spa' || path.startsWith('/spa/')) return spa(req, res);
  if (path === '/history-clean' || path === '/history-clean/session') return historyClean(req, res, u);
  if (path === '/new-window') return newWindow(req, res);
  if (path === '/popup-child') return popupChild(req, res, u);
  if (path === '/external') return external(req, res);
  if (path === '/scheme/auto') return schemeAuto(req, res, u);
  if (path === '/scheme/fallback') return schemeFallback(req, res, u);
  if (path === '/frames') return frames(req, res);
  if (path === '/frame/child') return frameChild(req, res, u);
  if (path === '/frame/auto-scheme') return frameAutoScheme(req, res);
  if (path === '/dialogs') return dialogs(req, res);
  if (path === '/slow') return slow(req, res, u);
  if (path === '/stream') return stream(req, res);
  if (path === '/late-title') return lateTitle(req, res);
  if (path === '/scroll') return scrollLab(req, res);
  if (path === '/visual-sampling') return visualSampling(req, res);
  if (path === '/snapshot') return snapshot(req, res);
  if (path === '/search/results') return searchResults(req, res, u);
  if (path === '/downloads') return downloads(req, res);
  if (path === '/download-fixture') return downloadFixture(req, res);
  if (path === '/download-fixture/redirect') return send(res, 302, '', { Location: downloadFixtures.plain.path });
  if (path === downloadFixtures.ctfileLike.path) return sendDownloadFixture(res, downloadFixtures.ctfileLike);
  if (path === downloadFixtures.plain.path) return sendDownloadFixture(res, downloadFixtures.plain);
  if (path === downloadFixtures.binary.path) return sendDownloadFixture(res, downloadFixtures.binary);
  if (path === downloadFixtures.chunked.path) return sendDownloadFixture(res, downloadFixtures.chunked, true);
  if (path === '/download/file') return downloadFile(req, res, u);
  if (path === '/download/redirect') return downloadRedirect(req, res);
  if (path === '/weird-links') return weirdLinks(req, res);
  if (path === '/weird/long-url') return longUrl(req, res, u);
  if (path === '/mime/plain-html') return mimePlainHtml(req, res);
  if (path === '/mime/json') return mimeJson(req, res);
  if (path === '/mime/pdf') return mimePdf(req, res);
  if (path === '/favicon.svg') return favicon(req, res, u);
  if (path === '/favicon.ico') return send(res, 204, '');
  if (path === '/__ping') return send(res, 200, 'ok\n', { 'Content-Type': 'text/plain; charset=utf-8' });
  return sendHtml(req, res, 'Not Found', 'No route exists for this manual lab URL.', `${action('/', 'Back to index')}`, { status: 404 });
}

const server = http.createServer((req, res) => {
  route(req, res).catch(error => {
    console.error(error);
    if (!res.headersSent) {
      send(res, 500, `Navigation lab error\n${error.stack || error.message}\n`, { 'Content-Type': 'text/plain; charset=utf-8' });
    } else {
      res.end();
    }
  });
});

server.listen(port, host, () => {
  const urls = [`http://127.0.0.1:${port}/`];
  for (const entries of Object.values(os.networkInterfaces())) {
    for (const entry of entries || []) {
      if (entry.family === 'IPv4' && !entry.internal) {
        urls.push(`http://${entry.address}:${port}/`);
      }
    }
  }
  console.log('Aira manual navigation lab is running.');
  console.log(`Bind: http://${host}:${port}/`);
  console.log('Open one of these in Aira on the phone:');
  for (const url of urls) {
    console.log(`  ${url}`);
  }
});
