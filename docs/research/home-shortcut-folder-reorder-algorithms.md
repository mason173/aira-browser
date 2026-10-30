# 主页拖拽：成组与避让的仲裁算法

研究日期：2026-10-30。目标：解决拖近目标时“应该把目标挤开，还是保留目标以便成组”的控制问题。本文区分已读源码事实与 Aira 移植建议；研究阶段不修改功能代码，不采集或查看设备、应用、浏览器画面。

用户随后明确 LeafTab 的图标跟手、避让位移、成组边框、大文件夹以及打开/关闭动效都可作为参考。完整体验已补充到[LeafTab 拖拽动效与大文件夹参考](leaftab-home-drag-motion-and-large-folders.md)，后续应连同本篇规则一起作为迁移基线。

## 结论

成熟实现把拖拽定义成互斥的意图状态：普通移动、避让排序、新建组、加入已有组。**先判断意图，再决定是否允许避让。** LeafTab 在合组时保留已确认的排序投影，AOSP 在进入成组模式时撤回临时挤位；两种策略都明确控制避让，而不是等松手才追加合组判断。如果排序引擎始终自行移动目标，目标会在判定前被挤走。

LeafTab 是最贴近 Aira 的直接参考，现行代码已将核心规则、React 控制层和产品预设拆开；AOSP Launcher3 是本次查到最直接、完整的原生参考。LeafTab 普通图标默认中心确认 100 ms、外围避让 200 ms；已读 AOSP 版本进入中心区域即可给出成组反馈，避让延迟 650 ms。不要把前一轮提出的 400–600 ms 合组停留建议当成通用算法，也不要把 Web 的像素/计时参数直接视为鸿蒙触屏标准。


## LeafTab：本次最贴近 Aira 的直接参考

