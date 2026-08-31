import {
  DownloadV2Action,
  DownloadV2ActionPermissionSet,
  DownloadV2Status,
  getDownloadV2ActionPermissionSet,
  isDownloadV2ActiveStatus,
  isDownloadV2TerminalStatus
} from './DownloadV2Types';

export type DownloadV2Event =
  'create' |
  'await_confirmation' |
  'confirm' |
  'queue' |
  'start' |
  'pause' |
  'resume' |
  'finish' |
  'fail' |
  'cancel' |
  'retry' |
  'remove' |
  'hydrate';

export type DownloadV2Phase =
  'created' |
  'confirmation' |
  'queued' |
  'running' |
  'paused' |
  'terminal';

export type DownloadV2TransitionReason =
  'applied' |
  'noop' |
  'invalid_transition';

export interface DownloadV2StateSnapshot {
  status: DownloadV2Status;
  phase: DownloadV2Phase;
  isActive: boolean;
  isTerminal: boolean;
  allowedActions: DownloadV2Action[];
}

export interface DownloadV2StateTransition {
  previousStatus: DownloadV2Status;
  event: DownloadV2Event;
  nextStatus: DownloadV2Status;
  changed: boolean;
  valid: boolean;
  reason: DownloadV2TransitionReason;
  permissionSet: DownloadV2ActionPermissionSet;
}

export function resolveDownloadV2StateSnapshot(status: DownloadV2Status): DownloadV2StateSnapshot {
  const permissionSet = getDownloadV2ActionPermissionSet(status);
  return {
    status: status,
    phase: resolveDownloadV2Phase(status),
    isActive: isDownloadV2ActiveStatus(status),
    isTerminal: isDownloadV2TerminalStatus(status),
    allowedActions: permissionSet.allowedActions
  };
}

export function transitionDownloadV2Status(
  currentStatus: DownloadV2Status,
  event: DownloadV2Event
): DownloadV2StateTransition {
  const nextStatus = computeNextDownloadV2Status(currentStatus, event);
  const valid = nextStatus !== undefined;
  const resolvedStatus = nextStatus ?? currentStatus;
  return {
    previousStatus: currentStatus,
    event: event,
    nextStatus: resolvedStatus,
    changed: currentStatus !== resolvedStatus,
    valid: valid,
    reason: valid ? (currentStatus === resolvedStatus ? 'noop' : 'applied') : 'invalid_transition',
    permissionSet: getDownloadV2ActionPermissionSet(resolvedStatus)
  };
}

function resolveDownloadV2Phase(status: DownloadV2Status): DownloadV2Phase {
  if (status === 'created') {
    return 'created';
  }
  if (status === 'awaiting_confirmation') {
    return 'confirmation';
  }
  if (status === 'queued') {
    return 'queued';
  }
  if (status === 'running') {
    return 'running';
  }
  if (status === 'paused') {
    return 'paused';
  }
  return 'terminal';
}

function computeNextDownloadV2Status(
  currentStatus: DownloadV2Status,
  event: DownloadV2Event
): DownloadV2Status | undefined {
  switch (currentStatus) {
    case 'created':
      return computeCreatedTransition(event);
    case 'awaiting_confirmation':
      return computeAwaitingConfirmationTransition(event);
    case 'queued':
      return computeQueuedTransition(event);
    case 'running':
      return computeRunningTransition(event);
    case 'paused':
      return computePausedTransition(event);
    case 'completed':
      return computeCompletedTransition(event);
    case 'failed':
      return computeFailedTransition(event);
    case 'canceled':
      return computeCanceledTransition(event);
    case 'removed':
      return computeRemovedTransition(event);
    default:
      return undefined;
  }
}

function computeCreatedTransition(event: DownloadV2Event): DownloadV2Status | undefined {
  switch (event) {
    case 'create':
    case 'hydrate':
      return 'created';
    case 'await_confirmation':
      return 'awaiting_confirmation';
    case 'queue':
      return 'queued';
    case 'remove':
      return 'removed';
    default:
      return undefined;
  }
}

function computeAwaitingConfirmationTransition(event: DownloadV2Event): DownloadV2Status | undefined {
  switch (event) {
    case 'await_confirmation':
    case 'hydrate':
      return 'awaiting_confirmation';
    case 'confirm':
    case 'queue':
      return 'queued';
    case 'cancel':
      return 'canceled';
    case 'remove':
      return 'removed';
    default:
      return undefined;
  }
}

function computeQueuedTransition(event: DownloadV2Event): DownloadV2Status | undefined {
  switch (event) {
    case 'queue':
    case 'hydrate':
      return 'queued';
    case 'start':
      return 'running';
    case 'cancel':
      return 'canceled';
    case 'remove':
      return 'removed';
    default:
      return undefined;
  }
}

function computeRunningTransition(event: DownloadV2Event): DownloadV2Status | undefined {
  switch (event) {
    case 'start':
    case 'resume':
    case 'hydrate':
      return 'running';
    case 'pause':
      return 'paused';
    case 'finish':
      return 'completed';
    case 'fail':
      return 'failed';
    case 'cancel':
      return 'canceled';
    default:
      return undefined;
  }
}

function computePausedTransition(event: DownloadV2Event): DownloadV2Status | undefined {
  switch (event) {
    case 'pause':
    case 'hydrate':
      return 'paused';
    case 'resume':
    case 'start':
      return 'running';
    case 'cancel':
      return 'canceled';
    case 'fail':
      return 'failed';
    case 'remove':
      return 'removed';
    default:
      return undefined;
  }
}

function computeCompletedTransition(event: DownloadV2Event): DownloadV2Status | undefined {
  switch (event) {
    case 'finish':
    case 'hydrate':
      return 'completed';
    case 'remove':
      return 'removed';
    default:
      return undefined;
  }
}

function computeFailedTransition(event: DownloadV2Event): DownloadV2Status | undefined {
  switch (event) {
    case 'fail':
    case 'hydrate':
      return 'failed';
    case 'retry':
      return 'queued';
    case 'remove':
      return 'removed';
    default:
      return undefined;
  }
}

function computeCanceledTransition(event: DownloadV2Event): DownloadV2Status | undefined {
  switch (event) {
    case 'cancel':
    case 'hydrate':
      return 'canceled';
    case 'remove':
      return 'removed';
    default:
      return undefined;
  }
}

function computeRemovedTransition(event: DownloadV2Event): DownloadV2Status | undefined {
  switch (event) {
    case 'remove':
    case 'hydrate':
      return 'removed';
    default:
      return undefined;
  }
}
