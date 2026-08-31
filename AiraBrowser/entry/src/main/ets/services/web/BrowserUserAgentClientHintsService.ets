import { webview } from '@kit.ArkWeb';
import {
  BrowserUserAgentClientHintsMetadata,
  BrowserUserAgentResolution
} from './BrowserUserAgentService';
import { BrowserFingerprintPrivacyPolicyService } from '../privacy/BrowserFingerprintPrivacyPolicyService';

interface WebviewControllerClientHintsAdapter {
  setUserAgentMetadata?: (userAgent: string, metadata: webview.UserAgentMetadata) => void;
}

interface BrowserUserAgentClientHintsPlan {
  enabled: boolean;
  metadata?: BrowserUserAgentClientHintsMetadata;
}

export class BrowserUserAgentClientHintsService {
  private appliedMetadataKeysByController: WeakMap<webview.WebviewController, string[]> =
    new WeakMap<webview.WebviewController, string[]>();

  applyToController(controller: webview.WebviewController, resolution: BrowserUserAgentResolution): void {
    const userAgent = resolution.userAgent.trim();
    if (userAgent.length <= 0) {
      return;
    }
    const plan = this.buildPlan(resolution);
    const applicationClientHintsEnabled =
      BrowserFingerprintPrivacyPolicyService.areClientHintsEnabledAtApplicationScope();
    if (!applicationClientHintsEnabled || !plan.enabled) {
      return;
    }
    if (plan.metadata === undefined) {
      return;
    }
    this.applyMetadata(controller, userAgent, plan.metadata);
  }

  private buildPlan(resolution: BrowserUserAgentResolution): BrowserUserAgentClientHintsPlan {
    if (BrowserFingerprintPrivacyPolicyService.isEnhancedEnabled() ||
      resolution.profile.clientHintsMode === 'system') {
      return { enabled: false };
    }
    return {
      enabled: true,
      metadata: resolution.profile.metadata
    };
  }

  private applyMetadata(
    controller: webview.WebviewController,
    userAgent: string,
    plan: BrowserUserAgentClientHintsMetadata
  ): void {
    const metadataKey = this.buildMetadataKey(userAgent, plan);
    const appliedMetadataKeys = this.appliedMetadataKeysByController.get(controller) ?? [];
    if (appliedMetadataKeys.includes(metadataKey)) {
      return;
    }
    const controllerAdapter = controller as object as WebviewControllerClientHintsAdapter;
    if (controllerAdapter.setUserAgentMetadata === undefined) {
      return;
    }
    try {
      const brandVersion = new webview.UserAgentBrandVersion();
      brandVersion.setBrand(plan.brand);
      brandVersion.setMajorVersion(plan.majorVersion);
      brandVersion.setFullVersion(plan.fullVersion);

      const metadata = new webview.UserAgentMetadata();
      metadata.setBrandVersionList([brandVersion]);
      metadata.setFullVersion(plan.fullVersion);
      metadata.setPlatform(plan.platform);
      metadata.setPlatformVersion(plan.platformVersion);
      metadata.setMobile(plan.mobile);
      metadata.setArchitecture(plan.architecture);
      metadata.setBitness(plan.bitness);
      metadata.setModel(plan.model);
      metadata.setWow64(plan.wow64);

      controllerAdapter.setUserAgentMetadata(userAgent, metadata);
      this.rememberMetadataKey(controller, metadataKey);
    } catch (_error) {
    }
  }

  releaseController(controller: webview.WebviewController): void {
    this.appliedMetadataKeysByController.delete(controller);
  }

  private buildMetadataKey(userAgent: string, plan: BrowserUserAgentClientHintsMetadata): string {
    return `${userAgent}|${plan.brand}|${plan.fullVersion}|${plan.platform}|${plan.platformVersion}|${plan.mobile ? '1' : '0'}`;
  }

  private rememberMetadataKey(controller: webview.WebviewController, metadataKey: string): void {
    const appliedMetadataKeys = this.appliedMetadataKeysByController.get(controller) ?? [];
    this.appliedMetadataKeysByController.set(controller, appliedMetadataKeys
      .filter((key: string) => key !== metadataKey)
      .concat([metadataKey])
      .slice(-20));
  }
}
