// Decode a URL's outer wrapper, never the percent escapes inside an already usable
// locator. Decoding an entire script/query corrupts signed paths and values such
// as %26, %2B and %252F. The runtime fragment is shared by all three page probes.
export function normalizeMediaLocatorText(value: string): string {
  const text = value.replace(/\\u002[fF]/g, '/')
    .replace(/\\+\//g, '/')
    .replace(/&amp;/g, '&')
    .replace(/\\u0026/g, '&')
    .replace(/\\u003[dD]/g, '=')
    .replace(/\\u003[fF]/g, '?');
  return text.replace(
    /(?:https?:\/\/|blob:|\/\/|[./A-Za-z0-9_%~-]+\?|https?%(?:25){0,2}3a|%(?:25){0,2}2f%(?:25){0,2}2f)[^"'<>\s]*/ig,
    (locator: string): string => {
      for (let i = 0; i < 3 && /^(?:https?%|%)/i.test(locator); i++) {
        try {
          const decoded = decodeURIComponent(locator);
          if (decoded === locator) break;
          locator = decoded;
        } catch (_error) {
          break;
        }
      }
      return locator;
    }
  );
}

export function mediaLocatorQueryValues(text: string, names: string[] = [
  'file', 'source', 'src', 'video_url', 'video', 'url', 'hls', 'm3u8', 'mpd', 'dash'
]): string[] {
  const pattern = /(?:^|[?&#;,\s])([A-Za-z_$][A-Za-z0-9_$-]{0,63})=([^"'&<>\s]{1,16384})(?=$|["'&<>\s])/ig;
  const values: string[] = [];
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(text)) !== null && values.length < 24) {
    const key = match[1].toLowerCase();
    if (names.some((name: string) => name.toLowerCase() === key)) {
      values.push(normalizeMediaLocatorText(match[2]));
    }
  }
  return values;
}

export const MEDIA_LOCATOR_TEXT_RUNTIME: string = `
function normalizeMediaLocatorText(value) {
  var text = String(value || '').replace(/\\\\u002[fF]/g, '/')
    .replace(/\\\\+\\//g, '/')
    .replace(/&amp;/g, '&')
    .replace(/\\\\u0026/g, '&')
    .replace(/\\\\u003[dD]/g, '=')
    .replace(/\\\\u003[fF]/g, '?');
  return text.replace(
    /(?:https?:\\/\\/|blob:|\\/\\/|[./A-Za-z0-9_%~-]+\\?|https?%(?:25){0,2}3a|%(?:25){0,2}2f%(?:25){0,2}2f)[^"'<>\\s]*/ig,
    function(locator) {
      for (var i = 0; i < 3 && /^(?:https?%|%)/i.test(locator); i++) {
        try {
          var decoded = decodeURIComponent(locator);
          if (decoded === locator) break;
          locator = decoded;
        } catch (e) {
          break;
        }
      }
      return locator;
    }
  );
}
function mediaLocatorQueryValues(text, names) {
  names = names || ['file', 'source', 'src', 'video_url', 'video', 'url', 'hls', 'm3u8', 'mpd', 'dash'];
  var pattern = /(?:^|[?&#;,\\s])([A-Za-z_$][A-Za-z0-9_$-]{0,63})=([^"'&<>\\s]{1,16384})(?=$|["'&<>\\s])/ig;
  var values = [];
  var match;
  while ((match = pattern.exec(String(text || ''))) !== null && values.length < 24) {
    if (names.some(function(name) { return String(name).toLowerCase() === match[1].toLowerCase(); })) {
      values.push(normalizeMediaLocatorText(match[2]));
    }
  }
  return values;
}
`;
