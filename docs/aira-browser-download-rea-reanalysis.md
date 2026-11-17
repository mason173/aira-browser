# Aira 下载对齐华为：REA 重新分析

日期：2026-11-17  
分析基线：Aira main，HEAD 4ab9aca9034a41dfc9c86f58e2ded25a73342218；本地华为浏览器 phone HAP 5.1.9.315。  
状态：本文保留实施前的静态复核与最小复现证据；后续代码已修改，实现范围和验证结果见 [实施规格第 8 节](aira-browser-download-parity-spec.md#8-本轮实现记录2026-11-17)。本文缺陷表描述修复前快照，设备运行时等价仍未验证。

## 1. 结论

此前“架构更规范，只需补几个兜底”的判断撤回。分层、枚举和双驱动的数量不能证明下载可靠。Aira 当前最重要的差距是**应用任务状态、实际传输状态、保存目标与恢复上下文没有形成一致的生命周期**。

重新对齐的主线：

1. 从平台首次回调就接管任务，待确认期间也要承接事件。
2. 排队、等待 Wi-Fi、暂停必须落实到实际传输控制，不能只改列表状态。
3. 网页下载保持 ArkWeb 任务所有权；网络中断与用户暂停分开，恢复原任务，避免自动切换引擎从零重放。
4. 保存用户意图、平台恢复凭据、授权目标和暂停原因；不能只保存一个进度数字。
5. 文件完成、导出成功、通知完成形成闭环；错误原因必须驱动可用操作和用户提示。

用户已明确目标为对齐华为下载核心：传输引擎、请求上下文、任务调度与恢复、持久化、后台和文件完整落地；Aira 现有交互保持不变。参考对象固定为本地 5.1.9.315 手机行为，PC 分支单列；不能把这一份样本等同于所有新版华为浏览器。实施规格见 [aira-browser-download-parity-spec.md](aira-browser-download-parity-spec.md)。

## 2. 方法、证据与能力边界

本轮读取并使用 morluto/rea 的 reverse-engineer-anything skill，安装包版本 6.9.0，skill metadata version 62。REA 负责包身份、完整性与原生导出表；ArkTS 控制流由官方 SDK 的 ark_disasm 和原始函数体核对；Aira 源码使用普通仓库工具分析。

| 标记 | 含义 | 能证明什么 |
| --- | --- | --- |
| R | 本轮 REA Evidence | 样本身份、包条目、符号声明及明确的工具边界 |
| A | 同一 ABC 重新反汇编后的函数体 | 静态分支、调用关系、字段与常量 |
| S | 当前 Aira 源码 | 应用实际实现的分支与数据流 |
| P | 实际 ETS 转译后，注入依赖/事件的复现 | 应用代码在指定输入下的结果；不代表真实 ArkWeb 回调时序 |
| O | 华为官方文档及 SDK 声明 | 公开平台 API 契约；版本限制仍须匹配 |
| U | 未观察到的运行时行为 | 需要目标设备、同条件对照或进一步分析 |

### 2.1 本轮身份校验

本地样本目录在下文记作 SAMPLE，不把 HAP、反汇编内容或原生库复制进公开仓库。

| 文件 | SHA-256 |
| --- | --- |
| HuaweiBrowser-phone.hap | d1ce178957898014080d13872734bdf8e1ebae997ce58dc98ff564e1bf8f8a09 |
| HAP 内 ets/modules.abc | fa5dbe2a1f4ea2ae04b98ecec36e62715d30af63edd887e4fa125492814ea6d4 |
| arm64-v8a/libbrowser_service.so | 52a4353656115caf53fbf83a798647e96025822220a62aae61bba11b9c2b69f4 |
| 重新生成的 modules.pa | 3b23428bbb8b1cbf2fb84117ba9dd8f76391952e5a8736960fad2d0ba9b72f07 |
| 本机 SDK @ohos.web.webview.d.ts | 50a9f20ed47de94e27dbb4d09603764cfdc543098f06955ff962acda4bc5825c |

使用 ZIP 成员读取核对 ABC、原生库与已解包文件，哈希一致。使用官方 ark_disasm 重新生成完整 modules.pa，其哈希与旧反汇编完全一致。因此可以使用旧提取文件的行号定位，同时依赖本轮重新验证的字节码身份。

### 2.2 REA 证据

| 操作 | 完整父 Evidence ID | 结果 |
| --- | --- | --- |
| inspect-artifact phone HAP | ev_6580cc08a2a65ab3cb8c2445b9e3c79c96b9bd5cea2b406c779d21ecb29d47cc | 877 节点、929 occurrence、928 边；container-entries 范围完整，integrity contradictions 为 0 |
| 包条目 inventory | ev_e899fbb8f5f9fb9fdfe1c5be191c63eb0039488300b97c15fc8c6c4e6ff13b9a | 与同一 HAP 身份绑定的静态条目证据 |
| inspect-native-exports bridge | ev_f0b5f6cdc9861fd9d9cba5a53ea964019b40a839d41d43f0290e6c29975f6679 | ELF64 arm64，2687 个导出；符号表范围完整 |

导出表内五个明确命名族：ArkWebExtensionDownloadsController 32、WebDownloadItem 31、WebDownloader 9、WebDownload 8、WebDownloadManager 1，共 81。旧报告按 download 子串得到的 86 还包含其它名称，不应把 86 全称为同一下载 API 家族。

PauseBeforeDownload、CancelBeforeDownload、ResumeBeforeDownload、ETag、SetFileRenameOption 等符号确实存在。但 REA 输出明确限制：**符号表不证明运行时可达、已加载、可安全调用或公开可用**。不能由 setter 的存在推出“start 后一定无效”，也不能由 ETag 字段存在证明条件续传的全部实现。

本机没有可用的 Ghidra/Hopper/IDA 深度分析引擎。本轮尝试 REA inspect-with-objdump，进程所有权预检在启动 objdump 前因 ps/EPERM 被拒绝；未得到该函数汇编，没有绕过此限制。REA 包和导出分析正常完成。ArkTS 分析来自官方反汇编工具，不伪装成 REA 原生反编译。

未运行浏览器/设备、未抓屏、未读取设备用户数据。本轮所有 UI 精确布局、实际流量、通知效果及真实恢复时序仍为 U。

## 3. 旧方案必须撤回或纠正的结论

以下 work 路径均相对 SAMPLE；行号以本轮确认哈希的文件为准。

| 旧判断 | 重新核对的事实 | 证据 |
| --- | --- | --- |
| 华为网络失败就是失败，等待用户重试 | NETWORK_FAILED/TIMEOUT/DISCONNECTED 映射 Pause，并写网络暂停原因；网络恢复会筛选任务继续 | A：work/dl_delegate.pa:482、2813；work/dl_mgr.pa:101、7422 |
| 华为恢复依靠 catch 猜调用方式 | 明确按对象来源 UnSerialize 或状态 CANCELED/INTERRUPTED 选 manager.resumeDownload，其余用 item.resume；catch 只记日志 | A：work/dl_sdk.pa:758、889 |
| 华为重启后仅用户点击才恢复 | recoverTask 按网络恢复符合状态/暂停原因的记录，先激活权限、反序列化，再 resumeImmediately | A：work/dl_mgr.pa:4802、4936、8865、8933、9013 |
| startPhoneDownload 是 delegate 缺失时独立兜底 | 读到的调用来自 setWebDownloadDelegate 回调，参数是已有 downloadTaskInfo，最终添加该任务 | A：work/modules.pa:5420394、5420415、5420459、5485047、5485807 |
| 华为证明应做 1.5 秒 URL 自动重放 | 上述调用链没有提供该证据；自动 watchdog 是新增设计，且可能重复消耗一次性 URL | A + U：撤销旧 T2 依据 |
| 36 分支明确取消任务 | 页面 delegate 分支只有 toast 和 return；没有 cancel。manager delegate 分支也不同 | A：work/dl_delegate.pa:1019、1037、1192 |
| 权限/空间/不支持 Range 一律不可重试 | 分档函数不含 retriable；AccessDeny 后续被压回 Fail；没有读到 SERVER_NO_RANGE 的专门禁止重试分支 | A：work/dl_delegate.pa:482、2954；work/dl_mgr.pa:5832 |
| PENDING 序列化即可保证任何阶段恢复 | 华为建任务时尝试序列化，但可能返回空；建任务并不等于此刻已写数据库，不能证明恢复成功 | A：work/dl_mgr.pa:1976、2007、6724；work/dl_sdk.pa:250、959、1075 |
| 确认弹窗使 Aira awaiting_confirmation 被更新成 queued | 常规入口在确认前没有 engine task；实际问题是事件无人承接，false 被转换成处理失败提示 | S + P：Service:316、503、971、1528；Runtime:872 |
| 重复下载按同 URL 判断 | checkDownloadTaskIsExist 通过目标路径查记录，并排除同 requestId | A：work/dl_fileutils.pa:470；work/dl_dao.pa:1604 |
| 文件名限制 2048 字符 | 主体按 UTF-8 字节截断，预算使用 255 并预留后缀；后缀预算使用 length，不能夸大为所有 Unicode 都已正确处理 | A：work/modules.pa:3307477、3307555、3307931 |
| 手机默认保存到 filesDir/download | 主链读取配置，必要时用 DOWNLOAD 模式的 DocumentViewPicker 获取目录；filesDir/download 是另一个函数 | A：work/dl_fileutils.pa:990、1314、1440；work/modules.pa:3308176 |
| blob 缓存为空后走保存缓存流程 | 缓存为空时调用下载回调并返回；缓存非空才命名、选目录并写盘 | A：work/dl_logic.pa:1556、1660、2296 |
| 该缓存逻辑覆盖任意 blob PDF/CSV | 已读到的是图片缓存保存，通过自有 webExtension.getImageFromCache；不能推广为通用 blob 能力 | A：work/modules.pa:3133655；其它类型 U |
| URI 根路径正则就是完整防穿越 | 非 media 特例需根路径匹配后 stat 成功；负向前瞻仅排除重复根字符串 | A：work/dl_fileutils.pa:128、633 |
| 未搜到 HLS/m3u8 说明华为没有视频下载能力 | 只能证明选定文本未命中；视频菜单可见 logic.download 调用 | A：work/modules.pa:5441310；更深媒体链 U |
| 默认并发 3、已有后台 API，所以基本一致 | 华为 PC UI 可放行并发；后台 map 含 Waiting/InProgress，不能等同于 Aira 仅 running 的集合 | A：work/dl_mgr.pa:1327；work/modules.pa:3355459 |

上表中的 Service / Runtime 分别指 Aira 的 DownloadV2Service.ets / DownloadRuntimeService.ets，完整路径见下一节。

## 4. 华为的实际机制

### 4.1 入口与待确认阶段

页面 delegate 创建 DownloadTask，查已有记录，创建任务信息，再分 PC pause 和手机 prepareDeeplink，随后进入用户确认/目录处理。全局 manager delegate 处理恢复任务，分支与页面入口不同。

华为官方公开契约说明：WebDownloadItem.start 指定落点；调用前 PENDING 任务仍可能下载到临时目录。若要阻止这一阶段传输，官方提供 cancel 后 manager.resumeDownload 的路径。pause 声明可能抛 17100019。因此“暂时不调用 start 就不会下载”是错误模型；也不能仅凭华为 PC 分支或原生符号，把 PENDING pause 当成所有设备的保证。

对应 O：

- [管理页面下载](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/web-download)
- [WebDownloadItem](https://developer.huawei.com/consumer/en/doc/harmonyos-references/arkts-apis-webview-webdownloaditem/)
- [WebDownloadDelegate](https://developer.huawei.com/consumer/en/doc/harmonyos-references/arkts-apis-webview-webdownloaddelegate/)

### 4.2 暂停原因是恢复策略的关键

| 状态/原因 | 华为静态恢复路径 |
| --- | --- |
| 手动暂停，reason 2 | 不被网络变化自动恢复筛选选中 |
| 网络暂停，reason 3 | 网络恢复后符合条件可继续 |
| 仅 Wi-Fi 暂停，reason 4 | 合适网络恢复后符合条件可继续 |
| 原运行中/等待中记录 | 网络变化和启动恢复路径可重新调度 |
| 真失败或无效恢复凭据 | 不可直接用上面的自动恢复条件替代，需独立处理 |

网络失败回调内的一秒 timer 只是延迟检查联网并 toast，不是定时重试。自动恢复来自网络事件与启动恢复逻辑。不能把“没有换成 libcurl”误解成“没有自动恢复”。

### 4.3 续传、路径与持久化

恢复以原 WebDownloadItem/序列化数据为依据。华为区分同会话暂停对象和反序列化/中断对象，不把 receivedBytes 当成可移交给另一引擎的顺序偏移量。

授权恢复有 authType：有的记录激活父目录，有的激活文件 URI。命名同时检查实际文件和未完成记录占用。serialize 有约 1.5 MiB 的保护上限，空 token 需要被显式处理。

进度更新使用 500 ms 时间阈值，并允许状态变化和时钟回退立即通过。更新包括恢复元数据；它不是让所有事件等待 500 ms。

data URL 链路有 base64 和经 decodeURI 再编码的路径，最终缓冲写盘。图片缓存是独立路径。不能据此承诺任意大文件、任意 binary percent 编码和任意 blob 导出都可用。

### 4.4 公开主动下载 API 可以用于对齐，但须正确理解

官方指南明确展示 controller.startDownload → 已注册 delegate 的通知链，并说明 referrer 按当前页面与 Referrer Policy 计算。旧 H1 不再是“该 API 有没有回调”的纯未知问题；真正要验的是 Aira 的控制器归属、回调去重、隐私边界及目标版本时序。

公开 startDownload 的签名不提供任意 header 参数。**不接受自定义 header 参数不等于不使用 Web 会话上下文**，也不意味着捕获到 UA/referrer 就必须改用 libcurl。需要区分浏览器默认会话与调用方额外指定的请求要求。

- [WebviewController](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-webview-webviewcontroller)
- 本机 SDK：startDownload:3909；start/pause/resume:5632–5684；serialize/deserialize:5729–5741。
- getOriginalUrl/getReferrerUrl 在本机声明标记 since 24，实施时要按项目最低 API 兼容，不能直接照最新声明无条件调用。

## 5. Aira 当前缺陷与风险

路径均相对 AiraBrowser/entry/src/main/ets/。这里区分“源码已确认的缺陷”和“需要设备确认影响范围的风险”。

| 编号 | 发现与影响 | 证据位置 / 等级 |
| --- | --- | --- |
| F01 | 确认前只存在 RequestCapture 条目，没有 engine task。收到后续事件时无任务返回 false，Runtime 误报处理失败；终态也缺少明确承接 | services/downloadv2/DownloadV2Service.ets:316、503、1528；services/download/DownloadRuntimeService.ets:872；S/P |
| F02 | 准入拒绝仅保存 queued 原因并返回，未停止已存在的 ArkWeb item。应用排队不保证实际网络停住 | DownloadV2Service.ets:1063、1143；S/O，实际流量 U |
| F03 | 网络变化只调度 queued；缺少运行中 Wi-Fi→蜂窝暂停及按原因恢复的完整闭环 | DownloadV2Service.ets:188；services/download/DownloadNetworkPolicyService.ets:106、188；S |
| F04 | Repository.cloneTask 丢 originalUrl 和 expectedTotalBytes；回读后原始 URL 丢失，替换下载长度校验条件失去字段 | data/downloadv2/DownloadV2Repository.ets:165；DownloadV2Service.ets:1542；S/P |
| F05 | createTaskFromCapturedRequest await 启动后优先返回旧 preparedTask，可能把实际失败报告成仍排队/确认成功 | DownloadV2Service.ets:1085；DownloadRuntimeService.ets:585、736；S |
| F06 | 网络错误 20 且部分进度时自动将 ArkWeb 改成 libcurl，从零重下并清平台 token；恢复原任务的语义被替换 | DownloadV2Service.ets:1827；S，站点受影响程度 U |
| F07 | 等待确认不持久化；已确认待调度的 prepared task 又清 id/token。未回填前退出可能丢恢复上下文，仅开放 PENDING serialize 不足 | DownloadV2Service.ets:248、1055；DownloadV2Repository.ets:359；platform/download/ArkWebDownloadBridge.ets:595；S |
| F08 | 错误统一 unknown；UI 常显示数字码；retry 权限仅对 context_lost 特例处理。只加错误 mapper 不能改变按钮和实际动作 | DownloadV2Service.ets:779、2399；DownloadRuntimeService.ets:1226；core/download/DownloadManagerViewModel.ets:334；S |
| F09 | 首次后台申请失败仍缓存 backgroundState，后续直接复用失败 state；同批任务未归零前没有再次申请 | services/downloadv2/DownloadV2SystemNotificationService.ets:122、142、160；S/P |
| F10 | 每个变化引发全量任务快照加入持久化 Promise 链，再全量 JSON、同步 flush；进度和关键状态未分层合并 | DownloadV2Repository.ets:341；data/downloadv2/DownloadV2RecordStore.ets:243；S |
| F11 | 回调建任务使用当时 activeBoundary，记录 onDownloadStart 时 tabId 被忽略；后台页延迟下载存在来源/隐私错绑风险 | DownloadRuntimeService.ets:614、887；ArkWebDownloadBridge.ets:373；S，实际错绑 U |
| F12 | INTERRUPTED 映射为 FAILED，但现有 adapter 仍支持序列化后 manager resume。差距是原因、操作和显示压平，不是完全没有续传 | ArkWebDownloadBridge.ets:491、625、647；DownloadV2Service.ets:2430；S |
| F13 | Engine 非法状态转移返回旧 task；调用方将非 undefined 当成功，可能记录 applied 并继续副作用 | core/downloadv2/DownloadV2Engine.ets:89；DownloadV2Service.ets:1642；S |

F10 不应夸大成“每 250 ms 无变化也必写盘”：LibcurlDownloadAdapter.ets:671 有 changed gate。问题是变化事件频繁时的全量快照队列与同步写入。

F08 也不能简单把 permission/storage/server 全部永久禁用重试。空间释放、权限修复、目录重选后应有相应动作；这是需要设计并实测的恢复路径。

## 6. 本轮执行的验证

### 6.1 新的应用代码复现

使用仓库自己的 TypeScript 转译器载入实际 ETS 类/方法，替换平台依赖，不修改业务源文件：

| 探针 | 输入 | 实际结果 |
| --- | --- | --- |
| Repository round trip | originalUrl 有值、expectedTotalBytes=1000，执行真实 upsert/findOne | 两字段变 undefined；totalBytes 仍为 1000 |
| 确认前事件 | 真实 consumePlatformEvent/syncTaskFromPlatformEvent 与 Runtime 回调；注入 before_download → updated(PENDING) | 一个待确认请求、没有 engine task，产生 download_process_failed |
| 后台首次失败 | 真实 ensureBackgroundTask；第一次平台调用注入异常，第二次本可成功 | 调用方法两次，但平台 API 只调用一次，systemProxyActive=false |

探针退出码 0 表示成功复现并断言了上述缺陷，**不是修复通过**。确认前事件探针不证明真实 ArkWeb 必定发送这个序列；后台探针不代表实际系统申请结果。

### 6.2 现有回归

以下四项在未修改下载源码的情况下全部通过：

- node scripts/check-aira-arkweb-download-recovery.cjs
- node scripts/check-aira-download-request-context.cjs
- node scripts/check-aira-download-directory-lifecycle.cjs
- node scripts/check-aira-download-export-ghost-guard.cjs

通过的含义受测试替身限制。比如 recovery 脚本使用自己的任务容器，未覆盖真实 Repository.cloneTask 的字段损失；也未证明 PENDING 状态真实网络静止。今后的回归要覆盖 Repository + Service + Bridge 的联合边界，而不能继续仅凭现有绿灯宣称可靠。

此次只更新分析文档，没有业务代码变更，因此未跑签名构建，没有安装测试包。

## 7. 完全对齐还缺什么

| 问题 | 当前状态 | 下一步需要的证据 |
| --- | --- | --- |
| 错误映射、暂停原因、静态恢复分支 | 已回答，A | 在目标系统复核可见文案/按钮和真实重试结果 |
| 待确认期间事件与临时下载 | 部分回答，S/P/O | 同版本手机的事件顺序、字节增长、关闭页面后的表现 |
| Wi-Fi/蜂窝/断网切换 | 华为策略已重建，A；Aira 缺口已定位，S | 同一慢速下载的网络切换与恢复流量 |
| 重启、保存目录授权、稀疏续传 | 部分回答，A/S/O | 冷启动恢复、权限撤销、文件最终哈希 |
| 主动下载会话继承 | API 通路已回答，O | 登录 cookie、referrer、UA、重定向、私密窗口的实际请求 |
| 重复任务与路径占用 | 已回答静态主链，A | 重复点击时对话框/按钮/命名的手机实际行为 |
| blob/data/图片缓存 | 已回答限定路径，A；通用覆盖未知 | 页面导出 PDF/CSV、blob 失效、data 编码边界 |
| 通知、后台、锁屏与 UI | 只有代码证据，A/S/P | 手机实际生命周期和视觉/交互对照 |
| 原生下载引擎内部重试/分片算法 | 未回答，U | 可用的深度分析或受控运行时证据；不以符号代替结论 |

本轮可以形成可执行的修复顺序，但不能宣布“已完整逆向华为”或“Aira 已完全对齐”。新版规格把上述未知项保留为验收门槛。
