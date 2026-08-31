import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  WebpageTranslationApplyItem,
  WebpageTranslationTextItem
} from '../web/WebpageTranslationRuntimeModels';
import {
  TranslationProviderError,
  TranslationProviderFailureClassifierService
} from './TranslationProviderFailureClassifierService';
import {
  AIRA_DISTRIBUTION_CAPABILITY_OWNER,
  AIRA_HOSTED_API_BASE_URL
} from '../../common/config/AiraDistributionCapabilityOwner';

const AIRA_SYSTEM_TRANSLATION_ENDPOINT: string = AIRA_HOSTED_API_BASE_URL + '/translation/system/batch';
const AIRA_SYSTEM_TRANSLATION_TIMEOUT_MS: number = 45000;
const AIRA_SYSTEM_TRANSLATION_LOG_DOMAIN: number = 0x0000;
const AIRA_SYSTEM_TRANSLATION_LOG_TAG: string = 'AiraSystemTranslate';

interface AiraSystemTranslationRequestText {
  id: string;
  text: string;
}

interface AiraSystemTranslationRequestBody {
  sourceLanguage: string;
  targetLanguage: string;
  texts: AiraSystemTranslationRequestText[];
  source?: string;
}

interface AiraSystemTranslationResponseItem {
  id?: string;
  translatedText?: string;
  TargetText?: string;
  text?: string;
  translation?: string;
}

interface AiraSystemTranslationResponseBody {
  ok?: boolean;
  code?: string;
  provider?: string;
  items?: AiraSystemTranslationResponseItem[];
  translations?: AiraSystemTranslationResponseItem[];
  results?: AiraSystemTranslationResponseItem[];
  result?: AiraSystemTranslationResponseBody | AiraSystemTranslationResponseItem[] | string;
  body?: AiraSystemTranslationResponseBody | AiraSystemTranslationResponseItem[] | string;
  data?: AiraSystemTranslationResponseBody;
  Response?: AiraSystemTranslationResponseItem;
  error?: AiraSystemTranslationErrorPayload;
  errorMessage?: string;
  message?: string;
  statusCode?: string | number;
}

export interface AiraSystemTranslationFunctionAdapter {
  post(url: string, body: AiraSystemTranslationRequestBody, timeoutMs: number): Promise<Object | string | null | undefined>;
}

class NetworkAiraSystemTranslationFunctionAdapter implements AiraSystemTranslationFunctionAdapter {
  async post(
    url: string,
    body: AiraSystemTranslationRequestBody,
    timeoutMs: number
  ): Promise<Object | string | null | undefined> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.POST,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        usingCache: false,
        header: {
          'Accept': 'application/json',
          'Content-Type': 'application/json; charset=utf-8',
          'User-Agent': 'AiraBrowser/1.0'
        },
        extraData: JSON.stringify(body)
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        const errorResponse: AiraSystemTranslationResponseBody = {
          ok: false,
          code: 'http_error',
          message: `Aira 系统翻译服务请求失败（${response.responseCode}）。`,
          statusCode: response.responseCode
        };
        return errorResponse;
      }
      return response.result as string | Object | null | undefined;
    } finally {
      request.destroy();
    }
  }
}

export class AiraSystemTranslationFunctionService {
  private adapter: AiraSystemTranslationFunctionAdapter;
  private failureClassifier: TranslationProviderFailureClassifierService =
    new TranslationProviderFailureClassifierService();

  constructor(adapter?: AiraSystemTranslationFunctionAdapter) {
    this.adapter = adapter ?? new NetworkAiraSystemTranslationFunctionAdapter();
  }

