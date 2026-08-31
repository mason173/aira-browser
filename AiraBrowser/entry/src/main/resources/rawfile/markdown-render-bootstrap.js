(function () {
  function safeHref(value) {
    var normalized = String(value || '').trim();
    var lower = normalized.toLowerCase();
    return lower.indexOf('http://') === 0 ||
      lower.indexOf('https://') === 0 ||
      lower.indexOf('mailto:') === 0 ||
      lower.indexOf('tel:') === 0 ||
      lower.indexOf('#') === 0;
  }

  function safeImageSrc(value) {
    var normalized = String(value || '').trim();
    var lower = normalized.toLowerCase();
    if (/^data:image\/(png|jpeg|jpg|webp|gif);base64,/.test(lower)) {
      return true;
    }
    if (/^resource:\/\/rawfile\/[a-z0-9._/-]+\.(png|jpe?g|webp|gif)$/i.test(normalized)) {
      return true;
    }
    return safeHref(normalized);
  }

  function renderMarkdownDocument() {
    var root = document.getElementById('markdown-root');
    var source = document.getElementById('markdown-source');
    var markdownItFactory = typeof globalThis !== 'undefined' &&
      typeof globalThis.markdownit === 'function' ? globalThis.markdownit : window.markdownit;
    if (root === null) {
      return;
    }
    if (source === null || typeof markdownItFactory !== 'function') {
      root.innerHTML = '<p class="error">Markdown 渲染器加载失败。</p>';
      return;
    }
    try {
      var markdown = JSON.parse(source.textContent || '""');
      var markdownIt = markdownItFactory({
        html: false,
        linkify: false,
        typographer: false,
        breaks: false
      });
      markdownIt.validateLink = function (url) {
        return safeHref(url) || safeImageSrc(url);
      };
      var blockedLinks = [];
      var defaultLinkOpen = markdownIt.renderer.rules.link_open;
      var defaultLinkClose = markdownIt.renderer.rules.link_close;
      markdownIt.renderer.rules.link_open = function (tokens, index, options, env, self) {
        var href = tokens[index].attrGet('href') || '';
        var blocked = !safeHref(href);
        blockedLinks.push(blocked);
        if (blocked) {
          return '';
        }
        return defaultLinkOpen ? defaultLinkOpen(tokens, index, options, env, self) :
          self.renderToken(tokens, index, options);
      };
      markdownIt.renderer.rules.link_close = function (tokens, index, options, env, self) {
        if (blockedLinks.pop() === true) {
          return '';
        }
        return defaultLinkClose ? defaultLinkClose(tokens, index, options, env, self) :
          self.renderToken(tokens, index, options);
      };
      root.innerHTML = markdownIt.render(markdown);
      if ((root.textContent || '').trim().length === 0) {
        root.innerHTML = '<p class="empty">这个 Markdown 文件没有内容。</p>';
      }
    } catch (error) {
      root.innerHTML = '<p class="error">Markdown 文档渲染失败。</p>';
    }
  }

  function highlightMarkdownCodeBlocks() {
    if (window.hljs && typeof window.hljs.highlightAll === 'function') {
      window.hljs.highlightAll();
    }
  }

  renderMarkdownDocument();
  highlightMarkdownCodeBlocks();
})();
