import type { SyncConflictPolicy } from '@/sync/core';

export type WebdavConfig = {
  url: string;
  username: string;
  password: string;
  syncOptions?: {
    enabled?: boolean;
    syncBySchedule: boolean;
    syncIntervalMinutes: number;
    syncConflictPolicy: SyncConflictPolicy;
  };
};
