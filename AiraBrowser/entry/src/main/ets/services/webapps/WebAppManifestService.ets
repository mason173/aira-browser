import { http } from '@kit.NetworkKit';
import { WebAppManifestParser, WebAppManifestParseResult } from '../../features/webapps/WebAppManifestParser';

export interface WebAppManifestFetchResult {
  ok: boolean;
  reason: string;
  rawJson: string;
  parse?: WebAppManifestParseResult;
  status: number;
}

const FETCH_CONNECT_TIMEOUT_MS: number = 8000;
const FETCH_READ_TIMEOUT_MS: number = 8000;

export class WebAppManifestService {
  private parser: WebAppManifestParser = new WebAppManifestParser();

  async fetchAndParse(manifestUrl: string, documentUrl: string): Promise<WebAppManifestFetchResult> {
    const url = manifestUrl.trim();
    if (url.length === 0) {
      return { ok: false, reason: 'empty_manifest_url', rawJson: '', status: 0 };
    }
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: FETCH_CONNECT_TIMEOUT_MS,
        readTimeout: FETCH_READ_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING,
        usingCache: true,
        header: {
          'Accept': 'application/manifest+json, application/json;q=0.9, */*;q=0.5'
        }
      });
      const status = Number(response.responseCode ?? 0);
      if (status < 200 || status >= 400) {
        return {
          ok: false,
          reason: `http_status_${status}`,
          rawJson: '',
          status: status
        };
      }
      const raw = typeof response.result === 'string' ? response.result : String(response.result ?? '');
      const parse = this.parser.parse(raw, url, documentUrl);
      return {
        ok: parse.ok,
        reason: parse.reason,
        rawJson: raw,
        parse: parse,
        status: status
      };
    } catch (_error) {
      return { ok: false, reason: 'request_failed', rawJson: '', status: 0 };
    } finally {
      try {
        request.destroy();
      } catch (_error) {
      }
    }
  }
}
