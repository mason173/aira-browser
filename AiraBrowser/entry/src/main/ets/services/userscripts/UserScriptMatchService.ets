import {
  InstalledUserScriptState,
  UserScriptPackageCandidate
} from '../../features/userscripts/UserScriptMetadataModels';
import {
  UserScriptParsedUrlParts,
  UserScriptUrlCompatibilityService
} from './UserScriptUrlCompatibilityService';

export class UserScriptMatchService {
  private compatibilityService: UserScriptUrlCompatibilityService = new UserScriptUrlCompatibilityService();

  resolveMatchingScripts(scripts: InstalledUserScriptState[], url: string): InstalledUserScriptState[] {
    return scripts.filter((script: InstalledUserScriptState) => {
      return script.enabled && this.matchesScript(script, url);
    });
  }

  matchesScript(script: InstalledUserScriptState, url: string): boolean {
    const target = this.parseUrl(url);
    if (target === undefined) {
      return false;
    }
    if (target.scheme !== 'http' && target.scheme !== 'https') {
      return false;
    }
    if (this.matchesAny(script.excludeMatches, target, false) || this.matchesAny(script.excludes, target, true)) {
      return false;
    }
    const compatibleTargets = this.compatibilityService.buildCompatibleTargets(target);
    return compatibleTargets.some((candidate: UserScriptParsedUrlParts): boolean => {
      return this.matchesAny(script.matches, candidate, false) ||
        this.matchesAny(script.includes, candidate, true);
    });
  }

  summarizeScope(script: InstalledUserScriptState | UserScriptPackageCandidate): string {
    const positiveRules: string[] = [];
    script.matches.concat(script.includes).forEach((rule: string): void => {
      if (!positiveRules.includes(rule)) {
        positiveRules.push(rule);
      }
    });
    if (positiveRules.length > 0) {
      return this.summarizeRules(positiveRules);
    }
    return '无站点';
  }

  private summarizeRules(rules: string[]): string {
    if (rules.length === 1) {
      return rules[0];
    }
    return `${rules.length} 个站点规则`;
  }

  private matchesAny(rules: string[], target: UserScriptParsedUrlParts, includeMode: boolean): boolean {
    return rules.some((rule: string) => {
      return includeMode ? this.matchesIncludeRule(rule, target) : this.matchesMatchRule(rule, target);
    });
  }

  private matchesMatchRule(rule: string, target: UserScriptParsedUrlParts): boolean {
    const trimmed = rule.trim();
    if (trimmed === '<all_urls>') {
      return true;
    }
    const separatorIndex = trimmed.indexOf('://');
    if (separatorIndex <= 0) {
      return false;
    }
    const schemeRule = trimmed.slice(0, separatorIndex).toLowerCase();
    const rest = trimmed.slice(separatorIndex + 3);
    const slashIndex = rest.indexOf('/');
    const hostRule = (slashIndex < 0 ? rest : rest.slice(0, slashIndex)).toLowerCase();
    const pathRule = slashIndex < 0 ? '/*' : rest.slice(slashIndex);
    return this.matchesScheme(schemeRule, target.scheme) &&
      this.matchesHost(hostRule, target.host) &&
      this.matchesWildcard(pathRule, target.path);
  }

  private matchesIncludeRule(rule: string, target: UserScriptParsedUrlParts): boolean {
    if (this.isRegexRule(rule)) {
      return this.matchesRegexRule(rule, target.url);
    }
    return this.matchesWildcard(rule, target.url);
  }

  private matchesScheme(rule: string, scheme: string): boolean {
    return rule === '*' || rule === scheme;
  }

  private matchesHost(rule: string, host: string): boolean {
    if (rule === '*') {
      return true;
    }
    if (rule.startsWith('*.')) {
      const suffix = rule.slice(2);
      return host === suffix || host.endsWith(`.${suffix}`);
    }
    return rule === host;
  }

  private matchesWildcard(pattern: string, value: string): boolean {
    const escaped = pattern.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*');
    return new RegExp(`^${escaped}$`).test(value);
  }

  private isRegexRule(rule: string): boolean {
    const trimmed = rule.trim();
    return trimmed.length >= 2 && trimmed.startsWith('/') && trimmed.lastIndexOf('/') > 0;
  }

  private matchesRegexRule(rule: string, value: string): boolean {
    const trimmed = rule.trim();
    const lastSlashIndex = trimmed.lastIndexOf('/');
    if (lastSlashIndex <= 0) {
      return false;
    }
    const pattern = trimmed.slice(1, lastSlashIndex);
    const flags = trimmed.slice(lastSlashIndex + 1).replace(/[^dgimsuvy]/g, '');
    try {
      return new RegExp(pattern, flags).test(value);
    } catch (_error) {
      return false;
    }
  }

  private parseUrl(url: string): UserScriptParsedUrlParts | undefined {
    const trimmed = url.trim();
    const match = /^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/([^/?#]+)(.*)$/.exec(trimmed);
    if (match === null) {
      return undefined;
    }
    const scheme = match[1].toLowerCase();
    const host = match[2].toLowerCase().split('@').pop()?.split(':')[0] ?? '';
    const remainder = match[3];
    const path = remainder.length === 0 ? '/' :
      (remainder.startsWith('?') || remainder.startsWith('#') ? `/${remainder}` : remainder);
    if (host.length === 0) {
      return undefined;
    }
    return {
      url: `${scheme}://${match[2]}${path}`,
      scheme: scheme,
      host: host,
      path: path
    };
  }
}
