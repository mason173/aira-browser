import { AdBlockResourceType } from '../../common/models/BrowserModels';

/**
 * Shape of the synthetic response a blocked request is answered with.
 *
 * ArkWeb classifies a completed 2xx navigation as a download when the renderer will not display it
 * (`content/browser/loader/download_utils_impl.cc`, `IsDownload`). A 200 — even a real empty HTML
 * document — is such a response for a frame the site never meant to render, such as the hidden POST
 * iframe news.cn submits to `https://a3.xinhuanet.com/s?`. A 204 has no content to save, which is why
 * blocked requests never surfaced as downloads before the 200 stand-ins were introduced.
 */
export interface AdBlockBlockedResourceResponse {
  /** Declared so the response is well formed. Unused by the renderer: the status is 204. */
  mimeType: string;
  /** Always empty. A body would make the response look like a file. */
  textBody: string;
  /** Always empty. A binary body would make the response look like a file. */
  base64Body: string;
  responseCode: number;
  reasonMessage: string;
}

const BLOCKED_NO_CONTENT: AdBlockBlockedResourceResponse = {
  mimeType: 'text/plain',
  textBody: '',
  base64Body: '',
  responseCode: 204,
  reasonMessage: 'No Content'
};

/**
 * Every blocked request is answered with the same empty 204, whatever its resource type.
 *
 * The type used to select a 200 stand-in (HTML for a frame, a GIF for an image) so the renderer could
 * display it. That is exactly the response ArkWeb saves: the xinhuanet POST subframe came back as
 * `text/html` 200 and the download sheet named the file `s`. Resource type does not change the answer.
 * Subframe navigations that can be denied before fetch still are; this is the answer for the ones that
 * cannot.
 */
export function resolveBlockedResourceResponse(
  _resourceType: AdBlockResourceType | undefined
): AdBlockBlockedResourceResponse {
  return BLOCKED_NO_CONTENT;
}
