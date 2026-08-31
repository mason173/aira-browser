import { describe, expect, it } from '@ohos/hypium';
import { webview } from '@kit.ArkWeb';
import {
  BrowserArkWebMediaCastMediaResolution,
  BrowserArkWebMediaTakeoverCoordinator
} from '../main/ets/core/browser/media/BrowserArkWebMediaTakeoverCoordinator';
import { TabManager } from '../main/ets/core/tabs/TabManager';
import {
  MediaCompatibilitySelectorEvidenceObservation,
  MediaEvidenceScope
} from '../main/ets/features/mediaDiscovery/MediaEvidenceGraphModels';
import { MediaSessionResolutionSnapshot } from
  '../main/ets/features/mediaDiscovery/MediaSessionResolutionModels';
import {
  VideoCompatibilityProfileCatalog,
  VideoCompatibilityProfileDefinition,
  VideoCompatibilityProfileResolution
} from '../main/ets/services/media/VideoCompatibilityProfileCatalog';
import {
  VideoCompatibilityAcquisitionResource,
  VideoCompatibilityAcquisitionReport,
  VideoCompatibilityProfileAcquisitionInterceptInput,
  VideoCompatibilityProfileAcquisitionScheduler
} from '../main/ets/services/media/VideoCompatibilityProfileAcquisitionRecipeService';
import { MediaEvidenceGraph } from '../main/ets/services/media/MediaEvidenceGraph';
import { MediaSessionResolutionService } from '../main/ets/services/media/MediaSessionResolutionService';
import { BrowserRuntimeLifecyclePort } from '../main/ets/services/web/BrowserRuntimeLifecyclePort';

const YOUTUBE_VIDEO_ID: string = 'abcdefghijk';

interface MaliciousProfileDefinition extends VideoCompatibilityProfileDefinition {
  directEvidence: string;
  activeSession: string;
  reachability: string;
  takeoverRoute: string;
  entryEligibility: boolean;
}

interface YoutubePlayerFormatFixture {
  itag: number;
  url: string;
  mimeType: string;
  bitrate: number;
  width?: number;
  height?: number;
  audioSampleRate?: string;
  audioChannels?: number;
  approxDurationMs: string;
}

interface YoutubePlayabilityStatusFixture {
  status: string;
}

interface YoutubeVideoDetailsFixture {
  videoId: string;
  title: string;
  lengthSeconds: string;
}

interface YoutubeStreamingDataFixture {
  expiresInSeconds: string;
  formats: YoutubePlayerFormatFixture[];
  adaptiveFormats: YoutubePlayerFormatFixture[];
}

interface YoutubePlayerResponseFixture {
  playabilityStatus: YoutubePlayabilityStatusFixture;
  videoDetails: YoutubeVideoDetailsFixture;
  streamingData: YoutubeStreamingDataFixture;
}

class YoutubeRecipeFixtureController extends webview.WebviewController {
  private readonly probePayload: string;

  constructor(playerResponse: YoutubePlayerResponseFixture) {
    super();
    this.probePayload = JSON.stringify({
      ok: true,
      pageUrl: `https://www.youtube.com/watch?v=${YOUTUBE_VIDEO_ID}`,
      videoId: YOUTUBE_VIDEO_ID,
      title: 'Fixture video',
      playerResponseJson: JSON.stringify(playerResponse),
      userAgent: 'Aira test fixture'
    });
  }

  runJavaScript(_script: string): Promise<string> {
    return Promise.resolve(this.probePayload);
  }
}

class AuthorityRuntimePort extends BrowserRuntimeLifecyclePort {
  constructor() {
    super(
      new TabManager(),
      {
        getTabs: () => [],
        getWindowScopeId: () => 'window-profile-gate',
        getActiveTabId: () => 'tab-profile-gate',
        isHomeVisible: () => false,
        applyTabRuntimePatch: () => {},
        recordRuntimeEvent: () => {}
      },
      () => new webview.WebviewController(),
      { persistMountedRuntimeSnapshot: () => {} }
    );
  }

  resolveController(_tabId: string): webview.WebviewController | undefined {
    return new webview.WebviewController();
  }

  isActiveWebTab(tabId: string): boolean {
    return tabId === 'tab-profile-gate';
  }
}

function scope(routeEpochId: string, tabId: string = 'tab-profile-gate'): MediaEvidenceScope {
  return {
    tabId: tabId,
    generationId: 'generation-profile-gate',
    routeEpochId: routeEpochId
  };
}

function youtubeProfile(key: string, host: string, pathPrefixes: string[]): VideoCompatibilityProfileDefinition {
  return {
    diagnosticProfileKey: key,
    revision: 'packaged-gate-1',
    scope: { exactHosts: [host], pathPrefixes: pathPrefixes },
    acquisitionRecipe: 'youtube_player'
  };
}

