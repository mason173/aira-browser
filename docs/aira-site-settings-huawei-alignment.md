# Aira 单站点设置对齐华为浏览器架构分析

日期：2026-07-03

## 1. 本文范围

本文只基于本地华为浏览器样本与本地 Aira 代码分析，不使用网络资料。

本地华为样本与既有调研：

- `<local-huawei-browser-research>/HuaweiBrowser-HarmonyOS-6.1.1-system-image.hap`
- `<local-huawei-browser-research>/HuaweiBrowser-HarmonyOS-6.1.1-system-image-research/modules.pa`
- `<local-huawei-browser-research>/HuaweiBrowser-site-permission-management-research.md`
- `<local-huawei-browser-research>/Aira-site-permission-management-current.md`
- `<local-huawei-browser-research>/Aira-Huawei-site-permission-alignment-design.md`

本文重点回答三个问题：

1. 华为浏览器单站点设置是怎么组织的。
2. Aira 当前单站点设置，特别是“关闭后清除 / 保留 Cookie / 站点权限”为什么容易坏。
3. 后续怎样按华为式架构对齐，同时保留 Aira 已经做对的能力。

## 2. 结论

Aira 现在不是没有单站点设置架构，但架构不够收口。

已经做对的部分：

- 单站点设置已经有 `SiteCustomizationManagementCoordinator`。
- 站点权限有 `SitePolicyService`、`PermissionPolicyService`、`PreferencesRepository`。
- 单站点关闭后清除有 `BrowserSitePrivacyRuleRepository`、`BrowserSitePrivacyRuleService`、`SiteClearOnCloseLifecycleService`、`SiteDataControlService`。
- 私密会话 session-only 权限、剪贴板脚本拦截、服务层/仓库层拆分，这些方向应该保留。

问题在于：

- 单站点设置的“设置模型”和“运行时生命周期”没有一个统一 owner。
- `关闭后清除` 的触发分散在 `BrowserShellPage.ets`、tab close coordinator、return-home coordinator、tab session persistence、startup restore 等多处回调。
- `保留 Cookie` 只是传给 `SiteDataControlService` 的一个布尔值，缺少一个面向“站点关闭策略”的统一清理计划。
- 规则是 UI 上的“站点/host”语义，但部分存储和匹配仍是 `origin` 语义，容易出现 http/https、子域、历史删除和设置页显示不一致。
- Aira 目前按站点清理 Cookie 的能力不完整。ArkWeb 常规 Cookie 清理 API 更偏全局，Aira 现在的 `clearPersistentCookies` 路径会走全局 Cookie 清理；所以“保留 Cookie”必须被严格纳入清理计划，否则很容易误伤。

所以用户直觉是对的：这不是单个按钮坏了，而是单站点设置的运行时架构边界有问题。华为更成熟的地方，不是某一个 API，而是站点设置中心 owner 更稳定，设置页、Web 初始化、运行时策略、清除能力、通知刷新都围绕同一个 Site Setting 体系。

## 3. 华为浏览器怎么做

### 3.1 一个中心 Site Setting owner

华为样本中，站点设置核心集中在：

```text
@hwbr/logic/src/main/ets/logic/sitesetting/SiteSettingLogic
SiteSettingLogicImpl
siteSettingDao
```

本地 `modules.pa` 能看到 `SiteSettingLogicImpl` 暴露了这些能力：

- `configureWhenWebInit`
- `initRestore`
- `query`
- `queryAll`
- `queryByDomain`
- `queryByPermission`
- `queryByWebElement`
- `addOrUpdate`
- `clearByWebSite`
- `clearAll`
- `onSiteSettingInfoChange`
- `offSiteSettingInfoChange`
- `setPermissionAllowedOnce`
- `isPermissionAllowedOnce`
- `clearPermissionsAllowedOnce`
- `setExceptionListForJavaScriptEnabled`
- `setExceptionListForAcceptCookie`
- `setAcceptThirdPartyCookie`
- `enableTrackingCookiePrevention`
- `setSingleSiteSettingPageModifyDelegate`
- `getSingleSiteSettingPageInformation`

这说明华为的站点设置不是“每个页面各自保存一个开关”。它有一个统一的站点设置逻辑层，页面、Web 初始化、权限请求、Cookie 例外、单站点详情都通过这个 owner 进出。

### 3.2 单站点设置页是 owner 的视图，不是 owner 本身

华为样本中存在：

```text
settings/src/main/ets/pages/websitesetting/SingleSiteSettingPage/SingleSiteSettingPage.ets
settings/src/main/ets/pages/websitesetting/WebsiteSettingsPublicController
settings/src/main/ets/pages/websitesetting/PermissionPage/PermissionPublicPageController
settings/src/main/ets/pages/websitesetting/PermissionPage/WebElementPage.ets
settings/src/main/ets/pages/websitesetting/PermissionPage/WebElementPublic.ets
```

