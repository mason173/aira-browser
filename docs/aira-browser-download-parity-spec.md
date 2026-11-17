# Aira 下载核心对齐华为：实施规格

日期：2026-11-17  
状态：按用户最新要求仅对齐下载核心，保留 Aira 下载界面。普通主动入口改为 ArkWeb；25 个可运行的下载检查脚本与 ArkTS/未签名 HAP 编译通过，完整网络门禁、签名产物和设备行为仍待验证。  
证据入口：[REA 重新分析](aira-browser-download-rea-reanalysis.md)。旧版 D1/D2/D3 和 T0–T8 不再作为实施指令，尤其不得按旧 D1 删除恢复后让网络错误永久留在失败态。

## 1. 对齐目标与证据规则

以本地华为浏览器 5.1.9.315 手机样本为行为参考，重点对齐主动下载引擎、来源会话、任务准入、暂停、网络变化、恢复、重试、持久化及文件可用的闭环。确认与列表仅消费这些核心状态，不继续复刻布局、颜色、图标、动画或菜单样式。此前视觉改动已恢复，不能作为本轮交付项。PC 分支单独解释，不把 PC 的 pending pause 或并发策略套到手机。

静态控制流和官方 API 文档支持引擎选择及调用顺序，设备行为仍需同一系统/ArkWeb 版本下验证。公开 API 无法直接覆盖的内部能力要列出差异，不能调用华为私有符号或宣称已等价。设备行为验证可使用请求记录、事件、文件和哈希；截图与视觉对照不是本轮交付门槛。

不要因为 Aira 有状态机、双驱动而预先宣布其更好。不要因为华为用 RDB 就预先要求迁移。内部结构服务于行为正确性，相关取舍要有测试与实际成本依据。

本轮明确不做自动 GET watchdog：现有华为证据没有证明该机制。若后续确有未被接管的用户请求，优先定位入口/控制器/回调丢失，再设计不会重复消费原请求的处理。

### 1.1 主动下载的静态证据

下列行号均为本地样本 `work/modules.pa` 的原始行号，不引用旧分析伪代码作为实现证据。样本文件不提交到源码仓库。

| 观察点 | 原始位置 | 能确认的事实 |
| --- | --- | --- |
| DownloadLogic 方法表 | 4457440 | 没有 `download(url)` 或 `startDownload`；有 dataUrlDownload、图片缓存和任务操作，不能虚构统一 URL 发起 API |
| DownloadItem 确认重新下载 | 5562799；startDownload 调用 5562945，另一分支 5563148 | 从当前 tab 取得 webController，登记原记录信息后调用 `controller.startDownload(info.url)`；无 controller 则返回 |
| PC 保存图片回调 | 5824073；调用 5824152 | 依 tabId 取得 Web controller，再调用 startDownload(url)；不是无页面全局下载器 |
| DownloadApiImpl.startDownloadTaskInfo | 3353425；addDownloadTask 调用 3353827 | 对已有 taskInfo 检查网络、目录与空间，然后接入任务管理；不是以 URL 创建网络请求 |
| WebComponent.startDownload | 5466855 | 同样接收已有任务并做准入；不能因方法同名就当作 WebviewController API |
| controller delegate 绑定 | WebComponentController.setWebDownloadDelegate，5484649 | 为具体 Web controller 注册下载委托，传入其隐私边界 |
| DownloadTask.start | 4667927 | 选择原 before item 或 current item，向 item.start 传入文件路径；不会自行构造 HTTP 请求 |
| 扩展下载适配器 | DownloadAdapter.init，3070802；getDownloadId，3071524 | 向私有 ExWebExtensionDownloadsController 设置操作委托，映射已有下载记录；ETS 委托没有 download(url, headers) 方法 |
| 视频下载 | VideoPlayerPageLogic.download，5435416；TabVideoPlayer.download，5523417；ArkwebVideoPlayer.download，5201765 | 逐级调用已有播放器的零参数 download，并非从 ETS 抽 URL 后用 HTTP 客户端抓取 |
| 视频上下文来源 | WebPageController 回调 5513187；构造 ArkwebVideoPlayer 5513223；ImportSo 3134696 | 页面原生全屏事件提供 player controller，最终进入私有 mediaPlayerController.download |

