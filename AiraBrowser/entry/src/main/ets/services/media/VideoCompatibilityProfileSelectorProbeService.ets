import { webview } from '@kit.ArkWeb';
import urlUtils from '@ohos.url';
import {
  MediaCompatibilitySelectorEvidenceObservation
} from '../../features/mediaDiscovery/MediaEvidenceGraphModels';
import {
  VideoCompatibilityProfileSelectorPlan
} from './VideoCompatibilityProfileCatalog';

interface VideoCompatibilityProfileSelectorProbeRawResult {
  index?: number;
  matchedCount?: number;
  qualityGateMatchCount?: number;
  attributeMatchCount?: number;
}

interface VideoCompatibilityProfileSelectorProbeRawPayload {
  ok?: boolean;
  origin?: string;
  results?: VideoCompatibilityProfileSelectorProbeRawResult[];
}

interface VideoCompatibilityProfileSelectorScriptPlan {
  selector: string;
  evidenceKind: string;
  mediaStructure: string;
  attribute: string;
}

/**
 * Executes only normalized, App-validated media selectors. The page receives no Profile identity or executable
 * content; it returns bounded counts and never serializes a DOM node, URL, attribute value, or page text.
 */
export class VideoCompatibilityProfileSelectorProbeService {
  async probe(
    controller: webview.WebviewController | undefined,
    pageUrl: string,
    profileAttribution: string,
    plans: VideoCompatibilityProfileSelectorPlan[]
  ): Promise<MediaCompatibilitySelectorEvidenceObservation[]> {
    if (controller === undefined || plans.length <= 0 || profileAttribution.trim().length <= 0) {
      return [];
    }
    const expectedOrigin = this.resolveOrigin(pageUrl);
    if (expectedOrigin.length <= 0) {
      return [];
    }
    try {
      const raw = await controller.runJavaScript(this.buildScript(plans));
      if (raw === null || raw === undefined || raw.length <= 0) {
        return [];
      }
      const payload = this.parsePayload(this.unwrapJsonString(raw));
      if (payload === undefined || payload.ok !== true || payload.origin !== expectedOrigin ||
        payload.results === undefined) {
        return [];
      }
      return this.buildEvidence(profileAttribution, plans, payload.results);
    } catch (_error) {
      return [];
    }
  }

  private buildScript(plans: VideoCompatibilityProfileSelectorPlan[]): string {
    const serializedPlans = JSON.stringify(plans.map((plan: VideoCompatibilityProfileSelectorPlan): VideoCompatibilityProfileSelectorScriptPlan => ({
      selector: plan.selector,
      evidenceKind: plan.evidenceKind,
      mediaStructure: plan.mediaStructure,
      attribute: plan.attribute
    })));
    return `(function(){
      try {
        var plans = ${serializedPlans};
        var results = [];
        function visible(node) {
          try {
            var rect = node.getBoundingClientRect();
            if (node.tagName.toLowerCase() === 'audio') {
              return node.readyState > 0 || (rect.width >= 2 && rect.height >= 2);
            }
            if (rect.width < 2 || rect.height < 2) return false;
            var style = window.getComputedStyle ? window.getComputedStyle(node) : null;
            return !style || (style.display !== 'none' && style.visibility !== 'hidden' &&
              Number.parseFloat(style.opacity || '1') > 0.02);
          } catch (_visibilityError) {
            return false;
          }
        }
        function attributePresent(node, attribute) {
          try {
            if (attribute === 'presence') return true;
            if (attribute === 'source') return String(node.currentSrc || node.src || '').length > 0;
            if (attribute === 'poster') return String(node.poster || '').length > 0;
            if (attribute === 'dimensions') {
              return node.tagName.toLowerCase() === 'video' ?
                Number(node.videoWidth || 0) > 0 && Number(node.videoHeight || 0) > 0 :
                Number(node.readyState || 0) > 0;
            }
          } catch (_attributeError) {
            return false;
          }
          return false;
        }
        for (var planIndex = 0; planIndex < plans.length && planIndex < 8; planIndex++) {
          var plan = plans[planIndex];
          var matchedCount = 0;
          var qualityGateMatchCount = 0;
          var attributeMatchCount = 0;
          try {
            var nodes = document.querySelectorAll(plan.selector);
            for (var nodeIndex = 0; nodeIndex < nodes.length && nodeIndex < 32; nodeIndex++) {
              var node = nodes[nodeIndex];
              if (!node || node.tagName.toLowerCase() !== plan.mediaStructure) continue;
              matchedCount++;
              if (!visible(node)) continue;
              qualityGateMatchCount++;
              if (attributePresent(node, plan.attribute)) attributeMatchCount++;
            }
          } catch (_selectorError) {
          }
          results.push({
            index: planIndex,
            matchedCount: matchedCount,
            qualityGateMatchCount: qualityGateMatchCount,
            attributeMatchCount: attributeMatchCount
          });
        }
        return JSON.stringify({
          ok: true,
          origin: window.location.origin || '',
          results: results
        });
      } catch (_error) {
        return JSON.stringify({ok: false, origin: '', results: []});
      }
    })()`;
  }

