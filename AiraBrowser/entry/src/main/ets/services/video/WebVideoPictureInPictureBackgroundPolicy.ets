export const WEB_VIDEO_PICTURE_IN_PICTURE_ENTER_SOURCE: string = 'picture_in_picture_enter';
export const WEB_VIDEO_PICTURE_IN_PICTURE_LEAVE_SOURCE: string = 'picture_in_picture_leave';
export const WEB_VIDEO_PICTURE_IN_PICTURE_WEBKIT_ENTER_SOURCE: string = 'webkit_picture_in_picture_enter';
export const WEB_VIDEO_PICTURE_IN_PICTURE_WEBKIT_LEAVE_SOURCE: string = 'webkit_picture_in_picture_leave';
export const WEB_VIDEO_PICTURE_IN_PICTURE_PAGEHIDE_SOURCE: string = 'picture_in_picture_pagehide';

interface PictureInPictureBackgroundSignalPayload {
  source?: string;
}

export function readPictureInPictureBackgroundSignal(payloadJson: string): boolean | undefined {
  let payload: PictureInPictureBackgroundSignalPayload;
  try {
    payload = JSON.parse(payloadJson) as PictureInPictureBackgroundSignalPayload;
  } catch (_error) {
    return undefined;
  }
  const source = payload.source?.trim() ?? '';
  if (source === WEB_VIDEO_PICTURE_IN_PICTURE_ENTER_SOURCE ||
    source === WEB_VIDEO_PICTURE_IN_PICTURE_WEBKIT_ENTER_SOURCE) {
    return true;
  }
  if (source === WEB_VIDEO_PICTURE_IN_PICTURE_LEAVE_SOURCE ||
    source === WEB_VIDEO_PICTURE_IN_PICTURE_WEBKIT_LEAVE_SOURCE ||
    source === WEB_VIDEO_PICTURE_IN_PICTURE_PAGEHIDE_SOURCE) {
    return false;
  }
  return undefined;
}
