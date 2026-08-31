(function () {
  "use strict";

  var MOCK_STATE = {
    selectedEngineId: "",
    selectionScope: "persistent",
    engines: [
      { id: "bing", name: "Bing", kind: "built_in", icon: "" },
      { id: "google", name: "Google", kind: "built_in", icon: "" },
      { id: "duckduckgo", name: "DuckDuckGo", kind: "built_in", icon: "" },
      { id: "baidu", name: "百度", kind: "built_in", icon: "" },
      { id: "demo-custom", name: "我的自定义搜索", kind: "custom", icon: "" }
    ]
  };

  var currentState = MOCK_STATE;
  var currentShortcuts = [];
  var eventCount = 0;
  var pendingEngineId = "";
  var toastTimer = 0;

  function getElement(id) {
    return document.getElementById(id);
  }

  function getApi() {
    return window.AiraHome || null;
  }

  function hasSearchEngineApi() {
    var api = getApi();
    return !!api &&
      typeof api.getSearchEngineState === "function" &&
      typeof api.setSearchEngine === "function";
  }

  function hasOpenSearchApi() {
    var api = getApi();
    return !!api && typeof api.openSearch === "function";
  }

  function hasShortcutApi() {
    var api = getApi();
    return !!api &&
      typeof api.getShortcuts === "function" &&
      typeof api.openShortcutPicker === "function" &&
      typeof api.openShortcut === "function" &&
      typeof api.removeShortcut === "function";
  }

  function normalizeState(value) {
    var incoming = value || {};
    var engines = Array.isArray(incoming.engines) ? incoming.engines : [];
    return {
      selectedEngineId: String(incoming.selectedEngineId || ""),
      selectionScope: incoming.selectionScope === "session" ? "session" : "persistent",
      engines: engines.map(function (engine) {
        return {
          id: String(engine && engine.id || ""),
          name: String(engine && engine.name || engine && engine.id || "未命名引擎"),
          kind: engine && engine.kind === "custom" ? "custom" : "built_in",
          icon: String(engine && engine.icon || "")
        };
      }).filter(function (engine) {
        return engine.id.length > 0;
      })
    };
  }

  function resolveEngineIcon(engine) {
    return engine.icon || "";
  }

  function buildFallbackText(engine) {
    var source = String(engine.name || engine.id || "?").trim();
    return source.length > 0 ? source.slice(0, 1).toUpperCase() : "?";
  }

  function appendEngineVisual(container, engine) {
    container.textContent = "";
    var fallback = document.createElement("span");
    fallback.className = "icon-fallback";
    fallback.textContent = buildFallbackText(engine);
    container.appendChild(fallback);

    var icon = resolveEngineIcon(engine);
    if (!icon) {
      return;
    }

    var image = document.createElement("img");
    image.alt = "";
    image.src = icon;
    image.addEventListener("load", function () {
      fallback.hidden = true;
    });
    image.addEventListener("error", function () {
      image.remove();
      fallback.hidden = false;
    });
    container.appendChild(image);
  }

  function findSelectedEngine(state) {
    var selected = state.engines.find(function (engine) {
      return engine.id === state.selectedEngineId;
    });
    return selected || state.engines[0] || {
      id: "",
      name: "没有可用引擎",
      kind: "built_in",
      icon: ""
    };
  }

  function setApiBadge(searchEngineLive, openSearchLive) {
    var live = searchEngineLive && openSearchLive;
    var badge = getElement("apiBadge");
    badge.classList.toggle("is-live", live);
    badge.classList.toggle("is-mock", !live);
    getElement("apiStatus").textContent = live ? "Aira API 已连接" :
      (searchEngineLive ? "原生搜索 API 不可用" : "搜索引擎 API 不可用");
  }

  function setScope(scope) {
    var session = scope === "session";
    getElement("scopeBadge").textContent = session ? "隐私会话选择" : "全局持久选择";
    getElement("scopeValue").textContent = session ? "session" : "persistent";
  }

  function updateEventCounter() {
    getElement("eventCounter").textContent = eventCount + (eventCount === 1 ? " event" : " events");
  }

  function buildEngineCard(engine, state) {
    var button = document.createElement("button");
    var selected = engine.id === state.selectedEngineId;
    var busy = engine.id === pendingEngineId;
    button.type = "button";
    button.className = "engine-card";
    button.classList.toggle("is-selected", selected);
    button.classList.toggle("is-busy", busy);
    button.setAttribute("role", "option");
    button.setAttribute("aria-selected", selected ? "true" : "false");
    button.disabled = pendingEngineId.length > 0 || !hasSearchEngineApi();

    var visual = document.createElement("span");
    visual.className = "engine-icon";
    appendEngineVisual(visual, engine);
    button.appendChild(visual);

    var copy = document.createElement("span");
    copy.className = "engine-copy";

    var name = document.createElement("span");
    name.className = "engine-name";
    name.textContent = engine.name;
    copy.appendChild(name);

    var meta = document.createElement("span");
    meta.className = "engine-meta";
    var kind = document.createElement("span");
    kind.textContent = engine.kind === "custom" ? "用户自定义" : "Aira 内置";
    meta.appendChild(kind);

    copy.appendChild(meta);
    button.appendChild(copy);

    var check = document.createElement("span");
    check.className = "selected-check";
    check.textContent = "✓";
    check.setAttribute("aria-hidden", "true");
    button.appendChild(check);

    button.addEventListener("click", function () {
      selectEngine(engine.id);
    });
    return button;
  }

  function renderState(nextState, source) {
    currentState = normalizeState(nextState);
    var apiReady = hasSearchEngineApi();
    var selected = apiReady ? findSelectedEngine(currentState) : {
      id: "",
      name: "等待新版 Aira",
      kind: "built_in",
      icon: ""
    };
    var grid = getElement("engineGrid");
    grid.textContent = "";
    currentState.engines.forEach(function (engine) {
      grid.appendChild(buildEngineCard(engine, currentState));
    });

    getElement("currentEngineName").textContent = selected.name;
    getElement("currentEngineId").textContent = selected.id || "-";
    appendEngineVisual(getElement("currentEngineIcon"), selected);
    if (apiReady) {
      setScope(currentState.selectionScope);
    } else {
      getElement("scopeBadge").textContent = "需要新版 Aira";
      getElement("scopeValue").textContent = "-";
    }
    getElement("lastUpdateValue").textContent = source;
    updateEventCounter();
  }

  function normalizeShortcuts(value) {
    if (!Array.isArray(value)) {
      return [];
    }
    return value.map(function (item) {
      return {
        id: String(item && item.id || ""),
        kind: item && item.kind === "system" ? "system" : "web",
        title: String(item && item.title || "未命名快捷方式"),
        url: String(item && item.url || ""),
        position: Number(item && item.position || 0),
        iconId: String(item && item.iconId || ""),
        icon: String(item && item.icon || ""),
        iconRendering: String(item && item.iconRendering || ""),
        iconColor: String(item && item.iconColor || "")
      };
    }).filter(function (item) {
      return item.id.length > 0;
    }).sort(function (left, right) {
      return left.position - right.position;
    });
  }

  function appendShortcutVisual(container, shortcut) {
    if (window.AiraHome && typeof window.AiraHome.renderShortcutIcon === "function") {
      window.AiraHome.renderShortcutIcon(container, shortcut);
      return;
    }
    var fallback = document.createElement("span");
    fallback.className = "shortcut-fallback";
    fallback.textContent = String(shortcut.title || "?").trim().slice(0, 1) || "?";
    container.appendChild(fallback);

    if (!shortcut.icon) {
      return;
    }
    var image = document.createElement("img");
    image.alt = "";
    image.src = shortcut.icon;
    image.addEventListener("load", function () {
      fallback.hidden = true;
    });
    image.addEventListener("error", function () {
      image.remove();
      fallback.hidden = false;
    });
    container.appendChild(image);
  }

  function openShortcut(shortcut) {
    var api = getApi();
    if (api && typeof api.openShortcut === "function") {
      api.openShortcut(shortcut.id);
      return;
    }
    showToast("AiraHome.openShortcut 当前不可用，请升级 Aira");
  }

  function removeShortcut(shortcut) {
    var api = getApi();
    if (api && typeof api.removeShortcut === "function") {
      api.removeShortcut(shortcut.id);
      showToast("已请求从主页移除“" + shortcut.title + "”");
      return;
    }
    showToast("AiraHome.removeShortcut 当前不可用，请升级 Aira");
  }

  function buildShortcutItem(shortcut) {
    var item = document.createElement("div");
    item.className = "shortcut-item";

    var openButton = document.createElement("button");
    openButton.type = "button";
    openButton.className = "shortcut-open";
    openButton.setAttribute("aria-label", "打开" + shortcut.title);

    var visual = document.createElement("span");
    visual.className = "shortcut-icon";
    appendShortcutVisual(visual, shortcut);
    openButton.appendChild(visual);

    var title = document.createElement("span");
    title.className = "shortcut-title";
    title.textContent = shortcut.title;
    openButton.appendChild(title);

    var kind = document.createElement("span");
    kind.className = "shortcut-kind";
    kind.textContent = shortcut.kind === "system" ? "系统入口" : "网页";
    openButton.appendChild(kind);
    openButton.addEventListener("click", function () {
      openShortcut(shortcut);
    });
    item.appendChild(openButton);

    var removeButton = document.createElement("button");
    removeButton.type = "button";
    removeButton.className = "shortcut-remove";
    removeButton.textContent = "×";
    removeButton.setAttribute("aria-label", "从主页移除" + shortcut.title);
    removeButton.addEventListener("click", function () {
      removeShortcut(shortcut);
    });
    item.appendChild(removeButton);
    return item;
  }

  function renderShortcuts(value, source) {
    currentShortcuts = normalizeShortcuts(value);
    var grid = getElement("shortcutGrid");
    var status = getElement("shortcutStatus");
    grid.textContent = "";

    if (!hasShortcutApi()) {
      status.textContent = "当前 Aira 版本不支持快捷方式选择器 API";
      getElement("addShortcutButton").disabled = true;
      return;
    }
    getElement("addShortcutButton").disabled = false;
    status.textContent = currentShortcuts.length + " 个快捷方式 · " + source;
    if (currentShortcuts.length === 0) {
      var empty = document.createElement("div");
      empty.className = "shortcut-empty";
      empty.textContent = "暂无快捷方式，点击“添加”调用 Aira 原生选择器";
      grid.appendChild(empty);
      return;
    }
    currentShortcuts.forEach(function (shortcut) {
      grid.appendChild(buildShortcutItem(shortcut));
    });
  }

  function loadShortcuts() {
    if (!hasShortcutApi()) {
      renderShortcuts([], "API unavailable");
      return;
    }
    getApi().getShortcuts().then(function (items) {
      renderShortcuts(items, "getShortcuts resolved");
    }).catch(function (error) {
      showToast(formatError(error));
    });
  }

  function openShortcutPicker() {
    var api = getApi();
    if (api && typeof api.openShortcutPicker === "function") {
      api.openShortcutPicker();
      return;
    }
    showToast("AiraHome.openShortcutPicker 当前不可用，请升级 Aira");
  }

  function showToast(message) {
    var toast = getElement("toast");
    toast.textContent = message;
    toast.classList.add("is-visible");
    if (toastTimer) {
      clearTimeout(toastTimer);
    }
    toastTimer = setTimeout(function () {
      toast.classList.remove("is-visible");
    }, 2400);
  }

  function formatError(error) {
    var code = error && error.code ? String(error.code) : "UNKNOWN";
    var message = error && error.message ? String(error.message) : "操作失败";
    return code + ": " + message;
  }

  function selectEngine(engineId) {
    if (!engineId || pendingEngineId) {
      return;
    }
    if (engineId === currentState.selectedEngineId) {
      showToast("已经在使用这个搜索引擎");
      return;
    }

    if (!hasSearchEngineApi()) {
      showToast("当前版本没有搜索引擎 API，无法切换");
      return;
    }

    pendingEngineId = engineId;
    renderState(currentState, "setSearchEngine pending");
    getApi().setSearchEngine(engineId).then(function (state) {
      pendingEngineId = "";
      renderState(state, "setSearchEngine Promise resolved");
      showToast("Aira 已切换到 " + findSelectedEngine(currentState).name);
    }).catch(function (error) {
      pendingEngineId = "";
      renderState(currentState, "setSearchEngine rejected");
      showToast(formatError(error));
    });
  }

  function refreshState() {
    if (!hasSearchEngineApi()) {
      renderState(currentState, "search engine API unavailable");
      showToast("请安装支持搜索引擎 API 的新版 Aira");
      return;
    }
    getApi().getSearchEngineState().then(function (state) {
      renderState(state, "getSearchEngineState resolved");
      showToast("已读取 Aira 最新状态");
    }).catch(function (error) {
      showToast(formatError(error));
    });
  }

  function openNativeSearch() {
    var api = getApi();
    if (api && typeof api.openSearch === "function") {
      api.openSearch();
      return;
    }
    showToast("AiraHome.openSearch 当前不可用，请升级 Aira");
  }

  function openSearchSettings() {
    var api = getApi();
    if (api && typeof api.openSearchSettings === "function") {
      api.openSearchSettings();
      return;
    }
    showToast("在 Aira 中会打开原生搜索设置");
  }

  function applyThemeVariable(root, name, value) {
    var normalized = String(value || "").trim();
    if (normalized) {
      root.style.setProperty(name, normalized);
    } else {
      root.style.removeProperty(name);
    }
  }

  function applyTheme(theme) {
    var state = theme || {};
    var palette = state.palette || {};
    var colors = palette.colors || {};
    var root = document.documentElement;
    root.dataset.theme = state.effectiveMode === "dark" ? "dark" : "light";
    root.dataset.themePalette = String(palette.id || "");
    applyThemeVariable(root, "--aira-accent", colors.accent);
    applyThemeVariable(root, "--aira-on-accent", colors.onAccent);
    applyThemeVariable(root, "--aira-page-background", colors.pageBackground);
    applyThemeVariable(root, "--aira-surface-background", colors.surfaceBackground);
    applyThemeVariable(root, "--aira-control-background", colors.controlBackground);
    applyThemeVariable(root, "--aira-text-primary", colors.textPrimary);
    applyThemeVariable(root, "--aira-text-secondary", colors.textSecondary);
    applyThemeVariable(root, "--aira-divider", colors.divider);
    applyThemeVariable(root, "--aira-outline", colors.outline);
  }

  function initializeTheme() {
    var previewTheme = new URLSearchParams(window.location.search).get("previewTheme");
    if (previewTheme === "light" || previewTheme === "dark") {
      applyTheme({ effectiveMode: previewTheme });
      return;
    }
    var api = getApi();
    if (api && typeof api.getTheme === "function") {
      api.getTheme().then(applyTheme).catch(function () {
        applyTheme({ effectiveMode: "light" });
      });
      return;
    }
    var dark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
    applyTheme({ effectiveMode: dark ? "dark" : "light" });
  }

  function initialize() {
    initializeTheme();
    setApiBadge(hasSearchEngineApi(), hasOpenSearchApi());
    renderState(MOCK_STATE, hasSearchEngineApi() ? "waiting for Aira state" : "search engine API unavailable");

    getElement("nativeSearchButton").addEventListener("click", openNativeSearch);
    getElement("refreshButton").addEventListener("click", refreshState);
    getElement("settingsButton").addEventListener("click", openSearchSettings);
    getElement("addShortcutButton").addEventListener("click", openShortcutPicker);

    window.addEventListener("aira-home-search-engines-changed", function (event) {
      eventCount += 1;
      renderState(event.detail || {}, "aira-home-search-engines-changed");
    });
    window.addEventListener("aira-home-theme-changed", function (event) {
      applyTheme(event.detail || {});
    });
    window.addEventListener("aira-home-shortcuts-changed", function (event) {
      eventCount += 1;
      updateEventCounter();
      renderShortcuts(event.detail || [], "aira-home-shortcuts-changed");
    });

    if (hasSearchEngineApi()) {
      refreshState();
    }
    loadShortcuts();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initialize);
  } else {
    initialize();
  }
})();
