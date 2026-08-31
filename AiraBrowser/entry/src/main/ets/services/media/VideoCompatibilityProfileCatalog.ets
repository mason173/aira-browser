import urlUtils from '@ohos.url';
import { MediaEvidenceScope } from '../../features/mediaDiscovery/MediaEvidenceGraphModels';
import {
  createVideoCompatibilityProfileAcquisitionCapability,
  VideoCompatibilityProfileAcquisitionCapability
} from './VideoCompatibilityProfileAcquisitionRecipeService';

export interface VideoCompatibilityProfileScopeDefinition {
  exactHosts?: string[];
  anchoredSubdomainHosts?: string[];
  pathPrefixes?: string[];
  requiredQueryKeys?: string[];
}

export type VideoCompatibilityProfileSelectorEvidenceKind = 'structured' | 'heuristic';
export type VideoCompatibilityProfileSelectorMediaStructure = 'video' | 'audio';
export type VideoCompatibilityProfileSelectorAttribute = 'presence' | 'source' | 'poster' | 'dimensions';
export type VideoCompatibilityProfileSelectorFrameScope = 'top_document';
export type VideoCompatibilityProfileSelectorOriginScope = 'top_origin';
export type VideoCompatibilityHeuristicSource = 'generic_dom_probe' | 'generic_deep_probe';
export type VideoCompatibilityProfilePresentationRecipe = 'weibo_preserve_surface';
export type VideoCompatibilityProfilePresentationMode = 'preserve_surface';
export type VideoCompatibilityProfileAcquisitionRecipe = 'bilibili_play_info' | 'youtube_player' | 'xlplayer_lines';

export interface VideoCompatibilityProfileSelectorDefinition {
  selector: string;
  evidenceKind: VideoCompatibilityProfileSelectorEvidenceKind;
  mediaStructure: VideoCompatibilityProfileSelectorMediaStructure;
  attribute: VideoCompatibilityProfileSelectorAttribute;
  frameScope?: VideoCompatibilityProfileSelectorFrameScope;
  originScope?: VideoCompatibilityProfileSelectorOriginScope;
}

/**
 * A normalized selector capability. It is intentionally a capability plan rather than the raw Profile schema.
 */
export interface VideoCompatibilityProfileSelectorPlan {
  selector: string;
  evidenceKind: VideoCompatibilityProfileSelectorEvidenceKind;
  mediaStructure: VideoCompatibilityProfileSelectorMediaStructure;
  attribute: VideoCompatibilityProfileSelectorAttribute;
  frameScope: VideoCompatibilityProfileSelectorFrameScope;
  originScope: VideoCompatibilityProfileSelectorOriginScope;
}

export interface VideoCompatibilityProfileDefinition {
  diagnosticProfileKey: string;
  revision: string;
  scope: VideoCompatibilityProfileScopeDefinition;
  enabled?: boolean;
  selectors?: VideoCompatibilityProfileSelectorDefinition[];
  suppressedHeuristicSources?: VideoCompatibilityHeuristicSource[];
  acquisitionRecipe?: VideoCompatibilityProfileAcquisitionRecipe;
  presentationRecipe?: VideoCompatibilityProfilePresentationRecipe;
}

export interface VideoCompatibilityProfileResolveInput {
  scope: MediaEvidenceScope;
  pageUrl: string;
}

export interface VideoCompatibilityProfileDiagnosticAttribution {
  profileKey: string;
}

interface ParsedProfileUrl {
  protocol: string;
  host: string;
  path: string;
  queryKeys: string[];
}

interface NormalizedVideoCompatibilityProfileScope {
  exactHosts: string[];
  anchoredSubdomainHosts: string[];
  pathPrefixes: string[];
  requiredQueryKeys: string[];
}

interface NormalizedVideoCompatibilityProfileDefinition {
  diagnosticProfileKey: string;
  revision: string;
  scope: NormalizedVideoCompatibilityProfileScope;
  enabled: boolean;
  selectors: VideoCompatibilityProfileSelectorPlan[];
  suppressedHeuristicSources: VideoCompatibilityHeuristicSource[];
  acquisitionRecipe?: VideoCompatibilityProfileAcquisitionRecipe;
  presentationRecipe?: VideoCompatibilityProfilePresentationRecipe;
}

interface VideoCompatibilityProfileMatch {
  definition: NormalizedVideoCompatibilityProfileDefinition;
  hostSpecificity: number;
  pathPrefixLength: number;
}