`SingleSiteSettingPage` 里能看到：

- `parseParam`
- `aboutToAppear`
- `buildSiteSettingItem`
- `buildBottomClearButton`
- `onSiteSettingItemChange`
- `getSingleSiteSettingPageTitle`

同时它会通过 `registry.browser.webSites.getSingleSiteSettingPageInformation(...)` 读取单站点信息。也就是说，页面负责展示和转发，真正的数据聚合与行为仍在 `registry.browser.webSites` / `SiteSettingLogicImpl`。

### 3.3 站点设置对象覆盖面很宽

本地样本中的 `SiteSettingInfo` 字段包含：

| 字段 | 含义 |
| --- | --- |
| `domain` / `SLD` / `protocol` | 站点身份 |
| `geolocationPermission` | 定位 |
| `cameraPermission` | 摄像头 |
| `microphonePermission` | 麦克风 |
| `notificationPermission` | 通知 |
| `emePermission` | 受保护媒体 |
| `midiPermission` | MIDI |
| `cookie` | Cookie 站点元素 |
| `javaScript` | JavaScript |
| `popupWindow` | 弹窗 |
| `userAgent` / `preUserAgent` | 网站版本 / UA |
| `savePassword` | 保存密码 |
| `adFilterPermission` | 广告过滤 |
| `personalizationPermission` | 个性化 |
| `appQueryPermission` | 应用查询 |
| `cookieInterceptedPermission` | Cookie 拦截 |
| `appDownloadInterceptedPermission` | 应用下载拦截 |
| `appOpenInterceptedPermission` | 打开应用拦截 |
| `calendarPermission` | 日历 |

所以华为浏览器的“单站点设置”是统一站点策略中心，不只是网页权限列表。

### 3.4 Cookie 与 Web 元素设置会回写 Web runtime

华为样本里能看到：

- `setExceptionListForAcceptCookie`
- `addUrlForWebExtensionCookie`
- `setAcceptThirdPartyCookie`
- `WebCookieManager.putAcceptCookieEnabled`
- `COOKIE_SITE_ELEMENT`
- `COOKIES_INTERCEPT`
- `COOKIE_BLOCK_INFO`
- `COOKIE_BLOCK_INCOGNITO_INFO`

这说明 Cookie 开关不是仅存在设置页里。站点设置 owner 会把 Cookie 例外列表或全局 Cookie 策略配置到 Web runtime / Web extension 层。

这个点对 Aira 很关键：如果单站点设置改完只落库，没有同步运行时，用户就会看到“页面能改，但不生效”。

### 3.5 允许本次和持久允许分开

华为样本里有：

- `setPermissionAllowedOnce`
- `isPermissionAllowedOnce`
- `clearPermissionsAllowedOnce`
- `_oncePermissionAllowed`

这说明“允许本次”不是单次 callback 上临时 grant 一下，而是进入 Site Setting owner 的运行时缓存。清除站点或清除全部站点设置时，也会清理一次性授权。

### 3.6 清除能力有独立 owner

华为样本里和清理相关的能力分散在独立逻辑中，而不是单站点页面自己清：

- 站点设置清理：`clearByWebSite`、`clearAll`
- 历史清理：`SearchHistoryLogic` / history dao 有 `queryByDomain`、`deleteHistory`、`clear`
- 浏览数据清理：`BrowsingDataAdapter` 有 `removeHistory`、`removeDownloads`
- 最近关闭：`extension_recently_close` 独立管理 `ClosedTabSource`、`CloseTabStatesKVStore`
- 标签生命周期：`TabLogicFactory` 管 `closeTab`、`closeTabs`、`closeAll`

本地样本没有确认华为浏览器有一个和 Aira 完全同名的“关闭后清除”单站点开关。因此不能说华为就是这么实现这个产品项。但能确认华为式架构是：单站点设置只声明策略，真正清理由历史、浏览数据、最近关闭、tab lifecycle 这些 owner 执行。

## 4. Aira 当前怎么做

### 4.1 站点权限

Aira 当前网站权限核心链路：

- `SitePolicyService`
- `PermissionPolicyService`
- `SiteCapabilityCatalogService`
- `PreferencesRepository`
- `BrowserSiteInfoSheet`
- `SiteCustomizationManagementCoordinator`

支持：

- `camera`
- `microphone`
- `location`
- `sensor`
- `clipboard`

保留项：

