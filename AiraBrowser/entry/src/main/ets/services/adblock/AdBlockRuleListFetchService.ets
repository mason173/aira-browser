import { http } from '@kit.NetworkKit';

const AD_BLOCK_RULE_FETCH_TIMEOUT_MS: number = 30000;
const MAX_RULE_LIST_CHARS: number = 5 * 1024 * 1024;

export class AdBlockRuleListFetchService {
  async fetchText(url: string): Promise<string> {
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