const ANCHORED_SUBDOMAIN_HOST_SPECIFICITY: number = 1;
const EXACT_HOST_SPECIFICITY: number = 2;
const MAX_DIAGNOSTIC_PROFILE_KEY_LENGTH: number = 96;

export interface VideoCompatibilityProfileResolution {
  isProfileApplied(): boolean;
  getScope(): MediaEvidenceScope;
  getDiagnosticAttribution(): VideoCompatibilityProfileDiagnosticAttribution | undefined;
  getSelectorPlans(): VideoCompatibilityProfileSelectorPlan[];
  isHeuristicSuppressed(source: VideoCompatibilityHeuristicSource): boolean;
  getAcquisitionCapability(): VideoCompatibilityProfileAcquisitionCapability | undefined;
  getPresentationMode(): VideoCompatibilityProfilePresentationMode | undefined;
}

class VideoCompatibilityProfileResolutionImplementation implements VideoCompatibilityProfileResolution {
  private readonly scope: MediaEvidenceScope;
  private readonly applied: boolean;
  private readonly diagnosticAttribution?: VideoCompatibilityProfileDiagnosticAttribution;
  private readonly profileRevision: string;
  private readonly selectorPlans: VideoCompatibilityProfileSelectorPlan[];
  private readonly suppressedHeuristicSources: VideoCompatibilityHeuristicSource[];
  private readonly acquisitionCapability?: VideoCompatibilityProfileAcquisitionCapability;
  private readonly presentationRecipe?: VideoCompatibilityProfilePresentationRecipe;

  constructor(
    scope: MediaEvidenceScope,
    applied: boolean,
    diagnosticAttribution?: VideoCompatibilityProfileDiagnosticAttribution,
    profileRevision: string = '',
    selectorPlans: VideoCompatibilityProfileSelectorPlan[] = [],
    suppressedHeuristicSources: VideoCompatibilityHeuristicSource[] = [],
    acquisitionCapability?: VideoCompatibilityProfileAcquisitionCapability,
    presentationRecipe?: VideoCompatibilityProfilePresentationRecipe
  ) {
    this.scope = {
      tabId: scope.tabId,
      generationId: scope.generationId,
      routeEpochId: scope.routeEpochId
    };
    this.applied = applied;
    this.diagnosticAttribution = diagnosticAttribution;
    this.profileRevision = profileRevision;
    this.selectorPlans = this.copySelectorPlans(selectorPlans);
    this.suppressedHeuristicSources = suppressedHeuristicSources.slice();
    this.acquisitionCapability = acquisitionCapability;
    this.presentationRecipe = presentationRecipe;
  }

  isProfileApplied(): boolean {
    return this.applied;
  }

  getScope(): MediaEvidenceScope {
    return {
      tabId: this.scope.tabId,
      generationId: this.scope.generationId,
      routeEpochId: this.scope.routeEpochId
    };
  }

  getDiagnosticAttribution(): VideoCompatibilityProfileDiagnosticAttribution | undefined {
    if (this.diagnosticAttribution === undefined) {
      return undefined;
    }
    return {
      profileKey: this.diagnosticAttribution.profileKey
    };
  }

  getSelectorPlans(): VideoCompatibilityProfileSelectorPlan[] {
    return this.copySelectorPlans(this.selectorPlans);
  }

  isHeuristicSuppressed(source: VideoCompatibilityHeuristicSource): boolean {
    return this.suppressedHeuristicSources.indexOf(source) >= 0;
  }

  getAcquisitionCapability(): VideoCompatibilityProfileAcquisitionCapability | undefined {
    return this.acquisitionCapability;
  }

  getPresentationMode(): VideoCompatibilityProfilePresentationMode | undefined {
    return this.presentationRecipe === 'weibo_preserve_surface' ? 'preserve_surface' : undefined;
  }

  private copySelectorPlans(
    plans: VideoCompatibilityProfileSelectorPlan[]
  ): VideoCompatibilityProfileSelectorPlan[] {
    return plans.map((plan: VideoCompatibilityProfileSelectorPlan): VideoCompatibilityProfileSelectorPlan => ({
      selector: plan.selector,
      evidenceKind: plan.evidenceKind,
      mediaStructure: plan.mediaStructure,
      attribute: plan.attribute,
      frameScope: plan.frameScope,
      originScope: plan.originScope
    }));
  }
}

/**
 * Resolves the declarative Video Compatibility Profile context for a top-level media route.
 * Generic discovery and takeover authority stay outside this module; callers only receive
 * immutable profile/no-profile context and sanitized diagnostics.
 */
