export interface CrossDeviceTabPresenceTab {
  title: string;
  url: string;
  active: boolean;
  lastActiveAt: number;
  windowOrder: number;
  tabOrder: number;
}

export interface CrossDeviceTabPresenceDevice {
  deviceId: string;
  deviceKind: 'desktop' | 'phone';
  deviceName: string;
  platform: string;
  model: string;
  browserName: string;
  browserVersion: string;
  tabs: CrossDeviceTabPresenceTab[];
  tabCount: number;
  updatedAt: number;
  expiresAt: number;
  freshnessMs: number;
}

export interface CrossDeviceTabPresenceLocalDevice {
  deviceId: string;
  deviceName: string;
  platform: string;
  model: string;
  browserName: string;
  browserVersion: string;
}

export type CrossDeviceTabPresencePanelStatus =
  'disabled' |
  'signed_out' |
  'loading' |
  'ready' |
  'error';

export interface CrossDeviceTabPresencePanelState {
  status: CrossDeviceTabPresencePanelStatus;
  enabled: boolean;
  deviceName: string;
  devices: CrossDeviceTabPresenceDevice[];
  message: string;
  serverTime: number;
  onlineWindowMs: number;
}

export interface CrossDeviceTabPresencePanelAccessDecision {
  allowed: boolean;
  title: string;
  message: string;
  openPro: boolean;
}

export interface CrossDeviceTabPresenceListResult {
  serverTime: number;
  onlineWindowMs: number;
  devices: CrossDeviceTabPresenceDevice[];
}
