# Aira 智能搜索引擎回退设计文档

日期：2026-07-05

状态：已实现。已落地设置、持久化、短窗口探测、地址栏搜索路由、启动/网络/代理变化预热，以及主引擎真实加载失败后的单次自动回退。

## 一句话结论

建议做，但不要做成“静默改默认搜索引擎”。Aira 应该提供一个可关闭的“智能搜索回退”能力：用户设置主搜索引擎和备用搜索引擎，地址栏提交搜索词时优先使用主搜索引擎；如果主搜索引擎在当前网络/代理环境下不可用，则本次搜索临时使用备用搜索引擎。

这个功能适合跨境出差、港澳/新加坡/内地频繁往返、以及经常切换代理开关的用户。它解决的是“我习惯用 Google，但当前网络突然不能用，地址栏搜索不要卡死或失败”的问题。

## 当前实现状态

已实现：

- “设置 > 搜索”新增“智能搜索回退”开关和“备用搜索引擎”选择页。
- `SearchEngineSettings` 增加 `fallbackSearch` 配置，仓库层负责归一化、持久化和主备不能相同的保护。
- 内置搜索引擎增加探测配置：Google 使用 `https://www.google.com/generate_204` 并期望 204；Bing/Baidu 使用各自首页可达性。
- 新增 `SearchEngineAvailabilityProbeService`，负责短超时 HTTP 探测、TTL 缓存、代理签名和缓存失效。
- 新增 `SearchEngineRoutingService`，地址栏搜索词提交时按主搜索引擎可达性选择实际搜索引擎；URL 输入不触发回退。
- App 启动、网络变化、回到前台和代理配置变化后，会清空主引擎可达性缓存并延迟预热。
- 如果短窗口内仍使用了主引擎，但该次搜索随后发生主框架加载失败，Aira 会自动用备用引擎完成同一查询，不先显示错误页，也不要求再次确认。
- 搜索历史记录实际使用的搜索引擎，而不是永远记录默认搜索引擎。
- `BrowserShellPage.ets` 只做异步提交、结果应用、toast 展示和事件转发；搜索回退策略在服务层。

未实现：

- 暂未提供高级用户自定义探测 URL；自定义搜索引擎首版使用主页或记录中的探测 URL。
- 暂未让网络搜索建议源跟随主备引擎切换。

验证状态：

- 已运行 `HDC_TARGET=5MT0226114030639 ./scripts/install-aira-browser.sh`，架构守卫、signed HAP 构建和 USB 真机安装均成功；安装版本为 `2.5.3 (1000699)`。
- 用户已在无代理真机环境确认 Google 主引擎不可用时会自动转到百度，且不会先展示错误页或要求再次确认。

## 调研结论

公开产品里没有看到 Chrome、Firefox、Edge 等主流浏览器把“Google 不通时自动把地址栏搜索换成百度/Bing”作为常规默认能力。它们主要提供手动默认搜索引擎选择、搜索建议开关、站点搜索或一次性切换。

但这个需求的底层技术思路是有先例的：

- Chromium OS 使用 `generate_204` 类 URL 做网络门户检测，预期返回 HTTP 204，用于判断网络是否被 captive portal 劫持。
- Android AOSP `NetworkMonitor` 也使用 Google/gstatic 的 `generate_204` 类地址做连通性探测，并配置短超时。
- Brave Search 有“fallback mixing”的近似产品思路：当 Brave 自有结果不足时，允许匿名检查 Google 并补充结果；它不是网络不可达回退，但说明“搜索主路径 + 备用策略”是可被用户理解的。
- SearXNG 这类元搜索系统会给不同搜索引擎配置 timeout，某个引擎失败时不让整体搜索被拖死，工程思想接近“搜索源失败隔离”。

参考资料：

