import { AVCastPickerState, avSession } from '@kit.AVSessionKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import urlUtils from '@ohos.url';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { isLikelyLocalUrlHost } from '../../common/utils/UrlUtils';

const VIDEO_ASSISTANT_CAST_LOG_DOMAIN: number = 0x0000;
const VIDEO_ASSISTANT_CAST_LOG_TAG: string = 'VideoAssistantCast';
const VIDEO_ASSISTANT_CAST_QUEUE_ITEM_ID: number = 1;

export interface VideoAssistantCastMediaItem {
  sessionKey: string;
  title: string;
  pageUrl: string;
  mediaUri: string;
  mediaFormat: string;
  posterUrl?: string;
  durationSeconds: number;
  positionSeconds: number;
  requiresWebRequestContext: boolean;
  requestHeaderCount: number;
}

export interface VideoAssistantCastLocalPlaybackHandler {
  isCurrent: () => boolean;
  isPlaying: () => boolean;
  pause: () => Promise<boolean>;
  resume: () => Promise<boolean>;
  showMessage: (message: string) => void;
}

export type VideoAssistantCastRequestReason =
  'picker_opened' |
  'request_in_flight' |
  'media_unavailable' |
  'session_unavailable' |
  'picker_failed';

export interface VideoAssistantCastRequestResult {
  opened: boolean;
  reason: VideoAssistantCastRequestReason;
  message: string;
}

export class VideoAssistantCastSessionService {
  private session?: avSession.AVSession = undefined;
  private sessionController?: avSession.AVSessionController = undefined;
  private castController?: avSession.AVCastController = undefined;
  private picker?: avSession.AVCastPickerHelper = undefined;
  private currentItem?: VideoAssistantCastMediaItem = undefined;
  private currentQueueItem?: avSession.AVQueueItem = undefined;
  private currentHandler?: VideoAssistantCastLocalPlaybackHandler = undefined;
  private requestGeneration: number = 0;
  private requestInFlight: boolean = false;
  private remoteStartInFlight: boolean = false;
  private remoteStartedKey: string = '';
  private remoteDeviceKey: string = '';
  private remotePlaybackConfirmedDeviceKey: string = '';
  private remoteConnectionGeneration: number = 0;
  private localPausedByCast: boolean = false;
  private remoteStartTask: Promise<void> = Promise.resolve();
  private localPlaybackTask: Promise<void> = Promise.resolve();

  private readonly outputDeviceChangeCallback =
    (state: avSession.ConnectionState, device: avSession.OutputDeviceInfo): void => {
      void this.handleOutputDeviceChange(state, device);
    };

  private readonly remotePlaybackStateChangeCallback = (state: avSession.AVPlaybackState): void => {
    void this.handleRemotePlaybackStateChange(state);
  };

  private readonly pickerStateChangeCallback = (state: AVCastPickerState): void => {
    this.logInfo('picker_state', state.toString());
  };

  async requestCast(
    item: VideoAssistantCastMediaItem,
    handler: VideoAssistantCastLocalPlaybackHandler
  ): Promise<VideoAssistantCastRequestResult> {
    if (this.requestInFlight) {
      return this.buildResult(false, 'request_in_flight', '投放设备列表正在打开。');
    }
    if (this.remoteStartInFlight) {
      return this.buildResult(false, 'request_in_flight', '正在启动远端视频。');
    }
    if (!AppRuntimeContext.hasUIAbilityContext()) {
      return this.buildResult(false, 'session_unavailable', '当前无法打开投放设备列表。');
    }

    const generation = ++this.requestGeneration;
    this.requestInFlight = true;
    this.currentItem = item;
    this.currentQueueItem = undefined;
    this.currentHandler = handler;
    try {
      const context = AppRuntimeContext.getUIAbilityContext();
      const session = await avSession.getAVSession(context);
      const controller = await session.getController();
      if (!this.isRequestCurrent(generation, item.sessionKey)) {
        return this.buildResult(false, 'session_unavailable', '当前视频会话已经变化。');
      }

      this.bindSession(session, controller);
      this.currentQueueItem = await this.resolveRemoteQueueItem(controller, item);
      if (this.currentQueueItem === undefined) {
        this.logInfo(
          'picker_request_rejected',
          `reason=no_remote_uri format=${item.mediaFormat} headers=${item.requestHeaderCount} ` +
            `web_context=${item.requiresWebRequestContext ? 'yes' : 'no'}`
        );
        return this.buildResult(
          false,
          'media_unavailable',
          '当前视频没有可供投放设备直接读取的地址。'
        );
      }
      await this.enableUrlCast(session, controller);
      this.detachPicker();
      this.picker = new avSession.AVCastPickerHelper(context);
      this.picker.on('pickerStateChange', this.pickerStateChangeCallback);
      this.logInfo(
        'picker_request',
        `media=ready headers=${item.requestHeaderCount} ` +
          `web_context=${item.requiresWebRequestContext ? 'yes' : 'no'}`
      );
      await this.picker.select({ sessionType: 'video' });
      if (!this.isRequestCurrent(generation, item.sessionKey)) {
        return this.buildResult(false, 'session_unavailable', '当前视频会话已经变化。');
      }
      await this.startIfAlreadyConnected(controller);
      return this.buildResult(true, 'picker_opened', '');
    } catch (error) {
      this.logWarning('picker_request_failed', error);
      if (this.isRequestCurrent(generation, item.sessionKey)) {
        this.detachPicker();
        this.currentQueueItem = undefined;
      }
      return this.buildResult(false, 'picker_failed', '投放设备列表打开失败，请稍后重试。');
    } finally {
      if (generation === this.requestGeneration) {
        this.requestInFlight = false;
      }
    }
  }

