import type { AiraDesktopPairingSession } from '@/features/desktop-connection/AiraDesktopConnectionModule';
import {
  AIRA_DESKTOP_CONNECTION_CHANGED_EVENT,
  disconnectAiraDesktopDevice,
  getAiraDesktopConnectionModule,
} from '@/features/desktop-connection/desktopConnectionRuntime';

export const AIRA_DESKTOP_LOGIN_PROFILE_CHANGED_EVENT = AIRA_DESKTOP_CONNECTION_CHANGED_EVENT;

export type AiraDesktopLoginSession = {
  sessionId: string;
  pollToken: string;
  desktopPushToken: string;
  qrPayload: string;
  expiresAt: number;
  pollIntervalMs: number;
  deviceId?: string;
  deviceName?: string;
};

export type AiraDesktopLoginStatus =
  | {
    status: 'pending' | 'expired';
    expiresAt: number;
    pollIntervalMs: number;
  }
  | {
    status: 'confirmed';
    confirmedAt: number;
  };

export async function createAiraDesktopLoginSession(): Promise<AiraDesktopLoginSession> {
  const session = await (await getAiraDesktopConnectionModule()).createPairing();
  return {
    ...session,
    desktopPushToken: session.deviceCredential,
  };
}

export async function pollAiraDesktopLoginStatus(session: AiraDesktopLoginSession): Promise<AiraDesktopLoginStatus> {
  const result = await (await getAiraDesktopConnectionModule()).pollPairing({
    ...session,
    deviceCredential: session.desktopPushToken,
  } as AiraDesktopPairingSession);
  if (result.status === 'confirmed') {
    return {
      status: 'confirmed',
      confirmedAt: result.confirmedAt,
    };
  }
  return {
    status: result.status,
    expiresAt: result.expiresAt,
    pollIntervalMs: result.pollIntervalMs,
  };
}

export async function disconnectAiraDesktopLogin(): Promise<void> {
  await disconnectAiraDesktopDevice();
}
