const RECEIVER_NEUTRAL_REQUEST_HEADERS: string[] = [
  'accept',
  'accept-charset',
  'accept-encoding',
  'accept-language',
  'cache-control',
  'connection',
  'content-length',
  'content-type',
  'dnt',
  'host',
  'if-match',
  'if-modified-since',
  'if-none-match',
  'if-range',
  'if-unmodified-since',
  'keep-alive',
  'origin',
  'pragma',
  'priority',
  'range',
  'referer',
  'te',
  'upgrade-insecure-requests',
  'user-agent',
  'via'
];

const RECEIVER_NEUTRAL_REQUEST_HEADER_PREFIXES: string[] = [
  'sec-ch-ua',
  'sec-fetch-'
];

const CREDENTIAL_REQUEST_HEADERS: string[] = [
  'authorization',
  'cookie',
  'proxy-authorization'
];

export type MediaCastRequestContextReason =
  'none' |
  'credential_header' |
  'custom_header';

export interface MediaCastRequestContextAssessment {
  requiresWebRequestContext: boolean;
  reason: MediaCastRequestContextReason;
  requestHeaderCount: number;
  incompatibleHeaderCount: number;
}

export class MediaCastRequestContextPolicy {
  assess(requestHeaders: Record<string, string> | undefined): MediaCastRequestContextAssessment {
    if (requestHeaders === undefined) {
      return this.buildAssessment(false, 'none', 0, 0);
    }
    const keys = Object.keys(requestHeaders);
    let requestHeaderCount = 0;
    let incompatibleHeaderCount = 0;
    let reason: MediaCastRequestContextReason = 'none';
    for (let i: number = 0; i < keys.length; i += 1) {
      const key = keys[i];
      const name = key.trim().toLowerCase();
      const value = requestHeaders[key]?.trim() ?? '';
      if (name.length <= 0 || value.length <= 0) {
        continue;
      }
      requestHeaderCount += 1;
      if (this.isReceiverNeutralHeader(name)) {
        continue;
      }
      incompatibleHeaderCount += 1;
      if (this.isCredentialHeader(name)) {
        reason = 'credential_header';
      } else if (reason === 'none') {
        reason = 'custom_header';
      }
    }
    return this.buildAssessment(
      incompatibleHeaderCount > 0,
      reason,
      requestHeaderCount,
      incompatibleHeaderCount
    );
  }

  private isReceiverNeutralHeader(name: string): boolean {
    if (RECEIVER_NEUTRAL_REQUEST_HEADERS.indexOf(name) >= 0) {
      return true;
    }
    for (let i: number = 0; i < RECEIVER_NEUTRAL_REQUEST_HEADER_PREFIXES.length; i += 1) {
      if (name.startsWith(RECEIVER_NEUTRAL_REQUEST_HEADER_PREFIXES[i])) {
        return true;
      }
    }
    return false;
  }

  private isCredentialHeader(name: string): boolean {
    if (CREDENTIAL_REQUEST_HEADERS.indexOf(name) >= 0) {
      return true;
    }
    return name.indexOf('token') >= 0 || name.indexOf('api-key') >= 0 || name.indexOf('apikey') >= 0;
  }

  private buildAssessment(
    requiresWebRequestContext: boolean,
    reason: MediaCastRequestContextReason,
    requestHeaderCount: number,
    incompatibleHeaderCount: number
  ): MediaCastRequestContextAssessment {
    return {
      requiresWebRequestContext: requiresWebRequestContext,
      reason: reason,
      requestHeaderCount: requestHeaderCount,
      incompatibleHeaderCount: incompatibleHeaderCount
    };
  }
}