  async release(): Promise<void> {
    this.requestGeneration += 1;
    this.requestInFlight = false;
    this.remoteStartInFlight = false;
    this.remoteStartedKey = '';
    this.remoteDeviceKey = '';
    this.remotePlaybackConfirmedDeviceKey = '';
    this.remoteConnectionGeneration += 1;
    this.localPausedByCast = false;
    this.currentItem = undefined;
    this.currentQueueItem = undefined;
    this.currentHandler = undefined;
    this.detachCastController();
    this.detachPicker();
    this.detachSessionController();
    this.session = undefined;
  }

  private bindSession(session: avSession.AVSession, controller: avSession.AVSessionController): void {
    if (this.sessionController !== controller) {
      this.detachSessionController();
      controller.on('outputDeviceChange', this.outputDeviceChangeCallback);
    }
    this.session = session;
    this.sessionController = controller;
  }

  private async enableUrlCast(
    session: avSession.AVSession,
    controller: avSession.AVSessionController
  ): Promise<void> {
    try {
      const extras = await controller.getExtras();
      extras['requireAbilityList'] = this.mergeUrlCastAbilityList(extras['requireAbilityList']);
      await session.setExtras(extras);
    } catch (error) {
      this.logWarning('merge_cast_extras_failed', error);
      throw new Error('video-assistant-cast-extras-unavailable');
    }
  }

  private async resolveRemoteQueueItem(
    controller: avSession.AVSessionController,
    item: VideoAssistantCastMediaItem
  ): Promise<avSession.AVQueueItem | undefined> {
    try {
      const state = await controller.getAVPlaybackState();
      const queueItems = await controller.getAVQueueItems();
      const activeItem = this.findCastableQueueItem(queueItems, state.activeItemId);
      if (activeItem !== undefined && this.queueItemMatchesCurrentMedia(activeItem, item)) {
        this.logInfo('queue_item_resolved', 'source=arkweb');
        return activeItem;
      }
      if (activeItem !== undefined) {
        this.logInfo('queue_item_rejected', 'reason=current_media_mismatch');
      }
    } catch (error) {
      this.logWarning('queue_read_failed', error);
    }
    if (!this.isDirectRemoteMediaUrl(item.mediaUri) || item.requiresWebRequestContext) {
      this.logInfo(
        'queue_item_unavailable',
        `format=${item.mediaFormat} headers=${item.requestHeaderCount} ` +
          `web_context=${item.requiresWebRequestContext ? 'yes' : 'no'}`
      );
      return undefined;
    }
    this.logInfo('queue_item_resolved', `source=media_info format=${item.mediaFormat}`);
    return this.buildQueueItem(item);
  }

  private findCastableQueueItem(
    queueItems: avSession.AVQueueItem[],
    activeItemId: number | undefined
  ): avSession.AVQueueItem | undefined {
    if (activeItemId !== undefined) {
      for (let i: number = 0; i < queueItems.length; i += 1) {
        if (queueItems[i].itemId === activeItemId && this.queueItemHasRemoteUri(queueItems[i])) {
          return queueItems[i];
        }
      }
      return undefined;
    }
    let resolvedItem: avSession.AVQueueItem | undefined = undefined;
    for (let i: number = 0; i < queueItems.length; i += 1) {
      if (this.queueItemHasRemoteUri(queueItems[i])) {
        if (resolvedItem !== undefined) {
          return undefined;
        }
        resolvedItem = queueItems[i];
      }
    }
    return resolvedItem;
  }

