import { webview } from '@kit.ArkWeb';
import { describe, expect, it } from '@ohos/hypium';
import { BrowserRuntimeControllerResolver } from
  '../main/ets/services/web/BrowserRuntimeLifecyclePort';
import {
  BrowserBrowsingIdentityCandidate,
  BrowserBrowsingIdentityDecision,
  BrowserBrowsingIdentityDecisionService,
  BrowserBrowsingIdentityPrecedenceSource
} from '../main/ets/services/web/BrowserBrowsingIdentityDecisionService';
import { BrowserUserAgentClientHintsService } from
  '../main/ets/services/web/BrowserUserAgentClientHintsService';
import {
  BrowserUserAgentNativeHistorySnapshot,
  BrowserUserAgentRuntimePlatformAdapter,
  BrowserUserAgentRuntimeService
} from '../main/ets/services/web/BrowserUserAgentRuntimeService';
import {
  AIRA_DEFAULT_BROWSER_IDENTITY_ID,
  BrowserUserAgentResolution,
  BrowserUserAgentService,
  DEFAULT_BROWSER_USER_AGENT_SETTINGS
} from '../main/ets/services/web/BrowserUserAgentService';

class FixedRuntimeControllerResolver implements BrowserRuntimeControllerResolver {
  private readonly controller: webview.WebviewController;

  constructor(controller: webview.WebviewController) {
    this.controller = controller;
  }

  resolveController(_tabId: string): webview.WebviewController | undefined {
    return this.controller;
  }
}

class InMemoryUserAgentRuntimePlatformAdapter implements BrowserUserAgentRuntimePlatformAdapter {
  appliedCustomUserAgents: string[] = [];
  historySnapshot: BrowserUserAgentNativeHistorySnapshot = {
    currentIndex: 0,
    size: 1
  };

  resolveController(
    runtimeControllerResolver: BrowserRuntimeControllerResolver,
    tabId: string
  ): webview.WebviewController | undefined {
    return runtimeControllerResolver.resolveController(tabId);
  }

  applyCustomUserAgent(_controller: webview.WebviewController, userAgent: string): void {
    this.appliedCustomUserAgents.push(userAgent);
  }

  readHistorySnapshot(_controller: webview.WebviewController): BrowserUserAgentNativeHistorySnapshot {
    return {
      currentIndex: this.historySnapshot.currentIndex,
      size: this.historySnapshot.size
    };
  }

  applyClientHints(
    _controller: webview.WebviewController,
    _resolution: BrowserBrowsingIdentityDecision
  ): void {
  }

  releaseController(_controller: webview.WebviewController): void {
  }
}

interface UserAgentRuntimeFixture {
  controller: webview.WebviewController;
  controllerResolver: BrowserRuntimeControllerResolver;
  platformAdapter: InMemoryUserAgentRuntimePlatformAdapter;
  runtime: BrowserUserAgentRuntimeService;
}

function createRuntimeFixture(): UserAgentRuntimeFixture {
  const controller = new webview.WebviewController();
  const platformAdapter = new InMemoryUserAgentRuntimePlatformAdapter();
  return {
    controller: controller,
    controllerResolver: new FixedRuntimeControllerResolver(controller),
    platformAdapter: platformAdapter,
    runtime: new BrowserUserAgentRuntimeService(
      new BrowserUserAgentClientHintsService(),
      platformAdapter
    )
  };
}

function emptyCandidate(source: BrowserBrowsingIdentityPrecedenceSource): BrowserBrowsingIdentityCandidate {
  return {
    source: source,
    identityId: '',
    unavailableReason: ''
  };
}

function buildDecision(presetId: string, snapshotKey: string): BrowserBrowsingIdentityDecision {
  const userAgentService = new BrowserUserAgentService();
  const settings = userAgentService.buildPresetSettings(presetId, DEFAULT_BROWSER_USER_AGENT_SETTINGS);
  const resolution: BrowserUserAgentResolution = userAgentService.resolveUserAgent({
    settings: settings,
    systemDefaultUserAgent: 'ArkWeb/System',
    applicationFamily: 'mobile',
    pageUrl: 'https://example.com/'
  });
  const selected: BrowserBrowsingIdentityCandidate = {
    source: 'global',
    identityId: resolution.profile.identityId,
    resolution: resolution,
    unavailableReason: ''
  };
  const applicableDefault: BrowserBrowsingIdentityCandidate = {
    source: 'applicable_default',
    identityId: AIRA_DEFAULT_BROWSER_IDENTITY_ID,
    resolution: resolution,
    unavailableReason: ''
  };
  return new BrowserBrowsingIdentityDecisionService().decide({
    policySnapshotKey: snapshotKey,
    mandatoryHost: emptyCandidate('mandatory_host'),
    currentTab: emptyCandidate('current_tab'),
    exactOrigin: emptyCandidate('exact_origin'),
    global: selected,
    airaCompatibility: emptyCandidate('aira_compatibility'),
    applicableDefault: applicableDefault
  });
}

