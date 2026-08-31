import { webview } from '@kit.ArkWeb';

export interface WebBackForwardCacheConfiguration {
  size: number;
  timeToLiveSeconds: number;
  nativeEmbedEnabled: boolean;
  mediaTakeOverEnabled: boolean;
}

export interface WebBackForwardCacheApplyResult {
  enabled: boolean;
  configured: boolean;
  message: string;
}

interface WebBackForwardCacheConfiguredRuntime {
  controller: webview.WebviewController;
  generation: number;
  configSignature: string;
}

const DEFAULT_BACK_FORWARD_CACHE_SIZE: number = 8;
const DEFAULT_BACK_FORWARD_CACHE_TTL_SECONDS: number = 600;
const DEFAULT_BACK_FORWARD_CACHE_NATIVE_EMBED_ENABLED: boolean = false;
const DEFAULT_BACK_FORWARD_CACHE_MEDIA_TAKE_OVER_ENABLED: boolean = false;

const BING_BROADCAST_CHANNEL_BFCACHE_COMPATIBILITY_SCRIPT: string = `
;(function airaBingBroadcastChannelBfCacheCompatibility() {
  var debugPrefix = '[DEBUG-bfcache-broadcast-0827]';
  try {
    var host = String(window.location && window.location.hostname || '').toLowerCase();
    var path = String(window.location && window.location.pathname || '');
    if ((host !== 'cn.bing.com' && host !== 'www.bing.com') || path !== '/search') {
      return;
    }
    var NativeBroadcastChannel = window.BroadcastChannel;
    if (typeof NativeBroadcastChannel !== 'function') {
      return;
    }
    var activeChannels = [];
    var AiraBroadcastChannel = function (name) {
      var channel = new NativeBroadcastChannel(name);
      activeChannels.push(channel);
      return channel;
    };
    try {
      Object.setPrototypeOf(AiraBroadcastChannel, NativeBroadcastChannel);
    } catch (_error) {
    }
    AiraBroadcastChannel.prototype = NativeBroadcastChannel.prototype;
    try {
      Object.defineProperty(window, 'BroadcastChannel', {
        configurable: true,
        enumerable: false,
        writable: true,
        value: AiraBroadcastChannel
      });
    } catch (_error) {
      window.BroadcastChannel = AiraBroadcastChannel;
    }
    window.addEventListener('pagehide', function () {
      var channels = activeChannels.splice(0, activeChannels.length);
      for (var index = 0; index < channels.length; index += 1) {
        try {
          channels[index].close();
        } catch (_error) {
        }
      }
      console.info(debugPrefix + ' pagehide_closed count=' + channels.length);
    }, true);
    console.info(debugPrefix + ' installed');
  } catch (error) {
    console.info(debugPrefix + ' install_failed');
  }
})();
`;

export class WebBackForwardCacheCoordinator {
  private static globalEnabled: boolean = false;
  private configuredRuntimeByTabId: Record<string, WebBackForwardCacheConfiguredRuntime | undefined> = {};
  private runtimeGenerationByTabId: Record<string, number | undefined> = {};

  createDefaultConfiguration(): WebBackForwardCacheConfiguration {
    return {
      size: DEFAULT_BACK_FORWARD_CACHE_SIZE,
      timeToLiveSeconds: DEFAULT_BACK_FORWARD_CACHE_TTL_SECONDS,
      nativeEmbedEnabled: DEFAULT_BACK_FORWARD_CACHE_NATIVE_EMBED_ENABLED,
      mediaTakeOverEnabled: DEFAULT_BACK_FORWARD_CACHE_MEDIA_TAKE_OVER_ENABLED
    };
  }

  buildCompatibilityDocumentStartScriptItem(): ScriptItem {
    return {
      script: BING_BROADCAST_CHANNEL_BFCACHE_COMPATIBILITY_SCRIPT,
      scriptRules: ['*']
    };
  }

  enableGlobalFeature(
    config: WebBackForwardCacheConfiguration = this.createDefaultConfiguration()
  ): WebBackForwardCacheApplyResult {
    if (WebBackForwardCacheCoordinator.globalEnabled) {
      return {
        enabled: true,
        configured: false,
        message: 'ArkWeb BFCache global feature already enabled'
      };
    }
    try {
      const features = new webview.BackForwardCacheSupportedFeatures();
      features.nativeEmbed = config.nativeEmbedEnabled;
      features.mediaTakeOver = config.mediaTakeOverEnabled;
      webview.WebviewController.enableBackForwardCache(features);
      WebBackForwardCacheCoordinator.globalEnabled = true;
      return {
        enabled: true,
        configured: true,
        message: this.buildEnabledMessage(config)
      };
    } catch (error) {
      return {
        enabled: false,
        configured: false,
        message: `ArkWeb BFCache enable failed: ${JSON.stringify(error)}`
      };
    }
  }

