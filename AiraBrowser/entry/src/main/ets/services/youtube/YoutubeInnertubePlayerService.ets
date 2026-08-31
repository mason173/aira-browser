import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  YoutubeFormat,
  YoutubePageProbeResult,
  YoutubePlaybackPlan
} from '../../features/youtubeTakeover/YoutubeModels';
import { YoutubeStreamingDataParser } from '../../features/youtubeTakeover/YoutubeStreamingDataParser';
import { YoutubeFormatSelector, YoutubeFormatSelection } from '../../features/youtubeTakeover/YoutubeFormatSelector';
import { sharedPreferencesRepository } from '../../app/bootstrap/BrowserAppRuntime';
import { NativeVideoHttpProxyResolution, NativeVideoHttpProxyService } from '../video/NativeVideoHttpProxyService';

const YOUTUBE_INNERTUBE_LOG_DOMAIN: number = 0xA1A0;
const YOUTUBE_INNERTUBE_LOG_TAG: string = 'YoutubeInnertube';
const YOUTUBE_INNERTUBE_TIMEOUT_MS: number = 12000;
const YOUTUBE_WEB_SAFARI_CLIENT_VERSION: string = '2.20260114.08.00';
const YOUTUBE_WEB_SAFARI_UA: string =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)';
const YOUTUBE_IOS_CLIENT_VERSION: string = '21.03.2';
const YOUTUBE_IOS_UA: string =
  'com.google.ios.youtube/21.03.2 (iPhone16,2; U; CPU iOS 18_7_2 like Mac OS X;)';
const YOUTUBE_ANDROID_CLIENT_VERSION: string = '21.03.36';
const YOUTUBE_ANDROID_UA: string =
  'com.google.android.youtube/21.03.36 (Linux; U; Android 16) gzip';
const YOUTUBE_ANDROID_VR_CLIENT_VERSION: string = '1.65.10';
const YOUTUBE_ANDROID_VR_UA: string =
  'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip';

interface YoutubeInnertubeClientInput {
  clientName: string;
  clientVersion: string;
  userAgent?: string;
  visitorData?: string;
  deviceMake?: string;
  deviceModel?: string;
  osName?: string;
  osVersion?: string;
  androidSdkVersion?: number;
}

interface YoutubeInnertubeClientContext {
  clientName: string;
  clientVersion: string;
  userAgent?: string;
  visitorData?: string;
  deviceMake?: string;
  deviceModel?: string;
  osName?: string;
  osVersion?: string;
  androidSdkVersion?: number;
}

interface YoutubeInnertubeRequestContext {
  client: YoutubeInnertubeClientContext;
}

interface YoutubeInnertubeContentPlaybackContext {
  html5Preference: string;
}

interface YoutubeInnertubePlaybackContext {
  contentPlaybackContext: YoutubeInnertubeContentPlaybackContext;
}

interface YoutubeInnertubePlayerRequestBody {
  context: YoutubeInnertubeRequestContext;
  videoId: string;
  playbackContext: YoutubeInnertubePlaybackContext;
  contentCheckOk: boolean;
  racyCheckOk: boolean;
}

export class YoutubeInnertubePlayerService {
  private parser: YoutubeStreamingDataParser = new YoutubeStreamingDataParser();
  private selector: YoutubeFormatSelector = new YoutubeFormatSelector();
  private httpProxyService: NativeVideoHttpProxyService = new NativeVideoHttpProxyService(sharedPreferencesRepository);

