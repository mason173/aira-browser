import { http } from '@kit.NetworkKit';
import {
  TranslationProviderConfig,
  TranslationProviderTemplateId
} from '../../common/models/BrowserModels';
import {
  WebpageTranslationApplyItem,
  WebpageTranslationTextItem
} from '../web/WebpageTranslationRuntimeModels';
import { TranslationProviderCryptoService } from './TranslationProviderCryptoService';
import {
  TranslationProviderError,
  TranslationProviderFailureClassifierService
} from './TranslationProviderFailureClassifierService';
import { AiraSystemTranslationFunctionService } from './AiraSystemTranslationFunctionService';

const TRANSLATION_REQUEST_TIMEOUT_MS: number = 20000;
const AIRA_USER_AGENT: string = 'AiraBrowser/1.0';

interface ProviderHttpRequest {
  url: string;
  method: http.RequestMethod;
  headers: Record<string, string>;
  body: string;
  responseParser: (rawBody: string, sourceItems: WebpageTranslationTextItem[]) => WebpageTranslationApplyItem[];
}

interface CustomHttpTranslationRequestText {
  id: string;
  text: string;
}

interface CustomHttpTranslationRequestBody {
  sourceLanguage: string;
  targetLanguage: string;
  texts: CustomHttpTranslationRequestText[];
}

interface GenericTranslationResponseItem {
  id?: string;
  translatedText?: string;
  text?: string;
  translation?: string;
}

interface GenericTranslationResponseBody {
  items?: GenericTranslationResponseItem[];
  translations?: GenericTranslationResponseItem[];
  results?: GenericTranslationResponseItem[];
  data?: GenericTranslationResponseBody;
}

interface DeepLTranslationItem {
  text?: string;
}

interface DeepLTranslationResponse {
  translations?: DeepLTranslationItem[];
}

interface GoogleTranslationItem {
  translatedText?: string;
}

interface GoogleTranslationData {
  translations?: GoogleTranslationItem[];
}

interface GoogleTranslationResponse {
  data?: GoogleTranslationData;
}

interface ProviderErrorPayload {
  message?: string;
  status?: string;
}

interface ProviderErrorResponse {
  error?: ProviderErrorPayload;
  message?: string;
  error_description?: string;
}

interface MicrosoftTranslationItem {
  text?: string;
}

interface MicrosoftTranslationResponseItem {
  translations?: MicrosoftTranslationItem[];
}

interface BaiduTranslationItem {
  dst?: string;
}

interface BaiduTranslationResponse {
  trans_result?: BaiduTranslationItem[];
  error_code?: string;
  error_msg?: string;
}

interface YoudaoWebTranslationItem {
  tgt?: string;
}

interface YoudaoTranslationResponse {
  errorCode?: string;
  translation?: string[];
  web?: YoudaoWebTranslationItem[];
}

interface TencentTranslationResponsePayload {
  TargetText?: string;
  TargetTextList?: string[];
}

interface TencentTranslationResponse {
  Response?: TencentTranslationResponsePayload;
}

interface AlibabaTranslationResponseData {
  Translated?: string;
  TranslatedText?: string;
}

interface AlibabaTranslationResponse {
  Data?: AlibabaTranslationResponseData;
}

interface VolcanoTranslationItem {
  Translation?: string;
  translation?: string;
}

interface VolcanoTranslationResponsePayload {
  TranslationList?: VolcanoTranslationItem[];
}

interface VolcanoTranslationResponse {
  TranslationList?: VolcanoTranslationItem[];
  ResponseMetadata?: Object;
  Response?: VolcanoTranslationResponsePayload;
}

interface ProviderQueryParam {
  key: string;
  value: string;
}

interface DeepLTranslationRequestBody {
  text: string[];
  source_lang: string;
  target_lang: string;
  tag_handling: string;
}

interface GoogleTranslationRequestBody {
  q: string[];
  source: string;
  target: string;
  format: string;
}

interface MicrosoftTranslationRequestText {
  Text: string;
}

export class TranslationProviderRequestService {
  private failureClassifier: TranslationProviderFailureClassifierService =
    new TranslationProviderFailureClassifierService();
  private cryptoService: TranslationProviderCryptoService = new TranslationProviderCryptoService();
  private airaSystemService: AiraSystemTranslationFunctionService = new AiraSystemTranslationFunctionService();
  private activeRequests: http.HttpRequest[] = [];

  cancelActiveRequests(): void {
    this.activeRequests.forEach((request: http.HttpRequest) => {
      try {
        request.destroy();
      } catch (_error) {
      }
    });
    this.activeRequests = [];
  }

