import { describe, expect, it } from '@ohos/hypium';
import { AdBlockRequestClassifierService } from '../main/ets/services/adblock/AdBlockRequestClassifierService';

// The navigation deny path classifies a request before asking the engine. A subframe EasyList matches
// as `subdocument`, not `document`, so a subframe with no recognisable destination must be asked as
// `subdocument`. Asking it as `document` let news.cn POST `https://a3.xinhuanet.com/s?` through.
class NavigationFrameRequest {
  private readonly mainFrame: boolean;
  private readonly headers: Array<Header>;

  constructor(mainFrame: boolean, headers: Array<Header>) {
    this.mainFrame = mainFrame;
    this.headers = headers;
  }

  isMainFrame(): boolean {
    return this.mainFrame;
  }

  isRedirect(): boolean {
    return false;
  }

  getRequestHeader(): Array<Header> {
    return this.headers;
  }
}

function navigationResourceType(
  classifier: AdBlockRequestClassifierService,
  mainFrame: boolean,
  headers: Array<Header>
): string {
  const classification = classifier.classify({
    url: 'https://a3.xinhuanet.com/s?',
    pageUrl: 'https://www.news.cn/fortune/article/c.html',
    method: 'POST',
    isMainFrame: mainFrame,
    isRedirect: false,
    request: new NavigationFrameRequest(mainFrame, headers) as ESObject as WebResourceRequest
  });
  if (mainFrame) {
    return 'document';
  }
  return classification.resourceType ?? 'subdocument';
}

export default function adBlockNavigationResourceTypeTest(): void {
  describe('Ad-block navigation resource type', () => {
    it('asks a subframe navigation as a subdocument when it has no destination', 0, () => {
      const classifier = new AdBlockRequestClassifierService();
      const resourceType = navigationResourceType(classifier, false, []);
      expect(resourceType).assertEqual('subdocument');
    });

    it('keeps a destination-typed subframe on that type', 0, () => {
      const classifier = new AdBlockRequestClassifierService();
      const resourceType = navigationResourceType(classifier, false, [
        { headerKey: 'Sec-Fetch-Dest', headerValue: 'script' }
      ]);
      expect(resourceType).assertEqual('script');
    });

    it('keeps a main-frame navigation as a document', 0, () => {
      const classifier = new AdBlockRequestClassifierService();
      const resourceType = navigationResourceType(classifier, true, [
        { headerKey: 'Sec-Fetch-Dest', headerValue: 'iframe' }
      ]);
      expect(resourceType).assertEqual('document');
    });
  });
}