  private queueItemHasRemoteUri(item: avSession.AVQueueItem): boolean {
    return this.isDirectRemoteMediaUrl(item.description?.mediaUri ?? '');
  }

  private queueItemMatchesCurrentMedia(
    queueItem: avSession.AVQueueItem,
    item: VideoAssistantCastMediaItem
  ): boolean {
    const expectedUri = item.mediaUri.trim();
    const queueUri = queueItem.description?.mediaUri?.trim() ?? '';
    return !item.requiresWebRequestContext && this.isDirectRemoteMediaUrl(expectedUri) && queueUri === expectedUri;
  }

  private async startIfAlreadyConnected(controller: avSession.AVSessionController): Promise<void> {
    try {
      const device = await controller.getOutputDevice();
      if (this.hasRemoteCastDevice(device)) {
        this.updateRemoteDevice(device);
        await this.queueRemoteStart();
      }
    } catch (error) {
      this.logWarning('output_device_read_failed', error);
    }
  }

  private async handleOutputDeviceChange(
    state: avSession.ConnectionState,
    device: avSession.OutputDeviceInfo
  ): Promise<void> {
    const hasRemoteDevice = this.hasRemoteCastDevice(device);
    this.logInfo('output_device_change', `state=${state} remote=${hasRemoteDevice ? 'yes' : 'no'}`);
    if (state === avSession.ConnectionState.STATE_DISCONNECTED) {
      this.remoteConnectionGeneration += 1;
      this.remoteDeviceKey = '';
      this.remotePlaybackConfirmedDeviceKey = '';
      this.detachCastController();
      this.remoteStartedKey = '';
      await this.queueLocalPlaybackReconciliation('remote_disconnected');
      return;
    }
    if (state === avSession.ConnectionState.STATE_CONNECTED && hasRemoteDevice) {
      this.updateRemoteDevice(device);
      if (this.requestInFlight) {
        this.logInfo('remote_start_deferred', 'picker_request_in_flight');
        return;
      }
      await this.queueRemoteStart();
    }
  }

  private queueRemoteStart(): Promise<void> {
    const task = this.remoteStartTask
      .catch((_error: Error): void => {})
      .then((): Promise<void> => this.startRemotePlayback());
    this.remoteStartTask = task.catch((_error: Error): void => {});
    return task;
  }

  private async startRemotePlayback(): Promise<void> {
    const session = this.session;
    const item = this.currentItem;
    const queueItem = this.currentQueueItem;
    const handler = this.currentHandler;
    const deviceKey = this.remoteDeviceKey;
    const connectionGeneration = this.remoteConnectionGeneration;
    if (session === undefined || item === undefined || handler === undefined || !handler.isCurrent() ||
      deviceKey.length <= 0) {
      return;
    }
    if (queueItem === undefined) {
      this.logInfo('remote_start_skipped', 'reason=no_remote_uri');
      handler.showMessage('投放设备已连接，但当前视频没有可供设备直接读取的地址。');
      return;
    }
    const generation = this.requestGeneration;
    const remoteStartKey = this.buildRemoteStartKey(item, queueItem, deviceKey);
    if (this.remoteStartedKey === remoteStartKey) {
      this.logInfo('remote_start_skipped', 'reason=already_started');
      return;
    }

    this.remoteStartInFlight = true;
    try {
      const controller = await session.getAVCastController();
      if (!this.isRemoteStartCurrent(
        generation,
        connectionGeneration,
        item.sessionKey,
        queueItem,
        deviceKey
      )) {
        return;
      }
      this.bindCastController(controller);
      try {
        await controller.prepare(queueItem);
      } catch (error) {
        this.logWarning('remote_prepare_failed', error);
      }
      if (!this.isRemoteStartCurrent(
        generation,
        connectionGeneration,
        item.sessionKey,
        queueItem,
        deviceKey
      )) {
        return;
      }
      this.logInfo('remote_start_request', 'sent');
      await controller.start(queueItem);
      if (!this.isRemoteStartCurrent(
        generation,
        connectionGeneration,
        item.sessionKey,
        queueItem,
        deviceKey
      )) {
        return;
      }
      this.remoteStartedKey = remoteStartKey;
      const state = await controller.getAVPlaybackState();
      await this.handleRemotePlaybackStateChange(state);
    } catch (error) {
      this.logWarning('remote_start_failed', error);
      if (this.isRemoteStartCurrent(
        generation,
        connectionGeneration,
        item.sessionKey,
        queueItem,
        deviceKey
      )) {
        this.remoteStartedKey = '';
        this.remotePlaybackConfirmedDeviceKey = '';
        handler.showMessage('投放设备已连接，但视频启动失败。');
        await this.queueLocalPlaybackReconciliation('remote_start_failed');
      }
    } finally {
      this.remoteStartInFlight = false;
    }
  }

