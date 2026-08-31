import { http } from '@kit.NetworkKit';

interface QihooSearchSuggestItem {
  word?: string;
}

interface QihooSearchSuggestPayload {
  errorcode?: number;
  query?: string;
  result?: QihooSearchSuggestItem[];
}

const QIHOO_SEARCH_SUGGEST_ENDPOINT: string = 'https://sug.so.360.cn/suggest';
const QIHOO_SEARCH_SUGGEST_TIMEOUT_MS: number = 3500;

export class QihooSearchSuggestionService {
  async fetchSuggestions(query: string, limit: number): Promise<string[]> {
    const trimmedQuery = query.trim();
    if (trimmedQuery.length === 0 || limit <= 0) {
      return [];
    }

    const request = http.createHttp();
    try {
      const response = await request.request(this.buildSuggestUrl(trimmedQuery), {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: QIHOO_SEARCH_SUGGEST_TIMEOUT_MS,
        readTimeout: QIHOO_SEARCH_SUGGEST_TIMEOUT_MS,
        usingCache: true,
        header: {
          'Accept': 'application/json',
          'User-Agent': 'AiraBrowser/1.0'
        }
      });

      if (response.responseCode < 200 || response.responseCode >= 300 || typeof response.result !== 'string') {
        return [];
      }

      return this.parseSuggestPayload(response.result, trimmedQuery, limit);
    } catch (_error) {
      return [];
    } finally {
      request.destroy();
    }
  }

  private buildSuggestUrl(query: string): string {
    return `${QIHOO_SEARCH_SUGGEST_ENDPOINT}?encodein=utf-8&encodeout=utf-8&format=json&fields=word&word=${encodeURIComponent(query)}`;
  }

  private parseSuggestPayload(payloadText: string, query: string, limit: number): string[] {
    const payload = JSON.parse(payloadText) as QihooSearchSuggestPayload;
    if (payload.errorcode !== 0 || !Array.isArray(payload.result)) {
      return [];
    }

    const normalizedQuery = query.trim().toLowerCase();
    const seen: Set<string> = new Set<string>();
    const results: string[] = [];
    payload.result.forEach((item: QihooSearchSuggestItem) => {
      const word = (item.word ?? '').trim();
      const key = word.toLowerCase();
      if (word.length === 0 || key === normalizedQuery || seen.has(key) || results.length >= limit) {
        return;
      }
      seen.add(key);
      results.push(word);
    });
    return results;
  }
}
