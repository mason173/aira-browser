import { AdBlockResourceType } from '../../common/models/BrowserModels';

/**
 * Shape of the synthetic response a blocked request is answered with.
 *
 * A blocked request must never be answered with an empty body under a guessed MIME: Chromium's
 * navigation loader treats a 2xx response whose MIME the renderer cannot display as a download
 * (`content/browser/loader/download_utils_impl.cc`, `IsDownload`). That is how an ad iframe whose
 * URL has no recognizable extension (for example `ad.parkvv.com/html/iframe.php?id=...`) used to
 * turn into a download prompt once EasyList China matched `||ad.parkvv.com^`.
 */
export interface AdBlockBlockedResourceResponse {
  /** Renderer-facing MIME. Must be a type the renderer can display, never a URL-guessed guess. */
  mimeType: string;
  /** Text body for text-family responses; empty when a binary body or an empty body is used. */
  textBody: string;
  /** Base64 of a binary body (the transparent image); empty when textBody is used. */
  base64Body: string;
  responseCode: number;
  reasonMessage: string;
}

// The same neutral placeholders uBlock Origin and Brave ship as web-accessible resources: each one
// is a minimal, correctly typed stand-in so the renderer finishes the request instead of downloading it.
const BLOCKED_NOOP_HTML: string =
  '<!DOCTYPE html>\n<html>\n    <head><title></title></head>\n    <body></body>\n</html>\n';
const BLOCKED_NOOP_CSS: string = '/* */\n';
const BLOCKED_NOOP_JSON: string = '{}';
// 43-byte transparent 1x1 GIF, identical to uBlock Origin's `1x1.gif`.
const BLOCKED_NOOP_GIF_BASE64: string = 'R0lGODlhAQABAIAAAP///////yH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==';

/**
 * Maps a blocked request's resource type to the neutral resource that replaces it.
 *
 * A document or subdocument (an iframe navigation) is the case that used to surface as a download,
 * so it is answered with a real, empty HTML document under `text/html`. Frames that a site loads as
 * a document are the same class of navigation. Non-navigation sub-resources keep an empty body; the
 * MIME still tracks the request type so the renderer never mistakes them for a file to save.
 */
export function resolveBlockedResourceResponse(
  resourceType: AdBlockResourceType | undefined
): AdBlockBlockedResourceResponse {
  switch (resourceType) {
    case 'document':
    case 'subdocument':
    case 'popup':
      return {
        mimeType: 'text/html',
        textBody: BLOCKED_NOOP_HTML,
        base64Body: '',
        responseCode: 200,
        reasonMessage: 'OK'
      };
    case 'script':
      return {
        mimeType: 'application/javascript',
        textBody: '',
        base64Body: '',
        responseCode: 200,
        reasonMessage: 'OK'
      };
    case 'stylesheet':
      return {
        mimeType: 'text/css',
        textBody: BLOCKED_NOOP_CSS,
        base64Body: '',
        responseCode: 200,
        reasonMessage: 'OK'
      };
    case 'image':
      return {
        mimeType: 'image/gif',
        textBody: '',
        base64Body: BLOCKED_NOOP_GIF_BASE64,
        responseCode: 200,
        reasonMessage: 'OK'
      };
    case 'xmlhttprequest':
      return {
        mimeType: 'application/json',
        textBody: BLOCKED_NOOP_JSON,
        base64Body: '',
        responseCode: 200,
        reasonMessage: 'OK'
      };
    default:
      return {
        mimeType: 'text/plain',
        textBody: '',
        base64Body: '',
        responseCode: 204,
        reasonMessage: 'No Content'
      };
  }
}