ImportSo 的 `c9` 来自 `libbrowser_service.so`（模块导入 95937）；ExWebExtension 构造见 3133510，
ExWebExtensionDownloadsController 构造见 3131197。原生包存在 `NWebMediaPlayerController_Download`、
`WebDownloader_StartDownload` 和 `ArkWeb_SetExtraHeadersMap` 导出，只能证明接口存在，不能据此宣称某个 ETS 下载入口已调用它们或支持任意请求头。

视频路径保留原生播放器对象这一事实支持“依赖页面/媒体上下文”的判断；具体 Cookie、鉴权、MP4/HLS 分流与媒体合并仍在私有实现内，不能由 ETS 推定。样本中未找到独立的 MP4/m3u8 下载分支或无页面手工 URL 下载创建链，不能把静态未发现写成平台绝对不支持。

## 2. 下载生命周期约束

### 2.1 从首次平台事件起有可追踪的任务

一个用户下载意图至少关联以下信息，具体类型放在现有 domain/features/service owners：

| 信息 | 必须保留的语义 |
| --- | --- |
| intentId / source | 页面或主动入口、来源 controller/tab、窗口、profile、privacy、原始 URL、请求方法 |
| platform ownership | ArkWeb guid、对象来源（live/deserialized）、有效 token、最新平台快照、当前传输尝试编号 |
| consent / admission | 未确认、已确认、用户取消；等待并发/等待网络/允许传输，不混为一个 queued |
| suspension reason | user、network、wifi_policy、concurrency、confirmation；决定自动恢复资格 |
| target | 目标 URI/路径、展示名称、文件冲突预留、授权类型及授权 URI |
| outcome | 网络接收完成、文件导出中、文件可用、恢复受阻、失败；不提前宣告完成 |

这些是设计约束，不声称华为使用相同字段名。仍由现有 Service/Engine/Repository 编排；页面只展示和派发用户操作。

首次 before_download 即关联生命周期。可保留待确认容器或创建任务，但后续 updated/failed/finished/canceled 都必须有明确处理者。未知/过期事件应被识别，不能把所有 handled=false 都 toast 为下载失败。

事件处理结果区分 applied、ignored/stale、rejected、error；不能因 Engine 返回旧 task 就记成 applied。异步启动返回实际 outcome 或最新任务，不返回启动前的 queued 快照。

### 2.2 准入决定必须控制实际传输

ArkWeb 在 start 指定路径前可能已经写临时文件。需要验证并实现：等待确认、Wi-Fi 限制、并发排队时，是否允许该平台任务继续传输；若不允许，必须执行公开 API 支持的控制操作并保留恢复上下文。

公开文档给出 cancel → manager.resumeDownload 路径。它不等于用户最终取消：业务意图、恢复资格与平台暂时中断需要分开。不能只加 item.pause 而忽略 17100019，不能把“没调用 start”视为“没发网络”。POST、一次性 URL 和 blob 的恢复代价必须先验证，禁止盲目重新 GET。

为每个传输尝试保留身份，处理由暂停/取消引起的同步或延迟回调，防止旧事件破坏后续尝试。取消等待任务必须释放平台对象、路径预留和未使用的临时文件。

### 2.3 网络暂停与用户暂停分开

华为已核实策略：网络类 20/21/22 转网络暂停；网络变化和启动恢复会继续符合条件的运行/等待/网络或 Wi-Fi 暂停记录；手动暂停不自动继续。

Aira 应按暂停原因统一：网络切换时对运行任务执行控制，网络恢复时只重新调度符合资格的任务，并重新检查保存权限和并发。

旧 ArkWeb 网络错误 20 后切 libcurl、清 token、另建 `.http1` 的自动策略已移除，由同 owner 网络暂停与恢复替代。错误来源必须分别解释；curl 的数字 20/21/22 不能套 ArkWeb 的网络暂停规则。回归应验证新行为，不保留自动换引擎预期。

### 2.4 普通下载统一由 ArkWeb 持有