  async translateBatch(
    provider: TranslationProviderConfig,
    items: WebpageTranslationTextItem[],
    sourceLanguage: string,
    targetLanguage: string
  ): Promise<WebpageTranslationApplyItem[]> {
    this.validateProvider(provider);
    if (items.length === 0) {
      return [];
    }

    if (provider.templateId === 'aira_system') {
      return this.airaSystemService.translateBatch(items, sourceLanguage, targetLanguage);
    }

    const providerRequest = this.buildProviderRequest(provider, items, sourceLanguage, targetLanguage);
    const request = http.createHttp();
    this.activeRequests.push(request);
    try {
      const response = await request.request(providerRequest.url, {
        method: providerRequest.method,
        extraData: providerRequest.body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: TRANSLATION_REQUEST_TIMEOUT_MS,
        readTimeout: TRANSLATION_REQUEST_TIMEOUT_MS,
        usingCache: false,
        header: providerRequest.headers
      });

      if (response.responseCode < 200 || response.responseCode >= 300) {
        const rawBody = typeof response.result === 'string' ? response.result : '';
        const providerMessage = this.buildProviderHttpFailureMessage(provider, response.responseCode, rawBody);
        if (providerMessage.length > 0) {
          throw new TranslationProviderError(
            this.failureClassifier.classifyHttpStatusWithMessage(response.responseCode, providerMessage)
          );
        }
        throw new TranslationProviderError(this.failureClassifier.classifyHttpStatus(response.responseCode));
      }
      if (typeof response.result !== 'string') {
        throw new TranslationProviderError(this.failureClassifier.buildFailure(
          'invalid_response',
          '翻译服务返回格式无效。'
        ));
      }
      return providerRequest.responseParser(response.result, items);
    } catch (error) {
      if (error instanceof TranslationProviderError) {
        throw error;
      }
      throw new TranslationProviderError(this.failureClassifier.classifyError(error as Error));
    } finally {
      this.activeRequests = this.activeRequests.filter((item: http.HttpRequest) => item !== request);
      try {
        request.destroy();
      } catch (_error) {
      }
    }
  }

  supportsProvider(templateId: TranslationProviderTemplateId): boolean {
    switch (templateId) {
      case 'aira_system':
      case 'custom_http':
      case 'deepl':
      case 'google_cloud':
      case 'microsoft':
      case 'baidu':
      case 'youdao':
      case 'tencent_cloud':
      case 'alibaba_cloud':
      case 'volcano':
        return true;
      default:
        return false;
    }
  }

  private validateProvider(provider: TranslationProviderConfig): void {
    if (!this.supportsProvider(provider.templateId)) {
      throw new TranslationProviderError(this.failureClassifier.buildFailure(
        'missing_provider',
        '当前翻译服务模板尚未实现。'
      ));
    }
    if (provider.templateId === 'aira_system') {
      return;
    }
    if (provider.templateId === 'custom_http') {
      this.validateHttpsEndpoint(provider.endpoint, '自定义翻译服务必须使用 HTTPS endpoint。');
      const lowerEndpoint = provider.endpoint.trim().toLowerCase();
      if (lowerEndpoint.indexOf('?') >= 0 &&
        (lowerEndpoint.indexOf('key=') >= 0 || lowerEndpoint.indexOf('token=') >= 0 ||
          lowerEndpoint.indexOf('secret=') >= 0 || lowerEndpoint.indexOf('password=') >= 0)) {
        throw new TranslationProviderError(this.failureClassifier.buildFailure(
          'invalid_endpoint',
          '翻译服务密钥不能放在 URL 查询参数中。'
        ));
      }
      return;
    }
    const validationMessage = this.validateProviderCredentials(provider);
    if (validationMessage.length > 0) {
      throw new TranslationProviderError(this.failureClassifier.buildFailure(
        'missing_provider',
        validationMessage
      ));
    }
  }

  private validateProviderCredentials(provider: TranslationProviderConfig): string {
    switch (provider.templateId) {
      case 'aira_system':
        return '';
      case 'deepl':
      case 'google_cloud':
      case 'microsoft':
        return provider.apiKey.trim().length > 0 ? '' : '请填写该服务商的 API Key。';
      case 'baidu':
      case 'youdao':
        return provider.appId.trim().length > 0 && provider.secretKey.trim().length > 0
          ? ''
          : '请填写该服务商的应用 ID 和应用密钥。';
      case 'tencent_cloud':
        return provider.appId.trim().length > 0 && provider.secretKey.trim().length > 0
          ? ''
          : '请填写腾讯云 SecretId 和 SecretKey。';
      case 'alibaba_cloud':
      case 'volcano':
        return provider.appId.trim().length > 0 && provider.secretKey.trim().length > 0
          ? ''
          : '请填写 Access Key 和 Secret Key。';
      default:
        return '';
    }
  }

  private validateHttpsEndpoint(endpoint: string, message: string): void {
    const normalizedEndpoint = endpoint.trim();
    if (normalizedEndpoint.length === 0 || !normalizedEndpoint.toLowerCase().startsWith('https://')) {
      throw new TranslationProviderError(this.failureClassifier.buildFailure('invalid_endpoint', message));
    }
  }

