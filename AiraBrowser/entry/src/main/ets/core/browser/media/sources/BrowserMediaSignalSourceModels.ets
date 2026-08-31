import { MediaSignal } from '../../../../features/mediaDiscovery/MediaSignalModels';

export type BrowserMediaSignalSourceKind =
  | 'arkweb_request'
  | 'dom_probe'
  | 'deep_probe'
  | 'userscript'
  | 'site_extractor'
  | 'arkweb_media_assistant';

export interface BrowserMediaSignalSourceSnapshotInput {
  tabId: string;
  pageUrl: string;
  pageTitle: string;
  reason: string;
}

export interface BrowserMediaSignalSource {
  readonly kind: BrowserMediaSignalSourceKind;
  isSupported(): boolean;
  requestSnapshot(input: BrowserMediaSignalSourceSnapshotInput): Promise<MediaSignal[]>;
  clearTab(tabId: string): void;
  clearAll(): void;
}
