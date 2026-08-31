import { MediaSignal } from '../../../features/mediaDiscovery/MediaSignalModels';
import {
  MediaAssistantAttachInput,
  MediaAssistantProvider,
  MediaAssistantProviderKind,
  MediaAssistantSnapshotInput
} from './MediaAssistantProvider';

export class ArkWebPublicMediaAssistantProvider implements MediaAssistantProvider {
  readonly kind: MediaAssistantProviderKind = 'arkweb_public_media_assistant';

  isSupported(): boolean {
    // HarmonyOS exposes native media-player takeover APIs, but they require Web attribute
    // wiring plus a NativeMediaPlayerBridge and are not a passive resource-discovery snapshot.
    return false;
  }

  attach(_input: MediaAssistantAttachInput): void {
  }

  detach(_tabId: string): void {
  }

  requestSnapshot(_input: MediaAssistantSnapshotInput): Promise<MediaSignal[]> {
    const signals: MediaSignal[] = [];
    return Promise.resolve(signals);
  }

  clearTab(tabId: string): void {
    this.detach(tabId);
  }

  clearAll(): void {
  }
}