  private buildProviderRequest(
    provider: TranslationProviderConfig,
    items: WebpageTranslationTextItem[],
    sourceLanguage: string,
    targetLanguage: string
  ): ProviderHttpRequest {
    switch (provider.templateId) {
      case 'aira_system':
        throw new TranslationProviderError(this.failureClassifier.buildFailure(
          'missing_provider',
          'Aira 系统翻译必须通过 Aira 自有服务接口调用。'
        ));
      case 'custom_http':
        return this.buildCustomHttpRequest(provider, items, sourceLanguage, targetLanguage);
      case 'deepl':
        return this.buildDeepLRequest(provider, items, sourceLanguage, targetLanguage);
      case 'google_cloud':
        return this.buildGoogleCloudRequest(provider, items, sourceLanguage, targetLanguage);
      case 'microsoft':
        return this.buildMicrosoftRequest(provider, items, sourceLanguage, targetLanguage);
      case 'baidu':
        return this.buildBaiduRequest(provider, items, sourceLanguage, targetLanguage);
      case 'youdao':
        return this.buildYoudaoRequest(provider, items, sourceLanguage, targetLanguage);
      case 'tencent_cloud':
        return this.buildTencentRequest(provider, items, sourceLanguage, targetLanguage);
      case 'alibaba_cloud':
        return this.buildAlibabaRequest(provider, items, sourceLanguage, targetLanguage);
      case 'volcano':
        return this.buildVolcanoRequest(provider, items, sourceLanguage, targetLanguage);
      default:
        throw new TranslationProviderError(this.failureClassifier.buildFailure(
          'missing_provider',
          '当前翻译服务模板尚未实现。'
        ));
    }
  }

  private buildCustomHttpRequest(
    provider: TranslationProviderConfig,
    items: WebpageTranslationTextItem[],
    sourceLanguage: string,
    targetLanguage: string
  ): ProviderHttpRequest {
    return {
      url: provider.endpoint.trim(),
      method: http.RequestMethod.POST,
      headers: this.jsonHeaders(),
      body: JSON.stringify({
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        texts: items.map((item: WebpageTranslationTextItem): CustomHttpTranslationRequestText => {
          return {
            id: item.id,
            text: item.text
          };
        })
      } as CustomHttpTranslationRequestBody),
      responseParser: (rawBody: string, sourceItems: WebpageTranslationTextItem[]) =>
        this.parseGenericResponse(rawBody, sourceItems)
    };
  }

  private buildDeepLRequest(
    provider: TranslationProviderConfig,
    items: WebpageTranslationTextItem[],
    sourceLanguage: string,
    targetLanguage: string
  ): ProviderHttpRequest {
    const endpoint = provider.endpoint.trim().length > 0
      ? provider.endpoint.trim()
      : 'https://api-free.deepl.com/v2/translate';
    this.validateHttpsEndpoint(endpoint, 'DeepL endpoint 必须使用 HTTPS。');
    const body: DeepLTranslationRequestBody = {
      text: items.map((item: WebpageTranslationTextItem): string => item.text),
      source_lang: this.toDeepLLanguage(sourceLanguage),
      target_lang: this.toDeepLLanguage(targetLanguage),
      tag_handling: 'html'
    };
    const headers = this.jsonHeaders();
    headers['Authorization'] = `DeepL-Auth-Key ${provider.apiKey.trim()}`;
    return {
      url: endpoint,
      method: http.RequestMethod.POST,
      headers: headers,
      body: JSON.stringify(body),
      responseParser: (rawBody: string, sourceItems: WebpageTranslationTextItem[]) =>
        this.parseDeepLResponse(rawBody, sourceItems)
    };
  }

  private buildGoogleCloudRequest(
    provider: TranslationProviderConfig,
    items: WebpageTranslationTextItem[],
    sourceLanguage: string,
    targetLanguage: string
  ): ProviderHttpRequest {
    const endpoint = provider.endpoint.trim().length > 0
      ? provider.endpoint.trim()
      : 'https://translation.googleapis.com/language/translate/v2';
    this.validateHttpsEndpoint(endpoint, 'Google Cloud Translation endpoint 必须使用 HTTPS。');
    const url = `${endpoint}${endpoint.indexOf('?') >= 0 ? '&' : '?'}key=${encodeURIComponent(provider.apiKey.trim())}`;
    const body: GoogleTranslationRequestBody = {
      q: items.map((item: WebpageTranslationTextItem): string => item.text),
      source: this.toGoogleLanguage(sourceLanguage),
      target: this.toGoogleLanguage(targetLanguage),
      format: 'text'
    };
    return {
      url: url,
      method: http.RequestMethod.POST,
      headers: this.jsonHeaders(),
      body: JSON.stringify(body),
      responseParser: (rawBody: string, sourceItems: WebpageTranslationTextItem[]) =>
        this.parseGoogleResponse(rawBody, sourceItems)
    };
  }

  private buildMicrosoftRequest(
    provider: TranslationProviderConfig,
    items: WebpageTranslationTextItem[],
    sourceLanguage: string,
    targetLanguage: string
  ): ProviderHttpRequest {
    const endpoint = provider.endpoint.trim().length > 0
      ? provider.endpoint.trim()
      : 'https://api.cognitive.microsofttranslator.com/translate?api-version=3.0';
    this.validateHttpsEndpoint(endpoint, 'Microsoft Translator endpoint 必须使用 HTTPS。');
    const url = `${endpoint}${endpoint.indexOf('?') >= 0 ? '&' : '?'}from=${encodeURIComponent(
      this.toMicrosoftLanguage(sourceLanguage)
    )}&to=${encodeURIComponent(this.toMicrosoftLanguage(targetLanguage))}`;
    const headers = this.jsonHeaders();
    headers['Ocp-Apim-Subscription-Key'] = provider.apiKey.trim();
    if (provider.region.trim().length > 0) {
      headers['Ocp-Apim-Subscription-Region'] = provider.region.trim();
    }
    return {
      url: url,
      method: http.RequestMethod.POST,
      headers: headers,
      body: JSON.stringify(items.map((item: WebpageTranslationTextItem): MicrosoftTranslationRequestText => {
        return { Text: item.text };
      })),
      responseParser: (rawBody: string, sourceItems: WebpageTranslationTextItem[]) =>
        this.parseMicrosoftResponse(rawBody, sourceItems)
    };
  }

