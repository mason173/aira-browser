import {
  MediaActionHint,
  MediaAcquisitionFacts,
  MediaAuthContext,
  MediaCandidate,
  MediaEvidence,
  MediaManifestContext,
  MediaPlaybackMetadata,
  MediaPlayabilityState
} from '../../features/mediaDiscovery/MediaCandidateModels';
import {
  MediaCandidateValidationResult,
  MediaCandidateValidationSnapshot,
  MediaValidationKind
} from '../../features/mediaDiscovery/MediaCandidateValidationModels';
import {
  MediaCandidateIdentityResolution,
  MediaCandidateIdentityService
} from '../../features/mediaDiscovery/MediaCandidateIdentity';
import { MediaCandidateScoring } from '../../features/mediaDiscovery/MediaCandidateScoring';
import {
  MediaSignal,
  MediaSignalBatch
} from '../../features/mediaDiscovery/MediaSignalModels';
import { MediaCandidateValidationFingerprintService } from './MediaCandidateValidationFingerprintService';

const MAX_MEDIA_CANDIDATES_PER_TAB: number = 192;
const VALIDATION_RETRY_INTERVAL_MS: number = 15 * 1000;
const VALIDATION_MAX_AGE_MS: number = 5 * 60 * 1000;

export interface MediaDiscoveryCandidateRecord {
  identityKey: string;
  candidate: MediaCandidate;
}

export interface MediaDiscoveryTabSnapshot {
  tabId: string;
  records: MediaDiscoveryCandidateRecord[];
}

export interface MediaDiscoveryStoreSummary {
  tabId: string;
  candidateCount: number;
  resourceRecordCount: number;
  videoRecordCount: number;
  presentationRelevantChange: boolean;
  validationRelevantChange: boolean;
}

interface MediaCandidateBuildResult {
  candidate: MediaCandidate;
  identity: MediaCandidateIdentityResolution;
}

interface MediaDiscoveryRecordMutation {
  presentationRelevantChange: boolean;
  validationRelevantChange: boolean;
}

export class MediaDiscoveryStore {
  private identityService: MediaCandidateIdentityService = new MediaCandidateIdentityService();
  private scoring: MediaCandidateScoring = new MediaCandidateScoring();
  private validationFingerprintService: MediaCandidateValidationFingerprintService =
    new MediaCandidateValidationFingerprintService();
  private recordsByTab: Map<string, MediaDiscoveryCandidateRecord[]> = new Map();
  private nextSequence: number = 1;

  ingestSignals(input: MediaSignalBatch): MediaDiscoveryStoreSummary {
    const records = this.recordsByTab.get(input.tabId)?.slice() ?? [];
    const identities = this.collectIdentityKeys(records);
    let presentationRelevantChange = false;
    let validationRelevantChange = false;
    for (let i = 0; i < input.signals.length; i++) {
      const build = this.buildFromSignal(input.signals[i]);
      const mutation = this.upsertRecord(records, identities, build.identity.idKey, build.candidate);
      presentationRelevantChange = presentationRelevantChange || mutation.presentationRelevantChange;
      validationRelevantChange = validationRelevantChange || mutation.validationRelevantChange;
    }
    this.sortAndStoreTab(input.tabId, records);
    return this.buildSummary(input.tabId, records, presentationRelevantChange, validationRelevantChange);
  }

  getTabSnapshot(tabId: string): MediaDiscoveryTabSnapshot {
    const records = this.recordsByTab.get(tabId) ?? [];
    return {
      tabId: tabId,
      records: records.slice()
    };
  }

  listValidationTargets(tabId: string, now: number): MediaCandidate[] {
    const records = this.recordsByTab.get(tabId) ?? [];
    const targets: MediaCandidate[] = [];
    for (let i = 0; i < records.length; i++) {
      const candidate = records[i].candidate;
      if (this.shouldValidateCandidate(candidate, now)) {
        targets.push(candidate);
      }
    }
    return targets;
  }

  markValidationInProgress(tabId: string, candidateId: string, fingerprint: string, now: number): boolean {
    const candidate = this.findCandidate(tabId, candidateId);
    if (candidate === undefined || this.buildValidationFingerprint(candidate) !== fingerprint) {
      return false;
    }
    candidate.validation = {
      state: 'validating',
      kind: this.validationKindForCandidate(candidate),
      fingerprint: fingerprint,
      validatedAt: now,
      failureCode: 'none',
      failureMessage: '',
      evidence: []
    };
    candidate.playabilityState = this.mapValidationToPlayability(candidate, candidate.validation);
    return true;
  }

