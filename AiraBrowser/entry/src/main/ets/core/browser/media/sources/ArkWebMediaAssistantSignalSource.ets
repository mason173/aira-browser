import { webview } from '@kit.ArkWeb';
import { MediaSignal } from '../../../../features/mediaDiscovery/MediaSignalModels';
import { ArkWebPublicMediaAssistantProvider } from '../../../../services/media/providers/ArkWebPublicMediaAssistantProvider';
import {
  BrowserMediaSignalSource,
  BrowserMediaSignalSourceKind,
  BrowserMediaSignalSourceSnapshotInput
} from './BrowserMediaSignalSourceModels';

export interface ArkWebMediaAssistantAttachInput {
  tabId: string;
  pageUrl: string;
  pageTitle: string;
  controller: webview.WebviewController;
}

export class ArkWebMediaAssistantSignalSource implements BrowserMediaSignalSource {
  readonly kind: BrowserMediaSignalSourceKind = 'arkweb_media_assistant';
  private provider: ArkWebPublicMediaAssistantProvider = new ArkWebPublicMediaAssistantProvider();

  isSupported(): boolean {
    return this.provider.isSupported();
  }

  attach(input: ArkWebMediaAssistantAttachInput): void {
    this.provider.attach({
      tabId: input.tabId,
      pageUrl: input.pageUrl,
      pageTitle: input.pageTitle,
      controller: input.controller
    });
  }

  detach(tabId: string): void {
    this.provider.detach(tabId);
  }

  requestSnapshot(input: BrowserMediaSignalSourceSnapshotInput): Promise<MediaSignal[]> {
    return this.provider.requestSnapshot({
      tabId: input.tabId,
      pageUrl: input.pageUrl,
      pageTitle: input.pageTitle,
      reason: input.reason
    });
  }

  clearTab(tabId: string): void {
    this.detach(tabId);
  }

  clearAll(): void {
    this.provider.clearAll();
  }
}
