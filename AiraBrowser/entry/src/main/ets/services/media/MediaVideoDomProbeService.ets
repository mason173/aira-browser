import { webview } from '@kit.ArkWeb';
import {
  MediaVideoDomProbePayload,
  MediaVideoDomProbeScript
} from '../../features/mediaDiscovery/MediaVideoDomProbeScript';

export class MediaVideoDomProbeService {
  private script: MediaVideoDomProbeScript = new MediaVideoDomProbeScript();

  async scan(controller: webview.WebviewController | undefined): Promise<MediaVideoDomProbePayload> {
    if (controller === undefined) {
      return { ok: false, results: [], error: 'no_controller' };
    }
    try {
      const raw: string = await controller.runJavaScript(this.script.build());
      if (raw === null || raw === undefined) {
        return { ok: false, results: [], error: 'no_result' };
      }
      const rawString: string = raw.length > 0 ? raw : '';
      const trimmed = this.unwrapJsonString(rawString);
      return this.script.parse(trimmed);
    } catch (error) {
      const message = (error as Error)?.message ?? 'scan_failed';
      return { ok: false, results: [], error: message };
    }
  }

  private unwrapJsonString(raw: string): string {
    if (raw.length >= 2 && raw.charAt(0) === '"' && raw.charAt(raw.length - 1) === '"') {
      try {
        const decoded: string = JSON.parse(raw) as string;
        if (typeof decoded === 'string') {
          return decoded;
        }
      } catch (_error) {
      }
    }
    return raw;
  }
}
