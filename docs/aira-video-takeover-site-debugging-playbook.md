# Aira 视频接管站点调试手册

创建日期：2026-07-09

## 目标

这份文档用于以后调试“某个视频网站没有悬浮接管按钮、按钮出现但点击失败、进入原生播放器后无法播放”等问题。目标是先用稳定日志把问题定位到链路层级，再决定改哪个 owner，避免反复刷新真实站点或临时试命令。

适用范围：

- HarmonyOS NEXT 真机上的 Aira debug 包。
- 通用媒体发现、HLS/DASH/MP4 候选、原生视频接管、AVPlayer / MediaSourceLoader / 本机代理。
- 真实网站只做少量人工复现；遇到 Cloudflare、风控、封禁、403 激增时，立即停止 live-site 测试，改用已有日志或可控 fixture。

非目标：

- 不把单站适配当默认方案。
- 不把策略或解析逻辑写进 `BrowserShellPage.ets`。
- 不用仓库内部自动化测试文件替代真机日志。需要可控验证时，用手动 fixture 或外部临时页面。

## 先记住的结论

视频接管链路分五层：

```text
页面/ArkWeb runtime 可用
  -> 媒体信号发现 ingest
  -> 候选 validation
  -> projection / floating button gate
  -> native launch / AVPlayer playback
```

调试时不要跳层。没有按钮时，先看 discovery/validation/projection；按钮都没有，不要让用户点击。按钮出现后播放失败，才看 native launch 和 playback loader。

## 代码 owner 对照

| 层级 | 主要 owner | 典型文件 |
| --- | --- | --- |
| 页面生命周期和 probe 调度 | `BrowserMediaDiscoveryCoordinator` | `AiraBrowser/entry/src/main/ets/core/browser/media/BrowserMediaDiscoveryCoordinator.ets` |
| DOM/deep probe 脚本 | media discovery feature | `AiraBrowser/entry/src/main/ets/features/mediaDiscovery/*ProbeScript.ets` |
| 信号分类 | `MediaSignalClassificationService` | `AiraBrowser/entry/src/main/ets/services/media/MediaSignalClassificationService.ets` |
| 候选 store / validation 状态 | `MediaDiscoveryStore` | `AiraBrowser/entry/src/main/ets/services/media/MediaDiscoveryStore.ets` |
| HLS/DASH/MP4 可播放校验 | `MediaCandidateValidationService` | `AiraBrowser/entry/src/main/ets/services/media/MediaCandidateValidationService.ets` |
| 按钮投影 | `MediaCandidateProjector` + floating view model | `AiraBrowser/entry/src/main/ets/services/media/MediaCandidateProjector.ets` |
| native item resolver | `NativeVideoTakeoverResolveService` | `AiraBrowser/entry/src/main/ets/services/video/NativeVideoTakeoverResolveService.ets` |
| AVPlayer source / HLS loader | `NativeVideoAvPlayerSession` / `NativeHlsMediaSourceLoaderService` | `AiraBrowser/entry/src/main/ets/services/video/*` |

页面文件只允许做 ArkUI/ArkWeb wiring 和状态转发。发现、过滤、排序、validation、播放加载都不应该进页面。

## 装包和启动前检查

如果改了行为并需要真机验证，先安装：

```bash
./scripts/install-aira-browser.sh
```

调试真实视频网站前，先在 Aira 里打开：

```text
设置 -> 实验室 -> 视频接管 -> 视频接管诊断日志
```

这个开关只控制详细 `media diagnostics ...` 诊断日志。开发包里可以一键打开；release/AppGallery 构建会通过 `AIRA_ENABLE_VIDEO_TAKEOVER_DIAGNOSTICS=false` 强制关闭，即使本地偏好里残留为开，也不会输出这组详细日志。调试结束后可以手动关掉，避免普通浏览时刷屏。

确认设备在线：

```bash
hdc list targets
```

确认当前包的进程。没有输出说明 app 没在运行，不是错误：

```bash
hdc shell pidof com.aira.browser || true
```

## 日志抓取：首选单进程 live capture

这是默认方式。优先用它，不要先发明别的 hilog 参数组合。

