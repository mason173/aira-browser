# Aira Minimal Home

> 对应 AiraHome API 契约版本：`v1`
>
> 文档同步日期：`2026-08-04`

这是 Aira 自定义主页的官方起步模板。它可以直接打包导入，也可以作为新主页项目的基础。主页中的“智感握姿 API”状态卡会显示
`AiraHome.motion` 是否可用、是否已订阅，以及最近一次 `holdingHandChanged` 回调收到的状态。

完整 API 说明见 [Aira 自定义主页开发指南](https://github.com/mason173/Aira-browser/blob/main/AiraBrowser/entry/src/main/resources/rawfile/custom_homepage_developer_guide.md)。

## 快速开始

```bash
git clone https://github.com/mason173/aira-minimal-homepage.git my-homepage
cd my-homepage
```

先把 `aira-homepage.json` 中的 `id` 改成你自己的长期稳定 ID，例如 `com.example.aira-home`，再修改
`name`、`version`、`author` 和 `description`，最后调整 `index.html` 与 `assets/`。不要让不同主页共用同一个
`id`；发布同一主页的新版本时保持 `id` 不变，并更新符合 SemVer 的 `version`，例如 `1.0.3`。

完成后打包：

```bash
zip -r ../my-homepage.zip aira-homepage.json index.html preview-light.jpg preview-dark.jpg assets
```

将生成的 `my-homepage.zip` 导入 Aira。

## 包内文件

```text
aira-homepage.json
index.html
preview-light.jpg
preview-dark.jpg
assets/
```

这些文件必须位于 zip 根目录。`README.md` 是模板说明文件，不要打包进去。

## 从哪里开始修改

- 主页稳定 ID、版本、名称、作者、说明和预览图：编辑 `aira-homepage.json`。同一主页后续版本保持 `id` 不变，并更新 `version`。
- 颜色、圆角、间距和深色模式：编辑 `index.html` 顶部的 CSS 变量。
- 搜索引擎展示图标：在 `resolveHomepageEngineIcon()` 的 `homepageIcons` 中按稳定引擎 ID 配置包内图片。
- 快捷方式布局：修改 `.shortcut-grid`、`buildShortcutButton()` 和 `renderShortcuts()`。
- 底部系统入口：修改 `.dock` 中的按钮，并调用对应的 `AiraHome.open*()` 方法。
- 主页内瞬态界面：沿用 `setBackHandlerActive()` 与 `aira-home-back-requested` 的配对处理。

主页自定义的搜索引擎图标只影响当前主页。例如：

```js
var homepageIcons = {
  bing: './assets/search-bing.svg',
  google: './assets/search-google.svg'
};
```

使用这些路径前，请把对应图片放进主页包。

## 模板包含的 API 示例

### 搜索

- `AiraHome.openSearch()`：点击搜索框右侧的 Aira 按钮，展开系统搜索并聚焦输入框。
- `AiraHome.openToolbar()`：点击“展开工具栏”，展示 Aira 当前配置的浏览器快捷操作。
- `AiraHome.search(query)`：提交主页输入框中的搜索词或网址。
- `getSearchEngineState()`、`setSearchEngine(id)`：读取并切换当前有效搜索引擎。
- `aira-home-search-engines-changed`：接收搜索引擎列表或选择变化。
- `AiraHome.scanQr()`：打开扫一扫。

### 快捷方式

- `getShortcuts()` 与 `aira-home-shortcuts-changed`：读取并实时刷新完整快捷方式列表。
- `renderShortcutIcon(element, shortcut)`：统一渲染 Aira 字体系统图标、网页图片图标和失败占位，不需要主页声明字体或解析 codepoint。
- `openShortcutPicker()`：打开 Aira 快捷方式选择器，可添加系统入口或书签。
- `openShortcut()`、`copyShortcutUrl()`、`editShortcut()`、移动和删除方法：组成长按菜单。
- `reorderShortcuts(ids)`：在拖动结束后提交完整 ID 顺序。

系统入口可以打开、移动和删除，但不能复制链接或编辑名称。模板会根据 `kind` 隐藏不适用的菜单项。

新版 Aira 的系统入口使用 `iconRendering: "font"`。模板会优先调用 `renderShortcutIcon()`，同时保留特性检测；
在尚未提供该方法的旧版 Aira 中，会继续使用图片或标题首字占位。主页作者不应把所有 `shortcut.icon` 都传给
`<img>`，也不应写死 Aira 的字体名或私有区 codepoint。

字体由 Aira 在第一次渲染系统入口时按需提供，每个主页文档只注册一次；模板包不需要携带字体文件。一般直接调用
`renderShortcutIcon()` 即可。只有在首次绘制前必须完成图标尺寸测量时，才需要选择性调用
`await AiraHome.prepareIconFont()` 预热。

需要使用主页自己的系统入口图标时，编辑 `index.html` 中的 `homepageSystemShortcutIcons`，按稳定 `iconId` 填写
包内图片路径：

```js
var homepageSystemShortcutIcons = {
  'browser.shortcut.bookmarks': './assets/system-bookmarks.svg',
  'browser.shortcut.settings': './assets/system-settings.svg'
};
```

只需要配置想替换的入口。未配置或图片加载失败的入口会自动回退到 Aira 的字体图标；不要按中文标题、字体 glyph
或私有区 codepoint 建立映射。自定义图片只影响当前主页视觉，不会修改 Aira 原生界面。

模板使用 Pointer Events 同时支持触摸和鼠标排序：点击“排序”，按住快捷方式拖到目标位置，松手后保存，最后点击
“完成排序”退出。提交时调用 `reorderShortcuts(ids)`，并传入所有快捷方式（包括系统入口）的完整 ID 顺序。

### 主题、隐私和返回处理

- `getTheme()`、`getThemePalette()` 与 `aira-home-theme-changed`：同步浅色/深色模式以及用户当前选择的 Aira
  配色方案。模板会把公开语义色写入 `--aira-*` CSS 变量，并使用页面背景、文字、控件、分隔线和强调色；旧版
  Aira 没有 palette 时会自动保留模板自身的浅色/深色默认值。
- `getPrivacyMode()` 与 `aira-home-privacy-mode-changed`：把当前状态写入 `data-privacy` 和 `private-home`，方便通过 CSS 自定义隐私主页。
- `setBackHandlerActive()` 与 `aira-home-back-requested`：关闭主页内展开的瞬态搜索界面。

### 智感握姿

导入并选中这个 ZIP 主页后，主页会调用 `AiraHome.motion.on('holdingHandChanged', callback)`，并在状态卡中显示当前握姿和后续回调的数字状态。
首次订阅不保证立即产生回调；状态卡会区分“已订阅、等待变化”和实际收到的左手、右手、双手、未握持或未知状态。
离开主页文档时会使用同一个回调调用 `off()`。要验证实时回调，请保持主页可见并在左手、右手、双手和松手之间切换。

### 系统入口

底部按钮演示了 `openTabs()`、`openBookmarks()` 和 `openSettings()`。需要更多入口时，可以使用开发指南中列出的
`open*()` 方法或 `openSystemEntry(entry)`。

### 主页配置存储

模板中的“隐藏名称/显示名称”按钮演示了 `AiraHome.storage`：页面启动时读取配置，用户切换后等待原生持久化完成，
失败时回滚页面状态并显示错误。

```js
var defaults = { showShortcutLabels: true };

AiraHome.storage.get('preferences', defaults).then(function (preferences) {
  // 仅当 preferences 不存在时返回 defaults；存储故障会进入 catch。
}).catch(function (error) {
  console.error('读取主页配置失败', error);
});

AiraHome.storage.set('preferences', {
  showShortcutLabels: false
}).then(function () {
  // Promise 成功表示原生存储已经完成持久化。
});

async function resetPreferences() {
  // 删除一个键：
  await AiraHome.storage.remove('preferences');
}

async function clearAllHomepagePreferences() {
  // 清空当前主页的全部配置，调用前应先征得用户确认：
  await AiraHome.storage.clear();
}
```

基础配置存储默认可用，不需要权限声明，只能访问当前已安装主页自己的本地空间，也不会进入 Aira 同步。每个主页最多
512 个键，总配置上限 1 MiB，单个 JSON 值上限 256 KiB；不用于文件、图片、Blob 或通用缓存。

官方模板当前版本为 `1.0.4`，并使用固定 ID `cool.aira.homepage.minimal`。开发规范要求新主页包必须声明自己的长期稳定 ID，它相当于包名；
开发自己的主页时必须换成自己的 ID，并在后续版本中永久保持不变。相同 ID 的后续包会更新原安装并保留配置。

Aira 当前仍兼容历史遗留的无 ID 包，但这只是兼容措施：无 ID 包每次导入都是独立主页，不具备可靠的更新身份，也不会与
后来带 ID 的包合并、绑定或迁移配置。

## 状态同步原则

- 页面初始化时读取一次主题、隐私模式、搜索引擎和快捷方式状态。
- 页面初始化时通过 `AiraHome.storage.get()` 读取主页自己的持久配置。
- 页面持续监听对应的 `*-changed` 事件，并以事件中的完整状态重新渲染。
- 快捷方式移动、编辑、删除或排序后，不长期保存页面自己的副本；最终状态以 Aira 推送为准。
- 模板在调用 API 前会检查方法是否可用。普通浏览器预览时，搜索引擎选择会隐藏，系统搜索、添加和排序按钮会禁用；其他入口会显示预览提示。

## 打包注意

- 主页包不要依赖远程脚本、直接网络请求、Service Worker、浏览器扩展或新窗口跳转。
- 持久配置使用 `AiraHome.storage`，不要依赖 `localStorage` 在主页包更新后继续保留。
- 不要把 `node_modules`、`.git`、隐藏文件、外层目录或其他开发文件打进 zip。
- `aira-homepage.json`、入口 HTML 和预览图必须使用包内相对路径。
- 在普通浏览器中可以预览布局，但 Aira API 只在导入后的自定义主页环境中提供。

## License

[MIT](LICENSE)。可导入主页包中同时包含 `assets/LICENSE.txt`。
