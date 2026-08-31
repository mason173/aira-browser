import {
  BrowserSearchInvocationSettingsAdapter
} from '../../core/search/BrowserSearchInvocationSessionCoordinator';
import { SettingsNavigationCoordinator } from './SettingsNavigationCoordinator';

class SettingsSearchExitDeferred {
  readonly authorityId: string;
  readonly promise: Promise<boolean>;
  private resolver: ((committed: boolean) => void) | undefined = undefined;
  private resolved: boolean = false;

  constructor(authorityId: string) {
    this.authorityId = authorityId;
    this.promise = new Promise<boolean>((resolve) => {
      this.resolver = resolve;
    });
  }

  resolve(committed: boolean): void {
    if (this.resolved || this.resolver === undefined) {
      return;
    }
    this.resolved = true;
    const resolver = this.resolver;
    this.resolver = undefined;
    resolver(committed);
  }
}

export class SettingsSearchInvocationAdapter implements BrowserSearchInvocationSettingsAdapter {
  private navigationCoordinator: SettingsNavigationCoordinator;
  private active: boolean = false;
  private pendingExit: SettingsSearchExitDeferred | undefined = undefined;

  constructor(navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator()) {
    this.navigationCoordinator = navigationCoordinator;
  }

  activate(): void {
    this.active = true;
  }

  dispose(): void {
    this.active = false;
    const pendingExit = this.pendingExit;
    this.pendingExit = undefined;
    pendingExit?.resolve(false);
  }

  requestExit(authorityId: string): Promise<boolean> {
    if (!this.active) {
      return Promise.resolve(true);
    }
    const normalizedAuthorityId = authorityId.trim();
    if (normalizedAuthorityId.length <= 0) {
      return Promise.resolve(false);
    }
    if (this.pendingExit?.authorityId === normalizedAuthorityId) {
      return this.pendingExit.promise;
    }
    const supersededExit = this.pendingExit;
    this.pendingExit = undefined;
    supersededExit?.resolve(false);

    const pendingExit = new SettingsSearchExitDeferred(normalizedAuthorityId);
    this.pendingExit = pendingExit;
    if (!this.navigationCoordinator.backToBrowserShell()) {
      this.pendingExit = undefined;
      pendingExit.resolve(false);
    }
    return pendingExit.promise;
  }

  notifyBrowserSurfaceReady(): void {
    if (!this.active && this.pendingExit === undefined) {
      return;
    }
    this.active = false;
    const pendingExit = this.pendingExit;
    this.pendingExit = undefined;
    pendingExit?.resolve(true);
  }
}