export default function browserUserAgentRuntimeServiceTest(): void {
  describe('BrowserUserAgentRuntimeService', () => {
    it('redirect hops reuse the frozen navigation identity', 0, () => {
      const fixture = createRuntimeFixture();
      const firstDecision = buildDecision('mobile_chrome_android', 'snapshot-mobile');
      const redirectDecision = buildDecision('desktop_chrome_windows', 'snapshot-desktop');

      const first = fixture.runtime.prepareWebMainFrameNavigation(
        fixture.controllerResolver,
        'tab-runtime',
        'https://example.com/start',
        firstDecision,
        true
      );
      const redirect = fixture.runtime.prepareWebMainFrameNavigation(
        fixture.controllerResolver,
        'tab-runtime',
        'https://redirect.example.net/final',
        redirectDecision,
        false
      );

      expect(first.applicationStatus).assertEqual('custom_applied');
      expect(redirect.applicationStatus).assertEqual('custom_applied');
      expect(fixture.platformAdapter.appliedCustomUserAgents.length).assertEqual(1);
      expect(fixture.platformAdapter.appliedCustomUserAgents[0]).assertEqual(firstDecision.userAgent);
      expect(fixture.runtime.hasEffectiveIdentityChange('tab-runtime', firstDecision)).assertFalse();
    });

    it('a later explicit main-frame navigation applies a new identity', 0, () => {
      const fixture = createRuntimeFixture();
      const firstDecision = buildDecision('mobile_chrome_android', 'snapshot-mobile');
      const nextDecision = buildDecision('desktop_chrome_windows', 'snapshot-desktop');
      fixture.runtime.prepareWebMainFrameNavigation(
        fixture.controllerResolver,
        'tab-runtime',
        'https://example.com/first',
        firstDecision,
        true
      );

      const next = fixture.runtime.prepareWebMainFrameNavigation(
        fixture.controllerResolver,
        'tab-runtime',
        'https://example.com/next',
        nextDecision,
        true
      );

      expect(next.applicationStatus).assertEqual('custom_applied');
      expect(fixture.platformAdapter.appliedCustomUserAgents.length).assertEqual(2);
      expect(fixture.platformAdapter.appliedCustomUserAgents[1]).assertEqual(nextDecision.userAgent);
      expect(fixture.runtime.hasEffectiveIdentityChange('tab-runtime', nextDecision)).assertFalse();
    });

    it('Controller synchronization keeps its committed identity until a new navigation', 0, () => {
      const fixture = createRuntimeFixture();
      const committedDecision = buildDecision('mobile_chrome_android', 'snapshot-mobile');
      const laterPolicyDecision = buildDecision('desktop_chrome_windows', 'snapshot-desktop');
      fixture.runtime.prepareNavigation(
        fixture.controllerResolver,
        'tab-runtime',
        'https://example.com/committed',
        committedDecision
      );
      expect(fixture.runtime.isControllerIdentitySynchronized('tab-runtime', fixture.controller)).assertFalse();
      fixture.runtime.commitNavigation('tab-runtime', fixture.controller, 'https://example.com/committed');
      expect(fixture.runtime.isControllerIdentitySynchronized('tab-runtime', fixture.controller)).assertTrue();

      const synchronized = fixture.runtime.applyToControllerForTab(
        'tab-runtime',
        fixture.controller,
        laterPolicyDecision
      );

      expect(synchronized).assertTrue();
      expect(fixture.platformAdapter.appliedCustomUserAgents.length).assertEqual(1);
      expect(fixture.runtime.hasEffectiveIdentityChange('tab-runtime', committedDecision)).assertFalse();
      expect(fixture.runtime.hasEffectiveIdentityChange('tab-runtime', laterPolicyDecision)).assertTrue();
    });

    it('commit records the applied Controller identity instead of transition intent', 0, () => {
      const fixture = createRuntimeFixture();
      const appliedDecision = buildDecision('mobile_chrome_android', 'snapshot-mobile');
      const nativeIntent = buildDecision('arkweb_original', 'snapshot-native');
      const fallbackDecision = buildDecision('desktop_chrome_windows', 'snapshot-fallback');
      fixture.platformAdapter.historySnapshot = { currentIndex: 0, size: 1 };
      fixture.runtime.prepareNavigation(
        fixture.controllerResolver,
        'tab-runtime',
        'https://example.com/first',
        appliedDecision
      );
      fixture.runtime.commitNavigation('tab-runtime', fixture.controller, 'https://example.com/first');
      fixture.platformAdapter.historySnapshot = { currentIndex: 1, size: 2 };

      const transition = fixture.runtime.prepareNavigation(
        fixture.controllerResolver,
        'tab-runtime',
        'https://example.com/native-intent',
        nativeIntent
      );
      fixture.runtime.commitNavigation('tab-runtime', fixture.controller, 'https://example.com/native-intent');
      const restoreCommittedEntry = fixture.runtime.prepareHistoryNavigation(
        fixture.controllerResolver,
        'tab-runtime',
        'https://example.com/native-intent',
        1,
        'forward',
        fallbackDecision
      );

      expect(transition.applicationStatus).assertEqual('identity_transition_required');
      expect(restoreCommittedEntry.applicationStatus).assertEqual('unchanged');
      expect(fixture.runtime.hasEffectiveIdentityChange('tab-runtime', appliedDecision)).assertFalse();
    });

    it('Back restores the committed entry identity despite later policy changes', 0, () => {
      const fixture = createRuntimeFixture();
      const firstDecision = buildDecision('mobile_chrome_android', 'snapshot-mobile');
      const laterDecision = buildDecision('desktop_chrome_windows', 'snapshot-desktop');
      fixture.platformAdapter.historySnapshot = { currentIndex: 0, size: 1 };
      fixture.runtime.prepareNavigation(
        fixture.controllerResolver,
        'tab-runtime',
        'https://example.com/first',
        firstDecision
      );
      fixture.runtime.commitNavigation('tab-runtime', fixture.controller, 'https://example.com/first');
      fixture.platformAdapter.historySnapshot = { currentIndex: 1, size: 2 };
      fixture.runtime.prepareNavigation(
        fixture.controllerResolver,
        'tab-runtime',
        'https://example.com/second',
        laterDecision
      );
      fixture.runtime.commitNavigation('tab-runtime', fixture.controller, 'https://example.com/second');

      const historyBack = fixture.runtime.prepareHistoryNavigation(
        fixture.controllerResolver,
        'tab-runtime',
        'https://example.com/first',
        0,
        'back',
        laterDecision
      );

      expect(historyBack.applicationStatus).assertEqual('identity_transition_required');
      expect(historyBack.allowed).assertTrue();
      expect(fixture.platformAdapter.appliedCustomUserAgents.length).assertEqual(2);
    });

    it('custom identity to ArkWeb Original requires a Controller transition', 0, () => {
      const fixture = createRuntimeFixture();
      const customDecision = buildDecision('mobile_chrome_android', 'snapshot-mobile');
      const nativeDecision = buildDecision('arkweb_original', 'snapshot-native');
      fixture.runtime.prepareNavigation(
        fixture.controllerResolver,
        'tab-runtime',
        'https://example.com/custom',
        customDecision
      );

      const transition = fixture.runtime.prepareNavigation(
        fixture.controllerResolver,
        'tab-runtime',
        'https://example.com/native',
        nativeDecision
      );

      expect(transition.applicationStatus).assertEqual('identity_transition_required');
      expect(transition.transitionNoticeRequired).assertTrue();
      expect(fixture.platformAdapter.appliedCustomUserAgents.length).assertEqual(1);
      expect(fixture.runtime.requiresControllerTransition('tab-runtime', nativeDecision)).assertTrue();
    });

    it('ArkWeb Original leaves a fresh Controller untouched', 0, () => {
      const fixture = createRuntimeFixture();
      const nativeDecision = buildDecision('arkweb_original', 'snapshot-native');

      const preparation = fixture.runtime.prepareNavigation(
        fixture.controllerResolver,
        'tab-runtime',
        'https://example.com/native',
        nativeDecision
      );

      expect(preparation.applicationStatus).assertEqual('native_untouched');
      expect(fixture.platformAdapter.appliedCustomUserAgents.length).assertEqual(0);
      expect(fixture.runtime.hasEffectiveIdentityChange('tab-runtime', nativeDecision)).assertFalse();
    });
  });
}