export class VideoCompatibilityProfileCatalog {
  private packagedProfiles: NormalizedVideoCompatibilityProfileDefinition[] = [];
  private packagedCatalogInvalid: boolean = false;
  private resolutionByScopeKey: Map<string, VideoCompatibilityProfileResolution> = new Map();
  private currentResolutionByTabId: Map<string, VideoCompatibilityProfileResolution> = new Map();

  constructor(packagedProfiles: VideoCompatibilityProfileDefinition[] = []) {
    this.replacePackagedProfiles(packagedProfiles);
  }

  replacePackagedProfiles(packagedProfiles: VideoCompatibilityProfileDefinition[]): void {
    this.packagedProfiles = this.normalizeDefinitions(packagedProfiles);
    this.packagedCatalogInvalid = this.hasEqualSpecificityConflict(this.packagedProfiles);
  }

  resolve(input: VideoCompatibilityProfileResolveInput): VideoCompatibilityProfileResolution {
    const scopeKey = this.buildScopeKey(input.scope);
    const existing = this.resolutionByScopeKey.get(scopeKey);
    if (existing !== undefined) {
      return existing;
    }
    const resolution = this.resolveFresh(input.scope, input.pageUrl);
    this.resolutionByScopeKey.set(scopeKey, resolution);
    return resolution;
  }

  /**
   * The observation owner invokes this only when a top-level document or route becomes current.
   * Late observers resolve their captured scope without calling this activation method.
   */
  activateRoute(
    input: VideoCompatibilityProfileResolveInput,
    currentScope: MediaEvidenceScope
  ): VideoCompatibilityProfileResolution {
    const resolution = this.resolve(input);
    if (!this.sameScope(input.scope, currentScope)) {
      return resolution;
    }
    const tabId = input.scope.tabId.trim();
    if (tabId.length > 0) {
      const previous = this.currentResolutionByTabId.get(tabId);
      if (previous !== undefined && !this.sameScope(previous.getScope(), resolution.getScope())) {
        this.clearAcquisitionScheduler(previous, tabId);
      }
      this.currentResolutionByTabId.set(tabId, resolution);
    }
    return resolution;
  }

  getCurrentResolution(tabId: string): VideoCompatibilityProfileResolution | undefined {
    return this.currentResolutionByTabId.get(tabId.trim());
  }