  private bindCastController(controller: avSession.AVCastController): void {
    if (this.castController === controller) {
      return;
    }
    this.detachCastController();
    controller.on('playbackStateChange', 'all', this.remotePlaybackStateChangeCallback);
    this.castController = controller;
  }

  private async handleRemotePlaybackStateChange(state: avSession.AVPlaybackState): Promise<void> {
    const handler = this.currentHandler;
    if (handler === undefined || !handler.isCurrent()) {
      return;
    }
    this.logInfo('remote_playback_state', `state=${state.state ?? -1}`);
    if (state.state === avSession.PlaybackState.PLAYBACK_STATE_PLAY) {
      if (this.remoteDeviceKey.length > 0) {
        this.remotePlaybackConfirmedDeviceKey = this.remoteDeviceKey;
        await this.queueLocalPlaybackReconciliation('remote_play_confirmed');
      }
      return;
    }
    if (state.state === avSession.PlaybackState.PLAYBACK_STATE_ERROR) {
      this.remoteStartedKey = '';
      this.remotePlaybackConfirmedDeviceKey = '';
      handler.showMessage('投放设备无法播放当前视频。');
      await this.queueLocalPlaybackReconciliation('remote_playback_error');
      return;
    }
    if (state.state === avSession.PlaybackState.PLAYBACK_STATE_STOP ||
      state.state === avSession.PlaybackState.PLAYBACK_STATE_COMPLETED) {
      this.remoteStartedKey = '';
    }
  }

  private queueLocalPlaybackReconciliation(reason: string): Promise<void> {
    const task = this.localPlaybackTask
      .catch((_error: Error): void => {})
      .then((): Promise<void> => this.reconcileLocalPlayback(reason));
    this.localPlaybackTask = task.catch((_error: Error): void => {});
    return task;
  }

  private async reconcileLocalPlayback(reason: string): Promise<void> {
    const handler = this.currentHandler;
    if (handler === undefined || !handler.isCurrent()) {
      this.localPausedByCast = false;
      return;
    }
    const shouldPause = this.remoteDeviceKey.length > 0 &&
      this.remotePlaybackConfirmedDeviceKey === this.remoteDeviceKey;
    if (shouldPause) {
      if (this.localPausedByCast || !handler.isPlaying()) {
        return;
      }
      const generation = this.requestGeneration;
      if (await handler.pause() && generation === this.requestGeneration && this.currentHandler === handler) {
        this.localPausedByCast = true;
        this.logInfo('local_playback_paused', reason);
      }
      return;
    }
    if (!this.localPausedByCast) {
      return;
    }
    if (handler.isPlaying()) {
      this.localPausedByCast = false;
      return;
    }
    const generation = this.requestGeneration;
    if (await handler.resume() && generation === this.requestGeneration && this.currentHandler === handler) {
      this.localPausedByCast = false;
      this.logInfo('local_playback_resumed', reason);
    }
  }

  private detachSessionController(): void {
    const controller = this.sessionController;
    this.sessionController = undefined;
    if (controller === undefined) {
      return;
    }
    try {
      controller.off('outputDeviceChange', this.outputDeviceChangeCallback);
    } catch (error) {
      this.logWarning('session_listener_release_failed', error);
    }
  }

  private detachCastController(): void {
    const controller = this.castController;
    this.castController = undefined;
    if (controller === undefined) {
      return;
    }
    try {
      controller.off('playbackStateChange', this.remotePlaybackStateChangeCallback);
    } catch (error) {
      this.logWarning('cast_listener_release_failed', error);
    }
  }

  private detachPicker(): void {
    const picker = this.picker;
    this.picker = undefined;
    if (picker === undefined) {
      return;
    }
    try {
      picker.off('pickerStateChange', this.pickerStateChangeCallback);
    } catch (error) {
      this.logWarning('picker_listener_release_failed', error);
    }
  }

  private buildQueueItem(item: VideoAssistantCastMediaItem): avSession.AVQueueItem {
    const description: avSession.AVMediaDescription = {
      assetId: item.sessionKey,
      title: item.title.trim().length > 0 ? item.title.trim() : '网页视频',
      subtitle: item.pageUrl,
      mediaType: 'video',
      mediaUri: item.mediaUri.trim(),
      mediaImage: item.posterUrl,
      duration: this.secondsToMs(item.durationSeconds)
    };
    if (item.durationSeconds > 0 && item.positionSeconds > 0) {
      description.startPosition = this.secondsToMs(item.positionSeconds);
    }
    return {
      itemId: VIDEO_ASSISTANT_CAST_QUEUE_ITEM_ID,
      description: description
    };
  }

