# 华为浏览器下载实现：REA 复核报告（原生层证据）

> **历史草稿，已被重新核验结果取代（2026-11-17）。** 下文保留调查过程，不再作为实施依据。
> 关于网络失败/自动恢复、startPhoneDownload 独立兜底、权限不可重试、PENDING 可恢复、文件名上限及原生符号能力的多处断言已纠正。
> 事实与证据请先读 [REA 重新分析](aira-browser-download-rea-reanalysis.md)，实施仅使用 [新版规格](aira-browser-download-parity-spec.md)。原生符号存在不等于公开 API 契约或实际运行行为。

日期：2026-11-17
关联文档：`aira-browser-download-huawei-alignment.md`（ArkTS 层还原 + Aira 差距清单）、`aira-browser-download-parity-spec.md`（**最终实施规格**，要改代码时以它为准）

## 1. 目的与结论

本文用 REA 6.9.0 对同一份华为浏览器 HAP 做**独立第二遍**分析（并追到系统组件 ArkWebCore 确认引擎身份，见 §4.0），目的不是重做 ArkTS 层的逻辑还原，而是回答两个 ArkTS 层回答不了的问题：

1. 下载在**原生层**到底由谁实现，暴露了哪些能力？
2. 之前 ArkTS 层的三个推断（续传靠 ETag 校验、冲突策略在建任务时定、`before_download` 期间可暂停）能否被原生符号证实？

**结论**：

- 网页下载的原生実现在 `libbrowser_service.so`，它是 **ArkWeb 下载桥的原生侧**，导出 **2687 个**符号，其中 **86 个**与 download 相关，分成 `WebDownloadItem_* / WebDownload_* / WebDownloader_* / WebDownloadManager_* / ArkWebExtensionDownloadsController_*` 五族。
- 三个 ArkTS 推断**全部被原生符号证实**，并额外发现一个此前未注意的能力族：`*BeforeDownload`（下载开始前可 pause / cancel / resume）。
- `libnetwork-download.so`（HMS NetworkKit）与网页下载**无关**，已被"零调用方"的证据闭环。
- REA **不能**解析 `.abc`（ArkTS 字节码），这一条有 REA 自己的明确回执。所以 ArkTS 层的结论仍然只能由 `ark_disasm` 得到，本文只做交叉验证。
- 发现 REA 6.9.0 一个可上报的缺陷：HarmonyOS 的 `.so` 其 `SHT_NOTE` 段未按 4 字节对齐，导致 `inspect-elf-notes` / `inspect-binary-hardening` 在这批库上全部 fail-closed。

## 2. 环境与版本

| 项 | 值 |
| --- | --- |
| REA 版本 | 6.8.0 → **6.9.0**（`rea update`，2026-11-17） |
| 安装方式 | npm 全局，`/opt/homebrew/lib/node_modules/rea-agents`，命令 `/opt/homebrew/bin/rea` |
| Node | v26.12.1（满足 `>=26.12.1`） |
| 分析引擎 | **无**。Ghidra `not_configured`（`GHIDRA_INSTALL_DIR` 未设）、Hopper `executable_missing`、IDA/Kuna/JADX 未配置、rizin 未安装 |
| 实际使用的 REA 面 | CLI（6.9.0 新能力）+ 6.8.0 MCP 会话（archive 目标） |
| 输入 | `HuaweiBrowser-phone.hap` sha256 `d1ce1789…f8f8a09` |

> 为什么走 CLI 而不是 MCP：本进程的 MCP server 是 6.8.0 启动的，`rea update` 不会热替换运行中的 server（doctor 明确要求「Restart agents running this installation」）。CLI 与 MCP 共用同一套 Evidence 生产者，返回的记录结构一致，按 skill 的指引直接用 CLI 继续。

## 3. 证据链

