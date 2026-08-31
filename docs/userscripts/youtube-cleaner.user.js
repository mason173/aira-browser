// ==UserScript==
// @name         YouTube 净化：移除推荐和 Shorts
// @namespace    https://aira.cool/userscripts
// @version      1.2.0
// @description  移除 YouTube 的“下一个视频”与播放器结束卡片，并从首页、热门和搜索结果中移除 Shorts。
// @match        *://www.youtube.com/*
// @match        *://m.youtube.com/*
// @run-at       document-start
// @grant        none
// ==/UserScript==

(() => {
  'use strict';

  // 如只想保留其中一项功能，将对应的 true 改成 false 后重新保存脚本。
  const REMOVE_RECOMMENDATIONS = true;
  const REMOVE_SHORTS = true;
  const STYLE_ID = 'aira-youtube-cleaner-style';
  const HIDDEN_ATTRIBUTE = 'data-aira-youtube-cleaner-hidden';
  const SHORTS_LINK_SELECTOR = 'a[href^="/shorts/"], a[href*="youtube.com/shorts/"]';
  const SHORTS_CARD_SELECTOR = [
    'yt-shorts-lockup-view-model',
    'ytm-shorts-lockup-view-model',
    'yt-lockup-view-model',
    'ytd-rich-item-renderer',
    'ytd-video-renderer',
    'ytd-grid-video-renderer',
    'ytd-reel-item-renderer',
    'ytd-guide-entry-renderer',
    'ytm-rich-item-renderer',
    'ytm-video-with-context-renderer',
    'ytm-pivot-bar-item-renderer'
  ].join(', ');
  const SHORTS_SHELF_SELECTOR = [
    'ytd-reel-shelf-renderer',
    'ytd-rich-shelf-renderer[is-shorts]',
    'yt-grid-shelf-view-model',
    'ytm-grid-shelf-view-model',
    'yt-shorts-lockup-view-model',
    'ytm-shorts-lockup-view-model',
    'ytm-reel-shelf-renderer'
  ].join(', ');

  const styleText = `
    ${REMOVE_RECOMMENDATIONS ? `
      ytd-compact-autoplay-renderer,
      ytm-autonav-toggle,
      .ytp-endscreen-content,
      .ytp-ce-element,
      .ytp-pause-overlay {
        display: none !important;
      }
    ` : ''}
    ${REMOVE_SHORTS ? `
      ytd-reel-shelf-renderer,
      ytd-rich-shelf-renderer[is-shorts],
      yt-grid-shelf-view-model:has(a[href*="/shorts/"]),
      ytm-grid-shelf-view-model:has(a[href*="/shorts/"]),
      yt-lockup-view-model:has(a[href*="/shorts/"]),
      yt-shorts-lockup-view-model,
      ytm-reel-shelf-renderer,
      ytm-shorts-lockup-view-model,
      [${HIDDEN_ATTRIBUTE}="shorts"] {
        display: none !important;
      }
    ` : ''}
  `;

  const installStyle = () => {
    if (document.getElementById(STYLE_ID)) {
      return;
    }
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = styleText;
    (document.head || document.documentElement).appendChild(style);
  };

  const hide = (element) => {
    if (element && element.getAttribute(HIDDEN_ATTRIBUTE) !== 'shorts') {
      element.setAttribute(HIDDEN_ATTRIBUTE, 'shorts');
      // 规则在 Shadow DOM 内时，页面根节点的 CSS 无法穿透；直接写到命中的
      // Web Component 宿主，PC/移动端以及 Shadow DOM 都会真正隐藏该元素。
      element.style.setProperty('display', 'none', 'important');
    }
  };

  const hideShortsInRoot = (root) => {
    if (!REMOVE_SHORTS) {
      return;
    }

    root.querySelectorAll(SHORTS_SHELF_SELECTOR).forEach((shelf) => {
      if (shelf.matches('ytd-reel-shelf-renderer, ytd-rich-shelf-renderer[is-shorts], ' +
        'yt-shorts-lockup-view-model, ytm-shorts-lockup-view-model, ytm-reel-shelf-renderer') ||
        shelf.querySelector(SHORTS_LINK_SELECTOR)) {
        hide(shelf);
      }
    });

    root.querySelectorAll(SHORTS_LINK_SELECTOR).forEach((link) => {
      const card = link.closest(SHORTS_CARD_SELECTOR);
      hide(card || link);
    });
  };

  const hideRecommendationsInRoot = (root) => {
    if (!REMOVE_RECOMMENDATIONS) {
      return;
    }
    root.querySelectorAll(
      'ytd-compact-autoplay-renderer, ytm-autonav-toggle, .ytp-endscreen-content, ' +
      '.ytp-ce-element, .ytp-pause-overlay'
    ).forEach((element) => {
      element.style.setProperty('display', 'none', 'important');
    });
  };

  const shadowRoots = new Set();
  let scheduled = false;
  const observer = new MutationObserver(() => scheduleRefresh());

  const observeRoot = (root) => {
    if (!root || shadowRoots.has(root)) {
      return;
    }
    shadowRoots.add(root);
    observer.observe(root, { childList: true, subtree: true });
  };

  const discoverShadowRoots = (root) => {
    observeRoot(root);
    root.querySelectorAll('*').forEach((element) => {
      if (element.shadowRoot) {
        discoverShadowRoots(element.shadowRoot);
      }
    });
  };

  const scan = () => {
    discoverShadowRoots(document);
    shadowRoots.forEach((root) => {
      hideRecommendationsInRoot(root);
      hideShortsInRoot(root);
    });
  };

  const refresh = () => {
    scheduled = false;
    installStyle();
    scan();
  };

  const scheduleRefresh = () => {
    if (scheduled) {
      return;
    }
    scheduled = true;
    requestAnimationFrame(refresh);
  };

  // YouTube 用 Shadow DOM 渲染新卡片。提前接管新 ShadowRoot，并扫描已经创建的根，
  // 才能在 PC 和 m.youtube.com 两套组件里命中真正可隐藏的宿主元素。
  const originalAttachShadow = Element.prototype.attachShadow;
  if (originalAttachShadow) {
    Element.prototype.attachShadow = function (options) {
      const root = originalAttachShadow.call(this, options);
      observeRoot(root);
      scheduleRefresh();
      return root;
    };
  }

  observer.observe(document.documentElement, { childList: true, subtree: true });
  document.addEventListener('yt-navigate-finish', scheduleRefresh, true);
  document.addEventListener('DOMContentLoaded', scheduleRefresh, { once: true });
  // 部分 YouTube 组件在连接后才填充 ShadowRoot；轮询作为 MutationObserver 的兜底。
  setInterval(scheduleRefresh, 1000);
  scheduleRefresh();
})();
