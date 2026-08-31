import { BrowserShellFamilyAvailability } from './BrowserWindowPresentationProfile';

export type BrowserShellAdapterKind = 'phone' | 'large_screen' | 'web_app';

export interface BrowserShellAdapterDescriptor {
  kind: BrowserShellAdapterKind;
  ready: boolean;
  generation: number;
}

export interface BrowserShellAdapterCatalogSnapshot {
  revision: number;
  phone: BrowserShellAdapterDescriptor;
  largeScreen: BrowserShellAdapterDescriptor;
  webApp: BrowserShellAdapterDescriptor;
}

/**
 * Stable-host capability catalog. A family is "available" only when its
 * complete ArkUI adapter is mounted and ready to own presentation state.
 */
export class BrowserShellAdapterCatalog {
  private readonly revision: number = 2;

  resolveAvailability(): BrowserShellFamilyAvailability {
    const catalog = this.snapshot();
    return {
      phoneShellAvailable: catalog.phone.ready,
      largeScreenShellAvailable: catalog.largeScreen.ready
    };
  }

  snapshot(): BrowserShellAdapterCatalogSnapshot {
    return {
      revision: this.revision,
      phone: {
        kind: 'phone',
        ready: true,
        generation: 1
      },
      largeScreen: {
        kind: 'large_screen',
        ready: true,
        generation: 2
      },
      webApp: {
        kind: 'web_app',
        ready: true,
        generation: 2
      }
    };
  }
}