  private buildBaiduRequest(
    provider: TranslationProviderConfig,
    items: WebpageTranslationTextItem[],
    sourceLanguage: string,
    targetLanguage: string
  ): ProviderHttpRequest {
    const endpoint = provider.endpoint.trim().length > 0
      ? provider.endpoint.trim()
      : 'https://fanyi-api.baidu.com/api/trans/vip/translate';
    this.validateHttpsEndpoint(endpoint, '百度翻译 endpoint 必须使用 HTTPS。');
    const text = this.joinTexts(items);
    const salt = `${Date.now()}${Math.floor(Math.random() * 100000)}`;
    const sign = this.cryptoService.md5Hex(`${provider.appId.trim()}${text}${salt}${provider.secretKey.trim()}`);
    return {
      url: endpoint,
      method: http.RequestMethod.POST,
      headers: this.formHeaders(),
      body: this.formEncode([
        { key: 'q', value: text },
        { key: 'from', value: this.toBaiduLanguage(sourceLanguage) },
        { key: 'to', value: this.toBaiduLanguage(targetLanguage) },
        { key: 'appid', value: provider.appId.trim() },
        { key: 'salt', value: salt },
        { key: 'sign', value: sign }
      ]),
      responseParser: (rawBody: string, sourceItems: WebpageTranslationTextItem[]) =>
        this.parseBaiduResponse(rawBody, sourceItems)
    };
  }

  private buildYoudaoRequest(
    provider: TranslationProviderConfig,
    items: WebpageTranslationTextItem[],
    sourceLanguage: string,
    targetLanguage: string
  ): ProviderHttpRequest {
    const endpoint = provider.endpoint.trim().length > 0
      ? provider.endpoint.trim()
      : 'https://openapi.youdao.com/api';
    this.validateHttpsEndpoint(endpoint, '有道智云 endpoint 必须使用 HTTPS。');
    const text = this.joinTexts(items);
    const salt = `${Date.now()}${Math.floor(Math.random() * 100000)}`;
    const curtime = `${Math.floor(Date.now() / 1000)}`;
    const input = this.truncateYoudaoInput(text);
    const sign = this.cryptoService.sha256Hex(`${provider.appId.trim()}${input}${salt}${curtime}${provider.secretKey.trim()}`);
    return {
      url: endpoint,
      method: http.RequestMethod.POST,
      headers: this.formHeaders(),
      body: this.formEncode([
        { key: 'q', value: text },
        { key: 'from', value: this.toYoudaoLanguage(sourceLanguage) },
        { key: 'to', value: this.toYoudaoLanguage(targetLanguage) },
        { key: 'appKey', value: provider.appId.trim() },
        { key: 'salt', value: salt },
        { key: 'sign', value: sign },
        { key: 'signType', value: 'v3' },
        { key: 'curtime', value: curtime }
      ]),
      responseParser: (rawBody: string, sourceItems: WebpageTranslationTextItem[]) =>
        this.parseYoudaoResponse(rawBody, sourceItems)
    };
  }

  private buildTencentRequest(
    provider: TranslationProviderConfig,
    items: WebpageTranslationTextItem[],
    sourceLanguage: string,
    targetLanguage: string
  ): ProviderHttpRequest {
    const endpoint = provider.endpoint.trim().length > 0
      ? provider.endpoint.trim()
      : 'https://tmt.tencentcloudapi.com';
    this.validateHttpsEndpoint(endpoint, '腾讯云机器翻译 endpoint 必须使用 HTTPS。');
    const region = provider.region.trim().length > 0 ? provider.region.trim() : 'ap-guangzhou';
    const timestamp = Math.floor(Date.now() / 1000);
    const payload = JSON.stringify({
      SourceTextList: items.map((item: WebpageTranslationTextItem): string => item.text),
      Source: this.toTencentLanguage(sourceLanguage),
      Target: this.toTencentLanguage(targetLanguage),
      ProjectId: 0
    });
    const headers = this.buildTencentHeaders(provider, region, timestamp, payload, 'TextTranslateBatch');
    return {
      url: endpoint,
      method: http.RequestMethod.POST,
      headers: headers,
      body: payload,
      responseParser: (rawBody: string, sourceItems: WebpageTranslationTextItem[]) =>
        this.parseTencentBatchResponse(rawBody, sourceItems)
    };
  }

