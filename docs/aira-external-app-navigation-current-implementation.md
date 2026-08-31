# Aira 网页拉起外部 App 当前实现调研

日期：2026-07-04  
调研对象：Aira 当前工作区代码  
关联文档：`docs/huawei-browser-external-app-navigation-research.md`

## 结论先行

Aira 现在把“网页请求打开 App”做成一条 **browser-first external navigation policy pipeline**：

- ArkWeb 的 `onLoadIntercept` / `onOverrideUrlLoading` 只负责把请求事件交给 Web runtime pipeline。
- 如果 URL scheme 是 ArkWeb 可加载的 `http` / `https` / `file` / `about` / `data` / `blob` / `javascript`，默认继续在 WebView 内加载，不走外部 App 打开。
- 只有 WebView 不支持的 scheme，例如 `quark://`、`baiduboxapp://`、`bilibili://`、`mailto:`、`tel:` 一类，才进入外部应用策略。
- 进入外部策略后，会经过主框架、页面/窗口可见性、用户手势或近期用户动作、重复提示抑制、用户取消后的短期静默、全局/站点策略这些门禁。
- 默认策略是 `ask`：用户触发时显示顶部 InfoBar；没有用户触发时静默拒绝或消费加载。
- 真正打开外部应用时，Aira 目前调用的是 `UIAbilityContext.openLink(url)`，不做华为浏览器那种 `queryAbilityInfo -> 目标 bundle 信息 -> App 图标/Ability 启动` 的完整目标 App 解析。

所以用户看到的“已阻止子框架自动打开外部应用。”，在 Aira 里不是权限弹窗，而是 `BrowserUnifiedLinkLogic` 对 **subframe deeplink / external protocol launch** 的安全拦截。普通网页 URL 仍然优先留在浏览器里。

## 术语对齐

这类能力通常可以叫：

- **External app navigation**：网页导航目标要交给浏览器外部的系统或 App。
- **External protocol handling**：处理非 WebView 可加载 scheme，比如 `tel:`、`mailto:`、App 自定义 scheme。
- **Deeplink / custom scheme**：App 自定义 URL scheme。
- **App Linking / AppLinking**：`http(s)` 链接被系统或 App 接管的能力。
- **ArkWeb navigation interception**：HarmonyOS Web 侧的 `onLoadIntercept`、`onOverrideUrlLoading` 回调。

Aira 当前实现更偏 **external protocol / deeplink handling**。对 `http(s)` AppLinking，当前没有全局主动 `openLink(... appLinkingOnly)` 或能力查询路径，而是让普通 Web URL 留在 ArkWeb。

## 当前架构图

```text
HostedWebNode ArkWeb callbacks
  -> BrowserWebEventHostCoordinator
  -> BrowserWebTabsController
  -> BrowserWebPageController
  -> BrowserWebComponentController
     -> special navigation action
     -> WebView 可加载 URL: 主框架清洗/改写后继续 Web 加载
     -> Web App scope-out navigation
     -> BrowserUnifiedLinkNavigationCoordinator
        -> BrowserUnifiedLinkLogic
           -> ExternalNavigationPolicyService
        -> BrowserUnifiedLinkApplicationCoordinator
           -> record policy / toast / openLink / show InfoBar（唯一应用叙事入口）
              -> BrowserExternalNavigationInfoBarApplicationCoordinator（subordinate prompt session）
                 -> BrowserInfoBarQueue（session 内部状态）
                 -> ExternalNavigationPromptViewModel
                 -> SiteIconService + current favicon
                 -> BrowserExternalNavigationPromptCard
```

这一层级里，主要 owner 是：