  async fetchPlan(
    probe: YoutubePageProbeResult,
    pageUrl: string,
    videoId: string,
    suppressDiagnostics: boolean
  ): Promise<YoutubePlaybackPlan | undefined> {
    const apiKey = probe.innertubeApiKey?.trim() ?? '';
    if (apiKey.length <= 0 || videoId.trim().length <= 0) {
      return undefined;
    }
    const clients = this.buildClients(probe);
    let adaptivePlan: YoutubePlaybackPlan | undefined = undefined;
    let fallbackPlan: YoutubePlaybackPlan | undefined = undefined;
    for (let i = 0; i < clients.length; i++) {
      const plan = await this.fetchPlanForClient(apiKey, clients[i], pageUrl, videoId, suppressDiagnostics);
      if (plan === undefined) {
        continue;
      }
      if (fallbackPlan === undefined) {
        fallbackPlan = plan;
      }
      if (plan.status !== 'ok') {
        continue;
      }
      const selection = this.selector.selectDefault(plan);
      if (adaptivePlan === undefined && this.hasPlayableAdaptivePair(selection)) {
        adaptivePlan = plan;
      }
      if (this.hasPlayableAdaptivePair(selection)) {
        continue;
      }
      if (adaptivePlan === undefined && selection.progressive !== undefined) {
        adaptivePlan = plan;
      }
    }
    return adaptivePlan ?? fallbackPlan;
  }

  private hasPlayableAdaptivePair(selection: YoutubeFormatSelection): boolean {
    return selection.video !== undefined && selection.video.url.length > 0 &&
      selection.audio !== undefined && selection.audio.url.length > 0;
  }

  private buildClients(probe: YoutubePageProbeResult): YoutubeInnertubeClientInput[] {
    const clients: YoutubeInnertubeClientInput[] = [];
    clients.push({
      clientName: 'ANDROID_VR',
      clientVersion: YOUTUBE_ANDROID_VR_CLIENT_VERSION,
      userAgent: YOUTUBE_ANDROID_VR_UA,
      visitorData: probe.visitorData,
      deviceMake: 'Oculus',
      deviceModel: 'Quest 3',
      osName: 'Android',
      osVersion: '12L',
      androidSdkVersion: 32
    });
    clients.push({
      clientName: 'IOS',
      clientVersion: YOUTUBE_IOS_CLIENT_VERSION,
      userAgent: YOUTUBE_IOS_UA,
      visitorData: probe.visitorData,
      deviceMake: 'Apple',
      deviceModel: 'iPhone16,2',
      osName: 'iOS',
      osVersion: '18.7.2.22H124'
    });
    clients.push({
      clientName: 'ANDROID',
      clientVersion: YOUTUBE_ANDROID_CLIENT_VERSION,
      userAgent: YOUTUBE_ANDROID_UA,
      visitorData: probe.visitorData,
      osName: 'Android',
      osVersion: '16',
      androidSdkVersion: 36
    });
    const clientName = probe.innertubeClientName?.trim() ?? '';
    const clientVersion = probe.innertubeClientVersion?.trim() ?? '';
    if (clientName.length > 0 && clientVersion.length > 0) {
      clients.push({
        clientName,
        clientVersion,
        userAgent: probe.userAgent,
        visitorData: probe.visitorData
      });
    }
    clients.push({
      clientName: 'WEB',
      clientVersion: YOUTUBE_WEB_SAFARI_CLIENT_VERSION,
      userAgent: YOUTUBE_WEB_SAFARI_UA,
      visitorData: probe.visitorData
    });
    return clients;
  }