  private buildAlibabaRequest(
    provider: TranslationProviderConfig,
    items: WebpageTranslationTextItem[],
    sourceLanguage: string,
    targetLanguage: string
  ): ProviderHttpRequest {
    const endpoint = provider.endpoint.trim().length > 0
      ? provider.endpoint.trim()
      : 'https://mt.cn-hangzhou.aliyuncs.com/';
    this.validateHttpsEndpoint(endpoint, '阿里云机器翻译 endpoint 必须使用 HTTPS。');
    const text = this.joinTexts(items);
    const params: ProviderQueryParam[] = [
      { key: 'Action', value: 'TranslateGeneral' },
      { key: 'Format', value: 'JSON' },
      { key: 'Version', value: '2018-10-12' },
      { key: 'AccessKeyId', value: provider.appId.trim() },
      { key: 'SignatureMethod', value: 'HMAC-SHA1' },
      { key: 'Timestamp', value: this.toIsoUtc(Date.now()) },
      { key: 'SignatureVersion', value: '1.0' },
      { key: 'SignatureNonce', value: `${Date.now()}${Math.floor(Math.random() * 100000)}` },
      { key: 'SourceLanguage', value: this.toAlibabaLanguage(sourceLanguage) },
      { key: 'TargetLanguage', value: this.toAlibabaLanguage(targetLanguage) },
      { key: 'SourceText', value: text },
      { key: 'FormatType', value: 'text' },
      { key: 'Scene', value: provider.model.trim().length > 0 ? provider.model.trim() : 'general' }
    ];
    const canonicalizedQuery = this.buildAlibabaCanonicalQuery(params);
    const stringToSign = `POST&%2F&${this.percentEncode(canonicalizedQuery)}`;
    const signature = this.cryptoService.hmacSha1Base64(`${provider.secretKey.trim()}&`, stringToSign);
    return {
      url: endpoint,
      method: http.RequestMethod.POST,
      headers: this.formHeaders(),
      body: `${canonicalizedQuery}&Signature=${this.percentEncode(signature)}`,
      responseParser: (rawBody: string, sourceItems: WebpageTranslationTextItem[]) =>
        this.parseSingleTextResponse(rawBody, sourceItems, 'Alibaba', (parsed: Object): string => {
          const response = parsed as AlibabaTranslationResponse;
          return response.Data?.Translated ?? response.Data?.TranslatedText ?? '';
        })
    };
  }

  private buildVolcanoRequest(
    provider: TranslationProviderConfig,
    items: WebpageTranslationTextItem[],
    sourceLanguage: string,
    targetLanguage: string
  ): ProviderHttpRequest {
    const endpoint = provider.endpoint.trim().length > 0
      ? provider.endpoint.trim()
      : 'https://translate.volcengineapi.com';
    this.validateHttpsEndpoint(endpoint, '火山引擎机器翻译 endpoint 必须使用 HTTPS。');
    const region = provider.region.trim().length > 0 ? provider.region.trim() : 'cn-north-1';
    const payload = JSON.stringify({
      SourceLanguage: this.toVolcanoLanguage(sourceLanguage),
      TargetLanguage: this.toVolcanoLanguage(targetLanguage),
      TextList: items.map((item: WebpageTranslationTextItem): string => item.text)
    });
    const signed = this.buildVolcanoSignedRequest(provider, region, payload);
    return {
      url: `${endpoint}/?Action=TranslateText&Version=2020-06-01`,
      method: http.RequestMethod.POST,
      headers: signed,
      body: payload,
      responseParser: (rawBody: string, sourceItems: WebpageTranslationTextItem[]) =>
        this.parseVolcanoResponse(rawBody, sourceItems)
    };
  }

