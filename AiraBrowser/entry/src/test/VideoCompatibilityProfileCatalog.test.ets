import { describe, expect, it } from '@ohos/hypium';
import { MediaEvidenceScope } from '../main/ets/features/mediaDiscovery/MediaEvidenceGraphModels';
import {
  VideoCompatibilityProfileCatalog,
  VideoCompatibilityProfileDefinition,
  VideoCompatibilityProfileResolveInput,
  VideoCompatibilityProfileResolution,
  VideoCompatibilityProfileScopeDefinition
} from '../main/ets/services/media/VideoCompatibilityProfileCatalog';
import { MediaEvidenceGraph } from '../main/ets/services/media/MediaEvidenceGraph';

function scope(routeEpochId: string, generationId: string = 'generation-video-profile'): MediaEvidenceScope {
  return {
    tabId: 'tab-video-profile',
    generationId: generationId,
    routeEpochId: routeEpochId
  };
}

function packagedProfile(): VideoCompatibilityProfileDefinition {
  return {
    diagnosticProfileKey: 'fixture.player-watch',
    revision: 'packaged-1',
    scope: {
      exactHosts: ['player.example.com'],
      pathPrefixes: ['/watch'],
      requiredQueryKeys: ['v']
    }
  };
}

function profile(
  diagnosticProfileKey: string,
  scopeDefinition: VideoCompatibilityProfileScopeDefinition
): VideoCompatibilityProfileDefinition {
  return {
    diagnosticProfileKey: diagnosticProfileKey,
    revision: 'packaged-1',
    scope: scopeDefinition
  };
}

function longWatchPath(): string {
  let path = '/watch/';
  for (let index: number = 0; index < 600; index += 1) {
    path += 'a';
  }
  return path;
}

function assertProfileResolutionHasNoTakeoverAuthority(
  resolution: VideoCompatibilityProfileResolution
): void {
  // ArkTS intentionally restricts prototype reflection. The public interface is
  // the compile-time boundary; this runtime check covers accidental authority
  // fields leaking through the object representation as well.
  const ownFields: string[] = Object.keys(resolution);
  const forbiddenMethods: string[] = [
    'selectActiveVideoAssistantSession',
    'proveWebLiveControlReachability',
    'createVideoAssistantTakeoverRoute',
    'grantVideoAssistantEntryEligibility'
  ];
  for (let index: number = 0; index < forbiddenMethods.length; index += 1) {
    expect(ownFields.indexOf(forbiddenMethods[index]) >= 0).assertFalse();
  }
}

