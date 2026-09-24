export const MANUAL_FULLSCREEN_ENTER_HINT_ESCAPE: string = '已进入全屏模式，按 Esc 退出。';
export const MANUAL_FULLSCREEN_ENTER_HINT_SYSTEM_BACK: string = '已进入全屏模式，按系统返回键可退出。';

/**
 * Computers advertise Esc. Tablets and phones keep the system back hint, even
 * when they are using the large-screen shell.
 */
export function isComputerFullscreenDevice(deviceType: string): boolean {
  const normalized = deviceType.trim().toLowerCase();
  return normalized === 'pc' ||
    normalized === 'desktop' ||
    normalized === '2in1' ||
    normalized === 'two_in_one' ||
    normalized === 'two-in-one';
}

export function resolveManualFullscreenEnterHint(deviceType: string): string {
  return isComputerFullscreenDevice(deviceType)
    ? MANUAL_FULLSCREEN_ENTER_HINT_ESCAPE
    : MANUAL_FULLSCREEN_ENTER_HINT_SYSTEM_BACK;
}

export function shouldExitFullscreenOnEscape(
  fullScreenModeEnabled: boolean,
  isEscapeKey: boolean,
  isKeyDown: boolean
): boolean {
  return fullScreenModeEnabled && isEscapeKey && isKeyDown;
}