| # | REA 操作 | Evidence ID | 观察 |
| --- | --- | --- | --- |
| 1 | `inspect-artifact`（HAP，summary） | `ev_256d14f2…6daf`（父）/ `ev_645cacf1…c28c8`（summary view）/ `ev_e899fbb8…3b9a`（inventory） | 2734 项检出、877 节点、929 occurrence、928 边、`integrity_contradictions: 0`、`source_complete: true` |
| 2 | `project-harmony-application-graph` | `ev_308431782fe8ceba83ec58a5b8c90aebf1e64d70842106ba0554464a43aad677` | `packaging_model: stage`；组件：manifest 2、bytecode 2、javascript 2、**native_libraries 48**、resources 871、signing 0；`runtime_families: [ark, javascript, native]`；`bridge_candidates: 96`（`complete`） |
| 3 | `inspect-native-exports`（`libbrowser_service.so`） | `ev_f0b5f6cdc9861fd9d9cba5a53ea964019b40a839d41d43f0290e6c29975f6679` | ELF64 little-endian arm64，2,126,448 B，**2687 exports / 86 download** |
| 4 | `inspect-native-exports`（`libnetwork-download.so`） | `ev_ae24c905aabf0de83781da4604f579c4623f55662b1490c6d535852b8dda7996` | 391,112 B，82 exports / **51 download**，全部 `NetworkKit::FileManager::*` |
| 5 | `inspect-native-exports`（`libnetwork-filedownload-service.so`） | `ev_adf30c77d9c692c7d9fdd3bb5cd7ebe9e13b9d2d9bbaf2bfb5f2645854e651ae` | 698,864 B，57 exports / **0 个 download 命名符号**（只有 C++ 运行时与 unwind） |
| 6 | `inspect-elf-unwind-ranges`（`libbrowser_service.so`） | `ev_2570c2e3007b39e6040943ceae6aa6ae02ed5101c8a8111b705a829d5d504a6e` | `.eh_frame` 1619 个 FDE、960 个带符号；**下载符号不在 FDE 里**（C 风格导出、无 unwinding 需求） |
| 7 | `inspect-artifact`（`ets/modules.abc`） | 无（拒绝） | `unsupported binary format` / `file_format_rejected` |
| 8 | `inspect-elf-notes` / `inspect-binary-hardening`（各 .so） | 无（拒绝） | `ELF note entry exceeds its table`（见第 6 节根因） |

## 4. 原生层新发现

### 4.0 引擎身份：ArkWeb 内置的 Chromium `components/download`

网页下载的引擎不在应用包里，而在系统组件 **ArkWebCore**：

| 事实 | 证据 |
| --- | --- |
| 引擎载荷 | 系统镜像 `/system/app/ArkWebCore/ArkWebCore.hap`，151,172,150 B，内含 `resources/rawfile/chrome_100_percent.pak`、`chrome_200_percent.pak`、`icudtl.dat`、`locales/*.pak` → Chromium 资源集 |
| 引擎本体 | `libarkweb_engine.so`，222,355,712 B，ELF64 arm64；UA 串含 `Chrome/144.0.7559.59`（另有 `126.0.6478.36`、`114.0.0.0` 历史常量）→ **Chromium 144 分支** |
| 下载实现 | 二进制内保留 Chromium 源文件路径：`components/download/internal/common/download_item_impl.cc`、`parallel_download_job.cc`、`download_file_impl.cc`、`download_file_with_copy.cc`、`download_response_handler.cc`、`download_path_reservation_tracker.cc`、`resource_downloader.cc`、`in_progress_download_manager.cc`、`download_job.cc`、`download_worker.cc`、`download_db_cache.cc`、`stream_handle_input_stream.cc` |
| 后台下载服务 | `components/download/internal/background_service/*`：`controller_impl.cc`、`basic_task_scheduler.cc`、`device_status_listener.cc`、`navigation_monitor_impl.cc`、`file_monitor_impl.cc`、`in_memory_download.cc` → Chromium Background Fetch |
| 华为扩展补丁 | `arkweb_download_item_impl_ext.cc`、`arkweb_download_file_impl_ext.cc`、`arkweb_download_manager_delegate_ext.cc`、`arkweb_download_utils_ext.cc`、`arkweb_download_url_parameters_util.cc` → 这就是 NAPI 暴露 `WebDownloadItem` 的落点 |
| 应用侧定位 | `libbrowser_service.so` 引用 `libarkweb_engine.so` 与 `/module_update/ArkWebCore/app/com.huawei.hmos.arkwebcore/ArkWebCore.hap`；本包导出 277 个 `ArkWebExtension*`、185 个 `WebExtension*`、49 个 `WebDownload*`，是**绑定层**不是引擎 |
| 无 libcurl | 浏览器 HAP 与 ArkWebCore 都没有 `libcurl/libssl/libnghttp2`；`libarkweb_engine.so` 内 `libcurl` 出现 0 次 |

**三个“下载引擎”的分工**（容易混）：

