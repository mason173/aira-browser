export type OfflinePageSaveStatus =
  'saving' |
  'saved' |
  'partial_saved' |
  'failed';

export type OfflinePageOpenStatus =
  'available' |
  'missing_snapshot' |
  'missing_assets' |
  'corrupted';

export type OfflinePageFailureReason =
  'unsupported_page' |
  'privacy_policy_blocked' |
  'content_too_large' |
  'storage_full' |
  'snapshot_failed' |
  'resource_partial_failed' |
  'file_write_failed' |
  'database_write_failed' |
  'controller_unavailable';

export type OfflinePageResourceStatus = 'saved' | 'failed' | 'skipped';

export type OfflinePageSaveBlockedReason =
  'none' |
  'home_page' |
  'empty_url' |
  'unsupported_scheme' |
  'internal_page' |
  'download_page' |
  'invalid_page' |
  'controller_unavailable';

export interface OfflinePageSaveEligibility {
  canSave: boolean;
  reason: OfflinePageSaveBlockedReason;
  targetUrl: string;
  title: string;
  message: string;
}

export interface OfflinePageSnapshotMetadata {
  pageUrl: string;
  title: string;
  siteName: string;
  host: string;
  description: string;
  htmlLength: number;
  visibleTextLength: number;
  imageElementCount: number;
  mediaElementCount: number;
  formElementCount: number;
  resourceUrls: string[];
  imageUrls: string[];
  inlinedImageUrls: string[];
  faviconUrls: string[];
}

export interface OfflinePageSnapshotResult {
  ok: boolean;
  reason: OfflinePageFailureReason | '';
  metadata: OfflinePageSnapshotMetadata;
  html: string;
}

export interface OfflinePageSelectedResource {
  originalUrl: string;
  kind: 'image' | 'favicon' | 'stylesheet';
  priority: number;
  localFileName: string;
}

export interface OfflinePageResourceSelectionResult {
  resources: OfflinePageSelectedResource[];
  skippedCount: number;
}

export interface OfflinePageStorageQuotaCheckInput {
  htmlBytes: number;
  resourceBudgetBytes: number;
  manifestBudgetBytes: number;
  previewBudgetBytes: number;
}

export interface OfflinePageStorageQuotaCheckResult {
  canWrite: boolean;
  availableBytes: number;
  requiredBytes: number;
  safetyMarginBytes: number;
}

export interface OfflinePageSaveRequest {
  controller: Object | undefined;
  eligibility: OfflinePageSaveEligibility;
}

export interface OfflinePageSaveResult {
  ok: boolean;
  status: OfflinePageSaveStatus;
  reason: OfflinePageFailureReason | '';
  message: string;
  record?: OfflinePageRecord;
}

export interface OfflinePageListItem {
  id: string;
  title: string;
  siteName: string;
  host: string;
  savedAtText: string;
  sizeText: string;
  previewImageUri: string;
  faviconUri: string;
  originalUrl: string;
  canOpen: boolean;
  openStatusText: string;
}

export interface OfflinePageListState {
  loading: boolean;
  empty: boolean;
  items: OfflinePageListItem[];
  message: string;
}

export interface OfflinePageDeleteResult {
  ok: boolean;
  message: string;
}

export interface OfflinePageOpenResult {
  ok: boolean;
  message: string;
  record?: OfflinePageRecord;
  html: string;
  archiveUri: string;
  contentKind: OfflinePageContentKind;
}

export interface OfflinePageViewerState {
  loading: boolean;
  canOpen: boolean;
  pageId: string;
  title: string;
  siteName: string;
  host: string;
  originalUrl: string;
  savedAt: number;
  updatedAt: number;
  totalBytes: number;
  resourceCount: number;
  failedResourceCount: number;
  saveStatus: OfflinePageSaveStatus;
  openStatus: OfflinePageOpenStatus;
  html: string;
  archiveUri: string;
  contentKind: OfflinePageContentKind;
  message: string;
}

export interface OfflinePageViewerInfoRow {
  label: string;
  value: string;
}

export type OfflinePageContentKind = 'html' | 'web_archive';

export interface OfflinePageRecord {
  id: string;
  originalUrl: string;
  normalizedUrl: string;
  urlHash: string;
  title: string;
  siteName: string;
  host: string;
  savedAt: number;
  updatedAt: number;
  snapshotPath: string;
  manifestPath: string;
  previewImageUri: string;
  faviconUri: string;
  totalBytes: number;
  resourceCount: number;
  failedResourceCount: number;
  saveStatus: OfflinePageSaveStatus;
  openStatus: OfflinePageOpenStatus;
}

export interface OfflinePageMediaManifestItem {
  originalUrl: string;
  localFileName: string;
  mimeType: string;
  bytes: number;
  status: OfflinePageResourceStatus;
}

export interface OfflinePageManifest {
  id: string;
  originalUrl: string;
  title: string;
  siteName: string;
  savedAt: number;
  snapshotFileName: string;
  contentKind: OfflinePageContentKind;
  previewFileName: string;
  faviconFileName: string;
  resources: OfflinePageMediaManifestItem[];
}

export interface OfflinePageWriteTextCommand {
  relativePath: string;
  content: string;
}

export interface OfflinePageWriteBytesCommand {
  relativePath: string;
  bytes: ArrayBuffer;
}

export interface OfflinePageDraftCommitResult {
  pageDir: string;
  manifestPath: string;
  snapshotPath: string;
  totalBytes: number;
}
