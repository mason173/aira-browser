import { AdBlockSubscriptionPolicyService } from './AdBlockSubscriptionPolicyService';

const MAX_SUBSCRIPTION_CHARS: number = 20 * 1024 * 1024;
const MAX_SUBSCRIPTION_FILES: number = 32;
const MAX_INCLUDE_DEPTH: number = 8;
const MAX_CONDITION_DEPTH: number = 32;
const MAX_CONDITION_CHARS: number = 1024;
const MAX_SUBSCRIPTION_DURATION_MS: number = 120000;

export interface AdBlockFetchedSubscription {
  text: string;
  updateIntervalMs: number;
}

interface AdBlockSubscriptionDownloadState {
  loadedUrls: Set<string>;
  activeUrls: Set<string>;
  totalChars: number;
  deadlineAt: number;
  updateIntervalMs: number | undefined;
}

interface AdBlockSubscriptionCondition {
  parentActive: boolean;
  result: boolean | undefined;
  hasElse: boolean;
}

// Small expression parser for !, &&, || and parentheses. Unknown tokens stay
// unknown, including after negation; they never enable either conditional arm.
class AdBlockSubscriptionConditionParser {
  private expression: string;
  private index: number = 0;
  private depth: number = 0;
  private unknown: boolean = false;

  constructor(expression: string) {
    this.expression = expression;
  }

  evaluate(): boolean | undefined {
    if (this.expression.length > MAX_CONDITION_CHARS) {
      throw new Error('规则订阅条件过长');
    }
    const result = this.parseOr();
    this.skipSpace();
    if (this.index !== this.expression.length) {
      throw new Error('规则订阅条件格式错误');
    }
    return this.unknown ? undefined : result;
  }

  private parseOr(): boolean {
    let result = this.parseAnd();
    while (this.consume('||')) {
      const right = this.parseAnd();
      result = result || right;
    }
    return result;
  }

  private parseAnd(): boolean {
    let result = this.parseAtom();
    while (this.consume('&&')) {
      const right = this.parseAtom();
      result = result && right;
    }
    return result;
  }

  private parseAtom(): boolean {
    this.depth += 1;
    if (this.depth > MAX_CONDITION_DEPTH) {
      throw new Error('规则订阅条件嵌套过深');
    }
    let value: boolean;
    if (this.consume('!')) {
      value = !this.parseAtom();
    } else if (this.consume('(')) {
      value = this.parseOr();
      if (!this.consume(')')) {
        throw new Error('规则订阅条件缺少右括号');
      }
    } else {
      this.skipSpace();
      const token = /^[a-z_][a-z0-9_]*/i.exec(this.expression.substring(this.index));
      if (token === null) {
        throw new Error('规则订阅条件缺少标识符');
      }
      this.index += token[0].length;
      const resolved = this.resolveToken(token[0]);
      this.unknown = this.unknown || resolved === undefined;
      value = resolved === true;
    }
    this.depth -= 1;
    return value;
  }

  private resolveToken(token: string): boolean | undefined {
    // Follow Brave's adblock-rust list dialect (ext_ublock and Chromium aliases):
    // github.com/brave/brave-core-crx-packager/blob/master/lib/adBlockRustUtils.js
    // Capabilities still describe Aira: no HTML response filtering/user-origin
    // stylesheets. A desktop user-agent does not change the HarmonyOS platform.
    if (token === 'ext_ublock' || token === 'env_chromium' || token === 'env_mobile' ||
      token === 'adguard_ext_chromium' || token === 'adguard_ext_opera') {
      return true;
    }
    const unsupported: string[] = [
      'false', 'ext_abp', 'ext_ubol', 'ext_devbuild', 'env_devbuild',
      'env_edge', 'env_firefox', 'env_safari', 'env_legacy', 'env_mv3',
      'cap_html_filtering', 'cap_user_stylesheet', 'cap_ipaddress',
      'adguard', 'adguard_app_android', 'adguard_app_cli', 'adguard_app_ios',
      'adguard_app_mac', 'adguard_app_windows', 'adguard_ext_android_cb',
      'adguard_ext_chromium_mv3', 'adguard_ext_edge',
      'adguard_ext_firefox', 'adguard_ext_safari'
    ];
    return unsupported.indexOf(token) >= 0 ? false : undefined;
  }

  private consume(value: string): boolean {
    this.skipSpace();
    if (!this.expression.substring(this.index).startsWith(value)) {
      return false;
    }
    this.index += value.length;
    return true;
  }

  private skipSpace(): void {
    while (this.index < this.expression.length && /\s/.test(this.expression[this.index])) {
      this.index += 1;
    }
  }
}

