import { BookmarkNodeType } from './BrowserModels';

export const AIRA_SYNC_SCHEMA_VERSION: number = 2;
export const AIRA_SYNC_DEFAULT_ROOT: string = 'aira/g3/bookmarks';
export const AIRA_SYNC_ROOT_ORDER_KEY: string = '__root__';
export const AIRA_BOOKMARK_SYNC_PROTOCOL_ID: string = 'bookmark-snapshot-v3';
// Aira Cloud and the browser extension share one deliberately breaking protocol epoch.
// WebDAV keeps its file envelope identity above; this token identifies the hosted API only.
export const AIRA_CLOUD_BOOKMARK_SYNC_PROTOCOL_ID: string = 'aira-cloud-bookmarks-v4';
export const AIRA_CLOUD_BOOKMARK_SYNC_GENERATION: number = 4;
export const AIRA_BOOKMARK_HISTORY_VERSION: number = 1;
export const AIRA_BOOKMARK_TOMBSTONE_RETENTION_MS: number = 90 * 24 * 60 * 60 * 1000;

export function buildAiraWebdavRemoteStatusProviderKey(
  endpoint: string,
  username: string,
  rootPath: string = AIRA_SYNC_DEFAULT_ROOT
): string {
  const normalizedEndpoint = endpoint.trim().replace(/\/+$/, '');
  const normalizedRootPath = rootPath.trim().replace(/^\/+/, '').replace(/\/+$/, '') || AIRA_SYNC_DEFAULT_ROOT;
  return [
    'webdav',
    AIRA_BOOKMARK_SYNC_PROTOCOL_ID,
    normalizedEndpoint,
    username.trim(),
    normalizedRootPath
  ].map((value: string) => encodeURIComponent(value)).join('|');
}

export function buildAiraHuaweiSpaceRemoteStatusProviderKey(
  uid: string,
  databaseName: string,
  rootPath: string = AIRA_SYNC_DEFAULT_ROOT
): string {
  return [
    'huawei_space',
    'bookmark-g8-blocks-v1',
    uid.trim(),
    databaseName.trim(),
    rootPath.trim()
  ].map((value: string): string => encodeURIComponent(value)).join('|');
}

export function buildAiraPersonalServerRemoteStatusProviderKey(
  instanceId: string,
  baseUrl: string
): string {
  return [
    'self_hosted',
    AIRA_CLOUD_BOOKMARK_SYNC_PROTOCOL_ID,
    instanceId.trim(),
    baseUrl.trim().replace(/\/+$/, '')
  ].map((value: string): string => encodeURIComponent(value)).join('|');
}

export interface AiraSyncSnapshotMeta {
  version: number;
  deviceId: string;
  generatedAt: string;
}

export interface AiraBookmarkHistoryDescriptor {
  version: number;
  epochId: string;
  retainedFrom: string;
}

export interface AiraSyncBaseEntity {
  id: string;
  type: string;
  createdAt: string;
  updatedAt: string;
  updatedBy: string;
  revision: number;
}

export interface AiraSyncBookmarkFolderEntity extends AiraSyncBaseEntity {
  type: 'bookmark-folder';
  parentId: string | null;
  title: string;
}

export interface AiraSyncBookmarkItemEntity extends AiraSyncBaseEntity {
  type: 'bookmark-item';
  parentId: string | null;
  title: string;
  url: string;
}

export interface AiraSyncBookmarkOrder {
  type: 'bookmark-order';
  parentId: string | null;
  ids: string[];
  updatedAt: string;
  updatedBy: string;
  revision: number;
}

export interface AiraSyncTombstone {
  id: string;
  type: 'bookmark-folder' | 'bookmark-item';
  deletedAt: string;
  deletedBy: string;
  lastKnownRevision: number;
}

export interface AiraSyncCommitSummary {
  bookmarkFolders: number;
  bookmarkItems: number;
  tombstones: number;
}

export interface AiraSyncSnapshot {
  meta: AiraSyncSnapshotMeta;
  bookmarkFolders: AiraSyncBookmarkFolderEntity[];
  bookmarkItems: AiraSyncBookmarkItemEntity[];
  bookmarkOrders: AiraSyncBookmarkOrder[];
  tombstones: AiraSyncTombstone[];
  appPrivateBookmarks?: AiraSyncBookmarkDataSet;
}