- 私密会话 session-only 权限保留。
- 剪贴板 document-start 脚本拦截保留。
- 服务层/仓库层拆分保留。

### 4.2 关闭后清除

Aira 当前关闭后清除核心链路：

- `BrowserSitePrivacyRuleService`
- `BrowserSitePrivacyRuleRepository`
- `SiteClearOnCloseLifecycleService`
- `SiteDataControlService`
- `SiteClearOnClosePendingRepository`
- `BrowserHistoryVisitPersistenceCoordinator`
- `BrowserTabSessionRecordFilterCoordinator`

运行时由 `BrowserShellPage.ets` 串起来：

- 历史写入时，通过 `shouldSkipForSiteClearOnClose` 跳过记录。
- 关闭标签时，调用 `clearSiteDataForTabOnCloseIfNeeded`。
- 上滑/底栏回主页时，走 `BrowserUserReturnHomeCoordinator`，再回调 `clearSiteDataForTabOnCloseIfNeeded`。
- 最近关闭记录保存时，通过 `shouldSkipRecentlyClosedForSiteClearOnClose` 跳过。
- tab session 持久化时，通过 `buildSiteClearOnCloseTabSessionFilter` 过滤。
- App 强杀/下次启动时，通过 `SiteClearOnClosePendingRepository` 消费上次未完成记录并清理。

这套设计方向对，但触发点太散。

## 5. 当前故障为什么会发生

### 5.1 关闭入口不是统一 owner

用户期望：

- 划掉标签页卡片：算关闭。
- 上滑返回主页：算关闭当前站点。
- 直接杀 App：下次启动不能留下这个站点的历史记录。

Aira 现在每条路径都要单独记得调用：

- 清站点数据。
- 删除历史。
- 删除最近关闭。
- 过滤 tab session。
- 记录 pending cleanup。

只要某条路径少一次回调，就会出现“开关打开了但不生效”。这就是架构风险。

华为式对齐方式：tab lifecycle owner 发出统一 `siteClosed` / `tabClosed` 事件，站点隐私 owner 订阅并执行策略。页面不直接决定清理策略。

### 5.2 规则语义不统一

产品语义是“单个站点”，用户理解是 host/site。

Aira 当前规则数据是 `origin`：

```ts
BrowserSitePrivacyRule {
  profileId
  origin
  mode: 'clear_on_close'
  includeSubdomains
  preserveCookiesOnClose
  updatedAt
}
```

风险：

- `https://example.com` 和 `http://example.com` 可能在 UI 上看起来是一个站点，但存储上是两个 origin。
- 历史删除按 host，规则保存按 origin，显示聚合又按 host，容易不同步。
- 子域是否包含靠 `includeSubdomains`，但 UI 没有足够明确。

华为样本中同时存在 `domain`、`SLD`、`protocol`。这表示它至少把“站点身份”和“协议/origin 细节”分开建模。Aira 应该学习这个方向：规则主键面向 site key，origin 只是来源或运行时清理参数。

### 5.3 保留 Cookie 没有成为清理计划的一等公民

用户期望：

- `关闭后清除` 开启：关闭站点后清除浏览记录、最近关闭、tab session、站点存储、缓存。
- `保留 Cookie` 开启：Cookie 保留，但浏览记录仍清除。

Aira 当前 `SiteDataControlService.buildClearCurrentSiteDataPlan(...)` 里：

- `preserveCookiesOnClose=true` 时 `clearPersistentCookies=false`。
- `preserveCookiesOnClose=false` 时 `clearPersistentCookies=true`。

这看起来没错，但问题是普通 Cookie 清理路径实际调用的是全局 Cookie 清理能力：

```ts
webview.WebCookieManager.clearAllCookiesSync(false)
```

所以 Aira 不能把“清 Cookie”当作可靠的单站点清理。对于单站点 `clear_on_close`：

- 如果 `保留 Cookie=true`，必须明确跳过 Cookie 清理。
- 如果 `保留 Cookie=false`，除非有可用的按站点 Cookie 清理能力，否则要在产品和实现上承认这是全局 Cookie 清理，不能伪装成单站点 Cookie 清理。

华为样本中 Cookie 更像站点元素策略和例外列表：`setExceptionListForAcceptCookie`、`COOKIE_SITE_ELEMENT`、`COOKIE_BLOCK_INFO`。它不是在单站点页面里随手调用全局清 Cookie。

### 5.4 初始化顺序会影响规则是否生效

`BrowserSitePrivacyRuleRepository.initialize()` 必须早于：

- restore tabs
- history record
- clear-on-close session filter
- startup pending cleanup

否则启动早期规则列表为空，`关闭后清除` 会像没打开一样。