export default function videoCompatibilityProfileCatalogTest(): void {
  describe('VideoCompatibilityProfileCatalog', () => {
    it('freezes a packaged Profile Resolution for its current route epoch', 0, () => {
      const catalog = new VideoCompatibilityProfileCatalog([packagedProfile()]);
      const routeOne = catalog.resolve({
        scope: scope('route-1'),
        pageUrl: 'https://player.example.com/watch?v=video-1'
      });

      expect(routeOne.isProfileApplied()).assertTrue();
      expect(routeOne.getScope().routeEpochId).assertEqual('route-1');
      expect(routeOne.getDiagnosticAttribution()?.profileKey).assertEqual('fixture.player-watch');

      catalog.replacePackagedProfiles([]);
      const sameRoute = catalog.resolve({
        scope: scope('route-1'),
        pageUrl: 'https://player.example.com/watch?v=video-1'
      });
      const nextRoute = catalog.resolve({
        scope: scope('route-2'),
        pageUrl: 'https://player.example.com/watch?v=video-1'
      });
      const nextGeneration = catalog.resolve({
        scope: scope('route-1', 'generation-video-profile-next'),
        pageUrl: 'https://player.example.com/watch?v=video-1'
      });

      expect(sameRoute.isProfileApplied()).assertTrue();
      expect(nextRoute.isProfileApplied()).assertFalse();
      expect(nextGeneration.isProfileApplied()).assertFalse();
    });

    it('prefers an exact host over an anchored subdomain and the longest normalized path', 0, () => {
      const catalog = new VideoCompatibilityProfileCatalog([
        profile('fixture.anchored', {
          anchoredSubdomainHosts: ['example.com'],
          pathPrefixes: ['/watch']
        }),
        profile('fixture.exact', {
          exactHosts: ['player.example.com'],
          pathPrefixes: ['/watch']
        }),
        profile('fixture.exact-deep', {
          exactHosts: ['player.example.com'],
          pathPrefixes: ['/watch/episode/']
        })
      ]);

      const exact = catalog.resolve({
        scope: scope('route-exact'),
        pageUrl: 'https://player.example.com/watch?v=video-1'
      });
      const deep = catalog.resolve({
        scope: scope('route-deep'),
        pageUrl: 'https://player.example.com/watch/episode/7?v=video-1'
      });

      expect(exact.getDiagnosticAttribution()?.profileKey).assertEqual('fixture.exact');
      expect(deep.getDiagnosticAttribution()?.profileKey).assertEqual('fixture.exact-deep');
    });

    it('keeps exact-host priority even when an anchored scope has a much longer path', 0, () => {
      const longerPath = longWatchPath();
      const catalog = new VideoCompatibilityProfileCatalog([
        profile('fixture.anchored-long', {
          anchoredSubdomainHosts: ['example.com'],
          pathPrefixes: [longerPath]
        }),
        profile('fixture.exact-short', {
          exactHosts: ['player.example.com'],
          pathPrefixes: ['/watch']
        })
      ]);

      const resolution = catalog.resolve({
        scope: scope('route-exact-before-path'),
        pageUrl: 'https://player.example.com' + longerPath
      });

      expect(resolution.getDiagnosticAttribution()?.profileKey).assertEqual('fixture.exact-short');
    });

    it('matches only a child of an anchored subdomain scope and requires named query keys', 0, () => {
      const catalog = new VideoCompatibilityProfileCatalog([
        profile('fixture.anchored-query', {
          anchoredSubdomainHosts: ['stream.example.com'],
          requiredQueryKeys: ['video']
        })
      ]);

      const childWithQuery = catalog.resolve({
        scope: scope('route-child-query'),
        pageUrl: 'https://embed.stream.example.com/player?video=one'
      });
      const childWithoutQuery = catalog.resolve({
        scope: scope('route-child-missing-query'),
        pageUrl: 'https://embed.stream.example.com/player'
      });
      const bareHostWithQuery = catalog.resolve({
        scope: scope('route-bare-host'),
        pageUrl: 'https://stream.example.com/player?video=one'
      });

      expect(childWithQuery.isProfileApplied()).assertTrue();
      expect(childWithoutQuery.isProfileApplied()).assertFalse();
      expect(bareHostWithQuery.isProfileApplied()).assertFalse();
    });

    it('rejects ambiguous equal-specificity matches regardless of catalog order', 0, () => {
      const left = profile('fixture.left', {
        exactHosts: ['player.example.com'],
        pathPrefixes: ['/watch']
      });
      const right = profile('fixture.right', {
        exactHosts: ['player.example.com'],
        pathPrefixes: ['/watch']
      });
      const unrelated = profile('fixture.unrelated', {
        exactHosts: ['other.example.com']
      });
      const firstOrder = new VideoCompatibilityProfileCatalog([left, right, unrelated]);
      const reversedOrder = new VideoCompatibilityProfileCatalog([right, left, unrelated]);
      const input: VideoCompatibilityProfileResolveInput = {
        scope: scope('route-conflict'),
        pageUrl: 'https://player.example.com/watch'
      };

      expect(firstOrder.resolve(input).isProfileApplied()).assertFalse();
      expect(reversedOrder.resolve(input).isProfileApplied()).assertFalse();
      expect(firstOrder.resolve({
        scope: scope('route-invalidated-catalog'),
        pageUrl: 'https://other.example.com/'
      }).isProfileApplied()).assertFalse();
    });

    it('keeps invalid schemes and path siblings on the generic route', 0, () => {
      const catalog = new VideoCompatibilityProfileCatalog([
        profile('fixture.watch', {
          exactHosts: ['player.example.com'],
          pathPrefixes: ['/watch']
        })
      ]);

      const unsupportedScheme = catalog.resolve({
        scope: scope('route-unsupported'),
        pageUrl: 'aira://player.example.com/watch'
      });
      const pathSibling = catalog.resolve({
        scope: scope('route-path-sibling'),
        pageUrl: 'https://player.example.com/watchful'
      });

      expect(unsupportedScheme.isProfileApplied()).assertFalse();
      expect(pathSibling.isProfileApplied()).assertFalse();
    });

    it('keeps the activated latest route when a late older scope is resolved again', 0, () => {
      const catalog = new VideoCompatibilityProfileCatalog([packagedProfile()]);
      const routeOne: VideoCompatibilityProfileResolveInput = {
        scope: scope('route-current-one'),
        pageUrl: 'https://player.example.com/watch?v=video-1'
      };
      const routeTwo: VideoCompatibilityProfileResolveInput = {
        scope: scope('route-current-two'),
        pageUrl: 'https://other.example.com/watch?v=video-2'
      };

      catalog.activateRoute(routeOne, routeOne.scope);
      catalog.activateRoute(routeTwo, routeTwo.scope);
      catalog.replacePackagedProfiles([]);
      const lateRouteOne = catalog.activateRoute(routeOne, routeTwo.scope);
      const current = catalog.getCurrentResolution('tab-video-profile');

      expect(lateRouteOne.isProfileApplied()).assertTrue();
      expect(current?.getScope().routeEpochId).assertEqual('route-current-two');
      expect(current?.isProfileApplied()).assertFalse();
    });

    it('exposes only immutable scope and sanitized attribution, never takeover authority', 0, () => {
      const catalog = new VideoCompatibilityProfileCatalog([packagedProfile()]);
      const resolution = catalog.resolve({
        scope: scope('route-authority'),
        pageUrl: 'https://player.example.com/watch?v=video-1'
      });
      const returnedAttribution = resolution.getDiagnosticAttribution();
      if (returnedAttribution !== undefined) {
        returnedAttribution.profileKey = 'tampered-profile';
      }

      expect(resolution.getScope().routeEpochId).assertEqual('route-authority');
      expect(resolution.getDiagnosticAttribution()?.profileKey).assertEqual('fixture.player-watch');
      expect(resolution.isProfileApplied()).assertTrue();
      assertProfileResolutionHasNoTakeoverAuthority(resolution);
    });

    it('publishes only bounded selector capabilities and named weak-source suppression', 0, () => {
      const catalog = new VideoCompatibilityProfileCatalog([{
        diagnosticProfileKey: 'fixture.selector-capability',
        revision: 'packaged-2',
        scope: { exactHosts: ['player.example.com'] },
        selectors: [{
          selector: 'video.aira-player#main_player',
          evidenceKind: 'structured',
          mediaStructure: 'video',
          attribute: 'source'
        }],
        suppressedHeuristicSources: ['generic_dom_probe']
      }]);
      const resolution = catalog.resolve({
        scope: scope('route-selector-capability'),
        pageUrl: 'https://player.example.com/watch?v=video-1'
      });

      const firstPlans = resolution.getSelectorPlans();
      expect(resolution.isProfileApplied()).assertTrue();
      expect(firstPlans.length).assertEqual(1);
      expect(firstPlans[0].frameScope).assertEqual('top_document');
      expect(firstPlans[0].originScope).assertEqual('top_origin');
      expect(resolution.isHeuristicSuppressed('generic_dom_probe')).assertTrue();
      expect(resolution.isHeuristicSuppressed('generic_deep_probe')).assertFalse();

      firstPlans[0].selector = 'video.tampered';
      expect(resolution.getSelectorPlans()[0].selector).assertEqual('video.aira-player#main_player');
    });

    it('fails closed for unsafe selector declarations and restores generic behavior for disabled Profiles', 0, () => {
      const unsafeSelector = new VideoCompatibilityProfileCatalog([{
        diagnosticProfileKey: 'fixture.unsafe-selector',
        revision: 'packaged-2',
        scope: { exactHosts: ['player.example.com'] },
        selectors: [{
          selector: 'video[data-source]',
          evidenceKind: 'structured',
          mediaStructure: 'video',
          attribute: 'source'
        }],
        suppressedHeuristicSources: ['generic_dom_probe']
      }]);
      const disabled = new VideoCompatibilityProfileCatalog([{
        diagnosticProfileKey: 'fixture.disabled-selector',
        revision: 'packaged-2',
        enabled: false,
        scope: { exactHosts: ['player.example.com'] },
        selectors: [{
          selector: 'video.player',
          evidenceKind: 'structured',
          mediaStructure: 'video',
          attribute: 'source'
        }],
        suppressedHeuristicSources: ['generic_dom_probe']
      }]);
      const input: VideoCompatibilityProfileResolveInput = {
        scope: scope('route-invalid-selector'),
        pageUrl: 'https://player.example.com/watch?v=video-1'
      };

      expect(unsafeSelector.resolve(input).isProfileApplied()).assertFalse();
      expect(disabled.resolve({
        scope: scope('route-disabled-selector'),
        pageUrl: input.pageUrl
      }).isProfileApplied()).assertFalse();
    });

    it('normalizes the packaged Weibo Presentation Recipe without exposing recipe identity', 0, () => {
      const catalog = new VideoCompatibilityProfileCatalog([{
        diagnosticProfileKey: 'fixture.weibo',
        revision: 'packaged-3',
        scope: { exactHosts: ['m.weibo.cn'] },
        presentationRecipe: 'weibo_preserve_surface'
      }]);
      const weibo = catalog.resolve({
        scope: scope('route-weibo-presentation'),
        pageUrl: 'https://m.weibo.cn/status/123'
      });
      const generic = catalog.resolve({
        scope: scope('route-generic-presentation'),
        pageUrl: 'https://player.example.com/watch?v=video-1'
      });

      expect(weibo.isProfileApplied()).assertTrue();
      expect(weibo.getPresentationMode()).assertEqual('preserve_surface');
      expect(generic.getPresentationMode()).assertUndefined();
    });

    it('selects only the closed Bilibili Acquisition Recipe for its resolved route', 0, () => {
      const catalog = new VideoCompatibilityProfileCatalog([{
        diagnosticProfileKey: 'fixture.bilibili',
        revision: 'packaged-3',
        scope: { exactHosts: ['www.bilibili.com'] },
        acquisitionRecipe: 'bilibili_play_info'
      }]);
      const bilibili = catalog.resolve({
        scope: scope('route-bilibili-acquisition'),
        pageUrl: 'https://www.bilibili.com/video/BV1fixture'
      });
      const mobile = catalog.resolve({
        scope: scope('route-bilibili-mobile'),
        pageUrl: 'https://m.bilibili.com/video/BV1fixture'
      });

      expect(bilibili.isProfileApplied()).assertTrue();
      expect(bilibili.getAcquisitionCapability() !== undefined).assertTrue();
      expect(mobile.isProfileApplied()).assertFalse();
      expect(mobile.getAcquisitionCapability()).assertUndefined();
    });

    it('keeps Profile selector evidence route-scoped and outside session resolution', 0, () => {
      const graph = new MediaEvidenceGraph();
      const ingress = graph.beginGeneration({
        tabId: 'tab-profile-evidence',
        navigationKey: 'navigation-profile-evidence',
        pageUrl: 'https://player.example.com/watch?v=video-1',
        pageTitle: 'Profile evidence',
        privacyMode: 'regular',
        startedAt: 1
      });
      const firstScope = ingress.currentScope();
      const receipt = ingress.observe({
        scope: firstScope,
        producer: 'profile_selector',
        observedAt: 2,
        signals: [],
        selectorEvidence: [{
          kind: 'profile_selector',
          profileAttribution: 'fixture.selector-capability',
          evidenceKind: 'structured',
          mediaStructure: 'video',
          attribute: 'source',
          frameScope: 'top_document',
          originScope: 'top_origin',
          matchedCount: 1,
          qualityGateMatchCount: 1,
          attributeMatchCount: 1
        }]
      });

      expect(receipt.acceptedCount).assertEqual(1);
      expect(receipt.changes.sessionEvidence).assertFalse();
      expect(ingress.compatibilityReader().projectProfileSelectorEvidence().length).assertEqual(1);
      const nextScope = ingress.advanceRouteEpoch({
        currentScope: firstScope,
        routeTransitionKey: 'route-change',
        pageUrl: 'https://player.example.com/watch?v=video-2',
        pageTitle: 'Profile evidence next',
        observedAt: 3
      });
      expect(nextScope.routeEpochId === firstScope.routeEpochId).assertFalse();
      expect(ingress.compatibilityReader().projectProfileSelectorEvidence().length).assertEqual(0);
      expect(ingress.compatibilityReader().projectSessionEvidence(4).targets.length).assertEqual(0);
    });
  });
}