function youtubeProfiles(): VideoCompatibilityProfileDefinition[] {
  return [
    youtubeProfile('gate.youtube', 'www.youtube.com', ['/watch', '/shorts', '/embed']),
    youtubeProfile('gate.youtube-mobile', 'm.youtube.com', ['/watch', '/shorts', '/embed']),
    youtubeProfile('gate.youtube-music', 'music.youtube.com', ['/watch', '/shorts', '/embed']),
    youtubeProfile('gate.youtu-be', 'youtu.be', ['/'])
  ];
}

function youtubePlayerResponse(adaptive: boolean, expiresInSeconds: string = '3600'): YoutubePlayerResponseFixture {
  const progressive: YoutubePlayerFormatFixture = {
    itag: 22,
    url: 'https://rr.example.googlevideo.com/videoplayback?itag=22',
    mimeType: 'video/mp4; codecs="avc1.64001F, mp4a.40.2"',
    bitrate: 1200000,
    width: 1280,
    height: 720,
    approxDurationMs: '60000'
  };
  const video: YoutubePlayerFormatFixture = {
    itag: 137,
    url: 'https://rr.example.googlevideo.com/videoplayback?itag=137',
    mimeType: 'video/mp4; codecs="avc1.640028"',
    bitrate: 2200000,
    width: 1920,
    height: 1080,
    approxDurationMs: '60000'
  };
  const audio: YoutubePlayerFormatFixture = {
    itag: 140,
    url: 'https://rr.example.googlevideo.com/videoplayback?itag=140',
    mimeType: 'audio/mp4; codecs="mp4a.40.2"',
    bitrate: 128000,
    audioSampleRate: '44100',
    audioChannels: 2,
    approxDurationMs: '60000'
  };
  return {
    playabilityStatus: { status: 'OK' },
    videoDetails: { videoId: YOUTUBE_VIDEO_ID, title: 'Fixture video', lengthSeconds: '60' },
    streamingData: {
      expiresInSeconds: expiresInSeconds,
      formats: adaptive ? [] : [progressive],
      adaptiveFormats: adaptive ? [video, audio] : []
    }
  };
}

function selectorEvidence(
  resolution: VideoCompatibilityProfileResolution
): MediaCompatibilitySelectorEvidenceObservation {
  const plan = resolution.getSelectorPlans()[0];
  return {
    kind: 'profile_selector',
    profileAttribution: resolution.getDiagnosticAttribution()?.profileKey ?? '',
    evidenceKind: plan.evidenceKind,
    mediaStructure: plan.mediaStructure,
    attribute: plan.attribute,
    frameScope: plan.frameScope,
    originScope: plan.originScope,
    matchedCount: 1,
    qualityGateMatchCount: 1,
    attributeMatchCount: 1
  };
}

function profileIntercept(pageUrl: string, tabId: string): VideoCompatibilityProfileAcquisitionInterceptInput {
  return {
    tabId: tabId,
    pageUrl: pageUrl,
    requestUrl: 'https://rr.example.googlevideo.com/videoplayback?itag=22'
  };
}

function missingCastMedia(): BrowserArkWebMediaCastMediaResolution {
  return { reason: 'missing_target', mediaFormat: '', requestHeaderCount: 0 };
}

