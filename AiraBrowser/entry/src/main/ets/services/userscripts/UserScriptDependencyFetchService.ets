import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import {
  UserScriptMaterializedDependencies,
  UserScriptPackageCandidate,
  UserScriptResourceDeclaration,
  UserScriptResourceRecord
} from '../../features/userscripts/UserScriptMetadataModels';
import {
  UserScriptSourceFetchResult,
  UserScriptSourceFetchService
} from './UserScriptSourceFetchService';

const MAX_REQUIRE_COUNT: number = 24;
const MAX_RESOURCE_COUNT: number = 24;
const MAX_RESOURCE_BYTES: number = 5 * 1024 * 1024;
const MAX_REQUIRE_SOURCE_LENGTH: number = 5 * 1024 * 1024;
const RESOURCE_FETCH_TIMEOUT_MS: number = 12000;

interface UserScriptResourceFetchResult {
  ok: boolean;
  text: string;
  contentBase64: string;
  mimeType: string;
}

export interface UserScriptDependencyFetchResult {
  dependencies: UserScriptMaterializedDependencies;
  warnings: string[];
}

export interface UserScriptBackupDependencyValidationResult {
  valid: boolean;
  dependencies: UserScriptMaterializedDependencies;
  errorMessage: string;
}

export class UserScriptDependencyFetchService {
  private sourceFetchService: UserScriptSourceFetchService;
  private base64Helper: util.Base64Helper = new util.Base64Helper();
  private textDecoder: util.TextDecoder = util.TextDecoder.create('utf-8');

  constructor(sourceFetchService: UserScriptSourceFetchService = new UserScriptSourceFetchService()) {
    this.sourceFetchService = sourceFetchService;
  }

  async materialize(candidate: UserScriptPackageCandidate): Promise<UserScriptDependencyFetchResult> {
    const warnings: string[] = [];
    const requireSources = await this.fetchRequires(candidate.requireUrls, warnings);
    const resources = await this.fetchResources(candidate.resourceDeclarations, warnings);
    return {
      dependencies: {
        requireSources: requireSources,
        resources: resources
      },
      warnings: warnings
    };
  }

  validateBackupDependencies(
    candidate: UserScriptPackageCandidate,
    dependencies: UserScriptMaterializedDependencies
  ): UserScriptBackupDependencyValidationResult {
    const expectedRequireCount = candidate.requireUrls
      .slice(0, MAX_REQUIRE_COUNT)
      .filter((url: string): boolean => this.isHttpUrl(url)).length;
    if (dependencies.requireSources.length !== expectedRequireCount ||
      dependencies.requireSources.some((source: string): boolean => {
        return source.trim().length <= 0 || source.length > MAX_REQUIRE_SOURCE_LENGTH;
      })) {
      return this.failedBackupValidation('备份中的 @require 内容无法与脚本声明可靠对应。');
    }
    if (!this.resourcesMatchDeclarations(candidate.resourceDeclarations, dependencies.resources)) {
      return this.failedBackupValidation('备份中的 @resource 内容与脚本声明不一致。');
    }
    return {
      valid: true,
      dependencies: {
        requireSources: dependencies.requireSources.slice(),
        resources: dependencies.resources.map(
          (resource: UserScriptResourceRecord): UserScriptResourceRecord => this.cloneResource(resource)
        )
      },
      errorMessage: ''
    };
  }

  private async fetchRequires(urls: string[], warnings: string[]): Promise<string[]> {
    const results: string[] = [];
    for (let index = 0; index < urls.length && index < MAX_REQUIRE_COUNT; index++) {
      const url = urls[index].trim();
      if (!this.isHttpUrl(url)) {
        warnings.push(`忽略不支持的 @require：${url}`);
        continue;
      }
      const result: UserScriptSourceFetchResult = await this.sourceFetchService.fetchSource(url, true);
      if (!result.ok) {
        warnings.push(`@require 下载失败：${url}`);
        continue;
      }
      results.push(result.source);
    }
    if (urls.length > MAX_REQUIRE_COUNT) {
      warnings.push(`@require 超过 ${MAX_REQUIRE_COUNT} 个，已忽略后续依赖。`);
    }
    return results;
  }

  private async fetchResources(
    resources: UserScriptResourceDeclaration[],
    warnings: string[]
  ): Promise<UserScriptResourceRecord[]> {
    const results: UserScriptResourceRecord[] = [];
    for (let index = 0; index < resources.length && index < MAX_RESOURCE_COUNT; index++) {
      const resource = resources[index];
      const url = resource.url.trim();
      if (!this.isHttpUrl(url)) {
        warnings.push(`忽略不支持的 @resource：${resource.name}`);
        continue;
      }
      const result: UserScriptResourceFetchResult = await this.fetchResource(url);
      if (!result.ok) {
        warnings.push(`@resource 下载失败：${resource.name}`);
        continue;
      }
      results.push({
        name: resource.name,
        url: resource.url,
        text: result.text,
        mimeType: result.mimeType,
        contentBase64: result.contentBase64
      });
    }
    if (resources.length > MAX_RESOURCE_COUNT) {
      warnings.push(`@resource 超过 ${MAX_RESOURCE_COUNT} 个，已忽略后续资源。`);
    }
    return results;
  }

