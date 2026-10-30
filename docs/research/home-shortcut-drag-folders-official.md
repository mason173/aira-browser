# 默认主页图标拖拽合组：官方参考与 Aira 实现评估

研究日期：2026-10-30。范围：HarmonyOS NEXT、ArkTS/ArkUI、Stage 模型；先评估，不实现功能。本文把华为公开 SDK 文档、OpenHarmony 系统桌面源码和工程建议分开说明。

方案前提更新：用户已明确允许升级到 API 26。后续交互方案可将 API 26 作为运行基线，不再把现有 API 23 配置当成选型障碍；本次仍处于研究阶段，构建配置尚未改动。

算法研究补充：已进一步读取用户提供的 LeafTab 和 AOSP Launcher3 的真实实现，详见[成组与避让仲裁算法](home-shortcut-folder-reorder-algorithms.md)。后续应优先验证应用对避让的控制权，并移植 LeafTab 的布局快照、已确认投影、双意图和候选确认规则；API 26 原生排序能否承载这些控制仍待验证。下文 400–600 ms 是早期建议初值，不能代替后续研究中 LeafTab 的 100/200 ms 分离计时或 AOSP 的延迟避让策略。

## 结论

可以实现，平台提供拖拽、目标命中、悬停检测、自定义预览和动画等基础能力。**“图标拖到图标上创建组”仍然是应用的数据操作与交互策略。** 本次未找到普通应用 SDK 内置的一键合组组件，或把排序、悬停合组、文件夹展开和拖出拆组全部打包的华为官方示例。

找到两层可参考材料：华为文档里的 Grid 拖拽完整示例适合验证公共 API；OpenHarmony 官方 Launcher 源码实际实现了拖到应用图标创建文件夹、拖到文件夹加入已有文件夹的逻辑。后者是系统应用，不能当成普通 HarmonyOS 应用可原样引入的组件。

在允许升级 API 26 的前提下，优先验证原生 Grid + onMove 的排序和动画能力能否与合组意图配合。但现有多列 List 已有 onMove，升级主要增加原生 Grid 这一选择，并不会自动补齐中心命中、停留成组、文件夹实体或同步规则。API 版本不再构成障碍，合组控制权与数据一致性仍是主要验证点。

## 1. 最值得直接看的官方材料

