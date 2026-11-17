# 下载历史修复回归记录（2026-11-17）

基线：`main` / `4ab9aca9`，验证对象为当前工作区的下载核心改动，而非逐个检出旧版本。通过下载相关提交标题、文件历史及关键提交差异，核对原来的故障场景在当前实现中是否仍受保护。

## 本次结论

- 发现并修复一项生产回归：主动下载 PDF、但尚未取得 ArkWeb 下载对象时，确认流程仍可能把它判成普通 PDF 页面导航并静默取消。
- 修复前，新增的跨模块测试中两个主动下载场景失败；修复后，未知 MIME / PDF MIME、主动下载 / 已有平台任务四种组合均通过，同时覆盖首次展示与恢复待确认提示。
- 33 项无需监听本地端口的检查通过。其中历史测试入口重放 9 组 ETS 测试及跨模块场景，共 36 个用例；一次性链接的应用调度检查为另外 6 个场景。这些用例数已包含在 33 项检查中，不应重复相加。
- 架构检查通过。
- 当前代码的 ArkTS 编译、HAP 打包和 debug 签名校验通过。已更新本地忽略的 `artifacts/aira-download-core-debug.hap`，包含本次 PDF 修复。版本为 `3.9.8 (1000589)`，SHA-256 为 `6ccd5e0bfb551f572ea5d43f4929bd74ab5e9e3bce583cbbf99ab4fdbde18b17`。
- 本地 debug profile 匹配 `com.aira.browser`，因此仅在构建期间临时覆盖包标识与签名配置，构建后恢复 Community 源文件。没有将签名材料写入跟踪文件，也没有变更提交用版本号；此构建不代表标准 `org.aira.browser` 签名发布验证。
- 真实 HTTP、原生下载/HLS 故障实验、HTTP/SOCKS 代理实验受本机执行环境的 `listen/bind EPERM` 限制，未完成。原生核心和 HLS 的主机测试程序已编译成功，但运行测试未通过网络实验的准备阶段。
- 未进行设备界面检查、截屏或真机下载验证，不能据此宣称全部真机场景通过。

## 提交与回归场景

以下脚本均位于 `scripts/`。表中的“通过”指主机侧行为测试或注明的静态检查，不等于真实 ArkWeb / 文件提供者 / 网络环境验证。

| 历史提交 | 原问题 / 保留的行为 | 当前验证与结果 |
| --- | --- | --- |
| `11151196` | 媒体资源识别、名称、时长，HLS 估算进度 | `check-aira-media-discovery.cjs`、`check-aira-media-resource-names.cjs`、`check-aira-media-durations.cjs`、`check-aira-hls-progress.cjs` 通过；真实 HLS 传输待补 |
| `90f7ce31` | 重复启动、加载期间暂停/取消、有限重试、恢复校验、批量管理 | `check-aira-download-lifecycle.cjs`、`check-aira-arkweb-download-recovery.cjs`、`check-aira-download-selection.cjs`、`check-aira-download-finalization.cjs` 通过；C++ 故障/Range/短写实验受阻 |
| `18ac1b3c` | 页面身份、Cookie、原任务恢复、加密 HLS、不得预请求或解释 HTML 跳转 | 请求上下文、恢复及一次性链接调度测试通过；真实 HTTP 与加密 HLS 实验受阻 |
| `8b35f869` | Documents 子文件不存在不应误判整个目录不可写；读写授权持久化 | `check-aira-download-directory-lifecycle.cjs`、`check-aira-download-destination.cjs` 通过，真实文件提供者待补 |
| `4f389298` | 网页下载继续使用原浏览器请求，不重复消费一次性链接 | `check-aira-arkweb-download-hold.cjs`、`check-aira-arkweb-download-recovery.cjs`、`check-aira-arkweb-manual-start.cjs` 通过；一次性链接调度 6 个场景通过，真实 HTTP 受阻 |
| `401189cc` | 自定义目录失效后不留下空文件 | 目录、目标与完成校验行为测试通过；`check-aira-download-export-ghost-guard.cjs` 静态防护通过。旧的静默回退策略已被冻结目标、失败后重新选择策略取代 |
| `92aa6d4c` | 默认下载保存到实际可用位置，展示真实路径 | 目标解析、完成提交、重名文件实际名称测试通过。不能把旧的直接写入目录策略视为当前授权策略 |
| `2929a53b` | 点击 PDF 下载无反应 | 原始 PDF 策略用例通过；本次额外发现并修复“主动下载尚无平台快照”的跨模块回归，4 个组合通过 |
| `c90df925`、`88ea7937`、`c8aa29e4` | 广告拦截的合成响应/子框架分类误触发下载 | `check-aira-adblock-download-response.cjs` 静态响应约束及原始 3 组广告/子框架行为测试通过 |
| `b879417b` | Office 的 POST 和 blob/data 下载不能被重放为 GET | ArkWeb 驱动选择、原任务恢复、上下文丢失不得重放测试通过；真实 Office 页面和渲染器进程恢复待补 |
| `f9997d04` | 下载使用应用内 HTTP/SOCKS 代理 | 原生请求上下文测试通过；真实代理实验在监听端口时被拒绝，未判定通过。当前普通下载走 ArkWeb，还需真机验证其页面代理一致性 |
| `31c3cb0e`、`c9974b1f` | 下载目录选择与保存设置，隐私窗口使用设备下载设置 | 目录生命周期与原始隐私设置/导出/窗口清理测试通过；系统选择器实际打开待真机验证 |
| `476f1743` | 桌面下载入口与最近记录状态、取消记录、数量上限 | 原始 `DownloadToolbarIndicatorViewModel`、`DownloadRecentRecordsViewModel` 测试通过 |
| `98dc0d50` | 下载不能把当前页面倒退；同文档恢复；同一提示只回退一次 | `check-aira-download-rewind-does-not-move-page.cjs` 静态约束、同文档恢复测试以及本次主动 PDF 不改变页面的行为测试通过 |
| `03dbaa4f` | 下载列表批量选择 | 原始选择模式测试、下载批量选择与媒体选择测试通过 |
| `6b056bf2` | 打开共享 HTML 保留原始响应 | `check-aira-shared-html-viewer.cjs` 通过；下载 HTML 不执行其中 JS 跳转的调度场景通过 |
| `7448829d` | 下载设置复用一个 `CustomDialogController`，避免 PC 崩溃 | 差异和当前实现核对：成员初始化、重复打开递增 revision 仍在；未进行界面运行复测 |
| `bb351436` | 矮窗口下确认按钮被内容挤出 | 差异和当前实现核对：内容滚动、操作区独立、按窗口预留高度仍在；未进行界面运行复测 |

