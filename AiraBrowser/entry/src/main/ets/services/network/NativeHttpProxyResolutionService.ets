import { connection } from '@kit.NetworkKit';
import { BrowserAppProxySettings, BrowserExperimentSettings } from '../../common/models/BrowserModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';

export interface NativeHttpProxyResolution {
  enabled: boolean;
  scheme: string;
  host: string;
  port: number;
  hasCredentials: boolean;
  signature: string;
  usingProxy?: connection.HttpProxy;
}

export class NativeHttpProxyResolutionService {
  private preferencesRepository: PreferencesRepository | undefined;

  constructor(preferencesRepository?: PreferencesRepository) {
    this.preferencesRepository = preferencesRepository;
  }

  resolveFromCurrentPreferences(): NativeHttpProxyResolution {
    const repository = this.preferencesRepository;
    if (repository === undefined) {
      return this.buildDisabledResolution();
    }
    return this.resolveFromExperimentSettings(repository.getPreferences().experiments);
  }

  resolveFromExperimentSettings(settings: BrowserExperimentSettings | undefined): NativeHttpProxyResolution {
    if (settings === undefined || !settings.appProxyEnabled) {
      return this.buildDisabledResolution(settings?.appProxy);
    }
    const proxy = settings.appProxy;
    const host = proxy.host.trim();
    const port = Math.floor(proxy.port);
    if (host.length <= 0 || port <= 0) {
      return this.buildDisabledResolution(proxy);
    }
    const username = proxy.username.trim();
    const usingProxy: connection.HttpProxy = {
      host: host,
      port: port,
      exclusionList: this.parseExclusionList(proxy.bypassHosts)
    };
    if (username.length > 0) {
      usingProxy.username = username;
      usingProxy.password = proxy.password;
    }
    return {
      enabled: true,
      scheme: proxy.scheme,
      host: host,
      port: port,
      hasCredentials: username.length > 0,
      signature: this.buildSignature(true, proxy.scheme, host, port, username.length > 0, proxy.bypassHosts),
      usingProxy: usingProxy
    };
  }

  private buildDisabledResolution(proxy?: BrowserAppProxySettings): NativeHttpProxyResolution {
    const scheme = proxy?.scheme ?? '';
    const host = proxy?.host.trim() ?? '';
    const port = proxy?.port ?? 0;
    const hasCredentials = (proxy?.username.trim().length ?? 0) > 0;
    return {
      enabled: false,
      scheme: scheme,
      host: host,
      port: port,
      hasCredentials: hasCredentials,
      signature: this.buildSignature(false, scheme, host, port, hasCredentials, proxy?.bypassHosts ?? '')
    };
  }

  private buildSignature(
    enabled: boolean,
    scheme: string,
    host: string,
    port: number,
    hasCredentials: boolean,
    bypassHosts: string
  ): string {
    return [
      enabled ? '1' : '0',
      scheme.trim(),
      host.trim().toLowerCase(),
      String(Math.floor(port)),
      hasCredentials ? '1' : '0',
      bypassHosts.trim().toLowerCase()
    ].join('|');
  }

  private parseExclusionList(value: string): string[] {
    const result: string[] = [];
    const parts = value.split(',');
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i].trim();
      if (part.length > 0) {
        result.push(part);
      }
    }
    return result;
  }
}