| 场景 | 目标路径 |
| --- | --- |
| 页面点击、附件重定向、POST | 保持原 ArkWeb task 与会话；不重放未知 body |
| 手动 URL、页面长按下载链接/图片 | 所属 controller.startDownload → Bridge 绑定原生/应用 GUID → Service 同一任务；保留来源/referrer/隐私 |
| 普通 MP4/WebM、非 HLS 嗅探资源、无自定义 headers 的 GM_download、批量 | 同样使用来源 controller.startDownload；入口名称或普通媒体 MIME 不决定 native owner |
| 调用方明确要求公开 startDownload 无法等价表达的自定义 headers | 显式标记专用 libcurl 原因，保留原请求能力，不把页面 UA/referrer/Cookie 兜底证据误当作该原因 |
| HLS 清单、密钥、分片 | 保留 native HLS 计划、解密、合并与恢复路径，不能简单下载 m3u8 文本冒充视频 |
| 旧版已持久化 libcurl 任务 | 按原 owner 恢复；不通过迁移或重试隐式创建新 ArkWeb 请求 |
| data/blob | 优先平台路径；按已验证的编码/页面上下文能力提供受限补充，不能外推华为图片缓存接口 |

Service 的新普通任务默认 owner 是 arkweb，只有明确的特殊能力原因进入 native。仅有平台 before item 时优先保留原 item，不能为了统一主动入口而重发 URL。

公开 `startDownload(url: string)` 不提供 headers/body 参数，controller 必须已绑定 Web 组件。官方指南说明它按当前显示 URL 与默认 Referrer Policy 计算 referrer。因此来源 controller 必须在用户发起时冻结；换 tab、普通/私密分区或 URL 相同不能成为借用别的 controller 的理由。

没有来源页面的 URL 仍需要应用提供已挂载且隐私边界正确的 Web controller；未具备时明确等待或失败，不静默切回 libcurl。专用空白 Web 是公开 API 可行的宿主方案，但不能声称它保留原网页 referrer、POST、blob 或私有播放器状态；也不能把这个方案写成已观察到的华为实现。

主动发起先登记 intent 和应用 GUID，before 回调到来后按来源与发起关联绑定 native GUID，再继续已有确认/准入/持久化链路。同 URL 的并行意图不能相互吞并；主动请求与 before 回调不能各自生成任务。`WebDownloadManager` 负责恢复已有对象，不是无页面 startDownload(url) 的替代入口。

## 3. 恢复、文件与持久化

1. 修复 Repository 克隆丢 originalUrl / expectedTotalBytes，覆盖实体、Repository、持久化读回的完整往返。
2. 保持 platform token 与 guid 配对；确认后排队不能无条件清 id/token。确认前是否持久化需独立定义，恢复绝不能自动补用户确认。
3. 同会话暂停用 item.resume；反序列化/失败中断路径用 manager.resumeDownload，并处理 token 为空、损坏、来源页面已失效等结果。已有恢复能力继续复用，不能误判为完全缺失而重写。
4. 区分续传和重新下载。服务器不接受 Range、校验器变化或 token 无效时，明确给出可用动作；不要把所有 interrupted 都标成可续。
5. 恢复前重新检查授权。保存授权 URI 与类型，不把目录授权、单文件授权和实际路径混为一谈。撤权后提供重新选目录的动作。
6. 文件名按实际文件系统/API 字节预算处理，保留合理后缀和冲突编号；覆盖中文、emoji、长名称。目标冲突同时考虑磁盘和未完成任务预留。URL 相同不能单独决定任务重复。
7. 网络接收完成后，最终文件写入/导出成功且目标可访问，才向用户报告文件可用。导出失败保留可恢复的源文件；删除任务与删除文件保持现有用户语义。
8. 高频进度合并最新快照，关键状态、确认、暂停、完成、失败、目标/权限变化立即持久化。不能让每次进度积累全量 JSON 快照队列，也不能把终态事件一起吞进 500 ms 限流。
9. 先评估合并写入对现有 preferences 的改善；仅在数据规模、恢复一致性或写入需求无法满足时再迁移。更换存储时必须有版本迁移和旧记录恢复测试。

## 4. 错误、操作、进度与后台

