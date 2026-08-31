import { webview } from '@kit.ArkWeb';
import {
  MediaVideoDeepProbeConfiguration,
  MediaVideoDeepProbePayload,
  MediaVideoDeepProbeScript
} from '../../features/mediaDiscovery/MediaVideoDeepProbeScript';
import {
  MediaDeepProbeStrategyId,
  MediaDetectionPolicy,
  MediaDetectionPolicyCatalog,
  sharedMediaDetectionPolicyCatalog
} from './MediaDetectionPolicyCatalog';

export class MediaVideoDeepProbeService {
  private script: MediaVideoDeepProbeScript = new MediaVideoDeepProbeScript();
  private readonly policyCatalog: MediaDetectionPolicyCatalog;

  constructor(
    policyCatalog: MediaDetectionPolicyCatalog = sharedMediaDetectionPolicyCatalog
  ) {
    this.policyCatalog = policyCatalog;
  }

  async probe(
    controller: webview.WebviewController | undefined,
    allowBlockingFallback: boolean = false,
    replacedGenericStrategyIds: MediaDeepProbeStrategyId[] = []
  ): Promise<MediaVideoDeepProbePayload> {
    if (controller === undefined) {
      return { ok: false, results: [], error: 'no_controller' };
    }
    try {
      const policy: MediaDetectionPolicy = this.policyCatalog.currentPolicy();
      const configuration: MediaVideoDeepProbeConfiguration = {
        strategyIds: this.excludeReplacedStrategies(
          policy.deepProbeStrategyIds,
          replacedGenericStrategyIds
        ),
        globalConfigNames: policy.globalConfigNames.slice(),
        mediaFieldNames: policy.mediaFieldNames.slice(),
        mediaQueryParameterNames: policy.mediaQueryParameterNames.slice(),
        playerMethodNames: policy.playerMethodNames.slice()
      };
      const raw: string = await controller.runJavaScript(
        this.script.build(allowBlockingFallback, configuration)
      );
      if (raw === null || raw === undefined) {
        return { ok: false, results: [], error: 'no_result' };
      }
      const rawString: string = raw.length > 0 ? raw : '';
      const trimmed = this.unwrapJsonString(rawString);
      return this.script.parse(trimmed);
    } catch (error) {
      const message = (error as Error)?.message ?? 'probe_failed';
      return { ok: false, results: [], error: message };
    }
  }

  private excludeReplacedStrategies(
    strategyIds: MediaDeepProbeStrategyId[],
    replacedStrategyIds: MediaDeepProbeStrategyId[]
  ): MediaDeepProbeStrategyId[] {
    if (replacedStrategyIds.length <= 0) {
      return strategyIds.slice();
    }
    const filtered: MediaDeepProbeStrategyId[] = [];
    for (let index: number = 0; index < strategyIds.length; index += 1) {
      if (replacedStrategyIds.indexOf(strategyIds[index]) < 0) {
        filtered.push(strategyIds[index]);
      }
    }
    return filtered;
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