- Web 事件入口：`HostedWebNode`
- tab 到 per-tab page 转发：`BrowserWebTabsController`
- per-tab Web runtime/page owner：`BrowserWebPageController` / `BrowserWebComponentController`
- 外部链接决策：`BrowserUnifiedLinkNavigationCoordinator` + `BrowserUnifiedLinkLogic`
- 外部应用策略：`ExternalNavigationPolicyService`
- 决策副作用和普通流程叙事：`BrowserUnifiedLinkApplicationCoordinator`
- InfoBar 提示、确认/取消、短期 suppression 和图标异步补全：subordinate `BrowserExternalNavigationInfoBarApplicationCoordinator`
- 站点图标：`SiteIconService` + `BrowserFaviconCoordinator`

`BrowserShellPage.ets` 当前只提供一个 typed application shell、一个 typed navigation facts read，以及一级
`ExternalNavigationPromptState` ArkUI 绑定。设置、profile/data scope、queue、recent-action 和 prompt 顺序由 owner
树直接组合；页面只保留当前页可见性/favicon事实、`openLink`、Toast/helper/error 和 diagnostics 等真实平台/UI effect。

## ArkWeb 事件入口

`HostedWebNode` 在 ArkUI Web 组件上注册 ArkWeb 回调：

- `onLoadIntercept` 调 `config.callbacks.onLoadIntercept(config.tabId, event)`
- `onOverrideUrlLoading` 调 `config.callbacks.onOverrideUrlLoading(config.tabId, request)`

然后 `BrowserWebTabsController` 按 tab 找到 `BrowserWebPageController`：

```text
BrowserWebTabsController.onOverrideUrlLoading(tabId, request)
  -> page.onOverrideUrlLoading(request, host)
BrowserWebTabsController.onLoadIntercept(tabId, event)
  -> page.onLoadIntercept(event, host)
```

`BrowserWebPageController` 再交给 `BrowserWebComponentController`。后者会安全读取：

- `request.getRequestUrl()`
- `request.isMainFrame()`
- `request.isRequestGesture()`

并统一进入 `handleNavigationEvent(...)`。

## WebView 优先策略

`BrowserWebComponentController.handleNavigationEvent(...)` 的顺序是：

1. 先问特殊导航 action，例如内部页面、扩展动作等。
2. 如果 `host.canLoadUrlInWebView(url)` 为 true：
   - 主框架请求进入 `BrowserWebNavigationInterceptionCoordinator.resolveMainFrameWebUrlDecision(...)`，用于广告清洗、Telegram 主框架改写等普通 Web 导航处理。
   - 子框架 WebView 支持的 URL 直接放行。
   - 返回 `false`，让 ArkWeb 继续加载。
3. 如果 WebView 不支持，先检查 Web App scope-out。
4. 最后才进入 `BrowserUnifiedLinkNavigationCoordinator.evaluate(...)`。

`WebRuntimeBridge.canLoadInWebView(...)` 当前认定这些 scheme 可以由 ArkWeb 加载：

```text
http, https, file, about, data, blob, javascript
```

这就是 Aira 和“只要系统能打开就跳 App”的关键差异：普通 `https://pan.quark.cn/...` 这种 URL 本身会先留在 WebView；只有页面后续触发 `quark://...` 之类 deeplink，才进入外跳策略。

## 统一外跳决策

`BrowserUnifiedLinkNavigationCoordinator.evaluate(...)` 负责把页面和运行时事实组装成 `BrowserUnifiedLinkContext`：

- 当前 tab URL / referer
- `isMainFrame`
- `isRequestGesture`
- tab 是否是当前可见 Web 页面
- Browser shell window 是否可见
- WebView 是否能加载该 URL
- 是否有近期用户动作
- 最近一次外跳提示的 URL 和时间
- 外部应用设置
- 当前站点 origin
- 用户取消后的 suppression records
- profile id

这里的重复提示抑制窗口是 `1200ms`。

随后 `BrowserUnifiedLinkLogic.evaluate(...)` 做核心门禁：

1. URL 为空：`allow_web`
2. WebView 能加载：`allow_web`
   - `http(s)` 原因是 `ordinary_web_url`
   - 其他 WebView 支持 scheme 原因是 `webview_supported_scheme`
