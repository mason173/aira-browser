import {
  MediaCandidate,
  MediaCandidateKind,
  MediaEvidence,
  MediaSignalSourceKind
} from '../../features/mediaDiscovery/MediaCandidateModels';
import {
  MediaCandidateValidationResult,
  MediaValidationFailureCode,
  MediaValidationGraphSummary,
  MediaValidationHlsVariantSummary,
  MediaValidationKind,
  MediaValidationProbeEvidence,
  MediaValidationProbeKind,
  MediaValidationState
} from '../../features/mediaDiscovery/MediaCandidateValidationModels';
import {
  MediaManifestRequestContext,
  MediaManifestSummary
} from '../../features/mediaDiscovery/MediaManifestModels';
import {
  MediaCandidateHttpProbeService,
  MediaHttpProbeInput,
  MediaHttpProbeResult
} from './MediaCandidateHttpProbeService';
import { MediaCandidateValidationFingerprintService } from './MediaCandidateValidationFingerprintService';
import { MediaManifestProcessingService } from './MediaManifestProcessingService';
import { WebCookieHeaderService } from '../web/WebCookieHeaderService';

const VALIDATION_MANIFEST_MAX_BYTES: number = 1024 * 1024;
const VALIDATION_PROBE_TIMEOUT_MS: number = 5000;

interface MediaHlsChildProbeTarget {
  kind: MediaValidationProbeKind;
  url: string;
}

interface MediaHlsChildProbeResult {
  probe: MediaHttpProbeResult;
  evidence: MediaValidationProbeEvidence[];
}

interface MediaHlsEstimateBitrate {
  bitrate: number;
  source?: 'average_bandwidth' | 'declared_bandwidth' | 'url_hint';
}

export class MediaCandidateValidationService {
  private manifestService: MediaManifestProcessingService;
  private httpProbeService: MediaCandidateHttpProbeService;
  private cookieHeaderService: WebCookieHeaderService;
  private fingerprintService: MediaCandidateValidationFingerprintService = new MediaCandidateValidationFingerprintService();

  constructor(
    manifestService: MediaManifestProcessingService = new MediaManifestProcessingService(),
    httpProbeService: MediaCandidateHttpProbeService = new MediaCandidateHttpProbeService(),
    cookieHeaderService: WebCookieHeaderService = new WebCookieHeaderService()
  ) {
    this.manifestService = manifestService;
    this.httpProbeService = httpProbeService;
    this.cookieHeaderService = cookieHeaderService;
  }

  buildFingerprint(candidate: MediaCandidate): string {
    return this.fingerprintService.build(candidate);
  }

  shouldValidate(candidate: MediaCandidate, _now: number): boolean {
    if (this.isTrustedNativeCandidate(candidate)) {
      return false;
    }
    if (candidate.kind === 'hls' || candidate.kind === 'dash' || candidate.acquisition?.mode === 'paired_adaptive') {
      return true;
    }
    if (this.isProgressiveKind(candidate.kind, candidate.acquisition?.mode)) {
      return true;
    }
    return candidate.manifestContext?.manifestText !== undefined;
  }

  async validate(candidate: MediaCandidate): Promise<MediaCandidateValidationResult> {
    const fingerprint = this.buildFingerprint(candidate);
    try {
      if (this.isTrustedNativeCandidate(candidate)) {
        return this.validateTrustedCandidate(candidate, fingerprint);
      }
      if (candidate.kind === 'hls' || this.hasCapturedHlsManifest(candidate)) {
        return await this.validateHls(candidate, fingerprint);
      }
      if (candidate.kind === 'dash' || candidate.acquisition?.mode === 'paired_adaptive') {
        return await this.validateDash(candidate, fingerprint);
      }
      if (this.isProgressiveKind(candidate.kind, candidate.acquisition?.mode)) {
        return await this.validateProgressive(candidate, fingerprint);
      }
      return this.fail(candidate, fingerprint, 'web_only', 'unsupported', 'unsupported_delivery',
        '不是当前视频识别支持的媒体类型。', []);
    } catch (error) {
      return this.fail(candidate, fingerprint, 'web_only', 'failed', 'unknown',
        this.stringifyError(error as Error), []);
    }
  }

  buildUnexpectedFailure(candidate: MediaCandidate, fingerprint: string, message: string): MediaCandidateValidationResult {
    return this.fail(candidate, fingerprint, 'web_only', 'failed', 'unknown', message, []);
  }

  private validateTrustedCandidate(candidate: MediaCandidate, fingerprint: string): MediaCandidateValidationResult {
    if (!this.isHttpUrl(candidate.url)) {
      return this.fail(candidate, fingerprint, 'site_native_identity', 'unsupported', 'non_http_url',
        '站点原生候选缺少可播放的网络地址。', []);
    }
    return this.playable(candidate, fingerprint, 'site_native_identity', [{
      kind: 'site_native_identity',
      url: candidate.url,
      ok: true,
      message: this.trustedCandidateReason(candidate)
    }], { role: 'progressive' });
  }