```bash
mkdir -p .tmp-navigation-capture

# 清掉旧 buffer，避免混到旧 PID 或上一轮测试。
hdc shell "hilog -r"

# 让用户手动打开页面，或只启动一次目标 URL。不要对风控站点循环启动。
URL='https://example.com/video-page'
hdc shell aa start \
  -a EntryAbility \
  -b com.aira.browser \
  -m entry \
  -A ohos.want.action.viewData \
  -U "$URL" \
  -e entity.system.browsable

sleep 3
PID=$(hdc shell pidof com.aira.browser | tr -d '\r' | awk '{print $1}')
if [ -z "$PID" ]; then
  echo "Aira process is not running; do not call hilog -P with an empty PID."
  exit 1
fi

CASE='video-site'
LOG=".tmp-navigation-capture/${CASE}-pid-${PID}-$(date +%Y%m%d-%H%M%S).log"
hdc shell "hilog -P $PID -v time" > "$LOG" &
CAPTURE_PID=$!
echo "capturing $LOG with capture pid $CAPTURE_PID"

# 只复现一次：等待页面加载、按钮出现或失败、必要时点击一次。
read -r -p "Press Enter after the single repro is complete..."

# 复现完成后停止抓取。
kill "$CAPTURE_PID"
wait "$CAPTURE_PID" 2>/dev/null || true
echo "$LOG"
```

要点：

- 正确命令是 `hdc shell "hilog -P <pid> -v time"`。
- 先拿到非空 PID，再用 `-P`。
- 把完整 raw log 保存到文件后再过滤，不要只保留管道过滤后的结果。
- `-v time` 必须保留。用户说“看 18:10 的日志”时，靠它对齐时间。

## 日志抓取：只读 tail fallback

有些情况下 PID 不存在、app 已退出、或者某些 hilog 参数组合在当前设备上不接受。此时不要继续试复杂参数，改成只读 tail。

```bash
mkdir -p .tmp-navigation-capture
CASE='video-site-tail'
LOG=".tmp-navigation-capture/${CASE}-tail-$(date +%Y%m%d-%H%M%S).log"

# 只读最近日志，不按 PID 过滤。
hdc shell "hilog -v time -n 1500" > "$LOG"
echo "$LOG"
```

如果用户给了具体时间，例如 18:10：

```bash
rg -n "18:10|18:11|MediaDiscovery|NativeVideo|NativeHls|AVPlayer|HLS|error|failed" "$LOG"
```

已知不要优先使用的方式：

- 不要用 `hdc hilog --pid ...`。这台设备上曾经抓错/混旧 PID，统一走 `hdc shell "hilog -P <pid> -v time"`。
- 不要在 PID 为空时调用 `hilog -P "$PID"`，容易得到无意义错误，例如 `Too many arguments [CODE: -36]`。
- 不要在这台机上把 `hilog -x` 和 `-z` 当成稳定路径；遇到不接受参数时，直接退回只读 tail。
- 不要只跑 `hdc shell hilog ... | rg ...` 而不保存 raw log。先保存，再 `rg`。

清理残留抓日志进程：

```bash
pgrep -fl "hdc.*hilog" || true
kill <pid1> <pid2> 2>/dev/null || true
```

## 标准过滤命令

先过滤媒体发现和按钮 gate：

```bash
rg -n \
  "media diagnostics (page_end_probe|ingest|ingest_empty|validation_targets|validation_auth|validation_hls_shape|validation_probe|validation_probe_retry|validation_page_fetch_fallback|validation_result|projection)|native video floating|NativeVideoTakeover|NativeVideoAV|NativeHlsLoader|NativeHlsPageFetch" \
  "$LOG"
```

播放失败时再加系统播放器关键词：

```bash
rg -n \
  "NativeVideoAV|NativeHlsLoader|NativeHlsPageFetch|NativeVideoProxy|AVPlayer|HLS|PullData|PeekRange|read failed|cannot read|error|failed" \
  "$LOG"
```

如果怀疑启动、路由、Web runtime 没起来：

```bash
rg -n \
  "LoadUrl|OnPageBegin|page_begin|page_end|active_tab_shell_web|tab_created|showHome|runtime_event|TypeError|RuntimeError|crash|Crash|FATAL" \
  "$LOG"
```

## 读日志的固定顺序

### 1. 看页面和 runtime 是否可探测

关键行：

```text
media diagnostics page_end_probe ... outcome=scheduled ... full=true takeover=true controller=true active=true host=...
```

判断：

- 没有 `page_end_probe`：先查导航、页面生命周期、Web runtime 事件，不要改媒体解析。
- `full=false`：全量模式/服务模式上下文有问题。
- `takeover=false`：先查 `BrowserMediaDiscoveryRuntimeContextFactory`、`PreferencesRepository`、设置缓存合并。不要直接说用户开关没开。
- `controller=false`：live ArkWeb controller 不可用，先查 runtime lifecycle。
- `active=false`：当前 tab 或 surface 不是活动 Web 页面，先查 tab/runtime owner。

### 2. 看 discovery 是否抓到媒体信号

关键行：

```text
media diagnostics ingest ... signals=94 ... hls=91 ... capturedManifest=9 ... http=... blob=... host=...
media diagnostics ingest_empty ... reason=scheduled_deep_probe_likely_video_page
```

判断：