  private async fetchResource(url: string): Promise<UserScriptResourceFetchResult> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: RESOURCE_FETCH_TIMEOUT_MS,
        readTimeout: RESOURCE_FETCH_TIMEOUT_MS,
        maxLimit: MAX_RESOURCE_BYTES,
        usingCache: true,
        header: {
          'Accept': '*/*',
          'User-Agent': 'AiraBrowser/1.0'
        }
      });
      if (response.responseCode < 200 || response.responseCode >= 300 ||
        !(response.result instanceof ArrayBuffer) || response.result.byteLength > MAX_RESOURCE_BYTES) {
        return this.failedResource();
      }
      const bytes = new Uint8Array(response.result);
      const mimeType = this.resolveMimeType(url, this.readContentType(response.header));
      return {
        ok: true,
        text: this.isTextMimeType(mimeType) ? this.textDecoder.decodeToString(bytes) : '',
        contentBase64: this.base64Helper.encodeToStringSync(bytes),
        mimeType: mimeType
      };
    } catch (_error) {
      return this.failedResource();
    } finally {
      request.destroy();
    }
  }

  private failedResource(): UserScriptResourceFetchResult {
    return {
      ok: false,
      text: '',
      contentBase64: '',
      mimeType: 'application/octet-stream'
    };
  }

  private resolveMimeType(url: string, responseContentType: string): string {
    const normalized = url.toLowerCase().split('?')[0].split('#')[0];
    if (normalized.endsWith('.css')) {
      return 'text/css';
    }
    if (normalized.endsWith('.json')) {
      return 'application/json';
    }
    if (normalized.endsWith('.svg')) {
      return 'image/svg+xml';
    }
    if (normalized.endsWith('.js') || normalized.endsWith('.mjs')) {
      return 'application/javascript';
    }
    if (normalized.endsWith('.html') || normalized.endsWith('.htm')) {
      return 'text/html';
    }
    if (normalized.endsWith('.xml')) {
      return 'application/xml';
    }
    if (normalized.endsWith('.woff2')) {
      return 'font/woff2';
    }
    if (normalized.endsWith('.woff')) {
      return 'font/woff';
    }
    if (normalized.endsWith('.ttf')) {
      return 'font/ttf';
    }
    if (normalized.endsWith('.otf')) {
      return 'font/otf';
    }
    if (normalized.endsWith('.png')) {
      return 'image/png';
    }
    if (normalized.endsWith('.jpg') || normalized.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (normalized.endsWith('.gif')) {
      return 'image/gif';
    }
    if (normalized.endsWith('.webp')) {
      return 'image/webp';
    }
    if (normalized.endsWith('.txt')) {
      return 'text/plain';
    }
    const normalizedContentType = responseContentType.trim().toLowerCase().split(';')[0].trim();
    return this.isValidMimeType(normalizedContentType) ? normalizedContentType : 'application/octet-stream';
  }

  private readContentType(headers: Object): string {
    const headerRecord = headers as Record<string, Object>;
    const keys = Object.keys(headers);
    for (let index = 0; index < keys.length; index += 1) {
      const key = keys[index];
      if (key.toLowerCase() === 'content-type') {
        const value = headerRecord[key];
        return typeof value === 'string' ? value : '';
      }
    }
    return '';
  }

  private isTextMimeType(mimeType: string): boolean {
    const normalized = mimeType.toLowerCase();
    return normalized.startsWith('text/') ||
      normalized === 'application/json' ||
      normalized === 'application/javascript' ||
      normalized === 'application/xml' ||
      normalized === 'image/svg+xml';
  }

  private isValidMimeType(value: string): boolean {
    return /^[a-z0-9][a-z0-9!#$&^_.+-]*\/[a-z0-9][a-z0-9!#$&^_.+-]*$/.test(value);
  }

  private resourcesMatchDeclarations(
    declarations: UserScriptResourceDeclaration[],
    resources: UserScriptResourceRecord[]
  ): boolean {
    const available = declarations.slice(0, MAX_RESOURCE_COUNT)
      .filter((declaration: UserScriptResourceDeclaration): boolean => this.isHttpUrl(declaration.url))
      .map((declaration: UserScriptResourceDeclaration): UserScriptResourceDeclaration => {
        return { name: declaration.name, url: declaration.url };
      });
    if (resources.length !== available.length) {
      return false;
    }
    for (let index = 0; index < resources.length; index += 1) {
      const resource = resources[index];
      const declarationIndex = available.findIndex(
        (declaration: UserScriptResourceDeclaration): boolean => {
          return declaration.name === resource.name && declaration.url === resource.url;
        }
      );
      if (declarationIndex < 0 || !this.isValidMimeType(resource.mimeType.trim().toLowerCase())) {
        return false;
      }
      available.splice(declarationIndex, 1);
    }
    return true;
  }

  private cloneResource(resource: UserScriptResourceRecord): UserScriptResourceRecord {
    return {
      name: resource.name,
      url: resource.url,
      text: resource.text,
      mimeType: resource.mimeType,
      contentBase64: resource.contentBase64
    };
  }

  private failedBackupValidation(errorMessage: string): UserScriptBackupDependencyValidationResult {
    return {
      valid: false,
      dependencies: {
        requireSources: [],
        resources: []
      },
      errorMessage: errorMessage
    };
  }

  private isHttpUrl(url: string): boolean {
    const normalized = url.trim().toLowerCase();
    return normalized.startsWith('http://') || normalized.startsWith('https://');
  }
}