  applyControllerOptions(
    controller: webview.WebviewController | undefined,
    config: WebBackForwardCacheConfiguration = this.createDefaultConfiguration()
  ): WebBackForwardCacheApplyResult {
    if (controller === undefined) {
      return {
        enabled: WebBackForwardCacheCoordinator.globalEnabled,
        configured: false,
        message: 'ArkWeb BFCache controller unavailable'
      };
    }
    if (!WebBackForwardCacheCoordinator.globalEnabled) {
      return {
        enabled: false,
        configured: false,
        message: 'ArkWeb BFCache global feature was not enabled before Web engine initialization'
      };
    }
    try {
      const options = new webview.BackForwardCacheOptions();
      options.size = Math.max(1, Math.min(50, Math.round(config.size)));
      options.timeToLive = Math.max(1, Math.round(config.timeToLiveSeconds));
      controller.setBackForwardCacheOptions(options);
      return {
        enabled: true,
        configured: true,
        message: `ArkWeb BFCache controller configured size=${options.size} ttl=${options.timeToLive}s`
      };
    } catch (error) {
      return {
        enabled: true,
        configured: false,
        message: `ArkWeb BFCache controller configuration failed: ${JSON.stringify(error)}`
      };
    }
  }

  applyControllerOptionsForTab(
    tabId: string,
    controller: webview.WebviewController | undefined,
    source: string,
    force: boolean = false,
    config: WebBackForwardCacheConfiguration = this.createDefaultConfiguration()
  ): WebBackForwardCacheApplyResult {
    const normalizedTabId = tabId.trim();
    const normalizedSource = source.trim().length > 0 ? source.trim() : 'unknown';
    const configSignature = this.buildConfigSignature(config);
    const configuredRuntime = this.configuredRuntimeByTabId[normalizedTabId];
    const sameController = controller !== undefined && configuredRuntime?.controller === controller;
    const runtimeGeneration = sameController
      ? configuredRuntime?.generation ?? 1
      : (this.runtimeGenerationByTabId[normalizedTabId] ?? 0) + 1;
    if (controller !== undefined && !force && normalizedTabId.length > 0 &&
      sameController && configuredRuntime?.configSignature === configSignature) {
      return {
        enabled: WebBackForwardCacheCoordinator.globalEnabled,
        configured: false,
        message: `tab=${normalizedTabId} generation=${runtimeGeneration} source=${normalizedSource} ` +
          'ArkWeb BFCache controller configuration unchanged'
      };
    }
    const result = this.applyControllerOptions(controller, config);
    if (result.configured && normalizedTabId.length > 0 && controller !== undefined) {
      this.configuredRuntimeByTabId[normalizedTabId] = {
        controller: controller,
        generation: runtimeGeneration,
        configSignature: configSignature
      };
      this.runtimeGenerationByTabId[normalizedTabId] = runtimeGeneration;
    }
    return {
      enabled: result.enabled,
      configured: result.configured,
      message: `tab=${normalizedTabId.length > 0 ? normalizedTabId : 'unknown'} ` +
        `generation=${runtimeGeneration} source=${normalizedSource} ${result.message}`
    };
  }

  removeTabId(tabId: string, controller?: webview.WebviewController): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return;
    }
    const configuredRuntime = this.configuredRuntimeByTabId[normalizedTabId];
    if (controller !== undefined && configuredRuntime?.controller !== controller) {
      return;
    }
    this.configuredRuntimeByTabId[normalizedTabId] = undefined;
  }

  hasConfiguredTab(tabId: string): boolean {
    return this.configuredRuntimeByTabId[tabId.trim()] !== undefined;
  }

  private buildEnabledMessage(config: WebBackForwardCacheConfiguration): string {
    return `ArkWeb BFCache enabled size=${Math.max(1, Math.min(50, Math.round(config.size)))} ` +
      `ttl=${Math.max(1, Math.round(config.timeToLiveSeconds))}s ` +
      `nativeEmbed=${config.nativeEmbedEnabled} mediaTakeOver=${config.mediaTakeOverEnabled}`;
  }

  private buildConfigSignature(config: WebBackForwardCacheConfiguration): string {
    return `${Math.max(1, Math.min(50, Math.round(config.size)))}:` +
      `${Math.max(1, Math.round(config.timeToLiveSeconds))}:` +
      `${config.nativeEmbedEnabled ? 1 : 0}:` +
      `${config.mediaTakeOverEnabled ? 1 : 0}`;
  }
}
