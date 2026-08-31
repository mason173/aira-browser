# Aira Web 长按上下文菜单实现调研（历史快照）

日期：2026-07-05
范围：记录 2026-07-05 当时 HarmonyOS NEXT / ArkTS / ArkUI / ArkWeb 网页长按菜单的实现，已归档，不代表当前架构。

> 归档说明（2026-07-20）：本文主体中的 `BrowserDirectChildWindowWebHost`、
> `WebContextMenuPositionCoordinator`、透明锚点和 `bindContextMenu` 链路已被后续重构删除，普通网页弹窗也不得恢复
> direct-child 路径。当前实现从 Hosted Web 事件进入 `WebLinkContextMenuCoordinator`，由它解析菜单与 viewport
> geometry，再交给 `WebContextMenuOverlay` 渲染和测量；userscript 命令统一通过
> `UserScriptRuntimeCoordinator` 获取并执行。本文剩余行号和旧模块名仅用于历史追溯。

相关对照文档：[华为浏览器 Web 长按菜单定位调研](./huawei-browser-longpress-context-menu-research.md)

## 结论先行

Aira 当前不是直接展示 ArkWeb 的默认长按菜单，而是通过 ArkWeb 的 `onContextMenuShow` 事件接管长按，然后在 ArkUI 层自己构造菜单状态和动作列表。菜单最终显示方式是：

```text
ArkWeb onContextMenuShow
  -> BrowserShellPage.handleWebContextMenuShow
  -> WebLinkContextMenuCoordinator.buildState
  -> 保存 WebContextMenuParam.x/y
  -> 关闭 ArkWeb result
  -> 下一 tick 打开 ArkUI bindContextMenu
  -> 在 2vp 透明锚点上挂 Menu / MenuItem
```

这条链路里，Aira 已经用 `WebContextMenuPositionCoordinator` 把 ArkWeb 坐标转换为根容器内坐标，但最终菜单位置仍由 ArkUI `bindContextMenu` 根据一个合成透明锚点二次决定。结合之前华为浏览器调研，Aira 坐标“会飘”的最大差异点就在这里：华为更像是自绘菜单并直接控制最终 `x/y`，Aira 是把透明锚点放到计算位置，再让系统菜单按自己的锚点规则布局。

## 代码证据地图

| 模块 | 位置 | 作用 |
| --- | --- | --- |
| ArkWeb 入口 | `AiraBrowser/entry/src/main/ets/core/web/HostedWebNode.ets:1032` | Web 组件收到 `onContextMenuShow` 后转发到 callbacks。 |
| 子窗口 Web 入口 | `AiraBrowser/entry/src/main/ets/app/components/browser/BrowserDirectChildWindowWebHost.ets:261` | 直接子窗口 Web 也把长按菜单事件转发给同一套 callbacks。 |
| 回调保护层 | `AiraBrowser/entry/src/main/ets/core/browser/BrowserWebEventHostCoordinator.ets:132` | 用 `runBoolean` 包住 handler，异常时回退 `false`。 |
| 页面接线 | `AiraBrowser/entry/src/main/ets/app/pages/BrowserShellPage.ets:23690` | 把 hosted web callback 接到 `handleWebContextMenuShow`。 |
| 菜单状态构造 | `AiraBrowser/entry/src/main/ets/core/web/WebLinkContextMenuCoordinator.ets:81` | 判断图片/链接，生成 `WebLinkContextMenuState`。 |
| 坐标转换 | `AiraBrowser/entry/src/main/ets/core/web/WebContextMenuPositionCoordinator.ets:20` | 把 ArkWeb 点转换成根容器内 press/anchor 坐标。 |
| Overlay / Menu | `AiraBrowser/entry/src/main/ets/app/pages/BrowserShellPage.ets:16088` | 全屏透明 overlay + 透明锚点 + `bindContextMenu`。 |
| 图片动作服务 | `AiraBrowser/entry/src/main/ets/services/web/WebImageContextActionService.ets:40` | 保存、复制、分享网页图片。 |
| Web 层几何缓存 | `AiraBrowser/entry/src/main/ets/core/browser/BrowserWebLayerGeometryCache.ets:25` | 在未测到当前 Web 区域时复用最近一次 Web 几何。 |

## 入口与事件流

Web 组件本身会套一个 `BrowserWebAttributeModifier`。API 版本满足条件时，它调用 `enableDefaultContextMenu(true)`，确保 ArkWeb 可以产生默认上下文菜单事件。代码位置是 `WebDefaultContextMenuModifier.ets:30` 到 `:40`。

主 Web 节点的事件入口在 `HostedWebNode.ets:1032`：

```text
.onContextMenuShow(event => callbacks.onContextMenuShow(tabId, event, controller))
.onContextMenuHide(() => callbacks.onContextMenuHide(tabId))
```

