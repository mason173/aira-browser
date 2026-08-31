// ==UserScript==
// @name         Aira Bilibili 画质选择器
// @namespace    https://aira.cool/userscripts
// @version      1.0.3
// @description  在 B 站播放器旁提供一个轻量画质入口，只读取并触发播放器已经提供的画质选项。
// @match        *://www.bilibili.com/video/*
// @match        *://m.bilibili.com/video/*
// @match        *://bilibili.com/video/*
// @run-at       document-start
// @grant        none
// ==/UserScript==

(() => {
  'use strict';

  const ROOT_ID = 'aira-bilibili-quality-menu';
  const STYLE_ID = 'aira-bilibili-quality-menu-style';
  const QUALITY_BUTTON_SELECTORS = [
    '.bpx-player-ctrl-quality',
    '.bilibili-player-video-quality',
    '.m-video-quality'
  ];
  const QUALITY_ITEM_SELECTORS = [
    '.bpx-player-ctrl-quality-menu-item',
    '.bilibili-player-video-quality-menu-item',
    '.m-video-quality-item'
  ];

  const isMobileBilibiliPage = () => {
    if (location.hostname === 'm.bilibili.com') return true;
    if (location.hostname !== 'www.bilibili.com' && location.hostname !== 'bilibili.com') return false;
    return /Mobile|Android|HarmonyOS|iPhone|iPad|iPod/i.test(navigator.userAgent);
  };

  const installStyle = () => {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = `
      #${ROOT_ID} { position: fixed !important; right: 16px !important; bottom: 112px !important; z-index: 2147483000 !important;
        font: 14px/1.4 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; color: #fff; }
      #${ROOT_ID} button { display: block !important; visibility: visible !important; opacity: 1 !important;
        border: 0; cursor: pointer; color: #fff; background: rgba(20,20,24,.82);
        box-shadow: 0 2px 10px rgba(0,0,0,.28); }
      #${ROOT_ID} > button { width: 42px; height: 32px; border-radius: 16px; }
      #${ROOT_ID} [data-aira-quality-panel] { display: none; min-width: 128px; margin-bottom: 8px;
        padding: 6px; border-radius: 10px; background: rgba(20,20,24,.94); box-shadow: 0 4px 18px rgba(0,0,0,.35); }
      #${ROOT_ID}[data-open="true"] [data-aira-quality-panel] { display: grid; gap: 3px; }
      #${ROOT_ID} [data-aira-quality-panel] button { padding: 7px 10px; border-radius: 7px; text-align: left; }
      #${ROOT_ID} [data-aira-quality-panel] button:hover, #${ROOT_ID} [data-aira-quality-panel] button[data-current="true"] { background: rgba(0,161,214,.85); }
      #${ROOT_ID} [data-aira-empty] { padding: 7px 10px; white-space: nowrap; color: rgba(255,255,255,.74); }
    `;
    (document.head || document.documentElement).appendChild(style);
  };

  const playerRoot = () => {
    const container = document.querySelector('.bpx-player-container, .bilibili-player, .m-video, .video-container');
    if (container) return container;
    const video = document.querySelector('video');
    return video?.closest('.bpx-player-container, .bilibili-player, .m-video, .video-container') || document;
  };

  const isVisible = (element) => {
    if (!(element instanceof HTMLElement)) return false;
    const style = window.getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
  };

  const qualityButton = () => {
    const root = playerRoot() || document;
    for (const selector of QUALITY_BUTTON_SELECTORS) {
      const candidate = root.querySelector(selector);
      if (candidate && isVisible(candidate)) return candidate;
    }
    // Mobile player skins change class names frequently; use only a visible,
    // player-local control whose accessible label explicitly names quality.
    const semantic = root.querySelectorAll('button, [role="button"], [aria-label], [title]');
    return Array.from(semantic).find((element) => {
      const label = `${element.getAttribute('aria-label') || ''} ${element.getAttribute('title') || ''} ${element.textContent || ''}`;
      return isVisible(element) && /画质|清晰度|quality/i.test(label);
    });
  };

  const qualityItems = () => {
    const seen = new Set();
    const items = [];
    const root = playerRoot() || document;
    QUALITY_ITEM_SELECTORS.forEach((selector) => {
      root.querySelectorAll(selector).forEach((item) => {
        const label = (item.textContent || '').replace(/\s+/g, ' ').trim();
        if (label && isVisible(item) && !seen.has(label)) {
          seen.add(label);
          items.push({ label, item });
        }
      });
    });
    if (items.length === 0) {
      root.querySelectorAll('[data-quality], [data-value], [role="menuitem"], li, button').forEach((item) => {
        const label = (item.textContent || '').replace(/\s+/g, ' ').trim();
        if (isVisible(item) && /(?:360|480|720|1080|1440|2160)P|4K|8K|高清|清晰|流畅|自动/i.test(label) && !seen.has(label)) {
          seen.add(label);
          items.push({ label, item });
        }
      });
    }
    return items;
  };

  const createUi = () => {
    if (document.getElementById(ROOT_ID)) return;
    const root = document.createElement('div');
    root.id = ROOT_ID;
    root.innerHTML = '<div data-aira-quality-panel></div><button type="button" aria-label="选择 B 站画质">画质</button>';
    document.documentElement.appendChild(root);
    const panel = root.querySelector('[data-aira-quality-panel]');
    const trigger = root.querySelector(':scope > button');
    const render = () => {
      panel.replaceChildren();
      const items = qualityItems();
      if (items.length === 0) {
        const empty = document.createElement('div');
        empty.dataset.airaEmpty = 'true';
        empty.textContent = qualityButton() ? '请先点播放器原生画质按钮一次' : '未找到播放器原生画质按钮';
        panel.appendChild(empty);
        return;
      }
      items.forEach(({ label, item }) => {
        const option = document.createElement('button');
        option.type = 'button';
        option.textContent = label;
        option.dataset.current = item.classList.contains('current') || item.getAttribute('data-selected') === 'true' ? 'true' : 'false';
        option.addEventListener('click', () => { item.click(); root.dataset.open = 'false'; });
        panel.appendChild(option);
      });
    };
    trigger.addEventListener('click', () => {
      const opening = root.dataset.open !== 'true';
      root.dataset.open = opening ? 'true' : 'false';
      if (opening) {
        const nativeButton = qualityButton();
        if (nativeButton) nativeButton.click();
        window.setTimeout(render, 180);
      }
    });
    document.addEventListener('click', (event) => {
      if (!root.contains(event.target)) root.dataset.open = 'false';
    }, true);
  };

  let scheduled = false;
  const refresh = () => {
    scheduled = false;
    if (!isMobileBilibiliPage()) {
      document.getElementById(ROOT_ID)?.remove();
      return;
    }
    installStyle();
    // Create the control independently of player timing. Bilibili mounts/replaces the
    // player asynchronously and may use a different container on mobile pages.
    createUi();
  };
  const scheduleRefresh = () => {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(refresh);
  };
  new MutationObserver(scheduleRefresh).observe(document.documentElement, { childList: true, subtree: true });
  document.addEventListener('DOMContentLoaded', scheduleRefresh, { once: true });
  window.addEventListener('popstate', scheduleRefresh);
  scheduleRefresh();
})();
