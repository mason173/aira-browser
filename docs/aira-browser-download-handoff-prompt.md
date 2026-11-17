# Aira 下载对齐华为：实施交接（重新核验版）

日期：2026-11-17。旧交接中的 D1/D2/D3、T0–T8 已撤回，不能从旧分析直接复制代码执行。

范围纠正：用户明确要求对齐下载引擎和底层逻辑，现有交互没有问题。此前华为化界面的改动已撤回，后续不得继续改版或把逐屏截图作为核心改造的前置。普通主动下载也必须进入来源 ArkWeb；libcurl 仅保留 HLS 合并、无法通过公开 ArkWeb 参数等价表达的自定义请求，以及旧任务兼容。先读当前源码和 [实施规格第 8 节](aira-browser-download-parity-spec.md#8-本轮实现记录2026-11-17)，下文缺陷描述对应修复前快照。

以下内容可交给实施者：

---

目标：把 Aira 的普通浏览器下载完整生命周期对齐本地华为浏览器 5.1.9.315 手机样本。包含用户确认、实际传输准入、进度、网络暂停与恢复、保存位置、冷启动、通知、后台及完成后文件可用性。保留 Aira 的 HLS/嗅探/用户脚本既有能力。PC 行为单列。

先读：

1. 仓库根 AGENTS.md 及适用嵌套规则。
2. docs/aira-browser-download-rea-reanalysis.md：原始证据、旧结论纠正、F01–F13、三个最小复现及未解问题。
3. docs/aira-browser-download-parity-spec.md：新的任务生命周期、实施顺序和验收矩阵。
4. docs/aira-browser-download-current-architecture.md：结构参考，以当前源码为准。

直接在 main 工作，保留已有无关改动。不自行创建分支、worktree、提交或推送。

必须理解的事实：

- 华为网络类 20/21/22 映射网络暂停，网络恢复和冷启动有按暂停原因筛选的恢复路径。手动暂停不自动继续。
- WebDownloadItem.start 主要指定文件落点，PENDING 阶段可能已在传输。排队/等待 Wi-Fi 的应用状态不能代替对底层传输的控制。
- Aira 确认前一般只有 RequestCapture 条目，没有 engine task；后续事件可能被 Runtime 误报处理失败。不是旧规格声称的 awaiting_confirmation 被 PENDING 更新成 queued。
- Repository.cloneTask 丢 originalUrl/expectedTotalBytes；后台申请首次失败会缓存失败状态；这些已通过实际应用方法的注入探针复现。
- startPhoneDownload 的已读链路来自 delegate，不能证明有回调缺失时的独立 URL 兜底。不要添加 1.5 秒盲目 GET 重放。
- controller.startDownload 有官方 delegate 示例。要验的是 Aira 的源控制器、请求会话、隐私与事件时序；捕获到 UA/referrer 不等于必须走 libcurl。
- 华为重复任务检查主要按目标路径，不是 URL；文件名用 255 预算按 UTF-8 截断主体，不是 2048 字符。
- 图片缓存桥不是任意 blob PDF/CSV 的通用公开 API。导出表符号不能视为第三方可用接口。

按新版规格 P0-A → P0-B → P0-C → P1 → P2 推进。先修数据往返与事件归属，再建立实际准入、暂停原因、同 owner 恢复，随后退出普通网页隐式跨引擎重下策略。不能只删恢复功能。

核验三种证据时保持边界：

- REA 用于样本/原生证据；ArkTS 控制流来自官方 ark_disasm。
- 注入平台事件的测试只证明应用处理，不能声称真实系统一定发送相同序列。
- 完全对齐必须经过目标系统同条件对照。未实测的场景留为待验收，不得填“通过”。

实现放入既有 core/services/domain/features/data/platform owners，页面保持 UI shell。错误分类必须贯通文案、按钮和实际动作；进度刷新、持久化和通知分层，状态事件立即处理。只按数字混用 curl 与 ArkWeb 错误码不可接受。

每阶段跑相关检查，并加入真实 Repository + Service + Bridge 边界回归；已有检查通过不能代替缺失场景。业务改动后有本地签名配置时，从仓库根执行 Community 构建。发布说明如修改，必须中英成对。

本地参考样本从用户提供的 hwbrowser 目录读取。HAP、反汇编、华为资源、日志与设备数据不提交。不得无授权抓屏。不得把无关服务器资料写入本仓库。

交付要列出：改动行为、回归结果、设备对照结果、仍未解决的差异。未完成设备对照时不得宣布完全对齐。
