import {
  MediaActionHint,
  MediaCandidate,
  MediaEvidence,
  MediaSignalSourceKind
} from '../../features/mediaDiscovery/MediaCandidateModels';
import {
  MediaResourceAction,
  MediaResourceFrameType,
  MediaResourceListItem,
  MediaResourceListProjection,
  MediaResourceSource,
  MediaResourceStatus,
  MediaResourceTabCounts,
  emptyMediaResourceTabCounts
} from '../../features/mediaDiscovery/MediaResourceProjectionModels';
import { MediaValidationHlsVariantSummary } from '../../features/mediaDiscovery/MediaCandidateValidationModels';
import {
  MediaHlsManifestEvidence,
  MediaHlsManifestTarget
} from '../../features/mediaDiscovery/MediaHlsProjectionModels';
import { MediaDownloadCandidate } from '../../features/mediaDiscovery/MediaDownloadProjectionModels';
import {
  MediaDiscoveryCandidateRecord,
  MediaDiscoveryTabSnapshot
} from './MediaDiscoveryStore';

const MIN_WEAK_OPAQUE_VIDEO_BYTES: number = 256 * 1024;

interface MediaProjectedMetrics {
  durationMs?: number;
  estimatedTotalBytes?: number;
}

export class MediaCandidateProjector {
  projectResourceList(
    snapshot: MediaDiscoveryTabSnapshot,
    _webVideoTakeoverEnabled: boolean
  ): MediaResourceListProjection {
    const graphCandidates = this.collectSurfaceCandidates(snapshot.records, snapshot.tabId);
    const candidates = this.sortedSurfaceCandidates(snapshot.records, snapshot.tabId);
    const items: MediaResourceListItem[] = [];
    for (let i = 0; i < candidates.length; i++) {
      if (!this.shouldShowInResourceList(candidates[i])) {
        continue;
      }
      items.push(this.projectResourceListItem(candidates[i], graphCandidates));
    }
    return {
      items: items,
      counts: this.countResourceListTabs(items)
    };
  }

  projectHlsManifestTargetById(
    snapshot: MediaDiscoveryTabSnapshot,
    candidateId: string
  ): MediaHlsManifestTarget | undefined {
    const candidate = this.findCandidateById(snapshot.records, candidateId, snapshot.tabId);
    if (candidate === undefined || !this.isStreamingManifestCandidate(candidate)) {
      return undefined;
    }
    return this.projectHlsManifestTarget(candidate);
  }

  projectDownloadCandidateById(
    snapshot: MediaDiscoveryTabSnapshot,
    candidateId: string
  ): MediaDownloadCandidate | undefined {
    const candidate = this.findCandidateById(snapshot.records, candidateId, snapshot.tabId);
    if (candidate === undefined || !this.isDownloadCandidate(candidate)) {
      return undefined;
    }
    return this.projectDownloadCandidate(
      candidate,
      this.collectSurfaceCandidates(snapshot.records, snapshot.tabId)
    );
  }

  private sortedSurfaceCandidates(records: MediaDiscoveryCandidateRecord[], tabId: string): MediaCandidate[] {
    const candidates = this.collectSurfaceCandidates(records, tabId);
    const visibleCandidates: MediaCandidate[] = [];
    for (let i = 0; i < candidates.length; i++) {
      if (!this.isAbsorbedPairedTrack(candidates[i], candidates) &&
        !this.isAbsorbedHlsMaster(candidates[i], candidates)) {
        visibleCandidates.push(candidates[i]);
      }
    }
    visibleCandidates.sort((a: MediaCandidate, b: MediaCandidate): number => {
      const priorityDifference = this.surfacePresentationPriority(b) - this.surfacePresentationPriority(a);
      if (priorityDifference !== 0) {
        return priorityDifference;
      }
      if (b.confidence !== a.confidence) {
        return b.confidence - a.confidence;
      }
      return b.lastSeenAt - a.lastSeenAt;
    });
    return visibleCandidates;
  }

  private collectSurfaceCandidates(records: MediaDiscoveryCandidateRecord[], tabId: string): MediaCandidate[] {
    const candidates: MediaCandidate[] = [];
    for (let i = 0; i < records.length; i++) {
      if (this.isCandidateForTab(records[i].candidate, tabId) && this.isSurfaceCandidate(records[i].candidate)) {
        candidates.push(records[i].candidate);
      }
    }
    return candidates;
  }