  applyValidationResult(result: MediaCandidateValidationResult): boolean {
    const candidate = this.findCandidate(result.tabId, result.candidateId);
    if (candidate === undefined || this.buildValidationFingerprint(candidate) !== result.fingerprint) {
      return false;
    }
    candidate.validation = result.snapshot;
    this.applyValidationPlaybackMetadata(candidate, result.snapshot);
    candidate.playabilityState = this.mapValidationToPlayability(candidate, result.snapshot);
    return true;
  }

  clearTab(tabId: string): void {
    this.recordsByTab.delete(tabId);
  }

  clearAll(): void {
    this.recordsByTab.clear();
  }

  private upsertRecord(
    records: MediaDiscoveryCandidateRecord[],
    identities: string[],
    identityKey: string,
    candidate: MediaCandidate
  ): MediaDiscoveryRecordMutation {
    for (let i = 0; i < identities.length; i++) {
      if (identities[i] === identityKey) {
        const current = records[i].candidate;
        const presentationFingerprint = this.buildPresentationFingerprint(current);
        const validationFingerprint = this.buildValidationFingerprint(current);
        const validationRetryDue = this.shouldValidateCandidate(current, Date.now());
        this.mergeRecord(records[i], candidate);
        return {
          presentationRelevantChange:
            presentationFingerprint !== this.buildPresentationFingerprint(current),
          validationRelevantChange:
            validationRetryDue || validationFingerprint !== this.buildValidationFingerprint(current)
        };
      }
    }
    identities.push(identityKey);
    records.push({
      identityKey: identityKey,
      candidate: candidate
    });
    return {
      presentationRelevantChange: true,
      validationRelevantChange: true
    };
  }

  private buildPresentationFingerprint(candidate: MediaCandidate): string {
    const playback = candidate.playbackMetadata;
    const manifest = candidate.manifestContext;
    const validation = candidate.validation;
    return candidate.id + '|' +
      candidate.tabId + '|' +
      candidate.pageUrl + '|' +
      candidate.pageTitle + '|' +
      candidate.url + '|' +
      candidate.kind + '|' +
      candidate.family + '|' +
      candidate.source + '|' +
      candidate.confidence.toString() + '|' +
      candidate.detectionState + '|' +
      candidate.playabilityState + '|' +
      candidate.downloadabilityState + '|' +
      candidate.actionHints.length.toString() + '|' +
      candidate.evidence.length.toString() + '|' +
      JSON.stringify(candidate.frameContext) + '|' +
      (manifest?.manifestBaseUrl ?? '') + '|' +
      (manifest?.pairedAudioUrl ?? '') + '|' +
      (manifest?.pairedAudioMimeType ?? '') + '|' +
      (manifest?.codecs ?? '') + '|' +
      (manifest?.bandwidth ?? 0).toString() + '|' +
      (manifest?.contentLength ?? 0).toString() + '|' +
      (manifest?.fps ?? 0).toString() + '|' +
      (manifest?.initializationRange ?? '') + '|' +
      (manifest?.indexRange ?? '') + '|' +
      (manifest?.pairedAudioCodecs ?? '') + '|' +
      (manifest?.pairedAudioBandwidth ?? 0).toString() + '|' +
      (manifest?.pairedAudioContentLength ?? 0).toString() + '|' +
      (manifest?.pairedAudioSampleRate ?? 0).toString() + '|' +
      (manifest?.pairedAudioChannels ?? 0).toString() + '|' +
      (manifest?.pairedAudioInitializationRange ?? '') + '|' +
      (manifest?.pairedAudioIndexRange ?? '') + '|' +
      (playback?.displayName ?? '') + '|' +
      (playback?.sourceHost ?? '') + '|' +
      (playback?.mimeType ?? '') + '|' +
      (playback?.extension ?? '') + '|' +
      (playback?.contentDisposition ?? '') + '|' +
      (playback?.durationMs ?? 0).toString() + '|' +
      (playback?.width ?? 0).toString() + '|' +
      (playback?.height ?? 0).toString() + '|' +
      (playback?.totalBytes ?? 0).toString() + '|' +
      (playback?.posterUrl ?? '') + '|' +
      JSON.stringify(candidate.nativeIdentity) + '|' +
      JSON.stringify(candidate.acquisition) + '|' +
      (validation?.state ?? '') + '|' +
      (validation?.kind ?? '') + '|' +
      (validation?.fingerprint ?? '') + '|' +
      (validation?.failureCode ?? '');
  }