  clearTab(tabId: string): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return;
    }
    this.currentResolutionByTabId.delete(normalizedTabId);
    const keysToDelete: string[] = [];
    this.resolutionByScopeKey.forEach((resolution: VideoCompatibilityProfileResolution, key: string): void => {
      if (resolution.getScope().tabId === normalizedTabId) {
        this.clearAcquisitionScheduler(resolution, normalizedTabId);
        keysToDelete.push(key);
      }
    });
    for (let index: number = 0; index < keysToDelete.length; index += 1) {
      this.resolutionByScopeKey.delete(keysToDelete[index]);
    }
  }

  private resolveFresh(
    scope: MediaEvidenceScope,
    pageUrl: string
  ): VideoCompatibilityProfileResolution {
    const parsed = this.parseProfileUrl(pageUrl);
    if (parsed === undefined || (parsed.protocol !== 'http:' && parsed.protocol !== 'https:')) {
      return new VideoCompatibilityProfileResolutionImplementation(scope, false);
    }
    const profiles: NormalizedVideoCompatibilityProfileDefinition[] = this.activeProfiles();
    if (this.packagedCatalogInvalid || this.hasEqualSpecificityConflict(profiles)) {
      return new VideoCompatibilityProfileResolutionImplementation(scope, false);
    }
    const match = this.resolveMatchFromProfiles(parsed, profiles);
    if (match === undefined) {
      return new VideoCompatibilityProfileResolutionImplementation(scope, false);
    }
    if (!match.definition.enabled) {
      return new VideoCompatibilityProfileResolutionImplementation(scope, false);
    }
    return new VideoCompatibilityProfileResolutionImplementation(
      scope,
      true,
      { profileKey: match.definition.diagnosticProfileKey },
      match.definition.revision,
      match.definition.selectors,
      match.definition.suppressedHeuristicSources,
      createVideoCompatibilityProfileAcquisitionCapability(
        match.definition.acquisitionRecipe,
        match.definition.diagnosticProfileKey
      ),
      match.definition.presentationRecipe
    );
  }

  private activeProfiles(): NormalizedVideoCompatibilityProfileDefinition[] {
    return this.packagedProfiles;
  }

  private resolveMatchFromProfiles(
    parsed: ParsedProfileUrl,
    profiles: NormalizedVideoCompatibilityProfileDefinition[]
  ): VideoCompatibilityProfileMatch | undefined {
    let bestMatch: VideoCompatibilityProfileMatch | undefined = undefined;
    let conflict: boolean = false;
    for (let index: number = 0; index < profiles.length; index += 1) {
      const definition = profiles[index];
      const candidate = this.resolveProfileMatch(definition, parsed);
      if (candidate === undefined) {
        continue;
      }
      if (bestMatch === undefined || this.isMoreSpecific(candidate, bestMatch)) {
        bestMatch = candidate;
        conflict = false;
        continue;
      }
      if (this.hasEqualSpecificity(candidate, bestMatch)) {
        conflict = true;
      }
    }
    return conflict ? undefined : bestMatch;
  }

  private resolveProfileMatch(
    definition: NormalizedVideoCompatibilityProfileDefinition,
    parsed: ParsedProfileUrl
  ): VideoCompatibilityProfileMatch | undefined {
    const scope = definition.scope;
    let hostSpecificity: number = 0;
    if (this.containsString(scope.exactHosts, parsed.host)) {
      hostSpecificity = EXACT_HOST_SPECIFICITY;
    } else {
      if (this.matchesAnchoredSubdomain(scope.anchoredSubdomainHosts, parsed.host)) {
        hostSpecificity = ANCHORED_SUBDOMAIN_HOST_SPECIFICITY;
      }
    }
    if (hostSpecificity <= 0 || !this.hasAllRequiredQueryKeys(scope.requiredQueryKeys, parsed.queryKeys)) {
      return undefined;
    }
    const pathPrefixLength = this.resolvePathPrefixLength(scope.pathPrefixes, parsed.path);
    if (pathPrefixLength < 0) {
      return undefined;
    }
    return {
      definition: definition,
      hostSpecificity: hostSpecificity,
      pathPrefixLength: pathPrefixLength
    };
  }

  private isMoreSpecific(
    candidate: VideoCompatibilityProfileMatch,
    current: VideoCompatibilityProfileMatch
  ): boolean {
    if (candidate.hostSpecificity !== current.hostSpecificity) {
      return candidate.hostSpecificity > current.hostSpecificity;
    }
    return candidate.pathPrefixLength > current.pathPrefixLength;
  }

  private hasEqualSpecificity(
    left: VideoCompatibilityProfileMatch,
    right: VideoCompatibilityProfileMatch
  ): boolean {
    return left.hostSpecificity === right.hostSpecificity &&
      left.pathPrefixLength === right.pathPrefixLength;
  }

  private matchesAnchoredSubdomain(hosts: string[], pageHost: string): boolean {
    for (let index: number = 0; index < hosts.length; index += 1) {
      const host = hosts[index];
      if (pageHost.length > host.length && pageHost.endsWith('.' + host)) {
        return true;
      }
    }
    return false;
  }

  private resolvePathPrefixLength(prefixes: string[], pagePath: string): number {
    if (prefixes.length <= 0) {
      return 0;
    }
    let bestLength: number = -1;
    for (let index: number = 0; index < prefixes.length; index += 1) {
      const prefix = prefixes[index];
      if (this.pathMatchesPrefix(pagePath, prefix) && prefix.length > bestLength) {
        bestLength = prefix.length;
      }
    }
    return bestLength;
  }

  private pathMatchesPrefix(path: string, prefix: string): boolean {
    if (prefix === '/') {
      return true;
    }
    if (!path.startsWith(prefix)) {
      return false;
    }
    if (prefix.endsWith('/')) {
      return true;
    }
    return path.length === prefix.length || path.charAt(prefix.length) === '/';
  }

  private hasAllRequiredQueryKeys(requiredKeys: string[], actualKeys: string[]): boolean {
    for (let requiredIndex: number = 0; requiredIndex < requiredKeys.length; requiredIndex += 1) {
      if (!this.containsString(actualKeys, requiredKeys[requiredIndex])) {
        return false;
      }
    }
    return true;
  }

  private hasEqualSpecificityConflict(
    definitions: NormalizedVideoCompatibilityProfileDefinition[]
  ): boolean {
    for (let leftIndex: number = 0; leftIndex < definitions.length; leftIndex += 1) {
      for (let rightIndex: number = leftIndex + 1; rightIndex < definitions.length; rightIndex += 1) {
        if (this.scopesCanTie(definitions[leftIndex].scope, definitions[rightIndex].scope)) {
          return true;
        }
      }
    }
    return false;
  }

  private scopesCanTie(
    left: NormalizedVideoCompatibilityProfileScope,
    right: NormalizedVideoCompatibilityProfileScope
  ): boolean {
    return this.hostScopesCanTie(left, right) && this.pathScopesCanTie(left.pathPrefixes, right.pathPrefixes);
  }

  private hostScopesCanTie(
    left: NormalizedVideoCompatibilityProfileScope,
    right: NormalizedVideoCompatibilityProfileScope
  ): boolean {
    return this.haveCommonString(left.exactHosts, right.exactHosts) ||
      this.anchoredHostScopesCanOverlap(left.anchoredSubdomainHosts, right.anchoredSubdomainHosts);
  }

  private anchoredHostScopesCanOverlap(leftHosts: string[], rightHosts: string[]): boolean {
    for (let leftIndex: number = 0; leftIndex < leftHosts.length; leftIndex += 1) {
      for (let rightIndex: number = 0; rightIndex < rightHosts.length; rightIndex += 1) {
        const left = leftHosts[leftIndex];
        const right = rightHosts[rightIndex];
        if (left === right || left.endsWith('.' + right) || right.endsWith('.' + left)) {
          return true;
        }
      }
    }
    return false;
  }

  private pathScopesCanTie(leftPrefixes: string[], rightPrefixes: string[]): boolean {
    if (leftPrefixes.length <= 0 || rightPrefixes.length <= 0) {
      return leftPrefixes.length <= 0 && rightPrefixes.length <= 0;
    }
    return this.haveCommonString(leftPrefixes, rightPrefixes);
  }

  private normalizeDefinitions(
    definitions: VideoCompatibilityProfileDefinition[]
  ): NormalizedVideoCompatibilityProfileDefinition[] {
    const normalized: NormalizedVideoCompatibilityProfileDefinition[] = [];
    for (let index: number = 0; index < definitions.length; index += 1) {
      const definition = this.normalizeDefinition(definitions[index]);
      if (definition !== undefined) {
        normalized.push(definition);
      }
    }
    return normalized;
  }

  private normalizeDefinition(
    definition: VideoCompatibilityProfileDefinition
  ): NormalizedVideoCompatibilityProfileDefinition | undefined {
    const profileKey = this.normalizeDiagnosticProfileKey(definition.diagnosticProfileKey);
    const revision = definition.revision.trim();
    if (profileKey === undefined || revision.length <= 0) {
      return undefined;
    }
    const scope = this.normalizeScope(definition.scope);
    if (scope === undefined) {
      return undefined;
    }
    const selectors = this.normalizeSelectorDefinitions(definition.selectors ?? []);
    if (selectors === undefined) {
      return undefined;
    }
    const suppressedHeuristicSources = this.normalizeSuppressedHeuristicSources(
      definition.suppressedHeuristicSources ?? []
    );
    if (suppressedHeuristicSources === undefined) {
      return undefined;
    }
    const acquisitionRecipe = this.normalizeAcquisitionRecipe(definition.acquisitionRecipe);
    if (acquisitionRecipe === null) {
      return undefined;
    }
    const presentationRecipe = this.normalizePresentationRecipe(definition.presentationRecipe);
    if (presentationRecipe === null) {
      return undefined;
    }
    return {
      diagnosticProfileKey: profileKey,
      revision: revision,
      scope: scope,
      enabled: definition.enabled !== false,
      selectors: selectors,
      suppressedHeuristicSources: suppressedHeuristicSources,
      acquisitionRecipe: acquisitionRecipe ?? undefined,
      presentationRecipe: presentationRecipe ?? undefined
    };
  }

  private normalizeSelectorDefinitions(
    definitions: VideoCompatibilityProfileSelectorDefinition[]
  ): VideoCompatibilityProfileSelectorPlan[] | undefined {
    const MAX_SELECTOR_COUNT: number = 8;
    if (definitions.length > MAX_SELECTOR_COUNT) {
      return undefined;
    }
    const normalized: VideoCompatibilityProfileSelectorPlan[] = [];
    for (let index: number = 0; index < definitions.length; index += 1) {
      const plan = this.normalizeSelectorDefinition(definitions[index]);
      if (plan === undefined) {
        return undefined;
      }
      if (this.containsSelectorPlan(normalized, plan)) {
        return undefined;
      }
      normalized.push(plan);
    }
    return normalized;
  }

  private normalizeSelectorDefinition(
    definition: VideoCompatibilityProfileSelectorDefinition
  ): VideoCompatibilityProfileSelectorPlan | undefined {
    const selector = definition.selector.trim();
    if (selector.length <= 0 || selector.length > 128 || !this.isClosedMediaSelector(selector)) {
      return undefined;
    }
    if (definition.evidenceKind !== 'structured' && definition.evidenceKind !== 'heuristic') {
      return undefined;
    }
    if (definition.mediaStructure !== 'video' && definition.mediaStructure !== 'audio') {
      return undefined;
    }
    if (definition.attribute !== 'presence' && definition.attribute !== 'source' &&
      definition.attribute !== 'poster' && definition.attribute !== 'dimensions') {
      return undefined;
    }
    const frameScope = definition.frameScope ?? 'top_document';
    const originScope = definition.originScope ?? 'top_origin';
    if (frameScope !== 'top_document' || originScope !== 'top_origin') {
      return undefined;
    }
    if (selector.indexOf('video') === 0 && definition.mediaStructure !== 'video') {
      return undefined;
    }
    if (selector.indexOf('audio') === 0 && definition.mediaStructure !== 'audio') {
      return undefined;
    }
    return {
      selector: selector,
      evidenceKind: definition.evidenceKind,
      mediaStructure: definition.mediaStructure,
      attribute: definition.attribute,
      frameScope: frameScope,
      originScope: originScope
    };
  }

  private isClosedMediaSelector(selector: string): boolean {
    const tag = selector.indexOf('video') === 0 ? 'video' : selector.indexOf('audio') === 0 ? 'audio' : '';
    if (tag.length <= 0) {
      return false;
    }
    let index = tag.length;
    let suffixCount = 0;
    while (index < selector.length) {
      const marker = selector.charAt(index);
      if (marker !== '.' && marker !== '#') {
        return false;
      }
      index += 1;
      const start = index;
      if (index >= selector.length || !this.isSelectorIdentifierStart(selector.charAt(index))) {
        return false;
      }
      while (index < selector.length && this.isSelectorIdentifierCharacter(selector.charAt(index))) {
        index += 1;
      }
      if (index === start || index - start > 48) {
        return false;
      }
      suffixCount += 1;
      if (suffixCount > 4) {
        return false;
      }
    }
    return true;
  }

  private isSelectorIdentifierCharacter(value: string): boolean {
    const code = value.charCodeAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) ||
      (code >= 48 && code <= 57) || value === '_' || value === '-';
  }

  private isSelectorIdentifierStart(value: string): boolean {
    const code = value.charCodeAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || value === '_' || value === '-';
  }

  private containsSelectorPlan(
    plans: VideoCompatibilityProfileSelectorPlan[],
    target: VideoCompatibilityProfileSelectorPlan
  ): boolean {
    for (let index: number = 0; index < plans.length; index += 1) {
      const plan = plans[index];
      if (plan.selector === target.selector && plan.evidenceKind === target.evidenceKind &&
        plan.mediaStructure === target.mediaStructure && plan.attribute === target.attribute) {
        return true;
      }
    }
    return false;
  }

  private normalizeSuppressedHeuristicSources(
    values: VideoCompatibilityHeuristicSource[]
  ): VideoCompatibilityHeuristicSource[] | undefined {
    const normalized: VideoCompatibilityHeuristicSource[] = [];
    if (values.length > 2) {
      return undefined;
    }
    for (let index: number = 0; index < values.length; index += 1) {
      const value = values[index];
      if (value !== 'generic_dom_probe' && value !== 'generic_deep_probe') {
        return undefined;
      }
      if (normalized.indexOf(value) >= 0) {
        return undefined;
      }
      normalized.push(value);
    }
    return normalized;
  }

  private normalizePresentationRecipe(
    value: VideoCompatibilityProfilePresentationRecipe | undefined
  ): VideoCompatibilityProfilePresentationRecipe | null | undefined {
    if (value === undefined) {
      return undefined;
    }
    return value === 'weibo_preserve_surface' ? value : null;
  }

  private normalizeAcquisitionRecipe(
    value: VideoCompatibilityProfileAcquisitionRecipe | undefined
  ): VideoCompatibilityProfileAcquisitionRecipe | null | undefined {
    if (value === undefined) {
      return undefined;
    }
    return value === 'bilibili_play_info' || value === 'youtube_player' || value === 'xlplayer_lines' ? value : null;
  }

  private clearAcquisitionScheduler(resolution: VideoCompatibilityProfileResolution, tabId: string): void {
    resolution.getAcquisitionCapability()?.getScheduler()?.clearTab(tabId);
  }

  private normalizeDiagnosticProfileKey(value: string): string | undefined {
    const key = value.trim();
    if (key.length <= 0 || key.length > MAX_DIAGNOSTIC_PROFILE_KEY_LENGTH) {
      return undefined;
    }
    for (let index: number = 0; index < key.length; index += 1) {
      const code = key.charCodeAt(index);
      const alpha = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
      const numeric = code >= 48 && code <= 57;
      const char = key.charAt(index);
      if (!alpha && !numeric && char !== '.' && char !== '-' && char !== '_' && char !== ':') {
        return undefined;
      }
    }
    return key;
  }

  private normalizeScope(
    scope: VideoCompatibilityProfileScopeDefinition
  ): NormalizedVideoCompatibilityProfileScope | undefined {
    const exactHosts = this.normalizeHosts(scope.exactHosts ?? []);
    const anchoredSubdomainHosts = this.normalizeHosts(scope.anchoredSubdomainHosts ?? []);
    if (exactHosts.length <= 0 && anchoredSubdomainHosts.length <= 0) {
      return undefined;
    }
    return {
      exactHosts: exactHosts,
      anchoredSubdomainHosts: anchoredSubdomainHosts,
      pathPrefixes: this.normalizePathPrefixes(scope.pathPrefixes ?? []),
      requiredQueryKeys: this.normalizeQueryKeys(scope.requiredQueryKeys ?? [])
    };
  }

  private normalizeHosts(values: string[]): string[] {
    const hosts: string[] = [];
    for (let index: number = 0; index < values.length; index += 1) {
      const host = values[index].trim().toLowerCase();
      if (host.length <= 0 || host.indexOf('*') >= 0 || host.indexOf('/') >= 0 || host.indexOf(':') >= 0 ||
        !this.isClosedHost(host) || this.containsString(hosts, host)) {
        continue;
      }
      hosts.push(host);
    }
    return hosts;
  }

  private isClosedHost(value: string): boolean {
    if (value.startsWith('.') || value.endsWith('.') || value.indexOf('..') >= 0) {
      return false;
    }
    for (let index: number = 0; index < value.length; index += 1) {
      const code = value.charCodeAt(index);
      const alpha = (code >= 97 && code <= 122);
      const numeric = (code >= 48 && code <= 57);
      const char = value.charAt(index);
      if (!alpha && !numeric && char !== '-' && char !== '.') {
        return false;
      }
    }
    return true;
  }

  private normalizePathPrefixes(values: string[]): string[] {
    const prefixes: string[] = [];
    for (let index: number = 0; index < values.length; index += 1) {
      const prefix = this.normalizePathPrefix(values[index]);
      if (prefix.length > 0 && !this.containsString(prefixes, prefix)) {
        prefixes.push(prefix);
      }
    }
    return prefixes;
  }

  private normalizePathPrefix(value: string): string {
    const trimmed = value.trim();
    if (trimmed.length <= 0 || trimmed.indexOf('?') >= 0 || trimmed.indexOf('#') >= 0 || trimmed.indexOf('*') >= 0) {
      return '';
    }
    let path = trimmed.startsWith('/') ? trimmed : '/' + trimmed;
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  private normalizeQueryKeys(values: string[]): string[] {
    const keys: string[] = [];
    for (let index: number = 0; index < values.length; index += 1) {
      const key = values[index].trim().toLowerCase();
      if (key.length <= 0 || key.indexOf('=') >= 0 || key.indexOf('&') >= 0 || key.indexOf('?') >= 0 ||
        !this.isClosedQueryKey(key) || this.containsString(keys, key)) {
        continue;
      }
      keys.push(key);
    }
    return keys;
  }

  private isClosedQueryKey(value: string): boolean {
    for (let index: number = 0; index < value.length; index += 1) {
      const code = value.charCodeAt(index);
      const alpha = (code >= 97 && code <= 122);
      const numeric = (code >= 48 && code <= 57);
      if (!alpha && !numeric && value.charAt(index) !== '_' && value.charAt(index) !== '-') {
        return false;
      }
    }
    return true;
  }

  private parseProfileUrl(pageUrl: string): ParsedProfileUrl | undefined {
    try {
      const parsed = urlUtils.URL.parseURL(pageUrl.trim());
      const protocol = parsed.protocol.trim().toLowerCase();
      const host = parsed.hostname.trim().toLowerCase();
      if (host.length <= 0) {
        return undefined;
      }
      return {
        protocol: protocol,
        host: host,
        path: this.normalizeParsedPath(parsed.pathname),
        queryKeys: this.parseQueryKeys(parsed.search)
      };
    } catch (_error) {
      return undefined;
    }
  }

  private normalizeParsedPath(value: string): string {
    const trimmed = value.trim();
    return trimmed.length > 0 && trimmed.startsWith('/') ? trimmed : '/';
  }

  private parseQueryKeys(search: string): string[] {
    const keys: string[] = [];
    const query = search.startsWith('?') ? search.substring(1) : search;
    if (query.length <= 0) {
      return keys;
    }
    const parts = query.split('&');
    for (let index: number = 0; index < parts.length; index += 1) {
      const part = parts[index];
      if (part.length <= 0) {
        continue;
      }
      const equalsIndex = part.indexOf('=');
      const rawKey = equalsIndex >= 0 ? part.substring(0, equalsIndex) : part;
      const key = rawKey.trim().toLowerCase();
      if (key.length > 0 && !this.containsString(keys, key)) {
        keys.push(key);
      }
    }
    return keys;
  }

  private buildScopeKey(scope: MediaEvidenceScope): string {
    return this.encodeScopeKeyPart(scope.tabId) +
      this.encodeScopeKeyPart(scope.generationId) +
      this.encodeScopeKeyPart(scope.routeEpochId);
  }

  private encodeScopeKeyPart(value: string): string {
    return value.length.toString() + ':' + value;
  }

  private sameScope(left: MediaEvidenceScope, right: MediaEvidenceScope): boolean {
    return left.tabId === right.tabId &&
      left.generationId === right.generationId &&
      left.routeEpochId === right.routeEpochId;
  }

  private containsString(values: string[], target: string): boolean {
    for (let index: number = 0; index < values.length; index += 1) {
      if (values[index] === target) {
        return true;
      }
    }
    return false;
  }

  private haveCommonString(left: string[], right: string[]): boolean {
    for (let index: number = 0; index < left.length; index += 1) {
      if (this.containsString(right, left[index])) {
        return true;
      }
    }
    return false;
  }
}

