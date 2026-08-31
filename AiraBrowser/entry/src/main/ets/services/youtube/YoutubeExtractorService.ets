import { webview } from '@kit.ArkWeb';
import {
  YoutubeFormat,
  YoutubePlaybackPlan
} from '../../features/youtubeTakeover/YoutubeModels';
import { YoutubeStreamingDataParser } from '../../features/youtubeTakeover/YoutubeStreamingDataParser';
import { YoutubeFormatSelector, YoutubeFormatSelection } from '../../features/youtubeTakeover/YoutubeFormatSelector';
import { YoutubePageProbeService } from './YoutubePageProbeService';
import { YoutubeInnertubePlayerService } from './YoutubeInnertubePlayerService';
import { hilog } from '@kit.PerformanceAnalysisKit';

const YOUTUBE_EXTRACTOR_LOG_DOMAIN: number = 0xA1A0;
const YOUTUBE_EXTRACTOR_LOG_TAG: string = 'YoutubeExtractor';

export interface YoutubeExtractionResult {
  plan: YoutubePlaybackPlan;
  selection: YoutubeFormatSelection;
}

export class YoutubeExtractorService {
  private probeService: YoutubePageProbeService = new YoutubePageProbeService();
  private parser: YoutubeStreamingDataParser = new YoutubeStreamingDataParser();
  private selector: YoutubeFormatSelector = new YoutubeFormatSelector();
  private innertubeService: YoutubeInnertubePlayerService = new YoutubeInnertubePlayerService();

  async extract(
    controller: webview.WebviewController,
    pageUrl: string,
    fallbackVideoId: string,
    suppressDiagnostics: boolean
  ): Promise<YoutubeExtractionResult> {
    const expectedVideoId = fallbackVideoId.trim();
    const probe = await this.probeService.probe(controller, pageUrl, expectedVideoId);
    const videoId = expectedVideoId.length > 0 ? expectedVideoId : probe.videoId ?? '';
    let plan: YoutubePlaybackPlan = this.buildNoStreamingPlan(pageUrl, videoId, probe.title, probe.error ?? 'probe_failed');
    let selection: YoutubeFormatSelection = {};

    if (probe.playerResponseJson !== undefined && probe.playerResponseJson !== null && probe.playerResponseJson.length > 0) {
      const pagePlan = this.parser.parse(probe.playerResponseJson, pageUrl, videoId);
      if (this.hasVideoIdMismatch(pagePlan.videoId, expectedVideoId)) {
        this.runDiagnostics(suppressDiagnostics, (): void => {
          hilog.warn(
            YOUTUBE_EXTRACTOR_LOG_DOMAIN,
            YOUTUBE_EXTRACTOR_LOG_TAG,
            'discard stale page plan expected=%{public}s actual=%{public}s',
            expectedVideoId,
            pagePlan.videoId
          );
        });
      } else {
        plan = pagePlan;
        if (probe.title !== undefined && plan.title.length === 0) {
          plan.title = probe.title;
        }
        if (probe.userAgent !== undefined && probe.userAgent.length > 0) {
          plan.userAgent = probe.userAgent;
        }
        selection = this.selector.selectDefault(plan);
      }
    }

    if (!probe.ok && probe.innertubeApiKey === undefined) {
      return { plan: plan, selection: selection };
    }
    const apiPlan = await this.innertubeService.fetchPlan(probe, pageUrl, videoId, suppressDiagnostics);
    if (apiPlan !== undefined) {
      if (this.hasVideoIdMismatch(apiPlan.videoId, expectedVideoId)) {
        this.runDiagnostics(suppressDiagnostics, (): void => {
          hilog.warn(
            YOUTUBE_EXTRACTOR_LOG_DOMAIN,
            YOUTUBE_EXTRACTOR_LOG_TAG,
            'discard stale api plan expected=%{public}s actual=%{public}s',
            expectedVideoId,
            apiPlan.videoId
          );
        });
        return { plan: plan, selection: selection };
      }
      if (probe.title !== undefined && apiPlan.title.length === 0) {
        apiPlan.title = probe.title;
      }
      const apiSelection = this.selector.selectDefault(apiPlan);
      if (this.isProgressivePlayable(apiPlan, apiSelection) || this.isAdaptiveOnly(apiPlan, apiSelection) ||
        (!this.isProgressivePlayable(plan, selection) && !this.isAdaptiveOnly(plan, selection))) {
        plan = apiPlan;
        selection = apiSelection;
      }
    }
    return { plan: plan, selection: selection };
  }

  selectorOf(plan: YoutubePlaybackPlan): YoutubeFormatSelection {
    return this.selector.selectDefault(plan);
  }

  isProgressivePlayable(plan: YoutubePlaybackPlan, selection: YoutubeFormatSelection): boolean {
    if (plan.status !== 'ok') {
      return false;
    }
    const progressive: YoutubeFormat | undefined = selection.progressive;
    return this.selector.isSafeProgressiveDirectFormat(progressive);
  }

  isAdaptiveOnly(plan: YoutubePlaybackPlan, selection: YoutubeFormatSelection): boolean {
    if (plan.status !== 'ok') {
      return false;
    }
    const hasVideo = selection.video !== undefined && selection.video.url.length > 0;
    const hasAudio = selection.audio !== undefined && selection.audio.url.length > 0;
    return hasVideo && hasAudio;
  }

  private buildNoStreamingPlan(
    pageUrl: string,
    videoId: string,
    title: string | undefined,
    reason: string
  ): YoutubePlaybackPlan {
    return {
      status: 'no_streaming_data',
      videoId: videoId,
      pageUrl: pageUrl,
      title: title ?? '',
      progressiveFormats: [],
      videoOnlyFormats: [],
      audioOnlyFormats: [],
      reason: reason
    };
  }

  private hasVideoIdMismatch(actualVideoId: string, expectedVideoId: string): boolean {
    const expected = expectedVideoId.trim();
    const actual = actualVideoId.trim();
    return expected.length > 0 && actual.length > 0 && expected !== actual;
  }

  private runDiagnostics(suppressDiagnostics: boolean, write: () => void): void {
    if (!suppressDiagnostics) {
      write();
    }
  }
}
