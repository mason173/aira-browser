# Custom Homepage System Chrome Architecture

## 产品语义

每个第三方主页独立拥有以下四项偏好：

- 在此主页显示系统搜索
- 显示系统入口按钮
- 尝试强制深色模式
- 滚动时显示或隐藏

第三方主页 A 和 B 可以保存完全不同的组合。用户切换选中的主页后，设置页与运行时必须立即解析该主页 ID 对应的值；修改 A 不得改变 B。

Aira 原生主页仍使用自己的系统搜索和滚动隐藏偏好，不读取任何第三方主页映射。普通网页也不参与主页偏好。

## 持久化模型

`CustomHomepageRepository` 是主页条目、当前选择和逐主页偏好的持久化 owner。

```text
systemHomepageShowSystemSearchBar: boolean
hideToolbarOnScroll: boolean

showSystemSearchBarByItemId: Record<homepageItemId, boolean>
showSystemEntryButtonByItemId: Record<homepageItemId, boolean>
forceDarkWebContentByItemId: Record<homepageItemId, boolean>
hideToolbarOnScrollByItemId: Record<homepageItemId, boolean>
```

缺少值时使用以下默认值：

| 偏好 | 默认值 |
| --- | --- |
| 系统搜索 | 开启 |
| 系统入口按钮 | 关闭 |
| 强制深色模式 | 开启 |
| 滚动显示/隐藏 | 关闭 |

规则：

- 新添加主页在 repository normalization 中取得默认值。
- 相同稳定主页 ID 的重新导入或替换保留原值。
- 删除主页时，同时清理该 ID 的四项偏好。
- 映射只保留当前仍存在的主页 ID。
- 不保留旧共享第三方主页标量、迁移标记或兼容写回路径。

## Owner 与状态流

```text
CustomHomepageRepository
  owns persisted schema, normalization, deletion cleanup
       |
       v
CustomHomepageSettingsViewModel / CustomHomepageSettingsCoordinator
  resolve and update only the selected third-party homepage
       |
       v
CustomHomepageSettingsPage
  renders shared settings rows and forwards actions

CustomHomepagePresentationViewModel
  resolves selected-item runtime behavior
       |
       +--> BrowserHomeSurfaceProfileViewModel
       |      owns final search / entry / scroll eligibility
       |
       +--> Web appearance policy
              owns selected remote homepage forced-dark behavior
```

`BrowserHomepageBackdropAppearanceCoordinator` 使用当前选中第三方主页的最终搜索、入口、强制深色和滚动隐藏值构造版本键，并按该主页自己的强制深色偏好选择外观快照。

`BrowserShellPage.ets` 只订阅最终 presentation state 并转发事件，不判断或持久化主页偏好。

## 运行时规则

```text
system_home:
  bottomSearchVisible = systemHomepageShowSystemSearchBar
  systemEntryButtonVisible = false
  homeScrollHideAllowed = bottomSearchVisible && hideToolbarOnScroll

third_party_home:
  bottomSearchVisible = showSystemSearchBarByItemId[selectedItemId] ?? true
  systemEntryButtonVisible = showSystemEntryButtonByItemId[selectedItemId] ?? false
  forceDarkWebContent = forceDarkWebContentByItemId[selectedItemId] ?? true
  homeScrollHideAllowed = bottomSearchVisible &&
    (hideToolbarOnScrollByItemId[selectedItemId] ?? false)

web_page:
  homepage preferences do not participate
```

强制深色模式只对 `remote_url` 主页执行 Web 深色策略；导入的本地主页仍保存独立值，但当前运行时不应用远程 Web 强制深色处理。

第三方主页通过 `AiraHome.openSearch()` 发起的临时搜索会话属于交互状态，不修改持久偏好；会话关闭后恢复当前主页自己的配置。

主页底部搜索有两种不同的临时隐藏状态：

- 用户手动下滑面板隐藏时，面板 resting detent 为 `peek`；随后任一方向产生超过约 12px 的明确主页内容滚动时恢复到 `low`。
- “滚动时显示或隐藏”自动触发时，只改变 visual collapse，resting detent 仍为 `low`。

原生主页的 Spring 边界回弹和 1–2px 方向噪声不参与显隐判断。到达底部后，小幅回弹继续被过滤；同一手势明显滚离底部时解除过滤并允许恢复搜索，避免必须等整个滚动停止后才重新响应。

## 设置页交互

- 四项开关只在已选中第三方主页时可编辑。
- 系统搜索、滚动显示/隐藏和系统入口按钮位于 `主页系统入口` 分组。
- 系统搜索关闭时，滚动显示/隐藏行保持原值但暂不可操作。
- 强制深色行仅在当前选择为网址主页时可操作。
- 切换主页卡片后，四项开关同步显示新主页保存的值。
- 选择 Aira 原生主页时，这些第三方主页开关不可编辑；原生主页设置由独立页面负责。

## 验收场景

1. A 与 B 为四项开关设置不同组合，来回切换时各自状态保持不变。
2. 修改 A 后，B 和 Aira 原生主页均不变化。
3. 选中 A 时，运行时搜索、入口、强制深色和滚动隐藏全部使用 A 的值；选中 B 时全部切换为 B 的值。
4. 删除 A 后，不保留 A 的孤立映射。
5. 替换或重新导入同一稳定 ID 的主页时保留四项配置。
6. 新添加主页使用明确默认值：搜索开、入口关、强制深色开、滚动隐藏关。
7. 普通网页态底部工具栏不受第三方主页偏好影响。
8. `AiraHome.openSearch()` 不修改当前主页的持久搜索开关。

## 实现约束

- 不在 `BrowserShellPage.ets` 添加主页偏好判断或持久化逻辑。
- 不把第三方主页偏好转换为全局 bottom-panel hidden 状态。
- 不把滚动产生的临时隐藏结果写回主页偏好。
- 不新增 repository-internal 自动化测试，除非任务明确授权；优先使用聚焦逻辑断言、构建、安装和用户手动验证。