export const sharedVideoCompatibilityProfileCatalog: VideoCompatibilityProfileCatalog =
  new VideoCompatibilityProfileCatalog([{
    diagnosticProfileKey: 'packaged.weibo',
    revision: 'packaged-1',
    scope: {
      exactHosts: ['m.weibo.cn']
    },
    presentationRecipe: 'weibo_preserve_surface'
  }, {
    // Large-screen ArkWeb keeps this site's playing video surface valid when
    // the takeover expands the Web component instead of promoting the DOM
    // video to a new fixed-position surface.
    diagnosticProfileKey: 'packaged.haokan-baidu',
    revision: 'packaged-1',
    scope: {
      exactHosts: ['haokan.baidu.com']
    },
    presentationRecipe: 'weibo_preserve_surface'
  }, {
    diagnosticProfileKey: 'packaged.bilibili',
    revision: 'packaged-1',
    scope: {
      exactHosts: ['www.bilibili.com']
    },
    acquisitionRecipe: 'bilibili_play_info'
  }, {
    diagnosticProfileKey: 'packaged.xlplayer-xl01',
    revision: 'packaged-1',
    scope: {
      exactHosts: ['v.xl01.eu.cc']
    },
    acquisitionRecipe: 'xlplayer_lines'
  }, {
    diagnosticProfileKey: 'packaged.youtube',
    revision: 'packaged-1',
    scope: {
      exactHosts: ['youtube.com', 'www.youtube.com'],
      pathPrefixes: ['/watch', '/shorts', '/embed']
    },
    acquisitionRecipe: 'youtube_player'
  }, {
    diagnosticProfileKey: 'packaged.youtube-mobile',
    revision: 'packaged-1',
    scope: {
      exactHosts: ['m.youtube.com'],
      pathPrefixes: ['/watch', '/shorts', '/embed']
    },
    acquisitionRecipe: 'youtube_player'
  }, {
    diagnosticProfileKey: 'packaged.youtube-music',
    revision: 'packaged-1',
    scope: {
      exactHosts: ['music.youtube.com'],
      pathPrefixes: ['/watch', '/shorts', '/embed']
    },
    acquisitionRecipe: 'youtube_player'
  }, {
    diagnosticProfileKey: 'packaged.youtu-be',
    revision: 'packaged-1',
    scope: {
      exactHosts: ['youtu.be'],
      pathPrefixes: ['/']
    },
    acquisitionRecipe: 'youtube_player'
  }]);