  private async fetchPlanForClient(
    apiKey: string,
    client: YoutubeInnertubeClientInput,
    pageUrl: string,
    videoId: string,
    suppressDiagnostics: boolean
  ): Promise<YoutubePlaybackPlan | undefined> {
    const request = http.createHttp();
    const endpoint = `https://www.youtube.com/youtubei/v1/player?key=${encodeURIComponent(apiKey)}`;
    try {
      const body = this.buildRequestBody(client, videoId);
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: YOUTUBE_INNERTUBE_TIMEOUT_MS,
        readTimeout: YOUTUBE_INNERTUBE_TIMEOUT_MS,
        usingCache: false,
        header: this.buildRequestHeaders(client, pageUrl),
        extraData: JSON.stringify(body)
      };
      this.applyNativeHttpProxy(options, client.clientName, suppressDiagnostics);
      const response = await request.request(endpoint, options);
      if (response.responseCode < 200 || response.responseCode >= 300 || typeof response.result !== 'string') {
        this.runDiagnostics(suppressDiagnostics, (): void => {
          hilog.warn(
            YOUTUBE_INNERTUBE_LOG_DOMAIN,
            YOUTUBE_INNERTUBE_LOG_TAG,
            'player api failed client=%{public}s code=%{public}d',
            client.clientName,
            response.responseCode
          );
        });
        return undefined;
      }
      const plan = this.parser.parse(response.result, pageUrl, videoId);
      this.applyClientStreamPolicy(plan, client.clientName);
      if ((client.userAgent ?? '').trim().length > 0) {
        plan.userAgent = client.userAgent;
      }
      this.runDiagnostics(suppressDiagnostics, (): void => {
        hilog.info(
          YOUTUBE_INNERTUBE_LOG_DOMAIN,
          YOUTUBE_INNERTUBE_LOG_TAG,
          'player api plan client=%{public}s status=%{public}s formats=%{public}d adaptiveV=%{public}d adaptiveA=%{public}d hls=%{public}s',
          client.clientName,
          plan.status,
          plan.progressiveFormats.length,
          plan.videoOnlyFormats.length,
          plan.audioOnlyFormats.length,
          (plan.hlsManifestUrl ?? '').length > 0 ? 'true' : 'false'
        );
      });
      return plan;
    } catch (error) {
      this.runDiagnostics(suppressDiagnostics, (): void => {
        hilog.warn(
          YOUTUBE_INNERTUBE_LOG_DOMAIN,
          YOUTUBE_INNERTUBE_LOG_TAG,
          'player api error client=%{public}s message=%{public}s',
          client.clientName,
          (error as Error)?.message ?? 'unknown'
        );
      });
      return undefined;
    } finally {
      request.destroy();
    }
  }

  private buildRequestBody(client: YoutubeInnertubeClientInput, videoId: string): YoutubeInnertubePlayerRequestBody {
    const clientContext: YoutubeInnertubeClientContext = {
      clientName: client.clientName,
      clientVersion: client.clientVersion
    };
    if ((client.userAgent ?? '').trim().length > 0) {
      clientContext.userAgent = client.userAgent ?? '';
    }
    if ((client.visitorData ?? '').trim().length > 0) {
      clientContext.visitorData = client.visitorData ?? '';
    }
    if ((client.deviceMake ?? '').trim().length > 0) {
      clientContext.deviceMake = client.deviceMake ?? '';
    }
    if ((client.deviceModel ?? '').trim().length > 0) {
      clientContext.deviceModel = client.deviceModel ?? '';
    }
    if ((client.osName ?? '').trim().length > 0) {
      clientContext.osName = client.osName ?? '';
    }
    if ((client.osVersion ?? '').trim().length > 0) {
      clientContext.osVersion = client.osVersion ?? '';
    }
    if (client.androidSdkVersion !== undefined && client.androidSdkVersion > 0) {
      clientContext.androidSdkVersion = client.androidSdkVersion;
    }
    const requestContext: YoutubeInnertubeRequestContext = {
      client: clientContext
    };
    const contentPlaybackContext: YoutubeInnertubeContentPlaybackContext = {
      html5Preference: 'HTML5_PREF_WANTS'
    };
    const playbackContext: YoutubeInnertubePlaybackContext = {
      contentPlaybackContext
    };
    const body: YoutubeInnertubePlayerRequestBody = {
      context: requestContext,
      videoId,
      playbackContext,
      contentCheckOk: true,
      racyCheckOk: true
    };
    return body;
  }

  private resolveClientNameCode(clientName: string): string {
    switch (clientName) {
      case 'WEB': return '1';
      case 'WEB_EMBEDDED_PLAYER': return '56';
      case 'MWEB': return '2';
      case 'ANDROID': return '3';
      case 'ANDROID_VR': return '28';
      case 'IOS': return '5';
      default: return '1';
    }
  }

  private isMobileClient(clientName: string): boolean {
    return clientName === 'IOS' || clientName === 'ANDROID' || clientName === 'ANDROID_VR';
  }

  private applyClientStreamPolicy(plan: YoutubePlaybackPlan, clientName: string): void {
    plan.sourceClient = clientName;
    this.applyFormatClientPolicy(plan.progressiveFormats, clientName);
    this.applyFormatClientPolicy(plan.videoOnlyFormats, clientName);
    this.applyFormatClientPolicy(plan.audioOnlyFormats, clientName);
  }

  private applyFormatClientPolicy(formats: YoutubeFormat[], clientName: string): void {
    for (let i = 0; i < formats.length; i++) {
      const format = formats[i];
      format.sourceClient = clientName;
      if (!format.hasPoToken && this.requiresGvsPoToken(clientName, format.itag)) {
        format.requiresPoToken = true;
      }
    }
  }

  private requiresGvsPoToken(clientName: string, itag: number): boolean {
    if (itag === 18) {
      return false;
    }
    switch (clientName) {
      case 'WEB':
      case 'MWEB':
      case 'IOS':
      case 'ANDROID':
        return true;
      default:
        return false;
    }
  }

  private buildRequestHeaders(client: YoutubeInnertubeClientInput, pageUrl: string): Record<string, string> {
    const headers: Record<string, string> = {
      'Accept': 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
      'Origin': 'https://www.youtube.com',
      'Referer': pageUrl,
      'User-Agent': client.userAgent ?? YOUTUBE_WEB_SAFARI_UA,
      'X-YouTube-Client-Name': this.resolveClientNameCode(client.clientName),
      'X-YouTube-Client-Version': client.clientVersion
    };
    if (this.isMobileClient(client.clientName)) {
      headers['X-Goog-Api-Format-Version'] = '2';
    }
    const visitorData = client.visitorData?.trim() ?? '';
    if (visitorData.length > 0) {
      headers['X-Goog-Visitor-Id'] = visitorData;
    }
    return headers;
  }

  private applyNativeHttpProxy(
    options: http.HttpRequestOptions,
    clientName: string,
    suppressDiagnostics: boolean
  ): void {
    const resolution = this.httpProxyService.resolveFromCurrentPreferences();
    if (resolution.usingProxy !== undefined) {
      options.usingProxy = resolution.usingProxy;
    }
    this.logNativeHttpProxy(clientName, resolution, suppressDiagnostics);
  }

  private logNativeHttpProxy(
    clientName: string,
    resolution: NativeVideoHttpProxyResolution,
    suppressDiagnostics: boolean
  ): void {
    this.runDiagnostics(suppressDiagnostics, (): void => {
      hilog.info(
        YOUTUBE_INNERTUBE_LOG_DOMAIN,
        YOUTUBE_INNERTUBE_LOG_TAG,
        'player api proxy client=%{public}s enabled=%{public}s applied=%{public}s scheme=%{public}s proxyHost=%{public}s proxyPort=%{public}d auth=%{public}s',
        clientName,
        resolution.enabled ? '1' : '0',
        resolution.usingProxy !== undefined ? '1' : '0',
        resolution.scheme,
        this.maskHost(resolution.host),
        resolution.port,
        resolution.hasCredentials ? '1' : '0'
      );
    });
  }

  private maskHost(value: string): string {
    const host = value.trim();
    if (host.length <= 0) {
      return '';
    }
    if (host === '127.0.0.1' || host === '::1' || host === 'localhost') {
      return host;
    }
    if (host.length <= 3) {
      return '***';
    }
    return `${host.substring(0, 1)}***(${host.length})`;
  }

  private runDiagnostics(suppressDiagnostics: boolean, write: () => void): void {
    if (!suppressDiagnostics) {
      write();
    }
  }
}