- `ingest_empty`：页面探针没有发现媒体。修 `MediaVideoDomProbeScript` / `MediaVideoDeepProbeScript` / 结构化 JSON 扫描 / 播放器实例扫描。
- `hls` 或 `progressive` 很多，但 `capturedManifest=0`：可能只看到 URL，没有拿到页面 runtime 生成的 manifest。补通用 hook、JSON.parse 递归扫描、player source hooks。
- 只有 `blob`，没有 http/captured manifest：不能直接交给 AVPlayer。要抓 blob 背后的 HTTP source 或 manifest text。
- `signals` 多但 store 候选少：查 `MediaCandidateIdentity`、`MediaDiscoveryStore.merge*` 是否把新信号错误合并/丢失。

修复方向：

- 优先补通用探测能力，不写单站白名单。
- 常见入口：`JSON.parse` 递归扫描、`URL.createObjectURL(Blob)` 关联、Video.js/hls.js/DPlayer/JWPlayer 配置与 `src/loadSource` hooks、`performance`/DOM media element 扫描。

### 3. 看 validation 是否调度

关键行：

```text
media diagnostics validation_targets ... potential=39 selected=39 scheduled=39 ... hls=... capturedManifest=...
```

判断：

- `potential=0`：候选形态或证据不够。查 `MediaSignalClassificationService` 和 `MediaCandidateProjector`。
- `selected=0` 且 `fresh` 很高：已有 validation 还没过期，不要重复刷新页面；可以等 retry 或清 buffer 后只复现一次。
- `retryDelay` 很高：上一轮刚失败。不要连续刷真实站点。
- `scheduled=0` 且 selected>0：查 validation job 去重、generation、`markValidationInProgress`。

### 4. 看 HLS auth 和子资源形态

关键行：

```text
media diagnostics validation_auth ... cookie=true referer=true ua=true origin=true
media diagnostics validation_hls_shape ... rootShape=... childShape=...
media diagnostics validation_probe ... probe=hls_segment ok=false status=403 contentType=text/html
media diagnostics validation_probe_retry ... retry=no_range
```

判断：

- `cookie=false`：查 `WebCookieHeaderService`、request headers 合并、`WebCookieManager.fetchCookieSync`。
- `referer=false` / `ua=false` / `origin=false`：查 `authContext` 从 intercept/DOM/deep probe 到 candidate 的传递。
- child probe `403 text/html`，而 auth 四项都 true：native HTTP 被站点/CDN 拦。不要继续堆 Referer/Cookie；优先考虑 captured-HLS 可展示 + page-runtime fetch fallback。
- child route 无扩展，例如 `route;slashes=2;fileLen=144;ext=none`：不要只靠扩展名判断，manifest parse 后的图结构更可信。
- no-Range retry 也 `403 text/html`：不是 Range 问题，转 page-context fetch 或可控 fixture。

修复方向：

- `MediaCandidateValidationService`：把“manifest 已由页面捕获且可解析、非 DRM”与“native HTTP 预探子资源成功”分开。
- `NativeHlsMediaSourceLoaderService`：native HTTP 失败后才走 page fetch fallback。
- 不要为了一个站点写固定 host/base 规则，除非已经证明它是通用 URL 解析规则缺失。

### 5. 看 validation 结果和按钮投影

关键行：

```text
media diagnostics validation_result ... state=validated_playable kind=captured_hls_virtual_graph code=none
media diagnostics projection ... enabled=true ... takeover=1 playable=1 blocker=...
```

判断：

- `validation_result state=expired`：按钮不会出现。继续看 auth/probe，不要让用户点击。
- `validated_playable` 但 `projection takeover=0`：查 `MediaCandidateProjector.isTakeoverLaunchCandidate()` 和 `NativeVideoTakeoverResolveService.resolveCandidate()`。
- `playable>0` 但 `takeover=0`：resolver 拒绝了 projected candidate，通常是 evidence/sourceKind/status 不匹配。
- `takeover>0` 但 UI 没按钮：查 `BrowserVideoTakeoverFloatingButtonViewModel` 的表面 gate，例如 active tab、Home surface、sheet、fullscreen、native takeover active。
- `enabled=false`：设置/全量模式上下文问题，不是探测能力问题。

### 6. 看点击和原生播放

按钮出现后才看这一层。

关键行：

```text
native video floating action ... accepted=true
NativeVideoTakeover: launch resolved status=playable sourceKind=hls_manifest backend=av_player
NativeVideoAV: setSource begin ...
NativeHlsLoader: create/open/read/remote ...
NativeHlsPageFetch: fetch ... ok=true status=200 bytes=...
```

判断：