  private mergeRecord(record: MediaDiscoveryCandidateRecord, next: MediaCandidate): void {
    const current = record.candidate;
    const currentValidation = current.validation;
    current.confidence = this.scoring.mergeConfidence(current.confidence, next.confidence);
    current.detectionState = this.scoring.mergeDetectionState(current.detectionState, next.detectionState);
    current.playabilityState = this.scoring.mergePlayabilityState(current.playabilityState, next.playabilityState);
    current.downloadabilityState =
      this.scoring.mergeDownloadabilityState(current.downloadabilityState, next.downloadabilityState);
    current.lastSeenAt = Math.max(current.lastSeenAt, next.lastSeenAt);
    current.firstSeenAt = Math.min(current.firstSeenAt, next.firstSeenAt);
    this.scoring.mergeActionHints(current.actionHints, next.actionHints);
    this.mergeEvidence(current.evidence, next.evidence);
    this.mergeCandidateShape(current, next);
    this.mergeCandidateContexts(current, next);
    if (currentValidation === undefined) {
      return;
    }
    if (currentValidation.fingerprint !== this.buildValidationFingerprint(current)) {
      current.validation = undefined;
      current.playabilityState = this.resetPlayabilityAfterValidationReset(current, next.playabilityState);
      return;
    }
    current.playabilityState = this.mapValidationToPlayability(current, currentValidation);
  }

  private buildFromSignal(signal: MediaSignal): MediaCandidateBuildResult {
    const observedAt = signal.observedAt > 0 ? signal.observedAt : Date.now();
    const signalCandidateId = signal.candidateId?.trim() ?? '';
    const mediaCandidate: MediaCandidate = {
      id: signalCandidateId.length > 0 ? signalCandidateId : this.allocateCandidateId(),
      tabId: signal.tabId,
      pageUrl: signal.pageUrl,
      pageTitle: signal.pageTitle,
      url: signal.url,
      kind: signal.kind,
      family: signal.family,
      source: signal.source,
      evidence: this.copyEvidence(signal.evidence),
      confidence: this.scoring.normalizeConfidence(signal.confidence),
      detectionState: signal.detectionState ?? 'detected',
      playabilityState: signal.playabilityState ?? 'unknown',
      downloadabilityState: signal.downloadabilityState ?? 'unknown',
      actionHints: this.copyActionHints(signal.actionHints),
      frameContext: signal.frameContext,
      authContext: signal.authContext,
      manifestContext: signal.manifestContext,
      playbackMetadata: signal.playbackMetadata,
      nativeIdentity: signal.nativeIdentity,
      acquisition: signal.acquisition === undefined ? undefined : this.copyAcquisitionFacts(signal.acquisition),
      firstSeenAt: observedAt,
      lastSeenAt: observedAt
    };
    return {
      candidate: mediaCandidate,
      identity: this.identityService.resolve({
        tabId: signal.tabId,
        url: signal.url,
        source: signal.source,
        nativeIdentity: signal.nativeIdentity
      })
    };
  }

  private allocateCandidateId(): string {
    const id = 'media-' + this.nextSequence.toString();
    this.nextSequence += 1;
    return id;
  }

  private mergeEvidence(target: MediaEvidence[], source: MediaEvidence[]): void {
    for (let i = 0; i < source.length; i++) {
      if (!this.hasEvidence(target, source[i])) {
        target.push(source[i]);
      }
    }
  }

  private hasEvidence(target: MediaEvidence[], evidence: MediaEvidence): boolean {
    for (let i = 0; i < target.length; i++) {
      if (target[i].kind === evidence.kind && target[i].value === evidence.value) {
        return true;
      }
    }
    return false;
  }

