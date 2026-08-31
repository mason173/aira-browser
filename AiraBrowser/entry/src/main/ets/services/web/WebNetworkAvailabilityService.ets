import { connection } from '@kit.NetworkKit';

export interface WebNetworkAvailabilitySnapshot {
  available: boolean;
  reliable: boolean;
  message: string;
}

const NETWORK_STATE_UNKNOWN: WebNetworkAvailabilitySnapshot = {
  available: true,
  reliable: false,
  message: ''
};

export class WebNetworkAvailabilityService {
  private netConnection: connection.NetConnection | undefined;
  private available: boolean = true;
  private reliable: boolean = false;
  private listening: boolean = false;
  private onChange?: (snapshot: WebNetworkAvailabilitySnapshot) => void;

  getSnapshot(): WebNetworkAvailabilitySnapshot {
    if (!this.reliable) {
      return NETWORK_STATE_UNKNOWN;
    }
    return {
      available: this.available,
      reliable: true,
      message: this.available ? '' : this.buildOfflineMessage()
    };
  }

  refresh(): WebNetworkAvailabilitySnapshot {
    try {
      this.available = connection.hasDefaultNetSync();
      this.reliable = true;
    } catch (_error) {
      this.reliable = false;
      this.available = true;
    }
    return this.getSnapshot();
  }

  start(onChange: (snapshot: WebNetworkAvailabilitySnapshot) => void): void {
    this.onChange = onChange;
    this.refresh();
    if (this.listening) {
      return;
    }
    try {
      const watcher = connection.createNetConnection();
      watcher.on('netAvailable', () => {
        this.updateAvailability(true);
      });
      watcher.on('netLost', () => {
        this.updateAvailabilityFromSystem();
      });
      watcher.on('netUnavailable', () => {
        this.updateAvailability(false);
      });
      watcher.register(() => {
      });
      this.netConnection = watcher;
      this.listening = true;
    } catch (_error) {
      this.netConnection = undefined;
      this.listening = false;
    }
  }

  stop(): void {
    this.onChange = undefined;
    if (this.netConnection === undefined || !this.listening) {
      return;
    }
    try {
      this.netConnection.unregister(() => {
      });
    } catch (_error) {
    }
    this.netConnection = undefined;
    this.listening = false;
  }

  shouldFastFailNavigation(targetUrl: string): boolean {
    if (!this.isNetworkNavigationUrl(targetUrl)) {
      return false;
    }
    const snapshot = this.refresh();
    return snapshot.reliable && !snapshot.available;
  }

  buildOfflineMessage(): string {
    return '加载失败：设备当前没有可用网络连接。';
  }

  isNetworkNavigationUrl(targetUrl: string): boolean {
    const normalized = targetUrl.trim().toLowerCase();
    return normalized.startsWith('http://') || normalized.startsWith('https://');
  }

  private updateAvailabilityFromSystem(): void {
    const previousAvailable = this.available;
    const snapshot = this.refresh();
    if (!snapshot.reliable || snapshot.available === previousAvailable) {
      return;
    }
    this.onChange?.(snapshot);
  }

  private updateAvailability(available: boolean): void {
    if (this.reliable && this.available === available) {
      return;
    }
    this.available = available;
    this.reliable = true;
    this.onChange?.(this.getSnapshot());
  }
}