| 引擎 | 实现 | 谁在用 |
| --- | --- | --- |
| ① ArkWeb 内置 Chromium `components/download` | `libarkweb_engine.so`（系统组件，随 ArkWebCore.hap 更新） | **网页触发的所有下载**；华为浏览器的 `BrowserWebDownloadDelegate` / `DownloadTaskManagerImpl` 只是它上面的一层策略 |
| ② HMS NetworkKit 文件下载 | `libnetwork-download.so`（`NetworkKit::FileManager::DownloadManager`）+ ArkTS HAR `@hms-network/file-download` 8.0.9-302（内部再分 `OsDownload` 与 `LibDownloadAdapter` 双后端） | 业务接口资源下载（`HttpUtils`），**不接网页下载** |
| ③ 系统下载服务 `@ohos.request` | 系统 DownloadAgent | 少量离线包/缓存类资源（浏览器内 4 处 import，含 `request.cacheDownload`） |

这对 Aira 最关键的一条：**`parallel_download_job.cc` 说明 ArkWeb 引擎本身就具备多连接分片下载能力**，Aira 自建 libcurl 分段并不是“平台做不到”，而是为了让分片/HLS 可携、可测、可暂停；这个取舍要写清楚，避免后续有人以为在重复造轮子。

### 4.1 网页下载的原生归属：`libbrowser_service.so`

86 个 download 符号的分布：

| 族 | 数量 | 含义 |
| --- | --- | --- |
| `ArkWebExtensionDownloadsController_*` | 32 | 面向 Web Extension 的 downloads API 控制器（`OnDeterminingFilename`、`SetGetAllDownloadItemFunc`、`SetShowFunc`、`SetEraseFunc`、`SetSetUiOptionsFunc`、`OpenCallback`、`RemoveFileCallback`…） |
| `WebDownloadItem_*` | 31 | 单个下载任务的属性读写（Guid / Url / OriginalUrl / MimeType / TotalBytes / ReceivedBytes / CurrentSpeed / PercentComplete / SuggestedFileName / FullPath / Method / **ETag** / **ContentDisposition** / State / **IsPaused** / CreateWebDownloadItem / Destroy） |
| `WebDownloader_*` | 9 | 传输执行器：`StartDownload`、`ResumeDownload`、**`ResumeDownloadStatic`**、`ReadDownloadData`、`PutDownloadCallback`、`SetDownloadBeforeStart`、`SetDownloadDidUpdate`、**`SetFileRenameOption`**、`CreateDownloadDelegateCallback` |
| `WebDownload_*` | 8 | 生命周期动作：`Pause` / `Cancel` / `Resume` / `Continue` / `GetItemState` + **`PauseBeforeDownload` / `CancelBeforeDownload` / `ResumeBeforeDownload`** |
| `WebDownloadManager_PutDownloadCallback` | 1 | 全局（manager 级）delegate 挂载点 |
| 其它 | 5 | `DestroyDownloadItemCallbackWrapper`、`DestroyBeforeDownloadCallbackWrapper`、`NWebMediaPlayerController_Pause`（非下载）、`ArkWebExtensionBrowsingDataController_SetOnRemoveDownloads` 等 |

**这直接说明**：华为 ArkTS 层的 `WebDownloadDelegate` / `WebDownloadManager` 不是纯 JS 实现，而是 NAPI 绑定到 `libbrowser_service.so`；两套 delegate（controller 级与 manager 级）在原生侧各有独立挂载点（`WebDownloader_PutDownloadCallback` vs `WebDownloadManager_PutDownloadCallback`）。这也解释了为什么少设一个 delegate 就会有一类下载静默——原生侧是两条独立回调链。

### 4.2 三个 ArkTS 推断的交叉验证

| ArkTS 层推断（来自 `.pa` 还原） | 原生符号证据 | 结论 |
| --- | --- | --- |
| 断点续传靠 `serialize()` 里的校验信息，服务端不支持 Range 就没戏 | `WebDownloadItem_ETag` / `SetETag` 存在，`WebDownloadItem_ContentDisposition` 存在；`WebDownloader_ResumeDownloadStatic` 与 `WebDownloadManager_PutDownloadCallback` 成对 | **证实**。item 真的携带 ETag，续传是条件请求而非盲续 |
| `FilenameConflictAction(UNIQUIFY/OVERWRITE/PROMPT)` 在 `start()` 之前决定 | `WebDownloader_SetFileRenameOption` 是**独立于 StartDownload 的 setter** | **证实**。冲突策略必须在 `start()` 之前设好，开始后再改无效——这正是华为把文件名/冲突决策全放在 `determineDownloadPathBeforeStart` 的原因 |
| PC 端在 `onBeforeDownload` 里先 `task.pause()`，确认后再 `start()` | `PauseBeforeDownload` / `CancelBeforeDownload` / `ResumeBeforeDownload` 与 `DestroyBeforeDownloadCallbackWrapper` 独立成族 | **证实并加强**。原生层专门为「下载开始前」提供了 pause/cancel/resume 三件套，说明 PENDING 窗口是一等公民，不是一个「还没开始就什么都做不了」的尴尬期 |

