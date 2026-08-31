import { SitePermissionKind } from '../../common/models/BrowserModels';

export interface TabMutationCommitOptions {
  syncRuntimeGraph?: boolean;
  refreshRuntimeTabIds?: string[];
  persistTabs?: boolean;
}

export interface CreateNewTabRuntimeOptions {
  skipCurrentTabPreviewForForegroundOpen?: boolean;
  restoreAsColdStart?: boolean;
}

export interface PendingWebPermissionRequest {
  tabId: string;
  origin: string;
  resources: string[];
  kinds: SitePermissionKind[];
  promptItems: PendingWebPermissionPromptItem[];
  currentPromptIndex: number;
  request: PermissionRequest;
}

export interface PendingWebPermissionPromptItem {
  resource: string;
  kind: SitePermissionKind;
}

export type BrowserSystemSheetType =
  'none' |
  'releaseNotice' |
  'desktopLoginConfirm' |
  'homeSettings' |
  'homeShortcutSelection' |
  'userScriptInstall' |
  'userScriptPageActions' |
  'webPageTools' |
  'appProxyQuick' |
  'readerText' |
  'readerAppearance' |
  'readerSettings' |
  'novelCatalog' |
  'novelReaderText' |
  'novelReaderAppearance' |
  'novelReaderSettings' |
  'crossDeviceTabs' |
  'resourceCandidates';

export interface PendingGeolocationPermissionRequest {
  tabId: string;
  origin: string;
  geolocation: JsGeolocation;
}

export type PendingSitePermissionPromptType = 'protected_resource' | 'geolocation';

export interface PendingSitePermissionPromptState {
  type: PendingSitePermissionPromptType;
  protectedResourceRequest?: PendingWebPermissionRequest;
  geolocationRequest?: PendingGeolocationPermissionRequest;
}

export interface PendingHttpAuthState {
  event?: OnHttpAuthRequestEvent;
  tabId: string;
  requestHost: string;
  isProxyAuthentication: boolean;
}

export interface PendingSslErrorState {
  event?: SslErrorEvent;
  tabId: string;
  httpFallbackUrl?: string;
}
