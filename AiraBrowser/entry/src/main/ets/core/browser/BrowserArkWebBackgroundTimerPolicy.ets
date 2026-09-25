export type ArkWebBackgroundTimerEvent =
  'process_background' |
  'process_foreground' |
  'hold' |
  'release';

export type ArkWebBackgroundTimerCommand = 'pause' | 'resume' | 'none';

export interface ArkWebBackgroundTimerPlan {
  processBackground: boolean;
  holds: string[];
  command: ArkWebBackgroundTimerCommand;
}

export function planArkWebBackgroundTimerCommand(
  processBackground: boolean,
  holds: string[],
  timersPaused: boolean,
  event: ArkWebBackgroundTimerEvent,
  reason: string = ''
): ArkWebBackgroundTimerPlan {
  const normalizedReason = reason.trim();
  if (event === 'process_foreground') {
    return {
      processBackground: false,
      holds: holds.slice(),
      command: timersPaused ? 'resume' : 'none'
    };
  }
  if (event === 'process_background') {
    return {
      processBackground: true,
      holds: holds.slice(),
      command: holds.length > 0 || timersPaused ? 'none' : 'pause'
    };
  }
  if (event === 'hold') {
    const nextHolds = holds.slice();
    if (normalizedReason.length > 0 && nextHolds.indexOf(normalizedReason) < 0) {
      nextHolds.push(normalizedReason);
    }
    return {
      processBackground: processBackground,
      holds: nextHolds,
      command: timersPaused ? 'resume' : 'none'
    };
  }
  const nextHolds = holds.filter((item: string): boolean => item !== normalizedReason);
  return {
    processBackground: processBackground,
    holds: nextHolds,
    command: nextHolds.length === 0 && processBackground && !timersPaused ? 'pause' : 'none'
  };
}