  private surfacePresentationPriority(candidate: MediaCandidate): number {
    if (!this.isPotentialVideoCandidate(candidate)) {
      return candidate.confidence;
    }
    let priority = 1000 + candidate.confidence;
    priority += candidate.family === 'video' ? 160 : candidate.family === 'manifest' ? 60 : 0;
    if (candidate.kind === 'mp4' || candidate.kind === 'webm' || candidate.kind === 'mov') {
      priority += 120;
    } else if (candidate.kind === 'hls' || candidate.kind === 'dash') {
      priority += 40;
    }
    priority += this.sourcePresentationBonus(candidate);
    priority += this.validationPresentationBonus(candidate);
    if (candidate.acquisition?.mode === 'paired_adaptive') {
      priority += 360;
    } else if (candidate.acquisition?.mode === 'progressive') {
      priority += 280;
    }
    if (this.hasEvidence(candidate.evidence, 'playback_state', 'playing')) {
      priority += 800;
    } else if (this.hasEvidence(candidate.evidence, 'playback_state', 'started')) {
      priority += 400;
    }
    if (this.hasEvidence(candidate.evidence, 'dom_signal', 'video_element')) {
      priority += 250;
    }
    if (this.hasEvidence(candidate.evidence, 'playback_visibility', 'visible')) {
      priority += 120;
    }
    if (this.hasEvidence(candidate.evidence, 'playback_readiness', 'current_data')) {
      priority += 100;
    }
    if ((candidate.playbackMetadata?.durationMs ?? 0) > 0) {
      priority += 220;
    }
    if ((candidate.playbackMetadata?.width ?? 0) > 0 && (candidate.playbackMetadata?.height ?? 0) > 0) {
      priority += 100;
    }
    if (this.hasEvidence(candidate.evidence, 'resource_evidence', 'weak_text_match')) {
      priority -= 300;
    } else if (this.hasEvidence(candidate.evidence, 'resource_evidence', 'generic_url_hint')) {
      priority -= 180;
    } else if (this.hasEvidence(candidate.evidence, 'resource_evidence', 'streaming_url_hint')) {
      priority -= 60;
    }
    if (this.hasEvidence(candidate.evidence, 'url_quality', 'noise')) {
      priority -= 600;
    }
    if (this.hasEvidenceKind(candidate.evidence, 'video_url_hint')) {
      priority -= 80;
    }
    return priority;
  }

  private sourcePresentationBonus(candidate: MediaCandidate): number {
    switch (candidate.source) {
      case 'site_extractor':
      case 'video_adapter': return 320;
      case 'arkweb_media_assistant': return 280;
      case 'video_dom': return 180;
      case 'resource_dom': return 100;
      case 'video_network': return 30;
      case 'resource_network': return 10;
      default: return 0;
    }
  }

  private validationPresentationBonus(candidate: MediaCandidate): number {
    if (candidate.playabilityState === 'playing_native') {
      return 650;
    }
    switch (candidate.validation?.state) {
      case 'validated_playable': return 500;
      case 'validated_resource_only': return 80;
      case 'protected':
      case 'expired':
      case 'unsupported':
      case 'failed': return -500;
      default:
        return candidate.playabilityState === 'playable' ? 350 : 0;
    }
  }

  private hasEvidence(evidence: MediaEvidence[], kind: string, value: string): boolean {
    for (let i = 0; i < evidence.length; i++) {
      if (evidence[i].kind === kind && evidence[i].value === value) {
        return true;
      }
    }
    return false;
  }

  private hasEvidenceKind(evidence: MediaEvidence[], kind: string): boolean {
    for (let i = 0; i < evidence.length; i++) {
      if (evidence[i].kind === kind) {
        return true;
      }
    }
    return false;
  }

  private isAbsorbedPairedTrack(candidate: MediaCandidate, candidates: MediaCandidate[]): boolean {
    const candidateUrl = candidate.url.trim();
    if (candidateUrl.length <= 0) {
      return false;
    }
    for (let i = 0; i < candidates.length; i++) {
      const parent = candidates[i];
      if (parent.id === candidate.id) {
        continue;
      }
      const acquisitionAudioUrl = parent.acquisition?.pairedTrack?.url.trim() ?? '';
      const manifestAudioUrl = parent.manifestContext?.pairedAudioUrl?.trim() ?? '';
      if ((acquisitionAudioUrl.length > 0 && acquisitionAudioUrl === candidateUrl) ||
        (manifestAudioUrl.length > 0 && manifestAudioUrl === candidateUrl)) {
        return true;
      }
    }
    return false;
  }

  private isAbsorbedHlsMaster(candidate: MediaCandidate, candidates: MediaCandidate[]): boolean {
    if (candidate.kind !== 'hls') {
      return false;
    }
    const childUrls = this.hlsChildPlaylistUrls(candidate);
    if (childUrls.length <= 0) {
      return false;
    }
    for (let i = 0; i < candidates.length; i++) {
      const child = candidates[i];
      if (child.id === candidate.id || child.kind !== 'hls') {
        continue;
      }
      if (this.containsEquivalentUrl(childUrls, child.url)) {
        return true;
      }
    }
    return false;
  }