export default function videoCompatibilityProfileReleaseGateTest(): void {
  describe('Packaged VideoCompatibilityProfile release gate', () => {
    it('carries malicious Profile fields through the real authority chain without granting authority', 0, () => {
      const malicious: MaliciousProfileDefinition = {
        diagnosticProfileKey: 'gate.malicious',
        revision: 'packaged-1',
        scope: { exactHosts: ['player.example.com'] },
        selectors: [{
          selector: 'video.player',
          evidenceKind: 'structured',
          mediaStructure: 'video',
          attribute: 'source'
        }],
        directEvidence: 'downgrade-to-heuristic',
        activeSession: 'attacker-session',
        reachability: 'reachable',
        takeoverRoute: 'web_live',
        entryEligibility: true
      };
      const catalog = new VideoCompatibilityProfileCatalog([malicious]);
      const graph = new MediaEvidenceGraph();
      const ingress = graph.beginGeneration({
        tabId: 'tab-profile-gate',
        navigationKey: 'navigation-malicious',
        pageUrl: 'https://player.example.com/watch',
        pageTitle: 'Malicious fixture',
        privacyMode: 'regular',
        startedAt: 1
      });
      const resolution = catalog.resolve({ scope: ingress.currentScope(), pageUrl: 'https://player.example.com/watch' });
      ingress.observe({
        scope: ingress.currentScope(),
        producer: 'profile_selector',
        observedAt: 2,
        signals: [],
        selectorEvidence: [selectorEvidence(resolution)]
      });
      const resolver = new MediaSessionResolutionService();
      const profileOnly = resolver.resolve(ingress.compatibilityReader().projectSessionEvidence(3), 3);
      expect(profileOnly.outcome).assertEqual('inactive');
      expect(profileOnly.getSessions().length).assertEqual(0);

      ingress.observe({
        scope: ingress.currentScope(),
        producer: 'playback_event',
        observedAt: 4,
        signals: [],
        observations: [{
          kind: 'playback_target',
          targetKey: 'dom:runtime-main',
          targetIdentityQuality: 'stable',
          event: 'playing',
          sourceLocators: ['https://media.example/video.mp4?credential=secret'],
          elementId: 'video-main',
          currentTimeSeconds: 12,
          durationSeconds: 120,
          quality: 'direct'
        }]
      });
      const direct = resolver.resolve(ingress.compatibilityReader().projectSessionEvidence(5), 5);
      expect(direct.outcome).assertEqual('active');
      expect(direct.getSessions()[0].evidenceQuality).assertEqual('direct');
      expect(direct.getSessions()[0].webLiveReachability).assertEqual('unknown');

      let snapshot: MediaSessionResolutionSnapshot | undefined = direct;
      const takeover = new BrowserArkWebMediaTakeoverCoordinator(new AuthorityRuntimePort());
      takeover.bindRuntimeEvidencePublisher({
        capture: () => undefined,
        resolveSnapshot: () => snapshot,
        resolveCastMedia: () => missingCastMedia()
      });
      const route = takeover.beginLaunch('tab-profile-gate', true);
      expect(route.accepted).assertFalse();
      expect(route.reason).assertEqual('web_live_unavailable');
      snapshot = profileOnly;
      const profileOnlyRoute = takeover.beginLaunch('tab-profile-gate', true);
      expect(profileOnlyRoute.accepted).assertFalse();
      expect(profileOnlyRoute.reason).assertEqual('session_missing');
    });

    it('projects sanitized Profile diagnostics from a real Private Browsing generation', 0, () => {
      const graph = new MediaEvidenceGraph();
      const ingress = graph.beginGeneration({
        tabId: 'tab-private-secret',
        navigationKey: 'navigation-private-secret',
        pageUrl: `https://www.youtube.com/watch?v=${YOUTUBE_VIDEO_ID}&private_fixture=secret`,
        pageTitle: 'Private secret title',
        privacyMode: 'private',
        startedAt: 1
      });
      const catalog = new VideoCompatibilityProfileCatalog([{
        diagnosticProfileKey: 'gate.private-safe',
        revision: 'packaged-1',
        scope: { exactHosts: ['www.youtube.com'], pathPrefixes: ['/watch'] },
        selectors: [{
          selector: 'video.player',
          evidenceKind: 'structured',
          mediaStructure: 'video',
          attribute: 'presence'
        }]
      }]);
      const resolution = catalog.resolve({
        scope: ingress.currentScope(),
        pageUrl: `https://www.youtube.com/watch?v=${YOUTUBE_VIDEO_ID}&private_fixture=secret`
      });
      ingress.observe({
        scope: ingress.currentScope(),
        producer: 'profile_selector',
        observedAt: 2,
        signals: [],
        selectorEvidence: [selectorEvidence(resolution)]
      });
      const diagnosticOutput = JSON.stringify(ingress.compatibilityReader().projectProfileSelectorEvidence());

      expect(diagnosticOutput.indexOf('gate.private-safe') >= 0).assertTrue();
      expect(diagnosticOutput.indexOf('private_fixture') >= 0).assertFalse();
      expect(diagnosticOutput.indexOf(YOUTUBE_VIDEO_ID) >= 0).assertFalse();
      expect(diagnosticOutput.indexOf('tab-private-secret') >= 0).assertFalse();
      expect(diagnosticOutput.indexOf('Private secret title') >= 0).assertFalse();
    });

    it('clears the route Catalog and YouTube scheduler state on tab close', 0, () => {
      const catalog = new VideoCompatibilityProfileCatalog(youtubeProfiles());
      const tabId = 'tab-youtube-close';
      const pageUrl = `https://www.youtube.com/watch?v=${YOUTUBE_VIDEO_ID}`;
      const routeScope = scope('route-youtube-close', tabId);
      const resolution = catalog.activateRoute({ scope: routeScope, pageUrl: pageUrl }, routeScope);
      const scheduler: VideoCompatibilityProfileAcquisitionScheduler | undefined =
        resolution.getAcquisitionCapability()?.getScheduler();

      expect(catalog.getCurrentResolution(tabId) !== undefined).assertTrue();
      expect(scheduler?.observeIntercept(profileIntercept(pageUrl, tabId)) !== undefined).assertTrue();
      expect(scheduler?.observeIntercept(profileIntercept(pageUrl, tabId))).assertUndefined();
      catalog.clearTab(tabId);
      expect(catalog.getCurrentResolution(tabId)).assertUndefined();
      expect(scheduler?.observeIntercept(profileIntercept(pageUrl, tabId)) !== undefined).assertTrue();
      expect(catalog.resolve({ scope: routeScope, pageUrl: pageUrl }) === resolution).assertFalse();
    });

    it('resolves every packaged YouTube surface to the same bounded Recipe contract', 0, () => {
      const catalog = new VideoCompatibilityProfileCatalog(youtubeProfiles());
      const urls: string[] = [
        `https://www.youtube.com/watch?v=${YOUTUBE_VIDEO_ID}`,
        `https://www.youtube.com/shorts/${YOUTUBE_VIDEO_ID}`,
        `https://www.youtube.com/embed/${YOUTUBE_VIDEO_ID}`,
        `https://m.youtube.com/watch?v=${YOUTUBE_VIDEO_ID}`,
        `https://youtu.be/${YOUTUBE_VIDEO_ID}`,
        `https://music.youtube.com/watch?v=${YOUTUBE_VIDEO_ID}`
      ];

      for (let index = 0; index < urls.length; index += 1) {
        const resolution = catalog.resolve({ scope: scope(`route-youtube-${index}`), pageUrl: urls[index] });
        expect(resolution.isProfileApplied()).assertTrue();
        expect(resolution.getAcquisitionCapability() !== undefined).assertTrue();
      }
    });

    it('normalizes progressive and adaptive YouTube resources through the Recipe capability interface', 0, async () => {
      const resolution = new VideoCompatibilityProfileCatalog(youtubeProfiles()).resolve({
        scope: scope('route-youtube-resources'),
        pageUrl: `https://www.youtube.com/watch?v=${YOUTUBE_VIDEO_ID}`
      });
      const capability = resolution.getAcquisitionCapability();
      const pageUrl = `https://www.youtube.com/watch?v=${YOUTUBE_VIDEO_ID}`;
      const progressive: VideoCompatibilityAcquisitionReport | undefined = await capability?.acquire(
        new YoutubeRecipeFixtureController(youtubePlayerResponse(false)), pageUrl, Date.now()
      );
      const adaptive: VideoCompatibilityAcquisitionReport | undefined = await capability?.acquire(
        new YoutubeRecipeFixtureController(youtubePlayerResponse(true)), pageUrl, Date.now()
      );
      const adaptiveResources: VideoCompatibilityAcquisitionResource[] = adaptive?.resources ?? [];

      expect(progressive?.resources.length ?? 0).assertEqual(1);
      expect(progressive?.resources[0].family).assertEqual('video');
      expect(progressive?.resources[0].kind).assertEqual('progressive');
      expect(adaptive?.resources.length ?? 0).assertEqual(2);
      expect(adaptive?.resources[0].family).assertEqual('video');
      expect(adaptive?.resources[0].kind).assertEqual('dash');
      expect(adaptive?.resources[1].family).assertEqual('audio');
      expect(adaptive?.resources[1].kind).assertEqual('dash');
      expect(adaptive?.resources[0].provenance).assertEqual('profile_acquisition');
      expect(Object.keys(adaptiveResources[0]).indexOf('youtube') >= 0).assertFalse();
    });

    it('keeps expired or incomplete YouTube plans empty without manufacturing fallback authority', 0, async () => {
      const resolution = new VideoCompatibilityProfileCatalog(youtubeProfiles()).resolve({
        scope: scope('route-youtube-empty'),
        pageUrl: `https://www.youtube.com/watch?v=${YOUTUBE_VIDEO_ID}`
      });
      const capability = resolution.getAcquisitionCapability();
      const pageUrl = `https://www.youtube.com/watch?v=${YOUTUBE_VIDEO_ID}`;
      const expired = await capability?.acquire(
        new YoutubeRecipeFixtureController(youtubePlayerResponse(false, '-1')), pageUrl, Date.now()
      );
      const incompleteFixture = youtubePlayerResponse(true);
      incompleteFixture.streamingData.adaptiveFormats.splice(1, 1);
      const incomplete = await capability?.acquire(
        new YoutubeRecipeFixtureController(incompleteFixture), pageUrl, Date.now()
      );

      expect(expired?.resources.length ?? 0).assertEqual(0);
      expect(incomplete?.resources.length ?? 0).assertEqual(0);
    });
  });
}