- 采用带来源的错误分类：ArkWeb 错误、curl 错误、HTTP 状态、文件/权限错误分别解释，再统一用户动作。相同数字不能跨来源直接套同一张表。
- 错误分类同时驱动 VM 文案、按钮与 Service 的可执行操作。网络中断可继续、授权问题可重新选位置、空间不足可修复后重试、上下文丢失可回原页重新发起；不能仅加几条字符串。
- 华为权限/空间/无 Range 的禁止重试策略尚未被证实，不把旧 mapper 作为真值。36 入口确有 toast/return，但 Aira 平台对象释放必须自己闭环，不能复制可能悬挂的早退。
- 进度保留未知总量语义；不要因为无法计算百分比而显示失败。只要求数据和状态一致，不因华为某处将未知值映射为 0 而改变 Aira 界面表现。
- 进度采样、列表更新、持久化、通知刷新分别控制。暂停/取消/结束不延迟。
- 后台能力和通知申请结果分开；首次后台申请失败不可缓存为已成功。同批任务的合理后续时机可重试，需限频，不能在每个 tick 连续申请。
- 对齐排队/传输/导出阶段的后台生命周期，防止空档过早释放；同时不因幽灵任务永久持有。私密下载保持隐私边界，不能为对齐普通通知而泄露文件名。

## 5. 实施顺序与交付条件

| 阶段 | 工作 | 完成条件 |
| --- | --- | --- |
| P0-A | 原始上下文往返、最新启动结果、事件处理结果类型；修 F04/F05/F13 | 真实 Repository 与 Service 联合回归，字段不丢、失败不报成功、非法转移不执行成功副作用 |
| P0-B | 待确认事件生命周期和来源身份；修 F01/F11 | 确认前更新/失败/完成/取消均收敛；多标签、跨窗口、普通/私密并发不串 |
| P0-C | 真正准入控制、暂停原因、网络恢复；修 F02/F03/F06/F07 | 实际字节/请求证明等待策略有效；手动暂停不自启；同 owner 恢复；无错误触发的自动换引擎 |
| P1-A | 普通主动入口默认 ArkWeb，来源关联和双 GUID 绑定 | manual/MP4/资源/GM/batch 进入来源 controller；before 不重复建任务；特殊 headers/HLS/旧任务兼容 |
| P1-B | 恢复授权、路径占用、文件名、导出终态 | 冷启动续传、撤权、磁盘满、同名并发与打开删除通过 |
| P1-C | 错误到动作/文案闭环；修 F08/F12 | 每类失败给出有效动作，列表/通知/弹层一致，不只显示数字 |
| P1-D | 合并持久化与后台重试；修 F09/F10 | 多任务长下载写入有界；后台失败可恢复；终态及时保存 |
| P2 | data/blob/图片保存补充与核心设备行为验证 | 每种支持范围有明确证据；不将私有图片缓存或播放器能力写成公开 API 已等价 |

阶段编号为执行顺序，不把 P2 解释为用户目标可以省略。先建立核心任务正确性，再扩展覆盖。

## 6. 验收矩阵

统一记录：参考样本/系统/ArkWeb 版本、入口、网络策略、平台 guid、应用 intent/attempt、事件顺序、目标位置、服务器请求次数、最终文件哈希。日志不包含 Cookie、Authorization、带 token 的完整 URL 或私密文件名。本轮不要求截图、录屏或视觉对照。