- [Chromium OS Network Portal Detection](https://www.chromium.org/chromium-os/chromiumos-design-docs/network-portal-detection/)
- [AOSP NetworkMonitor.java](https://android.googlesource.com/platform/frameworks/base/+/android-7.1.1_r4/services/core/java/com/android/server/connectivity/NetworkMonitor.java)
- [Brave Search Google fallback mixing](https://search.brave.com/help/google-fallback)
- [SearXNG engine settings](https://docs.searxng.org/admin/settings/settings_engines.html)
- [Chrome default search engine help](https://support.google.com/chrome/answer/95426)
- [Firefox default search settings](https://support.mozilla.org/en-US/kb/change-your-default-search-settings-firefox)
- [Microsoft Edge default search engine](https://support.microsoft.com/en-us/edge/change-your-default-search-engine-in-microsoft-edge)
- [HarmonyOS HTTP 请求指导](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/http-request)

## 产品目标

- 用户可以保留自己习惯的主搜索引擎，例如 Google。
- 当前网络无法访问主搜索引擎时，地址栏搜索能自动完成，不让用户手动重新输入关键词。
- 自动回退必须透明、可关闭、可解释，避免用户以为浏览器偷偷把默认搜索引擎改掉。
- 探测请求不能携带搜索词；搜索词只发送给最终实际使用的搜索引擎。
- 搜索体验不能因为探测明显变慢。

## 非目标

- 不做地区自动判断，不根据 SIM、GPS、系统地区或 IP 所属地切换搜索引擎。
- 不把全局默认搜索引擎永久改成备用搜索引擎。
- 不做多级搜索引擎链路，MVP 只支持一个主搜索引擎和一个备用搜索引擎。
- 不把手动打开的搜索结果 URL 或普通网页错误自动改写为备用搜索；真实加载失败自动回退只消费由本次智能搜索路由登记的一次性资格。
- 不让网络搜索建议自动跟着 Google/Baidu 切换，搜索建议源可在后续版本单独设计。

## 用户交互设计

### 设置入口

入口仍然放在“设置 > 搜索”。现有“默认搜索引擎”继续作为主搜索引擎使用，避免大规模改名带来的学习成本。

建议设置结构：

```text
搜索引擎
  默认搜索引擎        Google
  智能搜索回退        开关
  备用搜索引擎        百度（回退关闭时保留但置灰）
  回退提示            开关，默认打开

搜索建议
  搜索历史建议        开关
  网络搜索建议        开关
```

当“智能搜索回退”关闭时，“备用搜索引擎”和“回退提示”保留显示但置灰，避免用户不知道可以配置备用引擎。当开关打开但没有可用备用引擎时，引导用户选择一个与默认搜索引擎不同的引擎。

建议页脚文案：

```text
主搜索引擎当前不可用时，地址栏会自动使用备用搜索引擎完成本次搜索。检测只访问可达性地址，不发送搜索词。
```

### 首次打开开关

首次打开“智能搜索回退”时：

- 如果默认搜索引擎是 Google，推荐备用搜索引擎为百度；如果百度未启用，则推荐 Bing。
- 如果默认搜索引擎不是 Google，推荐备用搜索引擎为 Bing；如果与默认搜索引擎相同，则选择列表中第一个不同的可用搜索引擎。
- 用户仍可手动改成其他内置或自定义搜索引擎。

### 地址栏搜索行为

用户输入看起来像网址、`http(s)`、`file://`、`aira://` 时，不触发搜索回退，直接按网址打开。

用户输入普通搜索词时：

1. 智能回退关闭：使用默认搜索引擎。
2. 智能回退开启但当前用户没有有效 Aira Pro：仍只使用默认搜索引擎，不执行探测或备用引擎切换。
3. 智能回退开启且当前用户具有有效 Aira Pro：优先使用当前网络/代理签名下仍有效的后台预热结果；没有结果时，提交最多等待一个短 `HEAD` 探测窗口。
4. 主引擎可用或短窗口探测结果不确定：使用主搜索引擎。
5. 主引擎被较长后台探测或明确的 DNS/TLS/连接错误判定为不可用：使用备用搜索引擎。

自定义主页调用 `AiraHome.search(query)` 时使用上述默认搜索策略，不能传入回退模式、备用引擎、提示开关或会员状态。调用 `AiraHome.search(query, { engineId })` 才属于显式引擎意图：该次搜索精确使用指定引擎，不执行可达性探测，也不使用备用搜索引擎。`AiraHome.setSearchEngine(engineId)` 只修改当前有效的默认引擎，本身不赋予后续搜索绕过或强制使用智能回退的能力。

建议短探测窗口：

- 普通提交：最多等待 700-1000ms。
- App 启动、网络变化、代理变化后的后台预热：不阻塞 UI。

### 用户提示

自动回退时显示轻提示，但要限频，避免每次搜索都打扰用户。

建议文案：

```text
Google 当前不可用，已用百度搜索。
```

限频建议：

- 同一主/备用组合、同一会话内最多提示一次。
- 网络或代理变化后可重新提示一次。
- 如果用户手动选择某个搜索引擎完成本次搜索，不显示自动回退提示。
- 用户可以在“设置 > 搜索”关闭“回退提示”；关闭后只影响提示，不影响自动回退。

### 搜索失败后的兜底

即使探测认为 Google 可用，实际搜索结果页仍可能加载失败。对于本次由智能搜索路由提交、资格校验已通过且尚未回退的主引擎搜索，主框架失败会消费一次性回退资格，并直接用备用引擎构造同一查询的搜索 URL。

这个兜底不先展示错误文档、不要求用户点击确认；“回退提示”开启时只显示与提交前回退相同的轻提示。一次性资格消费后不会再次回退，因此备用引擎失败会进入普通错误处理，不形成循环。手动打开的搜索结果 URL、明确指定引擎的搜索和普通网页错误不会获得该资格。

## 架构设计

### 单一业务 Owner

这个功能的 owner 应该在搜索域，不在页面里。

推荐 owner：

```text
SearchEngineRoutingService
```

职责：

- 判断本次地址栏提交是网址导航还是搜索。
- 读取搜索回退配置。
- 在每次提交时检查原生有效 Aira Pro 资格；设置页校验不能替代运行时守门。
- 根据缓存和可达性探测选择实际搜索引擎。
- 返回结构化 submission，包含实际 URL、实际搜索引擎、是否发生回退、回退原因和可展示提示。

第三方主页只提交查询词和可选的明确引擎 ID。`SearchEngineRoutingService` 不接受第三方传入的
`routingMode`、`allowFallback`、备用引擎、提示设置或会员状态；这些事实全部来自 Aira 原生运行时。

页面职责：

- `BrowserShellPage.ets` 只负责转发地址栏提交事件、应用返回的 submission、执行打开 URL。
- 不在 `BrowserShellPage.ets` 中写网络探测、缓存、主备选择、toast 限频、代理判断或回退策略。

### 推荐模块分层

```text
BrowserShellPage.ets
  -> BrowserAddressSubmissionCoordinator
    -> SearchEngineRoutingService
      -> SearchEngineAvailabilityProbeService
      -> SearchEngineTemplateService
      -> SearchEngineRepository
      -> NativeHttpProxyResolutionService

SearchSettingsPage.ets
  -> SearchEngineManagementViewModel
  -> SearchEngineRepository
```

建议新增/调整的文件：

- `AiraBrowser/entry/src/main/ets/services/search/SearchEngineRoutingService.ets`
- `AiraBrowser/entry/src/main/ets/services/search/SearchEngineAvailabilityProbeService.ets`
- `AiraBrowser/entry/src/main/ets/services/search/SearchEngineFallbackNoticePolicyService.ets`
- `AiraBrowser/entry/src/main/ets/services/network/NativeHttpProxyResolutionService.ets`
- `AiraBrowser/entry/src/main/ets/core/navigation/BrowserAddressSubmissionCoordinator.ets`
- `AiraBrowser/entry/src/main/ets/data/search/SearchEngineRepository.ets`
- `AiraBrowser/entry/src/main/ets/core/search/SearchEngineManagementViewModel.ets`
- `AiraBrowser/entry/src/main/ets/app/components/search/SearchSettingsScreen.ets`
- `AiraBrowser/entry/src/main/ets/app/pages/SearchSettingsPage.ets`

`NativeHttpProxyResolutionService` 可以从现有 `NativeVideoHttpProxyService` 中抽出通用能力，避免搜索探测和原生视频请求各自维护一套代理解析逻辑。

### 数据模型

在 `SearchEngineSettings` 中增加回退配置：

```ts
export interface SearchEngineFallbackSettings {
  enabled: boolean;
  fallbackSearchEngineId: SearchEngineId;
  noticeEnabled: boolean;
}

export interface SearchEngineSettings {
  defaultSearchEngineId: SearchEngineId;
  builtInEngineOrder: SearchEngineId[];
  enabledBuiltInEngineIds: SearchEngineId[];
  customEngines: SearchEngineRecord[];
  searchSuggestions: SearchSuggestionPreferences;
  fallbackSearch: SearchEngineFallbackSettings;
  updatedAt: number;
}
```

不建议把动态探测状态持久化。可达性状态是网络/代理环境的瞬时结果，放在内存缓存即可。

运行时缓存模型：

```ts
export type SearchEngineReachability = 'unknown' | 'reachable' | 'unreachable';

export interface SearchEngineAvailabilitySnapshot {
  engineId: SearchEngineId;
  reachability: SearchEngineReachability;
  checkedAt: number;
  expiresAt: number;
  probeUrl: string;
  networkSignature: string;
  proxySignature: string;
  reason: string;
}
```

`networkSignature` 用于网络变化后失效缓存，`proxySignature` 用于代理配置变化后失效缓存。

### 探测策略

不要每次点开搜索框就探测。搜索框获得焦点可以触发后台预热，但不能阻塞输入。

推荐触发点：

- App 启动后延迟预热一次，不进入 launch readiness 关键路径。
- 网络变化后清空缓存并延迟探测。
- App 回到前台后，如果缓存过期则延迟探测。
- 代理开关或代理配置变化后清空缓存并延迟探测。
- 用户提交搜索词时优先复用仍有效的预热缓存；缓存缺失时才执行一次短超时 `HEAD` 探测。网络、App 代理和前台恢复事件继续负责失效并刷新缓存。

推荐 TTL：

- 成功：5-10 分钟。
- 失败：1-3 分钟。
- 网络/代理变化：立即失效。

推荐超时：

- 后台预热：1500-2500ms。
- 提交时等待：700-1000ms。

### 探测 URL 规则

内置搜索引擎可以增加可达性探测配置：

```ts
export interface SearchEngineOption {
  id: SearchEngineId;
  name: string;
  searchUrlTemplate?: string;
  homepageUrl?: string;
  availabilityProbeUrl?: string;
  availabilityExpectedStatus?: number;
}
```

建议默认值：

```text
Google: https://www.google.com/generate_204, expected 204
Bing:   https://www.bing.com, any HTTP response from target host
Baidu:  https://www.baidu.com, any HTTP response from target host
```

不建议只用 `http://www.gstatic.com/generate_204` 作为 Google 是否可用的唯一判断。`gstatic` 可用不等于 `www.google.com/search` 可用；而且本功能判断的是搜索服务是否可用，不是 captive portal 检测。Google 主引擎更适合优先探测 `https://www.google.com/generate_204` 或 Google 搜索同域的轻量 URL。

自定义搜索引擎：

- 默认使用 `homepageUrl` 做轻量 `HEAD` 探测，避免为了判断可达性等待或下载完整首页正文。
- 如果拿到目标主机的任意 HTTP 响应，可以认为网络路径可达。
- 如果 DNS、连接或 TLS 明确失败，则认为不可达。
- 提交路径的 700-1000ms 短超时只代表结果不确定，继续使用用户选择的主引擎；较长后台探测超时才可形成不可达结论。
- 后续版本可以允许高级用户自定义探测 URL，但 MVP 不需要暴露。

### 代理一致性

Aira 已经有 ArkWeb 代理：

```text
ArkWebAppProxyService
  -> webview.ProxyController.applyProxyOverride(...)
```

同时原生视频请求已有原生 HTTP 代理解析：

```text
NativeVideoHttpProxyService
  -> http.HttpRequestOptions.usingProxy
```

搜索引擎探测必须和“实际搜索页面加载路径”尽量一致。否则会出现：

- ArkWeb 走代理能打开 Google，但原生探测不走代理，于是误判 Google 不可用。
- 原生探测走系统网络可访问某站，但 ArkWeb 代理配置导致实际页面打不开。

MVP 应该至少做到：

- 如果 Aira App 代理开启，探测请求也应用同一个 `usingProxy` 配置。
- 代理配置变化时清空探测缓存。
- 探测日志记录 proxy enabled/applied 的布尔值，但不要记录代理用户名、密码或完整密钥信息。

开发前还需要用华为官方文档或实机确认：`@kit.NetworkKit` 的 `http.HttpRequestOptions.usingProxy` 与 ArkWeb `ProxyController.applyProxyOverride` 在当前 SDK/设备上的行为边界。若官方资料无法确认，应把这个问题发给华为支持，不要凭推断承诺完全一致。

## 地址栏提交流程

当前地址栏提交大致是同步流程：

```text
BrowserShellPage.openSubmittedAddress()
  -> BrowserAddressSubmissionCoordinator.resolveSubmission()
  -> NavigationController.resolveAddressInput()
  -> SearchEngineTemplateService.buildSearchUrl()
```

智能回退需要把“搜索 URL 构造”从纯同步改成可选异步：

```text
BrowserShellPage.openSubmittedAddress()
  -> await BrowserAddressSubmissionCoordinator.resolveSubmission()
    -> SearchEngineRoutingService.resolve()
      -> classify input
      -> if navigation: return normalized URL
      -> if search: choose effective search engine
      -> build search URL
  -> recordSubmittedSearchQuery()
  -> openResolvedUrl()
```

页面改动应该限制为：

- `openSubmittedAddress` 允许等待 Promise。
- 提交期间用 generation id 防止旧提交覆盖新提交。
- 继续调用现有 `applyAddressSubmitImmediateFeedback()` 和 `openResolvedUrl()`。
- toast 或 helperMessage 使用 service 返回的展示信息。

不要在页面里判断“Google 是否可用”。

### 路由伪代码

```ts
async resolve(input: SearchEngineRoutingInput): Promise<SearchEngineRoutingResult> {
  const submittedText = input.rawInput.trim();
  if (submittedText.length === 0) {
    return emptyResult();
  }
  if (looksLikeNavigation(submittedText)) {
    return navigateResult(normalizeUrl(submittedText));
  }

  const settings = input.searchEngineSettings;
  const primary = findEngine(settings.defaultSearchEngineId);
  const fallback = findEngine(settings.fallbackSearch.fallbackSearchEngineId);

  if (!settings.fallbackSearch.enabled || fallback === undefined || fallback.id === primary.id) {
    return searchResult(primary, false, '');
  }

  const snapshot = await availability.resolvePrimaryAvailability({
    engine: primary,
    maxWaitMs: input.maxProbeWaitMs,
    networkSignature: input.networkSignature,
    proxySignature: input.proxySignature
  });

  if (snapshot.reachability === 'reachable') {
    return searchResult(primary, false, '');
  }

  return searchResult(
    fallback,
    true,
    `${primary.name} 当前不可用，已用 ${fallback.name} 搜索。`
  );
}
```

### 搜索历史记录

`SearchQueryHistoryService.recordSubmittedSearch()` 应该记录实际使用的搜索引擎，而不是默认搜索引擎。

例如：

```text
默认搜索引擎：Google
备用搜索引擎：百度
本次因 Google 不可用回退到百度
搜索历史 searchEngineId：baidu
```

这样以后清理、统计、展示搜索历史时语义才一致。

## 设置页实现设计

### ViewModel

`SearchEngineManagementViewModel` 增加：

- `fallbackEnabled`
- `fallbackEngineName`
- `fallbackEngineAvailable`
- `canEnableFallback`
- `buildFallbackCandidateRows(...)`

设置页状态示例：

```ts
export interface SearchEngineManagementState {
  defaultEngineName: string;
  fallbackEnabled: boolean;
  fallbackEngineName: string;
  canEnableFallback: boolean;
  builtInEngines: SearchEngineRowView[];
  customEngines: SearchEngineRowView[];
  historySuggestionsEnabled: boolean;
  remoteSuggestionsEnabled: boolean;
  hasCustomEngines: boolean;
}
```

### Repository

`SearchEngineRepository` 增加：

- `updateSearchFallbackSettings(settings: SearchEngineFallbackSettings)`
- `setFallbackEngine(engineId: SearchEngineId)`
- `setSearchFallbackEnabled(enabled: boolean)`

归一化规则：

- `fallbackSearch.enabled` 缺失时默认为 `false`。
- `fallbackSearch.fallbackSearchEngineId` 缺失或不可用时，选择一个不同于 `defaultSearchEngineId` 的启用搜索引擎。
- 删除自定义搜索引擎时，如果它是备用搜索引擎，自动选择新的备用引擎或关闭回退。
- 默认搜索引擎变化后，如果与备用搜索引擎相同，自动选择新的备用引擎或关闭回退。

### 设置页面

`SearchSettingsScreen` 只渲染状态，不直接写业务逻辑：

- 新增 `onFallbackEnabledChange(enabled: boolean)`。
- 新增 `onOpenFallbackEngine()`。
- “备用搜索引擎”使用 `SettingsNavigationRow`。
- “智能搜索回退”使用 `SettingsSwitchRow`。

注意本仓库设置页规则：settings row 不在行内写第二行说明。解释文案放到组外 `SettingsFooterText`。

## 启动与生命周期

不要把探测放进启动 readiness 的阻塞链路。推荐：

```text
initializeBrowserRuntime()
  -> 初始化 preferences/search repository
  -> scheduleSearchEngineFallbackWarmup()
```

`scheduleSearchEngineFallbackWarmup()` 使用延迟任务，检查：

- 智能回退是否开启。
- 主/备搜索引擎是否有效且不同。
- 当前是否有默认网络。

满足条件才预热探测主搜索引擎。

网络监听可以参考现有：

- `WebNetworkAvailabilityService`
- `DownloadNetworkPolicyService`

但不要把目标站点可达性塞进这些服务。默认网络是否存在和 Google/Baidu 是否可达是两个不同概念。

## 失败与边界情况

| 场景 | 处理 |
| --- | --- |
| 主搜索引擎可用 | 使用主搜索引擎 |
| 主搜索引擎在短提交窗口内超时 | 结果不确定，继续使用主搜索引擎 |
| 主搜索引擎在较长后台探测中超时 | 使用备用搜索引擎 |
| 主搜索引擎 DNS/TLS/连接失败 | 使用备用搜索引擎 |
| 设备无默认网络 | 不做主备探测，走现有离线失败逻辑 |
| 备用搜索引擎也不可用 | 仍打开备用 URL，让现有 Web 错误页处理 |
| 主备搜索引擎相同 | 视为回退无效，使用主搜索引擎并提示设置异常 |
| 用户输入 URL | 不触发搜索回退 |
| 用户从搜索建议点选 URL 类结果 | 不触发搜索回退 |
| 用户从搜索建议点选搜索词 | 按本次搜索路由处理 |
| 私密模式 | 可以使用回退，但不持久化搜索词；探测不带搜索词 |
| App 代理变化 | 清空缓存并重新探测 |

## 验证计划

本功能是 HarmonyOS 原生网络 + ArkWeb 行为组合，验证要以实机为主。

### 本地构建

```bash
./scripts/build-aira-browser.sh
```

如果涉及可见 UI 或地址栏行为变更，构建成功后安装到手机：

```bash
./scripts/install-aira-browser.sh
```

### 手工验证矩阵

| 配置 | 网络状态 | 预期 |
| --- | --- | --- |
| 回退关闭，默认 Google | Google 可用 | 使用 Google |
| 回退关闭，默认 Google | Google 不可用 | 仍使用 Google，由 Web 错误页处理 |
| 回退开启，主 Google，备百度 | Google 可用 | 使用 Google |
| 回退开启，主 Google，备百度 | Google 不可用 | 使用百度，限频提示一次 |
| 回退开启，主 Google，备 Bing | Google 不可用 | 使用 Bing，限频提示一次 |
| 回退开启，输入 URL | 任意 | 直接打开 URL，不探测 |
| 回退开启，App 代理开启 | Google 仅代理可用 | 探测和实际 Web 加载结果一致 |
| 回退开启，App 代理关闭 | Google 不可用 | 回退到备用 |
| 私密模式 | Google 不可用 | 可回退，但不写搜索词历史 |

### 诊断日志

建议记录结构化诊断事件：

- `search_engine_probe_start`
- `search_engine_probe_result`
- `search_engine_route_primary`
- `search_engine_route_fallback`
- `search_engine_probe_cache_hit`
- `search_engine_probe_cache_expired`

日志中可以记录：

- engineId
- probeStatus
- responseCode
- durationMs
- networkSignature hash
- proxyEnabled
- proxyApplied
- fallbackApplied

不要记录：

- 搜索词全文
- 代理用户名/密码
- 用户身份 token
- 完整 URL 查询参数

## 分阶段实现建议

### Phase 1: 设置与持久化

- 扩展 `SearchEngineSettings`。
- `SearchEngineRepository` 支持 normalize/clone/persist 新字段。
- 搜索设置页新增开关和备用搜索引擎入口。
- 个性化同步继续同步搜索设置；确认新字段在快照中能被保留。

### Phase 2: 探测服务

- 新增 `SearchEngineAvailabilityProbeService`。
- 支持内存 TTL 缓存、短超时、代理配置、网络/代理签名失效。
- App 启动后和网络/代理变化后做后台预热。
- 只记录诊断，不改变搜索行为。

### Phase 3: 地址栏路由接入

- 新增 `SearchEngineRoutingService`。
- `BrowserAddressSubmissionCoordinator` 改为可异步返回 submission。
- `BrowserShellPage.ets` 只做最小事件转发和结果应用。
- 搜索历史记录实际使用的搜索引擎。

### Phase 4: 失败页兜底

- 对可识别的搜索结果失败页提供“用备用搜索重新搜索”动作。
- 失败页动作绕过探测，直接使用备用搜索引擎。

## 开放问题

- 华为官方文档是否确认 `@kit.NetworkKit` 的 `usingProxy` 能覆盖 Aira 当前支持的 HTTP/SOCKS 代理类型？如果不确认，需要向华为支持确认。
- ArkWeb `ProxyController.applyProxyOverride` 与原生 HTTP `usingProxy` 在认证代理、绕过列表、DNS 解析上的行为是否一致？
- Google 探测 URL 最终用 `https://www.google.com/generate_204` 还是搜索域轻量请求，需要实机验证误判率。
- 自定义搜索引擎是否允许用户配置探测 URL，还是 MVP 只用 homepage 探测。

## 推荐 MVP 范围

推荐 MVP 做到：

- 设置里可开关“智能搜索回退”。
- 默认搜索引擎作为主搜索引擎。
- 用户选择一个备用搜索引擎。
- 地址栏搜索词提交时，主引擎不可用则临时使用备用引擎。
- 探测不发送搜索词，有缓存，有短超时，有代理配置一致性处理。
- 自动回退时限频提示一次。

不要在 MVP 中做：

- 多级 fallback。
- 地区自动切换。
- 搜索建议源自动切换。
- 持久化动态可达性状态。
- 在页面文件中实现探测或主备决策。
