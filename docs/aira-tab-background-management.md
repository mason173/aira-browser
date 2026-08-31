# Aira 标签页后台管理实现分析

本文分析 Aira 当前自己的标签页后台管理、状态恢复和卡片截图链路。范围只看本仓库实现，不讨论产品改动。

参考文件主要包括：

- `AiraBrowser/entry/src/main/ets/common/models/BrowserModels.ets`
- `AiraBrowser/entry/src/main/ets/core/tabs/TabManager.ets`
- `AiraBrowser/entry/src/main/ets/core/tabs/TabRuntimeRegistry.ets`
- `AiraBrowser/entry/src/main/ets/core/web/WebTabRuntime.ets`
- `AiraBrowser/entry/src/main/ets/core/browser/BrowserSessionCoordinator.ets`
- `AiraBrowser/entry/src/main/ets/core/browser/BrowserTabBackgroundTypes.ets`
- `AiraBrowser/entry/src/main/ets/core/browser/BrowserTabBackgroundManagerCoordinator.ets`
- `AiraBrowser/entry/src/main/ets/core/browser/BrowserRuntimeLifecycleCoordinator.ets`
- `AiraBrowser/entry/src/main/ets/core/browser/BrowserMemoryPressureCoordinator.ets`
- `AiraBrowser/entry/src/main/ets/core/browser/BrowserTabPreviewCoordinator.ets`
- `AiraBrowser/entry/src/main/ets/services/web/BrowserTabPreviewCaptureService.ets`
- `AiraBrowser/entry/src/main/ets/services/web/BrowserTabPreviewCacheStore.ets`
- `AiraBrowser/entry/src/main/ets/core/browser/tabsOverview/*`
- `AiraBrowser/entry/src/main/ets/app/pages/BrowserShellPage.ets`

## 一句话结论

Aira 现在也不是“一个标签页永远等于一个活着的 WebView”。它大体分成四层：

1. `TabRecord / BrowserTabState`：标签页的逻辑记录。
2. `WebTabRuntimeRecord`：每个标签页对应的 ArkWeb controller/runtime 记录。
3. `HostedWebNodeController`：真正挂到 ArkUI 树上的 Web 节点。
4. `BrowserTabPreviewState`：标签页卡片和进出场动画用的截图资产。

也就是说，一个标签页可以还存在，但它的 Web 节点已经被释放；卡片截图也可以存在，但它和 WebState 恢复快照不是同一个东西。

2026-07-02 复核补充：对齐方案的第一阶段已经开始落地，新增了
`BrowserTabBackgroundTypes.ets` 和 `BrowserTabBackgroundManagerCoordinator.ets`。目前这个 manager 已经接管
`syncSessionCoordinatorState()` 的保护信号生成、retention sync 参数组装和统一 plan 日志，但仍是垂直切片：
实际释放/恢复仍复用既有 `BrowserRuntimeLifecycleCoordinator`、`BrowserSessionCoordinator`、
`BrowserMemoryPressureCoordinator`、`BrowserTabRecoveryCoordinator` 和 `BrowserWebHostCoordinator`。也就是说，
Aira 已经有了中心入口的雏形，但还没有完成 discard queue、`discardRuntime()` / `restoreRuntime()` 统一执行层。

## 标签页数据模型

核心模型在 `BrowserModels.ets` 和 `TabManager.ets`。

标签页运行状态包括：

- `active`
- `background`
- `background-hot`
- `background-warm`
- `suspended`
- `cold`
- `discarded`
- `loading`
- `error`
- `restoring`
- `crashed`

`BrowserTabState` 保存的不只是 url/title，还包括：

- `pendingUrl`
- `navigationHistory`
- `runtimeState`
- `lastError`
- `lastRestoreReason`
- `lastDiscardReason`
- `lastCrashReason`
- `lastLoadedAt`
- `webStatePath`
- `scrollOffsetY`
- `formDraft`
- `pageRuntimeSignals`
- `lastGoodUrl`
- `lastRestorableUrl`
- private/profile/data scope
- opener/open source/new-window 信息

持久化到数据库时使用 `TabRecord`。RDB 表是 `tab_sessions`，字段里也有 `runtime_state`、`web_state_path`、`scroll_offset_y`、`form_draft`、`page_runtime_signals` 等。

