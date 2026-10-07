/**
 * Download-trigger forensics probe (temporary).
 *
 * Reported symptom: with the content filter on and EasyList China enabled, opening a cool18.com
 * thread pops the download-confirm sheet for the ad iframe URL (ad.parkvv.com/html/iframe.php?...).
 * The blocked-response shape was changed to a typed neutral resource, but the prompt still appears,
 * so the branch that actually fires is unknown. This probe records every decision on the path from
 * "request intercepted" to "download prompt shown" under one tag, so a single capture answers:
 *   - whether the iframe request even reaches onInterceptRequest, and how it is classified,
 *   - what response shape the ad-blocker returned for it,
 *   - and whether ArkWeb still raised a WebDownloadItem / onDownloadStart for that URL.
 *
 * Like the navigation probe, this module imports no platform kit: several build guards load core
 * browser modules in a sandbox that rejects platform dependencies. The HiLog writer is installed
 * once from the ability through {@link AiraDownloadTriggerProbe.install}.
 *
 * Everything recorded is either a URL the user is already browsing or a bounded enum/flag. Remove
 * this probe together with its call sites once the branch is identified.
 */
export type AiraDownloadTriggerWriter = (line: string) => void;

export class AiraDownloadTriggerProbe {
  private static writer?: AiraDownloadTriggerWriter = undefined;
  private static sequence: number = 0;

  static install(writer: AiraDownloadTriggerWriter): void {
    AiraDownloadTriggerProbe.writer = writer;
  }

  static log(event: string, detail: string): void {
    const writer = AiraDownloadTriggerProbe.writer;
    if (writer === undefined) {
      return;
    }
    AiraDownloadTriggerProbe.sequence += 1;
    try {
      writer(`seq=${AiraDownloadTriggerProbe.sequence} event=${event} ${detail}`);
    } catch (_error) {
    }
  }

  /** One onInterceptRequest decision for a request the ad-blocker looked at. */
  static logInterceptDecision(
    url: string,
    isMainFrame: boolean,
    resourceType: string,
    filteringEnabled: boolean,
    blocked: boolean,
    redirected: boolean,
    responseShape: string
  ): void {
    AiraDownloadTriggerProbe.log(
      'intercept',
      `main_frame=${isMainFrame ? 1 : 0} type=${resourceType} filtering=${filteringEnabled ? 1 : 0} ` +
        `blocked=${blocked ? 1 : 0} redirected=${redirected ? 1 : 0} response=${responseShape} url=${url}`
    );
  }

  /** The block decision was skipped before classification (filtering off or non-http url). */
  static logInterceptSkipped(url: string, isMainFrame: boolean, reason: string): void {
    AiraDownloadTriggerProbe.log(
      'intercept_skip',
      `main_frame=${isMainFrame ? 1 : 0} reason=${reason} url=${url}`
    );
  }

  /** A raw WebDownloadItem event straight from the ArkWeb download delegate. */
  static logPlatformDownloadEvent(
    type: string,
    url: string,
    mimeType: string,
    contentDisposition: string,
    referer: string,
    suggestedFileName: string,
    method: string,
    guid: string,
    state: string
  ): void {
    AiraDownloadTriggerProbe.log(
      'platform_event',
      `type=${type} method=${method} mime=${mimeType} disposition=${contentDisposition} ` +
        `filename=${suggestedFileName} referer=${referer} guid=${guid} state=${state} url=${url}`
    );
  }

  /** The Web component's onDownloadStart callback. */
  static logOnDownloadStart(url: string, mimeType: string, contentDisposition: string, contentLength: string): void {
    AiraDownloadTriggerProbe.log(
      'on_download_start',
      `mime=${mimeType} disposition=${contentDisposition} length=${contentLength} url=${url}`
    );
  }

  /** A captured download request entering the V2 pipeline, with the prompt decision. */
  static logCapture(guid: string, url: string, requiresConfirmation: boolean, source: string): void {
    AiraDownloadTriggerProbe.log(
      'capture',
      `source=${source} prompt=${requiresConfirmation ? 1 : 0} guid=${guid} url=${url}`
    );
  }
}
