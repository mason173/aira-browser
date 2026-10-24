import { util } from '@kit.ArkTS';
import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';

export const QQ_WEB_LOGIN_CALLBACK_SOURCE: string = 'qq_web_login_callback';
const CALLBACK_PREFIX: string = 'airabrowser://qq-login/';
const LOGIN_LIFETIME_MS: number = 10 * 60 * 1000;
const MAX_PENDING_LOGINS: number = 16;
const MAX_LOGIN_URL_LENGTH: number = 65536;

export interface QqWebLoginContext {
  windowId: string;
  tabId: string;
  sourcePageUrl: string;
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
}

export interface QqWebLoginLaunch {
  launchUrl: string;
  requestId: string;
}

export interface QqWebLoginReturn extends QqWebLoginContext {
  requestId: string;
  targetUrl: string;
}

interface PendingQqWebLogin {
  requestId: string;
  context: QqWebLoginContext;
  expectedDestination: string;
  createdAt: number;
}

interface LoginQueryValue {
  found: boolean;
  valid: boolean;
  value: string;
}

/** Process-scoped, single-use return tickets. Never persist QQ credentials or private login state. */
export class QqWebLoginCallbackService {
  private pending: PendingQqWebLogin[] = [];

  prepareLaunch(
    sourceUrl: string,
    context: QqWebLoginContext | undefined,
    now: number = Date.now()
  ): QqWebLoginLaunch | undefined {
    const normalizedUrl = sourceUrl.trim();
    if (context === undefined || context.windowId.length === 0 || context.tabId.length === 0 ||
      context.sourcePageUrl.length === 0 || normalizedUrl.length > MAX_LOGIN_URL_LENGTH ||
      !/^wtloginmqq:\/\/ptlogin\/qlogin\?/i.test(normalizedUrl) || normalizedUrl.indexOf('#') >= 0) {
      return undefined;
    }
    const query = normalizedUrl.substring(normalizedUrl.indexOf('?') + 1);
    const jump = this.readQuery(query, 'p');
    const destination = this.readJumpDestination(jump.value);
    if (!jump.valid || !jump.found || destination.length === 0) {
      return undefined;
    }
    this.prune(now);
    // A second login from the same tab supersedes its earlier return ticket.
    this.pending = this.pending.filter((entry: PendingQqWebLogin): boolean =>
      entry.context.windowId !== context.windowId || entry.context.tabId !== context.tabId);
    const requestId = util.generateRandomUUID();
    this.pending.push({
      requestId: requestId,
      context: {
        windowId: context.windowId,
        tabId: context.tabId,
        sourcePageUrl: context.sourcePageUrl,
        profileId: context.profileId,
        privacyMode: context.privacyMode,
        dataScope: context.dataScope
      },
      expectedDestination: destination,
      createdAt: now
    });
    this.pending = this.pending.slice(-MAX_PENDING_LOGINS);
    const preserved = query.split('&').filter((part: string): boolean => {
      const key = this.decode(part.split('=')[0]).toLowerCase();
      return key !== 'schemacallback' && key !== 'encode_jump_url' && key !== 'replace_https';
    });
    const callback = `${CALLBACK_PREFIX}${requestId}?url=`;
    preserved.push(`schemacallback=${encodeURIComponent(callback)}`, 'encode_jump_url=1', 'replace_https=0');
    return {
      launchUrl: `wtloginmqq://ptlogin/qlogin?${preserved.join('&')}`,
      requestId: requestId
    };
  }

  isCallbackUrl(sourceUrl: string): boolean {
    // Consume all of our scheme at ingress, including malformed/expired callbacks; never route them outward again.
    return /^airabrowser:/i.test(sourceUrl.trim());
  }

  peekReturn(sourceUrl: string, now: number = Date.now()): QqWebLoginReturn | undefined {
    this.prune(now);
    const match = /^airabrowser:\/\/qq-login\/([a-f0-9-]{36})\?url=(.+)$/i.exec(sourceUrl.trim());
    if (match === null || sourceUrl.length > MAX_LOGIN_URL_LENGTH) {
      return undefined;
    }
    const requestId = match[1];
    const entry = this.pending.find((candidate: PendingQqWebLogin): boolean => candidate.requestId === requestId);
    if (entry === undefined) {
      return undefined;
    }
    // Current QQ clients honor encode_jump_url. Also accept an unencoded URL from older clients,
    // without decoding its query a second time (which would corrupt u1/openlogin_data).
    let targetUrl = /^(https:\/\/|ssl\.ptlogin2\.qq\.com\/jump\?)/i.test(match[2])
      ? match[2] : this.decode(match[2]);
    if (targetUrl.startsWith('ssl.ptlogin2.qq.com/jump?')) {
      targetUrl = `https://${targetUrl}`;
    }
    if (this.readJumpDestination(targetUrl) !== entry.expectedDestination) {
      return undefined;
    }
    return {
      windowId: entry.context.windowId,
      tabId: entry.context.tabId,
      sourcePageUrl: entry.context.sourcePageUrl,
      profileId: entry.context.profileId,
      privacyMode: entry.context.privacyMode,
      dataScope: entry.context.dataScope,
      requestId: requestId,
      targetUrl: targetUrl
    };
  }

  consumeReturn(sourceUrl: string, now: number = Date.now()): QqWebLoginReturn | undefined {
    const result = this.peekReturn(sourceUrl, now);
    if (result !== undefined) {
      this.cancel(result.requestId);
    }
    return result;
  }

  cancel(requestId: string): void {
    this.pending = this.pending.filter((entry: PendingQqWebLogin): boolean => entry.requestId !== requestId);
  }

  private prune(now: number): void {
    this.pending = this.pending.filter((entry: PendingQqWebLogin): boolean =>
      now >= entry.createdAt && now - entry.createdAt <= LOGIN_LIFETIME_MS);
  }

  private readJumpDestination(targetUrl: string): string {
    // The return must continue QQ's HTTPS ticket exchange, never an arbitrary scheme, host, or redirect.
    if (!/^https:\/\/ssl\.ptlogin2\.qq\.com\/jump\?/i.test(targetUrl) || /[\s#\\]/.test(targetUrl)) {
      return '';
    }
    const destination = this.readQuery(targetUrl.substring(targetUrl.indexOf('?') + 1), 'u1');
    return destination.valid && destination.found && /^https?:\/\//i.test(destination.value)
      ? destination.value : '';
  }

  private readQuery(query: string, expectedKey: string): LoginQueryValue {
    let found = false;
    let value = '';
    const parts = query.split('&');
    for (let index = 0; index < parts.length; index += 1) {
      const separator = parts[index].indexOf('=');
      const key = this.decode(separator < 0 ? parts[index] : parts[index].substring(0, separator));
      if (key.toLowerCase() !== expectedKey) {
        continue;
      }
      if (found || separator < 0) {
        return { found: true, valid: false, value: '' };
      }
      found = true;
      value = this.decode(parts[index].substring(separator + 1));
    }
    return { found: found, valid: true, value: value };
  }

  private decode(value: string): string {
    try {
      return decodeURIComponent(value);
    } catch (_error) {
      return '';
    }
  }
}

export const sharedQqWebLoginCallbackService: QqWebLoginCallbackService = new QqWebLoginCallbackService();