- floating action `accepted=false`：UI action gate 拒绝，先查 view model / active surface，不是播放器问题。
- launch `unsupported`：resolver 没产出 `NativeVideoPlaybackItem`，查 candidate projection 和 sourceKind。
- `NativeVideoAV setSource` 后没有 loader read：查 MediaSource/AVPlayer 初始化。
- `NativeHlsLoader remote status=403` 后没有 `NativeHlsPageFetch`：page-fetch bridge 没注册或 tabId/runtime 不 live。
- `NativeHlsPageFetch ok=true` 但 AVPlayer 仍失败：查 content type、offset/Content-Range、playlist rewrite、segment bytes。
- 系统 HLS 报 `HLS read cannot read`、`PullData error`、`PeekRange failed`：通常是 loader/proxy 没返回正确 bytes/header/range，不要回到 discovery 层。

## 症状到修复方向速查表

| 症状 | 关键日志 | 优先修复方向 |
| --- | --- | --- |
| 页面没按钮，日志 `ingest_empty` | `page_end_probe scheduled` 后无信号 | DOM/deep probe 覆盖、JSON.parse 递归扫描、播放器 hooks |
| 页面没按钮，但 HLS/capturedManifest 很多 | `validation_result expired/failed` | validation/auth/native HTTP probe/page-fetch fallback |
| `takeover=false` 但用户确认开关打开 | `page_end_probe ... takeover=false` | runtime context / preferences cache，不要质疑用户 |
| auth 缺失 | `validation_auth cookie=false` 等 | request headers/cookie/referer/UA/origin 传播 |
| native probe 403 HTML | `validation_probe status=403 contentType=text/html` | captured-HLS playable gate + page runtime fetch fallback |
| `validated_playable` 后仍无按钮 | `projection takeover=0 playable>0` | projector/resolver/floating button gate |
| 按钮可见但点击 toast unsupported | `launch resolved unsupported` | `NativeVideoTakeoverResolveService` sourceKind/proof |
| 进入播放器后失败 | `NativeVideoAV` / `NativeHlsLoader` / system HLS errors | MediaSourceLoader、本机代理、Range/header/content-type |
| 多次刷新后站点封禁 | 真实站点出现风控/403/ban | 立即停止 live-site 测试，改用已有日志或 fixture |

## 真实站点测试纪律

以后调视频网站，默认最多一次自动打开、一次人工复现。超过两轮没有新增证据，就停下来读日志或换 fixture。

停止 live-site 测试的条件：

- 出现 Cloudflare / 验证码 / 访问频率限制。
- 同一 URL 连续两次日志没有新增层级信息。
- 用户说站点已经封禁或账号/设备受限。
- validation 已经证明是 native HTTP 被站点拦截，继续刷新不会改变结论。

遇到以上条件后，记录：

- URL、时间、Aira 版本、设备 ID。
- 最后一份 raw log 路径。
- 断在哪一层。
- 下一步改本地 owner 或做 fixture。

## 可控 fixture 验证建议

当真实站点有风控，使用可控页面模拟“页面 runtime 能 fetch、native HTTP 失败/返回 HTML”的形态。不要继续刷真实站。

fixture 应覆盖：

- `<video>` 直接 MP4。
- hls.js / Video.js `loadSource("master.m3u8")`。
- manifest text 被页面转成 `Blob` URL。
- 子资源需要 Cookie/Referer/Origin。
- 子资源拒绝 Range，但无 Range 可取。
- 子资源 native HTTP 返回 `403 text/html`，页面 fetch 可取。

验证目标不是复刻某个站，而是证明 Aira 的通用链路：

```text
page runtime captured manifest
  -> validation marks captured HLS playable with degraded/page-fetch evidence
  -> floating button appears
  -> NativeHlsMediaSourceLoader reads manifest
  -> native HTTP fails
  -> NativeHlsPageFetchBridgeService succeeds
  -> AVPlayer receives correct bytes and headers
```

## 每次调试结束要留下的记录

在 active planning 文件或任务结尾记录：

- Build/version：例如 `0.2.7 (1000129)`。
- 设备：`hdc list targets` 的设备 ID。
- URL 或 fixture 名称。
- raw log 路径。
- 断层判断：runtime / discovery / validation / projection / launch / playback。
- 关键日志 3 到 8 行。
- 改动 owner 和文件。
- 是否安装到手机。
- 是否继续允许 live-site 测试。

示例：

```text
Version: 0.2.7 (1000129)
Device: 5MT0226114030639
URL: <redacted real video site>
Log: .tmp-navigation-capture/site-pid-49835-20260709-104440.log
Layer: validation
Evidence: ingest capturedManifest=9; validation_auth cookie/referer/ua/origin=true; hls_segment 403 text/html; projection takeover=0
Next owner: MediaCandidateValidationService + NativeHlsMediaSourceLoaderService
Live-site testing: stopped due to rate-limit risk
```
