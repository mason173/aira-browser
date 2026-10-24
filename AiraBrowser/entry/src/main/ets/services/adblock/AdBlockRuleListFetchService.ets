import { http } from '@kit.NetworkKit';
import {
  AdBlockFetchedSubscription,
  AdBlockSubscriptionPreprocessorService
} from './AdBlockSubscriptionPreprocessorService';

const AD_BLOCK_RULE_FETCH_TIMEOUT_MS: number = 30000;
const MAX_RULE_LIST_CHARS: number = 5 * 1024 * 1024;

export class AdBlockRuleListFetchService {
  async fetchText(url: string): Promise<string> {
    return (await this.fetchSubscription(url)).text;
  }

  async fetchSubscription(url: string, canContinue?: () => boolean): Promise<AdBlockFetchedSubscription> {
    return new AdBlockSubscriptionPreprocessorService().fetch(url.trim(),
      (address: string, included: boolean): Promise<string> => {
        if (canContinue !== undefined && !canContinue()) {
          throw new Error('规则订阅刷新已取消');
        }
        return this.fetchRawText(address, included);
      });
  }

  private async fetchRawText(url: string, included: boolean): Promise<string> {
    const normalizedUrl = url.trim();
    if (!normalizedUrl.startsWith('https://')) {
      throw new Error('仅支持 HTTPS 规则订阅地址');
    }

    const request = http.createHttp();
    try {
      const response = await request.request(normalizedUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: AD_BLOCK_RULE_FETCH_TIMEOUT_MS,
        readTimeout: AD_BLOCK_RULE_FETCH_TIMEOUT_MS,
        maxLimit: MAX_RULE_LIST_CHARS,
        // API 23+: child lists cannot follow a redirect outside the directory
        // validated by the preprocessor. A redirect fails the complete refresh.
        maxRedirects: included ? 0 : 5,
        usingCache: false,
        header: {
          'Accept': 'text/plain,*/*;q=0.8',
          'User-Agent': 'AiraBrowser/1.0'
        }
      });

      if (response.responseCode < 200 || response.responseCode >= 300 || typeof response.result !== 'string') {
        throw new Error(`规则订阅下载失败（${response.responseCode}）`);
      }
      if (response.result.length === 0) {
        throw new Error('规则订阅为空');
      }
      if (response.result.length > MAX_RULE_LIST_CHARS) {
        throw new Error('规则订阅超过 5MB');
      }
      return response.result;
    } finally {
      request.destroy();
    }
  }
}