  private async validateProgressive(
    candidate: MediaCandidate,
    fingerprint: string
  ): Promise<MediaCandidateValidationResult> {
    if (!this.isHttpUrl(candidate.url)) {
      return this.fail(candidate, fingerprint, 'progressive_http', 'unsupported', 'non_http_url',
        '直连视频地址不是 http/https。', []);
    }
    const mimeType = this.normalizeMime(candidate.playbackMetadata?.mimeType);
    if (this.canTrustProgressiveMimeWithoutProbe(candidate, mimeType)) {
      return this.playable(candidate, fingerprint, 'progressive_http', [{
        kind: 'response_header',
        url: candidate.url,
        ok: true,
        contentType: mimeType
      }], { role: 'progressive' });
    }
    const probe = await this.httpProbeService.probeBytes(this.buildProbeInput(candidate, candidate.url));
    const evidence = [this.probeEvidence('first_bytes', candidate.url, probe)];
    if (!probe.ok) {
      return this.fail(candidate, fingerprint, 'progressive_http', this.failureStateFromStatus(probe.statusCode),
        this.failureCodeFromStatus(probe.statusCode, 'range_probe_failed'), '视频字节探测失败。', evidence);
    }
    if (this.isHtmlLikeResponse(probe)) {
      return this.fail(candidate, fingerprint, 'progressive_http', 'failed', 'html_response',
        '探测结果是网页内容，不是视频。', evidence);
    }
    if (!this.isAcceptableProgressiveProbe(candidate, probe)) {
      return this.fail(candidate, fingerprint, 'progressive_http', 'unsupported', 'unsupported_codec',
        '没有确认到可交给原生播放器的视频字节。', evidence);
    }
    return this.playable(candidate, fingerprint, 'progressive_http', evidence, { role: 'progressive' });
  }

  private async validateHls(
    candidate: MediaCandidate,
    fingerprint: string
  ): Promise<MediaCandidateValidationResult> {
    const rootUrl = this.resolveManifestRootUrl(candidate);
    const capturedText = candidate.manifestContext?.manifestText?.trim() ?? '';
    const validationRootUrl = capturedText.length > 0 ?
      this.resolveCapturedHlsValidationRootUrl(candidate, rootUrl, capturedText) :
      rootUrl;
    if (!this.isHttpUrl(validationRootUrl)) {
      return this.fail(candidate, fingerprint, 'captured_hls_virtual_graph', 'unsupported', 'non_http_url',
        'HLS 清单缺少可验证的 http/https base URL。', []);
    }
    let manifestText = capturedText;
    const evidence: MediaValidationProbeEvidence[] = [];
    if (manifestText.length <= 0) {
      const fetch = await this.httpProbeService.fetchText(
        this.buildProbeInput(candidate, validationRootUrl, 'application/vnd.apple.mpegurl,application/x-mpegURL,*/*;q=0.8'),
        VALIDATION_MANIFEST_MAX_BYTES
      );
      evidence.push(this.probeEvidence('manifest_root', validationRootUrl, fetch));
      if (!fetch.ok || fetch.text.trim().length <= 0) {
        return this.fail(candidate, fingerprint, 'hls_resource_graph', this.failureStateFromStatus(fetch.statusCode),
          this.failureCodeFromStatus(fetch.statusCode, 'manifest_fetch_failed'), 'HLS 清单请求失败。', evidence);
      }
      manifestText = fetch.text.trim();
    } else {
      evidence.push({
        kind: 'manifest_root',
        url: validationRootUrl,
        ok: true,
        byteLength: manifestText.length,
        message: 'captured_manifest_text'
      });
    }
    if (!this.hasHlsHeader(manifestText)) {
      return this.fail(candidate, fingerprint, 'hls_resource_graph', 'failed', 'manifest_parse_failed',
        'HLS 清单缺少 #EXTM3U 头。', evidence);
    }
    const parseResult = await this.manifestService.parseText(
      manifestText,
      validationRootUrl,
      this.buildManifestContext(candidate, validationRootUrl)
    );
    if (!parseResult.ok || parseResult.summary === undefined) {
      return this.fail(candidate, fingerprint, 'hls_resource_graph', 'failed', 'manifest_parse_failed',
        parseResult.errorMessage, evidence);
    }
    const summary = parseResult.summary;
    if (summary.kind === 'dash') {
      return this.validateDashSummary(candidate, fingerprint, evidence, summary);
    }
    const graph = this.graphFromManifestSummary(summary);
    if (summary.protectedContent) {
      return this.fail(candidate, fingerprint, this.hlsValidationKind(candidate), 'protected', 'protected_drm',
        'HLS 清单包含当前不支持的 DRM/受保护片段。', evidence, graph);
    }
    if (summary.encrypted && summary.keyUrls.length > 0) {
      const keyProbe = await this.httpProbeService.probeBytes(this.buildProbeInput(candidate, summary.keyUrls[0]));
      evidence.push(this.probeEvidence('hls_key', summary.keyUrls[0], keyProbe));
      if (!keyProbe.ok) {
        if (this.canUseCapturedHlsPageFetchFallback(candidate, keyProbe)) {
          this.appendCapturedHlsFallbackEvidence(evidence, candidate, summary.keyUrls[0], 'hls_key_page_fetch_fallback');
        } else {
          return this.fail(candidate, fingerprint, this.hlsValidationKind(candidate),
            this.failureStateFromStatus(keyProbe.statusCode),
            this.failureCodeFromStatus(keyProbe.statusCode, 'key_resource_failed'), 'HLS key 请求失败。', evidence, graph);
        }
      }
    }
    const childProbeTarget = this.resolveHlsChildProbeTarget(summary);
    if (childProbeTarget.url.length <= 0) {
      return this.fail(candidate, fingerprint, this.hlsValidationKind(candidate), 'failed', 'child_resource_failed',
        'HLS 清单没有可验证的分片或初始化片段。', evidence, graph);
    }
    const childProbeResult = await this.probeHlsChildTarget(candidate, childProbeTarget);
    const childProbe = childProbeResult.probe;
    this.appendEvidence(evidence, childProbeResult.evidence);
    if (!this.isValidHlsChildProbe(childProbe)) {
      const alternateResult = capturedText.length > 0 ? await this.validateCapturedHlsAlternateRoots(
        candidate,
        fingerprint,
        manifestText,
        validationRootUrl
      ) : undefined;
      if (alternateResult !== undefined) {
        return alternateResult;
      }
      if (this.canUseCapturedHlsPageFetchFallback(candidate, childProbe)) {
        return this.playableCapturedHlsWithPageFetchFallback(
          candidate,
          fingerprint,
          evidence,
          graph,
          validationRootUrl,
          childProbe
        );
      }
      if (childProbe.ok) {
        return this.fail(candidate, fingerprint, this.hlsValidationKind(candidate), 'failed', 'child_resource_failed',
          'HLS 子资源不是可播放媒体内容。', evidence, graph);
      }
      return this.fail(candidate, fingerprint, this.hlsValidationKind(candidate),
        this.failureStateFromStatus(childProbe.statusCode),
        this.failureCodeFromStatus(childProbe.statusCode, 'child_resource_failed'), 'HLS 子资源请求失败。', evidence, graph);
    }
    return this.playable(candidate, fingerprint, this.hlsValidationKind(candidate), evidence, graph, validationRootUrl);
  }

