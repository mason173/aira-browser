import { connection, http } from '@kit.NetworkKit';
import { NativeHttpProxyResolutionService } from '../network/NativeHttpProxyResolutionService';
import { UserScriptInstallSourceResolver } from './UserScriptInstallSourceResolver';
import { UserScriptInstallUrlService } from './UserScriptInstallUrlService';

export interface UserScriptSourceFetchResult {
  ok: boolean;
  source: string;
  errorMessage: string;
}

export const USER_SCRIPT_SOURCE_OFFLINE_MESSAGE: string =
  '当前没有可用网络。请连接网络后重试。';
export const USER_SCRIPT_SOURCE_UNREACHABLE_MESSAGE: string =
  '当前网络访问不到这个来源，可能需要可访问外网的网络或代理。连接后可以重试。';
export const USER_SCRIPT_SOURCE_DOWNLOAD_FAILED_MESSAGE: string =
  '下载脚本失败，请稍后重试。';

const USER_SCRIPT_HTTP_ERROR_BASE: number = 2300000;
const USER_SCRIPT_UNREACHABLE_CURL_CODES: number[] = [5, 6, 7, 28, 35, 52, 55, 56];

export interface UserScriptHttpErrorShape {
  code?: number | string;
  message?: string;
}

export function readUserScriptHttpErrorCode(error: Object): number {
  const shaped = error as UserScriptHttpErrorShape;
  if (typeof shaped.code === 'number' && Number.isFinite(shaped.code)) {
    return shaped.code;
  }
  if (typeof shaped.code === 'string') {
    const parsed = Number(shaped.code);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

export function isUserScriptSourceUnreachableErrorCode(code: number): boolean {
  if (!Number.isFinite(code) || code === 0) {
    return false;
  }
  const curlCode = code > USER_SCRIPT_HTTP_ERROR_BASE ? code - USER_SCRIPT_HTTP_ERROR_BASE : code;
  return USER_SCRIPT_UNREACHABLE_CURL_CODES.indexOf(curlCode) >= 0;
}

export function describeUserScriptSourceTransportFailure(error: UserScriptHttpErrorShape): string {
  if (isUserScriptSourceUnreachableErrorCode(readUserScriptHttpErrorCode(error))) {
    return USER_SCRIPT_SOURCE_UNREACHABLE_MESSAGE;
  }
  const shaped = error as UserScriptHttpErrorShape;
  const message = typeof shaped.message === 'string' ? shaped.message : '';
  if (isUserScriptUnreachableTransportText(message)) {
    return USER_SCRIPT_SOURCE_UNREACHABLE_MESSAGE;
  }
  return USER_SCRIPT_SOURCE_DOWNLOAD_FAILED_MESSAGE;
}

function isUserScriptUnreachableTransportText(message: string): boolean {
  const normalized = message.trim().toLowerCase();
  if (normalized.length === 0) {
    return false;
  }
  return normalized.indexOf('couldn\'t resolve host') >= 0 ||
    normalized.indexOf('could not resolve host') >= 0 ||
    normalized.indexOf('failed to resolve the host') >= 0 ||
    normalized.indexOf('couldn\'t connect') >= 0 ||
    normalized.indexOf('failed to connect') >= 0 ||
    normalized.indexOf('operation timeout') >= 0 ||
    normalized.indexOf('timeout was reached') >= 0 ||
    normalized.indexOf('couldn\'t resolve proxy') >= 0;
}

const USER_SCRIPT_SOURCE_FETCH_TIMEOUT_MS: number = 12000;
const MAX_USER_SCRIPT_SOURCE_BYTES: number = 5 * 1024 * 1024;
const USER_SCRIPT_METADATA_MARKER: string = '// ==UserScript==';

export class UserScriptSourceFetchService {
  private installUrlService: UserScriptInstallUrlService = new UserScriptInstallUrlService();
  private installSourceResolver: UserScriptInstallSourceResolver = new UserScriptInstallSourceResolver();
  private proxyResolutionService: NativeHttpProxyResolutionService | undefined = undefined;

  constructor(proxyResolutionService?: NativeHttpProxyResolutionService) {
    this.proxyResolutionService = proxyResolutionService;
  }

  async fetchSource(url: string, allowAnyHttpScriptUrl: boolean = false): Promise<UserScriptSourceFetchResult> {
    const trimmedUrl = url.trim();
    if (!this.isHttpUrl(trimmedUrl)) {
      return this.fail('请输入 http 或 https 链接。');
    }
    if (!allowAnyHttpScriptUrl && !this.installUrlService.canInstallFromUrl(trimmedUrl)) {
      return this.fail('不是可安装的 .user.js 链接。');
    }
    if (!this.hasDefaultNetwork()) {
      return this.fail(USER_SCRIPT_SOURCE_OFFLINE_MESSAGE);
    }
    const sourceUrls = this.installSourceResolver.resolveSourceUrls(trimmedUrl);
    let failure: UserScriptSourceFetchResult | undefined = undefined;
    let sawNonScript = false;
    for (let index = 0; index < sourceUrls.length; index++) {
      const result = await this.fetchExactSource(sourceUrls[index]);
      if (!result.ok) {
        failure = this.preferSourceFetchFailure(failure, result);
        continue;
      }
      if (!this.looksLikeUserScript(result.source)) {
        sawNonScript = true;
        continue;
      }
      return result;
    }
    if (sawNonScript && (failure === undefined || !this.isReachabilityFailure(failure))) {
      return this.fail('未找到 userscript 元数据头。');
    }
    if (failure === undefined) {
      return this.fail(USER_SCRIPT_SOURCE_DOWNLOAD_FAILED_MESSAGE);
    }
    return failure;
  }

  private async fetchExactSource(url: string): Promise<UserScriptSourceFetchResult> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: USER_SCRIPT_SOURCE_FETCH_TIMEOUT_MS,
        readTimeout: USER_SCRIPT_SOURCE_FETCH_TIMEOUT_MS,
        usingCache: true,
        header: {
          'Accept': 'text/javascript,application/javascript,text/plain,*/*;q=0.8',
          'User-Agent': 'AiraBrowser/1.0'
        }
      };
      this.applyNativeProxy(options);
      const response = await request.request(url, options);
      if (response.responseCode === 0) {
        return this.fail(USER_SCRIPT_SOURCE_UNREACHABLE_MESSAGE);
      }
      if (response.responseCode < 200 || response.responseCode >= 300) {
        return this.fail(this.describeHttpStatusFailure(response.responseCode));
      }
      if (typeof response.result !== 'string') {
        return this.fail(USER_SCRIPT_SOURCE_DOWNLOAD_FAILED_MESSAGE);
      }
      const source = response.result.trim();
      if (source.length === 0) {
        return this.fail('脚本内容为空。');
      }
      if (source.length > MAX_USER_SCRIPT_SOURCE_BYTES) {
        return this.fail('脚本超过 5 MB，暂不支持安装。');
      }
      return {
        ok: true,
        source: source,
        errorMessage: ''
      };
    } catch (error) {
      return this.fail(describeUserScriptSourceTransportFailure(error as UserScriptHttpErrorShape));
    } finally {
      request.destroy();
    }
  }

  private applyNativeProxy(options: http.HttpRequestOptions): void {
    const service = this.proxyResolutionService;
    if (service === undefined) {
      return;
    }
    const usingProxy = service.resolveFromCurrentPreferences().usingProxy;
    if (usingProxy !== undefined) {
      options.usingProxy = usingProxy;
    }
  }

  private hasDefaultNetwork(): boolean {
    try {
      return connection.hasDefaultNetSync();
    } catch (_error) {
      return true;
    }
  }

  private describeHttpStatusFailure(status: number): string {
    return `下载脚本失败（HTTP ${status}）。请稍后重试。`;
  }

  private preferSourceFetchFailure(
    current: UserScriptSourceFetchResult | undefined,
    next: UserScriptSourceFetchResult
  ): UserScriptSourceFetchResult {
    if (current === undefined || this.isGenericDownloadFailure(current)) {
      return next;
    }
    if (this.isReachabilityFailure(next) && !this.isReachabilityFailure(current)) {
      return next;
    }
    return current;
  }

  private isReachabilityFailure(result: UserScriptSourceFetchResult): boolean {
    return result.errorMessage === USER_SCRIPT_SOURCE_UNREACHABLE_MESSAGE ||
      result.errorMessage === USER_SCRIPT_SOURCE_OFFLINE_MESSAGE;
  }

  private isGenericDownloadFailure(result: UserScriptSourceFetchResult): boolean {
    return result.errorMessage === USER_SCRIPT_SOURCE_DOWNLOAD_FAILED_MESSAGE ||
      result.errorMessage === '下载脚本失败。';
  }

  private looksLikeUserScript(source: string): boolean {
    const trimmed = source.trim().toLowerCase();
    if (trimmed.startsWith('<!doctype') || trimmed.startsWith('<html') || trimmed.startsWith('<')) {
      return false;
    }
    return source.indexOf(USER_SCRIPT_METADATA_MARKER) >= 0;
  }

  private isHttpUrl(url: string): boolean {
    const normalized = url.trim().toLowerCase();
    return normalized.startsWith('http://') || normalized.startsWith('https://');
  }

  private fail(message: string): UserScriptSourceFetchResult {
    return {
      ok: false,
      source: '',
      errorMessage: message
    };
  }
}
