# KISS Translator 网页翻译 Loading 行为参考

本文记录 KISS Translator / 简约翻译在“网页正文翻译中”展示段落级 loading 的整体行为和实现逻辑。以下路径相对于独立的 KISS Translator 上游源码目录。

## 相关源码

- `src/libs/translator.js`
  - `#createIntersectionObserver()`：可见性触发翻译。
  - `#scanNode()` / `#processNode()`：扫描、过滤、分组待翻译 DOM。
  - `#translateNodeGroup()`：段落级 loading 的创建、插入、替换、失败处理。
  - `#translateHoverBubbleNode()`：鼠标悬停气泡翻译的 loading，同样复用 loading SVG。
- `src/libs/svg.js`
  - `createLoadingSVG()`：创建 loading 动画 SVG。
  - `createRetrySVG()`：创建失败重试图标。
- `src/apis/index.js`
  - `apiTranslate()`：翻译分发、缓存命中、批量队列、流式回调。
- `src/libs/batchQueue.js`
  - `BatchQueue()`：批量翻译队列和流式结果回传。

## 用户看到的行为

网页正文翻译不是等整页翻完才一次性显示结果，而是按文本块逐段工作。

当某一段进入待翻译状态后，插件会立即在这段原文旁边插入一个译文位置。这个位置一开始不是空白，也不是全局进度条，而是一个跟文字字号一致的蓝色三点跳动 loading。用户会感觉“这一段正在翻译”。

当这一段翻译成功后，loading 会在原位置被译文替换。也就是说，loading 不单独消失，而是同一个译文容器里的内容从“loading 动画”变成“翻译结果”。

如果是流式翻译，第一段流式文本回来时，loading 就会被清掉，开始显示已经生成的部分译文；后续流式片段继续更新同一个文本节点。用户看到的是从 loading 过渡到逐步出现的译文。

如果翻译失败，loading 不会无限转下去。插件会把 loading 替换成失败/重试节点，用户可以点击重试。

如果识别到这段不需要翻译，例如源语言和目标语言相同，或者翻译结果为空，临时插入的 loading 容器会被移除，页面恢复为没有这段译文占位的状态。

## Loading 动画本体

`createLoadingSVG()` 动态创建内联 SVG，而不是依赖外部图片或 CSS keyframes。

它创建一个 `svg`：

- `display: inline-block`
- `width: 1em`
- `height: 1em`
- `vertical-align: middle`

内部有三个蓝色 `circle`，颜色为 `#209CEE`。每个圆点都有 `animateTransform`：

- 动画类型是 `translate`
- 时长是 `1s`
- 无限重复
- 三个点的 `begin` 分别是 `0.1`、`0.2`、`0.3`
- 三个点上下跳动幅度不同

所以它看起来像段落文字后面的一个小型三点跳动等待动画。因为尺寸是 `1em`，它会自然贴合所在文字大小。

## Loading 什么时候出现

正文翻译的入口不是点击后立刻翻译全部 DOM，而是先扫描和观察节点。

大致流程：

```text
页面根节点开始被监控
 -> scanNode 扫描可翻译文本块
 -> startObserveNode 注册 IntersectionObserver
 -> 节点进入视口或预加载边界
 -> processNode 处理该节点
 -> translateNodeGroup 对一个文本组发起翻译
 -> 立即插入 loading 容器
```

触发点主要有两类：

- 普通懒加载翻译：节点进入 `IntersectionObserver` 的观察范围后，经过 `transInterval` 防抖，再调用翻译处理。
- 立即翻译全页：如果处于 `transAllnow` 模式，节点不等进入视口，扫描到后直接处理。

`#processNode()` 会先做过滤：

- 节点已经处理过则跳过。
- 文本无效则跳过。
- 如果 `fromLang` 是 `auto`，先做语言检测。
- 如果检测到源语言和目标语言相同，或者命中跳过语言，则不插入 loading。
- 长段落可能先按句子切分。
- 子节点按块级分隔组合成 `nodeGroup`，每个 `nodeGroup` 单独进入 `#translateNodeGroup()`。

真正让 loading 出现在页面上的位置是 `#translateNodeGroup()`：

```text
序列化 nodeGroup 为待翻译字符串
 -> 创建 wrapper
 -> 创建 inner
 -> inner.appendChild(createLoadingSVG())
 -> 按原文/译文顺序把 inner 放进 wrapper
 -> wrapper 插到原文前面或后面
 -> 发起 translateFetch
```

注意顺序：它是先插入 loading，再发请求。因此只要这一段通过过滤并准备翻译，用户马上能看到反馈。

## 插入到哪里

它有两个层级：

