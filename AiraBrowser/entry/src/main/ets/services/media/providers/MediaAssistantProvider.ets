import { webview } from '@kit.ArkWeb';
import { MediaSignal } from '../../../features/mediaDiscovery/MediaSignalModels';

export type MediaAssistantProviderKind = 'javascript_probe' | 'arkweb_public_media_assistant';

export interface MediaAssistantAttachInput {
  tabId: string;
  pageUrl: string;
  pageTitle: string;
  controller: webview.WebviewController | undefined;
}

export interface MediaAssistantSnapshotInput {
  tabId: string;
  pageUrl: string;
  pageTitle: string;
  reason: string;
}

export interface MediaAssistantProvider {
  readonly kind: MediaAssistantProviderKind;
  isSupported(): boolean;
  attach(input: MediaAssistantAttachInput): void;
  detach(tabId: string): void;
  requestSnapshot(input: MediaAssistantSnapshotInput): Promise<MediaSignal[]>;
  clearTab(tabId: string): void;
  clearAll(): void;
}