| 组 | 必测场景 | 不可接受的结果 |
| --- | --- | --- |
| 基本入口 | 页面附件、长按、302/307 重定向、直接图片 | 无响应、两条重复任务、请求重放 |
| 主动 owner | 手动 URL、MP4、普通资源、无 headers GM、批量 | 普通请求仍默认 libcurl；before 重复建任务；同 URL 不同来源错绑 |
| 特殊 owner | 自定义 headers、HLS、旧 libcurl 记录 | 丢失显式头、把清单当视频、重启偷偷迁移引擎 |
| 会话 | 登录 Cookie、Referrer Policy、UA、自定义 header、普通/私密 | 凭据丢失、错用 cookie store、来源错绑 |
| 请求保真 | POST 下载、一次性签名 URL、过期链接 | 用 GET 重放 POST、消耗第二次签名、错误页面当文件 |
| 确认 | 立即确认、延迟确认、期间失败/完成、取消、切标签 | 没有任务承接、反复处理失败提示、取消后仍下载 |
| 排队 | 1/3/4 个任务、并发中取消/暂停/完成、无网启动 | 列表排队但超额传输、空槽不启动、同任务双写 |
| 网络 | Wi-Fi→蜂窝→Wi-Fi、离线→联网、用户手动暂停后换网 | 禁蜂窝仍持续传输、手动暂停自启、恢复从零且无说明 |
| 续传 | Range 支持/不支持、ETag 改变、无总长、稀疏平台文件 | 拼接损坏、把接收字节数当连续偏移、虚假百分比 |
| 冷启动 | 下载中退出、排队时退出、网络暂停、手动暂停、确认未完成 | token 丢失、用户意图改变、未确认任务自动保存 |
| 目录 | 默认 DOWNLOAD、自选目录、目录/文件授权、撤权、移动文件 | 假完成、授权错对象、已下载文件不可打开 |
| 命名 | 同 URL 不同目标、不同 URL 同目标、并发同名、长中文/emoji | 覆盖无关文件、名称越界、重复判断错误 |
| 文件失败 | 空间不足、导出失败、短写、权限失效 | 无法修复重试、源文件被过早清理 |
| 特殊 URL | base64/percent data、图片 blob、页面生成 PDF/CSV、blob 撤销 | 将图片专用路径误当通用支持、卡死或内存无界 |
| 后台 | 切后台/锁屏、首次申请失败、拒绝通知、全任务结束 | 进度停住无解释、申请失败永久不再申请、后台资源不释放 |
| 状态一致 | 列表、工具栏、toast、通知、打开文件、删除文件 | 一处失败另一处完成、按钮无法执行、重复通知 |
| 既有能力 | HLS、资源嗅探、站点视频、用户脚本、取消/隐私回归 | 为普通下载对齐破坏已有独立能力 |

所有设备场景目前为待执行。已有 Repository、待确认生命周期、来源边界、ArkWeb 原任务持有/恢复、文件落地核验、目标授权和后台恢复回归；主动发起的来源绑定、owner 路由和双 GUID 绑定需纳入本轮最终检查。真实 ETS owners 配合受控平台替身不能代替设备行为。完整检查入口为 `scripts/check-aira-downloads.sh`。

## 7. 实施规则

直接在 main 工作，保留无关改动；不创建分支/worktree，不自行提交。平台 API 以官方文档和目标 SDK 为准。分析样本、华为资源、设备数据不提交。现有 owners 内实现，不把策略放回页面。

每阶段运行相关现有检查，并增加能暴露缺陷的集成边界回归；不为每个文件机械增加镜像测试。依赖注入时保留真实 Repository/Engine 的往返，明确哪些平台行为是假设。

业务改动完成后从仓库根运行相应下载检查；有匹配签名配置时执行：

    AIRA_DISTRIBUTION=community SKIP_INSTALL=1 ./scripts/build-aira-browser.sh

发布说明如需变更必须中英成对、面向用户。没有目标设备证据时，交付只能说完成实现和本地验证，不能说已完全对齐。

## 8. 本轮实现记录（2026-11-17）

### 8.1 本轮核心实现范围

| 范围 | Aira 实现与验证边界 |
| --- | --- |
| 普通主动下载 | manual/MP4/资源/无自定义 headers GM/batch 通过来源 controller.startDownload；Bridge 绑定平台/应用 GUID；Service 默认 arkweb；入口与 Service→Bridge 联合回归通过 |
| 专用 native | 保留 HLS、明确自定义 headers 和旧 libcurl 任务；不按入口名称选 native，不因 ArkWeb 网络错误自动重放 |
| 来源与准入 | 按 controller/tab/窗口/隐私绑定 delegate；等待确认和排队持有原 ArkWeb 任务，保留 GUID 与 token；已经产生的网页请求不能重发 GET |
| 暂停与恢复 | 区分用户、网络、Wi-Fi 和并发原因；网络恢复只调度符合资格的任务；活对象与反序列化对象走相应公开恢复 API；过期事件不能重启取消任务 |
| 保存完成 | 接收完成后进入保存阶段；源文件与目标文件核验、元数据持久化成功后才报告完成；导出失败保留源文件，重新选位置后仅重试保存 |
| 路径与授权 | 每个任务冻结目标与真实授权；文件 URI 和目录 URI 分开处理；重启重新激活授权，撤权不能静默改存别处；旧目录仍被任务引用时不释放 |
| 文件元数据 | 显示最终实际文件名和保存位置；操作失败保留可用副本，不从单文件 URI 推导父目录授权 |
| 持久化与后台 | 高频进度合并最新快照，关键状态立即保存；后台申请失败限频重试；保存阶段继续持有后台能力，完成通知不提前发出；私密任务不泄露文件通知 |
| 图片上下文 | 图片保存、复制、分享固定使用发起菜单时的页面与隐私上下文；私密 Cookie 和缓存隔离；保留 data:image 解码，blob 不进入 native HTTP |

