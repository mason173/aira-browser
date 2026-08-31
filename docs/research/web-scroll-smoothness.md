# 网页加载后与持续滑动流畅度调研

更新日期：2026-08-29

## 结论

网页滑动是否流畅，关键不是“安装了多少个脚本”，而是用户拖动或抛滑期间，哪些工作同时占用了 ArkWeb 主线程、应用主线程、ArkUI 重渲染路径或 GPU 帧预算。

几十个已安装脚本不等于几十个脚本会在每个页面执行。真正需要测量的是：当前 URL 匹配并启用的脚本数量、`run-at` 时机、单次执行耗时、DOM/样式/布局工作、持续监听器或 `MutationObserver`、JSBridge 回调频率，以及这些工作是否与第一下滑动重叠。一个 100 ms 脚本可能比 20 个各 1 ms 的脚本更差；20 个顺序执行且每个都触发布局的脚本也可能累积成明显卡顿。

当前最合理的下一步是诊断，而不是继续凭感觉改调度：对同一页面录制“导航后立即滑动”和“等待 2-3 秒再滑动”的 ArkWeb/Frame/ArkUI/Time 轨迹，并做脚本全开/全关对照。只有定位到稳定、占比明显且由 Aira 所有的任务，才值得继续优化。

## 证据边界

本文把结论分成三类，避免把平台资料直接当成 Aira 已确诊结果：

- **华为确认事实**：来自华为官方文档、DevEco Studio 官方 Profiler/SDK 文档。
- **Web 平台事实**：来自 Chrome/Chromium、web.dev 或 W3C 的一手资料。
- **Aira 工程推论**：把上述事实映射到 Aira 的浏览器壳、用户脚本和页面结束任务；必须通过真机轨迹验证。

本文没有进行代码修改、构建、安装、设备操作或截图，也没有取得 Aira 的新一轮帧轨迹，因此不能声称当前瓶颈已经被证明。

## 一、华为确认事实

### 1. 需要同时看 ArkWeb、应用和合成帧

华为的 [Web 帧率问题分析](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/web-frame-rate-analysis) 指导使用 DevEco Profiler 的 `ArkWeb`、`Frame`、`ArkUI` 和 `Time` 模板关联分析。滚动区间可以通过 `GestureScrollBegin`、`GestureScrollEnd`、`GestureFlingStart` 等标记定位；VSync 附近出现 `H:RosenWeb=0` 表示 ArkWeb 对应帧没有准备好。

这套方法的重要含义是：只看一段 ArkTS 日志耗时，不能判断网页是否顺滑。需要把 ArkWeb 帧、应用主线程、ArkUI 重渲染和最终帧提交放在同一时间轴上。

### 2. 华为列出的典型竞争来源

同一份华为分析资料列出了可在轨迹中区分的几类原因：

- 页面加载后立即创建隐藏或离线 Web 组件，会阻塞应用主线程，可能与第一次滑动重叠。
- 高频 JSBridge 回调会让 Web 与应用侧反复切换；页面 `onscroll` 逐帧上报尤其危险。
- ArkUI `onScroll` 中的同步重活可在轨迹中表现为 `ExecuteJs`。
- 过于宽泛或频繁的 `@State` 更新可表现为 `JSView:ExecuteRerender`。
- WebGL、模糊、重绘和复杂 GPU 内容可能在应用主线程并不繁忙时仍造成掉帧。

因此，“后台任务是异步的”不能证明它没有竞争。异步任务的回调、解析、状态写入、DOM 注入、存储或 GPU 工作仍可能回到关键线程或共享有限资源。

### 3. ArkWeb 抛滑丢帧有官方事件

华为 `HiAppEvent` 从 API 23 起提供 `SCROLL_ARKWEB_FLING_JANK`，即 ArkWeb 抛滑丢帧事件。官方 [订阅 ArkWeb 抛滑丢帧事件](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hiappevent-watcher-scroll-arkweb-fling-jank) 示例通过 `addWatcher()` 获取抛滑开始时间、持续时间、`web_id` 和最大应用帧耗时；[`hiAppEvent` API 参考](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-hiviewdfx-hiappevent) 也声明了该事件常量。

这适合做低频、聚合的线上诊断，但不应在每个滚动样本里写大量日志或同步存储，否则诊断本身会污染热路径。