  private hlsChildPlaylistUrls(candidate: MediaCandidate): string[] {
    const urls: string[] = [];
    const graph = candidate.validation?.graph;
    if (graph?.role === 'master' && graph.variantUrls !== undefined) {
      this.appendUniqueUrls(urls, graph.variantUrls);
    }
    const manifestText = candidate.manifestContext?.manifestText?.trim() ?? '';
    if (manifestText.length <= 0) {
      return urls;
    }
    const manifestBaseUrl = candidate.validation?.manifestBaseUrl?.trim() ??
      candidate.manifestContext?.manifestBaseUrl?.trim() ?? candidate.url.trim();
    const lines = manifestText.replace(/\r/g, '').split('\n');
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].trim().indexOf('#EXT-X-STREAM-INF:') !== 0) {
        continue;
      }
      const childLine = this.nextHlsResourceLine(lines, i + 1);
      const childUrl = this.resolveHlsChildUrl(manifestBaseUrl, childLine);
      if (childUrl.length > 0) {
        urls.push(childUrl);
      }
    }
    return urls;
  }

  private nextHlsResourceLine(lines: string[], start: number): string {
    for (let i = start; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length > 0 && !line.startsWith('#')) {
        return line;
      }
    }
    return '';
  }

  private resolveHlsChildUrl(baseUrl: string, resourceUrl: string): string {
    const resource = resourceUrl.trim();
    if (resource.length <= 0 || resource.startsWith('#')) {
      return '';
    }
    if (this.isHttpOrHttpsUrl(resource)) {
      return resource;
    }
    const schemeEnd = baseUrl.indexOf('://');
    if (schemeEnd < 0 || !this.isHttpOrHttpsUrl(baseUrl)) {
      return '';
    }
    const authorityEnd = baseUrl.indexOf('/', schemeEnd + 3);
    const origin = authorityEnd >= 0 ? baseUrl.substring(0, authorityEnd) : baseUrl;
    if (resource.indexOf('//') === 0) {
      return baseUrl.substring(0, schemeEnd) + ':' + resource;
    }
    if (resource.startsWith('/')) {
      return origin + resource;
    }
    const baseWithoutFragment = this.removeUrlFragment(baseUrl);
    const baseWithoutQuery = this.removeUrlQuery(baseWithoutFragment);
    const slashIndex = baseWithoutQuery.lastIndexOf('/');
    const directory = slashIndex >= 0 ? baseWithoutQuery.substring(0, slashIndex + 1) : origin + '/';
    return this.normalizeHlsPath(directory + resource);
  }

  private normalizeHlsPath(url: string): string {
    const schemeEnd = url.indexOf('://');
    if (schemeEnd < 0) {
      return url;
    }
    const authorityEnd = url.indexOf('/', schemeEnd + 3);
    if (authorityEnd < 0) {
      return url;
    }
    const origin = url.substring(0, authorityEnd);
    const pathAndSuffix = url.substring(authorityEnd);
    const suffixIndex = this.firstUrlSuffixIndex(pathAndSuffix);
    const path = suffixIndex >= 0 ? pathAndSuffix.substring(0, suffixIndex) : pathAndSuffix;
    const suffix = suffixIndex >= 0 ? pathAndSuffix.substring(suffixIndex) : '';
    const parts = path.split('/');
    const normalized: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      if (part.length <= 0 || part === '.') {
        continue;
      }
      if (part === '..') {
        if (normalized.length > 0) {
          normalized.pop();
        }
        continue;
      }
      normalized.push(part);
    }
    return origin + '/' + normalized.join('/') + suffix;
  }

  private firstUrlSuffixIndex(value: string): number {
    const queryIndex = value.indexOf('?');
    const fragmentIndex = value.indexOf('#');
    if (queryIndex < 0) {
      return fragmentIndex;
    }
    if (fragmentIndex < 0) {
      return queryIndex;
    }
    return Math.min(queryIndex, fragmentIndex);
  }

  private appendUniqueUrls(target: string[], values: string[]): void {
    for (let i = 0; i < values.length; i++) {
      const value = values[i].trim();
      if (value.length > 0 && !this.containsEquivalentUrl(target, value)) {
        target.push(value);
      }
    }
  }

  private containsEquivalentUrl(values: string[], target: string): boolean {
    const normalizedTarget = this.removeUrlFragment(target.trim());
    for (let i = 0; i < values.length; i++) {
      if (this.removeUrlFragment(values[i].trim()) === normalizedTarget) {
        return true;
      }
    }
    return false;
  }

  private removeUrlFragment(url: string): string {
    const index = url.indexOf('#');
    return index >= 0 ? url.substring(0, index) : url;
  }

  private removeUrlQuery(url: string): string {
    const index = url.indexOf('?');
    return index >= 0 ? url.substring(0, index) : url;
  }

  private isSurfaceCandidate(candidate: MediaCandidate): boolean {
    if (candidate.url.trim().length <= 0) {
      return false;
    }
    if (candidate.family !== 'unknown' || candidate.kind !== 'unknown') {
      return true;
    }
    return candidate.actionHints.length > 0;
  }

  private findCandidateById(
    records: MediaDiscoveryCandidateRecord[],
    candidateId: string,
    tabId: string
  ): MediaCandidate | undefined {
    const normalizedCandidateId = candidateId.trim();
    if (normalizedCandidateId.length <= 0) {
      return undefined;
    }
    for (let i = 0; i < records.length; i++) {
      const candidate = records[i].candidate;
      if (this.isCandidateForTab(candidate, tabId) && this.matchesCandidateId(candidate, normalizedCandidateId)) {
        return candidate;
      }
    }
    return undefined;
  }

  private isCandidateForTab(candidate: MediaCandidate, tabId: string): boolean {
    return tabId.trim().length <= 0 || candidate.tabId === tabId;
  }

  private shouldShowInResourceList(candidate: MediaCandidate): boolean {
    if (candidate.family === 'segment' || candidate.kind === 'segment') {
      return false;
    }
    if (this.isNonActionableBlobCandidate(candidate)) {
      return false;
    }
    if (this.isWeakSmallOpaqueVideoCandidate(candidate)) {
      return false;
    }
    if (candidate.family === 'image') {
      return this.isDisplayableImageCandidate(candidate);
    }
    return true;
  }

  private isNonActionableBlobCandidate(candidate: MediaCandidate): boolean {
    if (candidate.url.trim().toLowerCase().indexOf('blob:') !== 0) {
      return false;
    }
    const actions = this.mediaResourceActions(candidate);
    return actions.indexOf('download') < 0 && actions.indexOf('parse_manifest') < 0;
  }

  private isWeakSmallOpaqueVideoCandidate(candidate: MediaCandidate): boolean {
    const totalBytes = candidate.playbackMetadata?.totalBytes ?? 0;
    if (candidate.family !== 'video' || candidate.kind !== 'mp4' || totalBytes <= 0 ||
      totalBytes >= MIN_WEAK_OPAQUE_VIDEO_BYTES) {
      return false;
    }
    if (!this.hasEvidence(candidate.evidence, 'video_url_hint', 'opaque_media_path')) {
      return false;
    }
    if ((candidate.playbackMetadata?.durationMs ?? 0) > 0 ||
      (candidate.playbackMetadata?.width ?? 0) > 0 ||
      (candidate.playbackMetadata?.height ?? 0) > 0) {
      return false;
    }
    return !this.hasEvidence(candidate.evidence, 'resource_evidence', 'media_element') &&
      !this.hasEvidence(candidate.evidence, 'resource_evidence', 'explicit_extension') &&
      !this.hasEvidence(candidate.evidence, 'resource_evidence', 'mime');
  }

  private isDisplayableImageCandidate(candidate: MediaCandidate): boolean {
    if (!this.isHttpOrHttpsUrl(candidate.url)) {
      return false;
    }
    const mimeType = this.normalizedMimeType(candidate.playbackMetadata?.mimeType);
    const extension = candidate.playbackMetadata?.extension ?? this.resolveExtension(candidate.url);
    if (mimeType === 'image/svg+xml' || extension === 'svg') {
      return false;
    }
    if (candidate.playbackMetadata?.width !== undefined && candidate.playbackMetadata?.height !== undefined) {
      const width = candidate.playbackMetadata.width;
      const height = candidate.playbackMetadata.height;
      if (width > 0 && height > 0 && (width < 8 || height < 8)) {
        return false;
      }
      return true;
    }
    if (candidate.playbackMetadata?.totalBytes !== undefined && candidate.playbackMetadata.totalBytes > 0) {
      return candidate.playbackMetadata.totalBytes >= 1024;
    }
    if (candidate.source === 'resource_dom') {
      const domSignal = this.domSignalFromMediaEvidence(candidate.evidence);
      return domSignal === 'image_element';
    }
    return true;
  }

  private normalizedMimeType(mimeType: string | undefined): string {
    if (mimeType === undefined) {
      return '';
    }
    return mimeType.split(';')[0].trim().toLowerCase();
  }

  private domSignalFromMediaEvidence(evidence: MediaEvidence[]): string {
    for (let i = 0; i < evidence.length; i++) {
      if (evidence[i].kind === 'dom_signal') {
        return evidence[i].value;
      }
    }
    return '';
  }

  private matchesCandidateId(candidate: MediaCandidate, candidateId: string): boolean {
    return candidate.id === candidateId ||
      ('media:' + candidate.id) === candidateId ||
      ('video:media:' + candidate.id) === candidateId;
  }

  private projectResourceListItem(
    candidate: MediaCandidate,
    candidates: MediaCandidate[]
  ): MediaResourceListItem {
    const playbackMetadata = candidate.playbackMetadata;
    const projectedMetrics = this.projectedMediaMetrics(candidate, candidates);
    return {
      id: candidate.id,
      tabId: candidate.tabId,
      pageTitle: candidate.pageTitle,
      url: candidate.url,
      source: this.mediaResourceSource(candidate.source),
      frameType: this.mediaResourceFrameType(candidate.frameContext?.frameType),
      family: candidate.family,
      kind: candidate.kind,
      status: this.mediaResourceStatus(candidate),
      displayName: this.resourceDisplayNameForCandidate(candidate),
      sourceHost: playbackMetadata?.sourceHost ?? this.resolveHost(candidate.url),
      extension: playbackMetadata?.extension ?? this.resolveExtension(candidate.url),
      durationMs: projectedMetrics.durationMs,
      width: playbackMetadata?.width,
      height: playbackMetadata?.height,
      totalBytes: playbackMetadata?.totalBytes,
      estimatedTotalBytes: projectedMetrics.estimatedTotalBytes,
      posterUrl: playbackMetadata?.posterUrl,
      acquisition: candidate.acquisition,
      failureReason: this.failureReasonFromEvidence(candidate.evidence),
      actions: this.mediaResourceActions(candidate)
    };
  }

  private projectedMediaMetrics(candidate: MediaCandidate, candidates: MediaCandidate[]): MediaProjectedMetrics {
    let durationMs = (candidate.playbackMetadata?.durationMs ?? 0) > 0 ?
      candidate.playbackMetadata?.durationMs : undefined;
    if (candidate.kind !== 'hls') {
      return { durationMs: durationMs };
    }
    const graphDurationSeconds = candidate.validation?.graph?.durationSeconds ?? 0;
    if (durationMs === undefined && graphDurationSeconds > 0) {
      durationMs = Math.round(graphDurationSeconds * 1000);
    }
    const variant = this.resolveHlsVariantSummary(candidate, candidates);
    if (durationMs === undefined && (variant?.durationSeconds ?? 0) > 0) {
      durationMs = Math.round((variant?.durationSeconds ?? 0) * 1000);
    }
    return {
      durationMs: durationMs,
      estimatedTotalBytes: (variant?.estimatedTotalBytes ?? 0) > 0 ? variant?.estimatedTotalBytes : undefined
    };
  }

  private resolveHlsVariantSummary(
    candidate: MediaCandidate,
    candidates: MediaCandidate[]
  ): MediaValidationHlsVariantSummary | undefined {
    const ownGraph = candidate.validation?.graph;
    const ownVariants = ownGraph?.hlsVariants ?? [];
    if (ownGraph?.role === 'master' && ownVariants.length === 1) {
      return ownVariants[0];
    }
    for (let i = 0; i < candidates.length; i++) {
      const parent = candidates[i];
      if (parent.id === candidate.id || parent.kind !== 'hls' || parent.validation?.graph?.role !== 'master') {
        continue;
      }
      const variants = parent.validation?.graph?.hlsVariants ?? [];
      for (let j = 0; j < variants.length; j++) {
        if (this.containsEquivalentUrl([variants[j].url], candidate.url)) {
          return variants[j];
        }
      }
    }
    return undefined;
  }

  private countResourceListTabs(items: MediaResourceListItem[]): MediaResourceTabCounts {
    const counts = emptyMediaResourceTabCounts();
    counts.all = items.length;
    for (let i = 0; i < items.length; i++) {
      switch (items[i].family) {
        case 'video':
          counts.video += 1;
          break;
        case 'manifest':
        case 'segment':
          counts.manifest += 1;
          break;
        case 'audio':
          counts.audio += 1;
          break;
        case 'image':
          counts.image += 1;
          break;
        case 'file':
          counts.file += 1;
          break;
      }
    }
    return counts;
  }

  private mediaResourceActions(candidate: MediaCandidate): MediaResourceAction[] {
    return this.rawMediaResourceActions(candidate);
  }

  private rawMediaResourceActions(candidate: MediaCandidate): MediaResourceAction[] {
    const actions: MediaResourceAction[] = [];
    this.appendActionsFromHints(actions, candidate.actionHints);
    if (actions.length <= 0) {
      this.appendDerivedResourceActions(actions, candidate);
    }
    return actions;
  }

  private appendActionsFromHints(actions: MediaActionHint[], hints: MediaActionHint[]): void {
    for (let i = 0; i < hints.length; i++) {
      this.pushAction(actions, hints[i]);
    }
  }

  private appendDerivedResourceActions(actions: MediaActionHint[], candidate: MediaCandidate): void {
    if (!this.isHttpOrHttpsUrl(candidate.url)) {
      return;
    }
    if (candidate.downloadabilityState === 'manifest' || candidate.family === 'manifest') {
      if (candidate.kind === 'hls') {
        this.pushAction(actions, 'download');
      } else {
        this.pushAction(actions, 'parse_manifest');
      }
      this.pushAction(actions, 'copy');
      return;
    }
    if (candidate.downloadabilityState === 'downloadable' || candidate.downloadabilityState === 'needs_headers') {
      this.pushAction(actions, 'download');
      this.pushAction(actions, 'copy');
      return;
    }
    if (candidate.family !== 'segment') {
      this.pushAction(actions, 'download');
    }
    this.pushAction(actions, 'copy');
  }

  private pushAction(actions: MediaActionHint[], action: MediaActionHint): void {
    if (actions.indexOf(action) < 0) {
      actions.push(action);
    }
  }

  private mediaResourceSource(source: MediaSignalSourceKind): MediaResourceSource {
    switch (source) {
      case 'resource_network':
      case 'video_network':
        return 'network';
      case 'site_extractor':
      case 'video_adapter':
        return 'video_adapter';
      case 'resource_dom':
      case 'video_dom':
      case 'arkweb_media_assistant':
        return 'dom';
      default:
        return 'unknown';
    }
  }

  private mediaResourceFrameType(frameType: string | undefined): MediaResourceFrameType | undefined {
    switch (frameType) {
      case 'main_frame': return 'main_frame';
      case 'sub_frame': return 'sub_frame';
      case 'dom_frame': return 'dom_frame';
      case 'dom_document': return 'dom_document';
      case 'unknown': return 'unknown';
      default: return undefined;
    }
  }

  private mediaResourceStatus(candidate: MediaCandidate): MediaResourceStatus {
    const validationStatus = this.mediaResourceValidationStatus(candidate);
    if (validationStatus !== undefined) {
      return validationStatus;
    }
    if (!this.hasTrustedMediaIdentity(candidate) &&
      this.isPotentialVideoCandidate(candidate) &&
      (candidate.playabilityState === 'candidate' || candidate.playabilityState === 'playable')) {
      if (this.isDirectlyDownloadableHls(candidate)) {
        return 'downloadable';
      }
      return 'needs_processing';
    }
    switch (candidate.playabilityState) {
      case 'playing_native': return 'playing_native';
      case 'playable': return 'playable';
      case 'unsupported':
      case 'requires_po_token':
      case 'signature_failed':
      case 'format_unavailable': return 'unsupported';
      case 'protected': return 'protected';
      case 'expired': return 'expired';
      case 'failed': return 'failed';
      default:
        if (candidate.detectionState === 'needs_processing' ||
          candidate.downloadabilityState === 'manifest' ||
          (candidate.family === 'manifest' && candidate.kind !== 'hls')) {
          return 'needs_processing';
        }
        if (candidate.downloadabilityState === 'downloadable' ||
          candidate.downloadabilityState === 'needs_headers') {
          return 'downloadable';
        }
        return 'detected';
    }
  }

  private projectHlsManifestTarget(candidate: MediaCandidate): MediaHlsManifestTarget {
    const playbackMetadata = candidate.playbackMetadata;
    const manifestContext = candidate.manifestContext;
    const authContext = candidate.authContext;
    return {
      candidateId: candidate.id,
      tabId: candidate.tabId,
      pageUrl: candidate.pageUrl,
      pageTitle: candidate.pageTitle,
      frameUrl: candidate.frameContext?.frameUrl,
      frameType: this.mediaResourceFrameType(candidate.frameContext?.frameType),
      url: candidate.url,
      kind: candidate.kind,
      family: candidate.family,
      acquisition: candidate.acquisition,
      displayName: this.displayNameForMediaCandidate(candidate),
      sourceHost: playbackMetadata?.sourceHost ?? this.resolveHost(candidate.url),
      extension: playbackMetadata?.extension ?? this.resolveExtension(candidate.url),
      mimeType: playbackMetadata?.mimeType,
      evidence: this.mediaHlsManifestEvidence(candidate.evidence),
      score: candidate.confidence,
      manifestText: manifestContext?.manifestText,
      manifestBaseUrl: candidate.validation?.manifestBaseUrl ?? manifestContext?.manifestBaseUrl,
      referer: authContext?.referer ?? authContext?.pageUrl,
      userAgent: authContext?.userAgent,
      originUrl: authContext?.originUrl,
      requestHeaders: authContext?.requestHeaders
    };
  }

  private projectDownloadCandidate(candidate: MediaCandidate, candidates: MediaCandidate[]): MediaDownloadCandidate {
    const playbackMetadata = candidate.playbackMetadata;
    const authContext = candidate.authContext;
    const projectedMetrics = this.projectedMediaMetrics(candidate, candidates);
    return {
      candidateId: candidate.id,
      tabId: candidate.tabId,
      pageUrl: candidate.pageUrl,
      url: candidate.url,
      family: candidate.family,
      kind: candidate.kind,
      acquisition: candidate.acquisition,
      actions: this.mediaResourceActions(candidate),
      score: candidate.confidence,
      displayName: this.downloadFileNameForCandidate(candidate),
      sourceHost: playbackMetadata?.sourceHost ?? this.resolveHost(candidate.url),
      totalBytes: playbackMetadata?.totalBytes,
      estimatedTotalBytes: projectedMetrics.estimatedTotalBytes,
      durationMs: projectedMetrics.durationMs,
      mimeType: playbackMetadata?.mimeType,
      contentDisposition: candidate.kind === 'hls' ? undefined : playbackMetadata?.contentDisposition,
      referer: authContext?.referer ?? authContext?.pageUrl,
      userAgent: authContext?.userAgent,
      originUrl: authContext?.originUrl,
      requestHeaders: authContext?.requestHeaders
    };
  }

  private downloadFileNameForCandidate(candidate: MediaCandidate): string {
    const displayName = this.displayNameForMediaCandidate(candidate).trim();
    if (candidate.kind !== 'hls') {
      return displayName;
    }
    if (displayName.length <= 0) {
      return 'video.ts';
    }
    if (/\.(?:m3u8|m3u)$/i.test(displayName)) {
      return displayName.replace(/\.(?:m3u8|m3u)$/i, '.ts');
    }
    if (/\.[A-Za-z0-9]{1,8}$/.test(displayName)) {
      return displayName.replace(/\.[A-Za-z0-9]{1,8}$/, '.ts');
    }
    return displayName + '.ts';
  }

  private mediaHlsManifestEvidence(evidence: MediaEvidence[]): MediaHlsManifestEvidence | undefined {
    const value = this.resourceEvidenceFromMediaEvidence(evidence);
    if (value === undefined) {
      return undefined;
    }
    return value;
  }

  private resourceEvidenceFromMediaEvidence(evidence: MediaEvidence[]): MediaHlsManifestEvidence | undefined {
    for (let i = 0; i < evidence.length; i++) {
      if (evidence[i].kind === 'resource_evidence' && this.isProjectionEvidence(evidence[i].value)) {
        return evidence[i].value as MediaHlsManifestEvidence;
      }
    }
    for (let i = 0; i < evidence.length; i++) {
      if (evidence[i].kind === 'mime') {
        return 'mime';
      }
      if (evidence[i].kind === 'dom_signal') {
        const domSignal = evidence[i].value;
        if (domSignal === 'video_element' || domSignal === 'audio_element') {
          return 'media_element';
        }
        if (domSignal === 'image_element' || domSignal === 'css_background' || domSignal === 'image_performance') {
          return 'image_element';
        }
        if (domSignal === 'embedded_attribute' || domSignal === 'performance_entry') {
          return 'streaming_url_hint';
        }
        if (domSignal === 'script_text' || domSignal === 'text_match' || domSignal === 'location') {
          return 'weak_text_match';
        }
      }
    }
    return undefined;
  }

  private isProjectionEvidence(value: string): boolean {
    return value === 'mime' ||
      value === 'explicit_extension' ||
      value === 'media_element' ||
      value === 'image_element' ||
      value === 'streaming_url_hint' ||
      value === 'generic_url_hint' ||
      value === 'weak_text_match' ||
      value === 'negative';
  }

  private hasTrustedMediaIdentity(candidate: MediaCandidate): boolean {
    return candidate.nativeIdentity !== undefined ||
      candidate.source === 'site_extractor' ||
      candidate.source === 'video_adapter';
  }

  private mediaResourceValidationStatus(candidate: MediaCandidate): MediaResourceStatus | undefined {
    const validation = candidate.validation;
    if (validation === undefined) {
      return undefined;
    }
    switch (validation.state) {
      case 'validating':
        return 'needs_processing';
      case 'validated_resource_only':
        return this.isDirectlyDownloadableHls(candidate) ? 'downloadable' : 'needs_processing';
      case 'validated_playable':
        return candidate.playabilityState === 'playing_native' ? 'playing_native' : 'playable';
      case 'unsupported':
        return 'unsupported';
      case 'protected':
        return 'protected';
      case 'expired':
        return 'expired';
      case 'failed':
        return 'failed';
      default:
        return undefined;
    }
  }

  private isDirectlyDownloadableHls(candidate: MediaCandidate): boolean {
    return candidate.kind === 'hls' && this.mediaResourceActions(candidate).indexOf('download') >= 0;
  }

  private isPotentialVideoCandidate(candidate: MediaCandidate): boolean {
    if (candidate.kind === 'hls' ||
      candidate.kind === 'dash' ||
      candidate.kind === 'mp4' ||
      candidate.kind === 'webm' ||
      candidate.kind === 'mov' ||
      this.hasVideoAcquisition(candidate)) {
      return true;
    }
    return candidate.family === 'video' || candidate.family === 'manifest';
  }

  private hasVideoAcquisition(candidate: MediaCandidate): boolean {
    const acquisition = candidate.acquisition;
    return acquisition !== undefined &&
      (acquisition.primaryTrack.role === 'combined' || acquisition.primaryTrack.role === 'video');
  }

  private isStreamingManifestCandidate(candidate: MediaCandidate): boolean {
    return candidate.kind === 'hls' ||
      candidate.kind === 'dash' ||
      candidate.family === 'manifest';
  }

  private isDownloadCandidate(candidate: MediaCandidate): boolean {
    if (candidate.url.trim().length <= 0 || !this.isHttpOrHttpsUrl(candidate.url)) {
      return false;
    }
    const actions = this.mediaResourceActions(candidate);
    return actions.indexOf('download') >= 0;
  }

  private displayNameForMediaCandidate(candidate: MediaCandidate): string {
    const nativeTitle = candidate.nativeIdentity?.title?.trim() ?? '';
    if (nativeTitle.length > 0) {
      return nativeTitle;
    }
    const playbackDisplayName = candidate.playbackMetadata?.displayName?.trim() ?? '';
    if (playbackDisplayName.length > 0) {
      return playbackDisplayName;
    }
    const fileName = this.fileNameFromUrl(candidate.url);
    return fileName.length > 0 ? fileName : this.resolveHost(candidate.url);
  }

  private resourceDisplayNameForCandidate(candidate: MediaCandidate): string {
    const displayName = this.displayNameForMediaCandidate(candidate);
    if (candidate.kind !== 'hls' || !this.isGenericHlsDisplayName(displayName)) {
      return displayName;
    }
    const pageTitle = candidate.pageTitle.trim();
    return pageTitle.length > 0 ? pageTitle : '网页视频';
  }

  private isGenericHlsDisplayName(value: string): boolean {
    const lower = value.trim().toLowerCase();
    const dotIndex = lower.lastIndexOf('.');
    const baseName = dotIndex > 0 ? lower.substring(0, dotIndex) : lower;
    return baseName === 'index' ||
      baseName === 'master' ||
      baseName === 'playlist' ||
      baseName === 'mixed' ||
      baseName === 'video' ||
      baseName === 'download';
  }

  private failureReasonFromEvidence(evidence: MediaEvidence[]): string | undefined {
    for (let i = 0; i < evidence.length; i++) {
      if (evidence[i].kind === 'failure_reason') {
        return evidence[i].value;
      }
    }
    return undefined;
  }

  private resolveHost(url: string): string {
    try {
      const schemeIndex = url.indexOf('://');
      if (schemeIndex < 0) {
        return '未知来源';
      }
      const hostStart = schemeIndex + 3;
      const pathStart = url.indexOf('/', hostStart);
      const authority = pathStart >= 0 ? url.substring(hostStart, pathStart) : url.substring(hostStart);
      const host = authority.split('@').pop()?.split(':')[0]?.trim() ?? '';
      return host.length > 0 ? host : '未知来源';
    } catch (_error) {
      return '未知来源';
    }
  }

  private fileNameFromUrl(url: string): string {
    const cleanUrl = url.split('?')[0].split('#')[0];
    const lastSlash = cleanUrl.lastIndexOf('/');
    const segment = lastSlash >= 0 ? cleanUrl.substring(lastSlash + 1) : cleanUrl;
    if (segment.trim().length > 0) {
      return this.decodeLoose(segment.trim());
    }
    return '';
  }

  private resolveExtension(url: string): string | undefined {
    const withoutQuery = url.split('?')[0].split('#')[0];
    const lastSlash = withoutQuery.lastIndexOf('/');
    const segment = lastSlash >= 0 ? withoutQuery.substring(lastSlash + 1) : withoutQuery;
    const dot = segment.lastIndexOf('.');
    if (dot < 0 || dot === segment.length - 1) {
      return undefined;
    }
    const extension = segment.substring(dot + 1).trim().toLowerCase();
    return extension.length > 0 && extension.length <= 8 ? extension : undefined;
  }

  private decodeLoose(value: string): string {
    try {
      return decodeURIComponent(value);
    } catch (_error) {
      return value;
    }
  }

  private isHttpOrHttpsUrl(url: string): boolean {
    const lower = url.trim().toLowerCase();
    return lower.indexOf('http://') === 0 || lower.indexOf('https://') === 0;
  }
}
