const TOOLBAR_CLEARANCE_ELEMENT_ID: string = 'aira-toolbar-clearance';

/**
 * Extends the root scroll range by a trailing spacer. Geometry stays out of page CSS rules:
 * a locked viewport (overflow hidden and not already scrolling) is left alone, because a spacer
 * there would steal layout instead of adding scroll room. A parent that lays its children out
 * sideways (row flex, grid) is left alone too: the spacer would become a full-width sibling and
 * push the real content off the screen instead of adding scroll room below it. Fixed page bars
 * are not moved.
 */
export class WebToolbarClearanceScriptService {
  static buildApplyScript(clearancePx: number): string {
    const px = Number.isFinite(clearancePx) ? Math.max(0, Math.round(clearancePx)) : 0;
    return `(() => {
      try {
        if (window !== window.top) return;
        var px = ${px};
        var id = ${JSON.stringify(TOOLBAR_CLEARANCE_ELEMENT_ID)};
        var runtime = window.__airaToolbarClearance;
        if (!runtime) {
          runtime = window.__airaToolbarClearance = {
            px: 0,
            observer: null,
            observedBody: null,
            savedScrollPadding: null
          };
          runtime.locked = function() {
            var html = document.documentElement;
            var body = document.body;
            if (!html || !body) return true;
            var htmlStyle = getComputedStyle(html);
            var bodyStyle = getComputedStyle(body);
            var htmlHidden = htmlStyle.overflowY === 'hidden' || htmlStyle.overflowY === 'clip';
            var bodyHidden = bodyStyle.overflowY === 'hidden' || bodyStyle.overflowY === 'clip';
            var scrolls = html.scrollHeight > html.clientHeight + 2 ||
              body.scrollHeight > body.clientHeight + 2;
            return (htmlHidden || bodyHidden) && !scrolls;
          };
          runtime.clear = function() {
            var node = document.getElementById(id);
            if (node && node.parentNode) node.parentNode.removeChild(node);
            if (runtime.savedScrollPadding !== null && document.documentElement) {
              document.documentElement.style.scrollPaddingBottom = runtime.savedScrollPadding;
              runtime.savedScrollPadding = null;
            }
            if (runtime.observer) {
              runtime.observer.disconnect();
              runtime.observer = null;
              runtime.observedBody = null;
            }
          };
          runtime.extendsFlow = function(parent) {
            try {
              if (!parent) return false;
              var style = getComputedStyle(parent);
              var display = style.display;
              if (display === 'flex' || display === 'inline-flex') {
                return style.flexDirection === 'column' || style.flexDirection === 'column-reverse';
              }
              // Row flex and grid put the spacer beside the real content, so a centered page
              // (body flex + justify-center) is pushed off the screen instead of the spacer
              // adding scroll room below it.
              if (display === 'grid' || display === 'inline-grid') return false;
              return true;
            } catch (_) { return false; }
          };
          runtime.insert = function(next) {
            var body = document.body;
            if (!body) return;
            if (!runtime.extendsFlow(body)) { runtime.clear(); return; }
            var node = document.getElementById(id);
            if (!node) {
              node = document.createElement('div');
              node.id = id;
              node.setAttribute('data-aira-toolbar-clearance', '1');
              node.setAttribute('aria-hidden', 'true');
              node.style.cssText = 'display:block;width:100%;margin:0;padding:0;border:0;clear:both;' +
                'flex:0 0 auto;pointer-events:none;';
            }
            node.style.height = next + 'px';
            if (node.parentNode !== body || body.lastElementChild !== node) body.appendChild(node);
            var root = document.documentElement;
            if (root && runtime.savedScrollPadding === null) {
              runtime.savedScrollPadding = root.style.scrollPaddingBottom || '';
            }
            if (root) root.style.scrollPaddingBottom = next + 'px';
          };
          runtime.bind = function() {
            if (!window.MutationObserver || !document.body) return;
            if (runtime.observer && runtime.observedBody === document.body) return;
            if (runtime.observer) runtime.observer.disconnect();
            runtime.observedBody = document.body;
            runtime.observer = new MutationObserver(function() {
              var costStarted = Date.now();
              try {
              if (!(runtime.px > 0) || runtime.locked()) return;
              if (!document.body) return;
              if (runtime.observedBody !== document.body) runtime.bind();
              if (!runtime.extendsFlow(document.body)) { runtime.clear(); return; }
              if (document.getElementById(id) === null) runtime.insert(runtime.px);
              } finally {
                if (window.__airaFreezeCostAdd) window.__airaFreezeCostAdd('toolbarObs', costStarted);
              }
            });
            runtime.observer.observe(document.body, { childList: true });
            if (document.documentElement) {
              runtime.observer.observe(document.documentElement, { childList: true });
            }
          };
          runtime.ensure = function() {
            if (!document.body) {
              document.addEventListener('DOMContentLoaded', function() { runtime.ensure(); }, { once: true });
              return;
            }
            if (!(runtime.px > 0) || runtime.locked() || !runtime.extendsFlow(document.body)) {
              runtime.clear();
              return;
            }
            runtime.insert(runtime.px);
            runtime.bind();
          };
        }
        runtime.px = px;
        runtime.ensure();
      } catch (error) {}
    })()`;
  }
}
