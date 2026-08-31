export type UserScriptRunAt =
  'document-start' |
  'document-idle' |
  'document-end' |
  'main-menu' |
  'tool-menu' |
  'context-menu';

export type UserScriptGrant =
  'none' |
  'GM_addStyle' |
  'GM_addElement' |
  'GM_getValue' |
  'GM_getValues' |
  'GM_setValue' |
  'GM_setValues' |
  'GM_deleteValue' |
  'GM_deleteValues' |
  'GM_listValues' |
  'GM_getResourceText' |
  'GM_getResourceURL' |
  'GM_xmlhttpRequest' |
  'GM_fetch' |
  'GM_download' |
  'GM_openInTab' |
  'GM_getTab' |
  'GM_saveTab' |
  'GM_getTabs' |
  'GM_setClipboard' |
  'GM_log' |
  'GM_notification' |
  'GM_info' |
  'GM_registerMenuCommand' |
  'GM_unregisterMenuCommand' |
  'GM_addValueChangeListener' |
  'GM_removeValueChangeListener' |
  'GM_EX_getSearchEngines' |
  'GM_EX_getAppSearchEngineUrl' |
  'GM_EX_TTS' |
  'GM_EX_ShareTextToApp' |
  'GM_EX_sniffMedia' |
  'window.onurlchange' |
  'window.close' |
  'window.focus' |
  'unsafeWindow';

export type UserScriptPackageSource = 'paste' | 'url' | 'file';
export type UserScriptInstallSource = UserScriptPackageSource | 'gallery';

export function resolveUserScriptPackageSource(
  installSource: UserScriptInstallSource,
  sourceUrl: string
): UserScriptPackageSource {
  if (installSource === 'file') {
    return 'file';
  }
  if (installSource === 'url' || (installSource === 'gallery' && sourceUrl.trim().length > 0)) {
    return 'url';
  }
  return 'paste';
}

export interface UserScriptResourceDeclaration {
  name: string;
  url: string;
}

export interface UserScriptResourceRecord extends UserScriptResourceDeclaration {
  text: string;
  mimeType: string;
  contentBase64?: string;
}

export interface UserScriptPackageCandidate {
  name: string;
  namespace: string;
  version: string;
  description: string;
  iconUrl: string;
  source: string;
  sourceUrl: string;
  updateUrl: string;
  downloadUrl: string;
  matches: string[];
  includes: string[];
  excludeMatches: string[];
  excludes: string[];
  grants: UserScriptGrant[];
  requireUrls: string[];
  resourceDeclarations: UserScriptResourceDeclaration[];
  connectRules: string[];
  noframes: boolean;
  runAt: UserScriptRunAt;
  installSource: UserScriptPackageSource;
}

export interface UserScriptMaterializedDependencies {
  requireSources: string[];
  resources: UserScriptResourceRecord[];
}

export interface UserScriptExportPayload {
  name: string;
  source: string;
}

export interface InstalledUserScriptState {
  id: string;
  name: string;
  namespace: string;
  version: string;
  description: string;
  iconUrl: string;
  source: string;
  sourceUrl: string;
  updateUrl: string;
  downloadUrl: string;
  enabled: boolean;
  matches: string[];
  includes: string[];
  excludeMatches: string[];
  excludes: string[];
  grants: UserScriptGrant[];
  requireUrls: string[];
  requireSources: string[];
  resources: UserScriptResourceRecord[];
  connectRules: string[];
  noframes: boolean;
  runAt: UserScriptRunAt;
  installSource: UserScriptInstallSource;
  createdAt: number;
  updatedAt: number;
  lastCheckedAt: number;
}

export interface UserScriptMetadataParseResult {
  valid: boolean;
  candidate?: UserScriptPackageCandidate;
  warnings: string[];
  errorMessage: string;
}

export interface UserScriptSettings {
  scripts: InstalledUserScriptState[];
  autoUpdateEnabled: boolean;
  updatedAt: number;
}

export function cloneUserScriptPackageCandidate(candidate: UserScriptPackageCandidate): UserScriptPackageCandidate {
  return {
    name: candidate.name,
    namespace: candidate.namespace,
    version: candidate.version,
    description: candidate.description,
    iconUrl: candidate.iconUrl,
    source: candidate.source,
    sourceUrl: candidate.sourceUrl,
    updateUrl: candidate.updateUrl,
    downloadUrl: candidate.downloadUrl,
    matches: candidate.matches.slice(),
    includes: candidate.includes.slice(),
    excludeMatches: candidate.excludeMatches.slice(),
    excludes: candidate.excludes.slice(),
    grants: candidate.grants.slice(),
    requireUrls: candidate.requireUrls.slice(),
    resourceDeclarations: candidate.resourceDeclarations.map(
      (resource: UserScriptResourceDeclaration): UserScriptResourceDeclaration => {
        return {
          name: resource.name,
          url: resource.url
        };
      }
    ),
    connectRules: candidate.connectRules.slice(),
    noframes: candidate.noframes,
    runAt: candidate.runAt,
    installSource: candidate.installSource
  };
}