```text
wrapper: 自定义翻译容器，class 是 kiss-translator-wrapper notranslate
inner: 真正显示译文或 loading 的节点，class 是 kiss-translator-inner 加译文样式 class
```

`wrapper` 的标签名来自 `#translationTagName`，值是项目的 app 小写名，也就是自定义标签。它还带 `notranslate`，避免浏览器或其它翻译逻辑再次翻译插件插入的内容。

`inner` 的标签名来自规则里的 `transTag`，并设置：

- `lang = toLang`
- `class = kiss-translator-inner + 当前译文样式`
- 如果用户配置了扩展样式，还会写入 `style.cssText`

插入位置由 `transOrder` 决定：

- `original-first`：原文在前，译文在后。这是默认行为。`wrapper` 插到 `nodes[nodes.length - 1].after(wrapper)`。
- `translation-first`：译文在前，原文在后。`wrapper` 插到 `nodes[0].before(wrapper)`。

对于长文本，它会在 wrapper 里放一个 `br`，让译文换行显示。对于短文本，它放一个普通空格 `span`，让译文更像跟在原文后面的内联内容。

## Loading 怎么消失

Loading 的消失有四种路径。

### 1. 普通成功：替换为最终译文

请求完成后，`#translateFetch()` 返回：

```text
{ trText, isSame, srLang, srCode }
```

如果 `trText` 有值并且 `isSame` 不是同语种，代码会把翻译文本恢复为 HTML，然后写入同一个 `inner`：

```text
inner.innerHTML = trustedHTML
```

这一步直接覆盖原来的 SVG loading，所以用户看到的是 loading 原地变成译文。

### 2. 流式成功：第一段 chunk 替换 loading

如果满足这些条件，就开启流式渲染：

- `streamRenderMode !== "disabled"`
- 当前 API 配置 `useStream` 为 true
- 当前 API 类型支持 stream

流式回调 `onStreamChunk` 会收到两类数据：

- `isComplete: false`：部分文本。
- `isComplete: true`：最终文本。

第一段部分文本到来时：

```text
innerRef.textContent = ""
innerRef.appendChild(document.createTextNode(pendingText))
```

这会清掉 SVG loading，放入一个 TextNode。

后续 chunk 不反复重建 DOM，而是改同一个 TextNode：

```text
textNode.nodeValue = pendingText
```

为了避免大模型流式输出频率太高导致页面布局抖动，它用 `requestAnimationFrame` 做节流。中间 chunk 先写到 `pendingText`，每帧最多刷新一次 DOM。

最终 chunk 到来时，如果还有未执行的 RAF，会先取消，再立即 flush 最终文本。

### 3. 无需翻译：移除 wrapper

如果最终没有译文，或者判断 `isSameLang` 为 true：

```text
wrapper.remove()
```

这种情况用户可能短暂看到 loading，然后它消失，不留下译文位置。

### 4. 请求过期或被中断：清理当前节点的译文容器

每轮翻译有一个 `runId`。`#translateNodeGroup()` 插入 loading 后会保存当前 `runId`。如果请求返回时发现当前 `runId` 已经变化，说明用户可能关闭/重新触发了翻译，本轮结果过期。

这时它抛出 `Request terminated`，catch 分支会调用：

```text
#cleanupDirectTranslations(hostNode)
```

直接清理该 host 下的临时翻译容器，避免旧请求回来后污染新状态。

### 5. 失败：替换为重试节点

如果请求失败且不是主动终止：

```text
找到 hostNode 下最后一个 kiss-translator-wrapper
 -> 找到里面的 kiss-translator-inner
 -> inner.textContent = ""
 -> inner.appendChild(retryNode)
```

`retryNode` 会绑定点击回调：

```text
移除当前 wrapper
 -> 从 processedNodes 删除 hostNode
 -> 再次调用 translateNodeGroup(nodes, hostNode, deLang)
```

所以失败状态不是独立弹窗，而是占用同一个译文位置。重试时旧失败节点被移除，新一轮又会先出现 loading。

## 翻译请求和 loading 的关系

`#translateFetch()` 只负责组装参数和调用 `apiTranslate()`，loading 的生命周期仍由 `#translateNodeGroup()` 管。

`apiTranslate()` 做几件事：

1. 校验文本和语言。
2. 构造缓存 key，包含翻译服务、原文、源语言、目标语言、版本、prompt 签名等。
3. 先查本地缓存。
4. 缓存命中时立即返回译文。
5. 缓存未命中时，根据 API 类型走本地 AI、批量队列或单请求。
6. 如果支持流式，把 `onStreamChunk` 继续传下去。
7. 得到最终译文后写入缓存。

这意味着：