## 二、Web 平台确认事实

### 1. 主线程长任务会直接增加输入等待

Chrome/web.dev 的 [Optimize long tasks](https://web.dev/articles/optimize-long-tasks) 将占用主线程超过 50 ms 的任务视为长任务。任务运行时，浏览器不能及时处理同一主线程上的输入、脚本和渲染工作；非关键工作应拆分，并在批次之间让出执行机会。

W3C [Long Tasks API](https://www.w3.org/TR/longtasks-1/) 提供了长任务观测与归因的标准基础。它适合回答“是否有超过 50 ms 的主线程块”，但对一帧内多个较短脚本、样式和布局累积造成的卡顿归因较弱。

### 2. Long Animation Frames 更适合定位掉帧归因

Chrome 的 [Long Animation Frames API](https://developer.chrome.com/docs/web-platform/long-animation-frames) 把超过 50 ms 的渲染更新记录为长动画帧，并提供 `blockingDuration`、脚本归因、样式/布局和交互时间信息。它比只看长任务更接近“哪段脚本或渲染工作挡住了这一帧”。

页面侧可以在一个短、受控的诊断窗口内使用 `PerformanceObserver` 观测 `long-animation-frame`，但应限制持续时间、记录数量和字段，避免把完整 URL、脚本文本或用户数据写入日志。

### 3. 第一滑动要在页面仍加载时测试

web.dev 的 [Interaction to Next Paint](https://web.dev/articles/inp) 将交互延迟拆成输入延迟、事件处理时间和呈现延迟，并明确建议在页面加载过程中测试交互。页面刚显示时的第一次滑动，可能与页面自身 hydration、第三方脚本、用户脚本、样式计算、图片解码和应用侧 page-end 工作同时发生；等待几秒再测会漏掉这个问题。

INP 本身主要针对离散交互，不直接把连续滚动完整压缩成一个指标。因此 Aira 应把 INP/事件时间作为交互延迟辅助证据，同时以帧时间、丢帧和抛滑事件作为滚动主指标。

### 4. 阻塞型触摸/滚轮监听器会推迟滚动开始

Chrome 的 [Use passive listeners to improve scrolling performance](https://developer.chrome.com/docs/lighthouse/best-practices/uses-passive-event-listeners) 说明：对于可能调用 `preventDefault()` 的 `touchstart`、`touchmove` 或 `wheel` 监听器，浏览器需要等待处理器结束才能确认是否可以滚动。明确不取消滚动的监听器使用 `{ passive: true }`，浏览器就不必等待。

这只适用于 Aira 自己注入或维护的监听器，而且必须确认监听器从不需要 `preventDefault()`。浏览器壳不应擅自改写第三方网页监听器语义。

## 三、用户脚本数量与实际开销

用户脚本应按以下漏斗分析，而不是只看安装数：

1. **已安装**：只产生元数据加载、匹配或管理成本，不代表会执行。
2. **已启用**：禁用脚本不应生成页面执行任务。
3. **URL 匹配**：只有正向规则命中且排除规则未命中的脚本才应进入当前页面计划。
4. **执行时机**：`document-start` 影响关键解析/渲染期；`document-end`、`document-idle` 仍可能与第一次滑动重叠。
5. **一次性成本**：脚本编译、执行、DOM 查询、样式写入、同步布局、依赖拼接。
6. **持续成本**：滚动/触摸监听器、定时器、`requestAnimationFrame`、`MutationObserver`、网络回调、GM/JSBridge 调用。
7. **跨边界成本**：native bridge 验证、网络请求、GM 存储、ArkUI 状态写入和报告持久化。

所以脚本数只能作为“潜在上限”的粗略信号。应记录每次导航的 `installed/enabled/matched/executed` 数量，并按阶段统计总耗时、最长脚本、桥接回调数量和页面结束后的尾部耗时。不要记录脚本正文或敏感页面数据。

## 四、Aira 最值得验证的竞争窗口

以下均为 **Aira 工程推论**，不是已确认根因：

### 当前实现基线

Aira 已经有一层正确的保护：`BrowserWebScrollInteractionCoordinator` 只在检测到真实 Web Move 后启动滚动安静窗口，默认持续 2.2 秒，并在连续移动时最多每 240 ms 延长一次。页面标题、favicon 的 ArkUI 发布、导航状态、跟踪保护状态、页面主题采样以及媒体 DOM/深探测中的一部分会等待这个窗口结束。

但这层保护有两个边界：触摸按下本身不会启动窗口；已经在第一次 Move 之前开始的任务也不会被取消。当前页面完成链路会立即进入 cosmetic filtering、手动元素隐藏、favicon/manifest 发现和媒体入口，而用户脚本在 `load` 后经过两次 `requestAnimationFrame` 发出 `post_paint` 信号。这正是“网页刚能看见，用户马上滑”的潜在竞争区间。

此前保留的真机诊断给出了一个量级参考：在测量页面上，20 个启用脚本中只有匹配当前 URL 的脚本进入执行；匹配脚本本体合计约 50-78 ms，但完整 post-paint 注入链路约 285-403 ms。它证明“脚本数”和“脚本本体耗时”都不能代表整个尾部窗口，但没有帧轨迹，因此仍不能断言这 285-403 ms 造成了掉帧。

本地代码证据入口：

- `core/browser/BrowserWebScrollInteractionCoordinator.ets`：Move 识别、2.2 秒安静窗口和逐次刷新。
- `core/browser/BrowserWebPageFeatureEffectsCoordinator.ets`：page-end/load-finished 的 cosmetic、手动隐藏、favicon 和媒体入口。
- `services/userscripts/UserScriptInjectionService.ets` 与 `core/userscripts/UserScriptRuntimeCoordinator.ets`：双 RAF 的 `post_paint` 信号、脚本执行、报告读取与状态持久化。
- `services/adblock/AdBlockCosmeticRuntimeScriptService.ets`：`[class],[id]` 候选扫描、分批选择器处理、几何读取和 MutationObserver。
- `services/siteicons/SiteIconCurrentPageDiscoveryService.ets` 与 `SiteIconService.ets`：link/manifest 扫描、250/650 ms 轮询、候选抓取/解码/缓存。
- `services/media/MediaProbePolicyService.ets`：媒体 page-end 探测需要完整服务模式且视频接管开启；深探测再经过安静窗口调度。

### 1. 页面结束后的用户脚本执行

如果 `document-end` / `document-idle` 脚本在页面可见后顺序通过 `runJavaScript()` 执行，脚本本体、DOM 工作和执行报告读取都可能与用户第一下滑动重叠。脚本本体只有几十毫秒，也不代表完整注入流程只有几十毫秒；多次 Web/Native 往返、队列等待、报告解析和存储会拉长重叠窗口。

### 2. 广告拦截的 cosmetic DOM 处理

选择器扫描、几何读取、样式写入、节点移除和 `MutationObserver` 都可能造成样式/布局/绘制工作。延迟它可能出现广告闪现或改变站点行为，因此应先用 LoAF/Profiler 证明其占比，再考虑改变时机。

### 3. favicon 与 manifest 发现

页面端扫描 `<link>`、抓取/解析 manifest、轮询、图标解码和持久化都不是首轮滚动所必需。如果轨迹证明它与第一滑动重叠，把发现和存储移到滚动安静窗口通常比改变脚本语义风险低。

### 4. JSBridge 与 ArkUI 状态回写

页面滚动、DOM 变化或脚本回调如果逐次跨桥并写多个 `@State`，即使每次很短，也可能以高频小任务和重渲染形式占满帧间空隙。应统计回调频率、每类总耗时和引发的重渲染，而不是只查是否存在某一个大于 50 ms 的任务。

代码复核发现两个可以不改第三方页面语义的 Aira 自有候选：

- `AdBlockInteractionGuardRuntimeScriptService` 在广告拦截启用时为每个文档注册 `pointerdown`、`touchstart`、`touchend`、`pointerup` 和 `click` 五个捕获监听器，统一声明为 `passive: false`。其中只有 `click` 分支调用 `preventDefault()`；触摸和指针分支可以按事件类型改为 passive。procedural cosmetic runtime 之后还会在 `document` 上注册另一套 `touchstart`、`touchend`、`click` 保护器；这套重复监听可以继续评估，但它会在隐藏点击区内取消触摸事件，不能未经回归验证直接删除。
- `BrowserWebLocalScrollSignalService` 对普通根页面滚动快速返回，但对内部滚动容器会按 `requestAnimationFrame` 合并后跨 JSBridge 上报，最坏接近每显示帧一次。native 侧滚动安静窗口本身最多每 240 ms 刷新一次，因此这条桥可以在保留累计 `deltaY` 和最新 `scrollTop` 的前提下限频；代价是内嵌滚动容器驱动的工具栏响应会略微降低采样频率，需要保留末次上报。

### 5. 功能探测、同步和后台维护

媒体深探测、页面资源扫描、大型书签合并、索引重建、远程刷新或隐藏 Web 预热，如果在前台浏览时运行，可能竞争 CPU、内存、应用主线程或 GPU。正确的边界是按功能启用、取消过期工作、分块让出，并在真实滚动期间暂停非关键提交，而不是笼统地把所有工作称为“后台”。

Aira 当前的自动同步不是首滑的第一嫌疑：History/个性化前台任务通常延后约 5 秒，书签和周期任务通常延后约 30 秒或更久，并不随每个网页 page-end 启动。它们仍可能影响长时间浏览中的某一次滚动，所以应保留在 Profiler 时间轴中，而不是先靠猜测关闭。

## 五、建议的诊断闭环

### 测试矩阵

固定同一设备、同一网页、相近网络与缓存状态，每组至少重复 3 次：

| 变量 | A 组 | B 组 | 要回答的问题 |
|---|---|---|---|
| 滑动时机 | 页面可见后立即拖动/抛滑 | 等待 2-3 秒再滑动 | 是否存在首轮加载尾部竞争 |
| 用户脚本 | 全部启用 | 全部禁用 | 当前页面匹配脚本是否有显著贡献 |
| 服务模式 | 完整模式 | 基础模式 | cosmetic/媒体/附加探测是否有显著贡献 |
| Aira 任务 | 正常 | 仅通过诊断标记识别，不先改语义 | 哪个 Aira owner 与掉帧重叠 |

不要用不同网页或一次测试直接比较，否则页面自身脚本、广告、网络和缓存差异会淹没 Aira 影响。

### 轨迹和指标

1. 在导航前启动 DevEco Profiler，覆盖 `ArkWeb`、`Frame`、`ArkUI`、`Time`。
2. 标记页面可见、page-end/post-paint、用户第一次 Move、`GestureScrollBegin`、`GestureFlingStart`、`GestureScrollEnd`。
3. 对齐 `H:RosenWeb=0`、应用帧耗时、ArkUI `ExecuteJs` / `ExecuteRerender` 和 Aira 任务区间。
4. 订阅聚合的 `SCROLL_ARKWEB_FLING_JANK`，以 `web_id` 关联当前页面运行实例。
5. 页面侧只在短诊断窗口采集 `long-animation-frame` 和 `longtask`；记录 duration、blocking duration 和归因类别，不保存正文或完整敏感 URL。
6. Aira 侧对以下 owner 增加成对、低开销的 HiTrace：用户脚本计划/执行/报告、cosmetic 注入、favicon/manifest 发现、JSBridge 分类回调、ArkUI 滚动处理、媒体探测和同步提交。

建议输出的聚合字段：

- 导航到第一次 Move 的时间。
- 首次 Move 前后 2 秒的总帧数、慢帧/丢帧数、最大帧耗时。
- `installed/enabled/matched/executed` 脚本数。
- 各 Aira owner 的调用次数、总耗时、最大耗时和与滚动区间的重叠时间。
- 长任务和 LoAF 数量、总 blocking duration、最重的归因类别。
- JSBridge 每类回调数量及是否触发 ArkUI 状态更新或存储。

### 判定标准

- **值得优化**：同一 owner 在多次立即滑动中稳定与慢帧重叠；关闭对应功能后帧指标明显改善；工作属于 Aira 且不是页面正确性的必要时序。
- **证据不足**：只有一条 50-100 ms 日志，但没有与慢帧重叠；或页面自身 LoAF/GPU 工作占主导。
- **停止继续改**：候选任务占比很小、对照无稳定改善，或必须改变第三方页面/用户脚本语义才能获得很小收益。

## 六、优化边界

### 低风险候选：有证据后优先做

- 先修正 Aira 自己的 document-start 广告交互保护监听器：不调用 `preventDefault()` 的触摸/指针事件使用 passive。不要改写网站自己的监听器。
- 将 favicon DOM/manifest 发现、图标摄取和存储放入“真实 Web Move 触发、抛滑结束后延长”的安静窗口。
- 用户脚本本体和报告读取保持原有顺序；将 runtime-state 的 `Preferences.flushSync()` 换成有序、可等待的异步 `flush()`，或在保持内存状态立即可见的前提下合并非关键诊断落盘。页面跳转后取消过期结果。
- 缓存不变的脚本匹配计划、生成包装和桥接配置，避免普通 tab/Chrome 状态同步导致重复准备。
- 对内嵌滚动容器的 JSBridge 回调做累计合并和限频；滚动期间只更新必要的轻量内存状态，稍后批量持久化。
- 仅在功能确实启用时运行媒体、翻译、资源或个性化探测，并在定时器执行前重新检查 tab/URL/可见性。
- 将 CPU 密集的原生解析、合并或索引工作分块/移出主线程；结果回写保持小粒度且避免全页 `@State` 重渲染。

### 中风险：必须先证明收益

- 延迟或分批执行 `document-end` / `document-idle` 用户脚本。
- 改变多个用户脚本的执行顺序或并行度。
- 延迟 cosmetic filtering 或手动隐藏规则。
- 更改脚本/页面注入的事件监听器、observer 或布局读写顺序。

这些动作可能破坏脚本之间的依赖、页面初始化时序、反闪烁效果或站点功能，需要按具体脚本和站点做兼容性矩阵。

### 高风险或不建议作为默认优化

- 阻止、改写或延迟网站正常重定向。
- 在滚动时停止 ArkWeb 加载、全局暂停页面计时器或禁止页面动画。
- 自动改写第三方页面的触摸/滚轮监听器为 passive。
- 默认启用会弱化 iframe、媒体或动画的实验“顺滑模式”。
- 为了“预热”在页面加载后立即创建隐藏/离线 Web；华为资料明确显示这类工作本身可能阻塞第一次滑动，并带来显著内存/算力成本。

## 七、对 Aira 的建议顺序

1. 保留现有滚动安静窗口和用户脚本诊断，不改用户脚本本体、执行顺序或网站重定向。
2. 第一批只考虑代码语义清楚的自有工作：document-start 广告保护监听器 passive、favicon 发现延后、用户脚本 runtime-state 异步落盘。
3. 第二批才考虑重复 cosmetic 保护器收敛和内嵌滚动容器 JSBridge 限频；前者要验证隐藏点击区仍被保护，后者必须保留累计位移、最新位置和末次上报。
4. cosmetic 全 DOM 候选扫描、MutationObserver 调度和用户脚本执行时机都先不动；它们可能收益更大，但兼容性风险也更高。
5. 若第一批没有稳定体感改善，停止继续做高风险壳层干预；完整 Profiler 只在以后确实需要定位具体站点时再投入。

## 来源

### 华为官方

- [Web 帧率问题分析](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/web-frame-rate-analysis)
- [订阅 ArkWeb 抛滑丢帧事件](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hiappevent-watcher-scroll-arkweb-fling-jank)
- [`@ohos.hiviewdfx.hiAppEvent` API 参考](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-hiviewdfx-hiappevent)

### Web 平台一手资料

- [Optimize long tasks, web.dev](https://web.dev/articles/optimize-long-tasks)
- [Long Animation Frames API, Chrome for Developers](https://developer.chrome.com/docs/web-platform/long-animation-frames)
- [Interaction to Next Paint, web.dev](https://web.dev/articles/inp)
- [Use passive listeners to improve scrolling performance, Chrome for Developers](https://developer.chrome.com/docs/lighthouse/best-practices/uses-passive-event-listeners)
- [Long Tasks API, W3C](https://www.w3.org/TR/longtasks-1/)
- [Event Timing API, W3C](https://w3c.github.io/event-timing/)

## 调研限制

- 华为文档站内容依赖动态加载；本文还用本机 DevEco Studio 官方 SDK/API 文档交叉确认了 `SCROLL_ARKWEB_FLING_JANK` 为 API 23+ 的 ArkWeb 抛滑丢帧事件。
- DevEco Knowledge 仅作为华为资料检索辅助，不作为独立权威来源；最终事实以上述华为官方页面和 SDK 声明为准。
- 本文没有新的真机轨迹，所有 Aira 映射仍是待验证工程推论。