  private buildRemoteStartKey(
    item: VideoAssistantCastMediaItem,
    queueItem: avSession.AVQueueItem,
    deviceKey: string
  ): string {
    const description = queueItem.description;
    return [
      item.sessionKey,
      deviceKey,
      queueItem.itemId.toString(),
      description?.assetId ?? '',
      description?.mediaUri ?? ''
    ].join('\n');
  }

  private isRemoteStartCurrent(
    requestGeneration: number,
    connectionGeneration: number,
    sessionKey: string,
    queueItem: avSession.AVQueueItem,
    deviceKey: string
  ): boolean {
    return this.isRequestCurrent(requestGeneration, sessionKey) &&
      connectionGeneration === this.remoteConnectionGeneration &&
      this.remoteDeviceKey === deviceKey && this.currentQueueItem === queueItem;
  }

  private mergeUrlCastAbilityList(value: Object | undefined): string[] {
    const abilities: string[] = [];
    if (Array.isArray(value)) {
      for (let i: number = 0; i < value.length; i += 1) {
        if (typeof value[i] === 'string') {
          const ability = (value[i] as string).trim();
          if (ability.length > 0 && abilities.indexOf(ability) < 0) {
            abilities.push(ability);
          }
        }
      }
    }
    if (abilities.indexOf('url-cast') < 0) {
      abilities.push('url-cast');
    }
    return abilities;
  }

  private isRequestCurrent(generation: number, sessionKey: string): boolean {
    return generation === this.requestGeneration && this.currentItem?.sessionKey === sessionKey &&
      this.currentHandler?.isCurrent() === true;
  }

  private hasRemoteCastDevice(device: avSession.OutputDeviceInfo): boolean {
    for (let i: number = 0; i < device.devices.length; i += 1) {
      if (device.devices[i].castCategory === avSession.AVCastCategory.CATEGORY_REMOTE) {
        return true;
      }
    }
    return false;
  }

  private updateRemoteDevice(device: avSession.OutputDeviceInfo): void {
    const deviceKey = this.resolveRemoteDeviceKey(device);
    if (deviceKey.length <= 0 || deviceKey === this.remoteDeviceKey) {
      return;
    }
    this.remoteConnectionGeneration += 1;
    this.remoteDeviceKey = deviceKey;
    this.remotePlaybackConfirmedDeviceKey = '';
    this.remoteStartedKey = '';
    this.detachCastController();
  }

  private resolveRemoteDeviceKey(device: avSession.OutputDeviceInfo): string {
    const deviceIds: string[] = [];
    for (let i: number = 0; i < device.devices.length; i += 1) {
      const candidate = device.devices[i];
      const deviceId = candidate.deviceId.trim();
      if (candidate.castCategory === avSession.AVCastCategory.CATEGORY_REMOTE && deviceId.length > 0 &&
        deviceIds.indexOf(deviceId) < 0) {
        deviceIds.push(deviceId);
      }
    }
    deviceIds.sort();
    return deviceIds.join('|');
  }

  private secondsToMs(seconds: number): number {
    if (!Number.isFinite(seconds) || seconds <= 0) {
      return 0;
    }
    return Math.floor(seconds * 1000);
  }

  private isDirectRemoteMediaUrl(url: string): boolean {
    try {
      const parsed = urlUtils.URL.parseURL(url.trim());
      const protocol = parsed.protocol.trim().toLowerCase();
      const hostname = parsed.hostname.trim();
      return (protocol === 'http:' || protocol === 'https:') && !isLikelyLocalUrlHost(hostname);
    } catch (_error) {
      return false;
    }
  }

  private buildResult(
    opened: boolean,
    reason: VideoAssistantCastRequestReason,
    message: string
  ): VideoAssistantCastRequestResult {
    return {
      opened: opened,
      reason: reason,
      message: message
    };
  }

  private logInfo(event: string, detail: string): void {
    hilog.info(
      VIDEO_ASSISTANT_CAST_LOG_DOMAIN,
      VIDEO_ASSISTANT_CAST_LOG_TAG,
      '%{public}s %{public}s',
      event,
      detail
    );
  }

  private logWarning(event: string, error: Object): void {
    hilog.warn(
      VIDEO_ASSISTANT_CAST_LOG_DOMAIN,
      VIDEO_ASSISTANT_CAST_LOG_TAG,
      '%{public}s %{public}s',
      event,
      `${error}`
    );
  }
}