  private async validateCapturedHlsAlternateRoots(
    candidate: MediaCandidate,
    fingerprint: string,
    manifestText: string,
    primaryRootUrl: string
  ): Promise<MediaCandidateValidationResult | undefined> {
    const roots = this.buildCapturedHlsAlternateValidationRootUrls(candidate, primaryRootUrl, manifestText);
    for (let i = 0; i < roots.length; i++) {
      const rootUrl = roots[i];
      const evidence: MediaValidationProbeEvidence[] = [{
        kind: 'manifest_root',
        url: rootUrl,
        ok: true,
        byteLength: manifestText.length,
        message: 'captured_manifest_text_alternate_base'
      }];
      const parseResult = await this.manifestService.parseText(
        manifestText,
        rootUrl,
        this.buildManifestContext(candidate, rootUrl)
      );
      if (!parseResult.ok || parseResult.summary === undefined) {
        continue;
      }
      const summary = parseResult.summary;
      if (summary.kind === 'dash' || summary.protectedContent) {
        continue;
      }
      const graph = this.graphFromManifestSummary(summary);
      if (summary.encrypted && summary.keyUrls.length > 0) {
        const keyProbe = await this.httpProbeService.probeBytes(this.buildProbeInput(candidate, summary.keyUrls[0]));
        evidence.push(this.probeEvidence('hls_key', summary.keyUrls[0], keyProbe));
        if (!keyProbe.ok) {
          continue;
        }
      }
      const childProbeTarget = this.resolveHlsChildProbeTarget(summary);
      if (childProbeTarget.url.length <= 0) {
        continue;
      }
      const childProbeResult = await this.probeHlsChildTarget(candidate, childProbeTarget);
      const childProbe = childProbeResult.probe;
      this.appendEvidence(evidence, childProbeResult.evidence);
      if (!childProbe.ok || this.isHtmlLikeResponse(childProbe) || !this.isAcceptableHlsChildProbe(childProbe)) {
        continue;
      }
      return this.playable(candidate, fingerprint, 'captured_hls_virtual_graph', evidence, graph, rootUrl);
    }
    return undefined;
  }

  private playableCapturedHlsWithPageFetchFallback(
    candidate: MediaCandidate,
    fingerprint: string,
    evidence: MediaValidationProbeEvidence[],
    graph: MediaValidationGraphSummary,
    manifestBaseUrl: string,
    probe: MediaHttpProbeResult
  ): MediaCandidateValidationResult {
    this.appendCapturedHlsFallbackEvidence(evidence, candidate, candidate.pageUrl, 'page_runtime_fetch_fallback_required');
    return this.playable(candidate, fingerprint, 'captured_hls_virtual_graph', evidence, graph, manifestBaseUrl);
  }