## Runtime 和 Web 节点

`TabRuntimeRegistry` 负责保存每个标签页的 runtime 记录。每个非首页 tab 可以有一个 `WebTabRuntimeRecord`，里面有：

- `controller: webview.WebviewController`
- `state`
- `currentUrl`
- `pendingUrl`
- `snapshotPath`
- `hasLiveController`
- `lastRestoreReason / lastDiscardReason / lastCrashReason`

这里要注意：有 `WebviewController` 对象，不代表这个 Web 节点已经挂在屏幕上。真正挂载由 `BrowserWebHostCoordinator` 和 `HostedWebNodeController` 管。

`HostedWebNodeController` 是 ArkUI `NodeController` 包了一层 Web。它可以：

- `attachWeb()`：把已有 FrameNode 挂回 ArkUI 树。
- `detachWeb()`：把 root node 置空，从 UI 树脱离。
- `dispose()`：释放 builder/root/controller 关联。

页面里的挂载点主要有两类：

- 前台 Web：`buildActiveHostedWebNodeContainer()`
- 隐藏后台 Web：`buildBackgroundTabPreviewHost()`

隐藏后台 Web 会被放到一个 0.01 透明度、不可点击的 `NodeContainer` 里，用于后台打开标签页时预热加载和截图。

## 后台保活和冷却策略

Aira 的后台管理核心过去不是一个单独的 `TabDiscardManager`，而是几层 coordinator 组合出来的：

- `BrowserTabBackgroundManagerCoordinator`
- `BrowserSessionCoordinator`
- `BrowserRuntimeLifecycleCoordinator`
- `BrowserMemoryPressureCoordinator`
- `WebRuntimePoolPolicy`
- `BrowserRuntimeTransactionSignalService`

第一阶段之后，`BrowserTabBackgroundManagerCoordinator` 是新的入口 owner：它消费保护信号输入，调用旧
runtime lifecycle sync，并把 `WebRuntimeRetentionPlan` 转成面向后台管理的 plan 摘要。旧模块仍然执行主要行为，
还没有降级成纯能力模块。

默认保活配置在 `PreferencesRepository.ets`：

- balanced：最多挂载 `3` 个 runtime
- hot 后台标签页：`1` 个
- warm 后台标签页：`1` 个
- hot 保留约 `3` 分钟
- warm 保留约 `12` 分钟
- stale 约 `20` 分钟

页面里还有 30 秒一次的冷却 tick：`RUNTIME_COOLING_TICK_MS`。它会触发 `syncSessionCoordinatorState()`。

冷却流程大致是：

1. 页面收集当前 tabs、activeTabId、下载任务、显式保护原因，并转发给 `BrowserTabBackgroundManagerCoordinator`。
2. `BrowserTabBackgroundManagerCoordinator` 通过 `BrowserRuntimeTransactionSignalService` 生成保护原因。
3. `BrowserTabBackgroundManagerCoordinator` 调用 `BrowserRuntimeLifecycleCoordinator.runSessionSync()`。
4. `BrowserSessionCoordinator.buildRuntimeRetentionPlan()` 调到 `BrowserMemoryPressureCoordinator`。
5. `BrowserMemoryPressureCoordinator` 按最近活跃时间、页面复杂度、保护信号、保活预算排序。
6. 生成 mounted/hot/warm/cold/discarded retention plan，并由 background manager 转成统一 background plan 摘要。
7. `BrowserRuntimeLifecycleCoordinator.applySessionSyncResult()` 对被冷却的后台 tab 调 `persistCoolingRuntimeSnapshot()`。
8. `persistMountedTabSnapshot()` 会先保存 WebState，再按需要释放隐藏 Web 节点。

保护信号包括：

- 显式文件选择、权限、下载等原因
- 页面探测出的 media/auth/payment/form
- 表单草稿
- loading/restoring 短保护窗口
- error/crashed 短保护窗口

所以 Aira 的思路是“根据策略逐步冷却后台 runtime”，不是所有后台页面一直活着。

## WebState 快照

WebState 快照不是标签页卡片图片。

WebState 走的是：

