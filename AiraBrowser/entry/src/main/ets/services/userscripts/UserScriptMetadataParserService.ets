import {
  UserScriptGrant,
  UserScriptPackageSource,
  UserScriptMetadataParseResult,
  UserScriptPackageCandidate,
  UserScriptResourceDeclaration,
  UserScriptRunAt
} from '../../features/userscripts/UserScriptMetadataModels';
import { UserScriptCapabilityContractService } from './UserScriptCapabilityContractService';
import { UserScriptIconService } from './UserScriptIconService';

interface UserScriptMetadataFields {
  names: string[];
  localizedNames: string[];
  namespaces: string[];
  versions: string[];
  descriptions: string[];
  icons: string[];
  matches: string[];
  includes: string[];
  excludeMatches: string[];
  excludes: string[];
  grants: string[];
  requires: string[];
  resources: UserScriptMetadataResourceField[];
  connects: string[];
  noframes: boolean;
  runAts: string[];
  updateUrls: string[];
  downloadUrls: string[];
  warnings: string[];
}

interface UserScriptMetadataResourceField {
  name: string;
  url: string;
}

const USER_SCRIPT_BEGIN_MARKER = '// ==UserScript==';
const USER_SCRIPT_END_MARKER = '// ==/UserScript==';
const MAX_USER_SCRIPT_SOURCE_LENGTH = 5 * 1024 * 1024;

export class UserScriptMetadataParserService {
  private capabilityContract: UserScriptCapabilityContractService = new UserScriptCapabilityContractService();
  private iconService: UserScriptIconService = new UserScriptIconService();

  parse(
    source: string,
    installSource: UserScriptPackageSource = 'paste',
    sourceUrl: string = ''
  ): UserScriptMetadataParseResult {
    const normalizedSource = source.trim();
    if (normalizedSource.length === 0) {
      return this.fail('脚本内容不能为空。');
    }
    if (normalizedSource.length > MAX_USER_SCRIPT_SOURCE_LENGTH) {
      return this.fail('脚本超过 5 MB，暂不支持安装。');
    }
    const header = this.extractHeader(normalizedSource);
    if (header.length === 0) {
      return this.fail('未找到 userscript 元数据头。');
    }
    const fields = this.parseHeaderFields(header);
    const primaryName = this.firstNonEmpty(fields.names);
    const name = primaryName.length > 0 ? primaryName : this.firstNonEmpty(fields.localizedNames);
    if (name.length === 0) {
      return this.fail('脚本缺少 @name。', fields.warnings);
    }
    if (primaryName.length === 0) {
      fields.warnings.push('脚本缺少基础 @name，已使用本地化名称。');
    }
    const matches = this.normalizeStringList(fields.matches);
    const includes = this.normalizeStringList(fields.includes);
    const excludeMatches = this.normalizeStringList(fields.excludeMatches);
    const excludes = this.normalizeStringList(fields.excludes);
    if (matches.length === 0 && includes.length === 0) {
      return this.fail('脚本缺少 @match 或 @include，无法确定运行站点。', fields.warnings);
    }
    const candidate: UserScriptPackageCandidate = {
      name: name,
      namespace: this.firstNonEmpty(fields.namespaces),
      version: this.firstNonEmpty(fields.versions) || '0.0.0',
      description: this.firstNonEmpty(fields.descriptions),
      iconUrl: this.iconService.resolveIconUrl(this.firstNonEmpty(fields.icons), sourceUrl),
      source: normalizedSource,
      sourceUrl: sourceUrl.trim(),
      updateUrl: this.firstNonEmpty(fields.updateUrls),
      downloadUrl: this.firstNonEmpty(fields.downloadUrls),
      matches: matches,
      includes: includes,
      excludeMatches: excludeMatches,
      excludes: excludes,
      grants: this.normalizeGrants(fields.grants, fields.warnings),
      requireUrls: this.normalizeStringList(fields.requires),
      resourceDeclarations: fields.resources.map(
        (resource: UserScriptMetadataResourceField): UserScriptResourceDeclaration => {
          const declaration: UserScriptResourceDeclaration = {
            name: resource.name,
            url: resource.url
          };
          return declaration;
        }
      ),
      connectRules: this.normalizeStringList(fields.connects),
      noframes: fields.noframes,
      runAt: this.normalizeRunAt(this.firstNonEmpty(fields.runAts), fields.warnings),
      installSource: installSource
    };
    return {
      valid: true,
      candidate: candidate,
      warnings: fields.warnings,
      errorMessage: ''
    };
  }

  private extractHeader(source: string): string {
    const start = source.indexOf(USER_SCRIPT_BEGIN_MARKER);
    const end = source.indexOf(USER_SCRIPT_END_MARKER);
    if (start < 0 || end <= start) {
      return '';
    }
    return source.slice(start, end + USER_SCRIPT_END_MARKER.length);
  }