- 缓存命中时，loading 仍然会先被插入，但通常马上被替换，肉眼可能只看到一闪。
- 缓存未命中时，loading 会持续到该段请求 resolve。
- 批量翻译时，某段 loading 的持续时间包含排队等待、批次请求、结果返回。
- 流式翻译时，loading 的持续时间只到第一段 chunk 到来，而不是等完整结果。

## 批量队列下的段落级反馈

批量队列的重点是：多个段落可以被合并请求，但 UI 仍然保持段落级 loading。

每个段落调用 `queue.addTask(text, args)` 后，都会得到自己的 Promise。队列实际发请求时把多段文本合并交给 `handleTranslate()`。

如果底层返回异步生成器：

- 中间结果 `isComplete: false` 时，队列把 `partialText` 回传给对应段落的 `onStreamChunk`。
- 最终结果 `isComplete: true` 时，队列把该段 Promise resolve。
- 某一段没有结果时，该段 Promise reject，进入失败重试逻辑。

所以即便网络层是批处理，页面表现依然是“每段自己转、自己消失、自己失败”。

## 鼠标悬停气泡的 loading

悬停翻译气泡也复用同一个 `createLoadingSVG()`，但生命周期更像浮层：

```text
鼠标悬停到可翻译节点
 -> currentRunId = ++hoverBubbleRunId
 -> showHoverBubble(createLoadingSVG(), "loading")
 -> 语言检测
 -> translateFetch
 -> 成功：showHoverBubble(译文)
 -> 无需翻译：hideHoverBubble()
 -> 失败：showHoverBubble(错误文本, "error")
 -> 鼠标离开或目标变化：hideHoverBubble() 并递增 hoverBubbleRunId
```

正文翻译 loading 是嵌入页面文档流的；悬停气泡 loading 是固定定位浮层。两者共用动画资产，但状态管理不同。

## 状态机摘要

正文段落级 loading 可以抽象成下面的状态机：

```text
idle
 -> eligible
 -> loading_visible
 -> streaming_visible
 -> translated_visible
```

异常和旁路状态：

```text
loading_visible -> removed_no_translation
loading_visible -> removed_stale_request
loading_visible -> retry_visible
streaming_visible -> translated_visible
streaming_visible -> retry_visible
retry_visible -> loading_visible
```

各状态含义：

- `idle`：节点尚未扫描或不在观察范围内。
- `eligible`：节点通过扫描和基础过滤，准备翻译。
- `loading_visible`：译文容器已插入，inner 中是 loading SVG。
- `streaming_visible`：loading 已被第一段流式文本替换，后续 chunk 继续更新文本节点。
- `translated_visible`：最终译文写入 inner。
- `removed_no_translation`：结果为空或同语种，移除临时容器。
- `removed_stale_request`：runId 变化，旧请求被判定过期并清理。
- `retry_visible`：请求失败，loading 替换成重试 UI。

## 这个设计值得借鉴的点

- 段落级反馈比全局 loading 更自然：用户能知道哪些段落正在处理，哪些已经完成。
- 先插入占位再请求，让慢网络也有即时反馈。
- loading 和译文共用同一个 `inner`，成功、流式、失败都只是替换内容，DOM 结构简单。
- 使用 `1em` 内联 SVG，能贴合不同网页字号，不需要维护多套尺寸。
- 流式更新只改 TextNode，并用 RAF 节流，避免高频 DOM 更新带来的卡顿。
- 用 `runId` 防止旧请求回写，适合处理用户快速开关翻译、切换规则、重新翻译等竞态。
- 失败状态原地替换为重试，避免用户误以为还在等待。
- `notranslate` 类和自定义 wrapper 可以避免二次翻译或扫描自己插入的内容。
- 懒加载观察节点能控制同时出现的 loading 数量，减少整页翻译时的并发和视觉噪声。

## 如果 Aira 参考这个模式

如果以后在 Aira 里做网页翻译 loading，不建议把这套逻辑塞进页面 shell。更适合拆成明确 owner：

- 页面或 Web 组件层：只负责注入/启用翻译能力、转发用户开关。
- 翻译 DOM owner：负责扫描、分组、插入占位、替换译文、清理旧状态。
- 翻译请求 service：负责缓存、批量、流式、错误分类。
- loading/retry renderer：负责生成 loading、失败、重试的 DOM 或注入脚本片段。

最小可参考模型：

```text
TranslationDomCoordinator
 -> TranslationNodeScanner
 -> TranslationPlaceholderRenderer
 -> TranslationRequestService
 -> TranslationStateRegistry
```

重点不是照搬 KISS Translator 的 DOM 代码，而是照搬它的交互原则：

```text
每个翻译单元都有自己的 loading
loading 原地替换为译文或失败状态
旧请求不能回写新状态
流式内容尽早替换 loading
```
