# Aira 自定义主页开发指南

> AiraHome API 契约版本：`v1`
>
> 文档最后更新：`2026-08-02`

> 适用对象：希望为 Aira 制作自定义主页的 HTML 作者。自定义主页会替换 Aira 首页内容，但它仍然以“主页”身份运行，不会作为普通网页进入标签页管理、历史记录或普通网页生命周期。

API 契约版本描述 `window.AiraHome` 的兼容边界，不等同于 Aira App 版本。`v1` 可以继续增加向后兼容的可选方法、字段和事件；
主页仍应对 `getThemePalette()` 等较新的能力做特性检测。只有发生不兼容变更时，API 契约版本才会升级到 `v2`。

## 0. 五分钟开始

准备一个主页目录，放入
`aira-homepage.json`、入口 HTML 和至少一张预览图即可。官方起步模板可以从
[aira-minimal-homepage](https://github.com/mason173/aira-minimal-homepage) 下载或克隆；拿到示例包后直接从“修改
manifest”开始。如果从空白项目开始，按下面的包结构和入口 HTML 章节创建文件。

创建自己的主页目录：

```bash
mkdir my-homepage
cd my-homepage
```

按第 2、3 节准备 `aira-homepage.json`、`index.html`、至少一张预览图和可选的 `assets/`，然后为主页设置
长期稳定且唯一的 `id`，并修改 manifest 中的 `name`、`version`、`author` 和 `description`。下面命令以同时提供浅色/深色
预览和 `assets/` 为例；没有使用的可选路径请从命令中删掉。打包时把主页包所需文件直接放在 zip 根目录：

```bash
zip -r my-homepage.zip aira-homepage.json index.html preview-light.jpg preview-dark.jpg assets
```

把生成的 `my-homepage.zip` 导入 Aira 即可。`README.md` 只用于开发说明，不需要放进最终主页包。

## 1. 文件形态

Aira 自定义主页当前只支持 Aira 主页包：`.zip`。主页包适合完整主页项目，可以包含 CSS、JavaScript、图片、壁纸和字体。

Aira 不再支持直接导入单文件 `.html` 或 `.htm` 作为自定义主页。即使只有一个入口页面，也请把入口 HTML、`aira-homepage.json` 和预览图一起打包为 zip。

Aira 会解压整个主页包，并从包内入口 HTML 加载页面。包内相对资源会随主页一起保存。

如果你的主页非常简单，也可以把 CSS 和 JavaScript 写在入口 HTML 中，但仍然需要通过 zip 主页包导入。

## 2. 主页包结构

推荐结构：

```text
my-homepage.zip
  aira-homepage.json
  index.html
  preview-light.jpg
  preview-dark.webp
  assets/
    app.css
    app.js
    icons/
    wallpapers/
      light.jpg
      dark.jpg
```

`aira-homepage.json` 必须放在 zip 根目录：

```json
{
  "schemaVersion": 1,
  "id": "com.example.aira-home",
  "name": "Aira Example Home",
  "version": "1.0.0",
  "entry": "index.html",
  "previewLight": "preview-light.jpg",
  "previewDark": "preview-dark.webp",
  "author": "Aira Developer",
  "description": "A complete custom homepage for Aira."
}
```

字段说明：

- `schemaVersion`: 必填，当前固定为 `1`。
- `id`: 新开发和新发布的主页包必填，最长 128 个字符。它相当于主页包名，是主页跨版本保持不变的唯一身份，推荐使用反向域名格式，例如 `com.example.aira-home`。同一主页的后续版本必须保持 `id` 不变；不同主页不得共用同一个 `id`。
- `name`: 主页包名称，会显示在 Aira 设置列表里。
- `version`: 可选，主页自身的发布版本，最长 32 个字符。使用 SemVer，例如 `1.0.0`、`1.2.0-beta.1`。它与清单格式的 `schemaVersion` 不同：更新同一主页时保持 `id` 不变，并修改 `version`。Aira 当前会在主页信息中展示该版本，但不会据此自动更新、比较新旧版本或阻止降级导入。
- `entry`: 必填，入口 HTML 文件路径，例如 `index.html` 或 `src/index.html`。
- `previewLight`: 浅色模式预览图路径。建议与 `previewDark` 一起提供。
- `previewDark`: 深色模式预览图路径。Aira 在有效深色模式下自动使用这张图。
- `preview`: 可选的单图回退字段。只提供一张预览图时可以继续使用它，Aira 会在浅色和深色模式下显示同一张图。
- `author`: 作者名称。
- `description`: 可选的主页简介，最多 200 个字符。建议用一到两句话说明主页的设计、用途或主要特点。

兼容说明：Aira 当前仍允许导入历史遗留的无 `id` 主页包，但这只是兼容措施。无 `id` 包每次导入都会被视为独立主页，
不具备可靠的原包更新身份；后来发布的带 `id` 版本也不会与旧无 `id` 版本自动合并、绑定或迁移配置。开发者应从下一个
发布版本开始补齐并永久保持自己的 `id`。

`preview`、`previewLight`、`previewDark` 至少需要配置一个。三者都必须指向包内 PNG、JPG/JPEG 或 WebP 图片，浅色与深色预览可以使用不同格式。推荐同时提供 `previewLight` 和 `previewDark`；如果某个主题没有专用图片，Aira 会依次回退到 `preview` 或另一个已提供的主题图片。

包体限制：

- zip 文件建议控制在 20 MB 以内。
- 解压后总体积建议控制在 50 MB 以内。
- 文件数量建议控制在 300 个以内。
- 单个资源文件建议控制在 8 MB 以内，入口 HTML 建议控制在 5 MB 以内。
- 只包含主页运行需要的静态资源。支持 HTML、CSS、JavaScript、JSON、常见图片和字体。
- 不要包含可执行文件、脚本安装包、隐藏文件、`node_modules`、`.git` 或与主页无关的二进制文件。

打包时请把 `aira-homepage.json`、`index.html`、预览图和 `assets` 放在 zip 根目录，不要把外层文件夹本身作为唯一根目录。正确示例：解压 zip 后能直接看到 `aira-homepage.json`。

包内资源可以使用相对路径引用：

```html
<link rel="stylesheet" href="./assets/app.css">
<script src="./assets/app.js"></script>
<img src="./assets/icons/search.png" alt="">
```

壁纸可以直接由你的主页 CSS 控制：

```css
body {
  background-image: url("./assets/wallpapers/light.jpg");
}

:root[data-theme="dark"] body {
  background-image: url("./assets/wallpapers/dark.jpg");
}
```

Aira 不会把包内壁纸写入系统壁纸设置。包内壁纸只作用于你的自定义主页。

## 3. 入口 HTML 模板

如果不需要从零编写，可以直接下载官方起步模板，再删除不需要的界面和事件处理。下面的代码是只保留搜索能力的
最小入口，不要求使用模板中的视觉结构。

- 文件大小建议控制在 5 MB 以内，编码建议使用 UTF-8。
- 页面必须能作为独立网页运行，不应依赖浏览器扩展、Service Worker 或桌面浏览器私有 API。
- 页面不应使用 `iframe`、`object`、`embed`、`file://` 绝对路径、自动刷新跳转或远程脚本。
- 这个 HTML 文件必须放在 zip 主页包内，并由 `aira-homepage.json` 的 `entry` 字段指向；不能作为单独 `.html` 文件导入。

最小模板：

```html
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>我的 Aira 主页</title>
</head>
<body>
  <form id="searchForm">
    <input id="searchInput" placeholder="搜索或输入网址">
    <button type="submit">搜索</button>
  </form>
  <script>
    document.getElementById("searchForm").addEventListener("submit", function (event) {
      event.preventDefault();
      var value = document.getElementById("searchInput").value.trim();
      if (value && window.AiraHome) {
        window.AiraHome.search(value);
      }
    });
  </script>
</body>
</html>
```

## 4. 主页桥接对象

Aira 会在自定义主页中提供 `window.AiraHome`。在普通浏览器中预览页面时，使用前先判断对象是否存在。

`AiraHome` 是自定义主页的公开接口，提供导航、系统入口、搜索引擎选择、快捷方式管理、主题和隐私模式等能力。主页只应依赖本文档列出的 API。

```js
function hasAiraHome() {
  return !!(window.AiraHome);
}
```

调用建议：

- 在 `DOMContentLoaded` 之后初始化，并监听一次 `aira-home-ready`：部分 ArkWeb 页面会在页面脚本开始后才完成 bridge 注入；事件触发时重新进行特性检测、加载主页状态并启用相关控件。在普通浏览器中预览时，先判断 `window.AiraHome` 是否存在。
- 按各方法签名传参：字符串、对象、布尔值和字符串数组分别用于对应参数；不要传 HTML 片段或未编码的用户隐私数据。
- 不要覆盖 `window.AiraHome` 或 Aira 派发的事件名。

```js
function initializeAiraHome() {
  if (!window.AiraHome) return;
  // 在这里做特性检测、加载快捷方式等初始化。
}

initializeAiraHome();
window.addEventListener('aira-home-ready', initializeAiraHome);
```

## 5. API 速查

下面按“最常见的开发任务”列出公开方法。完整 TypeScript 类型定义见文档末尾；每个方法的详细行为以对应专题章节为准。

| 任务 | 方法 | 返回/结果 | 相关事件 |
| --- | --- | --- | --- |
| 展开系统搜索 | `openSearch()` | `void`；展开、聚焦并弹出键盘 | 无 |
| 展开浏览器工具栏 | `openToolbar()` | `void`；展示 Aira 已配置的工具栏快捷操作 | 无 |
| 打开我的书架 | `openNovelBookshelf()` | `void`；打开 Aira 我的书架 | 无 |
| 切换隐私模式 | `togglePrivateMode()` | `void`；按当前模式显示进入或退出隐私模式确认 | 无 |
| 提交搜索或地址 | `search(query, options?)` | `void`；由 Aira 地址逻辑处理 | 无 |
| 打开明确 URL | `openUrl(url)` | `void` | 无 |
| 打开扫一扫 | `scanQr()` | `void` | 无 |
| 打开系统页面 | `openSystemEntry(entry)` 或具体 `open*()` 方法 | `void` | 无 |
| 读取/切换搜索引擎 | `getSearchEngineState()` / `setSearchEngine(id)` | `Promise` | `aira-home-search-engines-changed` |
| 保存主页配置 | `storage.get/set/remove/clear` | `Promise`；写入成功表示已经持久化 | 无 |
| 读取快捷方式 | `getShortcuts()` / `refreshShortcuts()` | `Promise<AiraShortcut[]>` | `aira-home-shortcuts-changed` |
| 渲染快捷方式图标 | `renderShortcutIcon(element, shortcut)` | `boolean`；自动选择字体或图片 | `aira-home-icon-font-ready` |
| 添加快捷方式 | `openShortcutPicker()` | `void`；打开 Aira 快捷方式选择器 | `aira-home-shortcuts-changed` |
| 管理快捷方式 | `openShortcut`、`copyShortcutUrl`、`editShortcut`、`removeShortcut` 等 | `void` 或 `Promise<void>` | `aira-home-shortcuts-changed` |
| 拖动排序 | `reorderShortcuts(ids)` | `Promise<void>`；提交完整 ID 顺序 | `aira-home-shortcuts-changed` |
| 读取设备与窗口环境 | `getEnvironment()` | `Promise<AiraEnvironment>` | `aira-home-environment-changed` |
| 订阅智感握姿 | `motion.on("holdingHandChanged", callback)` | 回调接收 `HoldingHandStatus` 数字枚举 | `motion.off(...)` 取消订阅 |
| 读取主题/主题色/隐私 | `getTheme()` / `getThemePalette()` / `getPrivacyMode()` | `Promise` | 对应 `*-changed` 事件 |
| 处理主页返回 | `setBackHandlerActive(active)` | `void`；注册或撤销一层返回处理 | `aira-home-back-requested` |

传参规则按各方法签名执行：`query`、`id`、`entry` 使用字符串，`options` 使用对象，`active` 使用布尔值，
`reorderShortcuts` 使用字符串 ID 数组。不要把所有参数统一转换成字符串。

所有 Promise 的最终状态都以方法返回值或对应事件为准；主页不应只依赖自己的本地副本。

## 6. 打开系统入口

这些能力用于进入 Aira 系统页面。它们不会把系统入口作为网页打开。

```js
AiraHome.openSettings();              // 设置中心
AiraHome.openBookmarks();             // 书签
AiraHome.openHistory();               // 历史记录
AiraHome.openTabs();                  // 标签后台
AiraHome.openDownloads();             // 下载管理
AiraHome.openSavedPages();            // 已保存页面
AiraHome.openSync();                  // 同步
AiraHome.openAiraPro();               // Aira Pro
AiraHome.openSearchSettings();        // 搜索设置
AiraHome.openAdBlockSettings();       // 网页内容过滤
AiraHome.openSiteSettings();          // 站点设置
AiraHome.openUserScripts();           // 用户脚本
AiraHome.openSystemEntry("appearanceSettings");
AiraHome.scanQr();                    // 扫一扫
```

`openSystemEntry(entry)` 可打开同一套白名单入口。入口名大小写不敏感，短横线、下划线和空格会被忽略。

常用入口名：`bookmarks`、`history`、`tabs`、`downloads`、`savedPages`、`settings`、`sync`、`airaPro`、`searchSettings`、`adBlockSettings`、`siteSettings`、`webpageTranslationSettings`、`passwordSettings`、`userScripts`、`userAgentSettings`、`downloadSettings`、`customHomepageSettings`、`generalSettings`、`appearanceSettings`、`privacySecuritySettings`、`experimentsSettings`、`aboutSettings`、`startupSettings`、`privateTabsSettings`、`historyRetentionSettings`、`themePaletteSettings`、`keyboardShortcutsSettings`、`appProxySettings`。

建议把这些入口放在页面显眼但不干扰搜索的位置。如果用户在 Aira 设置中关闭了系统入口按钮，你的主页仍然可以通过这些 API 提供入口。`openSystemEntry(entry)` 只接受上述白名单入口值。

## 7. 搜索和打开链接

```js
AiraHome.openSearch();
AiraHome.openToolbar();
AiraHome.openNovelBookshelf();
AiraHome.togglePrivateMode();
AiraHome.search("HarmonyOS NEXT ArkWeb");
AiraHome.search("HarmonyOS NEXT ArkWeb", { engineId: "baidu" });
AiraHome.openUrl("https://example.com");
AiraHome.scanQr();
```

- `openSearch()` 会展开 Aira 系统搜索界面，聚焦输入框并弹出键盘。用户提交后按普通地址栏规则处理，包括网址识别和智能搜索回退。
- `openToolbar()` 会展开 Aira 浏览器工具栏，展示用户当前配置和当前主页可用的快捷操作。它应由用户的点击、触摸或键盘操作直接调用；重复调用不会收起已展开的工具栏。
- `openNovelBookshelf()` 会打开 Aira 我的书架，页面不应假设当前主页仍保持焦点。
- `togglePrivateMode()` 会按当前浏览边界请求进入或退出隐私模式，并始终由 Aira 展示确认；主页不能跳过确认、读取隐私标签或访问隐私历史。
- `search(query)` 会交给 Aira 默认地址逻辑处理，可以是关键词，也可以是网址。关键词使用 Aira 默认搜索引擎；只有用户具备 Aira Pro、开启了智能搜索回退且默认引擎不可用时，Aira 才会使用备用引擎。是否显示回退提示继续由“设置 > 搜索 > 回退提示”控制。
- `search(query, { engineId })` 表示本次明确使用指定引擎。Aira 会验证 ID，但不会修改默认引擎、执行可达性探测或自动使用备用引擎。
- `openUrl(url)` 用于打开明确的 URL。
- `scanQr()` 会打开 Aira 扫一扫，识别成功后交给地址栏逻辑处理。
- 这些方法只表达用户意图，页面不应假设调用后当前主页会继续保留焦点或同步得到打开结果。

主页不能传入 `routingMode`、`allowFallback`、备用引擎、回退提示或会员状态。即使页面在 options 中附带这些字段，Aira 也会忽略；智能回退始终由用户的会员状态和搜索设置共同决定。没有调用 `AiraHome.search()` 的普通表单跳转或搜索网址只是网页导航，不会被 Aira 识别为可回退搜索。

`openSearch()` 应由点击、触摸或键盘操作直接调用，不要在主页加载完成后自动弹出键盘。调用前可以通过
`typeof AiraHome.openSearch === "function"` 做特性检测。

`openToolbar()` 同样应由用户操作直接调用。调用前可以通过
`typeof AiraHome.openToolbar === "function"` 做特性检测。

`openNovelBookshelf()` 和 `togglePrivateMode()` 也应由用户操作直接调用。后者会改变浏览边界，主页应在按钮标签中清楚说明该结果；调用前可分别通过 `typeof AiraHome.openNovelBookshelf === "function"` 和 `typeof AiraHome.togglePrivateMode === "function"` 做特性检测。

### 读取和切换 Aira 搜索引擎

自定义主页可以读取 Aira 当前可选择的搜索引擎，并切换当前有效搜索引擎。搜索提交仍应调用
`AiraHome.search(query)`，不要根据搜索模板自行拼接 URL。

```js
async function loadSearchEngines() {
  if (!window.AiraHome || typeof AiraHome.getSearchEngineState !== "function") {
    return { selectedEngineId: "", selectionScope: "persistent", engines: [] };
  }
  return await AiraHome.getSearchEngineState();
}

window.addEventListener("aira-home-search-engines-changed", function (event) {
  renderSearchEngineSelector(event.detail || {});
});
```

调用前可检查这两个方法是否存在；不可用时隐藏搜索引擎切换功能。

状态字段：

- `selectedEngineId`: 当前有效搜索引擎 ID。
- `selectionScope`: `persistent` 表示全局持久选择；`session` 表示仅当前私密会话有效。
- `engines`: 当前可选择的搜索引擎，顺序与 Aira 搜索设置一致，只包含已启用的内置引擎和用户自定义引擎。

搜索引擎字段：

- `id`: 稳定搜索引擎 ID。切换时必须原样传回。
- `name`: Aira 当前展示的引擎名称。用户自定义引擎会返回用户设置的名称。
- `kind`: `built_in` 或 `custom`。
- `icon`: HTML 可以直接用于 `<img src>` 的图标地址。可能是 `data:`、`file://` 或 `https://`；没有可用图标时为空字符串。

渲染时直接判断 `icon` 是否为空；为空时使用 `name` 的首字母或主页自己的占位图标。

切换示例：

```js
async function selectSearchEngine(engineId) {
  if (!window.AiraHome || typeof AiraHome.setSearchEngine !== "function") return;

  try {
    var state = await AiraHome.setSearchEngine(engineId);
    renderSearchEngineSelector(state);
  } catch (error) {
    console.warn("切换搜索引擎失败", error && error.code, error);
  }
}

async function searchWithSelectedEngine(engineId, query) {
  // 本次精确使用所选引擎，不修改默认引擎，也不触发智能回退。
  AiraHome.search(query, { engineId: engineId });
}
```

普通主页中切换会更新 Aira 的全局默认搜索引擎，并按用户同步设置参与个性化同步。私密主页中切换只在
当前会话有效，不修改全局偏好，返回状态的 `selectionScope` 为 `session`。

`setSearchEngine(engineId)` 只负责修改当前有效的默认引擎。之后调用 `AiraHome.search(query)` 仍走 Aira 的默认搜索策略；如果希望某一次搜索严格使用点击的引擎，应把同一个 ID 显式传给 `AiraHome.search(query, { engineId })`。

未知、已删除或当前未启用的 ID 会以 `ENGINE_NOT_AVAILABLE` 失败。主页应以 Promise 返回值或
`aira-home-search-engines-changed` 推送的完整状态为准，不要只在本地永久保存一次点击结果。

#### 使用主页自己的搜索引擎图标

主页可以按稳定 `id` 覆盖自己界面里的展示图标，不需要也不应该修改 Aira 的全局图标：

```js
var homepageEngineIcons = {
  bing: "./assets/search-bing.svg",
  google: "./assets/search-google.svg",
  baidu: "./assets/search-baidu.svg"
};

function resolveSearchEngineIcon(engine) {
  return homepageEngineIcons[engine.id] || engine.icon || "";
}
```

本地主页包可以使用包内 PNG、JPEG、WebP 或 SVG；网址主页也可以使用自己站点的图片资源。对于未知的
用户自定义引擎，建议回退到 Aira 返回的 `icon`，再回退到 `name` 的首字母。

`AiraHome` 不提供 `setSearchEngineIcon`。主页自定义图标只影响该主页自己的视觉呈现，不会修改 Aira
搜索栏、设置页、持久化记录或同步数据。用户要修改全局自定义搜索引擎图标时，应进入 Aira 搜索设置。

### 返回键与瞬态主页界面

主页展开搜索、菜单或其他需要单独退出的瞬态界面时，可以注册一层返回处理：

```js
function setTransientBackActive(active) {
  var api = window.AiraHome;
  if (api && typeof api.setBackHandlerActive === "function") {
    api.setBackHandlerActive(active);
  }
}

setTransientBackActive(true);

window.addEventListener("aira-home-back-requested", function () {
  closeTransientSurface();
  setTransientBackActive(false);
});

document.addEventListener("click", function (event) {
  if (!transientSurfaceOpen || transientSurface.contains(event.target)) return;

  // 必须先拦截，再关闭界面，避免同一次点击穿透到底层按钮。
  event.preventDefault();
  event.stopPropagation();
  closeTransientSurface();
  setTransientBackActive(false);
}, true);
```

API 契约：

- 方法：`setBackHandlerActive(active: boolean): void`。
- 参数为 `true` 时，注册一层待处理的主页返回；参数为 `false` 时，主动撤销当前注册。重复传入同一个值不会叠加多层返回。
- 事件：`aira-home-back-requested`。这是无 `detail` 数据的普通 `CustomEvent`，只表达“请关闭当前瞬态界面”。
- 返回注册是单次消费的。Aira 派发事件前会先消费当前注册；如果页面收到事件后仍决定保持瞬态界面打开，需要再次调用 `setBackHandlerActive(true)`。
- 调用前可使用 `typeof AiraHome.setBackHandlerActive === "function"` 做特性检测。
- 该方法只表示当前主页有一层可退出的瞬态界面。
- 用户按返回时，输入法会优先自行收起；下一次交给 Aira 的返回会派发 `aira-home-back-requested`。
- 页面关闭瞬态界面时应统一调用 `setBackHandlerActive(false)`；事件已经单次消费时，重复撤销也是安全的。再次展开时再重新注册。
- 页面隐藏、重新加载或切换出自定义主页时，Aira 会清除这项瞬态状态。
- Aira 只负责派发返回请求，不会判断 HTML 中哪里是“空白处”。点击外部关闭需要主页根据自己的 DOM 结构实现。
- 外部点击建议在捕获阶段监听 `click`，并在改变界面状态前调用 `preventDefault()` 与 `stopPropagation()`，否则恢复后的底层按钮可能收到同一次点击。

## 8. 读取和添加主页快捷方式

Aira 统一管理主页快捷方式，包括从书签、历史记录添加到主页的项目。自定义主页只负责展示，不需要维护自己的快捷方式数据。

```js
async function loadShortcuts() {
  if (!window.AiraHome) return [];
  return await AiraHome.getShortcuts();
}

window.addEventListener("aira-home-shortcuts-changed", function (event) {
  renderShortcuts(event.detail || []);
});
```

快捷方式字段：

- `id`: 快捷方式 ID。管理快捷方式时必须传这个值。
- `kind`: `web` 表示网页快捷方式，`system` 表示 Aira 系统入口。
- `iconId`: Aira 系统入口的稳定语义图标 ID；网页快捷方式为空字符串。不要根据字体 codepoint 判断功能。
- `title`: 展示名称。
- `url`: 网页快捷方式的目标链接；系统入口为空字符串。
- `position`: 排序位置，数值越小越靠前。
- `icon`: 图标内容。`image` 模式下是 `file://`、`https://` 或 `data:` 地址；`font` 模式下是 Aira 内部字体 glyph。
- `iconRendering`: `font` 表示 Aira 系统字体图标，`image` 表示网页、站点或其他图片图标。
- `iconColor`: 没有图片图标时可用作占位背景色。

系统入口复用 Aira 安装包内唯一的 Operational Icon 字体，不会再生成一套系统入口 SVG。第三方主页不要声明
`@font-face`、写死字体名或保存私有区 codepoint；统一调用 `renderShortcutIcon()`。Aira 会在当前主页文档中注册
稳定的字体别名并处理字体、图片和加载失败占位。字体不会随 Bridge 启动脚本一起注入：第一次渲染 `font` 类型
的系统入口时，Aira 才通过原生 Bridge 读取并缓存字体，在当前文档中注册一次。没有系统入口的主页不会传输这份
字体。主页只需要通过图标容器的 `font-size`、`color`、宽高等 CSS 控制外观。

通常不需要主动加载字体。如果主页必须在首次绘制前完成图标尺寸测量，可以选择 `await AiraHome.prepareIconFont()`；
它与 `renderShortcutIcon()` 共享同一份加载状态和缓存。`renderShortcutIcon()` 的布尔返回值表示已经接受该图标的
渲染方式，字体就绪本身是异步过程；需要监听时可使用 `aira-home-icon-font-ready` 事件。

#### 使用主页自己的系统入口图标

主页可以只在自己的界面中替换系统入口图标。请根据稳定的 `shortcut.iconId` 映射主页包内的 SVG、PNG 或其他
图片资源，不要根据中文标题、字体 glyph 或私有区 codepoint 判断入口。当前系统入口 ID 如下：

| 系统入口 | `iconId` |
|---|---|
| 书签 | `browser.shortcut.bookmarks` |
| 历史记录 | `browser.shortcut.history` |
| 下载管理 | `browser.shortcut.downloads` |
| 已保存页面 | `browser.toolbar.savedPages` |
| 标签页 | `browser.toolbar.tabs` |
| 用户脚本 | `browser.shortcut.scripts` |
| 广告拦截 | `settings.adBlocker` |
| 设置 | `browser.shortcut.settings` |

只配置需要替换的入口；其他入口继续交给 `AiraHome.renderShortcutIcon()`。例如：

```js
var homepageSystemShortcutIcons = {
  "browser.shortcut.bookmarks": "./assets/system-bookmarks.svg",
  "browser.shortcut.settings": "./assets/system-settings.svg"
};

function renderHomepageShortcutIcon(element, shortcut) {
  var customIcon = shortcut.kind === "system"
    ? String(homepageSystemShortcutIcons[shortcut.iconId] || "").trim()
    : "";
  if (customIcon) {
    var image = document.createElement("img");
    image.alt = "";
    image.src = customIcon;
    image.onerror = function () {
      element.textContent = "";
      AiraHome.renderShortcutIcon(element, shortcut);
    };
    element.appendChild(image);
    return;
  }
  AiraHome.renderShortcutIcon(element, shortcut);
}
```

这种替换只影响当前主页的视觉，不会修改 Aira 原生界面、系统入口行为、用户数据或全局 Operational Icon 字体。
自定义图片必须随主页包一起分发，并由主页开发者自行确保授权。官方起步模板已经提供
`homepageSystemShortcutIcons` 配置表。

升级说明：旧版主页如果无条件执行 `img.src = shortcut.icon`，系统入口将无法显示，因为系统入口现在使用
`iconRendering: "font"`。请改为调用 `AiraHome.renderShortcutIcon(container, shortcut)`；网页快捷方式的图片图标
仍由同一个方法按 `image` 模式渲染。新版主页也必须对 `renderShortcutIcon` 做特性检测，以便在尚未提供该方法的
旧版 Aira 中预览或运行；检测不到时退回图片或标题首字占位。

主页可以放置自己的“添加”按钮，并调用 Aira 快捷方式选择器。选择器包含系统入口和书签；添加或移除完成后，Aira 会通过 `aira-home-shortcuts-changed` 推送最新列表。

```js
document.getElementById("add-shortcut").addEventListener("click", function () {
  if (typeof AiraHome.openShortcutPicker === "function") {
    AiraHome.openShortcutPicker();
  }
});
```

`openShortcutPicker()` 应由点击、触摸或键盘操作直接调用，不要在主页加载完成后自动打开。

渲染示例：

```js
function renderShortcuts(items) {
  var root = document.getElementById("shortcuts");
  root.innerHTML = "";
  items.forEach(function (item) {
    var button = document.createElement("button");
    var icon = document.createElement("span");
    icon.className = "shortcut-icon";
    if (typeof AiraHome.renderShortcutIcon === "function") {
      AiraHome.renderShortcutIcon(icon, item);
    } else if (item.iconRendering === "image" && item.icon) {
      var image = document.createElement("img");
      image.alt = "";
      image.src = item.icon;
      icon.appendChild(image);
    } else {
      icon.textContent = String(item.title || item.url || "?").trim().slice(0, 1) || "?";
    }
    var title = document.createElement("span");
    title.textContent = item.title || item.url;
    button.appendChild(icon);
    button.appendChild(title);
    button.addEventListener("click", function () {
      if (AiraHome.openShortcut && item.id) {
        AiraHome.openShortcut(item.id);
      } else if (item.kind !== "system" && item.url) {
        AiraHome.openUrl(item.url);
      }
    });
    root.appendChild(button);
  });
}
```

## 9. 管理主页快捷方式

快捷方式菜单的 UI、触发方式、动作顺序和展示文案都由主页自己决定。Aira 只提供可组合的快捷方式操作 API；你可以做长按菜单、右键菜单、编辑模式、拖拽工具栏，或者只提供其中一两个动作。

Aira 的第三方主页 Web 运行时默认隐藏 ArkWeb 文本选择菜单，并关闭平台默认上下文菜单，避免它们与主页自己的
长按、右键或拖动交互重复出现。主页作者不需要再通过 `user-select`、`contextmenu` 等兼容代码屏蔽系统菜单；如果
主页需要长按管理、复制链接或排序，请自行渲染对应交互并调用下面的 `AiraHome` API。这个限制只作用于第三方主页，
普通网页仍使用 Aira 的网页菜单策略。

系统入口的名称和目标由 Aira 固定，第三方主页可以打开、移动或删除，但不能复制链接或编辑名称。网页快捷方式继续支持完整的打开、复制、编辑、排序和删除操作。即使主页错误地对系统入口调用复制链接或编辑，Aira 也会拒绝执行。

这些 API 都以 `id` 作为入参，`id` 来自 `getShortcuts()` 返回的快捷方式项。`editShortcut(id)` 会打开 Aira 编辑弹窗；`confirmDeleteShortcut(id)` 会打开 Aira 删除确认。移动（包括系统入口）、编辑、删除完成后，Aira 会重新推送最新快捷方式列表。

```js
function openShortcutMenuAction(item, action) {
  if (!window.AiraHome || !item.id) return;

  if (action === "open") {
    AiraHome.openShortcut(item.id);
  } else if (action === "copy") {
    AiraHome.copyShortcutUrl(item.id);
  } else if (action === "edit") {
    AiraHome.editShortcut(item.id);
  } else if (action === "up") {
    AiraHome.moveShortcutUp(item.id);
  } else if (action === "down") {
    AiraHome.moveShortcutDown(item.id);
  } else if (action === "top") {
    AiraHome.moveShortcutToTop(item.id);
  } else if (action === "bottom") {
    AiraHome.moveShortcutToBottom(item.id);
  } else if (action === "delete") {
    AiraHome.confirmDeleteShortcut(item.id);
  }
}
```

上移/下移适合普通排序菜单；置顶/置底适合批量整理或高级菜单。页面可以自行决定是否展示这些动作。

### 拖动排序

主页可以自行实现拖动手势或编辑模式。拖动结束后，调用一次 `reorderShortcuts(ids)` 提交最终顺序，
不要通过连续调用多个上移/下移来模拟拖动：

```js
async function commitShortcutDrag(orderedItems) {
  if (!window.AiraHome || typeof AiraHome.reorderShortcuts !== "function") return;

  // 提交当前主页中所有快捷方式（包括系统入口）的最终顺序。
  var orderedShortcutIds = orderedItems
    .map(function (item) { return item.id; });

  try {
    await AiraHome.reorderShortcuts(orderedShortcutIds);
  } catch (error) {
    console.warn("保存快捷方式排序失败", error && error.code, error);
  }
}
```

`ids` 必须是当前所有快捷方式（包括系统入口）的完整顺序，不能重复、不能遗漏，也不能传入未知 ID。
Aira 会原子校验并保存。Promise 成功只表示请求已被接受（或顺序本来就没有变化），不代表页面可以跳过事件同步；最终顺序仍以
`aira-home-shortcuts-changed` 事件推送的完整列表为准。

失败时可根据 `error.code` 处理：`INVALID_SHORTCUT_ORDER` 表示列表不完整、重复或包含未知 ID；
`SHORTCUT_REORDER_NOT_ALLOWED` 表示当前私密/临时主页不允许保存持久化排序；
`SHORTCUT_REORDER_UNAVAILABLE` 表示当前桥接不可用。

如果你的主页只提供直接删除入口，也可以调用删除 API：

```js
async function removeShortcut(item) {
  if (!window.AiraHome || !item.id) return;
  await AiraHome.removeShortcut(item.id);
}
```

兼容别名：

```js
AiraHome.deleteShortcut(id);
```

调用快捷方式管理方法前，可使用 `typeof AiraHome.editShortcut === "function"` 这类方式检测方法是否可用。

注意：快捷方式管理请求不会同步返回最终结果。页面应监听 `aira-home-shortcuts-changed`，以系统推送的新列表作为最终状态。

不要在主页里自己长期保存 Aira 快捷方式列表。快捷方式排序、编辑、删除和同步由 Aira 管理，主页只负责渲染当前快照。

## 10. 深色模式与跟随系统

Aira 会开放只读主题状态，方便主页适配颜色。主题选择权属于用户和 Aira 设置，第三方主页不应修改系统主题。

```js
AiraHome.getTheme().then(function (theme) {
  // theme.mode: "light" | "dark" | "system"
  // theme.effectiveMode: "light" | "dark"
  // theme.palette: 当前已解析的配色方案及语义颜色
  document.documentElement.dataset.theme = theme.effectiveMode;
});

window.addEventListener("aira-home-theme-changed", function (event) {
  document.documentElement.dataset.theme = event.detail.effectiveMode;
});
```

如果主页只需要读取当前配色方案，可以使用新增的 `getThemePalette()`：

```js
function applyAiraPalette(palette) {
  var root = document.documentElement;
  var state = palette || {};
  var colors = state.colors || {};
  root.dataset.themePalette = state.id || "";
  root.style.setProperty("--aira-accent", colors.accent);
  root.style.setProperty("--aira-on-accent", colors.onAccent);
  root.style.setProperty("--aira-page-background", colors.pageBackground);
  root.style.setProperty("--aira-surface-background", colors.surfaceBackground);
  root.style.setProperty("--aira-control-background", colors.controlBackground);
  root.style.setProperty("--aira-text-primary", colors.textPrimary);
  root.style.setProperty("--aira-text-secondary", colors.textSecondary);
  root.style.setProperty("--aira-divider", colors.divider);
  root.style.setProperty("--aira-outline", colors.outline);
}

if (typeof AiraHome.getThemePalette === "function") {
  AiraHome.getThemePalette().then(applyAiraPalette);
} else if (typeof AiraHome.getTheme === "function") {
  AiraHome.getTheme().then(function (theme) {
    // 兼容尚未提供 getThemePalette() 的旧版 Aira；没有 palette 时保留主页自己的 CSS 默认色。
    if (theme && theme.palette) applyAiraPalette(theme.palette);
  });
}

window.addEventListener("aira-home-theme-changed", function (event) {
  if (event.detail && event.detail.palette) {
    applyAiraPalette(event.detail.palette);
  }
});
```

`palette.id` 是稳定的配色方案 ID，`palette.title` 是面向用户的展示名称。`palette.colors` 已经按当前浅色/深色
模式解析，主页不需要自己去猜某个方案的深色颜色。公开的颜色是面向主页的稳定语义子集：强调色、强调色上的内容色、
页面背景、表面背景、控件背景、主/次文字、分隔线和轮廓。Aira 内部设置图标、同步提供方、热力图等专用 token
不会通过主页 API 暴露。

新版主页必须对 `getThemePalette` 做特性检测。旧版 Aira 的 `getTheme()` 只包含 `mode` 和 `effectiveMode`；此时
主页应继续使用自身的浅色/深色默认变量，不要把缺失的 palette 当成错误或阻止主页初始化。

建议使用 CSS 变量维护浅色和深色两套颜色：

```css
:root {
  --bg: #ffffff;
  --text: #111318;
}

:root[data-theme="dark"] {
  --bg: #111318;
  --text: #f4f7fb;
}

body {
  background: var(--bg);
  color: var(--text);
}
```

## 11. 设备与窗口环境

自定义主页可以读取稳定的设备类别和当前主页实际可用的 viewport。设备类别适合决定交互能力或较大的产品布局差异；
普通响应式排版应优先使用 `viewport.width`、`viewport.height`、CSS media query 和容器尺寸。

```js
function applyEnvironment(environment) {
  var state = environment || {};
  var viewport = state.viewport || {};
  document.documentElement.dataset.formFactor = state.formFactor || "unknown";
  document.documentElement.dataset.shellFamily = state.shellFamily || "phone";
  document.documentElement.dataset.orientation = viewport.orientation || "portrait";
}

if (window.AiraHome && typeof AiraHome.getEnvironment === "function") {
  AiraHome.getEnvironment().then(applyEnvironment);
}

window.addEventListener("aira-home-environment-changed", function (event) {
  applyEnvironment(event.detail);
});
```

返回值示例：

```js
{
  formFactor: "tablet", // "phone" | "tablet" | "two_in_one" | "pc" | "unknown"
  shellFamily: "large_screen", // "phone" | "large_screen"
  viewport: {
    width: 1024,
    height: 768,
    orientation: "landscape" // "portrait" | "landscape" | "square"
  }
}
```

`formFactor` 表示平台报告的宽泛设备类别，在同一个运行设备上通常保持不变。`viewport` 表示当前自定义主页 Web
区域的 CSS 像素尺寸，会随平板横竖屏切换、分屏和电脑窗口缩放而变化。`orientation` 从当前 viewport 推导，
不是物理屏幕方向。因此不要写成“平板一定是横屏”或“电脑一定有固定宽度”，也不要仅凭 `formFactor` 选择断点。

建议把连续排版交给 CSS，把设备类别只用于确实不同的产品能力：

```css
.shortcut-grid {
  grid-template-columns: repeat(auto-fit, minmax(88px, 1fr));
}

@media (min-width: 840px) {
  .page-content {
    max-width: 1120px;
    margin-inline: auto;
  }
}
```

API 契约保持向后兼容。主页必须对 `getEnvironment` 做特性检测；在旧版 Aira 或普通浏览器预览中，直接使用
CSS media query 和 `window.innerWidth` 作为回退即可。

## 12. 隐私模式状态

Aira 会开放只读隐私模式状态，方便主页在普通模式和隐私模式下使用不同皮肤、壁纸或布局。这个状态只表示当前主页所在浏览边界，不会开放隐私标签列表、历史记录或用户身份数据。

```js
AiraHome.getPrivacyMode().then(function (state) {
  // state.privacyMode: "regular" | "private"
  // state.isPrivate: boolean
  document.documentElement.dataset.privacy = state.isPrivate ? "private" : "regular";
});

AiraHome.isPrivateMode().then(function (isPrivate) {
  document.body.classList.toggle("private-home", isPrivate);
});

window.addEventListener("aira-home-privacy-mode-changed", function (event) {
  var state = event.detail || {};
  document.documentElement.dataset.privacy = state.isPrivate ? "private" : "regular";
});
```

建议把隐私模式只用于视觉差异，例如更克制的背景、隐私标识、水印或独立配色。不要在主页里长期保存隐私模式下的搜索词、快捷方式点击或其他使用痕迹。

## 13. 智感握姿

导入的 ZIP 主页包可以通过 `AiraHome.motion` 订阅智感握姿，用于把常用按钮、工具栏或信息区调整到更适合当前握持方式的位置。
这套门面的调用形态、事件名、回调参数和枚举值与 HarmonyOS 原生 `motion` API 保持一致。

```js
var motion = window.AiraHome && window.AiraHome.motion;

if (motion) {
  var HoldingHandStatus = motion.HoldingHandStatus;
  var holdingHandCallback = function (status) {
    if (status === HoldingHandStatus.LEFT_HAND_HELD) {
      document.documentElement.dataset.smartGrip = "left";
    } else if (status === HoldingHandStatus.RIGHT_HAND_HELD) {
      document.documentElement.dataset.smartGrip = "right";
    } else if (status === HoldingHandStatus.BOTH_HANDS_HELD) {
      document.documentElement.dataset.smartGrip = "both";
    } else {
      document.documentElement.dataset.smartGrip = "default";
    }
  };

  motion.on("holdingHandChanged", holdingHandCallback);

  // 页面不再需要监听时，使用同一个回调引用取消订阅。
  function stopHoldingHandListener() {
    motion.off("holdingHandChanged", holdingHandCallback);
  }
}
```

`motion.on()` 只负责注册监听，不保证注册后立即回调当前握姿。Aira 在主页文档已经提交、主页处于可见状态时，
会把后续的握姿变化实时派发给当前文档的回调；左手、右手、双手、未握持和未知状态都可能在使用过程中出现。
因此主页应先使用不依赖握姿的默认布局，再在回调中增量调整布局。取消监听时必须使用同一个回调引用调用 `off()`。

### 与 HarmonyOS 原生 API 的对应关系

| 能力 | HarmonyOS 原生 | Aira 自定义主页 |
| --- | --- | --- |
| 命名空间 | `motion` | `AiraHome.motion` |
| 注册 | `motion.on("holdingHandChanged", callback)` | 相同 |
| 取消单个回调 | `motion.off("holdingHandChanged", callback)` | 相同 |
| 取消全部同类回调 | `motion.off("holdingHandChanged")` | 相同 |
| 回调参数 | `HoldingHandStatus` 数字枚举 | 相同枚举名和数值 |

原生应用需要先导入模块：

```ts
import { motion } from "@kit.MultimodalAwarenessKit";
```

自定义主页不能导入 HarmonyOS Kit，因此改为从 `AiraHome.motion` 取得同形门面，其余订阅代码可以保持接近原生写法。

### HoldingHandStatus

| 枚举 | 数值 | 含义 |
| --- | ---: | --- |
| `HoldingHandStatus.NOT_HELD` | `0` | 未检测到握持 |
| `HoldingHandStatus.LEFT_HAND_HELD` | `1` | 左手握持 |
| `HoldingHandStatus.RIGHT_HAND_HELD` | `2` | 右手握持 |
| `HoldingHandStatus.BOTH_HANDS_HELD` | `3` | 双手握持 |
| `HoldingHandStatus.UNKNOWN_STATUS` | `16` | 状态未知或当前不可用 |

官方握姿 API 没有“上手”“下手”或上下方向状态，只有未握持、左手、右手、双手和未知这五种状态。

### Aira 边界

- 该能力只向通过 Aira 导入并选中的 ZIP 主页包开放。网址主页和普通网页的 `AiraHome.motion` 为 `undefined`。
- 主页只能注册当前文档内的 JavaScript 回调，不能替用户开启实验室开关、申请系统权限、调用 `canIUse`，也不能直接持有 HarmonyOS `motion` 对象。
- Aira 统一持有原生系统订阅。用户关闭“设置 > 高级 > 实验室 > 智感握姿”后，Aira 会停止原生监听；若主页此前收到过有效状态，会收到一次 `UNKNOWN_STATUS` 回退。
- `on()` 不保证注册后立即回调当前状态；华为官方原生声明也没有作出这项保证。主页初始布局必须不依赖握姿，收到回调后再做增强。
- Aira 只在当前主页可见、文档已经提交且运行 generation 有效时调用回调。主页隐藏期间不会收到更新；重新显示后，如果最新状态与主页最后收到的状态不同，会补发最新状态。
- 原生握姿变化会先更新 Aira 当前状态，再向可见主页文档派发变化；主页不需要轮询，也不能读取原生 `motion` 对象或自行创建系统订阅。
- `off("holdingHandChanged", callback)` 只移除指定回调；省略 `callback` 会移除当前文档的全部握姿回调。
- 非法事件名或非函数回调会抛出 `TypeError`。原生权限、设备能力和系统服务错误由 Aira 处理，不会把 HarmonyOS `BusinessError` 直接抛给网页。
- 状态可能因自然换手、双手操作或暂时离手而频繁变化。布局应保持平滑并避免触发不可逆操作。
- Aira 不提供历史状态、时间戳、识别置信度或系统错误码。
- 旧版 Aira 没有此门面。必须先判断 `window.AiraHome && window.AiraHome.motion`，并保留固定布局作为回退。

## 14. 事件与错误处理

### 事件速查

| 事件 | `event.detail` | 用途 |
| --- | --- | --- |
| `aira-home-ready` | `{ apiVersion: "v1" }` | AiraHome bridge 已可用；重新特性检测并加载初始状态 |
| `aira-home-shortcuts-changed` | `AiraShortcut[]` | 快捷方式添加、移动、编辑、删除或同步后的完整列表 |
| `aira-home-search-engines-changed` | `AiraSearchEngineState` | 搜索引擎列表或当前选择变化 |
| `aira-home-theme-changed` | `AiraTheme` | Aira 主题变化 |
| `aira-home-environment-changed` | `AiraEnvironment` | 当前主页 viewport 尺寸或方向变化 |
| `aira-home-privacy-mode-changed` | `AiraPrivacyModeState` | 当前主页边界变化 |
| `aira-home-back-requested` | 无 | Aira 请求主页关闭当前瞬态界面 |

### 常见错误码

- `ENGINE_NOT_AVAILABLE`：搜索引擎 ID 为空、未知、已删除或当前未启用。
- `SEARCH_ENGINE_UPDATE_UNAVAILABLE`：搜索引擎切换桥接不可用。
- `SEARCH_ENGINE_UPDATE_TIMEOUT`：搜索引擎切换在等待 Aira 返回结果时超时。
- `INVALID_SHORTCUT_ORDER`：排序列表不完整、重复或包含未知快捷方式 ID。
- `SHORTCUT_REORDER_NOT_ALLOWED`：当前私密/临时主页不允许保存持久化排序。
- `SHORTCUT_REORDER_UNAVAILABLE`：快捷方式排序桥接不可用。

### 异步语义

`open*()`、`search()`、`openUrl()` 等动作方法只表达用户意图，不返回导航完成结果。读取和变更状态的方法
通常返回 Promise；Promise 成功表示请求已被接受或状态已读取，不代表页面可以跳过事件同步。页面应在初始化时
读取一次状态，并持续监听相关 `*-changed` 事件。智感握姿是例外：它遵循原生 `motion.on/off` 的回调模型，
不提供快照 getter，也不承诺注册后立即回调。

## 15. 完整初始化建议

```js
(function () {
  var holdingHandMotion;
  var holdingHandCallback;

  function init() {
    if (!window.AiraHome) return;

    AiraHome.getShortcuts().then(renderShortcuts).catch(function () {
      renderShortcuts([]);
    });

    AiraHome.getTheme().then(applyTheme).catch(function () {});
    if (typeof AiraHome.getSearchEngineState === "function") {
      AiraHome.getSearchEngineState().then(renderSearchEngineSelector).catch(function () {});
    }
    if (typeof AiraHome.getPrivacyMode === "function") {
      AiraHome.getPrivacyMode().then(applyPrivacyMode).catch(function () {});
    }
    if (typeof AiraHome.getEnvironment === "function") {
      AiraHome.getEnvironment().then(applyEnvironment).catch(function () {});
    }
    if (AiraHome.motion) {
      holdingHandMotion = AiraHome.motion;
      holdingHandCallback = function (status) {
        applyHoldingHandStatus(status, holdingHandMotion.HoldingHandStatus);
      };
      holdingHandMotion.on("holdingHandChanged", holdingHandCallback);
    }
  }

  window.addEventListener("aira-home-shortcuts-changed", function (event) {
    renderShortcuts(event.detail || []);
  });

  window.addEventListener("aira-home-theme-changed", function (event) {
    applyTheme(event.detail || {});
  });

  window.addEventListener("aira-home-search-engines-changed", function (event) {
    renderSearchEngineSelector(event.detail || {});
  });

  window.addEventListener("aira-home-privacy-mode-changed", function (event) {
    applyPrivacyMode(event.detail || {});
  });

  window.addEventListener("aira-home-environment-changed", function (event) {
    applyEnvironment(event.detail || {});
  });

  window.addEventListener("pagehide", function () {
    if (holdingHandMotion && holdingHandCallback) {
      holdingHandMotion.off("holdingHandChanged", holdingHandCallback);
    }
  });

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
  window.addEventListener("aira-home-ready", init);
})();
```

## 16. 能力与安全边界

自定义主页可以通过 `AiraHome` 使用以下能力：

- 主页可以发起搜索、打开链接和打开 Aira 系统页面。
- 主页可以读取当前可选择的搜索引擎及其名称/图标，并请求切换当前有效搜索引擎。
- 主页通过当前明确选择的引擎提交搜索时，不受普通地址栏的智能搜索回退影响。
- 主页可以用自己的资源覆盖主页内的搜索引擎图标，但不能写回或修改 Aira 的全局搜索引擎图标。
- 主页可以请求打开 Aira 扫一扫。
- 主页可以读取并展示 Aira 管理的快捷方式，也可以请求执行快捷方式操作或提交包含系统入口的拖动排序结果。
- 主页可以读取主题状态和当前隐私模式状态，用 CSS 自己适配视觉。
- 导入的 ZIP 主页包可以在用户开启实验室开关时订阅智感握姿变化，但不能控制系统感知能力。
- 主页可以为搜索、菜单等瞬态界面注册一层受限返回事件。
- 主页可以在自己的独立空间中保存少量 JSON 配置；该配置不会与其他主页共享，也不会进入同步。
- 主页不能读取书签、历史、下载、账号、会员、同步配置或任意本地文件。
- 主页不能注册后台任务、拦截网页请求、注入普通网页、安装扩展或调用 Aira 未公开的能力。
- 主页不能直接把网络请求、统计上报或跳转控制藏在导入文件里；需要联网内容时请使用“网址主页”，让用户明确知道主页来自网络。
- 网址主页不能读取智感握姿；Aira 不会把握姿变化派发给可联网的远程主页。

这些边界用于保护用户的账号、数据和浏览器设置。

## 17. 设计和安全建议

- 自定义主页应把自己当作 Aira 首页内容，而不是普通网页导航页。
- 持久保存开关、滑块和布局配置时使用 `AiraHome.storage`。`localStorage` 可用于普通网页缓存，但不应作为主页包更新后仍需保留的配置来源。
- 不要伪装 Aira 系统设置、支付、登录或权限弹窗。
- 对外部图片、脚本和字体保持克制，避免影响首页启动速度。
- 为触控操作保留足够点击区域，建议主要按钮高度不低于 40 CSS 像素。
- 智感握姿只适合优化可达性和布局，不应用于推断身份、建立用户画像或决定权限、支付、登录等重要流程。

## 18. 导入校验

为了保护用户，Aira 会在导入时检查主页包。未通过校验的内容不会写入主页列表。

- 主页包必须是 zip 文件，且必须在根目录包含 `aira-homepage.json`。
- 新开发和新发布的主页包必须在 `aira-homepage.json` 中声明长期稳定的 `id`；Aira 暂时只为历史包兼容缺失 `id` 的情况。
- `aira-homepage.json` 必须声明有效入口 HTML，并通过 `preview`、`previewLight`、`previewDark` 中至少一个字段声明预览图。
- 主页包入口必须包含 `<!doctype html>` 以及完整的 `html/head/body` 结构。
- 所有已声明的预览图都必须存在，且只能使用 PNG、JPEG 或 WebP。
- 入口 HTML 只能是 `.html` 或 `.htm` 文件。
- 包内路径不能包含绝对路径、空路径、`.`、`..`、反斜杠或隐藏文件。
- 包内目录不能包含 `node_modules`、`.git`、`.svn`、`.hg` 或 `__MACOSX`。
- 包内文件只允许使用白名单后缀；可执行文件、系统库、压缩包嵌套和安装包会被拒绝。
- HTML 中如果出现 `iframe`、`object`、`embed`、`base`、内联事件属性、`javascript:` 链接、Service Worker、`file://` 绝对路径、自动刷新跳转、远程脚本、直接网络请求或直接打开新窗口，会被拒绝。
- 主页包内 `.js` 和 `.mjs` 资源同样不能注册 Service Worker、引用 `file://`、改写页面地址、直接打开新窗口或直接发起网络请求。

## 19. 持久配置存储

每个已安装主页都有独立的本地配置空间。配置跟随这一次主页安装保存，不依赖 zip 解压目录、`file://` 地址或 Web Storage origin。

```js
async function loadSettings() {
  return await AiraHome.storage.get("settings", {
    showClock: true,
    iconSize: 48
  });
}

async function saveSettings(settings) {
  await AiraHome.storage.set("settings", settings);
  // Promise 成功后表示原生存储已经完成持久化。
}

async function resetSettings() {
  await AiraHome.storage.remove("settings");
}
```

方法说明：

- `storage.get(key, defaultValue)`: 读取配置。仅当键确实不存在时返回 `defaultValue`；存储不可用时 Promise 会失败。
- `storage.set(key, value)`: 保存可转换为 JSON 的值。写入完成后 Promise 才成功。
- `storage.remove(key)`: 删除一个配置项。
- `storage.clear()`: 清空当前主页的全部配置。调用前应由主页明确征得用户确认。

基础配置空间用于开关、滑块、颜色、布局参数等少量数据，不支持文件、Blob、图片或通用缓存数据库。单个主页最多保存 512 个键，总配置上限为 1 MiB，单个值上限为 256 KiB。超出容量时写入失败，Aira 不会自动删除旧配置。

主页更新时，只要新包使用相同的 manifest `id`，原安装的配置会继续保留。历史无 `id` 包与后来带 `id` 的包是两个
独立主页，不会自动迁移配置；用户可以在确认新版可用后手动删除旧主页。

## 20. 当前限制

- 不支持直接导入单文件 `.html` 或 `.htm`；所有本地自定义主页都需要使用 zip 主页包。
- zip 主页包必须包含 `aira-homepage.json`、稳定 `id`、有效入口 HTML 和至少一张有效预览图；缺失 `id` 仅用于兼容历史主页包。
- 主页 API 只在 Aira 自定义主页环境中保证存在。
- 设备类别是平台提供的宽泛分类，不表示当前窗口尺寸；分屏、自由窗口和横竖屏适配必须以 viewport/CSS 为准。
- 主题 API 只读，不提供修改深色模式、浅色模式或跟随系统的能力。
- 隐私模式 API 只读，只表示当前主页边界是否为隐私模式，不提供读取隐私标签、隐私历史或其他隐私数据的能力。
- 智感握姿 API 只向导入的 ZIP 主页包开放；网址主页、普通网页和旧版单文件主页不接收握姿数据。
- 智感握姿依赖实验室总开关和设备能力，可能长期没有回调或只收到 `UNKNOWN_STATUS`。主页必须提供不依赖该能力的固定布局回退。
- 官方 `aira-minimal-homepage` 示例包含智感握姿状态卡，可用于确认 `AiraHome.motion` 可用、订阅成功以及后续握姿变化回调；示例包版本以其 `aira-homepage.json` 为准。
- 搜索引擎 API 不开放搜索 URL 模板、智能回退配置、会员判断或连通性探测结果。无 `engineId` 的搜索由 Aira 默认策略处理；显式 `engineId` 的搜索精确使用该引擎，不自动切换备用引擎。
- 搜索引擎图标只能在主页自身展示层覆盖，不能通过主页 API 修改 Aira 的全局或持久化图标。

## 21. 完整类型定义

```ts
interface AiraHomeApi {
  storage: AiraHomeStorage;
  motion?: AiraMotionApi;
  openSettings(): void;
  openBookmarks(): void;
  openHistory(): void;
  openTabs(): void;
  openDownloads(): void;
  openSavedPages(): void;
  openOfflinePages(): void;
  openSync(): void;
  openAiraPro(): void;
  openMembership(): void;
  openSearchSettings(): void;
  openAdBlockSettings(): void;
  openSiteSettings(): void;
  openWebpageTranslationSettings(): void;
  openPasswordSettings(): void;
  openUserScripts(): void;
  openUserAgentSettings(): void;
  openDownloadSettings(): void;
  openCustomHomepageSettings(): void;
  openGeneralSettings(): void;
  openAppearanceSettings(): void;
  openPrivacySecuritySettings(): void;
  openExperimentsSettings(): void;
  openAboutSettings(): void;
  openStartupSettings(): void;
  openPrivateTabsSettings(): void;
  openHistoryRetentionSettings(): void;
  openThemePaletteSettings(): void;
  openKeyboardShortcutsSettings(): void;
  openAppProxySettings(): void;
  openSystemEntry(entry: AiraSystemEntry): void;
  openSearch(): void;
  openToolbar(): void;
  openNovelBookshelf(): void;
  togglePrivateMode(): void;
  scanQr(): void;
  search(query: string, options?: AiraSearchOptions): void;
  openUrl(url: string): void;
  getEnvironment(): Promise<AiraEnvironment>;
  getSearchEngineState(): Promise<AiraSearchEngineState>;
  setSearchEngine(engineId: string): Promise<AiraSearchEngineState>;
  setBackHandlerActive(active: boolean): void;
  getShortcuts(): Promise<AiraShortcut[]>;
  refreshShortcuts(): Promise<AiraShortcut[]>;
  prepareIconFont(): Promise<boolean>;
  renderShortcutIcon(element: HTMLElement, shortcut: AiraShortcut): boolean;
  openShortcutPicker(): void;
  openShortcut(id: string): void;
  copyShortcutUrl(id: string): void;
  editShortcut(id: string): void;
  moveShortcutUp(id: string): Promise<void>;
  moveShortcutDown(id: string): Promise<void>;
  moveShortcutToTop(id: string): Promise<void>;
  moveShortcutToBottom(id: string): Promise<void>;
  reorderShortcuts(ids: string[]): Promise<void>;
  confirmDeleteShortcut(id: string): void;
  removeShortcut(id: string): Promise<void>;
  deleteShortcut(id: string): Promise<void>;
  getTheme(): Promise<AiraTheme>;
  getThemePalette(): Promise<AiraThemePalette>;
  refreshTheme(): Promise<AiraTheme>;
  getPrivacyMode(): Promise<AiraPrivacyModeState>;
  isPrivateMode(): Promise<boolean>;
  refreshPrivacyMode(): Promise<AiraPrivacyModeState>;
}

interface AiraHomeStorage {
  get<T>(key: string, defaultValue: T): Promise<T>;
  set(key: string, value: unknown): Promise<void>;
  remove(key: string): Promise<void>;
  clear(): Promise<void>;
}

type AiraSystemEntry =
  "bookmarks" | "history" | "tabs" | "downloads" | "savedPages" | "settings" |
  "sync" | "airaPro" | "searchSettings" | "adBlockSettings" | "siteSettings" |
  "webpageTranslationSettings" | "passwordSettings" | "userScripts" | "userAgentSettings" |
  "downloadSettings" | "customHomepageSettings" |
  "generalSettings" | "appearanceSettings" | "privacySecuritySettings" | "experimentsSettings" |
  "aboutSettings" | "startupSettings" | "privateTabsSettings" |
  "historyRetentionSettings" | "themePaletteSettings" |
  "keyboardShortcutsSettings" | "appProxySettings";

interface AiraShortcut {
  id: string;
  kind: "web" | "system";
  iconId: string;
  title: string;
  url: string;
  position: number;
  icon: string;
  iconRendering: "font" | "image" | "";
  iconColor: string;
}

interface AiraTheme {
  mode: "light" | "dark" | "system";
  effectiveMode: "light" | "dark";
  palette: AiraThemePalette;
}

interface AiraThemePalette {
  id: string;
  title: string;
  colors: AiraThemePaletteColors;
}

interface AiraThemePaletteColors {
  accent: string;
  onAccent: string;
  pageBackground: string;
  surfaceBackground: string;
  controlBackground: string;
  textPrimary: string;
  textSecondary: string;
  divider: string;
  outline: string;
}

interface AiraPrivacyModeState {
  privacyMode: "regular" | "private";
  isPrivate: boolean;
}

interface AiraEnvironment {
  formFactor: "phone" | "tablet" | "two_in_one" | "pc" | "unknown";
  shellFamily: "phone" | "large_screen";
  viewport: AiraViewport;
}

interface AiraViewport {
  width: number;
  height: number;
  orientation: "portrait" | "landscape" | "square";
}

type AiraHoldingHandStatus = 0 | 1 | 2 | 3 | 16;

type AiraHoldingHandCallback = (status: AiraHoldingHandStatus) => void;

interface AiraHoldingHandStatusEnum {
  readonly NOT_HELD: 0;
  readonly LEFT_HAND_HELD: 1;
  readonly RIGHT_HAND_HELD: 2;
  readonly BOTH_HANDS_HELD: 3;
  readonly UNKNOWN_STATUS: 16;
}

interface AiraMotionApi {
  readonly HoldingHandStatus: AiraHoldingHandStatusEnum;
  on(type: "holdingHandChanged", callback: AiraHoldingHandCallback): void;
  off(type: "holdingHandChanged", callback?: AiraHoldingHandCallback): void;
}

interface AiraSearchOptions {
  engineId?: string;
}

interface AiraSearchEngineState {
  selectedEngineId: string;
  selectionScope: "persistent" | "session";
  engines: AiraSearchEngine[];
}

interface AiraSearchEngine {
  id: string;
  name: string;
  kind: "built_in" | "custom";
  icon: string;
}
```