  private mergeCandidateShape(current: MediaCandidate, next: MediaCandidate): void {
    if (this.shouldPreferSecureUrl(current.url, next.url)) {
      current.url = next.url;
    }
    if (current.family === 'unknown' && next.family !== 'unknown') {
      current.family = next.family;
    }
    if (current.kind === 'unknown' && next.kind !== 'unknown') {
      current.kind = next.kind;
    }
    if (current.source === 'unknown' && next.source !== 'unknown') {
      current.source = next.source;
    }
  }

  private shouldPreferSecureUrl(currentUrl: string, nextUrl: string): boolean {
    if (currentUrl.trim().toLowerCase().indexOf('http://') !== 0 ||
      nextUrl.trim().toLowerCase().indexOf('https://') !== 0) {
      return false;
    }
    return this.identityService.normalizeUrlKey(currentUrl) === this.identityService.normalizeUrlKey(nextUrl);
  }

  private mergeCandidateContexts(current: MediaCandidate, next: MediaCandidate): void {
    if (current.frameContext === undefined && next.frameContext !== undefined) {
      current.frameContext = next.frameContext;
    }
    current.authContext = this.mergeAuthContext(current.authContext, next.authContext);
    current.manifestContext = this.mergeManifestContext(current.manifestContext, next.manifestContext);
    current.playbackMetadata = this.mergePlaybackMetadata(current.playbackMetadata, next.playbackMetadata);
    if (current.nativeIdentity === undefined && next.nativeIdentity !== undefined) {
      current.nativeIdentity = next.nativeIdentity;
    }
    if (current.acquisition === undefined && next.acquisition !== undefined) {
      current.acquisition = this.copyAcquisitionFacts(next.acquisition);
    }
  }

  private copyAcquisitionFacts(input: MediaAcquisitionFacts): MediaAcquisitionFacts {
    return {
      mode: input.mode,
      primaryTrack: {
        role: input.primaryTrack.role,
        url: input.primaryTrack.url,
        mimeType: input.primaryTrack.mimeType,
        codecs: input.primaryTrack.codecs,
        bitrate: input.primaryTrack.bitrate,
        contentLength: input.primaryTrack.contentLength,
        width: input.primaryTrack.width,
        height: input.primaryTrack.height,
        fps: input.primaryTrack.fps,
        audioSampleRate: input.primaryTrack.audioSampleRate,
        audioChannels: input.primaryTrack.audioChannels,
        initializationRange: input.primaryTrack.initializationRange,
        indexRange: input.primaryTrack.indexRange
      },
      pairedTrack: input.pairedTrack === undefined ? undefined : {
        role: input.pairedTrack.role,
        url: input.pairedTrack.url,
        mimeType: input.pairedTrack.mimeType,
        codecs: input.pairedTrack.codecs,
        bitrate: input.pairedTrack.bitrate,
        contentLength: input.pairedTrack.contentLength,
        width: input.pairedTrack.width,
        height: input.pairedTrack.height,
        fps: input.pairedTrack.fps,
        audioSampleRate: input.pairedTrack.audioSampleRate,
        audioChannels: input.pairedTrack.audioChannels,
        initializationRange: input.pairedTrack.initializationRange,
        indexRange: input.pairedTrack.indexRange
      }
    };
  }

  private mergeAuthContext(
    current: MediaAuthContext | undefined,
    next: MediaAuthContext | undefined
  ): MediaAuthContext | undefined {
    if (current === undefined) {
      return next;
    }
    if (next === undefined) {
      return current;
    }
    return {
      pageUrl: this.preferRequiredText(current.pageUrl, next.pageUrl),
      referer: this.preferText(current.referer, next.referer),
      userAgent: this.preferText(current.userAgent, next.userAgent),
      originUrl: this.preferText(current.originUrl, next.originUrl),
      requestHeaders: this.mergeHeaderMap(current.requestHeaders, next.requestHeaders),
      responseHeaders: this.mergeHeaderMap(current.responseHeaders, next.responseHeaders)
    };
  }

