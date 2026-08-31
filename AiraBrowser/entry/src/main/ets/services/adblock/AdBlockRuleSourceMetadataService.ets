import { AdBlockCustomRuleSource } from '../../common/models/BrowserModels';

export class AdBlockRuleSourceMetadataService {
  buildSource(url: string, title: string, existing?: AdBlockCustomRuleSource): AdBlockCustomRuleSource {
    const now = Date.now();
    return {
      id: existing?.id ?? this.buildSourceId(url),
      payloadIdentity: '',
      title: title.trim().length > 0 ? title.trim() : this.buildTitle(url),
      url: url.trim(),
      sourceType: existing?.sourceType ?? 'remote',
      enabled: existing?.enabled ?? true,
      nativeNetworkRuleCount: 0,
      nativeCosmeticRuleCount: 0,
      ruleCount: 0,
      lastUpdatedAt: now,
      lastError: '',
      createdAt: existing?.createdAt ?? now,
      updatedAt: now
    };
  }

  buildLocalSource(url: string, title: string, existing?: AdBlockCustomRuleSource): AdBlockCustomRuleSource {
    const source = this.buildSource(url, title, existing);
    source.sourceType = 'local';
    return source;
  }

  buildFailedSource(
    url: string,
    title: string,
    message: string,
    existing?: AdBlockCustomRuleSource
  ): AdBlockCustomRuleSource {
    const now = Date.now();
    return {
      id: existing?.id ?? this.buildSourceId(url),
      payloadIdentity: existing?.payloadIdentity ?? '',
      title: title.trim().length > 0 ? title.trim() : (existing?.title ?? this.buildTitle(url)),
      url: url.trim(),
      sourceType: existing?.sourceType ?? 'remote',
      enabled: existing?.enabled ?? false,
      nativeNetworkRuleCount: existing?.nativeNetworkRuleCount,
      nativeCosmeticRuleCount: existing?.nativeCosmeticRuleCount,
      ruleCount: existing?.ruleCount ?? 0,
      lastUpdatedAt: existing?.lastUpdatedAt ?? 0,
      lastError: message.trim(),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now
    };
  }

  normalizeSubscriptionUrl(url: string): string {
    const trimmed = url.trim();
    if (!trimmed.startsWith('https://github.com/')) {
      return trimmed;
    }
    const parts = trimmed.substring('https://github.com/'.length).split('/');
    if (parts.length >= 5 && (parts[2] === 'blob' || parts[2] === 'raw')) {
      return `https://raw.githubusercontent.com/${parts[0]}/${parts[1]}/${parts[3]}/${parts.slice(4).join('/')}`;
    }
    return trimmed;
  }

  buildTitle(url: string): string {
    const value = this.normalizeSubscriptionUrl(url);
    const lastSlash = value.lastIndexOf('/');
    return lastSlash >= 0 && lastSlash < value.length - 1 ? value.substring(lastSlash + 1) : '自定义规则';
  }

  private buildSourceId(url: string): string {
    let hash = 0;
    for (let index = 0; index < url.length; index += 1) {
      hash = ((hash * 31) + url.charCodeAt(index)) >>> 0;
    }
    return `custom-${hash}`;
  }
}
