import { webview } from '@kit.ArkWeb';
import {
  MediaResourceDomProbePayload,
  MediaResourceDomProbeScript
} from '../../features/mediaDiscovery/MediaResourceDomProbeScript';

export class MediaResourceDomProbeService {
  private script: MediaResourceDomProbeScript = new MediaResourceDomProbeScript();

  async scan(controller: webview.WebviewController | undefined): Promise<MediaResourceDomProbePayload> {
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