### 4.3 连带结论：HMS NetworkKit 与网页下载零关系

- `libnetwork-download.so` 的 51 个 download 符号**全部**是 `NetworkKit::FileManager::DownloadManager::*` / `DownloadRequest::*`（`Start`、`PauseRequest`、`ResumeRequest`、`CancelRequest`、`GetAllRequests`、`CreatePreconnection`…），属于 HMS NetworkKit 的文件下载子服务。
- `libnetwork-filedownload-service.so` 的 57 个导出里 **download 命名符号为 0**。
- ArkTS 侧唯一引用 `NetworkkitDownload` 的模块是 `hwbr/common_base/.../network/networkkit/NetworkkitDownload`，而它只被 `HttpUtils` 使用。

**闭环**：网页触发的下载走 ArkWeb（`libbrowser_service.so`），业务接口里的资源下载走 NetworkKit（`libnetwork-download.so`），两条链互不重叠。这对 Aira 的意义是：**Aira 自己手写的 libcurl 驱动不是"重复实现华为已有的东西"，而是在替代 ArkWeb 无法覆盖的那部分（Range/分段/HLS）**——方向上没有走错。

## 5. REA 的能力边界（对本次任务而言）

### 5.1 `.abc` 不在 REA 的射程内

```bash
rea inspect-artifact work/hap/ets/modules.abc
# → code: target_unavailable / category: unsupported_target
#   message: "Cannot open artifact: unsupported binary format."
#   details.reason: "unsupported binary format"
#   details.constraint: "file_format_rejected"
```

这是 REA 自己的回执，不是猜测。ArkTS 字节码需要 `ark_disasm`（DevEco SDK 自带）或方舟运行时工具链，REA 6.9.0 没有 ArkTS provider。

### 5.2 HarmonyOS 投影只到清单级

`project_harmony_application_graph` 的 `limitations` 原文：

> Manifest, module, resource, and signing semantics require a dedicated HarmonyOS provider; this projection reports exact inventory paths and hashes only.

它可以给：组件路径 + SHA-256、`packaging_model`、`runtime_families`、48 个原生库清单、96 条 NAPI 桥候选（`napi-library-convention`）。
它不能给：`module.json` 语义、资源语义、签名语义、ArkTS 代码逻辑。

**用途定位**：拿来做「产物身份 + 暴露面」的基线（比如对比两个版本 HAP 的组件哈希差异），而不是做「功能怎么实现」。

### 5.3 未安装任何原生引擎时的可用面

| 需要引擎的工具 | 状态 |
| --- | --- |
| `open_binary`（native）/ `list_procedures` / `decompile` / `xrefs` / `analyze_function` | 不可用（无 Ghidra/Hopper/IDA/Kuna） |
| `inspect-native-exports`（PE/ELF 导出表） | **可用**，且足以回答"暴露了什么能力" |
| `inspect-elf-unwind-ranges`（`.eh_frame` 函数范围） | 可用，但 C 风格导出函数没有 FDE，覆盖不到下载符号 |
| `execute-rizin-command` | 不可用（`ENOENT`，未安装 rizin；brew 有 0.9.1 bottle） |
| `inspect-with-objdump` | 受限于 macOS 自带 llvm-objdump，非 GNU 语义 |
| `inspect-elf-notes` / `inspect-binary-hardening` | **这批库上全部失败**（见 5.4） |

要把 `libbrowser_service.so` 里的 `WebDownloader_StartDownload` 等函数**反编译成伪代码**，必须先配一个引擎：`GHIDRA_INSTALL_DIR`（Ghidra ≥12.1）或 `REA_RIZIN_COMMAND`（`brew install rizin`）——后者只解锁 rizin 命令面，不解锁 `decompile`。

### 5.4 一个可上报的缺陷：HarmonyOS `.so` 的 `SHT_NOTE` 未对齐

**现象**：对这 48 个 `.so` 中的任意一个执行 `inspect-elf-notes` 或 `inspect-binary-hardening`，一律返回：

