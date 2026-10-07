import { describe, expect, it } from '@ohos/hypium';
import { resolveBlockedResourceResponse } from '../main/ets/services/adblock/AdBlockBlockedResourcePolicy';

export default function adBlockBlockedResourcePolicyTest(): void {
  describe('Ad-block blocked resource policy', () => {
    // An ad iframe on cool18.com (ad.parkvv.com/html/iframe.php?id=...) is matched by EasyList
    // China's `||ad.parkvv.com^`. Answering that navigation with an empty body under a URL-guessed
    // MIME made Chromium read the response as a download, so the frame must instead receive a real,
    // displayable empty HTML document.
    it('answers a blocked document with a displayable empty HTML document', 0, () => {
      const document = resolveBlockedResourceResponse('document');
      expect(document.mimeType).assertEqual('text/html');
      expect(document.responseCode).assertEqual(200);
      expect(document.textBody.indexOf('<!DOCTYPE html>') >= 0).assertTrue();
      expect(document.textBody.length > 0).assertTrue();
    });

    it('treats a blocked iframe navigation as a document', 0, () => {
      expect(resolveBlockedResourceResponse('subdocument').mimeType).assertEqual('text/html');
      expect(resolveBlockedResourceResponse('subdocument').textBody.length > 0).assertTrue();
      expect(resolveBlockedResourceResponse('popup').mimeType).assertEqual('text/html');
    });

    it('types the neutral stand-in to the request for non-document resources', 0, () => {
      expect(resolveBlockedResourceResponse('script').mimeType).assertEqual('application/javascript');
      expect(resolveBlockedResourceResponse('stylesheet').mimeType).assertEqual('text/css');
      expect(resolveBlockedResourceResponse('image').mimeType).assertEqual('image/gif');
      expect(resolveBlockedResourceResponse('xmlhttprequest').mimeType).assertEqual('application/json');
    });

    it('returns a real image body for a blocked image', 0, () => {
      const image = resolveBlockedResourceResponse('image');
      // A transparent 1x1 GIF decodes to the 6-byte GIF89a magic.
      expect(image.base64Body.length > 0).assertTrue();
    });

    it('never answers a frame with a guessed MIME', 0, () => {
      expect(resolveBlockedResourceResponse('document').mimeType).assertEqual('text/html');
      expect(resolveBlockedResourceResponse('subdocument').mimeType).assertEqual('text/html');
      expect(resolveBlockedResourceResponse('popup').mimeType).assertEqual('text/html');
    });

    it('keeps an empty 204 for the other categorised types', 0, () => {
      const other = resolveBlockedResourceResponse('other');
      expect(other.mimeType).assertEqual('text/plain');
      expect(other.responseCode).assertEqual(204);
      expect(resolveBlockedResourceResponse(undefined).responseCode).assertEqual(204);
    });
  });
}