  private buildTencentHeaders(
    provider: TranslationProviderConfig,
    region: string,
    timestamp: number,
    payload: string,
    action: string = 'TextTranslate'
  ): Record<string, string> {
    const service = 'tmt';
    const host = 'tmt.tencentcloudapi.com';
    const date = this.toUtcDate(timestamp * 1000);
    const hashedPayload = this.cryptoService.sha256Hex(payload);
    const canonicalRequest = [
      'POST',
      '/',
      '',
      `content-type:application/json; charset=utf-8\nhost:${host}\nx-tc-action:${action.toLowerCase()}\n`,
      'content-type;host;x-tc-action',
      hashedPayload
    ].join('\n');
    const credentialScope = `${date}/${service}/tc3_request`;
    const stringToSign = [
      'TC3-HMAC-SHA256',
      `${timestamp}`,
      credentialScope,
      this.cryptoService.sha256Hex(canonicalRequest)
    ].join('\n');
    const secretDate = this.cryptoService.hmacSha256Bytes(this.cryptoService.utf8(`TC3${provider.secretKey.trim()}`), date);
    const secretService = this.cryptoService.hmacSha256Bytes(secretDate, service);
    const secretSigning = this.cryptoService.hmacSha256Bytes(secretService, 'tc3_request');
    const signature = this.cryptoService.toHex(this.cryptoService.hmacSha256Bytes(secretSigning, stringToSign));
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
      'User-Agent': AIRA_USER_AGENT,
      'Authorization': `TC3-HMAC-SHA256 Credential=${provider.appId.trim()}/${credentialScope}, SignedHeaders=content-type;host;x-tc-action, Signature=${signature}`,
      'Host': host,
      'X-TC-Action': action,
      'X-TC-Version': '2018-03-21',
      'X-TC-Region': region,
      'X-TC-Timestamp': `${timestamp}`
    };
  }

  private buildVolcanoSignedRequest(
    provider: TranslationProviderConfig,
    region: string,
    payload: string
  ): Record<string, string> {
    const service = 'translate';
    const host = 'translate.volcengineapi.com';
    const now = Date.now();
    const date = this.toUtcDate(now);
    const amzDate = this.toAmzDate(now);
    const canonicalQuery = 'Action=TranslateText&Version=2020-06-01';
    const hashedPayload = this.cryptoService.sha256Hex(payload);
    const canonicalRequest = [
      'POST',
      '/',
      canonicalQuery,
      `content-type:application/json\nhost:${host}\nx-content-sha256:${hashedPayload}\nx-date:${amzDate}\n`,
      'content-type;host;x-content-sha256;x-date',
      hashedPayload
    ].join('\n');
    const credentialScope = `${date}/${region}/${service}/request`;
    const stringToSign = [
      'HMAC-SHA256',
      amzDate,
      credentialScope,
      this.cryptoService.sha256Hex(canonicalRequest)
    ].join('\n');
    const kDate = this.cryptoService.hmacSha256Bytes(this.cryptoService.utf8(provider.secretKey.trim()), date);
    const kRegion = this.cryptoService.hmacSha256Bytes(kDate, region);
    const kService = this.cryptoService.hmacSha256Bytes(kRegion, service);
    const kSigning = this.cryptoService.hmacSha256Bytes(kService, 'request');
    const signature = this.cryptoService.toHex(this.cryptoService.hmacSha256Bytes(kSigning, stringToSign));
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': AIRA_USER_AGENT,
      'Host': host,
      'X-Date': amzDate,
      'X-Content-Sha256': hashedPayload,
      'Authorization': `HMAC-SHA256 Credential=${provider.appId.trim()}/${credentialScope}, SignedHeaders=content-type;host;x-content-sha256;x-date, Signature=${signature}`
    };
  }

  private jsonHeaders(): Record<string, string> {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
      'User-Agent': AIRA_USER_AGENT
    };
  }

  private formHeaders(): Record<string, string> {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
      'User-Agent': AIRA_USER_AGENT
    };
  }

  private parseGenericResponse(rawBody: string, sourceItems: WebpageTranslationTextItem[]): WebpageTranslationApplyItem[] {
    const parsed = this.parseJson<GenericTranslationResponseBody>(rawBody);
    const responseItems = this.resolveGenericResponseItems(parsed);
    if (responseItems.length === 0) {
      throw new TranslationProviderError(this.failureClassifier.buildFailure(
        'invalid_response',
        '翻译服务没有返回可用译文。'
      ));
    }
    return this.mapGenericTranslations(sourceItems, responseItems);
  }

  private parseDeepLResponse(rawBody: string, sourceItems: WebpageTranslationTextItem[]): WebpageTranslationApplyItem[] {
    const parsed = this.parseJson<DeepLTranslationResponse>(rawBody);
    return this.mapIndexedTranslations(
      sourceItems,
      (parsed.translations ?? []).map((item: DeepLTranslationItem): string => item.text ?? '')
    );
  }

  private parseGoogleResponse(rawBody: string, sourceItems: WebpageTranslationTextItem[]): WebpageTranslationApplyItem[] {
    const parsed = this.parseJson<GoogleTranslationResponse>(rawBody);
    return this.mapIndexedTranslations(
      sourceItems,
      (parsed.data?.translations ?? []).map((item: GoogleTranslationItem): string => item.translatedText ?? '')
    );
  }

  private buildProviderHttpFailureMessage(
    provider: TranslationProviderConfig,
    statusCode: number,
    rawBody: string
  ): string {
    if (rawBody.trim().length === 0) {
      return '';
    }
    const message = this.extractProviderErrorMessage(rawBody);
    if (message.length === 0) {
      return '';
    }
    const safeMessage = this.sanitizeProviderMessage(message, provider);
    if (provider.templateId === 'google_cloud') {
      return `Google Cloud Translation 返回错误：${safeMessage}`;
    }
    return `翻译服务返回错误 ${statusCode}：${safeMessage}`;
  }

  private extractProviderErrorMessage(rawBody: string): string {
    try {
      const parsed = JSON.parse(rawBody) as ProviderErrorResponse;
      const message = parsed.error?.message ?? parsed.message ?? parsed.error_description ?? '';
      return message.trim();
    } catch (_error) {
      return '';
    }
  }

  private sanitizeProviderMessage(message: string, provider: TranslationProviderConfig): string {
    let result = message;
    const secrets: string[] = [
      provider.apiKey.trim(),
      provider.secretKey.trim(),
      provider.appId.trim()
    ].filter((item: string) => item.length > 0);
    secrets.forEach((secret: string) => {
      result = result.split(secret).join('******');
    });
    return result;
  }

  private parseMicrosoftResponse(rawBody: string, sourceItems: WebpageTranslationTextItem[]): WebpageTranslationApplyItem[] {
    const parsed = this.parseJson<MicrosoftTranslationResponseItem[]>(rawBody);
    return this.mapIndexedTranslations(
      sourceItems,
      parsed.map((item: MicrosoftTranslationResponseItem): string => item.translations?.[0]?.text ?? '')
    );
  }

  private parseBaiduResponse(rawBody: string, sourceItems: WebpageTranslationTextItem[]): WebpageTranslationApplyItem[] {
    const parsed = this.parseJson<BaiduTranslationResponse>(rawBody);
    if (parsed.error_code !== undefined && parsed.error_code.length > 0) {
      throw new TranslationProviderError(this.failureClassifier.buildFailure(
        'invalid_response',
        `百度翻译返回错误：${parsed.error_msg ?? parsed.error_code}`
      ));
    }
    return this.splitJoinedTranslation(
      sourceItems,
      (parsed.trans_result ?? []).map((item: BaiduTranslationItem): string => item.dst ?? '').join('\n')
    );
  }

  private parseYoudaoResponse(rawBody: string, sourceItems: WebpageTranslationTextItem[]): WebpageTranslationApplyItem[] {
    const parsed = this.parseJson<YoudaoTranslationResponse>(rawBody);
    if (parsed.errorCode !== undefined && parsed.errorCode !== '0') {
      throw new TranslationProviderError(this.failureClassifier.buildFailure(
        'invalid_response',
        `有道智云返回错误：${parsed.errorCode}`
      ));
    }
    const text = (parsed.translation ?? []).join('\n');
    if (text.length > 0) {
      return this.splitJoinedTranslation(sourceItems, text);
    }
    return this.mapIndexedTranslations(
      sourceItems,
      (parsed.web ?? []).map((item: YoudaoWebTranslationItem): string => item.tgt ?? '')
    );
  }

  private parseVolcanoResponse(rawBody: string, sourceItems: WebpageTranslationTextItem[]): WebpageTranslationApplyItem[] {
    const parsed = this.parseJson<VolcanoTranslationResponse>(rawBody);
    const list = parsed.TranslationList ?? parsed.Response?.TranslationList ?? [];
    return this.mapIndexedTranslations(
      sourceItems,
      list.map((item: VolcanoTranslationItem): string => item.Translation ?? item.translation ?? '')
    );
  }

  private parseTencentBatchResponse(rawBody: string, sourceItems: WebpageTranslationTextItem[]): WebpageTranslationApplyItem[] {
    const parsed = this.parseJson<TencentTranslationResponse>(rawBody);
    const targetTextList = parsed.Response?.TargetTextList;
    if (Array.isArray(targetTextList)) {
      return this.mapIndexedTranslations(sourceItems, targetTextList);
    }
    const fallbackText = parsed.Response?.TargetText ?? '';
    if (fallbackText.trim().length > 0) {
      return this.splitJoinedTranslation(sourceItems, fallbackText);
    }
    throw new TranslationProviderError(this.failureClassifier.buildFailure(
      'invalid_response',
      'Tencent 没有返回可用译文。'
    ));
  }

  private parseSingleTextResponse(
    rawBody: string,
    sourceItems: WebpageTranslationTextItem[],
    providerName: string,
    extractor: (parsed: Object) => string
  ): WebpageTranslationApplyItem[] {
    const parsed = this.parseJson<Object>(rawBody);
    const text = extractor(parsed);
    if (text.trim().length === 0) {
      throw new TranslationProviderError(this.failureClassifier.buildFailure(
        'invalid_response',
        `${providerName} 没有返回可用译文。`
      ));
    }
    return this.splitJoinedTranslation(sourceItems, text);
  }

  private parseJson<T>(rawBody: string): T {
    try {
      return JSON.parse(rawBody) as T;
    } catch (_error) {
      throw new TranslationProviderError(this.failureClassifier.buildFailure(
        'invalid_response',
        '翻译服务返回的 JSON 无法解析。'
      ));
    }
  }

  private resolveGenericResponseItems(parsed: GenericTranslationResponseBody): GenericTranslationResponseItem[] {
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
      return this.resolveGenericResponseItems(parsed.data);
    }
    return [];
  }

  private mapIndexedTranslations(
    sourceItems: WebpageTranslationTextItem[],
    translations: string[]
  ): WebpageTranslationApplyItem[] {
    const results: WebpageTranslationApplyItem[] = [];
    translations.forEach((text: string, index: number) => {
      const translatedText = text.trim();
      const id = sourceItems[index]?.id ?? '';
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
        '翻译服务返回的译文为空。'
      ));
    }
    return results;
  }

  private mapGenericTranslations(
    sourceItems: WebpageTranslationTextItem[],
    responseItems: GenericTranslationResponseItem[]
  ): WebpageTranslationApplyItem[] {
    const results: WebpageTranslationApplyItem[] = [];
    responseItems.forEach((item: GenericTranslationResponseItem, index: number) => {
      const translatedText = (item.translatedText ?? item.translation ?? item.text ?? '').trim();
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
        '翻译服务返回的译文为空。'
      ));
    }
    return results;
  }

  private splitJoinedTranslation(
    sourceItems: WebpageTranslationTextItem[],
    translatedText: string
  ): WebpageTranslationApplyItem[] {
    const parts = translatedText.split('\n').map((item: string): string => item.trim()).filter((item: string) => item.length > 0);
    if (parts.length === sourceItems.length) {
      return this.mapIndexedTranslations(sourceItems, parts);
    }
    if (sourceItems.length === 1) {
      return this.mapIndexedTranslations(sourceItems, [translatedText]);
    }
    throw new TranslationProviderError(this.failureClassifier.buildFailure(
      'invalid_response',
      '翻译服务返回的译文数量与原文不一致。'
    ));
  }

  private joinTexts(items: WebpageTranslationTextItem[]): string {
    return items.map((item: WebpageTranslationTextItem): string => item.text).join('\n');
  }

  private formEncode(params: ProviderQueryParam[]): string {
    return params.map((item: ProviderQueryParam): string => {
      return `${encodeURIComponent(item.key)}=${encodeURIComponent(item.value)}`;
    }).join('&');
  }

  private buildAlibabaCanonicalQuery(params: ProviderQueryParam[]): string {
    return params
      .slice()
      .sort((left: ProviderQueryParam, right: ProviderQueryParam): number => left.key.localeCompare(right.key))
      .map((item: ProviderQueryParam): string => `${this.percentEncode(item.key)}=${this.percentEncode(item.value)}`)
      .join('&');
  }

  private percentEncode(value: string): string {
    return encodeURIComponent(value)
      .replace(/\+/g, '%20')
      .replace(/\*/g, '%2A')
      .replace(/%7E/g, '~');
  }

  private truncateYoudaoInput(text: string): string {
    if (text.length <= 20) {
      return text;
    }
    return `${text.substring(0, 10)}${text.length}${text.substring(text.length - 10)}`;
  }

  private toUtcDate(timestampMs: number): string {
    const date = new Date(timestampMs);
    const year = date.getUTCFullYear().toString().padStart(4, '0');
    const month = (date.getUTCMonth() + 1).toString().padStart(2, '0');
    const day = date.getUTCDate().toString().padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  private toIsoUtc(timestampMs: number): string {
    return new Date(timestampMs).toISOString().replace(/\.\d{3}Z$/, 'Z');
  }

  private toAmzDate(timestampMs: number): string {
    const iso = new Date(timestampMs).toISOString();
    return `${iso.substring(0, 4)}${iso.substring(5, 7)}${iso.substring(8, 10)}T${iso.substring(11, 13)}${iso.substring(14, 16)}${iso.substring(17, 19)}Z`;
  }

  private toDeepLLanguage(languageCode: string): string {
    switch (languageCode) {
      case 'zh-CN':
      case 'zh-TW':
        return 'ZH';
      case 'en':
        return 'EN';
      default:
        return languageCode.toUpperCase();
    }
  }

  private toGoogleLanguage(languageCode: string): string {
    return this.normalizeCommonLanguage(languageCode);
  }

  private toMicrosoftLanguage(languageCode: string): string {
    return this.normalizeCommonLanguage(languageCode);
  }

  private toBaiduLanguage(languageCode: string): string {
    switch (languageCode) {
      case 'zh-CN':
        return 'zh';
      case 'zh-TW':
        return 'cht';
      case 'en':
        return 'en';
      case 'ja':
        return 'jp';
      case 'ko':
        return 'kor';
      case 'fr':
        return 'fra';
      case 'es':
        return 'spa';
      case 'pt':
        return 'pt';
      case 'ru':
        return 'ru';
      default:
        return 'auto';
    }
  }

  private toYoudaoLanguage(languageCode: string): string {
    switch (languageCode) {
      case 'zh-CN':
        return 'zh-CHS';
      case 'zh-TW':
        return 'zh-CHT';
      case 'ja':
        return 'ja';
      case 'ko':
        return 'ko';
      default:
        return this.normalizeCommonLanguage(languageCode);
    }
  }

  private toTencentLanguage(languageCode: string): string {
    switch (languageCode) {
      case 'zh-CN':
      case 'zh-TW':
        return 'zh';
      case 'ja':
        return 'jp';
      case 'ko':
        return 'kr';
      default:
        return this.normalizeCommonLanguage(languageCode);
    }
  }

  private toAlibabaLanguage(languageCode: string): string {
    switch (languageCode) {
      case 'zh-CN':
      case 'zh-TW':
        return 'zh';
      case 'ja':
        return 'ja';
      case 'ko':
        return 'ko';
      default:
        return this.normalizeCommonLanguage(languageCode);
    }
  }

  private toVolcanoLanguage(languageCode: string): string {
    switch (languageCode) {
      case 'zh-CN':
      case 'zh-TW':
        return 'zh';
      case 'ja':
        return 'ja';
      case 'ko':
        return 'ko';
      default:
        return this.normalizeCommonLanguage(languageCode);
    }
  }

  private normalizeCommonLanguage(languageCode: string): string {
    switch (languageCode) {
      case 'zh-CN':
        return 'zh-CN';
      case 'zh-TW':
        return 'zh-TW';
      default:
        return languageCode.trim().length > 0 ? languageCode.trim() : 'auto';
    }
  }
}
