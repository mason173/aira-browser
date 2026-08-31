import {
  SitePermissionKind,
  SitePermissionRule,
  SitePermissionSettings
} from '../../common/models/BrowserModels';
import { SiteIdentityService } from './SiteIdentityService';

export interface SitePermissionDraftState {
  origin: string;
  camera: SitePermissionRule;
  microphone: SitePermissionRule;
  location: SitePermissionRule;
  sensor: SitePermissionRule;
  clipboard: SitePermissionRule;
}

export class SiteInteractionLogicService {
  private siteIdentityService: SiteIdentityService = new SiteIdentityService();

  formatBytes(bytes: number): string {
    if (bytes <= 0) {
      return '0 KB';
    }
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(bytes < 1024 * 100 ? 1 : 0)} KB`;
    }
    return `${(bytes / 1024 / 1024).toFixed(bytes < 1024 * 1024 * 100 ? 1 : 0)} MB`;
  }

  resolveOrigin(url: string): string {
    const trimmed = url.trim();
    const match = trimmed.match(/^([a-z][a-z0-9+.-]*:\/\/[^/?#]+)/i);
    return match === null ? '' : match[1].toLowerCase();
  }

  normalizeOrigin(origin: string): string {
    return origin.trim().toLowerCase();
  }

  isSamePermissionSite(firstOrigin: string, secondOrigin: string): boolean {
    return this.siteIdentityService.matchesSite(firstOrigin, secondOrigin);
  }

  isIpAddressHost(host: string): boolean {
    if (host.indexOf(':') >= 0) {
      return true;
    }
    return host.match(/^\d{1,3}(\.\d{1,3}){3}$/) !== null;
  }

  getDisplayOrigin(origin: string): string {
    const host = this.siteIdentityService.resolve(origin).displayHost;
    return host.length > 0 ? host : origin;
  }

  getHostFromUrl(url: string): string {
    return this.siteIdentityService.resolve(url).displayHost;
  }

  buildPermissionUpdateOrigins(
    origin: string,
    currentOrigin: string,
    relatedOrigins: string[]
  ): string[] {
    const normalizedOrigin = this.normalizeOrigin(origin);
    let origins: string[] = [];
    origins = this.addOriginIfMissing(origins, normalizedOrigin);
    if (this.isSamePermissionSite(currentOrigin, normalizedOrigin)) {
      origins = this.addOriginIfMissing(origins, currentOrigin);
    }
    relatedOrigins.forEach((relatedOrigin: string) => {
      if (this.isSamePermissionSite(relatedOrigin, normalizedOrigin)) {
        origins = this.addOriginIfMissing(origins, relatedOrigin);
      }
    });
    return origins;
  }

  addOriginIfMissing(origins: string[], origin: string): string[] {
    const normalizedOrigin = this.normalizeOrigin(origin);
    if (normalizedOrigin.length === 0 || origins.indexOf(normalizedOrigin) >= 0) {
      return origins;
    }
    return origins.concat([normalizedOrigin]);
  }

  applyRuleToDraft(
    draft: SitePermissionDraftState,
    kind: SitePermissionKind,
    rule: SitePermissionRule
  ): SitePermissionDraftState {
    const nextDraft: SitePermissionDraftState = {
      origin: draft.origin,
      camera: draft.camera,
      microphone: draft.microphone,
      location: draft.location,
      sensor: draft.sensor,
      clipboard: draft.clipboard
    };
    if (kind === 'camera') {
      nextDraft.camera = rule;
    } else if (kind === 'microphone') {
      nextDraft.microphone = rule;
    } else if (kind === 'location') {
      nextDraft.location = rule;
    } else if (kind === 'sensor') {
      nextDraft.sensor = rule;
    } else {
      nextDraft.clipboard = rule;
    }
    return nextDraft;
  }

  buildDraftFromSettings(settings: SitePermissionSettings): SitePermissionDraftState {
    return {
      origin: settings.origin,
      camera: settings.camera,
      microphone: settings.microphone,
      location: settings.location,
      sensor: settings.sensor,
      clipboard: settings.clipboard
    };
  }

  hasDraftChanged(current: SitePermissionDraftState, saved: SitePermissionDraftState): boolean {
    return current.camera !== saved.camera ||
      current.microphone !== saved.microphone ||
      current.location !== saved.location ||
      current.sensor !== saved.sensor ||
      current.clipboard !== saved.clipboard;
  }
}
