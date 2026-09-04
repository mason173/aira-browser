export type AiratabDistribution = 'community' | 'official';

export type AiratabOfficialApiRoute =
  | 'bookmarkSync'
  | 'historySync'
  | 'desktopPairingCreate'
  | 'desktopPairingStatus'
  | 'desktopMembershipState'
  | 'desktopSessionRevoke'
  | 'pagePushPoll'
  | 'pagePushAck'
  | 'deviceTabsPublish'
  | 'deviceTabsList'
  | 'deviceTabsClear';

type AiratabOfficialApiRoutes = Record<AiratabOfficialApiRoute, string>;

const configuredDistribution = String(import.meta.env.VITE_AIRATAB_DISTRIBUTION || '').trim().toLowerCase();

export const AIRATAB_DISTRIBUTION: AiratabDistribution = configuredDistribution === 'official'
  ? 'official'
  : 'community';

export const AIRATAB_CAPABILITIES = Object.freeze({
  airaCloud: AIRATAB_DISTRIBUTION === 'official',
  personalServer: true,
  webdav: true,
});

const EMPTY_OFFICIAL_API_ROUTES: AiratabOfficialApiRoutes = {
  bookmarkSync: '',
  historySync: '',
  desktopPairingCreate: '',
  desktopPairingStatus: '',
  desktopMembershipState: '',
  desktopSessionRevoke: '',
  pagePushPoll: '',
  pagePushAck: '',
  deviceTabsPublish: '',
  deviceTabsList: '',
  deviceTabsClear: '',
};

export const AIRATAB_OFFICIAL_API_ROUTES = Object.freeze(readOfficialApiRoutes());

export function requireAiratabOfficialApiRoute(route: AiratabOfficialApiRoute): string {
  const endpoint = AIRATAB_OFFICIAL_API_ROUTES[route];
  if (!AIRATAB_CAPABILITIES.airaCloud || !endpoint) {
    throw new Error('当前 Aira-sync 发行版不包含 Aira 官方云服务。');
  }
  return endpoint;
}

export function isAiratabSyncSourceAvailable(source: unknown): boolean {
  return source !== 'aira-cloud' || AIRATAB_CAPABILITIES.airaCloud;
}

function readOfficialApiRoutes(): AiratabOfficialApiRoutes {
  if (!AIRATAB_CAPABILITIES.airaCloud) return EMPTY_OFFICIAL_API_ROUTES;
  try {
    const parsed = JSON.parse(String(import.meta.env.VITE_AIRATAB_OFFICIAL_API_ROUTES || '')) as Record<string, unknown>;
    const routes = { ...EMPTY_OFFICIAL_API_ROUTES };
    for (const route of Object.keys(routes) as AiratabOfficialApiRoute[]) {
      routes[route] = normalizeEndpoint(parsed[route], import.meta.env.VITE_AIRATAB_LOCAL_TEST_MODE === '1');
    }
    return routes;
  } catch {
    return EMPTY_OFFICIAL_API_ROUTES;
  }
}

function normalizeEndpoint(value: unknown, allowHttp: boolean): string {
  try {
    const url = new URL(String(value || '').trim());
    const validProtocol = url.protocol === 'https:' || (allowHttp && url.protocol === 'http:');
    if (!validProtocol || url.username || url.password) return '';
    url.hash = '';
    return url.toString();
  } catch {
    return '';
  }
}
