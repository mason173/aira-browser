export interface WebdavProviderTemplate {
  id: string;
  name: string;
  endpoint: string;
  icon?: Resource;
  logo?: Resource;
}

export const WEB_DAV_PROVIDER_SELECTION_KEY: string = 'aira.sync.webdav.selectedProviderId';
export const WEB_DAV_PROVIDER_ENDPOINT_KEY: string = 'aira.sync.webdav.selectedEndpoint';
export const WEB_DAV_PROVIDER_SELECTION_REVISION_KEY: string = 'aira.sync.webdav.selectedRevision';

export class WebdavProviderCatalog {
  listProviders(): WebdavProviderTemplate[] {
    return [
      this.buildProvider('custom', '自定义服务', '', $r('sys.symbol.icloud_fill')),
      this.buildProvider('jianguoyun', '坚果云', 'https://dav.jianguoyun.com/dav/',
        undefined, $r('app.media.webdav_provider_jianguoyun')),
      this.buildProvider('pcloud-us', 'pCloud (US)', 'https://webdav.pcloud.com/',
        undefined, $r('app.media.webdav_provider_pcloud_us')),
      this.buildProvider('pcloud-eu', 'pCloud (EU)', 'https://ewebdav.pcloud.com/',
        undefined, $r('app.media.webdav_provider_pcloud_eu')),
      this.buildProvider('gmx-mediacenter', 'GMX MediaCenter', 'https://webdav.mc.gmx.net/',
        undefined, $r('app.media.webdav_provider_gmx_mediacenter')),
      this.buildProvider('kdrive', 'kDrive', 'https://IDkDrive.connect.kdrive.infomaniak.com/',
        undefined, $r('app.media.webdav_provider_kdrive')),
      this.buildProvider('koofr', 'Koofr', 'https://app.koofr.net/dav/Koofr/',
        undefined, $r('app.media.webdav_provider_koofr'))
    ];
  }

  resolveProvider(providerId: string): WebdavProviderTemplate {
    const providers = this.listProviders();
    return providers.find((provider: WebdavProviderTemplate) => provider.id === providerId) ?? providers[0];
  }

  resolveProviderForEndpoint(endpoint: string): WebdavProviderTemplate {
    const normalizedEndpoint = this.normalizeEndpoint(endpoint);
    const matched = this.listProviders().find((provider: WebdavProviderTemplate) => {
      return provider.id !== 'custom' &&
        provider.endpoint.length > 0 &&
        this.normalizeEndpoint(provider.endpoint) === normalizedEndpoint;
    });
    return matched ?? this.resolveProvider('custom');
  }

  resolveProviderEndpoint(providerId: string, fallbackEndpoint: string): string {
    const provider = this.resolveProvider(providerId);
    if (provider.id !== 'custom' && provider.endpoint.length > 0) {
      return provider.endpoint;
    }
    return fallbackEndpoint;
  }

  private buildProvider(
    id: string,
    name: string,
    endpoint: string,
    icon?: Resource,
    logo?: Resource
  ): WebdavProviderTemplate {
    return {
      id: id,
      name: name,
      endpoint: endpoint,
      icon: icon,
      logo: logo
    };
  }

  private normalizeEndpoint(endpoint: string): string {
    return endpoint.trim().replace(/\/+$/, '');
  }
}
