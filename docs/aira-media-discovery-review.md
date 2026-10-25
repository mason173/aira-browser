# 资源嗅探调研与改进

日期：2026-10-25。范围：HarmonyOS 客户端的资源发现、下载上下文和网页性能。

## 对照实现

本次下载并阅读了猫抓源码，以及 HLS Downloader 的监听器、请求和合并模块。第三方代码仅作为
调研材料，未加入客户端依赖，也未复制到产品源码。

| 实现 | 源码中的做法 | 对 Aira 的启示 |
| --- | --- | --- |
| [猫抓网络发现](https://github.com/xifangczy/cat-catch/blob/a7c96921be16ef05432fb0058d1bcbef13f255f6/js/background.js) | 关联请求头与响应；结合扩展名、响应 MIME、附件文件名和 media 请求类型判断；去重并延迟保存 | 地址后缀不是唯一证据；请求上下文和有界缓存同样影响可下载性 |
| [猫抓深度搜索](https://github.com/xifangczy/cat-catch/blob/a7c96921be16ef05432fb0058d1bcbef13f255f6/catch-script/search.js) | 在页面中观察 JSON、XHR、fetch 等动态数据 | 可补充动态播放器，但大范围改写全局函数、读取响应体会增加兼容和性能成本 |
| [HLS Downloader 发现](https://github.com/puemos/hls-downloader/blob/c6392f2ff2a52762faaac9542dcf7c9ff20f0cf6/src/background/src/listeners/addPlaylistListener.ts) | 对指定 m3u8 XHR 请求检查完成状态与响应 MIME，按地址去重 | 它的该监听器也有限定范围，不能假设所有第三方方案在所有网站都能发现更多 |
| [HLS Downloader 合并](https://github.com/puemos/hls-downloader/blob/c6392f2ff2a52762faaac9542dcf7c9ff20f0cf6/src/background/src/services/ffmpeg-muxer.ts) | 独立处理音视频输入，再交由 FFmpeg 合并封装 | “识别到清单”与“导出完整可播放文件”是两项能力，需要分别实现 |

平台约束以[华为 Web 拦截能力说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/web-component-intercept-capab-usage)
为依据：`onInterceptRequest` 是请求拦截/响应替换能力，要求提供完整内容，不能直接当作扩展的
`webRequest.onResponseStarted` 使用。此次没有为嗅探接管全站网络请求，也没有新增主动下载探测。

## 在当前实现中复现的问题

1. **深度脚本无法解析。** 模板字符串中的四处正则转义遗漏；生成的脚本出现
   `/(?:/media/|/stream/|/video/|videoplayback)/i`。对修改前 HEAD 的构建结果运行 JavaScript
   解析器可复现 `SyntaxError: Invalid regular expression flags`。ArkTS 编译不会发现字符串内部的错误。
2. **签名地址被改坏。** 资源正则只提取到扩展名；另外三个探针和原生文本提取器会对整段内容反复
   `decodeURIComponent`，将 URL 内的 `%26`、`%2B`、`%252F` 等签名值改写。
3. **异步发现丢失。** 部分 fetch/XHR 文本扫描结果进入安装 hook 那次调用的局部数组；调用返回后，
   下一次扫描无法读取这些结果。
4. **结果顺序和扫描成本不合理。** 图片先占据 160 项输出；网络记录只看最早 320 项；扫描最多
   180 个节点的计算样式。文本扫描虽然有字符限制，但没有整体时间预算。
5. **响应读取缺少完整边界。** Blob hook 有额外的整块 `text()` 读取；fetch 副本读取没有超时和
   并发上限，超大单个 chunk 在检查限制前就进入解码。运行时去重表未随结果淘汰。
6. **DOM 下载上下文不完整。** DOM 发现的地址没有携带当前 Web 控制器的站点 UA。原生请求观察则
   为 Referer、UA、Origin 和完整头表重复读取同一份平台头信息。

## 本次实现

- 三个页面探针与原生文本提取器使用相同的地址规范化规则：只解开地址外层编码，保留地址内的
  转义和完整查询串。播放器查询参数按值单独解析，相对地址使用 `document.baseURI`。
- URL 提取先消费完整 token，再判断类型，避免无有效后缀的长字符串触发反复正则回溯。
- 修复深度脚本语法；异步结果进入最多 80 项的运行时缓存。淘汰结果时同步清理去重表，后续清单
  内容能够补充先收到的 MIME 证据。
- fetch/XHR 的已成功媒体响应通过 MIME 补充无后缀地址识别。普通二进制媒体只观察元信息；fetch
  POST 响应本身不冒充 GET 下载地址。Resource Timing 的 `contentType` 存在时也用于识别，不依赖它必然可用。
- 资源面板优先扫描实际媒体与最近的网络记录，再处理脚本、属性、文件链接和图片；补充 `data-src`
  懒加载图片和无后缀 `data-hls` / `data-m3u8` 地址。
- DOM 观察携带页面/框架来源和站点 UA；每次原生观察只读取一次请求头，保留完整捕获头供后续下载使用。

| 工作量边界 | 本次值 |
| --- | --- |
| 单次资源面板扫描 | 24 ms 协作式截止时间、最多 160 项结果 |
| 手动脚本文本扫描 | 每节点 32,768 字符，总计 131,072 字符，最多 24 个节点 |
| 计算样式 | 最多 48 个节点，并受扫描截止时间限制 |
| Resource Timing | 最近 320 项，媒体优先于图片 |
| fetch/Blob 文本读取 | 最多同时 2 份，每份 1.5 秒超时 |
| fetch 文本大小 | 普通文本最多 100,000 字节，清单最多 300,000 字节 |
| Blob 文本大小 | 仅考虑不超过 300,000 字节的候选，移除整块无界读取 |

这些是工作量上限，不是设备帧耗时的测量值。单次 DOM 查询或浏览器原语不能被 JavaScript 中途
抢占，因此 24 ms 是协作式截止时间。SSE、NDJSON 和流式 JSON 跳过响应体扫描；超限或中断的
文本不作为完整清单解析。取消只针对嗅探的副本，不等待副本取消完成，也不替换网页收到的 Response。

保留 `9b8472eb` 引入的原生流式请求绕过、按需探测和静态扫描次数限制。未增加常驻全页面
MutationObserver、全量对象遍历或 MSE 缓冲复制。

## 下载能力边界与后续顺序

现有 HTTP GET、HLS VOD 和 AES-128 identity 下载继续使用现有下载器。DASH、HLS 独立音轨、
直播录制和通用 MSE 导出仍不是此次新增能力；详见[下载架构](aira-browser-download-current-architecture.md)。

建议后续依次推进：

1. 以实际失败站点建立可复现样本，分别记录“未发现”“发现但无完整上下文”“传输失败”“缺少合并能力”。
   对比滚动、页面加载和播放期间的耗时、内存及请求量，不能仅比较资源条数。
2. 在现有下载 owner 内增加独立音视频的选择、任务恢复和合并封装，再开放对应下载操作。
3. 在华为支持的接口范围内评估更完整的响应元信息及框架证据采集；首先验证平台能力与成本，
   避免为了取得响应头而重新代理所有请求。
4. 深度模式中的更昂贵能力继续按需开启，并配置独立预算，不将桌面扩展的默认成本直接搬到手机。

## 验证

`scripts/check-aira-media-discovery.cjs` 执行实际生成的页面脚本，使用合成 DOM、响应流与请求头，
以 20 组回归覆盖语法、编码/签名、相对地址、资源优先级、标题与时长归属、工作量边界、响应副本、异步留存和下载上下文。
该检查已加入本地构建和 CI 共用的 `scripts/check-aira-downloads.sh`。

不使用真实设备画面或私有页面数据。本地契约测试与构建不能代替真机网站兼容性及帧耗时验证。

## 视频名称：对照源码后补充的改进

本节针对“嗅探结果与下载文件名只有数字、字母”的反馈。先阅读下列具体命名实现，再决定 Aira
的规则；不将作者说明或功能宣传当作已经实现的行为。

| 对照源码 | 实际命名方式 | Aira 采用的思路 |
| --- | --- | --- |
| [猫抓 popup.js](https://github.com/xifangczy/cat-catch/blob/a7c96921be16ef05432fb0058d1bcbef13f255f6/js/popup.js#L58-L84)、[init.js](https://github.com/xifangczy/cat-catch/blob/a7c96921be16ef05432fb0058d1bcbef13f255f6/js/init.js#L80-L101) | 保留资源原名；开启 TitleName 后使用模板，预设模板为 `${title}.${ext}`。所查提交的 TitleName 默认是 false | 名称与扩展名独立处理，保留原始证据 |
| [HLS Downloader generate-file-name.ts](https://github.com/puemos/hls-downloader/blob/c6392f2ff2a52762faaac9542dcf7c9ff20f0cf6/src/core/src/use-cases/generate-file-name.ts) | 页面标题加清单原名；扩展名来自输出容器，清理非法字符并做 NFC 规范化 | 网页标题参与命名；HLS 文件后缀服从实际下载输出，不把清单名直接当成视频格式 |
| [Live Stream Downloader build.js](https://github.com/chandler-stimson/live-stream-downloader/blob/983af6f28a109be5d7f78b0836608de969b0c20d/v3/data/job/build.js#L14-L215) | 默认使用提取的资源名；模板支持页面标题和按需读取指定 DOM 元素，也提供可选网络名称探测 | 在现有扫描中读取少量标题属性；Aira 此次不引入任意选择器模板或额外请求 |

Aira 的实现放在 `MediaResourceNamePolicy`，由资源列表与下载投影共用：

1. 优先采用站点提取器已有的原生标题、与具体视频元素绑定的 `title` / `aria-label` / `data-title`。
2. 已有清晰资源文件名时保留原名。仅对常见哈希、UUID、长数字、部分长混合标识，以及
   `index`、`master`、`playlist`、`video` 等通用名称，使用页面标题补足；这是保守启发式，不是语义识别。
3. 页面标题在现有 DOM 扫描中从 Open Graph、Twitter 元数据、`document.title` 读取，最多两次
   单元素查询。每个标题最多读取 512 个字符；不新增定时器、全页面文本扫描或响应体读取。
4. 各播放器标题只传给它自身的 URL，不借用首个播放器的标题给其他资源。页面级标题无法保证是
   同页每个视频的独立名称；没有可靠标题时保留原名，不猜测。保存重名文件沿用既有冲突处理。
5. 清理文件名禁用字符、控制字符与方向覆盖字符，标题主体限制为 200 个 UTF-8 字节，保留中文、
   表情和 `.EP01` 之类的标题内容。后缀根据资源格式补齐；HLS 初始为 `.ts`，最终容器仍由下载器确定。
6. 将明确的标题交给下载任务时，不再把会覆盖它的旧 Content-Disposition 文件名传给下载命名器；
   原始响应头继续保留在候选证据中。后到达的清晰服务器名称可补充此前只有哈希的记录。

`check-aira-media-resource-names.cjs` 另有 7 组命名契约，覆盖标题优先级、原名保留、格式与长度、
非视频资源、列表到下载的完整命名链路，以及后续 DOM/响应元数据合并。它与注入脚本的标题隔离
测试一并进入下载可靠性检查。第三方源码仅作为参考，没有复制其模板引擎或引入新依赖。

## 分片视频时长显示修复

针对“十几分钟的视频在资源弹窗只显示四十多秒”的反馈，用合成数据复现了下列问题：

- 资源探针把页面第一个播放器的时长补给其他视频 URL；三个探针也会把当前源的时长赋给未播放的备选源。
- 候选合并永远保留第一次的时长；投影又优先采用该值，导致完整清单的 900 秒被播放器早期的 42 秒遮住。
- 清单解析没有区分可继续增长的播放窗口与已结束的清单，五个 8.5 秒片段会被显示成总长 42.5 秒。
- 已捕获的早期清单文本不会被后来捕获的完整清单替换，完成后的总时长也无法更新。

对照[猫抓的直播/点播显示分支](https://github.com/xifangczy/cat-catch/blob/a7c96921be16ef05432fb0058d1bcbef13f255f6/js/m3u8.js#L801-L808)
以及 [RFC 8216 的 ENDLIST 定义](https://www.rfc-editor.org/rfc/rfc8216.html#section-4.3.3.4)，
将“已列出的片段范围”和“已完成资源的总时长”分开。HTML 的时长也允许随着新信息修订，不能只读第一次；
参见 [HTML 媒体时长定义](https://html.spec.whatwg.org/multipage/media.html#dom-media-duration-dev)。

实现只调整已有采集、合并、解析和投影链路：

1. 播放器时长仅属于与 `currentSrc` 精确匹配的资源，不再借用其他播放器或未选中源的数据。
2. 后续有效播放器时长可以更新旧值，也允许向下纠正；NaN、无限值、负数不覆盖有效时长。
3. HLS 弹窗时长只使用完整清单证据，优先采用自身清单，其次采用父主清单中匹配的变体。
   收到 ENDLIST 且每个分片都有有效 EXTINF 时，累加全部分片，和最多五个探测样本的限制无关。
   正在增长的清单、缺失片段信息、截断清单、带 SKIP 的增量清单不提供总时长，也不据此估算整片大小。
4. 初始有限的播放器时长不再作为 HLS 总长兜底；未取得完整清单时暂不显示总时长。
5. 后来捕获到完成清单时替换早期文本并失效旧验证。普通滚动窗口变化继续复用已有验证，
   不为每次滚动更新增加请求；原有探测数量、频率和扫描预算不变。

新增 `check-aira-media-durations.cjs` 的 7 组回归，覆盖完整 15 分钟清单、42.5 秒滚动窗口、
EVENT 完成、增量/缺失数据、列表与下载投影一致、主清单各变体隔离、播放器时长修订以及捕获清单升级。
注入脚本另覆盖 42 秒预览不能污染完整视频及备选源。修复前这些样例可复现错误，修复后全部通过。
测试使用本地合成清单和 DOM，不代表已验证所有站点或真机性能。