export class AdBlockSubscriptionPreprocessorService {
  private policy: AdBlockSubscriptionPolicyService = new AdBlockSubscriptionPolicyService();

  async fetch(
    url: string,
    download: (url: string, included: boolean) => Promise<string>
  ): Promise<AdBlockFetchedSubscription> {
    const state: AdBlockSubscriptionDownloadState = {
      loadedUrls: new Set<string>(), activeUrls: new Set<string>(), totalChars: 0,
      deadlineAt: Date.now() + MAX_SUBSCRIPTION_DURATION_MS, updateIntervalMs: undefined
    };
    const text = await this.expand(url, download, state, 0);
    return { text: text, updateIntervalMs: this.policy.normalizeUpdateIntervalMs(state.updateIntervalMs) };
  }

  private async expand(
    url: string,
    download: (url: string, included: boolean) => Promise<string>,
    state: AdBlockSubscriptionDownloadState,
    depth: number
  ): Promise<string> {
    if (state.activeUrls.has(url)) {
      throw new Error('规则订阅存在循环引用');
    }
    if (state.loadedUrls.has(url)) {
      return '';
    }
    if (depth > MAX_INCLUDE_DEPTH || state.loadedUrls.size >= MAX_SUBSCRIPTION_FILES ||
      Date.now() >= state.deadlineAt) {
      throw new Error('规则订阅子清单超过加载限制');
    }
    state.loadedUrls.add(url);
    state.activeUrls.add(url);
    const text = (await download(url, depth > 0)).replace(/^\uFEFF/, '');
    state.totalChars += text.length;
    if (state.totalChars > MAX_SUBSCRIPTION_CHARS || Date.now() >= state.deadlineAt) {
      throw new Error('规则订阅总量或加载时间超过限制');
    }
    const interval = this.policy.readUpdateIntervalMs(text);
    if (interval !== undefined) {
      state.updateIntervalMs = Math.min(state.updateIntervalMs ?? interval, interval);
    }
    const output: string[] = [];
    const conditions: AdBlockSubscriptionCondition[] = [];
    let active: boolean = true;
    for (const line of text.split(/\r?\n/)) {
      const directive = /^!#(if|else|endif|include)\b(.*)$/.exec(line.trim());
      if (directive === null) {
        if (active) {
          output.push(line);
        }
        continue;
      }
      const argument = directive[2].trim();
      if (directive[1] === 'if') {
        if (conditions.length >= MAX_CONDITION_DEPTH) {
          throw new Error('规则订阅条件嵌套过深');
        }
        const result = new AdBlockSubscriptionConditionParser(argument).evaluate();
        conditions.push({ parentActive: active, result: result, hasElse: false });
        active = active && result === true;
      } else if (directive[1] === 'else' || directive[1] === 'endif') {
        const condition = conditions[conditions.length - 1];
        if (condition === undefined || argument.length > 0) {
          throw new Error('规则订阅条件结构错误');
        }
        if (directive[1] === 'else') {
          if (condition.hasElse) {
            throw new Error('规则订阅条件重复 else');
          }
          condition.hasElse = true;
          active = condition.parentActive && condition.result === false;
        } else {
          conditions.pop();
          active = condition.parentActive;
        }
      } else if (active) {
        const includeUrl = this.resolveIncludeUrl(url, argument);
        output.push(await this.expand(includeUrl, download, state, depth + 1));
      }
    }
    if (conditions.length > 0) {
      throw new Error('规则订阅条件缺少 endif');
    }
    state.activeUrls.delete(url);
    return output.join('\n');
  }

  private resolveIncludeUrl(parentUrl: string, relativePath: string): string {
    // uBO requires sublists in the same directory or a child directory. Accept
    // only literal relative paths so encoded traversal/authority changes cannot
    // turn a subscription into a downloader for another origin or directory.
    if (!/^[a-zA-Z0-9_~@+.,/-]+$/.test(relativePath) || relativePath.startsWith('/') ||
      relativePath.split('/').some((part: string): boolean => part === '..' || part.length === 0)) {
      throw new Error('规则订阅子清单必须位于同一目录或子目录');
    }
    const path = relativePath.split('/').filter((part: string): boolean => part !== '.').join('/');
    if (path.length === 0) {
      throw new Error('规则订阅子清单地址为空');
    }
    const base = parentUrl.split(/[?#]/)[0];
    const slash = base.lastIndexOf('/');
    if (!base.startsWith('https://') || slash < 'https://'.length) {
      throw new Error('规则订阅子清单需要 HTTPS 地址');
    }
    return base.substring(0, slash + 1) + path;
  }
}