export interface AiraSyncBookmarkDataSet {
  bookmarkFolders: AiraSyncBookmarkFolderEntity[];
  bookmarkItems: AiraSyncBookmarkItemEntity[];
  bookmarkOrders: AiraSyncBookmarkOrder[];
  tombstones: AiraSyncTombstone[];
}

export interface AiraBookmarkImportNode {
  id: string;
  type: BookmarkNodeType;
  parentId?: string;
  title: string;
  url?: string;
  position: number;
  sourceEntityId: string;
  createdAt: number;
  updatedAt: number;
}

export interface AiraBookmarkImportPlan {
  nodes: AiraBookmarkImportNode[];
  rootOrderIds: string[];
  summary: string;
}

export interface AiraBookmarkImportApplyResult {
  batchId: string;
  importedFolderCount: number;
  importedBookmarkCount: number;
  skippedNodeCount: number;
  duplicateCount: number;
  summary: string;
}

export interface AiraBookmarkSyncApplyResult {
  upsertedFolderCount: number;
  upsertedBookmarkCount: number;
  deletedNodeCount: number;
  skippedNodeCount: number;
  blocked: boolean;
  summary: string;
}

export interface AiraBookmarkOverview {
  bookmarkFolderCount: number;
  bookmarkItemCount: number;
}

export interface AiraSyncRemoteState {
  snapshot: AiraSyncSnapshot | null;
  commitId: string | null;
  history: AiraBookmarkHistoryDescriptor | null;
}

export interface AiraSyncRemoteHead {
  commitId: string | null;
  updatedAt: number;
  bookmarkFolders: number;
  bookmarkItems: number;
  hasBookmarkSummary: boolean;
}

export interface AiraSyncWriteStateParams {
  snapshot: AiraSyncSnapshot;
  history: AiraBookmarkHistoryDescriptor;
  deviceId: string;
  parentCommitId?: string | null;
  createdAt?: string;
}

export interface AiraSyncWriteStateResult {
  commitId: string;
  writtenAt: string;
}

export interface AiraSyncRemoteStore {
  readHead?(): Promise<AiraSyncRemoteHead>;
  readState(): Promise<AiraSyncRemoteState>;
  confirmPendingWrites?(): Promise<void>;
  writeState(params: AiraSyncWriteStateParams): Promise<AiraSyncWriteStateResult>;
}

export type AiraSyncRemoteKind = 'none' | 'webdav' | 'aira_cloud' | 'huawei_space' | 'self_hosted';
export type AiraSyncProviderKind = 'webdav' | 'aira_cloud' | 'huawei_space' | 'self_hosted';
export type AiraSyncDomainId = 'bookmarks' | 'personalization';
export type AiraSyncRuntimeDomainId =
  | 'bookmark'
  | 'personalization'
  | 'bookmark_backup'
  | 'personalization_backup';
export type AiraAdditionalBackupIntervalDays = 1 | 3 | 7;
export type AiraSyncProviderHealth = 'idle' | 'healthy' | 'degraded' | 'unavailable';
export type AiraBookmarkSyncFailureStage =
  | 'authentication'
  | 'network'
  | 'remote_read_validation'
  | 'local_snapshot'
  | 'merge'
  | 'remote_commit'
  | 'remote_confirmation'
  | 'local_apply'
  | 'unknown';
export interface AiraBookmarkSyncFailure {
  code: string;
  stage: AiraBookmarkSyncFailureStage;
  safeDetail: string;
}
export interface AiraSyncDomainRuntimeState {
  providerIdentity: string;
  health: AiraSyncProviderHealth;
  lastAttemptAt: number;
  lastSuccessAt: number;
  revision: string;
  lastError: string;
  failureCode: string;
  failureStage: AiraBookmarkSyncFailureStage | '';
  failureDetail: string;
  blocked: boolean;
}
export interface AiraSyncProviderRuntimeState {
  remoteKind: AiraSyncProviderKind;
  bookmark: AiraSyncDomainRuntimeState;
  personalization: AiraSyncDomainRuntimeState;
  bookmarkBackup: AiraSyncDomainRuntimeState;
  personalizationBackup: AiraSyncDomainRuntimeState;
}