这一点已经在当前改动中被移到 launch readiness 阶段，是正确方向。

### 5.5 当前页面仍知道太多

`BrowserShellPage.ets` 现在仍直接参与：

- 清站点历史。
- 清最近关闭。
- pending cleanup 持久化。
- tab session 过滤。
- clear-on-close 事件记录。

这违反当前 repo 的 owner-first 方向。更重要的是，它让站点隐私生命周期很难测试，也很难保证所有关闭入口一致。

## 6. 对齐华为后的目标架构

### 6.1 统一站点设置 owner

Aira 应保留现有 `SiteCustomizationManagementCoordinator` 作为设置聚合 owner，但需要新增或强化运行时 owner：

```text
SiteSettingsRuntimeCoordinator
```

职责：

- 聚合站点设置规则。
- 暴露当前站点设置快照。
- 接收单站点设置修改。
- 通知 Web runtime 刷新策略。
- 对接站点权限、UA、内容过滤、外部动作、关闭后清除。

页面职责：

- `SiteCustomizationDetailPage` 只读 state、转发 action。
- `BrowserShellPage` 只转发当前 tab / Web runtime 事件。

### 6.2 关闭后清除独立 owner

建议新增：

```text
AiraBrowser/entry/src/main/ets/core/browser/SiteClearOnCloseCoordinator.ets
```

或把现有 `SiteClearOnCloseLifecycleService` 升级成真正 runtime owner。

职责：

- 统一处理 tab explicit close。
- 统一处理 return-home close。
- 统一处理 close-all。
- 统一处理 App kill 后启动清理。
- 统一处理 history write skip。
- 统一处理 recently closed skip。
- 统一处理 tab session persistence filter。
- 统一产出清理计划。

`BrowserShellPage.ets` 不再调用多个零散私有方法，只转发事件：

```text
onTabClosed(tab)
onSiteReturnedHome(tab)
onBeforePersistTabs(records)
onStartupRestore(records)
onHistoryVisitCandidate(url, tab)
```

### 6.3 清理计划一等公民化

新增明确的 plan：

```ts
interface SiteClearOnClosePlan {
  siteKey: string;
  host: string;
  origins: string[];
  profileId: BrowserProfileId;
  dataScope: BrowserDataScope;
  preserveCookies: boolean;
  clearHistory: boolean;
  clearRecentlyClosed: boolean;
  clearTabSession: boolean;
  clearStorage: boolean;
  clearCache: boolean;
  clearCookies: boolean;
}
```

规则：

- `clearHistory` 永远为 true。
- `clearRecentlyClosed` 永远为 true。
- `clearTabSession` 永远为 true。
- `clearStorage` 为 true。
- `clearCache` 为 true。
- `clearCookies = !preserveCookies && hasReliableSiteCookieClearCapability`。

如果没有可靠按站点 Cookie 清理能力，`clearCookies` 不应默认调用全局 Cookie 清理。否则“单站点清理”会伤害其他站点登录态。

### 6.4 site key 和 origin 分层

建议把 `BrowserSitePrivacyRule` 调整为面向站点：

```ts
interface BrowserSitePrivacyRule {
  profileId: BrowserProfileId;
  siteKey: string;
  displayHost: string;
  primaryOrigin: string;
  mode: 'clear_on_close';
  includeSubdomains: boolean;
  preserveCookiesOnClose: boolean;
  updatedAt: number;
}
```

当前实现已经做干净切换，不做旧数据迁移或旧格式修补。服务层统一：

- 保存时用同一个 resolver。
- 查找时用同一个 resolver。
- 删除历史时用同一个 resolver。
- 设置页聚合时用同一个 resolver。

不要一处按 origin、一处按 host、一处按简化 site key。

## 7. 交互对齐

### 7.1 单站点详情页

单站点详情建议按华为心智分组：

1. 权限
   - 位置
   - 摄像头
   - 麦克风
   - 通知
   - 传感器
   - 剪贴板

2. 网站功能
   - 网站版本 / UA
   - 弹窗与重定向
   - 打开应用
   - JavaScript / 用户脚本
   - Cookie / Cookie 拦截

3. 隐私
   - 关闭后清除
   - 保留 Cookie
   - 清除该站点数据

4. 内容与安全
   - 内容过滤例外
   - 跟踪保护例外

### 7.2 关闭后清除文案

当只打开 `关闭后清除`：

```text
关闭此站点后，将清除历史记录、最近关闭记录、站点存储和缓存。
```

当同时打开 `保留 Cookie`：

```text
关闭此站点后，将清除历史记录、最近关闭记录、站点存储和缓存，但保留 Cookie 登录状态。
```