直接子窗口 Web 使用相同思路，在 `BrowserDirectChildWindowWebHost.ets:261` 到 `:267` 转发事件。

`BrowserWebEventHostCoordinator` 会把 `onContextMenuShow` 包成安全调用，默认返回值和失败回退都是 `false`。也就是说，如果页面 handler 没有成功接管，ArkWeb 事件不会被 Aira 自定义菜单消费。

最终页面回调在 `BrowserShellPage.ets:23690` 接到：

```text
onContextMenuShow -> handleWebContextMenuShow(tabId, event, controller)
onContextMenuHide -> handleWebContextMenuHide(tabId)
```

## 状态构造

`BrowserShellPage.handleWebContextMenuShow` 做了几件事：

1. 当前激活标签页正展示错误页时，直接返回 `true` 消费事件，不继续显示菜单。
2. 调用 `WebLinkContextMenuCoordinator.buildState(...)`，传入 tabId、页面标题、隐私模式、dataScope、ArkWeb event、`controller.getLastHitTest()` 和 userscript 菜单项。
3. 如果 coordinator 返回 `undefined`，返回 `false`，表示 Aira 不处理这个长按上下文。
4. 保存 state，调用 `event.result.closeContextMenu()`，再用 `setTimeout(..., 0)` 把 `webNativeContextMenuVisible` 置为 `true`。

核心代码在 `BrowserShellPage.ets:16608` 到 `:16638`。

`WebLinkContextMenuCoordinator` 会先尝试构造图片菜单，再退回链接菜单：

- 图片路径：`buildImageState`，见 `WebLinkContextMenuCoordinator.ets:89`。
- 链接路径：`buildLinkState`，见 `WebLinkContextMenuCoordinator.ets:112`。

状态结构 `WebLinkContextMenuState` 包含：

```text
visible, kind, tabId, url, sourceUrl, title, x, y, items
```

其中 `x/y` 直接来自 `event.param.x()` 和 `event.param.y()`，保存在 `WebLinkContextMenuCoordinator.ets:102`、`:103`、`:125`、`:126`。

## 链接菜单判定与菜单项

链接 URL 的来源优先级是：

```text
param.getLinkUrl()
  -> param.getUnfilteredLinkUrl()
  -> controller.getLastHitTest().extra
```

对应代码在 `WebLinkContextMenuCoordinator.ets:153` 到 `:166`。

链接上下文必须满足：

- URL 是 `http://` 或 `https://`。
- hit-test 是 `HttpAnchor` / `HttpAnchorImg`，或者 ArkWeb param 能提供 link URL。

默认链接菜单项在 `WebLinkContextMenuCoordinator.ets:54` 到 `:64`：

```text
打开
新标签页打开
后台打开
隐私标签页打开
复制链接
分享链接
添加书签
保存离线
下载链接
```

隐私边界下会过滤 `添加书签` 和 `保存离线`。2026-07-20 后的现行实现中，匹配当前页面 URL 的 userscript `context-menu` 命令由 `WebLinkContextMenuCoordinator.buildUserScriptItems()` 向 `UserScriptRuntimeCoordinator.buildContextMenuCommands()` 获取，并通过 Runtime 的 `executePageCommandForPage()` 执行；BrowserShell 不再拥有独立的 userscript 菜单 owner。

当前代码里没有华为浏览器那种叫“自由复制”的链接菜单项。

## 图片菜单判定与菜单项

图片 URL 的来源优先级是：

```text
hitTest.extra
  -> param.getSourceUrl()
```

对应代码在 `WebLinkContextMenuCoordinator.ets:168` 到 `:177`。

图片上下文必须满足：

- `param.getMediaType()` 解析为硬编码的 image 类型值 `1`。
- 如果有 hit-test，它必须是 `Img` 或 `HttpAnchorImg`。
- 图片 URL 是 `http(s)` 或 `data:image/`。

菜单项固定为：

```text
保存至图库
复制图片
分享图片
```

对应代码在 `WebLinkContextMenuCoordinator.ets:104` 到 `:108`。当前代码没有单独的“查看图片/长按图片”项。

## 坐标和定位模型

Aira 的坐标转换分成三层。

第一层，ArkWeb 原始坐标被保存为 state：

```text
state.x = event.param.x()
state.y = event.param.y()
```

结合前一份华为调研里确认的官方 API 语义，这两个值应按“Web 组件左上角为原点的物理 px”理解。

第二层，页面提供 Web 层相对根容器的几何信息。根容器在 `BrowserShellPage.ets:6415` 的 `onAreaChange` 中记录全局 left/top/width/height；Web 层在 `BrowserShellPage.ets:6975` 的 `onAreaChange` 中记录：

```text
hostedWebLayerLeft = webGlobalLeft - rootGlobalLeft
hostedWebLayerTop = webGlobalTop - rootGlobalTop
hostedWebLayerWidth
hostedWebLayerHeight
```

