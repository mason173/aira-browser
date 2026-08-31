export interface AiraSyncWorkThrottleClock {
  sleep(delayMs: number): Promise<void>;
}

export interface AiraSyncCooperativeThrottle {
  afterBatchItem(processedCount: number): Promise<void>;
  afterStage(): Promise<void>;
}

export interface AiraSyncWorkThrottleOptions {
  batchSize: number;
  batchPauseMs: number;
  stagePauseMs: number;
}

const DEFAULT_BATCH_SIZE: number = 250;
const DEFAULT_BATCH_PAUSE_MS: number = 0;
const DEFAULT_STAGE_PAUSE_MS: number = 4;

class DefaultAiraSyncWorkThrottleClock implements AiraSyncWorkThrottleClock {
  sleep(delayMs: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), Math.max(0, delayMs));
    });
  }
}

export class AiraSyncWorkThrottleService implements AiraSyncCooperativeThrottle {
  private clock: AiraSyncWorkThrottleClock;
  private options: AiraSyncWorkThrottleOptions;

  constructor(clock?: AiraSyncWorkThrottleClock, options?: Partial<AiraSyncWorkThrottleOptions>) {
    this.clock = clock ?? new DefaultAiraSyncWorkThrottleClock();
    this.options = {
      batchSize: options?.batchSize ?? DEFAULT_BATCH_SIZE,
      batchPauseMs: options?.batchPauseMs ?? DEFAULT_BATCH_PAUSE_MS,
      stagePauseMs: options?.stagePauseMs ?? DEFAULT_STAGE_PAUSE_MS
    };
  }

  async afterBatchItem(processedCount: number): Promise<void> {
    if (processedCount <= 0 || processedCount % this.resolveBatchSize() !== 0) {
      return;
    }
    await this.pause(this.options.batchPauseMs);
  }

  async afterStage(): Promise<void> {
    await this.pause(this.options.stagePauseMs);
  }

  async beforeMainThreadWrite(): Promise<void> {
    await this.pause(this.options.stagePauseMs);
  }

  private resolveBatchSize(): number {
    return Math.max(1, this.options.batchSize);
  }

  private async pause(delayMs: number): Promise<void> {
    await this.clock.sleep(Math.max(0, delayMs));
  }
}
