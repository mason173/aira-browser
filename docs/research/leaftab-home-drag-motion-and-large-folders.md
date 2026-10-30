# LeafTab 主页：拖拽动效与大文件夹参考

研究日期：2026-10-30。固定源码版本：`mason173/LeafTab@0dbe1c4f4355f16ac30608e5099462908019e60f`。本轮研究范围扩展为整套交互体验：图标跟手、其他图标位移、落位、成组候选反馈、文件夹展开收起及大文件夹。下述内容区分当前业务接线、包内能力与 Aira 移植建议；不修改功能代码、不运行扩展、不操作或采集设备与浏览器画面。

## 文件夹展开与收起：现行调用链

业务入口 [App.handleShortcutActivate](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/App.tsx#L647-L693) 等待 overlay 模块预热后，按 folderId 在预览 registry 找到源外框、圆角、标题及每个 childId 对应的小图标位置，再调用 FolderTransitionController.openFolder。此处用 requestId 避免较旧异步打开请求覆盖新请求。

[ShortcutExperienceRoot](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/features/shortcuts/app/ShortcutExperienceRoot.tsx#L89-L124) 订阅 transition 状态，并把 phase/progress/sourceSnapshot 传给 ShortcutFolderCompactOverlay；overlay 使用业务版 [FolderShortcutSurface](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/features/shortcuts/components/FolderShortcutSurface.tsx#L350-L390)，后者再调用当前业务 RootShortcutGrid。因此应沿产品接线研究，不应把包内同名 FolderShortcutSurface 当成当前产品壳。

### 1. 先测量、后播放，运动层与交互层分开

过渡阶段明确分为：

```text
idle → opening-measure → opening-animate → open
open → closing-measure → closing-animate → idle
```

opening-measure 会渲染不可见的布局层，测量最终面板、标题、图标和标签位置；布局就绪才 notifyOpeningReady。动画中使用 ghost 图标层，open/closing-measure 才显示真正可排序的文件夹内容层；避免动画图标和可交互列表同时重复绘制。[测量和开始通知](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/ShortcutFolderCompactOverlay.tsx#L795-L945)、[层切换](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/ShortcutFolderCompactOverlay.tsx#L997-L1010)。

收起时不是永远返回打开瞬间的旧坐标：closing-measure 会重新查询根主页的 folder preview 和其 child slot，适应期间成员、排序或主页位置变化。[收起重新测量](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/ShortcutFolderCompactOverlay.tsx#L827-L874)。

这套模式适合移植为“布局就绪后开始动画、动画层统一持有源/目标几何”；需要在 ArkUI 的布局与显示状态中重新表达。

### 2. 外框、标题、小图标分别运动

每个 childId 优先使用源缩略图的真实 rect，没有对应 child rect 时用同 index 的源槽位；预览中不可见的项目则生成虚拟缩略图位置。每个 ghost 从自己的源 rect 插值到展开列表的目标 rect，不是把整个面板等比放大后直接显示全部图标。[源槽位 registry](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/shortcuts/folderPreviewRegistry.ts#L71-L135)、[每项插值与 ghost](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/ShortcutFolderCompactOverlay.tsx#L1140-L1266)。

面板圆角在源圆角与展开的 32 px 间插值；标题单独从源标题框向目标标题框移动，字号从 12 px 到 22 px，另带 10 px→0 的纵向位移。子图标标签也单独处理位置和透明度。[外框与标题](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/ShortcutFolderCompactOverlay.tsx#L989-L1040)、[标题绘制](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/ShortcutFolderCompactOverlay.tsx#L1110-L1138)。

文件夹内部始终保留标题高度，即使标题暂时隐藏也不改变图标行高，避免文字淡入时顶动图标。[固定标签空间](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/features/shortcuts/components/FolderShortcutSurface.tsx#L227-L231)。

### 3. 节奏不是统一一条动画

| 已读参数 | 当前源码值/行为 |
| --- | --- |
| 完整打开 / 关闭基准时长 | 765 / 550 ms |
| 打开曲线 | cubic-bezier(0.215, 0.61, 0.355, 1) |
| 关闭曲线 | cubic-bezier(0.32, 0.72, 0, 1) |
| 子图标打开错峰 | 归一化进度基准 0.045，每项增加 0.028 |
| 子图标关闭错峰 | 归一化进度基准 0.02，每项增加 0.018 |
| 标题和 chrome | 从进度 0.05 后开始自己的重映射 |
| 未在折叠预览中可见的图标 | 虚拟源位置；打开时从 0.32 的透明度起步并延后显现，标签再晚一些 |
| 过渡生命周期清理 | animationRunId 排除过期帧，cancelAnimationFrame 清前一播放任务 |

[时长、曲线、错峰和背景进度函数](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/shortcutFolderCompactAnimation.ts#L9-L153)、[控制器](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/folderTransition/useFolderTransitionController.ts#L65-L185)、[不可见项与标签处理](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/ShortcutFolderCompactOverlay.tsx#L60-L75)。

这些进度会经过控制器与各图层的再次映射，不能把错峰比例简单理解为“固定每项延迟若干毫秒”。控制器支持取消旧播放，但 requestClose 当前会把 closing-measure 的 progress 设为 1；不能仅凭 duration 计算函数就声称它实现了任意时刻无跳变、保速度的反向动画。[关闭路径](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/folderTransition/useFolderTransitionController.ts#L207-L246)。

### 4. 边框、源预览和沉浸背景要分别记录

已展开文件夹内部开始拖图标时，面板增加 2.5 px、rgba(255,255,255,0.3) 边框和淡内阴影；opacity、border-color、box-shadow 用 120 ms ease-out 变化。拖动结束后恢复。这是已展开面板的拖动反馈，和根主页成组候选边框是两套状态。[面板拖动反馈](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/ShortcutFolderCompactOverlay.tsx#L588-L611)。

本版本 overlay 的面板 surface 明确设为透明、无自身 backdropFilter；整屏模糊与沉浸效果由主页背景层承载。[surface 样式](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/ShortcutFolderCompactOverlay.tsx#L81-L92)。FolderTransitionDocumentEffects 将过渡进度、反向透明度及 1→1.05 的缩放写成 CSS 变量；HomeInteractiveSurface 用这些变量交叉淡入预模糊壁纸、相关 tint/veil，缩放壁纸并淡出 UI shell。[变量驱动](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/folderTransition/FolderTransitionDocumentEffects.tsx#L36-L49)、[背景消费](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/home/HomeInteractiveSurface.tsx#L575-L698)、[UI shell](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/home/HomeInteractiveSurface.tsx#L747-L751)。

预览组件可通过 hidePreviewContents 同时设 opacity=0、visibility=hidden、pointerEvents=none；大文件夹的部分缩略图/打开入口堆叠在 drop target active 时可降到 opacity=0.01。这与“整个文件夹透明”不同，应按内容层与外框层分开移植。[内容层](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/shortcuts/ShortcutFolderPreview.tsx#L564-L583)、[大文件夹打开入口内容](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/shortcuts/ShortcutFolderPreview.tsx#L425-L460)。当前 preview 的 drop-target fade transition 常量为 none，不能概括成所有高亮都渐变。[常量](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/shortcuts/ShortcutFolderPreview.tsx#L29-L42)。

DocumentEffects 另写入 body dataset 的过渡 folderId/phase；本次未据此确认额外样式消费者，因此不把“写了 dataset”当作源预览已自动隐藏的证据。

## 从已展开文件夹拖出：保持同一拖拽会话

### 1. 边界反馈与接力触发分开

文件夹内部共用根网格拖拽机制，通过 maskBoundaryRef 传入面板边界；内部 profile 为 folder-internal、allowLargeFolder=false。RootShortcutDropIntent 的 reorder-root 被包装为 reorder-folder-shortcuts。拖动进入面板外区域时，四块屏幕外围 mask 作为拖出范围反馈，hovered 从黑色 5% 提到 10%；它们 pointer-events:none，不接管事件。[组内配置](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/features/shortcuts/components/FolderShortcutSurface.tsx#L350-L390)、[外围 mask](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/features/shortcuts/components/FolderShortcutSurface.tsx#L29-L101)。

extractHandoff 用拖动图标视觉识别点判断是否越界，越界先清除组内成组/排序候选，再安排交接；回到内部会清交接 timer 和越界反馈。根网格常量将交接等待设为 500 ms，这与合组确认或已有组展开的时长不是同一个参数。[越界、返回、计时](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootRuntime/extractHandoff.ts#L20-L146)、[等待常量](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootShortcutGridContracts.ts#L30-L34)。

### 2. 传的是拖动锚点，跨容器后不重新吸到中心

交接 payload 包含 shortcutId、源 folderId、pointerId、pointerType、当前 pointer 和归一化 anchor。根网格按新图标尺寸用 anchor 还原 previewOffset，保留原手指相对图标的位置；新的外部 session 设置 ignoreNextPointerCancel，吸收交接瞬间的一次取消。[seed 生成](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootRuntime/dragState.ts#L35-L59)、[恢复 previewOffset](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootRuntime/sessionStart.ts#L52-L78)。

产品处理 extract start 时使用 flushSync 让待显示根列表、源 child 隐藏标记、外部拖拽 session 一起更新；文件夹 overlay 在此特殊路径 clearImmediately，直接关闭，不等待完整收起动画。这样 root 能立即接力同一 pointer。[产品交接](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/App.tsx#L1015-L1023)、[待提取预览](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/features/shortcuts/workspace/useShortcutWorkspaceController.ts#L80-L117)。

### 3. 预览与持久化边界，以及取消语义

提取先生成 pending previewShortcuts；rootDisplayShortcuts 临时使用这份预览，原域数据不必立刻写入。根网格 release 有实际目标时优先走它；window pointerup 的收尾让出一个 0 ms task，使 root 的正式 drop 先完成，然后才兜底提交仍未处理的提取预览。pointercancel 的 workspace 收尾清预览与外部 session，不主动提交这份初始提取预览。[preview 路由](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/features/shortcuts/workspace/useShortcutWorkspaceController.ts#L62-L117)、[收尾和提交先后](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/features/shortcuts/workspace/useShortcutWorkspaceController.ts#L183-L247)。

但这不是“所有取消均不提交”的通用保证：通用 root pointer finish 对非交接忽略的一次 pointercancel 保留已确认意图，并仍然调用 onRelease。移植时应分别定义普通拖动取消、交接导致的取消与提取预览撤销，不能把该版本的任一分支直接概括成全部回滚。[通用取消路径](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootRuntime/pointerSession.ts#L113-L120)、[finish 仍调用 release](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootRuntime/pointerSession.ts#L235-L253)。

## 文件夹动效的 Aira 映射建议

以下为工程建议：

- 用稳定 folderId/childId 维护源缩略图、展开目标和拖拽项的一致身份；先取几何快照，再播放，不依赖动画中不断变化的位置重新命中。
- 将“测量中、运动中、可交互”做成明确状态；动画 ghost 层与真正网格在状态边界交接，文字/边框/背景分别使用自己的进度。
- 保留标题空间、预览内容显隐、面板拖动边框、打开期间可点击的图标 hit target 等细节；这些共同构成交互，不应只保留一条平移曲线。
- 拖出交接传递 pointer 与归一化锚点，避免跨容器后图标跳到手指中心；边界反馈、交接等待、关闭文件夹和持久化各有独立时机。
- 原生实现重建状态、几何与属性动画，继续沿 Aira 的 features/core/services/data 所有者组织；不直接搬 DOM 查询、CSS 变量和 React flushSync。

## 根网格：跟手、其他图标位移与成组反馈

### 当前业务外观优先于 preset 默认外观

真实业务 [RootShortcutGrid](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/features/shortcuts/components/RootShortcutGrid.tsx#L452-L550) 注入自定义卡片，并将中心命中映射到 `dropTargetActive`；同时显式把 `renderCenterPreview` 和 `renderDropPreview` 设为返回 null。因此，包内 preset 的 SVG `MergePreviewHighlight` 或默认虚线占位不能直接当成当前 LeafTab 页面实际使用的表现。下面记录实际连接到业务卡片的样式。

### 1. 被拖图标跟手与源槽位

[rootView/renderSurface](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootView/renderSurface.tsx#L331-L368) 使用独立顶层预览层，位置为 pointer 减去按下偏移，跟手阶段没有对位置设置缓动 transition。原网格保留布局占位，并通过 `hiddenSortId`、`hideDragPlaceholder` 隐藏原卡片内容，避免预览层和源位置同时出现两枚完整图标。

[GridDragItemFrame](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/GridDragItemFrame.tsx#L26-L93) 的通用代码还定义了拖动项 scale 0.98、opacity 0.32，但当前根网格隐藏了该项的 children 和 placeholder，不能把这两个值直接描述为浮动预览图的可见缩放和透明度。当前业务的浮动预览隐藏标题并关闭图标 wrapper 的 hover 特效。[业务预览](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/features/shortcuts/components/leaftabShortcutVisualAdapter.tsx#L190-L220)

### 2. 其他图标如何让位

拖动期只计算下一排序的布局投影，得到各实体从快照位置到目标位置的 x/y 差量，组合到 transform 上。当前不是拖一格就立即重建正式数据列表；规则图标使用对应槽位差，混合尺寸项目则先重新排布再计算几何差。[投影计算](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootResolution/projection.ts#L94-L198)

普通 frame 的位移动画为 `transform 320ms ease-in-out`。进入中心候选的目标另加 `scale(1.02)`，叠加现有投影位置；退出后撤销这一 scale。当前仲裁保留已确认的避让投影，这与前一轮[成组/避让算法](home-shortcut-folder-reorder-algorithms.md)中“交互意图与视觉投影分离”配套，避免候选状态变化让整片图标跳回。[frame 动画](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/GridDragItemFrame.tsx#L4-L5)、[目标缩放与位移组合](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/GridDragItemFrame.tsx#L26-L40)

### 3. 目标边框、光晕和提亮是实际状态反馈

普通链接目标由 [ShortcutVisualRenderer](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/shortcuts/ShortcutVisualRenderer.tsx#L75-L91) 控制：

- 中心候选激活：1 px 的半透明白色细线，加 6 px 的浅灰外圈；对应源码 `0 0 0 1px rgba(255,255,255,0.34), 0 0 0 6px rgba(232,236,240,0.22)`。
- 同时 `brightness(1.04)` 轻微提亮。
- 阴影与亮度在 150 ms ease 内过渡；中心候选退出时移除这些状态值。
- 普通、小文件夹和大文件夹分别沿各自形状绘制接收反馈，不能用同一固定半径方框盖所有项目。

小/大文件夹接收态由 `highlightBorder` 驱动边框色和内外阴影，预览组件当前把接收态 transition 显式设为 none；不能把普通链接的 150 ms 套给文件夹。[文件夹接收态常量与样式](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/shortcuts/ShortcutFolderPreview.tsx#L29-L53)

目标候选可以立刻显示边框，业务提交仍等待意图确认，因此“出现边框”“确认可合组”“松手落数据”是三个阶段。

### 4. 松手落位和数据变化动画各有责任

正常排序或无有效目标回原位时，保留浮动预览并从松手处移动到投影落点，位置 transition 为 `220ms ease-in-out`；结束前继续隐藏原项，避免双影。[落位层](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootView/renderSurface.tsx#L349-L368)、[起止坐标](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootRuntime/dragSettle.ts#L60-L87)

`useDragMotionState` 先建立起始预览，隔两次 requestAnimationFrame 再切换到终点，清理计时为 settleDuration + 80 ms。这个双帧是 Web 绘制时序手段；ArkUI 迁移要保留“先有起始画面再启动落位”的效果，不照搬浏览器 RAF。[实现](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/useDragMotionState.ts#L76-L103)

合组等结构变化会先保存当前实体矩形，再在新布局中算 `previous - current` 差量：先禁用 transition、把实体逆向放回原画面位置，下一帧取消逆向偏移，由 CSS 动画进入新位置。这是 FLIP 思路，可复用其位置连续性规则。[结构变化前捕获](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootRuntime/dropCommit.ts#L103-L115)、[差量与恢复](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/useDragMotionState.ts#L36-L73)、[纯差量计算](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-core/src/drag/dragMotion.ts#L14-L43)

普通排序落地时另有双帧的 projection settle suppression，防止正式布局已经到位、旧投影移除时再做一遍反向/重复动画。仅图标尺寸变化而项目顺序和跨度不变时，layout animation signature 也保持稳定，避免无关布局动画。[抑制重复落位](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootRuntime/dragState.ts#L189-L219)、[已有测试表达的意图](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/features/shortcuts/components/rootShortcutGridMotion.test.ts#L26-L78)

### 5. 滚动和误触也是同一条体验链

靠近可滚动容器上/下边缘时，LeafTab 用 88 px 边缘带和二次曲线计算自动滚动量，源码最大值为每次 RAF 26 px；每次滚动同时更新坐标和 hover 判定。因此不能只移动画面、继续拿旧坐标合组。该速度是 Web 每帧实现参数，迁移时应按时间换算。[常量](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootShortcutGridContracts.ts#L24-L25)、[速度与滚动循环](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootRuntime/autoScroll.ts#L53-L120)

拖动期间屏蔽点击，结束后延后 120 ms 放开，防止松手紧接着打开链接。[拖动生命周期](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootRuntime/dragState.ts#L160-L186)

## 大文件夹：占位、插入和预览分别定义

### 1. 2×2 占位与可见尺寸不是同一个数

大文件夹占根网格 2×2 格，标题作为视觉附属，不计入文件夹 body 的测量高度。可见外框尺寸取“一个普通图标尺寸 + 一个列宽 + 一个列间距”，对齐相邻普通图标的可见外边，而非简单填满两个格子的总宽。[尺寸计算](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-preset-leaftab/src/layout.ts#L167-L201)、[跨度与 body 测量](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-preset-leaftab/src/layout.ts#L224-L247)

因此既要维护占位矩形，也要维护图标可见矩形；合组判定、浮动预览和落位不能随意混用两者。

### 2. 拖普通图标与拖大文件夹采用不同排序策略

当前根网格在拖 1×1 图标、同时存在跨格项目时，冻结跨格项目的列表槽位，只在可移动的小项序列中插入。底层对应 `reorderRootShortcutPreservingLargeFolderPositions`。大文件夹自己被拖动时不走这套冻结策略。[当前分支](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootShortcutGridHelpers.ts#L414-L459)、[小项排序数据操作](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-core/src/model/operations.ts#L512-L551)

拖跨格项目时，根网格会枚举插入索引，分别做占位排布，按大文件夹的实际落点生成候选并去掉重复物理位置。其他图标的移动由候选布局差量得到，不能直接套“一项占一格”的 from/to 平移。[候选生成](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/rootShortcutGridHelpers.ts#L247-L412)、[实际布局打包](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-react/src/serpentineWorldGrid.ts#L70-L132)

底层另有 `applyBigFolderBlockInsert`，可指定 2×2 footprint、收集冲突项目、固定大文件夹后重新布局。但在已读根网格的当前调用链中没有看到生成 `placement.kind = big-folder-block-insert` 的入口。因此它是可继续研究的模型能力，不能宣称当前页面已允许任意物理四格落点。[模型实现](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-core/src/model/operations.ts#L321-L407)、[接收该意图的分支](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-core/src/domain/dropIntents.ts#L80-L91)

### 3. 大文件夹缩略图本身有交互

小文件夹展示前四个孩子。大文件夹采用 3×3 九宫格，前部孩子可直接打开；孩子达到九个时，最后一格承担打开整个文件夹的入口，显示叠层提示。进入接收态时，该入口的图标和叠层有单独的淡出处理；这与整个文件夹的边框高亮是不同状态。[小预览](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/shortcuts/ShortcutFolderPreview.tsx#L505-L559)、[大预览与入口分支](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/shortcuts/ShortcutFolderPreview.tsx#L582-L698)

具体 slot 按 folderId/childId 注册，为展开/收起时从缩略图位置飞入、再飞回提供锚点。内部普通孩子的点击会停止冒泡，避免同时打开链接与文件夹。[直接打开与槽位注册](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/src/components/shortcuts/ShortcutFolderPreview.tsx#L359-L411)

### 4. 组操作也保留位置连续性

新建组可以把目标图标作为 anchor，在目标原序位插入新文件夹；成员保留稳定 ID。拖出后若原文件夹剩余不超过一个孩子，已读模型会解散原文件夹。这是 LeafTab 的具体产品行为，可作为 Aira 对齐基线，不能与此前“默认保留单项组”的早期建议混为一谈。[新建组锚点](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-core/src/model/operations.ts#L409-L448)、[拖出与解散](https://github.com/mason173/LeafTab/blob/0dbe1c4f4355f16ac30608e5099462908019e60f/packages/grid-core/src/model/operations.ts#L554-L593)

## Aira 迁移时的整体基线

以用户已有的 LeafTab 作为完整交互参考，同时记录触发条件、运动对象、目标几何、时长/曲线、预览与真实内容显隐、完成提交和中断处理。应覆盖：

| 体验阶段 | 要保持的行为 |
| --- | --- |
| 拖起与跟手 | 按下锚点连续、原位置与浮动图层不重影、标题和点击处理正确 |
| 外围避让 | 使用稳定投影，其他图标按同一候选布局位移 |
| 进入/离开合组 | 对应目标的边框、光晕、亮度和缩放跟随候选，已有避让布局保持连续 |
| 松手落位 | 浮动预览有明确终点，恢复真实项目时不闪烁、不重复回弹 |
| 新建/加入组 | 使用稳定身份与锚点位置，其他项目的结构变化平滑衔接 |
| 大文件夹混排 | 占位、可见框、标题范围、候选落点与小项冻结策略一致 |
| 文件夹展开/收起 | 源预览、ghost、最终内容分阶段显示；各孩子能对应自己的缩略位置 |
| 组内拖动和拖出 | 保持指针锚点和会话接力，预览和持久提交分开 |
| 中断与失焦 | 单独定义并验证取消语义，清理候选、计时和图层，避免沿用浏览器特殊事件假设 |

以上是体验对齐的范围，不表示 Aira 已实现。颜色、像素、时长可以按原生视觉和性能调优，目标状态与连续性不应在迁移时遗漏。API 26 的 Grid/onMove 只有在能保持这些控制点时才适合作为内部排序所有者；如果让位目标、时序或取消无法接管，应由统一 ArkTS 策略控制投影和合组，再用原生布局/动画呈现。保持原生主页，复用既有 features/core/services/data 边界，不新增 Web 主页或平行收藏存储。

本轮只读源码并补充研究文档，没有运行 LeafTab、没有视觉采集，也没有修改 Aira 功能代码。源码中的 320/220/150 ms、2×2/3×3、边框和淡出参数是当前固定版本的事实；原生手感和性能仍待实际实现验证。