  private parsePayload(raw: string): VideoCompatibilityProfileSelectorProbeRawPayload | undefined {
    try {
      const payload = JSON.parse(raw) as VideoCompatibilityProfileSelectorProbeRawPayload;
      if (payload === undefined || payload === null) {
        return undefined;
      }
      return payload;
    } catch (_error) {
      return undefined;
    }
  }

  private buildEvidence(
    profileAttribution: string,
    plans: VideoCompatibilityProfileSelectorPlan[],
    results: VideoCompatibilityProfileSelectorProbeRawResult[]
  ): MediaCompatibilitySelectorEvidenceObservation[] {
    const evidence: MediaCompatibilitySelectorEvidenceObservation[] = [];
    for (let index = 0; index < results.length && index < plans.length; index += 1) {
      const result = results[index];
      const planIndex = this.boundedInteger(result.index, 0, plans.length - 1);
      if (planIndex < 0 || planIndex !== index) {
        continue;
      }
      const matchedCount = this.boundedInteger(result.matchedCount, 0, 32);
      const qualityGateMatchCount = this.boundedInteger(result.qualityGateMatchCount, 0, matchedCount);
      const attributeMatchCount = this.boundedInteger(result.attributeMatchCount, 0, qualityGateMatchCount);
      if (qualityGateMatchCount <= 0) {
        continue;
      }
      const plan = plans[planIndex];
      evidence.push({
        kind: 'profile_selector',
        profileAttribution: profileAttribution.trim(),
        evidenceKind: plan.evidenceKind,
        mediaStructure: plan.mediaStructure,
        attribute: plan.attribute,
        frameScope: plan.frameScope,
        originScope: plan.originScope,
        matchedCount: matchedCount,
        qualityGateMatchCount: qualityGateMatchCount,
        attributeMatchCount: attributeMatchCount
      });
    }
    return evidence;
  }

  private boundedInteger(value: number | undefined, minimum: number, maximum: number): number {
    if (value === undefined || !Number.isFinite(value)) {
      return minimum;
    }
    return Math.min(maximum, Math.max(minimum, Math.floor(value)));
  }

  private resolveOrigin(pageUrl: string): string {
    try {
      const parsed = urlUtils.URL.parseURL(pageUrl.trim());
      const protocol = parsed.protocol.trim().toLowerCase();
      const hostname = parsed.hostname.trim().toLowerCase();
      const port = parsed.port?.trim() ?? '';
      if ((protocol !== 'http:' && protocol !== 'https:') || hostname.length <= 0) {
        return '';
      }
      const isDefaultPort = (protocol === 'http:' && port === '80') ||
        (protocol === 'https:' && port === '443');
      return protocol + '//' + hostname + (port.length > 0 && !isDefaultPort ? ':' + port : '');
    } catch (_error) {
      return '';
    }
  }

  private unwrapJsonString(raw: string): string {
    if (raw.length >= 2 && raw.charAt(0) === '"' && raw.charAt(raw.length - 1) === '"') {
      try {
        const decoded = JSON.parse(raw) as string;
        return typeof decoded === 'string' ? decoded : raw;
      } catch (_error) {
      }
    }
    return raw;
  }
}
