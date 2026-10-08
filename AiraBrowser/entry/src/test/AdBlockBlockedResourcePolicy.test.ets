import { describe, expect, it } from '@ohos/hypium';
import { AdBlockResourceType } from '../main/ets/common/models/BrowserModels';
import { resolveBlockedResourceResponse } from '../main/ets/services/adblock/AdBlockBlockedResourcePolicy';

const BLOCKED_RESOURCE_TYPES: AdBlockResourceType[] = [
  'document',
  'popup',
  'script',
  'image',
  'stylesheet',
  'xmlhttprequest',
  'websocket',
  'ping',
  'subdocument',
  'media',
  'font',
  'object',
  'other'
];

export default function adBlockBlockedResourcePolicyTest(): void {
  describe('Ad-block blocked resource policy', () => {
    // A 200 answer is what ArkWeb saves. news.cn POSTs `https://a3.xinhuanet.com/s?` into a hidden
    // iframe once per ad slot; answering that subframe with empty HTML 200 opened a download sheet
    // named `s` for every slot. The same 200 stand-in was introduced for the cool18 ad iframe. A
    // blocked request has nothing to render, so every type is an empty 204, which has no file to save.
    it('answers every blocked request with an empty 204', 0, () => {
      const answers = BLOCKED_RESOURCE_TYPES.map((resourceType: AdBlockResourceType) =>
        resolveBlockedResourceResponse(resourceType));
      answers.push(resolveBlockedResourceResponse(undefined));
      for (let index = 0; index < answers.length; index++) {
        const answer = answers[index];
        expect(answer.responseCode).assertEqual(204);
        expect(answer.reasonMessage).assertEqual('No Content');
        expect(answer.textBody).assertEqual('');
        expect(answer.base64Body).assertEqual('');
        expect(answer.mimeType).assertEqual('text/plain');
      }
    });

    it('does not answer a blocked subframe with a displayable document', 0, () => {
      const subframe = resolveBlockedResourceResponse('subdocument');
      expect(subframe.responseCode).assertEqual(204);
      expect(subframe.mimeType === 'text/html').assertFalse();
      expect(subframe.textBody.indexOf('<!DOCTYPE html>') >= 0).assertFalse();
    });
  });
}