3. 非主框架：消费加载并提示 `已阻止子框架自动打开外部应用。`
4. tab/window 不可见，且没有 deeplink 豁免：消费加载并提示 `已阻止后台页面打开外部应用。`
5. 交给 `ExternalNavigationPolicyService.shouldInterceptExternalNavigationRequest(...)`
6. 按策略结果映射为：
   - `consume_security_block`
   - `open_external`
   - `deny`
   - `show_info_bar`
   - `allow_web`

`show_info_bar` 只会在策略要求询问、没有被抑制、且请求具备用户触发时出现。没有用户触发时，即使全局或站点是 `ask`，也会拒绝自动打开。

## 外部应用策略

`ExternalNavigationPolicyService` 的策略维度是：

- 全局默认：`externalNavigation.appOpenPolicy`
- 站点规则：`externalNavigation.siteRules`
- 用户取消后的 suppression record
- 同 URL 短时间重复提示
- 用户触发状态

策略枚举是：

```text
block | ask | allow
```

默认设置是：

```text
appOpenPolicy: ask
suppressAfterCancelMs: 24h
siteRules: []
```

策略含义：

- `block`：拦截并记录 block，不打开。
- `allow`：如果用户触发，直接 `open_external`；如果不是用户触发，仍静默阻止网页自动打开。
- `ask`：用户触发时显示 InfoBar；短时间重复或用户刚取消过，则静默抑制。

App 名称当前主要由 scheme 推断：

- `baiduboxapp` -> `百度 App`
- `bilibili` -> `哔哩哔哩 App`
- 其他非空 scheme -> `${scheme} 应用`
- 无法识别 -> `其他应用`

这说明 Aira 目前没有真实查询目标 App 的 bundle 名、应用名和图标。提示里的 App 名是 scheme 级推断。

## 决策副作用

`BrowserUnifiedLinkApplicationCoordinator` 是外部跳转应用阶段的唯一叙事入口。它把逻辑结果变成可执行 plan，
并在需要提示时调用内部持有的 InfoBar session owner：

- `consume_security_block` -> 记录 block，并 toast。
- `open_external` -> 记录 allow，并打开外部链接。
- `deny` -> 记录 block/deny；如果原因是 `external_policy_suppressed`，不 toast。
- `show_info_bar` -> 记录 prompt，并显示 InfoBar，消息是 `请求外跳到 ${appName}`。
- `load_fallback_in_web` -> 当前只记录 runtime event。

打开外部链接最终走：

```text
ExternalNavigationPolicyService.openExternalLink(...)
  -> context.openLink(url)
```

失败时由 `BrowserExternalNavigationInfoBarApplicationCoordinator.executeExternalLinkOpen(...)` 分类故障、记录失败，并 toast：

```text
没有找到可打开此链接的应用。
```

## InfoBar 和图标链路

外跳提示由 subordinate `BrowserExternalNavigationInfoBarApplicationCoordinator` 创建；它自己持有
`BrowserInfoBarQueue` 和 canonical prompt state，再把不可变 state 发布给页面一级 `@State`。

提示文案来自 `ExternalNavigationPromptViewModel`：

- title：`此网站请求打开 ${appName}`
- subtitle：`${originLabel} 想切换到其他应用`

图标链路是站点图标，不是目标 App 图标：

```text
current origin
  -> SiteIconService.getMemoryIconUri(origin)
  -> prompt state iconUri
  -> shell.readPromptPresentationContext(tabId) 取 source page URL 和当前 tab preview favicon PixelMap
  -> SiteIconService.getCachedIconUri(origin) 异步补 cached iconUri
  -> BrowserExternalNavigationPromptCard
  -> BrowserTopPromptIcon
  -> SiteIconView
     -> iconUri
     -> iconPixelMap
     -> fallbackLabel 首字母
```

这里正好复用了书签、历史、最近关闭、离线页面等列表用的 `SiteIconService` / `WebsiteIconView` / `SiteIconView` 体系。

因此，Aira 当前合理的兜底顺序应该是：

