// duration describes currentSrc, not other source/data-* URLs on the element
// or another stream discovered elsewhere in the page. Reuse existing scans.
export const MEDIA_DURATION_PROBE_RUNTIME: string = `
    function mediaElementDurationMs(element, resourceUrl) {
      if (!element || !element.currentSrc || !resourceUrl) return undefined;
      var duration = element.duration;
      if (typeof duration !== 'number' || !isFinite(duration) || duration <= 0) return undefined;
      try {
        var base = (element.ownerDocument && element.ownerDocument.baseURI) || document.baseURI || location.href;
        var current = new URL(element.currentSrc, base).href;
        var candidate = new URL(resourceUrl, base).href;
        return current === candidate ? Math.round(duration * 1000) : undefined;
      } catch (e) { return undefined; }
    }
`;
