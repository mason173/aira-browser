import {
  RawUserScriptNativeBridgePayload,
  UserScriptNativeDownloadRequest,
  UserScriptNativeDownloadTaskUpdate
} from '../../features/userscripts/UserScriptNativeBridgeModels';

export class UserScriptNativeDownloadService {
  buildRequest(payload: RawUserScriptNativeBridgePayload, sourcePageUrl: string): UserScriptNativeDownloadRequest | undefined {
    const url = String(payload.url ?? '').trim();
    if (url.length === 0) {
      return undefined;
    }
    return {
      url: url,
      name: String(payload.name ?? '').trim(),
      headers: this.normalizeHeaders(payload.headers),
      sourcePageUrl: sourcePageUrl.trim()
    };
  }

  buildDispatchScript(
    requestId: string,
    type: 'load' | 'error' | 'progress',
    message: string = '',
    update?: UserScriptNativeDownloadTaskUpdate
  ): string {
    const eventLiteral = JSON.stringify({
      id: requestId,
      type: type,
      statusText: message,
      loaded: update?.downloadedSize ?? 0,
      total: update?.totalSize ?? 0,
      lengthComputable: (update?.totalSize ?? 0) > 0,
      status: update?.status ?? ''
    });
    return `
;(function airaUserScriptDownloadDispatch() {
  if (typeof window.__airaUserScriptDownloadDispatch === 'function') {
    window.__airaUserScriptDownloadDispatch(${eventLiteral});
  }
})();
`;
  }

  private normalizeHeaders(headers: Record<string, string> | undefined): Record<string, string> {
    const results: Record<string, string> = {};
    if (headers === undefined) {
      return results;
    }
    Object.keys(headers).forEach((name: string) => {
      const key = String(name ?? '').trim();
      const value = String(headers[name] ?? '').trim();
      if (key.length > 0 && value.length > 0) {
        results[key] = value;
      }
    });
    return results;
  }
}