  private async validateDash(
    candidate: MediaCandidate,
    fingerprint: string
  ): Promise<MediaCandidateValidationResult> {
    if (this.isTrustedNativeCandidate(candidate)) {
      return this.validateTrustedCandidate(candidate, fingerprint);
    }
    const rootUrl = this.resolveManifestRootUrl(candidate);
    if (!this.isHttpUrl(rootUrl)) {
      return this.fail(candidate, fingerprint, 'dash_resource_graph', 'unsupported', 'non_http_url',
        'DASH 清单缺少可验证的网络地址。', []);
    }
    const evidence: MediaValidationProbeEvidence[] = [];
    const manifestText = candidate.manifestContext?.manifestText?.trim() ?? '';
    if (manifestText.length > 0 && this.looksLikeDashText(manifestText)) {
      return this.dashResourceOnly(candidate, fingerprint, evidence, rootUrl);
    }
    const fetch = await this.httpProbeService.fetchText(
      this.buildProbeInput(candidate, rootUrl, 'application/dash+xml,*/*;q=0.8'),
      VALIDATION_MANIFEST_MAX_BYTES
    );
    evidence.push(this.probeEvidence('manifest_root', rootUrl, fetch));
    if (!fetch.ok || !this.looksLikeDashText(fetch.text)) {
      return this.fail(candidate, fingerprint, 'dash_resource_graph', 'unsupported', 'unsupported_delivery',
        '通用 DASH 暂未确认到可直接原生播放的资源图。', evidence);
    }
    return this.dashResourceOnly(candidate, fingerprint, evidence, rootUrl);
  }

  private validateDashSummary(
    candidate: MediaCandidate,
    fingerprint: string,
    evidence: MediaValidationProbeEvidence[],
    summary: MediaManifestSummary
  ): MediaCandidateValidationResult {
    return this.fail(candidate, fingerprint, 'dash_resource_graph', 'validated_resource_only', 'unsupported_delivery',
      'DASH/MPD 已识别，但通用 DASH 资源图解析后续再接入。', evidence, {
        role: 'dash',
        variantCount: summary.variantCount
      });
  }

  private dashResourceOnly(
    candidate: MediaCandidate,
    fingerprint: string,
    evidence: MediaValidationProbeEvidence[],
    rootUrl: string
  ): MediaCandidateValidationResult {
    return this.fail(candidate, fingerprint, 'dash_resource_graph', 'validated_resource_only', 'unsupported_delivery',
      'DASH/MPD 已识别，但通用 DASH 资源图解析后续再接入。', evidence, {
        role: 'dash',
        sampleSegmentUrl: rootUrl
      });
  }

  private playable(
    candidate: MediaCandidate,
    fingerprint: string,
    kind: MediaValidationKind,
    evidence: MediaValidationProbeEvidence[],
    graph?: MediaValidationGraphSummary,
    manifestBaseUrl?: string
  ): MediaCandidateValidationResult {
    return {
      candidateId: candidate.id,
      tabId: candidate.tabId,
      fingerprint: fingerprint,
      snapshot: {
        state: 'validated_playable',
        kind: kind,
        fingerprint: fingerprint,
        validatedAt: Date.now(),
        playableUrl: candidate.url,
        manifestBaseUrl: manifestBaseUrl ?? candidate.manifestContext?.manifestBaseUrl,
        failureCode: 'none',
        failureMessage: '',
        graph: graph,
        evidence: evidence
      }
    };
  }

  private fail(
    candidate: MediaCandidate,
    fingerprint: string,
    kind: MediaValidationKind,
    state: MediaValidationState,
    code: MediaValidationFailureCode,
    message: string,
    evidence: MediaValidationProbeEvidence[],
    graph?: MediaValidationGraphSummary
  ): MediaCandidateValidationResult {
    return {
      candidateId: candidate.id,
      tabId: candidate.tabId,
      fingerprint: fingerprint,
      snapshot: {
        state: state,
        kind: kind,
        fingerprint: fingerprint,
        validatedAt: Date.now(),
        manifestBaseUrl: candidate.manifestContext?.manifestBaseUrl,
        failureCode: code,
        failureMessage: message,
        graph: graph,
        evidence: evidence
      }
    };
  }

  private buildProbeInput(candidate: MediaCandidate, url: string, accept?: string): MediaHttpProbeInput {
    return {
      url: url,
      referer: candidate.authContext?.referer ?? candidate.authContext?.pageUrl,
      userAgent: candidate.authContext?.userAgent,
      originUrl: candidate.authContext?.originUrl,
      requestHeaders: candidate.authContext?.requestHeaders,
      timeoutMs: VALIDATION_PROBE_TIMEOUT_MS,
      accept: accept
    };
  }

  private buildManifestContext(candidate: MediaCandidate, url: string): MediaManifestRequestContext {
    return {
      url: url,
      referer: candidate.authContext?.referer ?? candidate.authContext?.pageUrl,
      userAgent: candidate.authContext?.userAgent,
      originUrl: candidate.authContext?.originUrl,
      requestHeaders: candidate.authContext?.requestHeaders
    };
  }