## 本次代码与测试修正

1. `DownloadRuntimeService` 为明确的主动下载传递独立的 `isUserInitiatedDownload` 标记，保留 `isPlatformDownload` 的原始含义；首次提示和恢复提示均携带该标记。
2. `BrowserDownloadConfirmOverlayCoordinator` 对该标记保留下载确认和当前文档，不再套用普通内联 PDF 导航的忽略规则。普通 PDF 页面导航仍由原策略处理。
3. 新增 `check-aira-download-history.cjs`：运行生产策略/服务及原始 ETS 用例。资源查询、平台模块和存储环境由主机适配，不读取设备数据。它是主机侧回放，未替代真机 Hypium。
4. 旧 `DownloadPrivacyPolicy.test.ets` 使用了已移除的任务查询类型、扁平时间字段，且文件适配器缺少新接口。改为当前任务实体和有明确源文件/导出文件判定的测试适配器，保留隔离、导出及清理断言。
5. 一次性链接测试采用真实 `DownloadV2Engine` 与内存仓库，补齐目标快照及授权接口，检查真实状态转换、来源、页面 UA、Referer、Cookie、自定义头和驱动选择。`--control-only` 显式使用内存响应；默认模式仍必须运行真实本地 HTTP，不会遇到权限错误后自动降级为假通过。
6. 历史用例和广告响应防护加入统一下载检查入口；一次性链接调度先执行，真实 HTTP、原生和代理实验仍是完整门禁的必需项。

## 策略变化与尚未完成的验证

- 普通手动、资源、MP4、批量下载使用来源页面的 ArkWeb；HLS、明确自定义请求头及原有原生任务仍保留 native 能力。旧的“默认手动下载必须走 curl”不是需要恢复的行为。
- ArkWeb 网络错误不再自动转 curl 重放；恢复同一个浏览器任务。一次性链接、POST 和渲染器 URL 的请求身份优先。
- 已确认任务的保存位置与授权被冻结，授权失效时明确失败并允许重新选择，不静默改存其他目录。无空文件、无假成功、展示真实路径的要求仍保留。
- 主机平台适配不能证明 ArkWeb 的真实 Cookie、POST body、代理、断网/后台/进程重启行为，也不能证明 Documents 提供者的真机授权状态。以上应在手机上补测，不能只看单元测试通过。

完整验证入口：

```sh
./scripts/check-aira-downloads.sh
./scripts/check-architecture-guardrails.sh
```

第一条包含真实端口监听；当前受限执行环境不能完成整条命令。需要在允许本机监听的终端中运行，任何失败均应保留，不得通过跳过网络测试宣称完整门禁成功。
