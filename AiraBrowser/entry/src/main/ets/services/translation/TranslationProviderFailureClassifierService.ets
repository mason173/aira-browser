export type TranslationProviderFailureType =
  'missing_provider' |
  'missing_disclosure' |
  'local_engine_unavailable' |
  'invalid_endpoint' |
  'invalid_response' |
  'network_unavailable' |
  'request_canceled' |
  'quota_or_rate_limit' |
  'server_error' |
  'unknown';

export interface TranslationProviderFailure {
  type: TranslationProviderFailureType;
  message: string;
  statusCode: number;
}

export class TranslationProviderError extends Error {
  failure: TranslationProviderFailure;

  constructor(failure: TranslationProviderFailure) {
    super(failure.message);
    this.failure = failure;
  }
}

export class TranslationProviderFailureClassifierService {
  buildFailure(type: TranslationProviderFailureType, message: string, statusCode: number = 0): TranslationProviderFailure {
    return {
      type: type,
      message: message,
      statusCode: statusCode
    };
  }

  classifyHttpStatus(statusCode: number): TranslationProviderFailure {
    return this.classifyHttpStatusWithMessage(statusCode, '');
  }

  classifyHttpStatusWithMessage(statusCode: number, message: string): TranslationProviderFailure {
    const normalizedMessage = message.trim();
    const lowerMessage = message.toLowerCase();
    if (this.isQuotaOrRateLimit(statusCode, lowerMessage)) {
      return this.buildFailure('quota_or_rate_limit', this.resolveQuotaMessage(message), statusCode);
    }
    if (statusCode === 401 || statusCode === 403) {
      return this.buildFailure(
        'missing_provider',
        normalizedMessage.length > 0 ? normalizedMessage : '翻译服务认证失败，请检查服务配置。',
        statusCode
      );
    }
    if (statusCode >= 500) {
      return this.buildFailure(
        'server_error',
        normalizedMessage.length > 0 ? normalizedMessage : '翻译服务暂时不可用。',
        statusCode
      );
    }
    return this.buildFailure(
      'server_error',
      normalizedMessage.length > 0 ? normalizedMessage : `翻译服务返回异常状态：${statusCode}`,
      statusCode
    );
  }

  classifyError(error: Error | Object): TranslationProviderFailure {
    const message = this.stringifyError(error);
    const lowerMessage = message.toLowerCase();
    if (lowerMessage.indexOf('canceled') >= 0 || lowerMessage.indexOf('destroy') >= 0) {
      return this.buildFailure('request_canceled', '已取消翻译请求。');
    }
    if (lowerMessage.indexOf('timeout') >= 0 || lowerMessage.indexOf('network') >= 0) {
      return this.buildFailure('network_unavailable', '网络连接异常，无法完成翻译。');
    }
    if (this.isQuotaOrRateLimit(0, lowerMessage)) {
      return this.buildFailure('quota_or_rate_limit', this.resolveQuotaMessage(message));
    }
    return this.buildFailure('unknown', message.length > 0 ? message : '网页翻译失败。');
  }

  private isQuotaOrRateLimit(statusCode: number, lowerMessage: string): boolean {
    if (statusCode === 402 || statusCode === 429) {
      return true;
    }
    return lowerMessage.indexOf('quota') >= 0 ||
      lowerMessage.indexOf('rate limit') >= 0 ||
      lowerMessage.indexOf('rate-limit') >= 0 ||
      lowerMessage.indexOf('too many request') >= 0 ||
      lowerMessage.indexOf('exceed') >= 0 ||
      lowerMessage.indexOf('exceeded') >= 0 ||
      lowerMessage.indexOf('limit exceeded') >= 0 ||
      lowerMessage.indexOf('insufficient quota') >= 0 ||
      lowerMessage.indexOf('token limit') >= 0 ||
      lowerMessage.indexOf('tokens limit') >= 0;
  }

  private resolveQuotaMessage(message: string): string {
    const normalizedMessage = message.trim();
    return normalizedMessage.length > 0 ? normalizedMessage : '翻译服务额度或频率受限，稍后再试。';
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
}