如果当前版本不能可靠按站点删除 Cookie，不要写“会清除该站点 Cookie”。可以写：

```text
Cookie 清理依赖系统 Web 能力；为避免影响其他站点登录状态，当前单站点关闭后清除会保留 Cookie。
```

### 7.3 关闭触发语义

对用户明确：

| 用户动作 | 是否触发关闭后清除 |
| --- | --- |
| 划掉标签页卡片 | 是 |
| 上滑返回主页 | 是，等同关闭当前网页 |
| 底栏主页按钮返回主页 | 是，等同关闭当前网页 |
| 切换到其他标签 | 否 |
| App 直接被杀 | 是，下次启动补偿清理 |
| 普通后退到上一页 | 否 |
| 站点内跳转 | 否 |

## 8. Aira 当前修复优先级

### P0：先收口架构，不继续往页面加逻辑

目标：

- 新增 `SiteClearOnCloseCoordinator` 或升级 `SiteClearOnCloseLifecycleService` 为 runtime owner。
- 关闭入口统一发事件。
- BrowserShellPage 只保留事件转发。

验收：

- 卡片关闭、上滑回主页、底栏回主页、关闭全部、强杀恢复全部走同一套 plan。
- 单测或轻量 harness 能验证每个入口调用同一个 owner。

### P0：修正规则匹配和初始化

目标：

- 站点隐私规则仓库必须在 restore/history 之前初始化。
- `https://host` 和 `http://host` 按产品站点语义一致匹配。
- 保存、显示、删除、匹配全部使用同一个 site resolver。

当前代码已有部分修复方向：

- `sharedBrowserSitePrivacyRuleRepository.initialize()` 已移到 launch readiness。
- `BrowserSitePrivacyRuleService.matchesRule()` 已补同 host 跨 scheme 匹配。

### P0：保留 Cookie 语义落到 plan

目标：

- `preserveCookiesOnClose=true` 时绝不调用全局 Cookie 清理。
- `preserveCookiesOnClose=false` 时，如果没有可靠按站点 Cookie 删除能力，不要用全局清理冒充单站点清理。
- 文案和实际能力一致。

### P1：站点设置变更后刷新运行时

目标：

- 修改权限、UA、Cookie、关闭后清除后，当前 tab 的 Web runtime 立即拿到新策略。
- 需要 reload 的能力由 owner 判断，不由页面临时判断。

当前状态：已完成，刷新判断在 `SiteCustomizationRuntimeRefreshCoordinator`，页面只执行 plan。

### P1：一次性授权缓存对齐华为

目标：

- `allow once` 进入 `SitePolicyService` 或 `WebPermissionCoordinator` 的内存缓存。
- 清除站点设置、清除全部、私密会话结束时清空对应缓存。

当前状态：已完成，`SitePolicyService` 管 per-origin/per-kind/profile/scope allow-once 缓存并在清除路径同步清空。

## 9. 是否“华为更好”

华为在站点设置架构上更成熟，原因是：

- 有中心 Site Setting owner。
- 页面不是规则 owner。
- Web 初始化会统一读取站点设置并配置 runtime。
- 单站点、全局设置、权限请求、Cookie 例外、一次性授权、清除站点设置都围绕同一个体系。
- 清理能力由历史、浏览数据、最近关闭、tab lifecycle 等 owner 承担。

Aira 的优势是：

- 私密会话 session-only 权限模型更明确。
- 剪贴板脚本拦截是 Aira 有用的补充能力。
- 服务层/仓库层已经开始拆出来，改成华为式 owner-first 架构成本可控。

Aira 当前的问题是运行时收口不够。不要继续在 `BrowserShellPage.ets` 补更多判断；应该把单站点设置的策略、生命周期和清理计划统一到非页面 owner。

## 10. 下一步实现边界

下一步如果开始改代码，应按这个顺序：

1. 建 `SiteClearOnCloseCoordinator`，把关闭后清除的 plan、history skip、recently closed skip、tab session filter、startup cleanup 统一进去。
2. BrowserShellPage 只转发 tab lifecycle / history candidate / startup records。
3. `SiteIdentityService` 提供统一 site resolver；UA、权限、关闭后清除规则已经使用必填 `siteKey/displayHost/primaryOrigin`，不保留旧格式兼容路径。
4. `SiteDataControlService` 暴露明确的 `buildSiteCloseClearPlan`，不要让调用者自己拼 `preserveCookiesOnClose`。
5. 单站点详情页只展示 state，所有开关写入 `SiteCustomizationManagementCoordinator`，并通过 runtime owner 刷新当前站点策略。
6. 华为式 allow-once 缓存已经完成；后续只做真机实测发现的细节修正。

