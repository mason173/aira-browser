# Aira 下载对齐：任务入口（重新核验版）

旧版 Prompt A–E 依赖已撤回的 D1/D2/D3 与 T0–T8，请勿再使用。没有“先验一条回调就能全量照抄”的前提，也不提供未经验证的工期承诺。

证据见 [REA 重新分析](aira-browser-download-rea-reanalysis.md)，目标和顺序见 [实施规格](aira-browser-download-parity-spec.md)，完整交接见 [handoff](aira-browser-download-handoff-prompt.md)。

范围纠正：只对齐下载核心与传输逻辑，保留 Aira 原有交互。此前界面改造已撤回；普通主动文件下载从 libcurl 迁入来源 ArkWeb，特殊能力与旧任务单独兼容。以下模板为初始任务记录，后续先读实施规格第 8 节，不要把历史缺陷当作当前源码状态，也不要以视觉对照替代核心验收。

## 全量实施

    请按 docs/aira-browser-download-handoff-prompt.md 和新版 parity-spec，
    把 Aira 下载完整生命周期对齐华为 5.1.9.315 手机样本。
    先完成 P0-A 数据与事件结果，再完成待确认来源、真实准入和同 owner 恢复。
    保留 HLS/嗅探/用户脚本能力，不添加盲目 URL watchdog。
    实现每阶段后跑对应回归；明确本地探针和实际设备证据的区别。
    先读 AGENTS.md；直接在 main 工作，保留无关改动，不自行提交。

## 单阶段实施

    请完成新版 parity-spec 中指定的阶段，并读取其依赖与 REA 重新分析中的相关发现。
    若前置机制还未实现，先补必要前置，不按旧 T0–T8 机械修改。
    对用户可见结果给出验证，新增测试保留真实 Repository/Service 边界。
    不把平台替身结果称为设备验证。

## 行为验收

    请按新版 parity-spec 第 6 节，在指定的目标系统与华为样本上做同条件对照。
    记录请求次数、任务状态、实际字节、恢复方式、最终文件哈希与可用操作。
    先说明现有可用设备和未解前置，遵守本次设备/屏幕授权范围。
    未执行项保持待验收；不提交 HAP、反汇编、设备日志或私密数据。