export interface AiraSyncWebdavConfig {
  endpoint: string;
  username: string;
  password: string;
  remoteStatusCache: AiraSyncRemoteStatusCache | null;
}

export interface AiraHuaweiCloudConfig {
  uid: string;
  displayName: string;
  photoUrl: string;
  remoteStatusCache: AiraSyncRemoteStatusCache | null;
  lastAuthAt: number;
}

export interface AiraHuaweiSpaceConfig {
  uid: string;
  displayName: string;
  photoUrl: string;
  databaseName: string;
  remoteStatusCache: AiraSyncRemoteStatusCache | null;
  lastAuthAt: number;
}

export interface AiraPersonalServerConfig {
  baseUrl: string;
  instanceId: string;
  protocolVersion: number;
  credentialId: string;
  deviceToken: string;
  deviceName: string;
  remoteStatusCache: AiraSyncRemoteStatusCache | null;
}

export function createDefaultAiraPersonalServerConfig(): AiraPersonalServerConfig {
  return {
    baseUrl: '',
    instanceId: '',
    protocolVersion: 0,
    credentialId: '',
    deviceToken: '',
    deviceName: 'Aira HarmonyOS',
    remoteStatusCache: null
  };
}

export function resolveAiraPersonalServerConfig(settings: AiraSyncSettings): AiraPersonalServerConfig {
  return settings.selfHosted ?? createDefaultAiraPersonalServerConfig();
}

export interface AiraHuaweiAccountIdentity {
  uid: string;
  displayName: string;
  photoUrl: string;
  lastAuthAt: number;
}

export function resolveAiraHuaweiAccountIdentity(
  huaweiCloud: AiraHuaweiCloudConfig,
  huaweiSpace: AiraHuaweiSpaceConfig
): AiraHuaweiAccountIdentity {
  const cloudUid = huaweiCloud.uid.trim();
  const spaceUid = huaweiSpace.uid.trim();
  const useSpace = cloudUid.length <= 0 || (spaceUid.length > 0 && spaceUid !== cloudUid &&
    huaweiSpace.lastAuthAt > huaweiCloud.lastAuthAt);
  const uid = useSpace ? spaceUid : cloudUid;
  const primaryDisplayName = useSpace
    ? huaweiSpace.displayName.trim()
    : huaweiCloud.displayName.trim();
  const secondaryDisplayName = useSpace
    ? huaweiCloud.displayName.trim()
    : huaweiSpace.displayName.trim();
  const primaryPhotoUrl = useSpace
    ? huaweiSpace.photoUrl.trim()
    : huaweiCloud.photoUrl.trim();
  const secondaryPhotoUrl = useSpace
    ? huaweiCloud.photoUrl.trim()
    : huaweiSpace.photoUrl.trim();
  const sameIdentity = cloudUid.length > 0 && cloudUid === spaceUid;
  return {
    uid: uid,
    displayName: primaryDisplayName.length > 0
      ? primaryDisplayName
      : (sameIdentity ? secondaryDisplayName : ''),
    photoUrl: primaryPhotoUrl.length > 0
      ? primaryPhotoUrl
      : (sameIdentity ? secondaryPhotoUrl : ''),
    lastAuthAt: sameIdentity
      ? Math.max(huaweiCloud.lastAuthAt, huaweiSpace.lastAuthAt)
      : (useSpace ? huaweiSpace.lastAuthAt : huaweiCloud.lastAuthAt)
  };
}

export interface AiraSyncSettings {
  sourceId: string;
  bookmarkGenerationInitializedAt?: number;
  remoteKind: AiraSyncRemoteKind;
  bookmarkSyncEnabled: boolean;
  personalizationSyncEnabled: boolean;
  providerStates: AiraSyncProviderRuntimeState[];
  additionalBackupEnabled: boolean;
  additionalBackupRemoteKinds: AiraSyncProviderKind[];
  additionalBackupIntervalDays: AiraAdditionalBackupIntervalDays;
  webdav: AiraSyncWebdavConfig;
  huaweiCloud: AiraHuaweiCloudConfig;
  huaweiSpace: AiraHuaweiSpaceConfig;
  selfHosted?: AiraPersonalServerConfig;
  updatedAt: number;
  pendingBookmarkSyncAt: number;
  pendingBookmarkProviderSwitchFrom: AiraSyncRemoteKind;
}