```json
{"code":"invalid_request","category":"invalid_input",
 "details":{"issues":[{"path":["path"],"reason":"invalid_format",
 "message":"Selected artifact …: ELF note entry exceeds its table."}],
 "partial_observation":{"kind":"file-snapshot-hash","sha256":"52a4353656…","bytes":2126448}}}
```

**根因**（手工比对 program header 与 section header 得出）：

```
libagcommon.so
  PT_NOTE  p_offset=…, p_filesz=60          # OHOS(24) + GNU.build-id(36)，4 字节对齐
  SHT_NOTE sh_offset=0x270, sh_size=21      # namesz=5 未补 padding：12+5+4=21
  SHT_NOTE sh_offset=0x288, sh_size=36
```

OHOS 链接器把 note **按 section 写出时不补 4 字节对齐**（`12 + namesz + descsz`，无 padding），但 program header 里是补齐后的长度。ELF 规范要求 `n_namesz` 按 4 字节对齐，因此 section 视图是非规范的；按 section 解析必然「note entry exceeds its table」。

REA 的处理是 **fail-closed**（拒绝返回部分结果，只给文件快照哈希），这个设计本身是对的；建议上报为「HarmonyOS/OHOS ELF note 兼容性：优先使用 PT_NOTE 视图」。

**对本次分析的影响**：只损失 build-id 与加固项两项元数据，不影响第 4 节的导出表结论。

## 6. 对 Aira 的额外启示（原生证据带出来的）

1. **冲突策略必须是 start 前的 setter**（`WebDownloader_SetFileRenameOption`）。Aira 的 `DownloadFilenameConflictService` 现在是"算好文件名再开始"，方向正确；要保证没有代码路径在 start 之后再改文件名，否则原生侧忽略。
2. **`BeforeDownload` 窗口有专门的 pause/cancel/resume**。Aira 目前在 `awaiting_confirmation` 期间既不 pause 也不 cancel（见对齐文档 P1-3），原生其实支持"暂停这个还没开始的下载"，比"什么都不做、任由它往临时目录写"更贴近平台设计意图。
3. **ETag 是 item 的一等字段**，不是 ArkTS 层自己算的。Aira 的 `persistence.etag/lastModified/acceptRanges/contentRange` 走的是 libcurl 自采，arkweb 驱动这条路上应改为"信任 item 自带校验器"，即把 `serialize()` 结果当作唯一凭据，而不是再抓一遍响应头。
4. **两套 delegate 在原生是两个挂载点**，证实了"少设一个就有一类下载静默"不是猜测。

## 7. 复现命令

```bash
# 0. 升级（会打印 previousVersion / installedVersion）
rea update && rea --version

# 1. HAP 清单（summary 必须配 --evidence_output 才能保留完整源证据）
rea inspect-artifact HuaweiBrowser-phone.hap --detail summary \
  --evidence_output rea-out/hap-inventory.json

# 2. HarmonyOS 应用图投影（走 retained evidence）
cat > harmony-input.json <<'JSON'
{ "inventory_evidence": [ { "kind": "retained-evidence",
  "evidence_id": "ev_e899fbb8f5f9fb9fdfe1c5be191c63eb0039488300b97c15fc8c6c4e6ff13b9a" } ] }
JSON
rea project-harmony-application-graph harmony-input.json \
  --evidence-bundle rea-out/hap-inventory.json --format json > harmony-graph.json

# 3. 原生导出表（无引擎也可用）
rea inspect-native-exports libs/arm64-v8a/libbrowser_service.so --format json \
  | python3 -c "import json,sys,re; d=json.load(sys.stdin); \
n=[e['name'] for e in d['normalized_result']['exports']]; \
print(len(n), len([x for x in n if re.search('download',x,re.I)]))"

# 4. 确认 REA 不解析 ArkTS 字节码
rea inspect-artifact ets/modules.abc        # → unsupported binary format

# 5. 复现 note 段缺陷
rea inspect-elf-notes libs/arm64-v8a/libagcommon.so   # → ELF note entry exceeds its table
```

## 8. 一句话总结

REA 这次不是主分析工具（`.abc` 它读不了），但它用**导出表证据**独立证实了 ArkTS 层的三条关键推断，并补上了 ArkTS 层看不到的两件事：**冲突策略与续传校验器都在原生侧且必须在 `start()` 之前确定**，以及 **`before_download` 窗口在原生存有独立的 pause/cancel/resume 三件套**。这两点都直接影响对齐文档里 P1-1 与 P1-3 的改法。