  private mergeManifestContext(
    current: MediaManifestContext | undefined,
    next: MediaManifestContext | undefined
  ): MediaManifestContext | undefined {
    if (current === undefined) {
      return next;
    }
    if (next === undefined) {
      return current;
    }
    return {
      manifestText: this.preferText(current.manifestText, next.manifestText),
      manifestBaseUrl: this.preferText(current.manifestBaseUrl, next.manifestBaseUrl),
      pairedAudioUrl: this.preferText(current.pairedAudioUrl, next.pairedAudioUrl),
      pairedAudioMimeType: this.preferText(current.pairedAudioMimeType, next.pairedAudioMimeType),
      codecs: this.preferText(current.codecs, next.codecs),
      bandwidth: this.preferNumber(current.bandwidth, next.bandwidth),
      contentLength: this.preferNumber(current.contentLength, next.contentLength),
      fps: this.preferNumber(current.fps, next.fps),
      initializationRange: this.preferText(current.initializationRange, next.initializationRange),
      indexRange: this.preferText(current.indexRange, next.indexRange),
      pairedAudioCodecs: this.preferText(current.pairedAudioCodecs, next.pairedAudioCodecs),
      pairedAudioBandwidth: this.preferNumber(current.pairedAudioBandwidth, next.pairedAudioBandwidth),
      pairedAudioContentLength: this.preferNumber(current.pairedAudioContentLength, next.pairedAudioContentLength),
      pairedAudioSampleRate: this.preferNumber(current.pairedAudioSampleRate, next.pairedAudioSampleRate),
      pairedAudioChannels: this.preferNumber(current.pairedAudioChannels, next.pairedAudioChannels),
      pairedAudioInitializationRange: this.preferText(current.pairedAudioInitializationRange, next.pairedAudioInitializationRange),
      pairedAudioIndexRange: this.preferText(current.pairedAudioIndexRange, next.pairedAudioIndexRange)
    };
  }

  private mergePlaybackMetadata(
    current: MediaPlaybackMetadata | undefined,
    next: MediaPlaybackMetadata | undefined
  ): MediaPlaybackMetadata | undefined {
    if (current === undefined) {
      return next;
    }
    if (next === undefined) {
      return current;
    }
    return {
      displayName: this.preferText(current.displayName, next.displayName),
      sourceHost: this.preferText(current.sourceHost, next.sourceHost),
      extension: this.preferText(current.extension, next.extension),
      mimeType: this.preferText(current.mimeType, next.mimeType),
      contentDisposition: this.preferText(current.contentDisposition, next.contentDisposition),
      totalBytes: this.preferNumber(current.totalBytes, next.totalBytes),
      durationMs: this.preferNumber(current.durationMs, next.durationMs),
      width: this.preferNumber(current.width, next.width),
      height: this.preferNumber(current.height, next.height),
      posterUrl: this.preferText(current.posterUrl, next.posterUrl)
    };
  }

  private applyValidationPlaybackMetadata(
    candidate: MediaCandidate,
    validation: MediaCandidateValidationSnapshot
  ): void {
    const candidateUrl = candidate.url.trim();
    if (candidateUrl.length <= 0) {
      return;
    }
    let validatedBytes = 0;
    for (let i = 0; i < validation.evidence.length; i++) {
      const evidence = validation.evidence[i];
      if (!evidence.ok || evidence.url.trim() !== candidateUrl ||
        (evidence.kind !== 'response_header' && evidence.kind !== 'first_bytes' && evidence.kind !== 'manifest_root')) {
        continue;
      }
      const contentLength = evidence.contentLength ?? 0;
      if (contentLength > validatedBytes) {
        validatedBytes = Math.floor(contentLength);
      }
    }
    if (validatedBytes <= 0) {
      return;
    }
    if (candidate.playbackMetadata === undefined) {
      candidate.playbackMetadata = { totalBytes: validatedBytes };
      return;
    }
    candidate.playbackMetadata.totalBytes = Math.max(candidate.playbackMetadata.totalBytes ?? 0, validatedBytes);
  }

  private mergeHeaderMap(
    current: Record<string, string> | undefined,
    next: Record<string, string> | undefined
  ): Record<string, string> | undefined {
    if (current === undefined) {
      return next;
    }
    if (next === undefined) {
      return current;
    }
    const result: Record<string, string> = {};
    this.copyHeaders(result, current, false);
    this.copyHeaders(result, next, true);
    return Object.keys(result).length > 0 ? result : undefined;
  }

