import { InstalledUserScriptState } from '../../features/userscripts/UserScriptMetadataModels';

export interface UserScriptParsedUrlParts {
  url: string;
  scheme: string;
  host: string;
  path: string;
}

export class UserScriptUrlCompatibilityService {
  buildCompatibleTargets(target: UserScriptParsedUrlParts): UserScriptParsedUrlParts[] {
    const targets: UserScriptParsedUrlParts[] = [target];
    if (target.host === 'wk.baidu.com' && target.path.startsWith('/tfview/')) {
      const compatiblePath = `/view/${target.path.substring('/tfview/'.length)}`;
      targets.push({
        url: `${target.url.slice(0, target.url.length - target.path.length)}${compatiblePath}`,
        scheme: target.scheme,
        host: target.host,
        path: compatiblePath
      });
    }
    return targets;
  }

  expandRunAtRules(script: InstalledUserScriptState): string[] {
    const results: string[] = [];
    const expandedMatches = this.expandRules(script.matches);
    for (let index = 0; index < expandedMatches.length; index += 1) {
      const projected = this.projectMatchRule(expandedMatches[index]);
      if (projected === undefined) {
        return ['*'];
      }
      projected.forEach((rule: string): void => this.appendUnique(results, rule));
    }
    const expandedIncludes = this.expandRules(script.includes);
    for (let index = 0; index < expandedIncludes.length; index += 1) {
      const projected = this.projectIncludeRule(expandedIncludes[index]);
      if (projected === undefined) {
        return ['*'];
      }
      projected.forEach((rule: string): void => this.appendUnique(results, rule));
    }
    if (results.length === 0 || results.includes('*')) {
      return ['*'];
    }
    return results;
  }

  private buildCompatibleMatchRule(rule: string): string {
    const trimmed = rule.trim();
    if (trimmed === '*://wk.baidu.com/view/*') {
      return '*://wk.baidu.com/tfview/*';
    }
    return '';
  }

  private expandRules(rules: string[]): string[] {
    const results: string[] = [];
    rules.forEach((rule: string): void => {
      this.appendUnique(results, rule);
      const compatibleRule = this.buildCompatibleMatchRule(rule);
      if (compatibleRule.length > 0) {
        this.appendUnique(results, compatibleRule);
      }
    });
    return results;
  }

  private projectMatchRule(rule: string): string[] | undefined {
    const trimmed = rule.trim();
    if (trimmed === '<all_urls>') {
      return ['*'];
    }
    const separatorIndex = trimmed.indexOf('://');
    if (separatorIndex <= 0) {
      return undefined;
    }
    const schemeRule = trimmed.slice(0, separatorIndex).toLowerCase();
    if (schemeRule !== '*' && schemeRule !== 'http' && schemeRule !== 'https') {
      return [];
    }
    const rest = trimmed.slice(separatorIndex + 3);
    const slashIndex = rest.indexOf('/');
    const hostRule = (slashIndex < 0 ? rest : rest.slice(0, slashIndex)).toLowerCase();
    const pathRule = slashIndex < 0 ? '/*' : rest.slice(slashIndex);
    if (!this.isSafeArkWebHostRule(hostRule) || !this.isSafeArkWebPathRule(pathRule)) {
      return undefined;
    }
    if (hostRule === '*') {
      return ['*'];
    }
    const schemes = schemeRule === '*' ? ['http', 'https'] : [schemeRule];
    const hosts: string[] = [];
    if (hostRule.startsWith('*.')) {
      this.appendUnique(hosts, hostRule.slice(2));
    }
    this.appendUnique(hosts, hostRule);
    const results: string[] = [];
    schemes.forEach((scheme: string): void => {
      hosts.forEach((host: string): void => {
        this.appendUnique(results, `${scheme}://${host}`);
      });
    });
    return results;
  }

  private projectIncludeRule(rule: string): string[] | undefined {
    const trimmed = rule.trim();
    if (this.isRegexIncludeRule(trimmed)) {
      return undefined;
    }
    const separatorIndex = trimmed.indexOf('://');
    if (separatorIndex <= 0) {
      return undefined;
    }
    const schemeRule = trimmed.slice(0, separatorIndex).toLowerCase();
    if (schemeRule !== '*' && schemeRule !== 'http' && schemeRule !== 'https') {
      return [];
    }
    const rest = trimmed.slice(separatorIndex + 3);
    const slashIndex = rest.indexOf('/');
    if (slashIndex <= 0) {
      return undefined;
    }
    const hostRule = rest.slice(0, slashIndex);
    const pathRule = rest.slice(slashIndex);
    if (hostRule !== hostRule.toLowerCase() || !this.isSafeArkWebHostRule(hostRule) ||
      !this.isSafeArkWebPathRule(pathRule)) {
      return undefined;
    }
    if (hostRule === '*') {
      return ['*'];
    }
    const schemes = schemeRule === '*' ? ['http', 'https'] : [schemeRule];
    return schemes.map((scheme: string): string => `${scheme}://${hostRule}`);
  }

  private isRegexIncludeRule(rule: string): boolean {
    return rule.length >= 2 && rule.startsWith('/') && rule.lastIndexOf('/') > 0;
  }

  private isSafeArkWebHostRule(rule: string): boolean {
    if (rule === '*') {
      return true;
    }
    const candidate = rule.startsWith('*.') ? rule.slice(2) : rule;
    if (candidate.length === 0) {
      return false;
    }
    return candidate.split('.').every((label: string): boolean => {
      return label.length > 0 && /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(label);
    });
  }

  private isSafeArkWebPathRule(rule: string): boolean {
    return rule.startsWith('/') && !/[\s,]/.test(rule);
  }

  private appendUnique(values: string[], value: string): void {
    const trimmed = value.trim();
    if (trimmed.length > 0 && !values.includes(trimmed)) {
      values.push(trimmed);
    }
  }
}
