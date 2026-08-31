export const WEB_VIDEO_FRAME_HOST_PROTOCOL: string = 'aira.media_frame_host.v1';
export const WEB_VIDEO_FRAME_HOST_BRIDGE_PROPERTY: string = '__airaMediaVideoFrameHostBridgeV1';

export interface WebVideoFrameCommandRequest {
  tabId: string;
  frameRuntimeId: string;
  action: string;
  script: string;
}

export interface WebVideoFrameCommandTransport {
  executeFrameCommand(request: WebVideoFrameCommandRequest): Promise<string>;
}