如果当前 Web 层还没测到，`BrowserShellPage.ets:16995` 到 `:17025` 会尝试使用 `resolveReusableWebLayerGeometry()`，再不行就用 `getWebViewportTopInsetPx()` 和根视口尺寸兜底。这个 reusable geometry 来自 `BrowserWebLayerGeometryCache`，会校验 root 宽高、layoutTop、visualTop 和快照年龄。

第三层，`WebContextMenuPositionCoordinator` 计算 press 点和透明锚点位置：

```text
pressX = webLeft + px2vp(rawX)
pressY = webTop + px2vp(rawY)
anchorLeft = pressX - anchorSize / 2
anchorTop = pressY - anchorSize / 2
```

它还会把 Web-local 坐标夹在 Web 可见宽高内，再把 press 点夹在 root 边界内。锚点尺寸是 `2vp`，边缘 inset 是 `1vp`，常量在 `BrowserShellPresentationTokens.ets:41` 到 `:42`。

需要注意的是，这个 coordinator 只计算一个 2vp 锚点的位置，不计算菜单本身的最终 left/top，也不知道菜单宽高。

## Overlay 与菜单渲染

`BrowserShellPage.buildWebContextMenuOverlay()` 根据 state.kind 分图片/链接两条 builder，但当前两条 builder 的结构几乎一样：

1. 挂一个全屏透明 `Stack`，点击后 `closeWebContextMenu()`。
2. 再挂一个 `2vp x 2vp`、`opacity(0.01)` 的透明 `Stack`。
3. 把透明 Stack `.position({ x: resolveWebContextMenuAnchorLeft(), y: resolveWebContextMenuAnchorTop() })`。
4. 在这个透明 Stack 上调用 `.bindContextMenu(webNativeContextMenuVisible, buildWebNativeContextMenu(), { onDisappear })`。

对应代码：

- 图片 overlay：`BrowserShellPage.ets:16097` 到 `:16124`
- 链接 overlay：`BrowserShellPage.ets:16127` 到 `:16154`
- 菜单内容：`BrowserShellPage.ets:16157` 到 `:16165`

真正的菜单内容是 ArkUI `Menu()` + 多个 `MenuItem({ content: item.label })`。所以 Aira 自己控制的是菜单项内容和透明锚点位置，最终菜单弹窗的朝向、边界翻转、与锚点的偏移，仍由 `bindContextMenu` 所在的系统/ArkUI 菜单机制决定。

## 动作执行

用户点击菜单项后，`handleWebContextMenuAction` 会先 clone 当前 state，然后隐藏并关闭菜单，再按 action 分发。入口在 `BrowserShellPage.ets:16690` 到 `:16742`。

链接动作主要在页面内完成：

- `open`：当前 tab 打开链接。
- `open_new_tab` / `open_background_tab`：交给 `browserAppUrlOpenCoordinator`。
- `open_private_tab`：创建隐私标签页。
- `copy_link`：复制 URL 到剪贴板。
- `share_link`：走当前网页分享服务。
- `add_bookmark`：写入书签，并触发自动同步通知。
- `save_offline`：创建新标签，页面加载完成后保存离线。
- `download_link`：打开手动下载确认。
- `run_userscript`：执行 userscript 页面菜单命令。

图片动作统一走 `WebImageContextActionService`：

- `saveToGallery`：下载/解析图片，创建图库资源，再写入图库 URI。
- `copyImage`：下载图片，创建 `PixelMap`，写入系统剪贴板。
- `shareImage`：准备缓存文件，用 `systemShare.ShareController` 打开系统分享面板。

图片服务还做了这些处理：

- 支持 `data:image/` base64 图片。
- HTTP 请求带 `Accept`、`User-Agent`、可用时带 `Referer` 和 Cookie。
- 图片最大 30MB。
- 校验 PNG/JPEG/GIF/WebP/AVIF/SVG 等常见图片头。
- 临时文件写到应用 cache 下的 `web-image-context-actions` 目录。

## 生命周期与关闭行为

当前关闭逻辑是：

- `closeWebContextMenu()` 会取消延迟打开 timer，置 `webNativeContextMenuVisible = false`，把 state 还原为 hidden。
- `bindContextMenu` 的 `onDisappear` 会调用 `closeWebContextMenu()`。
- 点击全屏透明背景会调用 `closeWebContextMenu()`。
- 系统返回键流程会优先识别 `webContextMenuVisible`，然后返回 `close_web_context_menu`，见 `BrowserShellBackCoordinator.ets:80` 和 `BrowserShellPage.ets:6499`。
- Web 导航成功且不是 dialog back 时会调用 `hideWebContextMenuForNavigation`，见 `BrowserWebPageController.ets:421` 到 `:423`。
- 页面消失时会取消 `webContextMenuOpenTimer`，见 `BrowserShellPage.ets:6080`。
- prompt / release notice / app review 等浮层阻塞判断会把 `webContextMenuVisible` 算进去，见 `BrowserShellPromptSurfaceViewModel.ets:55`。

