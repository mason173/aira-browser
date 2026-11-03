import type { HistoryTimelinePage } from './HistorySyncModels';

export const HISTORY_MESSAGE_TYPE = 'AIRA_HISTORY_SYNC_V1';
export const HISTORY_REVISION_STORAGE_KEY = 'aira_history_sync_v1_revision';

export type HistoryCapabilityStatus =
  | 'ready'
  | 'login-required'
  | 'pro-required'
  | 'temporarily-unavailable';

export type HistoryRuntimeMessage = {
  type: typeof HISTORY_MESSAGE_TYPE;
  action: 'open' | 'list' | 'sync' | 'delete' | 'clear';
  query?: string;
  deviceId?: string;
  offset?: number;
  limit?: number;
  visitId?: string;
  /** Desktop history surfaces also read all browser-native history, outside sync retention. */
  includeNative?: boolean;
};

export type HistoryRuntimeResponse = {
  success: boolean;
  status: HistoryCapabilityStatus;
  error?: string;
  page?: HistoryTimelinePage;
};

export function sendHistoryRuntimeMessage(
  message: Omit<HistoryRuntimeMessage, 'type'>,
): Promise<HistoryRuntimeResponse> {
  const runtime = globalThis.chrome?.runtime;
  if (!runtime?.sendMessage) {
    return Promise.resolve({
      success: false,
      status: 'temporarily-unavailable',
      error: 'Aira extension runtime is unavailable.',
    });
  }
  return runtime.sendMessage({ type: HISTORY_MESSAGE_TYPE, ...message }) as Promise<HistoryRuntimeResponse>;
}