- `controller.serializeWebState()`
- `WebStateSnapshotStore.saveSnapshot()`
- 存到 cache 目录 `web-tab-snapshots`
- 恢复时用 `controller.restoreWebState(bytes)`

它用于恢复 ArkWeb 页面状态。它的产物是二进制 `.bin`，不是卡片 JPEG，也不是进出场动画图片。

当前还有一个重要现象：冷启动恢复时，`BrowserRestoreCoordinator.buildColdRestoreRecord()` 会把非首页 tab 的 `webStatePath` 清空，并把恢复类型设成 reload 路径。所以冷启动看到卡片有图，主要证明的是卡片预览 JPEG 恢复成功，不代表 WebState 一定被拿来恢复页面。

## 标签页卡片截图链路

卡片截图走另一套：

- `BrowserTabPreviewCoordinator`
- `BrowserTabPreviewCaptureService`
- `BrowserTabPreviewCacheStore`
- `BrowserTabsOverviewSnapshotPipelineCoordinator`
- `BrowserTabsOverviewThumbnailStore`
- `BrowserTabOverviewCard`

预览缓存是 JPEG，目录是：

`cacheDir/tab-preview-images/<scopeId>/`

每个 tab 会保存类似：

- `<tabId>-shared-<timestamp>.jpg`
- `<tabId>-shared-meta.json`

metadata 会记录图片宽高、截图来源、sourceRect。

截图来源支持很多种：

- `webPageSnapshot`
- ArkUI component snapshot
- window snapshot
- surface snapshot
- transformed surface snapshot
- visible tab surface

但现在从网页点标签页按钮进入标签页管理页时，主路径不是等 `webPageSnapshot()`。它走的是更直接的 entry snapshot：

1. `openTabsOverview()` 调 `captureFreshActiveTabPreviewForOverview()`。
2. 通过 `uiContext.getComponentSnapshot().get(buildBrowserTabPreviewVisibleSurfaceSnapshotId(tabId), ...)` 先截当前可见 tab surface。
3. `BrowserTabsOverviewSnapshotPipelineCoordinator` 立刻把这个 PixelMap 放进 entry session。
4. 同一张图会马上用于缩小动画。
5. 同时通过 `persistImmediateSharedSnapshot()` 写入 `BrowserTabPreviewCoordinator` 和 JPEG cache。
6. 卡片渲染和动画共用这套 shared snapshot 状态。
7. 截图成功后才 `playTabsOverviewEntryAnimation()`。

这就是这次白屏问题修好后，运动过程和卡片都能有图的关键：动画不再靠一个空 overlay 硬跑，而是先拿到 fresh PixelMap，再开始进场。

## 卡片渲染链路

标签页管理页里的卡片由 `BrowserTabsSheet` 派生数据，再交给 `BrowserTabOverviewCard`。

图片来源优先级大概是：

1. 当前 entry session 的 fresh PixelMap。
2. `BrowserTabPreviewCoordinator` 里的 shared snapshot URI。
3. `BrowserTabsOverviewThumbnailStore` 中按 tabId 缓存的 URI。
4. 如果没有图，则显示首页占位或 pending skeleton。

`BrowserTabsOverviewThumbnailStore` 有一个关键保护：更旧的 capture 时间不能覆盖更新的缩略图。这样可以避免异步旧图晚回来，把新图覆盖掉。

## 后台打开标签页预览

后台打开新 tab 时，`TabManager.createBackgroundTab()` 默认把它设成：

- 有 URL：`suspended`
- 无 URL：首页类 `background`

之后 `BrowserBackgroundTabPreviewCoordinator` 会尝试为后台 tab 做预览：

1. 判断 tab 不是当前 active、不是 home、URL 是 http/https、还没有预览图。
2. `markBackgroundTabHot()` 把它加入隐藏 Web slot。
3. `BrowserWebHostCoordinator.syncPreview()` 创建/挂载隐藏 Web。
4. controller attached 后加载 URL。
5. 定时截图：
   - 初始截图延迟约 `360ms`
   - 稳定截图约 `1200ms`
   - page ready 后约 `64ms`
   - 总超时约 `5200ms`
6. 截图成功或超时后结束预览任务。

隐藏 Web slot 会受到数量限制，溢出的后台 hot tab 会被 dispose。

## 冷启动恢复