`onContextMenuHide` 目前主要记录 runtime event，不负责关闭 Aira 自己的菜单状态，见 `BrowserShellPage.ets:16640` 到 `:16645`。

## 当前实现的主要风险

### 1. 透明锚点 + bindContextMenu 让最终位置不可完全控

Aira 计算出来的是一个透明锚点，不是菜单最终位置。即使锚点完全落在手指点附近，`bindContextMenu` 仍可能基于锚点矩形、菜单尺寸、可用空间、系统边界策略做二次偏移。用户看到的“菜单飘”，很可能发生在这一层。

这和华为浏览器调研里看到的自绘 `ContextMenu` 不同：华为的控制器会把菜单宽高、窗口宽度、上下边界都纳入 `getX/getY`，最终由菜单组件直接 `.position({ x, y })`。

### 2. px / vp 约定分散

ArkWeb `param.x/y` 应按 Web-local 物理 px 处理；Aira 的 position coordinator 会做 `px2vp`。但 Web 层几何来自 ArkUI `onAreaChange`，解析逻辑 `parseAreaDimension` 只是去掉字符串里的 `vp` / `px` 后转数字，见 `BrowserShellPage.ets:12418`。如果某些设备/系统版本给出的 Area 值单位和预期不一致，就可能产生比例型偏移。

这点不能只靠静态代码定论，需要真机日志验证：

```text
rawX_px, rawY_px
px2vp(rawX), px2vp(rawY)
rootViewportWidth/Height
hostedWebLayerLeft/Top/Width/Height
resolvedPressX/Y
anchorLeft/Top
```

### 3. Web 层 top/left 兜底可能带来固定偏移

正常路径会用真实 `hostedWebLayerLeft/Top`。但首次渲染或测量未完成时，会用 reusable geometry 或 `getWebViewportTopInsetPx()` 兜底。如果兜底几何与当前视觉 Web 区域不一致，菜单会出现固定方向偏移。

这种偏移通常表现为：每个长按点都差不多向上/下/左/右偏同一段，而不是越靠右偏越多。

### 4. 立即关闭 ArkWeb result + 下一 tick 打开 ArkUI 菜单有时序变量

`handleWebContextMenuShow` 在 state 保存后立即调用 `event.result.closeContextMenu()`，然后 `setTimeout(..., 0)` 打开 ArkUI `bindContextMenu`。这符合“不让 ArkWeb 默认菜单继续占用”的意图，但也意味着原生 context menu 生命周期和 Aira 菜单显示之间隔了一帧。

这不一定是漂移原因，但它会让焦点、布局、菜单 host 状态更难推理。

### 5. 行为 owner 已经有一部分抽出，但 page 仍承担较多逻辑

菜单项判定在 `WebLinkContextMenuCoordinator`，坐标转换在 `WebContextMenuPositionCoordinator`，图片动作在 `WebImageContextActionService`，这些是好的方向。

但 overlay 渲染、event.result 关闭时机、延迟打开、链接动作分发、Web geometry 兜底组装仍大量在 `BrowserShellPage.ets`。如果后续要修定位，建议继续把“菜单显示 owner”抽到非 page 模块里，让页面只做 ArkUI 挂载和事件转发。

## 后续排查建议

如果只是定位“为什么会飘”，建议先加一次真机日志，不急着重构 UI。长按九宫格点位：

```text
左上 / 中上 / 右上
左中 / 中心 / 右中
左下 / 中下 / 右下
```

判断方式：

- 偏移随点位距离成比例放大：优先查 px/vp 单位。
- 每个点都固定偏一段：优先查 Web layer top/left 和 visual inset。
- 靠右/靠底时明显异常：优先查 `bindContextMenu` 的边界翻转策略。
- 日志里的 anchor 已准，但菜单仍飘：透明锚点路线本身就是主要问题，应转自绘 overlay 菜单。

如果目标是接近华为浏览器的准确度，推荐最终方向是：

1. 保留 `WebLinkContextMenuCoordinator` 负责链接/图片菜单项。
2. 扩展或新建一个非 page 的菜单 overlay owner，显式区分 `rawWebXPx/rawWebYPx`、`webLeftVp/webTopVp`、`pressXVp/pressYVp`、`menuLeftVp/menuTopVp`。
3. 用 ArkUI 自绘菜单组件直接 `.position({ x: menuLeftVp, y: menuTopVp })`，把菜单宽高、窗口边界、上下左右翻转纳入同一个 owner。
4. `BrowserShellPage.ets` 只保留挂载 overlay、绑定 state、转发菜单点击这些 shell wiring。
