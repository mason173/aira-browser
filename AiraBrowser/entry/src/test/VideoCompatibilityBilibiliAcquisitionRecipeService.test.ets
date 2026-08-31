import { describe, expect, it } from '@ohos/hypium';
import { MediaEvidenceScope } from '../main/ets/features/mediaDiscovery/MediaEvidenceGraphModels';
import { MediaVideoDeepProbeResult } from '../main/ets/features/mediaDiscovery/MediaVideoDeepProbeScript';
import {
  VideoCompatibilityAcquisitionReport,
  VideoCompatibilityBilibiliAcquisitionRecipeService,
  VideoCompatibilityProfileAcquisitionLease
} from '../main/ets/services/media/VideoCompatibilityProfileAcquisitionRecipeService';

const BILIBILI_PAGE_URL: string = 'https://www.bilibili.com/video/BV1fixture';
const VIDEO_URL: string = 'https://media.example.test/video.m4s?token=fixture';
const AUDIO_URL: string = 'https://media.example.test/audio.m4s?token=fixture';

interface BilibiliRecipeFixtureResource {
  url: string;
  family: string;
  kind: string;
  mimeType: string;
  codecs?: string;
  bandwidth?: number;
  initializationRange?: string;
  indexRange?: string;
  width?: number;
  height?: number;
  durationMs?: number;
}

interface BilibiliRecipeFixturePayload {
  ok: boolean;
  origin: string;
  resources: BilibiliRecipeFixtureResource[];
}

function fixtureRecipePayload(): string {
  const payload: BilibiliRecipeFixturePayload = {
    ok: true,
    origin: 'https://www.bilibili.com',
    resources: [{
      url: VIDEO_URL,
      family: 'video',
      kind: 'dash',
      mimeType: 'video/mp4',
      codecs: 'avc1.640028',
      bandwidth: 1400000,
      initializationRange: '0-1000',
      indexRange: '1001-2000',
      width: 1920,
      height: 1080,
      durationMs: 64000
    }, {
      url: AUDIO_URL,
      family: 'audio',
      kind: 'dash',
      mimeType: 'audio/mp4',
      codecs: 'mp4a.40.2',
      bandwidth: 192000,
      initializationRange: '0-400',
      indexRange: '401-900',
      durationMs: 64000
    }]
  };
  return JSON.stringify(payload);
}

function legacyBilibiliDashFixture(): MediaVideoDeepProbeResult[] {
  return [{
    url: VIDEO_URL,
    source: 'player',
    signal: 'video_element',
    mimeType: 'video/mp4',
    pairedAudioUrl: AUDIO_URL,
    pairedAudioMimeType: 'audio/mp4',
    codecs: 'avc1.640028',
    bandwidth: 1400000,
    initializationRange: '0-1000',
    indexRange: '1001-2000',
    pairedAudioCodecs: 'mp4a.40.2',
    pairedAudioBandwidth: 192000,
    pairedAudioInitializationRange: '0-400',
    pairedAudioIndexRange: '401-900',
    durationMs: 64000,
    width: 1920,
    height: 1080,
    fromBlob: false
  }];
}

export default function videoCompatibilityBilibiliAcquisitionRecipeServiceTest(): void {
  describe('VideoCompatibilityBilibiliAcquisitionRecipeService', () => {
    it('normalizes bounded neutral resources with fixed provenance and freshness', 0, () => {
      const service = new VideoCompatibilityBilibiliAcquisitionRecipeService();
      const report = service.normalizePayload(
        fixtureRecipePayload(),
        BILIBILI_PAGE_URL,
        'fixture.bilibili',
        12345
      );

      expect(report?.resources.length).assertEqual(2);
      expect(report?.resources[0].family).assertEqual('video');
      expect(report?.resources[1].family).assertEqual('audio');
      expect(report?.resources[0].provenance).assertEqual('profile_acquisition');
      expect(report?.resources[0].profileAttribution).assertEqual('fixture.bilibili');
      expect(report?.resources[0].observedAt).assertEqual(12345);
    });

    it('rejects a payload that was not produced by the current top-level origin', 0, () => {
      const service = new VideoCompatibilityBilibiliAcquisitionRecipeService();
      const wrongOriginPayload: BilibiliRecipeFixturePayload = {
        ok: true,
        origin: 'https://m.bilibili.com',
        resources: []
      };
      const wrongOrigin = JSON.stringify(wrongOriginPayload);

      expect(service.normalizePayload(
        wrongOrigin,
        BILIBILI_PAGE_URL,
        'fixture.bilibili',
        12345
      )).assertUndefined();
    });

    it('compares sanitized Recipe and legacy deep-probe fixtures without exposing resource addresses', 0, () => {
      const service = new VideoCompatibilityBilibiliAcquisitionRecipeService();
      const report = service.normalizePayload(
        fixtureRecipePayload(),
        BILIBILI_PAGE_URL,
        'fixture.bilibili',
        12345
      );
      const normalizedReport: VideoCompatibilityAcquisitionReport = report ?? { resources: [] };
      const comparison = service.compareWithLegacyBilibiliDeepProbe(
        normalizedReport,
        legacyBilibiliDashFixture()
      );

      expect(comparison.recipeResourceCount).assertEqual(2);
      expect(comparison.legacyResourceCount).assertEqual(2);
      expect(comparison.recipeVideoCount).assertEqual(1);
      expect(comparison.legacyVideoCount).assertEqual(1);
      expect(comparison.recipeAudioCount).assertEqual(1);
      expect(comparison.legacyAudioCount).assertEqual(1);
      expect(comparison.trackFactsMatch).assertTrue();
      expect(comparison.resourceIdentityMatch).assertTrue();
      expect(Object.keys(comparison).indexOf('url') >= 0).assertFalse();
    });

    it('rejects acquisition receipts after generation or route epoch advancement', 0, () => {
      const capturedScope: MediaEvidenceScope = {
        tabId: 'tab-bilibili',
        generationId: 'generation-1',
        routeEpochId: 'route-1'
      };
      const nextGeneration: MediaEvidenceScope = {
        tabId: 'tab-bilibili',
        generationId: 'generation-2',
        routeEpochId: 'route-1'
      };
      const nextRoute: MediaEvidenceScope = {
        tabId: 'tab-bilibili',
        generationId: 'generation-1',
        routeEpochId: 'route-2'
      };
      const lease = new VideoCompatibilityProfileAcquisitionLease(
        capturedScope,
        BILIBILI_PAGE_URL,
        'fixture.bilibili'
      );

      expect(lease.isCurrent(capturedScope, BILIBILI_PAGE_URL, 'fixture.bilibili')).assertTrue();
      expect(lease.isCurrent(nextGeneration, BILIBILI_PAGE_URL, 'fixture.bilibili')).assertFalse();
      expect(lease.isCurrent(nextRoute, BILIBILI_PAGE_URL, 'fixture.bilibili')).assertFalse();
      expect(lease.isCurrent(
        capturedScope,
        'https://www.bilibili.com/video/BV1next',
        'fixture.bilibili'
      )).assertFalse();
    });
  });
}
