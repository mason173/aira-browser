export type LeafTabAutoSyncAttemptResult = 'skipped' | 'success' | 'failure';

export type LeafTabAutoSyncRetryDecision =
  | {
      kind: 'idle';
      nextFailureCount: number;
    }
  | {
      kind: 'retry-busy';
      nextFailureCount: number;
    }
  | {
      kind: 'retry-failure';
      nextFailureCount: number;
    };

export const reduceLeafTabAutoSyncRetry = (
  result: LeafTabAutoSyncAttemptResult,
  failureCount: number,
): LeafTabAutoSyncRetryDecision => {
  if (result === 'success') {
    return {
      kind: 'idle',
      nextFailureCount: 0,
    };
  }

  if (result === 'skipped') {
    return {
      kind: 'retry-busy',
      nextFailureCount: failureCount,
    };
  }

  return {
    kind: 'retry-failure',
    nextFailureCount: failureCount + 1,
  };
};

export const normalizeLeafTabAutoSyncAttemptResult = (
  result: boolean | null,
): LeafTabAutoSyncAttemptResult => {
  if (result === true) return 'success';
  if (result === null) return 'skipped';
  return 'failure';
};