冷启动链路在 `restoreSavedTabs()`：

1. 从 `sharedTabSessionRepository.refresh()` 读取 `tab_sessions`。
2. `BrowserTabSessionRestoreService.prepareRecordsForColdRestore()` 过滤私密/临时/自动关闭标签页。
3. `BrowserRestoreCoordinator.buildColdRestoreResolution()` 生成冷启动恢复记录和 trace。
4. `TabManager.restoreTabs()` 还原 tab 列表和 activeTabId。
5. `restorePersistedTabPreviews()` 从 JPEG cache 恢复卡片图。
6. `syncActiveTabToView()` 让 active tab 进入 Web 恢复或加载流程。

所以冷启动“卡片上有图”的来源主要是 `BrowserTabPreviewCacheStore.buildSharedSnapshotRestoreIndex()`，不是 WebView 还活着。

## 和 Huawei 思路的主要差异

对照已经整理过的 Huawei 文档 `docs/huawei-tab-background-management.md`，Aira 目前有几个明显差异：

1. Huawei 更像是成熟的中心化 `TabDiscardManagerImpl`：监听内存、窗口、tab 切换，然后统一 discard/restore。Aira
   已新增 `BrowserTabBackgroundManagerCoordinator` 作为入口雏形，但 discard queue 和统一 runtime service 还没有完成。
2. Huawei 的 tab snapshot 更像单一权威字段：tab controller 的 snapshot 直接给卡片和切换动画用。Aira 之前存在 WebState、preview cache、entry PixelMap、thumbnail store 多套资产，出 bug 时容易一边有图、一边白屏。
3. Huawei 有系统 memory level 驱动。Aira 当前没看到直接接入类似 `application.onMemoryLevel` 的真实系统内存回调，更多是定时和配置驱动的 retention。
4. Huawei 的 discard/restore 原语更清晰。Aira 的 detach/dispose/cold/suspended/discarded、snapshot restore、reload fallback 分散在 runtime lifecycle、web host、recovery、preview pipeline 里。
5. Aira 现在进入标签页管理页的 fresh screenshot 链路已经更接近 Huawei 的稳定做法：先拿当前可见组件截图，再用同一张图驱动动画和卡片。

## 当前架构的风险点

最容易出问题的是这些地方：

- 卡片图、动画图、WebState 是三套东西，任何一套异步失败都可能造成“冷启动有图，但进场动画没图”这种错觉。
- runtime 冷却和截图预览不是同一个 coordinator 管，状态同步顺序错了就可能出现 Web 节点释放太早。
- `BrowserShellPage.ets` 仍然参与很多调度：打开 overview、截图、锁 snapshot、恢复 persisted preview、后台 preview host 等都在这里串起来，可读性和可验证性偏重。
- `webPageSnapshot()`、component snapshot、window snapshot、surface snapshot 都存在，调用链复杂；如果入口没固定住，容易不同场景走到不同截图 API。
- 冷启动页面恢复现在偏 reload，卡片恢复偏 JPEG cache。用户看到“卡片有图”不等于页面状态恢复链路是同一套。

## 值得保留和继续对齐的方向

现在已经比较正确的方向：

- 标签模型和 Web runtime 分离，不强求所有 tab live。
- 卡片进场使用 fresh PixelMap，不允许无图动画硬跑。
- 卡片和动画尽量用同一张 shared snapshot。
- 缩略图 store 有时间戳保护，旧图不能覆盖新图。
- 后台 tab 可以用隐藏 Web slot 预热和截图，而不是必须切到前台。

后续如果继续对齐 Huawei，优先方向应该是：

1. 继续把 tab discard/restore 收拢到 `BrowserTabBackgroundManagerCoordinator`，并让旧模块逐步降级为能力模块。
2. 把“标签卡片截图资产”定义成单一权威来源，减少 entry PixelMap、preview cache、thumbnail store 之间的分歧。
3. 明确每个入口到底用哪种截图 API，尤其是点标签页按钮时固定走 fresh visible snapshot。
4. 引入或确认 HarmonyOS 系统内存等级回调后，再把真实内存压力接进后台回收策略。
5. 继续把 `BrowserShellPage.ets` 里与 tab overview 截图、几何、后台预览相关的调度往 non-page coordinator 收。