UI 已恢复 Aira 原有设计。上述实现改变的是引擎与任务事实，不要求复制华为布局或资源。

### 8.2 仍需验证的行为与能力边界

- 本轮没有设备截图要求；不把字体、颜色、间距、动画或逐屏视觉结果列入交付门槛。
- 原 ArkWeb 任务的等待、恢复、POST、一次性链接和 blob 行为仍需同版本设备实测；替身回归只能证明应用选择了正确控制路径，不能证明平台已停止实际字节传输或恢复成功。
- 主动 URL 的来源绑定、当前页面 referrer、普通/私密会话、controller 生命周期与并行请求对应关系仍需设备请求记录核验；公开 API 的存在不自动证明所有调用时机都正确。
- 公开 before 回调没有请求关联 ID。应用按来源、方法和原始 URL 精确匹配，并将主动请求串行绑定；同一来源、同一 URL 上恰好重叠的独立网页请求仍无法绝对区分。首次回调前的暂停保留控制意图，收到对象后才执行实际停止，不能宣称此前网络字节已经停止。
- 华为播放器 download 与 WebExtension 包含私有能力；普通直接文件可用公开 startDownload 接入 ArkWeb，但这不能证明媒体缓存、分片、DRM 或任意 headers 已与私有播放器等价。
- 华为内部图片缓存提取尚无已核实的公开字节读取等价接口。Aira 图片操作仍使用 HTTP/data 路径，blob 图片保存与缓存原图提取尚未实现等价能力。
- 只有单文件授权时，Aira 不推导父目录权限，应用内重命名明确不支持；真实目录授权支持。缺失文件的重新下载只在用户确认且可安全重新发起 GET 时提供，POST/带凭据或签名的旧请求需回原页面发起。
- 此轮对齐的是上述手机样本；没有将其外推为华为所有版本或 PC 行为一致。

### 8.3 本轮验证状态

下载检查统一入口为 `scripts/check-aira-downloads.sh`，包含真实 ETS owners 的生命周期、来源隔离、原任务持有、恢复、文件落地、持久化、授权、通知和文件操作回归。平台能力使用受控替身；这些测试不替代第 6 节设备矩阵。

最终源码完成后，统一入口中的 25 个不依赖本地监听的下载检查脚本全部通过，覆盖入口路由、双 GUID、首次回调前暂停/立即继续、原任务恢复、文件落地、授权及持久化。原有选择/批量操作回归通过，确认面板、列表行与选择模型已恢复原实现。架构检查通过。

目标 DevEco SDK 的 ArkTS 编译与 `assembleHap` 通过，生成未签名 HAP；本机 default product 没有匹配的 signingConfig，未执行安装或设备端到端验证。

完整下载门禁的重定向 HTTP fixture，以及 Community 构建脚本的 WebDAV fixture，均被执行环境禁止 `listen 127.0.0.1`（EPERM）；后续 native/proxy 网络门禁未完成。因此不能将完整下载门禁或完整 Community 构建脚本标为通过。单独 HAP 编译只能证明源码、资源和打包，不替代网络 fixture、签名或设备行为。

公开 API 依据：[Web 下载指南](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/web-download/)、
[WebviewController](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-webview-webviewcontroller/)、
[WebDownloadManager](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-webview-webdownloadmanager/)。
本地目标 SDK 的 `@ohos.web.webview.d.ts` 中，setDownloadDelegate 为 3893 行、startDownload 为 3909 行，
WebDownloadManager 的 setDownloadDelegate/resumeDownload 为 5811/5821 行；接口版本与目标系统兼容性仍以实际构建 SDK 为准。