  private probeEvidence(
    kind: MediaValidationProbeKind,
    url: string,
    probe: MediaHttpProbeResult
  ): MediaValidationProbeEvidence {
    return {
      kind: kind,
      url: url,
      ok: probe.ok,
      statusCode: probe.statusCode,
      contentType: probe.contentType,
      contentLength: probe.contentLength,
      byteLength: probe.bytes.byteLength > 0 ? probe.bytes.byteLength : probe.text.length,
      message: probe.errorMessage
    };
  }

  private graphFromManifestSummary(summary: MediaManifestSummary): MediaValidationGraphSummary {
    const variantUrls: string[] = [];
    const hlsVariants: MediaValidationHlsVariantSummary[] = [];
    for (let i = 0; i < summary.variants.length; i++) {
      const variant = summary.variants[i];
      const variantUrl = variant.url.trim();
      if (variantUrl.length > 0) {
        variantUrls.push(variantUrl);
        const estimatedBitrate = this.resolveHlsEstimateBitrate(
          variantUrl,
          variant.averageBandwidth,
          variant.bandwidth
        );
        const estimatedTotalBytes = this.estimateHlsTotalBytes(
          variant.durationSeconds,
          estimatedBitrate.bitrate
        );
        hlsVariants.push({
          url: variantUrl,
          bandwidth: variant.bandwidth > 0 ? variant.bandwidth : undefined,
          averageBandwidth: variant.averageBandwidth > 0 ? variant.averageBandwidth : undefined,
          estimatedBitrate: estimatedBitrate.bitrate > 0 ? estimatedBitrate.bitrate : undefined,
          bitrateEstimateSource: estimatedBitrate.source,
          durationSeconds: variant.durationSeconds > 0 ? variant.durationSeconds : undefined,
          estimatedTotalBytes: estimatedTotalBytes
        });
      }
    }
    return {
      role: summary.role === 'dash' ? 'dash' : (summary.role === 'master' ? 'master' : 'media'),
      variantUrls: variantUrls,
      hlsVariants: hlsVariants,
      variantCount: summary.variantCount,
      probedVariantCount: this.countProbedVariants(summary),
      segmentCount: summary.segmentCount,
      durationSeconds: summary.durationSeconds > 0 ? summary.durationSeconds : undefined,
      sampleSegmentUrl: summary.sampleSegments.length > 0 ? summary.sampleSegments[0] : undefined,
      mapUrl: summary.mapUrls.length > 0 ? summary.mapUrls[0] : undefined,
      keyUrl: summary.keyUrls.length > 0 ? summary.keyUrls[0] : undefined,
      encrypted: summary.encrypted,
      protectedContent: summary.protectedContent
    };
  }

  private estimateHlsTotalBytes(
    durationSeconds: number,
    bitsPerSecond: number
  ): number | undefined {
    if (!Number.isFinite(durationSeconds) || durationSeconds <= 0 ||
      !Number.isFinite(bitsPerSecond) || bitsPerSecond <= 0) {
      return undefined;
    }
    const bytes = durationSeconds * bitsPerSecond / 8;
    return Number.isFinite(bytes) && bytes > 0 ? Math.floor(bytes) : undefined;
  }

  private resolveHlsEstimateBitrate(
    variantUrl: string,
    averageBandwidth: number,
    bandwidth: number
  ): MediaHlsEstimateBitrate {
    const minimumPlausibleBitrate = 16000;
    if (Number.isFinite(averageBandwidth) && averageBandwidth >= minimumPlausibleBitrate) {
      return { bitrate: averageBandwidth, source: 'average_bandwidth' };
    }
    if (Number.isFinite(bandwidth) && bandwidth >= minimumPlausibleBitrate) {
      return { bitrate: bandwidth, source: 'declared_bandwidth' };
    }
    const inferred = this.inferHlsBitrateFromUrl(variantUrl);
    return inferred > 0 ? { bitrate: inferred, source: 'url_hint' } : { bitrate: 0 };
  }

  private inferHlsBitrateFromUrl(url: string): number {
    const match = url.match(/(?:^|[\/_-])(\d{2,6})k(?:bps)?(?:[\/_.-]|$)/i);
    if (match === null || match.length < 2) {
      return 0;
    }
    const kilobitsPerSecond = Number(match[1]);
    if (!Number.isFinite(kilobitsPerSecond) || kilobitsPerSecond < 16 || kilobitsPerSecond > 100000) {
      return 0;
    }
    return Math.floor(kilobitsPerSecond * 1000);
  }

  private countProbedVariants(summary: MediaManifestSummary): number {
    let count = 0;
    for (let i = 0; i < summary.variants.length; i++) {
      if ((summary.variants[i].segmentCount ?? 0) > 0) {
        count += 1;
      }
    }
    return count;
  }

