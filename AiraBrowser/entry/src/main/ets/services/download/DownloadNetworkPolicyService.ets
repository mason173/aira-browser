import { connection } from '@kit.NetworkKit';

export type DownloadNetworkKind =
  'unknown' |
  'offline' |
  'wifi' |
  'ethernet' |
  'cellular' |
  'other';

export type DownloadNetworkAdmissionReason =
  'start_now' |
  'waiting_wifi' |
  'offline_network' |
  'network_unknown';

export interface DownloadNetworkSnapshot {
  kind: DownloadNetworkKind;
  available: boolean;
  reliable: boolean;
  bearerTypes: number[];
  checkedAt: number;
}

export interface DownloadNetworkStartAdmission {
  canStartNow: boolean;
  reason: DownloadNetworkAdmissionReason;
  message: string;
  snapshot: DownloadNetworkSnapshot;
}

export interface DownloadNetworkPolicyConfig {
  waitForWifiOnCellular?: boolean;
  allowUnknownNetwork?: boolean;
  allowOtherNetwork?: boolean;
}

export interface DownloadNetworkSnapshotProvider {
  readSnapshot(): DownloadNetworkSnapshot;
  startMonitoring?(onChange: (snapshot: DownloadNetworkSnapshot) => void): void;
  stopMonitoring?(): void;
}

const DEFAULT_NETWORK_POLICY: Required<DownloadNetworkPolicyConfig> = {
  waitForWifiOnCellular: false,
  allowUnknownNetwork: true,
  allowOtherNetwork: true
};

const UNKNOWN_NETWORK_SNAPSHOT: DownloadNetworkSnapshot = {
  kind: 'unknown',
  available: true,
  reliable: false,
  bearerTypes: [],
  checkedAt: 0
};

class SystemDownloadNetworkSnapshotProvider implements DownloadNetworkSnapshotProvider {
  private netConnection: connection.NetConnection | undefined;
  private listening: boolean = false;
  private onChange?: (snapshot: DownloadNetworkSnapshot) => void;

  readSnapshot(): DownloadNetworkSnapshot {
    const checkedAt = Date.now();
    try {
      if (!connection.hasDefaultNetSync()) {
        return {
          kind: 'offline',
          available: false,
          reliable: true,
          bearerTypes: [],
          checkedAt: checkedAt
        };
      }
      const defaultNet = connection.getDefaultNetSync();
      if (defaultNet.netId === 0) {
        return {
          kind: 'offline',
          available: false,
          reliable: true,
          bearerTypes: [],
          checkedAt: checkedAt
        };
      }
      const capabilities = connection.getNetCapabilitiesSync(defaultNet);
      const bearerTypes = this.normalizeBearerTypes(capabilities.bearerTypes);
      return {
        kind: this.resolveNetworkKind(bearerTypes),
        available: true,
        reliable: true,
        bearerTypes: bearerTypes,
        checkedAt: checkedAt
      };
    } catch (_error) {
      return {
        kind: UNKNOWN_NETWORK_SNAPSHOT.kind,
        available: UNKNOWN_NETWORK_SNAPSHOT.available,
        reliable: UNKNOWN_NETWORK_SNAPSHOT.reliable,
        bearerTypes: UNKNOWN_NETWORK_SNAPSHOT.bearerTypes.slice(),
        checkedAt: checkedAt
      };
    }
  }

  startMonitoring(onChange: (snapshot: DownloadNetworkSnapshot) => void): void {
    this.onChange = onChange;
    if (this.listening) {
      return;
    }
    try {
      const watcher = connection.createNetConnection();
      watcher.on('netAvailable', () => {
        this.notifyChange();
      });
      watcher.on('netLost', () => {
        this.notifyChange();
      });
      watcher.on('netUnavailable', () => {
        this.notifyChange();
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

  stopMonitoring(): void {
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

  private notifyChange(): void {
    this.onChange?.(this.readSnapshot());
  }

  private normalizeBearerTypes(bearerTypes: Array<connection.NetBearType>): number[] {
    const values: number[] = [];
    for (let index = 0; index < bearerTypes.length; index += 1) {
      values.push(bearerTypes[index] as number);
    }
    return values;
  }

  private resolveNetworkKind(bearerTypes: number[]): DownloadNetworkKind {
    if (bearerTypes.indexOf(connection.NetBearType.BEARER_WIFI as number) >= 0) {
      return 'wifi';
    }
    if (bearerTypes.indexOf(connection.NetBearType.BEARER_ETHERNET as number) >= 0) {
      return 'ethernet';
    }
    if (bearerTypes.indexOf(connection.NetBearType.BEARER_CELLULAR as number) >= 0) {
      return 'cellular';
    }
    return bearerTypes.length > 0 ? 'other' : 'unknown';
  }
}

export class DownloadNetworkPolicyService {
  private config: Required<DownloadNetworkPolicyConfig>;
  private provider: DownloadNetworkSnapshotProvider;

  constructor(
    config?: DownloadNetworkPolicyConfig,
    provider?: DownloadNetworkSnapshotProvider
  ) {
    this.config = {
      waitForWifiOnCellular: config?.waitForWifiOnCellular ?? DEFAULT_NETWORK_POLICY.waitForWifiOnCellular,
      allowUnknownNetwork: config?.allowUnknownNetwork ?? DEFAULT_NETWORK_POLICY.allowUnknownNetwork,
      allowOtherNetwork: config?.allowOtherNetwork ?? DEFAULT_NETWORK_POLICY.allowOtherNetwork
    };
    this.provider = provider ?? new SystemDownloadNetworkSnapshotProvider();
  }

  resolveStartAdmission(): DownloadNetworkStartAdmission {
    const snapshot = this.provider.readSnapshot();
    if (!snapshot.available || snapshot.kind === 'offline') {
      return {
        canStartNow: false,
        reason: 'offline_network',
        message: '网络不可用，下载已等待网络恢复。',
        snapshot: snapshot
      };
    }
    if (snapshot.kind === 'cellular' && this.config.waitForWifiOnCellular) {
      return {
        canStartNow: false,
        reason: 'waiting_wifi',
        message: '当前为蜂窝网络，下载已等待 WLAN。',
        snapshot: snapshot
      };
    }
    if (snapshot.kind === 'unknown' && !this.config.allowUnknownNetwork) {
      return {
        canStartNow: false,
        reason: 'network_unknown',
        message: '无法确认当前网络类型，下载已暂缓。',
        snapshot: snapshot
      };
    }
    if (snapshot.kind === 'other' && !this.config.allowOtherNetwork) {
      return {
        canStartNow: false,
        reason: 'network_unknown',
        message: '当前网络类型暂不支持自动下载，下载已暂缓。',
        snapshot: snapshot
      };
    }
    return {
      canStartNow: true,
      reason: 'start_now',
      message: '',
      snapshot: snapshot
    };
  }

  setCellularDownloadsAllowed(allowed: boolean): void {
    this.config.waitForWifiOnCellular = !allowed;
  }

  startMonitoring(onChange: (snapshot: DownloadNetworkSnapshot) => void): void {
    this.provider.startMonitoring?.(onChange);
  }

  stopMonitoring(): void {
    this.provider.stopMonitoring?.();
  }
}