  async translateBatch(
    items: WebpageTranslationTextItem[],
    sourceLanguage: string,
    targetLanguage: string
  ): Promise<WebpageTranslationApplyItem[]> {
    if (items.length === 0) {
      return [];
    }
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      throw new TranslationProviderError(this.failureClassifier.buildFailure(
        'missing_provider',
        AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('aira_cloud')
      ));
    }
    try {
      const requestBody: AiraSystemTranslationRequestBody = {
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        source: 'app_translation',
        texts: items.map((item: WebpageTranslationTextItem): AiraSystemTranslationRequestText => {
          return {
            id: item.id,
            text: item.text
          };
        })
      };
      const rawValue = await this.adapter.post(
        AIRA_SYSTEM_TRANSLATION_ENDPOINT,
        requestBody,
        AIRA_SYSTEM_TRANSLATION_TIMEOUT_MS
      );
      hilog.info(
        AIRA_SYSTEM_TRANSLATION_LOG_DOMAIN,
        AIRA_SYSTEM_TRANSLATION_LOG_TAG,
        'system translation raw result: %{public}s',
        this.describeRawValue(rawValue)
      );
      const parsed = this.parseFunctionValue(rawValue);
      const responseItems = this.resolveResponseItems(parsed);
      if (responseItems.length === 0) {
        throw new TranslationProviderError(this.failureClassifier.buildFailure(
          'invalid_response',
          `Aira 系统翻译没有返回可用译文。返回结构：${this.describeParsedShape(parsed)}`
        ));
      }
      return this.mapTranslations(items, responseItems);
    } catch (error) {
      if (error instanceof TranslationProviderError) {
        throw error;
      }
      throw new TranslationProviderError(this.classifyFunctionError(error as Error | Object));
    }
  }

  private parseFunctionValue(value: Object | string | null | undefined): AiraSystemTranslationResponseBody {
    if (value === undefined || value === null) {
      throw new TranslationProviderError(this.failureClassifier.buildFailure(
        'invalid_response',
        'Aira 系统翻译服务返回为空。'
      ));
    }
    if (typeof value === 'string') {
      try {
        return JSON.parse(value) as AiraSystemTranslationResponseBody;
      } catch (_error) {
        throw new TranslationProviderError(this.failureClassifier.buildFailure(
          'invalid_response',
          'Aira 系统翻译返回的 JSON 无法解析。'
        ));
      }
    }
    return value as AiraSystemTranslationResponseBody;
  }

  private resolveResponseItems(parsed: AiraSystemTranslationResponseBody): AiraSystemTranslationResponseItem[] {
    const providerError = this.resolveProviderErrorMessage(parsed);
    if (providerError.length > 0) {
      throw new TranslationProviderError(this.failureClassifier.buildFailure(
        'server_error',
        `Aira 系统翻译失败：${providerError}`
      ));
    }
    if (Array.isArray(parsed.items)) {
      return parsed.items;
    }
    if (Array.isArray(parsed.translations)) {
      return parsed.translations;
    }
    if (Array.isArray(parsed.results)) {
      return parsed.results;
    }
    if (parsed.data !== undefined) {
      return this.resolveNestedValue(parsed.data);
    }
    if (parsed.body !== undefined) {
      return this.resolveNestedValue(parsed.body);
    }
    if (parsed.result !== undefined) {
      return this.resolveNestedValue(parsed.result);
    }
    if (parsed.Response !== undefined) {
      return [parsed.Response];
    }
    return [];
  }

  private resolveNestedValue(
    value: AiraSystemTranslationResponseBody | AiraSystemTranslationResponseItem[] | string
  ): AiraSystemTranslationResponseItem[] {
    if (Array.isArray(value)) {
      return value;
    }
    if (typeof value === 'string') {
      return this.resolveResponseItems(this.parseFunctionValue(value));
    }
    return this.resolveResponseItems(value);
  }

  private mapTranslations(
    sourceItems: WebpageTranslationTextItem[],
    responseItems: AiraSystemTranslationResponseItem[]
  ): WebpageTranslationApplyItem[] {
    const results: WebpageTranslationApplyItem[] = [];
    responseItems.forEach((item: AiraSystemTranslationResponseItem, index: number) => {
      const translatedText = (item.translatedText ?? item.TargetText ?? item.translation ?? item.text ?? '').trim();
      const fallbackId = sourceItems[index]?.id ?? '';
      const id = (item.id ?? fallbackId).trim();
      if (id.length > 0 && translatedText.length > 0) {
        results.push({
          id: id,
          translatedText: translatedText
        });
      }
    });
    if (results.length === 0) {
      throw new TranslationProviderError(this.failureClassifier.buildFailure(
        'invalid_response',
        'Aira 系统翻译返回的译文为空。'
      ));
    }
    return results;
  }

  private resolveProviderErrorMessage(parsed: AiraSystemTranslationResponseBody): string {
    const errorMessage = parsed.error?.message ?? '';
    if (errorMessage.trim().length > 0) {
      return errorMessage.trim();
    }
    const plainErrorMessage = parsed.errorMessage ?? '';
    if (plainErrorMessage.trim().length > 0) {
      return plainErrorMessage.trim();
    }
    const message = parsed.message ?? '';
    if (parsed.ok === false && message.trim().length > 0) {
      return message.trim();
    }
    if (message.trim().toLowerCase().indexOf('error') >= 0 ||
      message.trim().toLowerCase().indexOf('cannot ') >= 0) {
      return message.trim();
    }
    return '';
  }

  private classifyFunctionError(error: Error | Object) {
    const rawMessage = this.stringifyError(error);
    const lowerMessage = rawMessage.toLowerCase();
    const statusCode = this.resolveStatusCode(error, rawMessage);
    if (statusCode === 402 || statusCode === 429 || lowerMessage.indexOf('quota') >= 0 ||
      lowerMessage.indexOf('rate') >= 0 || lowerMessage.indexOf('limit') >= 0 ||
      lowerMessage.indexOf('exceed') >= 0 || lowerMessage.indexOf('too many request') >= 0) {
      return this.failureClassifier.buildFailure(
        'quota_or_rate_limit',
        'Aira 系统翻译额度或频率受限，稍后再试。',
        statusCode
      );
    }
    if (statusCode === 401 || statusCode === 403 || lowerMessage.indexOf('unauthorized') >= 0 ||
      lowerMessage.indexOf('token') >= 0 || lowerMessage.indexOf('credential') >= 0) {
      return this.failureClassifier.buildFailure(
        'missing_provider',
        'Aira 系统翻译鉴权失败，请检查自有服务配置。',
        statusCode
      );
    }
    if (lowerMessage.indexOf('timeout') >= 0 || lowerMessage.indexOf('network') >= 0) {
      return this.failureClassifier.buildFailure(
        'network_unavailable',
        '网络连接异常，无法完成 Aira 系统翻译。',
        statusCode
      );
    }
    if (statusCode >= 500) {
      return this.failureClassifier.buildFailure(
        'server_error',
        'Aira 系统翻译暂时不可用。',
        statusCode
      );
    }
    if (lowerMessage.indexOf('cannot read') >= 0 || lowerMessage.indexOf('undefined') >= 0) {
      return this.failureClassifier.buildFailure(
        'server_error',
        'Aira 系统翻译服务执行异常，请检查服务入参读取和返回结构。',
        statusCode
      );
    }
    return this.failureClassifier.buildFailure(
      'server_error',
      rawMessage.length > 0 ? `Aira 系统翻译失败：${rawMessage}` : 'Aira 系统翻译失败。',
      statusCode
    );
  }

  private resolveStatusCode(error: Error | Object, rawMessage: string): number {
    const detail = error as AiraSystemTranslationErrorDetail;
    if (typeof detail.code === 'number') {
      return detail.code;
    }
    const match = rawMessage.match(/(?:responseCode|status|code)["':=\s]+(\d{3})/);
    if (match !== null) {
      return Number(match[1]);
    }
    return 0;
  }

  private stringifyError(error: Error | Object): string {
    if (error instanceof Error) {
      return error.message;
    }
    try {
      return JSON.stringify(error);
    } catch (_error) {
      return `${error}`;
    }
  }

  private describeRawValue(value: Object | string | null | undefined): string {
    if (value === undefined) {
      return 'undefined';
    }
    if (value === null) {
      return 'null';
    }
    if (typeof value === 'string') {
      return value.substring(0, 500);
    }
    try {
      return JSON.stringify(value).substring(0, 500);
    } catch (_error) {
      return `${value}`;
    }
  }

  private describeParsedShape(parsed: AiraSystemTranslationResponseBody): string {
    const keys: string[] = Object.keys(parsed);
    const statusCode = parsed.statusCode === undefined ? '' : ` status=${parsed.statusCode}`;
    const bodyType = parsed.body === undefined ? '' : ` bodyType=${typeof parsed.body}`;
    return `keys=${keys.join(',')}${statusCode}${bodyType}`;
  }

}

interface AiraSystemTranslationErrorDetail {
  code?: number;
}

interface AiraSystemTranslationErrorPayload {
  message?: string;
}