这个顺序能先把当前“关闭后清除 / 保留 Cookie / 单站点权限改了不生效”的结构性问题压住，再继续补功能。

## 11. 本地样本证据索引

本节记录本次判断来自哪些本地材料，避免后续实现时又回到网络资料或凭印象改代码。

### 11.1 华为浏览器本地样本

样本位置：

- `<local-huawei-browser-research>/HuaweiBrowser-HarmonyOS-6.1.1-system-image.hap`
- `<local-huawei-browser-research>/HuaweiBrowser-HarmonyOS-6.1.1-system-image-research/modules.pa`

关键观察点：

| 证据 | 本地样本中观察到的名称 | 对 Aira 的含义 |
| --- | --- | --- |
| 站点设置中心 owner | `SiteSettingLogicImpl`、`SiteSettingLogic`、`siteSettingDao` | 单站点设置不应由页面和各入口分别决定，应该有中心 owner |
| Web 初始化配置 | `configureWhenWebInit`、`initRestore` | 设置落库后还要同步到 Web runtime，不能只改 UI 状态 |
| 单站点设置页 | `SingleSiteSettingPage`、`SingleSiteSettingPageController`、`getSingleSiteSettingPageInformation` | 页面是 owner 的视图和操作入口，不是策略 owner |
| 一次性授权 | `setPermissionAllowedOnce`、`isPermissionAllowedOnce`、`clearPermissionsAllowedOnce`、`_oncePermissionAllowed` | `允许本次` 应进入运行时缓存，而不是只 grant 当前 request |
| Cookie 站点例外 | `setExceptionListForAcceptCookie`、`addUrlForWebExtensionCookie`、`COOKIE_SITE_ELEMENT`、`COOKIES_INTERCEPT` | Cookie 策略需要 Web runtime / extension 层同步，不应在单站点清理里随手全局清 Cookie |
| 站点信息变化通知 | `onSiteSettingInfoChange`、`offSiteSettingInfoChange`、`notifyDataChanged` | 设置变更后要有统一通知和刷新链路 |
| 清理职责拆分 | `BrowsingDataAdapter.removeHistory`、`BrowsingDataAdapter.removeDownloads`、`SearchHistoryLogic` | 清理由数据 owner 执行，单站点设置只声明策略 |
| 最近关闭独立管理 | `ClosedTabSource`、`CloseTabStatesKVStore`、`extension_recently_close` | 最近关闭不能只在页面里临时跳过，应由 lifecycle/数据 owner 接入策略 |
| 标签生命周期 owner | `TabLogicFactory`、`closeTab`、`closeTabs`、`closeAll` | 关闭入口应收口到 tab lifecycle owner，再触发站点隐私策略 |

### 11.2 已写过的本地调研材料

本次文档复用了这些本地 MD，不使用网络搜索：

- `<local-huawei-browser-research>/HuaweiBrowser-site-permission-management-research.md`
- `<local-huawei-browser-research>/Aira-site-permission-management-current.md`
- `<local-huawei-browser-research>/Aira-Huawei-site-permission-alignment-design.md`

其中可直接复查的结论：

- 华为网站权限是系统权限、ArkWeb request、浏览器站点策略三层结构。
- 华为 Site Setting 体系同时管理 camera、microphone、location、notification、cookie、JavaScript、popup、UA、广告过滤、应用打开拦截等站点能力。
- 华为可观察到 `允许本次 / 始终允许 / 阻止` 的权限弹窗交互。
- Aira 当前已经有 `SitePolicyService`、`PermissionPolicyService`、`PreferencesRepository`、`SiteCustomizationManagementCoordinator`，不是从零开始。
- Aira 当前最危险的问题是运行时入口分散，尤其是关闭后清除、保留 Cookie、历史/最近关闭/tab session/startup cleanup 没有统一 plan。

## 12. 当前实现进度与交接

更新时间：2026-08-08

关键提交：

```text
6cc81da90 fix: align site settings lifecycle
9be59ac40 docs: add site settings handoff
2c917936a docs: make site settings handoff portable
609eaa005 docs: replace local handoff paths
```

当前仓库状态：

- `main` 分支已提交 P0 与可移植交接文档；换电脑后先 `git pull --ff-only origin main`。
- 2026-07-03 本轮继续完成 P1 runtime refresh、P1 allow-once 清理收口、P2 site identity 干净切换。
- 本轮没有加入旧数据迁移、旧格式修复、fallback transform 或兼容保留路径；缺少 `siteKey/displayHost/primaryOrigin` 的旧规则会被读取层丢弃。
- 已运行 `./scripts/build-aira-browser.sh`，构建通过并安装到连接设备。
- 构建输出：`AiraBrowser/entry/build/default/outputs/default/entry-default-signed.hap`