  private copyHeaders(target: Record<string, string>, source: Record<string, string>, overwrite: boolean): void {
    const keys = Object.keys(source);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i].trim();
      const value = source[keys[i]]?.trim() ?? '';
      if (key.length <= 0 || value.length <= 0) {
        continue;
      }
      const existingKey = this.findHeaderKey(target, key);
      if (existingKey.length > 0) {
        if (overwrite) {
          target[existingKey] = value;
        }
      } else {
        target[key] = value;
      }
    }
  }

  private findHeaderKey(headers: Record<string, string>, key: string): string {
    const lower = key.toLowerCase();
    const keys = Object.keys(headers);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === lower) {
        return keys[i];
      }
    }
    return '';
  }

  private preferText(current: string | undefined, next: string | undefined): string | undefined {
    const currentText = current?.trim() ?? '';
    if (currentText.length > 0) {
      return current;
    }
    const nextText = next?.trim() ?? '';
    return nextText.length > 0 ? next : undefined;
  }

  private preferRequiredText(current: string, next: string): string {
    return this.preferText(current, next) ?? current;
  }

  private preferNumber(current: number | undefined, next: number | undefined): number | undefined {
    return current !== undefined ? current : next;
  }

  private collectIdentityKeys(records: MediaDiscoveryCandidateRecord[]): string[] {
    const identities: string[] = [];
    for (let i = 0; i < records.length; i++) {
      identities.push(records[i].identityKey);
    }
    return identities;
  }

  private findCandidate(tabId: string, candidateId: string): MediaCandidate | undefined {
    const records = this.recordsByTab.get(tabId);
    if (records === undefined) {
      return undefined;
    }
    for (let i = 0; i < records.length; i++) {
      if (records[i].candidate.id === candidateId) {
        return records[i].candidate;
      }
    }
    return undefined;
  }

  private shouldValidateCandidate(candidate: MediaCandidate, now: number): boolean {
    if (candidate.tabId.length <= 0 || candidate.url.trim().length <= 0) {
      return false;
    }
    if (this.isTrustedNativeCandidate(candidate) || !this.isPotentialNativeTakeoverCandidate(candidate)) {
      return false;
    }
    const validation = candidate.validation;
    if (validation === undefined) {
      return true;
    }
    const fingerprint = this.buildValidationFingerprint(candidate);
    if (validation.fingerprint !== fingerprint) {
      return true;
    }
    if (validation.state === 'validating') {
      return false;
    }
    if (validation.state === 'failed' || validation.state === 'expired') {
      return now - validation.validatedAt >= VALIDATION_RETRY_INTERVAL_MS;
    }
    return now - validation.validatedAt >= VALIDATION_MAX_AGE_MS;
  }

  private buildValidationFingerprint(candidate: MediaCandidate): string {
    return this.validationFingerprintService.build(candidate);
  }

  private mapValidationToPlayability(
    candidate: MediaCandidate,
    validation: MediaCandidateValidationSnapshot
  ): MediaPlayabilityState {
    switch (validation.state) {
      case 'validated_playable':
        return candidate.playabilityState === 'playing_native' ? 'playing_native' : 'playable';
      case 'validated_resource_only':
      case 'validating':
        return 'needs_processing';
      case 'protected':
        return 'protected';
      case 'expired':
        return 'expired';
      case 'unsupported':
        return 'unsupported';
      case 'failed':
        return 'failed';
      default:
        return candidate.playabilityState;
    }
  }

  private resetPlayabilityAfterValidationReset(
    candidate: MediaCandidate,
    nextPlayability: MediaPlayabilityState
  ): MediaPlayabilityState {
    if (candidate.playabilityState === 'playing_native') {
      return 'playing_native';
    }
    if (nextPlayability !== 'unknown') {
      return nextPlayability;
    }
    return this.isPotentialNativeTakeoverCandidate(candidate) ? 'needs_processing' : 'unknown';
  }

  private validationKindForCandidate(candidate: MediaCandidate): MediaValidationKind {
    if (this.isTrustedNativeCandidate(candidate)) {
      return 'site_native_identity';
    }
    if (candidate.kind === 'hls') {
      return this.hasCapturedHlsManifest(candidate) && !this.isHttpOrHttpsUrl(candidate.url) ?
        'captured_hls_virtual_graph' :
        'hls_resource_graph';
    }
    if (candidate.kind === 'dash' || candidate.acquisition?.mode === 'paired_adaptive') {
      return 'dash_resource_graph';
    }
    if (candidate.kind === 'mp4' ||
      candidate.kind === 'webm' ||
      candidate.kind === 'mov' ||
      candidate.acquisition?.mode === 'progressive') {
      return 'progressive_http';
    }
    return this.hasCapturedHlsManifest(candidate) ? 'captured_hls_virtual_graph' : 'web_only';
  }

  private isPotentialNativeTakeoverCandidate(candidate: MediaCandidate): boolean {
    if (this.isTrustedNativeCandidate(candidate)) {
      return true;
    }
    if (candidate.kind === 'hls' ||
      candidate.kind === 'dash' ||
      candidate.kind === 'mp4' ||
      candidate.kind === 'webm' ||
      candidate.kind === 'mov' ||
      this.hasVideoAcquisition(candidate)) {
      return true;
    }
    return this.hasCapturedHlsManifest(candidate) ||
      (candidate.family === 'video' && this.isHttpOrHttpsUrl(candidate.url)) ||
      (candidate.family === 'manifest' && this.isHttpOrHttpsUrl(candidate.url));
  }

  private isTrustedNativeCandidate(candidate: MediaCandidate): boolean {
    return candidate.nativeIdentity !== undefined ||
      candidate.source === 'site_extractor' ||
      candidate.source === 'video_adapter';
  }

  private hasCapturedHlsManifest(candidate: MediaCandidate): boolean {
    const text = candidate.manifestContext?.manifestText?.trim() ?? '';
    return text.indexOf('#EXTM3U') >= 0;
  }

  private isHttpOrHttpsUrl(url: string): boolean {
    const lower = url.trim().toLowerCase();
    return lower.indexOf('http://') === 0 || lower.indexOf('https://') === 0;
  }

  private sortAndStoreTab(tabId: string, records: MediaDiscoveryCandidateRecord[]): void {
    records.sort((a: MediaDiscoveryCandidateRecord, b: MediaDiscoveryCandidateRecord): number => {
      if (b.candidate.confidence !== a.candidate.confidence) {
        return b.candidate.confidence - a.candidate.confidence;
      }
      return b.candidate.lastSeenAt - a.candidate.lastSeenAt;
    });
    if (records.length > MAX_MEDIA_CANDIDATES_PER_TAB) {
      records.length = MAX_MEDIA_CANDIDATES_PER_TAB;
    }
    if (records.length > 0) {
      this.recordsByTab.set(tabId, records);
    } else {
      this.recordsByTab.delete(tabId);
    }
  }

  private copyEvidence(source: MediaEvidence[]): MediaEvidence[] {
    const evidence: MediaEvidence[] = [];
    for (let i = 0; i < source.length; i++) {
      evidence.push({
        kind: source[i].kind,
        value: source[i].value
      });
    }
    return evidence;
  }

  private copyActionHints(source: MediaActionHint[] | undefined): MediaActionHint[] {
    const hints: MediaActionHint[] = [];
    if (source === undefined) {
      return hints;
    }
    for (let i = 0; i < source.length; i++) {
      hints.push(source[i]);
    }
    return hints;
  }

  private buildSummary(
    tabId: string,
    records: MediaDiscoveryCandidateRecord[],
    presentationRelevantChange: boolean,
    validationRelevantChange: boolean
  ): MediaDiscoveryStoreSummary {
    let resourceRecordCount = 0;
    let videoRecordCount = 0;
    for (let i = 0; i < records.length; i++) {
      const candidate = records[i].candidate;
      if (candidate.family !== 'unknown') {
        resourceRecordCount += 1;
      }
      if (candidate.family === 'video' ||
        candidate.family === 'manifest' ||
        candidate.kind === 'hls' ||
        candidate.kind === 'dash' ||
        candidate.kind === 'mp4' ||
        candidate.kind === 'webm' ||
        this.hasVideoAcquisition(candidate)) {
        videoRecordCount += 1;
      }
    }
    return {
      tabId: tabId,
      candidateCount: records.length,
      resourceRecordCount: resourceRecordCount,
      videoRecordCount: videoRecordCount,
      presentationRelevantChange: presentationRelevantChange,
      validationRelevantChange: validationRelevantChange
    };
  }

  private hasVideoAcquisition(candidate: MediaCandidate): boolean {
    const acquisition = candidate.acquisition;
    return acquisition !== undefined &&
      (acquisition.primaryTrack.role === 'combined' || acquisition.primaryTrack.role === 'video');
  }
}