  private resolveHlsChildProbeTarget(summary: MediaManifestSummary): MediaHlsChildProbeTarget {
    if (summary.mapUrls.length > 0) {
      return { kind: 'hls_map', url: summary.mapUrls[0] };
    }
    if (summary.sampleSegments.length > 0) {
      return { kind: 'hls_segment', url: summary.sampleSegments[0] };
    }
    for (let i = 0; i < summary.variants.length; i++) {
      const variantSegments = summary.variants[i].sampleSegments ?? [];
      if (variantSegments.length > 0) {
        return { kind: 'hls_segment', url: variantSegments[0] };
      }
      const variantMaps = summary.variants[i].mapUrls ?? [];
      if (variantMaps.length > 0) {
        return { kind: 'hls_map', url: variantMaps[0] };
      }
    }
    return { kind: 'hls_segment', url: '' };
  }

  private async probeHlsChildTarget(
    candidate: MediaCandidate,
    target: MediaHlsChildProbeTarget
  ): Promise<MediaHlsChildProbeResult> {
    const rangedProbe = await this.httpProbeService.probeBytes(this.buildProbeInput(candidate, target.url));
    const evidence: MediaValidationProbeEvidence[] = [this.probeEvidence(target.kind, target.url, rangedProbe)];
    if (!this.shouldRetryHlsChildProbeWithoutRange(rangedProbe)) {
      return { probe: rangedProbe, evidence: evidence };
    }
    const noRangeInput = this.buildProbeInput(candidate, target.url);
    noRangeInput.useRange = false;
    const noRangeProbe = await this.httpProbeService.probeBytes(noRangeInput);
    const retryEvidence = this.probeEvidence(target.kind, target.url, noRangeProbe);
    retryEvidence.message = 'no_range_retry';
    evidence.push(retryEvidence);
    return { probe: noRangeProbe, evidence: evidence };
  }

  private shouldRetryHlsChildProbeWithoutRange(probe: MediaHttpProbeResult): boolean {
    if (this.isValidHlsChildProbe(probe)) {
      return false;
    }
    return probe.statusCode === 0 ||
      probe.statusCode === 403 ||
      probe.statusCode === 405 ||
      probe.statusCode === 416 ||
      this.isHtmlLikeResponse(probe);
  }

  private isValidHlsChildProbe(probe: MediaHttpProbeResult): boolean {
    return probe.ok && !this.isHtmlLikeResponse(probe) && this.isAcceptableHlsChildProbe(probe);
  }

  private appendEvidence(target: MediaValidationProbeEvidence[], values: MediaValidationProbeEvidence[]): void {
    for (let i = 0; i < values.length; i++) {
      target.push(values[i]);
    }
  }

  private appendCapturedHlsFallbackEvidence(
    evidence: MediaValidationProbeEvidence[],
    candidate: MediaCandidate,
    url: string,
    message: string
  ): void {
    evidence.push({
      kind: 'media_element',
      url: url.trim().length > 0 ? url : candidate.pageUrl,
      ok: true,
      message: message
    });
  }

  private resolveManifestRootUrl(candidate: MediaCandidate): string {
    const baseUrl = candidate.manifestContext?.manifestBaseUrl?.trim() ?? '';
    return baseUrl.length > 0 ? baseUrl : candidate.url.trim();
  }

  private resolveCapturedHlsValidationRootUrl(
    candidate: MediaCandidate,
    rootUrl: string,
    manifestText: string
  ): string {
    if (this.isHttpUrl(rootUrl)) {
      return rootUrl;
    }
    const firstAbsoluteResourceUrl = this.firstHttpResourceUrlFromHlsText(manifestText);
    if (firstAbsoluteResourceUrl.length > 0) {
      return this.syntheticManifestUrlForResource(firstAbsoluteResourceUrl);
    }
    const pageUrl = candidate.pageUrl.trim();
    return this.isHttpUrl(pageUrl) ? pageUrl : rootUrl;
  }

  private buildCapturedHlsAlternateValidationRootUrls(
    candidate: MediaCandidate,
    primaryRootUrl: string,
    manifestText: string
  ): string[] {
    const roots: string[] = [];
    this.appendCapturedHlsAlternateRoot(roots, candidate.manifestContext?.manifestBaseUrl, primaryRootUrl);
    this.appendCapturedHlsAlternateRoot(roots, candidate.url, primaryRootUrl);
    this.appendCapturedHlsAlternateRoot(roots, candidate.pageUrl, primaryRootUrl);
    this.appendCapturedHlsAlternateRoot(roots, this.firstHttpResourceUrlFromHlsText(manifestText), primaryRootUrl);
    return roots;
  }

  private appendCapturedHlsAlternateRoot(
    roots: string[],
    sourceUrl: string | undefined,
    primaryRootUrl: string
  ): void {
    const normalized = sourceUrl?.trim() ?? '';
    if (!this.isHttpUrl(normalized) || this.isHlsManifestUrl(normalized)) {
      return;
    }
    const origin = this.extractOrigin(normalized);
    if (origin.length <= 0) {
      return;
    }
    const rootUrl = origin + '/__aira_captured__.m3u8';
    if (this.sameUrl(rootUrl, primaryRootUrl)) {
      return;
    }
    for (let i = 0; i < roots.length; i++) {
      if (this.sameUrl(roots[i], rootUrl)) {
        return;
      }
    }
    roots.push(rootUrl);
  }