### 12.1 已完成

已完成 P0 主体：

- 新增 `AiraBrowser/entry/src/main/ets/core/browser/SiteClearOnCloseCoordinator.ets`。
- `关闭后清除` 的显式关闭、启动补偿清理、tab session 过滤、pending 记录、历史删除、最近关闭删除，已统一进入 `SiteClearOnCloseCoordinator`。
- `BrowserShellPage.ets` 只保留 `SiteClearOnCloseCoordinatorHost` 和事件转发，不再直接拥有 `deleteSiteHistoryOnClose`、`deleteRecentlyClosedForSiteOnClose` 这类清理策略。
- `BrowserTabSessionRecordFilterCoordinator` 中原来只代转 site-clear 过滤的空方法已删除，避免假 owner。
- `SiteDataControlService.ets` 新增 `SiteDataClearOnClosePlan` 和 `buildSiteDataClearOnClosePlan(...)`。
- 单站点关闭后清除不再使用 `WebCookieManager.clearAllCookiesSync(false)` 冒充“清除该站点 Cookie”，避免误伤其他站点登录态。
- `preserveCookiesOnClose` 已成为关闭后清除 plan 的显式字段。
- `BrowserSitePrivacyRuleRepository.initialize()` 已在 launch readiness 阶段初始化，早于 restore/history 等早期路径。
- `BrowserSitePrivacyRuleService.matchesRule()` 已支持同 host 跨 scheme 匹配。
- 单站点权限写入方向已对齐到 `SitePolicyService.persistPermissionRuleForOrigins()` / `persistPermissionDraftForOrigins()`，保留私密会话 `session-only` 语义。
- 私密会话 `session-only` 权限、剪贴板 document-start 脚本拦截、服务层/仓库层拆分都保留。
- 已把 ArkWeb Cookie 全局清理不能当作单站点 Cookie 删除的经验写入 `.codex/skills/harmonyos-native/references/browser-architecture.md`。

本次提交同时包含这些架构拆分：

- `BrowserWebCapabilityPromptApplicationCoordinator.ets`
- `BrowserWebPageFeatureEffectsCoordinator.ets`
- `BrowserWebPagePresentationEventCoordinator.ets`
- `BrowserWebPageLifecycleApplicationCoordinator.ets` 的相关应用层收口
- `BrowserUnifiedLinkNavigationCoordinator.ets` 的应用结果执行收口

这些拆分的目的都是减少 `BrowserShellPage.ets` 中的业务逻辑，让页面回到 ArkUI/ArkWeb binding、state passing、event forwarding。

### 12.2 本轮完成

P1：站点设置变更后刷新运行时已收口：

- 新增 `AiraBrowser/entry/src/main/ets/core/sitecustomization/SiteCustomizationRuntimeRefreshCoordinator.ets`。
- 单站点设置页在权限、桌面站点、关闭后清除、保留 Cookie、重置后发出 typed refresh reason。
- `BrowserShellPage.ets` 只监听 refresh revision、传入 active tab/runtime facts、执行 owner 返回的 plan；是否 reload 由 `SiteCustomizationRuntimeRefreshCoordinator` 判断。
- 当前 plan 会刷新站点数据策略、当前站点权限、UA runtime 配置，并在 UA/reset/general 场景触发当前页 reload。

P1：华为式 allow-once 缓存已收口：

- `SitePolicyService` 维护 per-origin/per-kind/profile/scope 的 allow-once 内存缓存。
- `WebPermissionCoordinator` 的 `允许本次` 会写入该缓存。
- 单站点清除、全站点权限清除、私密会话清理都会清空匹配的 allow-once 缓存。

P1：单站点设置交互已对齐当前目标：

- 权限设置主交互保持 `询问 / 允许 / 拒绝`。
- 权限请求弹窗主动作已经是 `允许本次 / 始终允许 / 阻止`。
- 系统权限被拒后的设置引导保留在既有 `SystemPermissionService` / 权限请求链路中。

P2：exact-Origin Saved Site Setting 与 Host Rule 已分层：

