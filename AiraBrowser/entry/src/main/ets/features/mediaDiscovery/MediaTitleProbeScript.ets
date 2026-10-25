// Reused by the existing bounded DOM scans. No timers, global hooks, response
// reads, full-page text scans or layout measurements are needed for naming.
export const MEDIA_TITLE_PROBE_RUNTIME: string = `
    function boundedMediaTitle(value) {
      var title = typeof value === 'string' ? value.substring(0, 512).replace(/\\s+/g, ' ').trim() : '';
      return /^(?:video|video player|player|play|untitled|loading\\.*|视频|视频播放器|播放器|播放|无标题|加载中\\.*)$/i.test(title) ? '' : title;
    }
    function readMediaElementTitle(element) {
      if (!element || !element.getAttribute) return undefined;
      return boundedMediaTitle(element.getAttribute('title')) ||
        boundedMediaTitle(element.getAttribute('aria-label')) ||
        boundedMediaTitle(element.getAttribute('data-title')) || undefined;
    }
    function readMediaPageTitle() {
      try {
        if (document.querySelector) {
          var og = document.querySelector('meta[property="og:title"]');
          var ogTitle = og && boundedMediaTitle(og.getAttribute('content'));
          if (ogTitle) return ogTitle;
          var twitter = document.querySelector('meta[name="twitter:title"]');
          var twitterTitle = twitter && boundedMediaTitle(twitter.getAttribute('content'));
          if (twitterTitle) return twitterTitle;
        }
        return boundedMediaTitle(document.title) || undefined;
      } catch (e) { return undefined; }
    }
`;