|材料|已核对的代码/内容|可复用的部分|
|---|---|---|
|[华为：拖拽排序](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-drag-sorting)|示例 1、2：`ForEach.onMove` 修改源数组顺序，第二个参数提供长按、拖动、经过条目、落下回调|现有排序能力及其边界|
|[华为：API 26 Grid 原生排序示例](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-drag-sorting#示例3grid规则布局使用foreach的onmove进行拖拽并设置拖拽事件回调)|示例 3 为规则 Grid 的 ForEach.onMove；示例 4–6 展示跨行跨列项目|升级后的首选原生网格排序验证基线；不含合组业务|
|[华为：Grid 网格元素拖拽](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-grid-element-drag-exchange)|完整长按 + `PanGesture` 组合手势代码，跟手位移和 `animateTo` 动画|自定义拖动与挤位动画的实现方式|
|[华为：Grid 参考，示例 5、16、17](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-grid)|示例 5 使用 `onItemDragStart/onItemDrop`；16 自定义手势；17 使用通用 `onDragStart/onDragEnter/onDrop`，并说明拖到边缘自动滚动|系统拖拽、通用拖拽和自定义手势三种实现路径的实际代码|
|[华为：支持统一拖拽](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-common-events-drag-event)|拖出/拖入职责、预览图、坐标；“支持悬停检测”给出拖文件悬停文件夹自动打开的场景|已有文件夹悬停展开、拖拽生命周期与目标处理|
|[华为：拖拽事件](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-events-drag-drop)|`onDragMove`、`onDrop`、`onDragEnd`、`onDragSpringLoading`、`DragEvent`|精确命中、提交和取消、API 起始版本|
|[OpenHarmony 官方 Launcher：PageDesktopDragHandler](https://github.com/openharmony/applications_launcher/blob/f75dfb6bf7276e942793b75e7a9081bbcd015843/feature/pagedesktop/src/main/ets/default/common/PageDesktopDragHandler.ts#L229-L309)|真实 `onDragDrop(x,y)` 根据目标类型执行加入文件夹或新建文件夹|合组业务判定与职责划分|

## 2. SDK 能做什么，不能直接替应用决定什么

### 2.1 原生排序不等于创建文件夹

官方 `onMove` 的约定是拖放后更新数据顺序，并保留数据项身份，才有正常落位动画。`onMove` 提供 `from/to`；API 20 增加的 `ItemDragEventHandler` 中，`onMoveThrough` 仍只提供 `from/to`，`onDrop` 只提供结束索引。它们没有给应用连续拖动坐标或“合并目标”语义。[来源：拖拽排序](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-drag-sorting)

**工程判断：** 不宜在原本只负责排序的 `onMove` 回调内直接把两个顶层项目替换成一个新文件夹，再假定系统排序动画仍然正确。创建文件夹改变了项目数量和身份，需要单独的提交路径及相应动效。

版本边界要特别注意：当前最新文档虽然总述同时提到 List 和 Grid，但明确标注 **Grid 的 `onMove` 从 API 26.0.0 才支持，且只支持可滚动 Grid**。用户已接受升级，因此这一版本要求不再是方案障碍；可直接以该页示例 3 的规则网格为验证起点。List 的基础 `onMove` 为 API 12 起，带阶段回调的重载为 API 20 起。即使升级，数据只能改变顺序的动画约定仍然成立。[来源同上]

### 2.2 精确区分“插入排序”与“覆盖合并”需要坐标和策略

通用 `onDragMove` 回调包含 `DragEvent`，可以获取拖动点坐标；目标组件还需要注册 `onDrop`，`onDragMove` 才有效。`onDrop` 由接收方处理数据；`onDragEnd` 可让发起方处理成功、失败和清理。[来源：拖拽事件](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-events-drag-drop)

**工程建议：** 同一格子划分中心合并区与外围排序区。进入中心并稳定停留后显示合组反馈；退出中心、快速掠过、目标变化或取消时撤销候选。只有在释放时提交“新建组”或“加入已有组”。具体命中半径和停留时长需要实机调校，不是官方强制值。

本次未找到华为文档保证 `ForEach.onMove` 排序与另加一套通用 `onDragMove/onDrop` 在同一次拖拽中能自然协作、并由应用无缝接管中途的系统挤位。两者有不同回调和动画约定。**先做最小交互验证；若无法稳定保留合并候选，应让一个拖拽会话统一管理排序与合组。** 不把“没有找到混用保证”表述成平台绝对禁止混用。

### 2.3 悬停展开已有文件夹有正式 API

`onDragSpringLoading` 从 API 20 开始支持，适用于 Stage 模型。官方指南明确举例：拖文件悬停在文件夹上时自动打开文件夹。回调具有 `BEGIN/UPDATE/END/CANCEL` 状态，可用于提醒、展开和取消；目标检测遵守拖拽命中规则，同一位置只由一个目标响应，子组件优先。[来源：支持统一拖拽“支持悬停检测”](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-common-events-drag-event#支持悬停检测)、[API 参考](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-events-drag-drop#ondragspringloading20)

它可以帮助实现“拖住图标悬停已有组，自动打开后放进去”，但不会自动创建文件夹、更新成员关系或决定组名。对于“两个单图标合组”的短暂停留，仍需产品定义触发规则。

### 2.4 预览与动画也有边界

官方支持用 `onDragStart` 返回的 `CustomBuilder/DragItemInfo` 或 `dragPreview` 设置拖拽背板。这个 builder 生成的是当次拖动的图片，修改 builder 不会实时更新当前已经生成的背板。`DragEvent.useCustomDropAnimation` 可在通用 `onDrop` 阶段禁用系统落位动效，使用应用自定义动效；若保留系统动效，官方要求避免同时叠加自定义落位动效。[来源：拖拽事件](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-events-drag-drop)、[支持统一拖拽](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-common-events-drag-event)

因此，合组候选更适合让**目标图标/文件夹本身**变大、出现底板或小图标预览。合组成功后的缩入动画应由明确的动画责任方处理。

## 3. 华为 Grid 完整例子怎么参考

已阅读官方实际代码，而非只依据标题：

- **Grid 示例 5：** `LazyForEach`、`onItemDragStart` 自定义浮起图，`onItemDrop` 读取起始/插入索引后交换数据，`supportAnimation(true)` 提供拖动动画。这个例子只交换位置，没有文件夹模型。
- **Grid 示例 16：** `GestureGroup(GestureMode.Sequence, LongPressGesture(...), PanGesture(...))`；手势更新中计算 `offsetX/offsetY`，用弹簧动画移动数据/位置。适合参考应用完全掌控拖动意图的路径。示例含固定三列和硬编码尺寸，正式产品要改为实际布局计算。
- **Grid 示例 17：** 每个 `GridItem` 注册通用拖拽事件，在 `onDragStart` 携带来源信息，在目标 `onDrop` 交换数据；官方说明这一方案支持拖到 Grid 边缘时自动滚动。它仍是排序例子，没有合组交互。

[三例原文与完整代码](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-grid)

额外限制：传统 `onItemDragStart` 与在 `GridItem` 上额外绑定的长按手势可能发生识别冲突，官方建议需要长按与拖拽同时使用时采用通用拖拽。传统 Grid 项目拖拽不自动处理边缘滚动；官方引导使用通用拖拽或 API 26 的 `onMove`。`supportAnimation` 的内置动画针对规则尺寸/滚动模式，不能据此承诺任何网格布局都有系统动效。[来源：Grid 参考](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-grid)、[Grid 网格元素拖拽](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-grid-element-drag-exchange)

核对时也发现当前 Grid 参考的 `editMode` 属性说明与该页示例 5/16 对模板的用法存在差异，因此不把“照抄 editMode 配置即可得到目标体验”作为结论；接入前需以项目实际 SDK 行为验证。

## 4. 有真正合组逻辑的 OpenHarmony 官方桌面源码

核对版本：`openharmony/applications_launcher`，提交 `f75dfb6bf7276e942793b75e7a9081bbcd015843`。以下链接固定到该提交。

1. **拖动坐标交给独立 handler。** [`SwiperPage.ets` 251–286](https://github.com/openharmony/applications_launcher/blob/f75dfb6bf7276e942793b75e7a9081bbcd015843/feature/pagedesktop/src/main/ets/default/common/components/SwiperPage.ets#L251-L286) 的通用 `onDragMove` 读取窗口坐标，`onDrop` 调用 `PageDesktopDragHandler.onDragDrop`。
2. **在释放时根据目标决定动作。** [`PageDesktopDragHandler.ts` 229–309](https://github.com/openharmony/applications_launcher/blob/f75dfb6bf7276e942793b75e7a9081bbcd015843/feature/pagedesktop/src/main/ets/default/common/PageDesktopDragHandler.ts#L229-L309) 中，目标为 `TYPE_FOLDER` 就调用 `addOneAppToFolder`；目标为 `TYPE_APP` 则收集目标和来源，调用 `addNewFolder`。同位置、文件夹和卡片等另行处理。
3. **文件夹数据操作归 viewmodel。** [`BigFolderViewModel.ts` 126–184](https://github.com/openharmony/applications_launcher/blob/f75dfb6bf7276e942793b75e7a9081bbcd015843/feature/bigfolder/src/main/ets/default/viewmodel/BigFolderViewModel.ts#L126-L184) 的 `addNewFolder` 从桌面布局移除原应用项，生成文件夹对象并纳入原应用；随后 `addOneAppToFolder` 处理加入已有文件夹。

**适合借鉴：** 把坐标和拖动生命周期、目标判定、文件夹数据提交、文件夹 UI 拆开；使用“排序/新建组/加入已有组”不同业务动作；用稳定实体身份组织数据。

**适用边界：** 仓库 README 标明这是 OpenHarmony Launcher，并描述 full SDK 的编译要求；[`phone_launcher/module.json5`](https://github.com/openharmony/applications_launcher/blob/f75dfb6bf7276e942793b75e7a9081bbcd015843/product/phone/src/main/module.json5#L53-L96) 申请多项系统权限。它不是当前 HarmonyOS NEXT 普通应用的现成依赖，也不能保证它的系统 API、旧 ArkTS 写法或固定桌面布局约束适合 Aira。源码有 Huawei Device 版权声明并采用 [Apache-2.0](https://github.com/openharmony/applications_launcher/blob/f75dfb6bf7276e942793b75e7a9081bbcd015843/LICENSE)。当前只做参考，不导入该仓库代码或资源。

## 5. 工程风险与建议验证顺序

以下均为根据官方能力做出的工程建议，不是已经在 Aira 真机验证的结论。

1. 先验证一屏图标的拖动意图：外围经过正常挤位，中心稳定停留进入合组候选，离开立即取消，释放才提交。特别关注系统排序是否把候选目标提前挤走。
2. 验证长按菜单、主页上下滚动、鼠标拖动与手势竞争，并确保取消、拖出容器、应用失焦等情况清理候选状态。
3. 再接新建组/加入已有组的持久化、组名与文件夹预览，保证一次拖动只提交一次业务事务，取消不写数据。
4. 最后增加组内排序、拖出还原为顶层项、剩一个项目时组的处理、已有组悬停展开以及跨屏拖动。

一层文件夹、明确合组反馈和稳定取消的范围属于可控的中等交互开发；如果要求完整手机桌面的多页、组内外连续拖拽和细腻动效，难度会明显增加。主要难点是意图区分、排序与合组的控制权、跨层数据一致性和动画时序，公共 SDK 的基础拖拽能力本身并不是缺口。

## 6. 研究方法和未验证项

使用华为 HarmonyOS 官方知识检索读取上述文档完整内容，并核对官方页面及 OpenHarmony 官方仓库实际源文件。未引用第三方教程作为平台事实依据。本次未运行示例，未进行设备、模拟器、浏览器或桌面视觉采集；文档中的动画链接仅用于定位官方材料，未下载或复制媒体。`onMove` 与通用拖拽混用、现有长按菜单竞争和最终动效仍需后续交互验证。

## Aira 现有实现与落地评估

以下为对当前 `main` 源码的静态检查，以及基于官方资料的工程建议，不代表已完成实现或真机验证。

### 当前不是缺少一个“开启分组”属性

- 原生主页的收藏宫格由 [HomeShortcutSurface.ets](../../AiraBrowser/entry/src/main/ets/app/components/browser/HomeShortcutSurface.ets) 使用多列 `List.lanes` 呈现，并在 `ForEach.onMove` 的结束回调里提交 `move_shortcut`。它已经覆盖拖动排序，当前没有合并、加入文件夹、移出文件夹动作。
- 同一组件另有 450 ms 长按菜单、长按后移动关闭菜单、拖动期间屏蔽点击和冻结图标内容的处理。新增交互必须接上这些生命周期，避免合并时弹菜单、松手打开网页或取消拖动后无法滚动。
- [ClassicHomeFrame.ets](../../AiraBrowser/entry/src/main/ets/app/components/browser/ClassicHomeFrame.ets) 和 [CenteredHomeFrame.ets](../../AiraBrowser/entry/src/main/ets/app/components/browser/CenteredHomeFrame.ets) 共用此组件，并在拖动时暂停父级滚动。无需复制主页；需要同时检查两种布局的宽度、末行居中、隐藏图标名等命中几何。
- [build-profile.json5](../../AiraBrowser/build-profile.json5) 的公开模板将 compatible/target SDK 均设为 `6.1.0(23)`。这是当前源码状态；用户已允许升级 API 26，因此后续可采用 Grid.onMove。直接以 API 26 运行且不保留旧系统回退时，需要同步落实最低兼容版本、目标版本和本地构建 SDK，而不只是调整 target。

### 现有数据边界

| 位置 | 当前事实 | 对文件夹功能的影响 |
| --- | --- | --- |
| [BrowserModels.ets](../../AiraBrowser/entry/src/main/ets/common/models/BrowserModels.ets)，ShortcutRecord | `kind` 只有 web/system；没有稳定文件夹 ID、父节点字段或子节点集合 | 需要显式定义文件夹实体与成员关系 |
| [HomeShortcutLogicService.ets](../../AiraBrowser/entry/src/main/ets/services/shortcuts/HomeShortcutLogicService.ets) | 显示、查找、去重、克隆和位置归一化面向平铺链接集合 | 不能只在 UI 里把两项包成一组；聚合投影与排序需同步适配 |
| [BrowserRepositories.ets](../../AiraBrowser/entry/src/main/ets/data/repositories/BrowserRepositories.ets)，normalizeShortcutForLocalReplace | 当前替换路径重建记录，并把 `folderName` 写为“首页” | `folderName` 不能直接充当文件夹身份，改个名字也无法持久保存成员关系 |
| [BrowserDatabase.ets](../../AiraBrowser/entry/src/main/ets/data/database/BrowserDatabase.ets)，mapShortcutRows/toShortcutValues | 表中仍有 `children`、`folder_display_mode` 列，但现行读取不投影它们，写入固定为 null | 这些残留列不构成现成可用的分组实现 |
| [PersonalizationSyncModels.ets](../../AiraBrowser/entry/src/main/ets/common/models/PersonalizationSyncModels.ets) | home_shortcuts 同步 scenarios、shortcuts，以及按 scenario 的一份 ID 顺序 | 文件夹内、外两层顺序需要明确表达 |
| [PersonalizationSyncSnapshotValidationService.ets](../../AiraBrowser/entry/src/main/ets/services/sync/PersonalizationSyncSnapshotValidationService.ets) | 校验只允许 web/system 两种 kind | 直接上传 folder 类型会被现行校验拒绝，必须考虑版本与旧客户端兼容 |
| [CustomHomepageBridgeService.ets](../../AiraBrowser/entry/src/main/ets/services/customhome/CustomHomepageBridgeService.ets) | 第三方主页使用同一快捷方式集合，并按 web/system 投影 | 需保留完整链接可达性，并定义第三方主页的兼容显示/排序契约 |

[ADR 0044](../adr/0044-home-web-shortcuts-are-independent-from-bookmarks.md) 已明确：从书签添加到主页是复制为独立 Web Shortcut。因此本需求属于主页快捷方式与 Personalization 同步领域，不应借用书签目录或改动书签树。

[ADR 0045](../adr/0045-home-shortcut-kinds-share-one-ordered-aggregate.md) 已明确：Web/System 快捷方式共用一个有序聚合。文件夹设计应扩展这个聚合及现有 repository/coordinator，不应另造第二套收藏存储或平行排序系统。本次只提出设计方向，不修改既有 ADR。

### 建议的首版交互

1. 长按并移动开始拖动，保留原生浮起预览；进入拖动后关闭快捷菜单。
2. 移到两枚图标之间的区域，预览插入位置；移入目标图标中心，并稳定停留约 400–600 ms 后，显示合并高亮。这个时间是待调试的初值，不是华为规定值。
3. 松手时根据当前意图只提交一次操作：普通换位、两项建组、加入已有组。离开中心区域或取消拖动就撤销合并候选，不能路过就成组。
4. 文件夹使用小图标拼图和名称；点击展开，支持重命名、组内排序和拖出。首版仅做一层文件夹，不允许文件夹套文件夹。
5. 默认建议保留只剩一项的文件夹，等用户主动移出最后一项时清理空组；自动解散也可另定规则，但必须先定义跨端并发与删除行为。
6. “添加”和居中主页固定的“设置”入口是派生 UI，不是 ShortcutRecord，必须排除在合并、移动入组和删除动作之外。已有真实 web/system 快捷方式仍遵循同一聚合规则。

上述中心命中、停留阈值、单层限制与空组策略均为工程/产品建议，而非官方组件自带行为。

### 技术路线建议

在允许升级 API 26 的前提下，先验证“原生 Grid + onMove 排序 + 应用合组意图策略”。参考官方示例 3 保留原生跟手和挤位，重点确认连续坐标、中心停留期间保留目标、取消排序或切换到合组的控制权。onMoveThrough 只给索引，不能单靠它判断进入图标中心；不能把升级等同于这些控制能力已获保证。

同时要验证布局条件：官方只在可滚动 Grid 中支持 onMove，而 Aira 当前收藏宫格按内容高度展开，页面滚动交给父级 Scroll，不能只把 List 名称替换成 Grid。需要确认短列表、长列表及父级滚动协调；只有为了规则图标排序，没有必要仅因版本提高就替换已经可用的多列 List。

若原生排序不能可靠让出合组控制权，使用“原生 Grid 或现有布局容器 + 官方通用拖拽事件 + 应用自己的落点/合并意图策略”，由同一通路管理排序与合组。原生拖拽负责预览和生命周期；应用负责排序预览、中心命中、悬停计时和一次性数据提交。

不应在现有 `onMove` 回调里直接删掉两项再添加文件夹，这超出了官方只改变顺序的落位动画契约。也不能未经验证就假设 `onMove` 的内部拖动与通用 `onDragMove/onDrop` 是同一套事件流。若二者不能可靠配合，应让同一条通用拖拽通路同时承载排序和合并，避免两个手势所有者互相抢状态。手动 LongPress + Pan + 自绘悬浮层可以作为后备方案，代价是自行维护预览、取消、滚动、鼠标与边缘移动。

数据上优先评估：在既有快捷方式聚合里给文件夹稳定 ID，成员通过稳定父 ID 关联，各容器有自己的顺序。这样图标移动时保留原记录 ID，而不是复制链接、删除旧记录。具体结构需在实现前结合同步兼容性确认，不建议仅按文件夹名称分组，也不建议把整个文件夹及所有孩子序列化成一个不可独立合并的大字段。

合并、移入、移出、删除空组应由 [HomeShortcutStateCoordinator.ets](../../AiraBrowser/entry/src/main/ets/core/shortcuts/HomeShortcutStateCoordinator.ets) 及现有 services/data 所有者提交为一致的聚合变更，UI 只上报意图。跨端要验证：同时移动同一图标、同名不同文件夹、文件夹已删但成员仍存活、两端并发加入成员、旧客户端重新排序、Provider 切换时 live-over-opposing-tombstone 的既有规则。成员不能因找不到父组而永久消失。

### 难度与下一步

| 范围 | 难度判断 | 主要工作 |
| --- | --- | --- |
| 单屏内存演示：拖两枚图标成组并展开 | 中等偏低 | 几何命中、停留反馈、展开层 |
| Aira 可用首版：持久保存、组内排序、移出、取消恢复 | 中等 | 统一拖拽状态、聚合与数据库读写、两种原生主页 |
| 完整体验：跨端同步、旧版本兼容、边缘滚动、鼠标、连续拖入拖出、细致动画 | 中高 | 并发语义、兼容策略、拖拽生命周期与实机调优 |

建议实现前先做一个很小的交互验证：在同一宫格里区分“从两侧经过换位”和“中心停留准备成组”，确认取消拖动、长按菜单和父级滚动都能恢复。验证通过后再一次性补齐文件夹聚合、持久化和同步契约，而不是把内存演示直接当成可发布功能。

本次只完成文档与静态源码研究；没有修改功能代码，没有构建/安装，没有操作或采集设备、模拟器、桌面、浏览器或应用画面，尚无真机手感或性能结论。

## 实现记录（2026-10-30）

研究阶段之后，原生首页采用同一份应用布局投影管理命中、避让与动画：`HomeShortcutGridPolicy` 负责混排，`HomeShortcutDragSession` 仲裁中心成组与边缘排序，`HomeShortcutSurface` 使用原生 LongPress/Pan 和定位节点呈现。没有同时启用系统 onMove，以免两条通路争夺成组目标。

当前规则为长按 450ms 后移动；不移动时松手显示菜单。进入可见图标中心即显示边框，停留 100ms 后允许成组；排序停留为 200ms。组内越界 500ms 连续交接主页，可继续排序或加入另一组。提取预览不写库，松手才提交归属、最终目标与顺序；取消保留原数据。普通图标移动时保留大文件夹的排序槽位，大文件夹占 2×2。加入既有组追加到末尾，显式移出/删除导致源组只剩一项时自动解散；这取代了研究阶段保留单项组的初步建议。

文件夹展开/收起采用 765/550ms 的独立子图标过渡，关闭包含滚动偏移，坐标转换以实际 cover 原点为准。组内浮标位于 cover 顶层，正常内容仍由 Scroll 裁切。API 下限与目标已升到 26。

文件夹使用平铺聚合中的 `parentId` 与 `folderDisplayMode`，数据库为 schema8。孤儿成员投影回主页而不改写同步归属；本地显式操作才解散小组。三方保存仅应用本地改动，保留并发新增与未改字段，删除版本严格递增。备份与 custom-home 叶子投影保留原实体身份。

同步读取 schema2/3。没有文件夹字段的快照继续使用 v2，文件夹/成员及其 tombstone 使用 v3，旧客户端不能将不理解的结构当作空数据覆盖。Personal Server 和 WebDAV 的既有传输版本/路径不变；Aira Cloud 服务端必须支持 v3 与文件夹字段后才能同步该结构，客户端构建通过不代表服务端已经升级。

验证覆盖真实生产规则、持久化映射、7→8 迁移的成功/失败、备份往返、普通删除和 Provider 切换保活，以及 Community 编译打包。未安装或采集设备画面，动画手感、触摸/鼠标和长列表性能仍需实机交互验收。

服务端兼容补丁已在本地验证：同时接受 v2/v3，保留文件夹字段；隔离 HTTP/SQLite 回归及完整服务端测试通过。补丁尚未部署，线上文件夹同步须在服务端升级后生效。