- `SiteIdentityService` 分别解析 exact HTTP/HTTPS Origin 目标和 host 规则目标；exact-Origin 的 scheme、host、有效端口共同参与身份，不跨协议、端口或子域名回退。
- `SavedSiteSettingRepository` 以 profile 加 canonical Origin 保存站点覆盖项，网页标识通过 `userAgentIdentityId` 引用全局浏览标识目录。
- 站点管理页标题栏的“添加站点”入口支持手动输入域名、IP、localhost 或完整 HTTP/HTTPS 地址；非默认端口直接进入对应的独立 Origin，只有用户保存具体设置时才创建记录。
- 关闭后清除、权限和网页标识仍由各自 owner 执行；需要 host/include-subdomains 语义的内容过滤例外继续由 Host Rule 管理，不混入 Saved Site Setting。
- 旧 `BrowserUserAgentSiteRule` 模型、解析、CRUD 和 UA runtime fallback 已删除。启动清理只按原始 key 删除 `desktop_site_rules`，不再读取或迁移旧记录。
- Saved Site Setting 读取层只接受当前结构记录；没有旧格式修补、fallback transform 或 host 规则迁移。

### 12.3 后续建议

下一步不再是 P1 主链路实现，而是设备实测与细节打磨：

1. 在手机上按真实网站验证：权限改动、桌面/移动版、关闭后清除、保留 Cookie、重置后当前 tab 是否即时应用新策略；从“添加站点”分别输入同一 IP 的 `:8080` / `:9090`，确认两条设置互不影响。
2. 观察 Cookie 策略在 ArkWeb 可用 API 边界内的即时效果；Aira 仍不能用全局 Cookie 清理冒充单站点 Cookie 删除。
3. 如实测发现某类策略必须 reload 才能可靠生效，把判断加到 `SiteCustomizationRuntimeRefreshCoordinator`，不要放回 `BrowserShellPage.ets`。

### 12.4 换电脑继续 Prompt

把下面这段发给下一台电脑上的 Codex：

```text
继续 Aira-browser 仓库里的 Aira HarmonyOS NEXT 浏览器单站点设置/网站权限管理工作。

先进入已经 clone 好的 Aira-browser 仓库根目录；下面用 <repo> 表示这个仓库根目录。不要依赖旧电脑的本地绝对路径。先执行：

git pull --ff-only origin main

必须先读取仓库 AGENTS.md 和 .codex/skills/harmonyos-native/SKILL.md，遵守 BrowserShellPage.ets active debt paydown 规则：页面只能做 ArkUI/ArkWeb binding、state passing、event forwarding；任何权限、站点设置、关闭后清除、运行时刷新、清理策略都必须进 core/services/data/features 的 owner，不要往 BrowserShellPage.ets 加业务逻辑。

背景：
- 用户要求对齐本地华为浏览器样本，不要网络搜索。
- 华为浏览器样本不是仓库内容。如果新电脑也有 Huawei-browser 样本目录，把新电脑上的实际路径告诉 AI；如果没有，就先基于仓库里的 docs/aira-site-settings-huawei-alignment.md 和本仓库代码继续，不要编造样本路径。
- 重点文档是 docs/aira-site-settings-huawei-alignment.md，尤其第 12 节。
- 已提交进度：6cc81da90 fix: align site settings lifecycle。
- 已提交交接文档：2c917936a docs: make site settings handoff portable。
- 这个提交已经完成 P0：新增 SiteClearOnCloseCoordinator，把关闭后清除的显式关闭、启动补偿、tab session 过滤、pending 记录、历史删除、最近关闭删除收口；BrowserShellPage 只剩 host/wiring；SiteDataControlService 有关闭后清除专用 plan，不再用 WebCookieManager.clearAllCookiesSync(false) 冒充单站点 Cookie 删除。
- 2026-07-03 本轮继续完成 P1 runtime refresh、P1 allow-once 清理收口、P2 site identity 干净切换；已运行 ./scripts/build-aira-browser.sh，构建通过并安装到连接设备。
- 不要做旧格式兼容、迁移、修补、fallback transform；缺少 siteKey/displayHost/primaryOrigin 的旧记录应直接丢弃。

继续前先执行：
1. git status --short
2. git log -3 --oneline
3. 阅读 docs/aira-site-settings-huawei-alignment.md 的第 12 节
4. 只基于新电脑实际可用的 Huawei-browser 样本、仓库文档和仓库代码继续，不要网络搜索

下一步建议：
1. 在手机上实测权限改动、桌面/移动版、关闭后清除、保留 Cookie、重置后当前 tab 是否即时应用新策略。
2. 如果某类设置实测必须 reload 才可靠生效，把判断放进 SiteCustomizationRuntimeRefreshCoordinator，不要放回 BrowserShellPage.ets。
3. 继续保留 Aira 已做对的能力：私密会话 session-only 权限、剪贴板 document-start 脚本拦截、服务层/仓库层拆分。
4. 如果碰 BrowserShellPage.ets，必须同时减少 touched area 的页面业务逻辑，并在最终说明里写清楚抽出了什么。
5. 代码改完运行 ./scripts/build-aira-browser.sh。设备安装脚本不在本仓库。
```