1. 当前 tab 的 ArkWeb favicon PixelMap
2. `SiteIconService` memory cache icon URI
3. `SiteIconService` disk cache icon URI
4. `BrowserTopPromptIcon` / `SiteIconView` 的站点首字母 fallback

当前代码已经按这个方向串了：`BrowserExternalNavigationInfoBarApplicationCoordinator` 会传 `iconUri` 和 `favicon`，`BrowserExternalNavigationPromptCard` 经 `BrowserTopPromptIcon` 复用 `SiteIconView`，在 URI 不可用或加载失败时落到 PixelMap 或首字母。也就是说，外跳提示不应该出现完全空白的 icon slot；如果真实设备上空白，优先查的是 prompt state 是否传入了空 `originLabel/appName` 或 `BrowserTopPromptIcon/SiteIconView` 的 fallback 绘制条件，而不是另起一套图标系统。

## Favicon 如何进入统一缓存

Aira 的普通网页 favicon 进入路径是：

```text
ArkWeb onFaviconReceived
  -> BrowserWebPagePresentationEventCoordinator
  -> BrowserFaviconCoordinator
     -> update tab preview favicon
     -> persist non-private favicon through SiteIconService.rememberFaviconFromPixelMap(...)
     -> update background prompt favicon
```

外跳 InfoBar 的 `resolveFavicon(tabId)` 取的是 `BrowserTabPreviewCoordinator` 的 preview favicon；异步 cached icon URI 取的是 `SiteIconService`。这就是它和历史/书签“统一图标管理”的交点。

## 用户可控设置

Aira 有两类设置入口：

- 全局默认：`SiteControlsExternalNavigationDefaultPage`
- 单站点规则：站点设置 / Web App 详情页通过 `SiteCustomizationManagementCoordinator`

全局页展示：

- `询问`：网站尝试打开外部应用时先询问
- `允许`：允许网站直接打开外部应用
- `阻止`：阻止网站打开外部应用

私密数据域不改全局外部应用策略。

单站点规则会写入 `externalNavigation.siteRules`，最多保留最近 120 条。匹配时优先 `primaryOrigin`，再按 `displayHost`。

当前 InfoBar 只提供“打开”和关闭/滑走；关闭会写短期 suppression record，避免同站点同 app/scheme
立即重复打扰。持久 `allow` / `block` 只通过 Settings 或 Site Controls 的明确设置入口写入，不由 Prompt
携带不可达的“记住”分支。

## 与华为浏览器的主要差异

相同点：

- 都把 ArkWeb 回调当作事实入口，而不是把所有判断写在 Web 组件里。
- 都有主框架、可见性、用户动作这些安全门禁。
- 都不会无条件让子框架或后台页面自动拉起 App。
- 都有 InfoBar / Dialog 这类用户确认层。

差异点：

- 华为侧同时处理 `http(s)` AppLinking 和 Deeplink；Aira 当前更保守，普通 `http(s)` 留在 WebView。
- 华为侧有 `queryAbilityInfo`、bundle resource info、白名单、fallback URL、AppGallery/market fallback 等更完整的系统能力链路；Aira 当前主要依赖 `context.openLink(url)`。
- 华为侧外跳提示更偏目标 App 图标；Aira 当前提示更偏发起网站图标，因为还不知道目标 App bundle。
- 华为侧有更强的 AppLinking 白名单/预渲染延后/Ability 查询路径；Aira 当前的重点是非 Web scheme 的安全拦截和用户确认。

## 对当前问题的解释

以 `https://pan.quark.cn/s/e8a170a25fe1` 这类页面为例：

- 这个 `https` 页面本身会被当作普通 Web URL，优先在 ArkWeb 里打开。
- 用户点击页面上的“打开 APP”后，页面可能触发一个 `quark://...` 或类似 deeplink。
- 如果这个 deeplink 是主框架、tab/window 可见、且有用户手势或近期动作，默认策略 `ask` 会显示外跳 InfoBar。
- 如果后续同样的外跳由 iframe/subframe、自动脚本、隐藏页、重复触发或没有用户激活触发，Aira 会消费加载并阻止。
- “已阻止子框架自动打开外部应用。”对应的就是非主框架 deeplink 被拦截。

