import { webview } from '@kit.ArkWeb';
import { YoutubePageProbeResult } from '../../features/youtubeTakeover/YoutubeModels';
import { YoutubePageProbeScript } from '../../features/youtubeTakeover/YoutubePageProbeScript';

export class YoutubePageProbeService {
  private script: YoutubePageProbeScript = new YoutubePageProbeScript();

  async probe(controller: webview.WebviewController, pageUrl: string, expectedVideoId: string = ''): Promise<YoutubePageProbeResult> {
    try {
      const raw: string = await controller.runJavaScript(this.script.build(expectedVideoId)) as string;
      return this.parse(raw, pageUrl, expectedVideoId);
    } catch (error) {
      const message = (error as Error)?.message ?? 'probe_failed';
      return { ok: false, pageUrl: pageUrl, error: message };
    }
  }

  parse(raw: string | undefined | null, pageUrl: string, expectedVideoId: string = ''): YoutubePageProbeResult {
    if (raw === undefined || raw === null) {
      return { ok: false, pageUrl: pageUrl, error: 'empty_result' };
    }
    let text = String(raw);
    if (text.length === 0) {
      return { ok: false, pageUrl: pageUrl, error: 'empty_result' };
    }
    if (text.charAt(0) === '"' && text.charAt(text.length - 1) === '"') {
      try {
        text = JSON.parse(text) as string;
      } catch (_error) {
        return { ok: false, pageUrl: pageUrl, error: 'bad_outer_quotes' };
      }
    }
    try {
      const parsed: YoutubePageProbeResult = JSON.parse(text) as YoutubePageProbeResult;
      if (typeof parsed.ok !== 'boolean') {
        return { ok: false, pageUrl: pageUrl, error: 'bad_shape' };
      }
      if (parsed.pageUrl === undefined || parsed.pageUrl === null) {
        parsed.pageUrl = pageUrl;
      }
      if (this.hasVideoIdMismatch(parsed.videoId, expectedVideoId)) {
        return {
          ok: false,
          pageUrl: parsed.pageUrl,
          videoId: expectedVideoId.trim(),
          title: parsed.title,
          innertubeApiKey: parsed.innertubeApiKey,
          innertubeClientName: parsed.innertubeClientName,
          innertubeClientVersion: parsed.innertubeClientVersion,
          playerJsUrl: parsed.playerJsUrl,
          visitorData: parsed.visitorData,
          userAgent: parsed.userAgent,
          error: 'stale_probe_video_id_mismatch'
        };
      }
      if (expectedVideoId.trim().length > 0 && (parsed.videoId === undefined || parsed.videoId.length <= 0)) {
        parsed.videoId = expectedVideoId.trim();
      }
      return parsed;
    } catch (error) {
      const message = (error as Error)?.message ?? 'parse_error';
      return { ok: false, pageUrl: pageUrl, error: message };
    }
  }

  private hasVideoIdMismatch(actualVideoId: string | undefined, expectedVideoId: string): boolean {
    const expected = expectedVideoId.trim();
    const actual = actualVideoId?.trim() ?? '';
    return expected.length > 0 && actual.length > 0 && expected !== actual;
  }
}
