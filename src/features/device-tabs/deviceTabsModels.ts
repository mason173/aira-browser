export type CrossDeviceTab = {
  title: string;
  url: string;
  active: boolean;
  lastActiveAt: number;
  windowOrder: number;
  tabOrder: number;
};

export type CrossDeviceTabDevice = {
  deviceId: string;
  deviceKind: 'desktop' | 'phone';
  deviceName: string;
  platform: string;
  model: string;
  browserName: string;
  browserVersion: string;
  tabs: CrossDeviceTab[];
  tabCount: number;
  updatedAt: number;
  expiresAt: number;
  freshnessMs: number;
};

export type CrossDeviceTabList = {
  serverTime: number;
  onlineWindowMs: number;
  devices: CrossDeviceTabDevice[];
};

export type DesktopDeviceMetadata = {
  deviceId: string;
  deviceName: string;
  platform: string;
  model: string;
  browserName: string;
  browserVersion: string;
};