export function cloneInstalledUserScriptState(state: InstalledUserScriptState): InstalledUserScriptState {
  return {
    id: state.id,
    name: state.name,
    namespace: state.namespace,
    version: state.version,
    description: state.description,
    iconUrl: state.iconUrl,
    source: state.source,
    sourceUrl: state.sourceUrl,
    updateUrl: state.updateUrl,
    downloadUrl: state.downloadUrl,
    enabled: state.enabled,
    matches: state.matches.slice(),
    includes: state.includes.slice(),
    excludeMatches: state.excludeMatches.slice(),
    excludes: state.excludes.slice(),
    grants: state.grants.slice(),
    requireUrls: state.requireUrls.slice(),
    requireSources: state.requireSources.slice(),
    resources: cloneUserScriptResources(state.resources),
    connectRules: state.connectRules.slice(),
    noframes: state.noframes === true,
    runAt: state.runAt,
    installSource: state.installSource,
    createdAt: state.createdAt,
    updatedAt: state.updatedAt,
    lastCheckedAt: state.lastCheckedAt
  };
}

export function createInstalledUserScriptState(
  candidate: UserScriptPackageCandidate,
  dependencies: UserScriptMaterializedDependencies,
  installedAt: number
): InstalledUserScriptState {
  return {
    id: buildUserScriptId(candidate.name, installedAt),
    name: candidate.name,
    namespace: candidate.namespace,
    version: candidate.version,
    description: candidate.description,
    iconUrl: candidate.iconUrl,
    source: candidate.source,
    sourceUrl: candidate.sourceUrl,
    updateUrl: candidate.updateUrl,
    downloadUrl: candidate.downloadUrl,
    enabled: true,
    matches: candidate.matches.slice(),
    includes: candidate.includes.slice(),
    excludeMatches: candidate.excludeMatches.slice(),
    excludes: candidate.excludes.slice(),
    grants: candidate.grants.slice(),
    requireUrls: candidate.requireUrls.slice(),
    requireSources: dependencies.requireSources.slice(),
    resources: cloneUserScriptResources(dependencies.resources),
    connectRules: candidate.connectRules.slice(),
    noframes: candidate.noframes,
    runAt: candidate.runAt,
    installSource: candidate.installSource,
    createdAt: installedAt,
    updatedAt: installedAt,
    lastCheckedAt: 0
  };
}

export function replaceInstalledUserScriptPackage(
  candidate: UserScriptPackageCandidate,
  dependencies: UserScriptMaterializedDependencies,
  installed: InstalledUserScriptState,
  lastCheckedAt: number,
  updatedAt: number
): InstalledUserScriptState {
  return {
    id: installed.id,
    name: candidate.name,
    namespace: candidate.namespace,
    version: candidate.version,
    description: candidate.description,
    iconUrl: candidate.iconUrl.length > 0 ? candidate.iconUrl : installed.iconUrl,
    source: candidate.source,
    sourceUrl: installed.sourceUrl,
    updateUrl: candidate.updateUrl,
    downloadUrl: candidate.downloadUrl,
    enabled: installed.enabled,
    matches: candidate.matches.slice(),
    includes: candidate.includes.slice(),
    excludeMatches: candidate.excludeMatches.slice(),
    excludes: candidate.excludes.slice(),
    grants: candidate.grants.slice(),
    requireUrls: candidate.requireUrls.slice(),
    requireSources: dependencies.requireSources.slice(),
    resources: cloneUserScriptResources(dependencies.resources),
    connectRules: candidate.connectRules.slice(),
    noframes: candidate.noframes,
    runAt: candidate.runAt,
    installSource: installed.installSource,
    createdAt: installed.createdAt,
    updatedAt: updatedAt,
    lastCheckedAt: lastCheckedAt
  };
}

export function setInstalledUserScriptEnabled(
  state: InstalledUserScriptState,
  enabled: boolean,
  updatedAt: number
): InstalledUserScriptState {
  const updated = cloneInstalledUserScriptState(state);
  updated.enabled = enabled;
  updated.updatedAt = updatedAt;
  return updated;
}

export function markInstalledUserScriptChecked(
  state: InstalledUserScriptState,
  checkedAt: number
): InstalledUserScriptState {
  const checked = cloneInstalledUserScriptState(state);
  checked.lastCheckedAt = checkedAt;
  return checked;
}

function cloneUserScriptResources(resources: UserScriptResourceRecord[]): UserScriptResourceRecord[] {
  return resources.map((resource: UserScriptResourceRecord): UserScriptResourceRecord => {
    return {
      name: resource.name,
      url: resource.url,
      text: resource.text,
      mimeType: resource.mimeType,
      contentBase64: resource.contentBase64
    };
  });
}

function buildUserScriptId(name: string, now: number): string {
  const slug = name.trim().toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return `userscript-${slug.length > 0 ? slug : 'script'}-${now}`;
}