  private parseHeaderFields(header: string): UserScriptMetadataFields {
    const fields: UserScriptMetadataFields = {
      names: [],
      localizedNames: [],
      namespaces: [],
      versions: [],
      descriptions: [],
      icons: [],
      matches: [],
      includes: [],
      excludeMatches: [],
      excludes: [],
      grants: [],
      requires: [],
      resources: [],
      connects: [],
      noframes: false,
      runAts: [],
      updateUrls: [],
      downloadUrls: [],
      warnings: []
    };
    header.split('\n').forEach((line: string) => {
      const trimmed = line.trim();
      if (!trimmed.startsWith('// @')) {
        return;
      }
      const withoutPrefix = trimmed.slice(4).trim();
      const separator = withoutPrefix.search(/\s/);
      const key = separator < 0 ? withoutPrefix : withoutPrefix.slice(0, separator).trim();
      const value = separator < 0 ? '' : withoutPrefix.slice(separator + 1).trim();
      this.appendField(fields, key, value);
    });
    return fields;
  }

  private appendField(fields: UserScriptMetadataFields, key: string, value: string): void {
    switch (key) {
      case 'name':
      case 'name:':
        fields.names.push(value);
        return;
      case 'namespace':
        fields.namespaces.push(value);
        return;
      case 'version':
        fields.versions.push(value);
        return;
      case 'description':
        fields.descriptions.push(value);
        return;
      case 'icon':
      case 'iconURL':
      case 'iconUrl':
      case 'defaulticon':
        fields.icons.push(value);
        return;
      case 'match':
        fields.matches.push(value);
        return;
      case 'include':
        fields.includes.push(value);
        return;
      case 'exclude-match':
        fields.excludeMatches.push(value);
        return;
      case 'exclude':
        fields.excludes.push(value);
        return;
      case 'grant':
        fields.grants.push(value);
        return;
      case 'require':
        fields.requires.push(value);
        return;
      case 'resource':
        this.appendResourceField(fields, value);
        return;
      case 'connect':
        fields.connects.push(value);
        return;
      case 'run-at':
        fields.runAts.push(value);
        return;
      case 'updateURL':
        fields.updateUrls.push(value);
        return;
      case 'downloadURL':
        fields.downloadUrls.push(value);
        return;
      case 'noframes':
        fields.noframes = true;
        return;
      default:
        if (key.startsWith('name:')) {
          fields.localizedNames.push(value);
        }
        return;
    }
  }

  private appendResourceField(fields: UserScriptMetadataFields, value: string): void {
    const trimmed = value.trim();
    const separator = trimmed.search(/\s/);
    if (separator <= 0) {
      fields.warnings.push('忽略格式不正确的 @resource。');
      return;
    }
    const name = trimmed.slice(0, separator).trim();
    const url = trimmed.slice(separator + 1).trim();
    if (name.length === 0 || url.length === 0) {
      fields.warnings.push('忽略格式不正确的 @resource。');
      return;
    }
    fields.resources.push({
      name: name,
      url: url
    });
  }

  private normalizeGrants(values: string[], warnings: string[]): UserScriptGrant[] {
    const normalized = this.normalizeStringList(values);
    if (normalized.length === 0) {
      return ['none'];
    }
    const grants: UserScriptGrant[] = [];
    normalized.forEach((value: string) => {
      const grant = this.capabilityContract.normalizeGrant(value);
      if (grant !== undefined) {
        if (!grants.includes(grant)) {
          grants.push(grant);
        }
        return;
      }
      warnings.push(`暂不支持 @grant ${value}，安装后会忽略该授权。`);
    });
    return grants.length > 0 ? grants : ['none'];
  }

  private normalizeRunAt(value: string, warnings: string[]): UserScriptRunAt {
    if (value === 'document-start') {
      return 'document-start';
    }
    if (value === 'document-idle') {
      return 'document-idle';
    }
    if (value === 'main-menu' || value === 'tool-menu' || value === 'context-menu') {
      return value;
    }
    if (value === 'document-end' || value.length === 0) {
      return 'document-end';
    }
    warnings.push(`暂不支持 @run-at ${value}，将按 document-end 运行。`);
    return 'document-end';
  }

  private normalizeStringList(values: string[]): string[] {
    const results: string[] = [];
    values.forEach((value: string) => {
      const trimmed = value.trim();
      if (trimmed.length > 0 && !results.includes(trimmed)) {
        results.push(trimmed);
      }
    });
    return results;
  }

  private firstNonEmpty(values: string[]): string {
    const match = values.find((value: string) => value.trim().length > 0);
    return match?.trim() ?? '';
  }

  private fail(message: string, warnings: string[] = []): UserScriptMetadataParseResult {
    return {
      valid: false,
      warnings: warnings,
      errorMessage: message
    };
  }
}