  private firstHttpResourceUrlFromHlsText(text: string): string {
    const lines = text.replace(/\r/g, '').split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length <= 0) {
        continue;
      }
      const attrUrl = this.firstHttpUriAttribute(line);
      if (attrUrl.length > 0) {
        return attrUrl;
      }
      if (!line.startsWith('#') && this.isHttpUrl(line)) {
        return line;
      }
    }
    return '';
  }

  private firstHttpUriAttribute(line: string): string {
    const doubleQuoted = this.firstHttpUriAttributeForQuote(line, '"');
    if (doubleQuoted.length > 0) {
      return doubleQuoted;
    }
    return this.firstHttpUriAttributeForQuote(line, "'");
  }

  private firstHttpUriAttributeForQuote(line: string, quote: string): string {
    const marker = 'URI=' + quote;
    const start = line.indexOf(marker);
    if (start < 0) {
      return '';
    }
    const valueStart = start + marker.length;
    const valueEnd = line.indexOf(quote, valueStart);
    if (valueEnd < 0) {
      return '';
    }
    const value = line.substring(valueStart, valueEnd).trim();
    return this.isHttpUrl(value) ? value : '';
  }

  private syntheticManifestUrlForResource(resourceUrl: string): string {
    const withoutFragment = this.removeUrlFragment(resourceUrl.trim());
    const withoutQuery = this.removeUrlQuery(withoutFragment);
    const slashIndex = withoutQuery.lastIndexOf('/');
    if (slashIndex < 0) {
      return resourceUrl;
    }
    return withoutQuery.substring(0, slashIndex + 1) + '__aira_captured__.m3u8';
  }

  private isHlsManifestUrl(url: string): boolean {
    const extension = this.resolveUrlExtension(url);
    return extension === 'm3u8' || extension === 'm3u';
  }

  private sameUrl(left: string, right: string): boolean {
    return left.trim() === right.trim();
  }

  private removeUrlQuery(url: string): string {
    const index = url.indexOf('?');
    return index >= 0 ? url.substring(0, index) : url;
  }

  private removeUrlFragment(url: string): string {
    const index = url.indexOf('#');
    return index >= 0 ? url.substring(0, index) : url;
  }

  private hlsValidationKind(candidate: MediaCandidate): MediaValidationKind {
    return this.hasCapturedHlsManifest(candidate) ?
      'captured_hls_virtual_graph' :
      'hls_resource_graph';
  }

  private hasCapturedHlsManifest(candidate: MediaCandidate): boolean {
    const text = candidate.manifestContext?.manifestText?.trim() ?? '';
    return text.indexOf('#EXTM3U') >= 0;
  }

  private hasHlsHeader(text: string): boolean {
    return text.substring(0, Math.min(text.length, 512)).indexOf('#EXTM3U') >= 0;
  }

  private looksLikeDashText(text: string): boolean {
    return text.substring(0, Math.min(text.length, 512)).toLowerCase().indexOf('<mpd') >= 0;
  }

  private isAcceptableProgressiveProbe(candidate: MediaCandidate, probe: MediaHttpProbeResult): boolean {
    const mime = this.normalizeMime(probe.contentType);
    if (this.isSupportedDirectVideoMime(mime) || mime === 'video/mp2t' || mime === 'application/octet-stream') {
      return true;
    }
    if (this.hasMp4Bytes(probe.bytes) || this.hasWebmBytes(probe.bytes) || this.hasTsBytes(probe.bytes)) {
      return true;
    }
    return this.hasStrongMediaEvidence(candidate.evidence) && !this.isRejectedContentType(mime);
  }

  private isAcceptableHlsChildProbe(probe: MediaHttpProbeResult): boolean {
    const mime = this.normalizeMime(probe.contentType);
    if (mime === 'video/mp2t' ||
      mime === 'video/mp4' ||
      mime === 'audio/aac' ||
      mime === 'application/octet-stream' ||
      mime === 'binary/octet-stream') {
      return true;
    }
    return this.hasMp4Bytes(probe.bytes) || this.hasTsBytes(probe.bytes) || this.hasAacBytes(probe.bytes);
  }

  private isHtmlLikeResponse(probe: MediaHttpProbeResult): boolean {
    const mime = this.normalizeMime(probe.contentType);
    if (this.isRejectedContentType(mime)) {
      return true;
    }
    const prefix = probe.textPrefix.trim().toLowerCase();
    return prefix.startsWith('<!doctype') ||
      prefix.startsWith('<html') ||
      prefix.startsWith('<script') ||
      prefix.startsWith('{') ||
      prefix.startsWith('[');
  }

  private canUseCapturedHlsPageFetchFallback(candidate: MediaCandidate, probe: MediaHttpProbeResult): boolean {
    if (!this.hasCapturedHlsManifest(candidate)) {
      return false;
    }
    return probe.statusCode === 0 ||
      probe.statusCode === 401 ||
      probe.statusCode === 403 ||
      this.isHtmlLikeResponse(probe);
  }

  private isRejectedContentType(mime: string): boolean {
    return mime === 'text/html' ||
      mime === 'application/xhtml+xml' ||
      mime === 'text/javascript' ||
      mime === 'application/javascript' ||
      mime === 'application/json' ||
      mime === 'application/manifest+json' ||
      mime.startsWith('image/');
  }

  private hasStrongMediaEvidence(evidence: MediaEvidence[]): boolean {
    for (let i = 0; i < evidence.length; i++) {
      if (evidence[i].kind === 'mime' || evidence[i].value === 'media_element') {
        return true;
      }
    }
    return false;
  }

  private isProgressiveKind(kind: MediaCandidateKind, acquisitionMode?: string): boolean {
    return kind === 'mp4' || kind === 'webm' || kind === 'mov' || acquisitionMode === 'progressive';
  }

  private isTrustedNativeCandidate(candidate: MediaCandidate): boolean {
    return candidate.nativeIdentity !== undefined ||
      candidate.source === 'site_extractor' ||
      candidate.source === 'video_adapter';
  }

  private trustedCandidateReason(candidate: MediaCandidate): string {
    if (candidate.nativeIdentity !== undefined) {
      return 'native_identity';
    }
    return this.sourceReason(candidate.source);
  }

  private sourceReason(source: MediaSignalSourceKind): string {
    switch (source) {
      case 'site_extractor': return 'site_extractor';
      case 'video_adapter': return 'video_adapter';
      default: return 'trusted';
    }
  }

  private isSupportedDirectVideoMime(mime: string): boolean {
    return mime === 'video/mp4' ||
      mime === 'video/webm' ||
      mime === 'video/quicktime' ||
      mime === 'video/x-m4v' ||
      mime === 'application/octet-stream-video';
  }

  private canTrustProgressiveMimeWithoutProbe(candidate: MediaCandidate, mime: string): boolean {
    if (!this.isSupportedDirectVideoMime(mime)) {
      return false;
    }
    return this.hasDirectVideoExtension(candidate.url) ||
      candidate.source === 'site_extractor' ||
      candidate.source === 'video_adapter';
  }

  private hasDirectVideoExtension(url: string): boolean {
    const extension = this.resolveUrlExtension(url);
    return extension === 'mp4' ||
      extension === 'm4v' ||
      extension === 'mov' ||
      extension === 'webm';
  }

  private resolveUrlExtension(url: string): string {
    const clean = this.removeUrlQuery(this.removeUrlFragment(url.trim()));
    const slashIndex = clean.lastIndexOf('/');
    const fileName = slashIndex >= 0 ? clean.substring(slashIndex + 1) : clean;
    const dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex >= fileName.length - 1) {
      return '';
    }
    const extension = fileName.substring(dotIndex + 1).trim().toLowerCase();
    return extension.length > 0 && extension.length <= 8 ? extension : '';
  }

  private normalizeMime(mimeType: string | undefined): string {
    return (mimeType ?? '').split(';')[0].trim().toLowerCase();
  }

  private failureStateFromStatus(statusCode: number): MediaValidationState {
    if (statusCode === 401 || statusCode === 403 || statusCode === 410) {
      return 'expired';
    }
    return 'failed';
  }

  private failureCodeFromStatus(
    statusCode: number,
    fallback: MediaValidationFailureCode
  ): MediaValidationFailureCode {
    if (statusCode === 401 || statusCode === 403 || statusCode === 410) {
      return 'expired_url';
    }
    if (statusCode === 0) {
      return 'probe_timeout';
    }
    return fallback;
  }

  private hasMp4Bytes(buffer: ArrayBuffer): boolean {
    const bytes = new Uint8Array(buffer);
    if (bytes.length < 12) {
      return false;
    }
    return bytes[4] === 0x66 && bytes[5] === 0x74 && bytes[6] === 0x79 && bytes[7] === 0x70;
  }

  private hasWebmBytes(buffer: ArrayBuffer): boolean {
    const bytes = new Uint8Array(buffer);
    return bytes.length >= 4 && bytes[0] === 0x1A && bytes[1] === 0x45 && bytes[2] === 0xDF && bytes[3] === 0xA3;
  }

  private hasTsBytes(buffer: ArrayBuffer): boolean {
    const bytes = new Uint8Array(buffer);
    return bytes.length > 188 && bytes[0] === 0x47 && bytes[188] === 0x47;
  }

  private hasAacBytes(buffer: ArrayBuffer): boolean {
    const bytes = new Uint8Array(buffer);
    return bytes.length >= 2 && bytes[0] === 0xFF && (bytes[1] & 0xF0) === 0xF0;
  }

  private isHttpUrl(url: string): boolean {
    const lower = url.trim().toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  private extractOrigin(url: string): string {
    const match = /^https?:\/\/[^/?#]+/i.exec(url.trim());
    return match !== null ? match[0] : '';
  }

  private stringifyError(error: Error): string {
    const message = error.message?.trim() ?? '';
    return message.length > 0 ? message : 'validation_failed';
  }
}