图标问题则应按当前实现这样理解：

- 这个提示拿不到“夸克 App 图标”是正常的，因为 Aira 目前没有查询目标 App bundle/resource。
- 但提示不应该空白，因为它应该显示发起网站 favicon 或站点首字母 fallback。
- 修复方向应该继续走现有 `SiteIconService` / `WebsiteIconView` / `SiteIconView`，不要新建一套外跳图标路径。

## 证据索引

| 主题 | 证据位置 |
| --- | --- |
| ArkWeb `onLoadIntercept` / `onOverrideUrlLoading` 转发 | `AiraBrowser/entry/src/main/ets/core/web/HostedWebNode.ets:1020`、`:1026` |
| tab 级转发到 per-tab page | `AiraBrowser/entry/src/main/ets/core/browser/BrowserWebTabsController.ets:260`、`:272` |
| per-tab page 转到 component controller | `AiraBrowser/entry/src/main/ets/core/web/BrowserWebPageController.ets:264`、`:268` |
| Web callback 读取 URL / main frame / gesture | `AiraBrowser/entry/src/main/ets/core/web/BrowserWebComponentController.ets:312`、`:327`、`:440`、`:448`、`:456` |
| WebView 优先，能加载就不进外跳 | `AiraBrowser/entry/src/main/ets/core/web/BrowserWebComponentController.ets:371` |
| 进入 unified link 的位置 | `AiraBrowser/entry/src/main/ets/core/web/BrowserWebComponentController.ets:400` |
| WebView 支持 scheme 列表 | `AiraBrowser/entry/src/main/ets/core/web/WebRuntimeBridge.ets:204` |
| 页面 typed application shell / navigation facts | `AiraBrowser/entry/src/main/ets/app/pages/BrowserShellPage.ets:4395`、`:4448` |
| unified link context 组装 | `AiraBrowser/entry/src/main/ets/core/browser/BrowserUnifiedLinkNavigationCoordinator.ets:68` |
| dedupe interval 1200ms | `AiraBrowser/entry/src/main/ets/core/browser/BrowserUnifiedLinkNavigationCoordinator.ets:45` |
| WebView 可加载 URL 直接 `allow_web` | `AiraBrowser/entry/src/main/ets/services/web/BrowserUnifiedLinkLogic.ets:84` |
| 子框架自动外跳拦截文案 | `AiraBrowser/entry/src/main/ets/services/web/BrowserUnifiedLinkLogic.ets:90` |
| 后台/不可见页面外跳拦截 | `AiraBrowser/entry/src/main/ets/services/web/BrowserUnifiedLinkLogic.ets:95` |
| 外部导航策略委托 | `AiraBrowser/entry/src/main/ets/services/web/BrowserUnifiedLinkLogic.ets:100` |
| 策略结果映射为打开/拒绝/提示 | `AiraBrowser/entry/src/main/ets/services/web/BrowserUnifiedLinkLogic.ets:115` |
| 外部导航策略主逻辑 | `AiraBrowser/entry/src/main/ets/services/web/ExternalNavigationPolicyService.ets:65` |
| 站点/全局 effective policy | `AiraBrowser/entry/src/main/ets/services/web/ExternalNavigationPolicyService.ets:301` |
| `context.openLink(url)` | `AiraBrowser/entry/src/main/ets/services/web/ExternalNavigationPolicyService.ets:217` |
| App 名由 scheme 推断 | `AiraBrowser/entry/src/main/ets/services/web/ExternalNavigationPolicyService.ets:232` |
| 默认 external navigation 设置 | `AiraBrowser/entry/src/main/ets/data/preferences/PreferencesRepository.ets:244` |
| 设置模型类型 | `AiraBrowser/entry/src/main/ets/common/models/BrowserModels.ets:375` |
| 决策副作用 plan | `AiraBrowser/entry/src/main/ets/core/browser/BrowserUnifiedLinkApplicationCoordinator.ets:137`、`:188` |
| 显示 InfoBar / 打开外部链接 | `AiraBrowser/entry/src/main/ets/core/browser/BrowserUnifiedLinkApplicationCoordinator.ets:119`、`:198` |
| InfoBar showPrompt 和 favicon/iconUri 输入 | `AiraBrowser/entry/src/main/ets/core/browser/BrowserExternalNavigationInfoBarApplicationCoordinator.ets:145` |
| immediate memory icon | `AiraBrowser/entry/src/main/ets/core/browser/BrowserExternalNavigationInfoBarApplicationCoordinator.ets:249` |
| async cached icon hydration | `AiraBrowser/entry/src/main/ets/core/browser/BrowserExternalNavigationInfoBarApplicationCoordinator.ets:253` |
| confirm/dismiss side effects | `AiraBrowser/entry/src/main/ets/core/browser/BrowserExternalNavigationInfoBarApplicationCoordinator.ets:115`、`:312` |
| open failure toast | `AiraBrowser/entry/src/main/ets/core/browser/BrowserExternalNavigationInfoBarApplicationCoordinator.ets:361` |
| InfoBar queue | `AiraBrowser/entry/src/main/ets/core/browser/BrowserInfoBarQueue.ets:51` |
| prompt 文案 | `AiraBrowser/entry/src/main/ets/core/browser/ExternalNavigationPromptViewModel.ets:68` |
| prompt card 使用 BrowserTopPromptIcon | `AiraBrowser/entry/src/main/ets/app/components/browser/BrowserExternalNavigationPromptCard.ets:43` |
| WebsiteIconView 转 SiteIconView | `AiraBrowser/entry/src/main/ets/app/components/common/WebsiteIconView.ets:35` |
| SiteIconView URI / PixelMap / fallback 三层渲染 | `AiraBrowser/entry/src/main/ets/app/components/common/SiteIconView.ets:29` |
| SiteIconService memory/cache icon URI | `AiraBrowser/entry/src/main/ets/services/siteicons/SiteIconService.ets:271`、`:306` |
| ArkWeb favicon 入统一缓存 | `AiraBrowser/entry/src/main/ets/core/browser/BrowserFaviconCoordinator.ets:52` |
| BrowserShell 提供 current tab favicon 给 InfoBar | `AiraBrowser/entry/src/main/ets/app/pages/BrowserShellPage.ets:4128` |
| 全局设置页 | `AiraBrowser/entry/src/main/ets/app/pages/SiteControlsExternalNavigationDefaultPage.ets:64`、`:145`、`:167` |
| 全局设置 coordinator | `AiraBrowser/entry/src/main/ets/core/settings/SettingsExternalNavigationCoordinator.ets:28` |
| 单站点外跳规则写入/重置 | `AiraBrowser/entry/src/main/ets/core/sitecustomization/SiteCustomizationManagementCoordinator.ets:460`、`:493` |
| 站点控制显示 open_app 状态 | `AiraBrowser/entry/src/main/ets/core/sitecontrols/SiteControlsCoordinator.ets:279` |
| site capability 外跳选项/标签 | `AiraBrowser/entry/src/main/ets/services/web/SiteCapabilityCatalogService.ets:213` |

## 未覆盖和待确认

- 本文只描述 Aira 当前代码，不代表最终应实现的完整 AppLinking 能力。
- `context.openLink(url)` 的平台行为细节没有在本文重新查 Huawei 官方文档；华为侧调研已确认浏览器可以在白名单 AppLinking 场景使用 `openLink(... appLinkingOnly)`，但 Aira 当前没有采用这条路径。
- 如果后续要补目标 App 图标，需要新增 Ability 查询/bundle resource owner；在那之前，外跳提示图标应继续使用站点图标统一链路。