export function isAiraBookmarkProviderTransition(
  sourceRemoteKind: AiraSyncRemoteKind,
  targetRemoteKind: AiraSyncProviderKind
): boolean {
  return sourceRemoteKind !== 'none' && sourceRemoteKind !== targetRemoteKind;
}

export function isAiraSyncProviderEnabled(
  settings: AiraSyncSettings,
  remoteKind: AiraSyncProviderKind
): boolean {
  if (settings.remoteKind === remoteKind) {
    return true;
  }
  return settings.additionalBackupEnabled && settings.additionalBackupRemoteKinds.indexOf(remoteKind) >= 0;
}

export function resolveAiraSyncProviderRuntimeState(
  settings: AiraSyncSettings,
  remoteKind: AiraSyncProviderKind
): AiraSyncProviderRuntimeState {
  const state = settings.providerStates.find((value: AiraSyncProviderRuntimeState) => {
    return value.remoteKind === remoteKind;
  });
  return state ?? {
    remoteKind: remoteKind,
    bookmark: createAiraSyncDomainRuntimeState(),
    personalization: createAiraSyncDomainRuntimeState(),
    bookmarkBackup: createAiraSyncDomainRuntimeState(),
    personalizationBackup: createAiraSyncDomainRuntimeState()
  };
}

export function createAiraSyncDomainRuntimeState(): AiraSyncDomainRuntimeState {
  return {
    providerIdentity: '',
    health: 'idle',
    lastAttemptAt: 0,
    lastSuccessAt: 0,
    revision: '',
    lastError: '',
    failureCode: '',
    failureStage: '',
    failureDetail: '',
    blocked: false
  };
}

export function resolveAiraSyncDomainRuntimeState(
  settings: AiraSyncSettings,
  remoteKind: AiraSyncProviderKind,
  domain: AiraSyncRuntimeDomainId
): AiraSyncDomainRuntimeState {
  const provider = resolveAiraSyncProviderRuntimeState(settings, remoteKind);
  if (domain === 'personalization') {
    return provider.personalization;
  }
  if (domain === 'bookmark_backup') {
    return provider.bookmarkBackup;
  }
  if (domain === 'personalization_backup') {
    return provider.personalizationBackup;
  }
  return provider.bookmark;
}

export function resolveAiraSyncActiveProviderLastSuccessAt(settings: AiraSyncSettings): number {
  if (settings.remoteKind === 'none') {
    return 0;
  }
  const state = resolveAiraSyncProviderRuntimeState(settings, settings.remoteKind);
  return Math.max(state.bookmark.lastSuccessAt, state.personalization.lastSuccessAt);
}

export interface AiraSyncRemoteStatusCache {
  providerKey: string;
  summary: string;
  bookmarkFolders: number;
  bookmarkItems: number;
  commitId: string;
  checkedAt: number;
}

export interface AiraSyncBaselineRecord {
  providerId: string;
  commitId: string;
  snapshot: AiraSyncSnapshot | null;
  history: AiraBookmarkHistoryDescriptor;
  updatedAt: number;
}

export interface AiraSyncStatusSummary {
  providerId: string;
  enabled: boolean;
  remoteKind: AiraSyncRemoteKind;
  rootPath: string;
  baselineCommitId: string;
  lastSuccessAt: number;
  localBookmarkFolders: number;
  localBookmarkItems: number;
  summary: string;
}

export interface AiraBookmarkSyncRemoteObservation {
  commitId: string;
  bookmarkFolders: number;
  bookmarkItems: number;
}

export interface AiraBookmarkMergeSyncResult {
  commitId: string;
  merged: boolean;
  blocked: boolean;
  conflictCount: number;
  localChangeCount: number;
  remoteChangeCount: number;
  conflictDetails: AiraBookmarkMergeConflictDetail[];
  remoteObservation: AiraBookmarkSyncRemoteObservation | null;
  summary: string;
}

export type AiraBookmarkConflictResolution = 'prefer-local' | 'prefer-remote';

export interface AiraBookmarkMergeConflictDetail {
  id: string;
  type: 'bookmark-folder' | 'bookmark-item' | 'bookmark-order';
  title: string;
  localValue: string;
  remoteValue: string;
}