第一手源：[mason173/LeafTab](https://github.com/mason173/LeafTab)，固定提交 `0dbe1c4f4355f16ac30608e5099462908019e60f`。本次经 GitHub 接口读取源码到临时目录分析，未运行扩展或查看任何浏览器画面。项目已把交互拆成 `packages/grid-core`、`packages/grid-react`、`packages/grid-preset-leaftab`，可优先研究规则层和交互控制层。

### 1. 已确认实际生效的调用链

当前业务组件 [RootShortcutGrid](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/features/shortcuts/components/RootShortcutGrid.tsx#L1-L8) 引用包内 Grid 与 LeafTab preset；preset 注入 `resolveCompactTargetRegions`。包内运行链为：

```text
RootShortcutGrid
  → useRootShortcutGridControllerBundle
  → hoverFromPointer.resolveRootHoverResolutionFromMeasuredPointer
  → compactHover.resolveRootGridHoverResolution
  → resolvePrototypeAlignedCompactRootHoverResolution
  → hoverTiming.commitResolvedHoverResolution
  → dropCommit.commitRootPointerRelease
```

[实际分支选择](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootResolution/compactHover.ts#L578-L672)、[preset 注入](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-preset-leaftab/src/rootGridPreset.ts#L61-L83)。

仓库里另有较大的 `compactRootHover.ts`，但当前 preset 的主路径走上述 `rootResolution/compactHover.ts`。不能仅根据同名函数或旧的中心阈值，判断现行交互算法。

### 2. 用图标视觉中心命中，修正按下位置和滚动差

识别点不是裸鼠标/手指坐标。`getDragVisualCenter` 用 pointer 减去按下时相对预览的位置，再加预览可见部分的半宽、半高；同时统一滚动后的坐标。这使从图标角落开始拖动时，仍以被拖图标的视觉中心瞄准目标。[视觉中心计算](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-core/src/drag/gridDragEngine.ts#L42-L68)、[接入命中](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootResolution/hoverFromPointer.ts#L36-L76)。

### 3. 格子、图标、目标身份与动画位置分别管理

拖动开始测量并保存布局快照；拖动期间 measurement controller 优先返回该快照，滚动用坐标偏移补偿。它没有每帧读取正在 transition 的元素位置，再拿抖动的测量结果反过来决定排序。[开始快照](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootRuntime/sessionStart.ts#L125-L149)、[快照复用](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootGeometry/measurement.ts#L94-L100)。

后续命中又不是永远盯着原始位置：它根据**已确认**的排序建立 `displayedTargetBySlotIndex` 和拖动项占位 footprint，得到当前展示布局；再对快照应用已确认的投影偏移，建立稳定的“当前格子对应哪个实体”。命中自己的占位格不生成新目标。[投影布局与占位](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootResolution/compactHover.ts#L199-L275)、[命中当前展示布局](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootResolution/compactHover.ts#L324-L377)。

**工程含义：** 稳定命中需要“起始快照 + 已确认投影 + 实体 ID”，只冻结初始位置或只读动画位置都不够。

### 4. 中心合组区与外围避让区明确分开

当前普通目标格四边各内缩 24%，中间形成宽、高各 52% 的中心区域；大文件夹四边内缩 12%，中心区域宽、高各 76%。以上是格子归一化比例，不是占整个格子面积的 52%/76%，也不是固定像素。

`classifyGridHeatZone` 返回中心 core 或上下左右边缘 T/R/B/L；大文件夹的外围不触发这种局部边缘避让。文件夹本体拖动、组内排序、从组内提取等交互 profile 可以禁用合组，避免拖文件夹时意外生成嵌套组。[比例](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootShortcutGridContracts.ts#L30-L34)、[区域判定](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/sharedGrid/heatZone.ts#L11-L59)、[交互类型](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-core/src/domain/interactionProfile.ts#L31-L91)。

### 5. 最关键：合组意图与避让预览分开

进入中心且目标能接收时，返回的结果是：

```text
interactionIntent       = 合并两图标 / 加入已有文件夹
visualProjectionIntent  = 当前已显示的排序投影
```

这里没有继续为合组目标生成新避让，也没有把已经挪开的所有图标立刻弹回原位。后者会让目标位置随意图切换跳动，导致下一帧又命中另一个目标。LeafTab 保留当前确认过的预览布局，让合组反馈在稳定位置出现。[核心分支](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootResolution/compactHover.ts#L383-L430)。

这与 AOSP 的“进入成组后撤回临时排序”是不同策略。两者共同点是禁止排序和合组各自独立移动同一个目标；在连续避让后的体验上，LeafTab 的双意图结构更值得 Aira 优先验证。

### 6. 延迟主要保护合组机会，等待期间也有明确行为

| 普通根级图标的状态 | 当前 LeafTab 行为 |
| --- | --- |
| 进入中心区 | 立即显示中心候选，100 ms 后才成为可提交合组意图 |
| 在外围准备避让 | 默认等待 200 ms，期间保留上次已确认的排序预览 |
| 避让候选未变但识别点移动超过 1 px | 重启避让计时，持续经过时不急着挤开目标 |
| 从某目标中心退出到同一目标外围 | 可以跳过新一轮避让等待，避免退出成组后感觉粘住 |
| 目标变更或离开中心 | 撤销旧中心确认，清理旧计时 |
| 落在中性空隙 | 可保留已确认的避让预览，避免布局反复回弹 |

默认 100/200 ms 来自普通交互 profile；其他 profile 的避让延迟可为 0。1 px 和这些时间都属于 Web 项目参数，不能照搬为鸿蒙触屏标准。[默认 profile](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-core/src/domain/interactionProfile.ts#L31-L91)、[离开中心后跳过等待](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootRuntime/hoverTiming.ts#L60-L83)、[计时与显示/确认分离](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootRuntime/hoverTiming.ts#L197-L280)。

注意：100 ms 不是新建文件夹后的持久化延迟；200 ms 也不是每帧动画时长。它们控制的是交互意图何时确认。

### 7. 释放只提交已确认的结果

`commitRootPointerRelease` 从 `confirmedHoverResolutionRef` 解析最终意图；有合组/入组意图优先用交互意图，否则可回退为确认过的排序投影，随后只走一次业务提交并清理会话。因此刚碰到中心、还没完成确认就松手，不会因为一帧候选高亮就直接合组。[释放入口](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootRuntime/dropCommit.ts#L68-L117)、[最终意图优先级](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootShortcutGridHelpers.ts#L743-L748)。

`grid-core/domain/dropIntents.ts` 把三种根级操作分开：重排、请求新建文件夹、移入已有文件夹。这一层不依赖 React，可作为 ArkTS 规则层的结构参考。[意图应用](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-core/src/domain/dropIntents.ts#L66-L130)。

### 8. 能移植什么

优先移植视觉中心、稳定布局快照、已确认的投影映射、中心/边缘区域、双意图、候选/确认、计时取消和释放一次提交。保留 Aira 的原生 ArkUI 主页，把 React refs、DOMRect、CSS transform、React flushSync 分别改为原生会话状态、布局几何、ArkUI 属性动画和既有 coordinator 提交。

不建议先把 LeafTab 完整 Web 界面嵌进主页，也不建议直接复制其可变尺寸布局打包算法作为前提：API 26 可以负责部分布局，是否还能借用其内部排序，取决于能否让应用掌握合组期间的避让决策。

LeafTab 是与 Aira 同类的新标签页，且已经有独立算法分层；本需求应将它作为第一参考，AOSP 用来校验取消、模式互斥与释放重验。两套策略要选定一致的投影行为，不要把 LeafTab 的保留投影与 AOSP 的立即还原同时执行。

## AOSP Launcher3：参考版本与入口

第一手源：Google 的 `platform/packages/apps/Launcher3`，本次读取 `main` 固定提交 `2663cf0a414bd603d6a833cb691cea76eb1897b7`。下文链接均固定到该提交；通过 Gitiles `format=TEXT` 下载并逐段阅读真实源文件。

| 文件/函数 | 主要职责 |
| --- | --- |
| [Workspace.onDragOver / manageReorderOnDragOver](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/Workspace.java#2457) | 每次移动先判成组，后判避让；限制避让模式并设延迟 |
| [Workspace.manageFolderFeedback / ReorderAlarmListener](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/Workspace.java#2675) | 中心范围内进入新建组/加入组；延迟到期执行临时重排 |
| [Workspace.setDragMode](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/Workspace.java#2378) | 切换意图时取消竞争计时、清理候选与反馈 |
| [CellLayout.getFolderCreationRadius / getReorderRadius](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/CellLayout.java#928) | 根据图标可见尺寸和格子边界计算两个命中范围 |
| [CellLayout.revertTempState](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/CellLayout.java#1518) | 撤回临时排序坐标，动画还原未提交布局 |
| [Workspace.willCreateUserFolder / willAddToExistingUserFolder](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/Workspace.java#1870) | 检查目标类型、自身、临时挤位以及目标是否可接收 |
| [Workspace.onDragExit](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/Workspace.java#2307) / [drop 路径](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/Workspace.java#2046) | 保存最终成组意图；释放时先尝试组操作，再走普通落点 |

### 1. 先让成组拿到决策机会

`onDragOver` 用拖拽物的视觉中心计算最近格子和到目标视觉中心的距离，接着调用 `manageFolderFeedback`，再调用 `manageReorderOnDragOver`。这个调用顺序是关键：能否成组先于避让计算。[源码](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/Workspace.java#2486)

进入 `CREATE_FOLDER` 或 `ADD_TO_FOLDER` 后，`setDragMode` 会调用 `cleanupReorder(true)`，取消等待中的避让 alarm，清空上次重排位置。避让分支只允许在 `NONE` 或 `REORDER` 模式运行。每次移动尾部若处于成组模式，调用 `revertTempState()`，还原还没有提交的挤位布局。[状态切换](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/Workspace.java#2378)、[互斥与还原](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/Workspace.java#2514)

### 2. 两个半径加避让延时，避免“还没碰到中心就被挤走”

文件夹半径不是固定像素：`getFolderCreationRadius` 取避让半径与图标可见半径的平均值。对于可成组的 1×1 图标，`getReorderRadius` 使用格子可用空间较小方向的内接范围；源码注释明确说明此举是为了避免在有机会接受文件夹落点前过早重排。其他形状按占用尺寸计算更大的范围。[几何计算](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/CellLayout.java#928)

当目标被占用、意图允许排序、目标格子与上次重排不同、距离进入避让范围时，先显示 reorder hint，再设 `REORDER_TIMEOUT = 650` ms；目标变化会取消旧 alarm，重新记录格子并计时。到期才做 `MODE_DRAG_OVER` 重排。因此从边缘向中心移动时，合组判定有机会先截住避让。[常量](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/Workspace.java#249)、[调度逻辑](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/Workspace.java#2524)

这 650 ms 是已读版本的实现参数，不是 Aira 应照搬的常量。快速拖动通常不会在同一目标完成计时，但在已读仲裁函数内没有显式速度阈值。

### 3. 成组候选必须是稳定实体

`willCreateUserFolder` 排除空目标、自身和不允许进入文件夹的项目；新建和加入组都会排除使用临时坐标且已经偏离正式位置的目标。其意义是：不能把已经被挤向别处的图标继续当成原位合组目标。目标格子变化会重置模式；离开成组半径时退出成组模式并清理反馈。[候选检查](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/Workspace.java#1877)、[格子变化](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/Workspace.java#2370)、[退出范围](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/Workspace.java#2675)

已读版本使用相同的文件夹半径进行进入/退出判断，未在这一层实现“进入小半径、退出大半径”的双阈值迟滞；不能把迟滞说成该源码已有。防重复重排依靠目标格子记忆、计时和互斥模式。若 Aira 增加双阈值，应标注为移植后的调优策略。

### 4. 候选反馈与真正写入分开

悬停时只展示文件夹背景或接收反馈。`onDragExit` 在清理拖拽状态前保存本次是否准备新建组/加入组；释放时重新算距离并检查标志与目标类型，先尝试 `createUserFolderIfNecessary` / `addToExistingFolderIfNecessary`，成功就返回，不再走普通落位。这个顺序避免同一次拖动同时合组和排序。[保留最终意图](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/Workspace.java#2307)、[提交前检查](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/Workspace.java#1928)、[提交顺序](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/Workspace.java#2054)

已有文件夹的自动展开另有 `ON_OPEN_DELAY = 800` ms。`FolderIcon.onDragEnter` 显示接收态并安排展开；`onDragExit` 撤销展开 alarm。这与“两图标形成新组”的判断分开。[常量](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/folder/FolderIcon.java#112)、[进入/退出](https://android.googlesource.com/platform/packages/apps/Launcher3/+/2663cf0a414bd603d6a833cb691cea76eb1897b7/src/com/android/launcher3/folder/FolderIcon.java#283)

## OpenHarmony Launcher：适合补业务路径，避让仲裁参考价值较弱

第一手源：`openharmony/applications_launcher`，固定提交 `f75dfb6bf7276e942793b75e7a9081bbcd015843`。其 `PageDesktopDragHandler.onDragDrop` 根据最终目标：已有文件夹就加入，普通应用就生成组；普通落位则转到 `checkAndMove`，后者按占用矩阵移动文件夹/卡片和应用项。[释放路径](https://github.com/openharmony/applications_launcher/blob/f75dfb6bf7276e942793b75e7a9081bbcd015843/feature/pagedesktop/src/main/ets/default/common/PageDesktopDragHandler.ts#L229-L342)、[占用矩阵与挤位](https://github.com/openharmony/applications_launcher/blob/f75dfb6bf7276e942793b75e7a9081bbcd015843/feature/pagedesktop/src/main/ets/default/common/PageDesktopDragHandler.ts#L450-L505)

已读 `SwiperPage` 的通用 `onDragMove` 路径主要做页边切页；其 `itemMove`/切页延时和最终 drop 是分开的。此入口没有像 AOSP 的 `manageFolderFeedback → cancel reorder → revertTempState` 那样完整展示逐次移动的互斥状态机，因此不把它当作成组与连续避让仲裁的首选样本。[移动与切页](https://github.com/openharmony/applications_launcher/blob/f75dfb6bf7276e942793b75e7a9081bbcd015843/feature/pagedesktop/src/main/ets/default/common/components/SwiperPage.ets#L138-L169)、[拖拽回调](https://github.com/openharmony/applications_launcher/blob/f75dfb6bf7276e942793b75e7a9081bbcd015843/feature/pagedesktop/src/main/ets/default/common/components/SwiperPage.ets#L251-L286)

## 对 Aira 的移植建议

以下为工程推论，不是 ArkUI 已验证保证：

1. 用一个拖拽会话统一持有原始顺序、临时预览顺序、当前目标 ID、命中几何、意图、计时 token。目标身份必须与屏幕上的动画位移分开。
2. 每次移动先用稳定目标几何判成组，随后才允许安排避让。进入成组候选即暂停新的目标避让、取消 pending reorder，已有投影优先参考 LeafTab 保持稳定；不要同时执行 AOSP 的全部回原位逻辑。离开候选后恢复排序判断，成组高亮在真实提交前可撤销。
3. 避让是可撤销预览，不能每次挤位就改掉持久化的正式顺序；最终松手只提交一个结果，取消恢复原快照。异步 timer 需核对拖拽会话 token 和目标 ID，不能把旧候选应用到新目标。
4. “中心立即接收 + 外围延迟避让”有 AOSP 实证；“中心停留一段时间才接收”也可以设计，但中心等待期间同样必须保护目标，不能让避让计时先完成。参数需按触屏与鼠标分开调优。
5. API 26 的 Grid.onMove 能做原生重排，不等于应用能暂停某个目标的内部挤位或撤回它的临时坐标。是否能取得连续坐标、拦截 reorder、保留候选和控制落位，需要最小验证。若无这些控制点，应使用单一通用拖拽通路管理成组/避让，再由原生布局与动画呈现，不能把两套决策同时挂上去。

## 证据边界

本文读取的是第一手仓库固定版本源码；没有运行 Launcher、测试其手感或性能，也没有验证 ArkUI 与该算法的兼容性。Android View/CellLayout 与 OpenHarmony 系统桌面都不是 Aira 可原样调用的公共组件；可迁移的是命中、模式互斥、延迟与提交规则。
