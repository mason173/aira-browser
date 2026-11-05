/** Reads the pressed anchor, never the page title or another link with the same URL. */
export class WebLinkTextScriptService {
  buildReadScript(url: string, rawXPx: number, rawYPx: number, webWidthPx: number, targetId: string = ''): string {
    const widthPx = Math.max(1, webWidthPx);
    const xRatio = Math.max(0, rawXPx) / widthPx;
    const yRatio = Math.max(0, rawYPx) / widthPx;
    return `(function () {
      var expectedUrl = ${JSON.stringify(url)};
      function readAt(doc, x, y, depth) {
        if (depth > 8) return '';
        var node = doc.elementFromPoint(x, y);
        while (node && node.shadowRoot && node.shadowRoot.elementFromPoint) {
          var inner = node.shadowRoot.elementFromPoint(x, y);
          if (!inner || inner === node) break;
          node = inner;
        }
        if (!node) return '';
        if (node.tagName === 'IFRAME' || node.tagName === 'FRAME') {
          try {
            var rect = node.getBoundingClientRect();
            return readAt(node.contentDocument, x - rect.left - node.clientLeft,
              y - rect.top - node.clientTop, depth + 1);
          } catch (_) { return ''; }
        }
        while (node) {
          if (node.tagName === 'A' && node.href === expectedUrl) {
            if (${JSON.stringify(targetId)}.length) window.__airaLinkTextTarget = { id: ${JSON.stringify(targetId)}, node: node };
            return String(node.innerText || node.textContent || '').trim();
          }
          node = node.parentElement || (node.getRootNode && node.getRootNode().host);
        }
        return '';
      }
      try {
        var viewport = window.visualViewport;
        var width = viewport ? viewport.width : window.innerWidth;
        return readAt(document, (viewport ? viewport.offsetLeft : 0) + ${xRatio} * width,
          (viewport ? viewport.offsetTop : 0) + ${yRatio} * width, 0);
      } catch (_) { return ''; }
    })()`;
  }

  parseText(result: string): string {
    try {
      const value = JSON.parse(result) as string;
      return typeof value === 'string' ? value.trim() : '';
    } catch (_error) {
      return '';
    }
  }
}
