export type BrowserRecentActionKind = 'click' | 'operate' | 'create';

export interface BrowserRecentActionSnapshot {
  recentClickTime: number;
  recentOperateTime: number;
  recentCreateTime: number;
  windowMs: number;
}

const DEFAULT_RECENT_ACTION_WINDOW_MS: number = 3000;

export class BrowserRecentActionManager {
  private recentClickTime: number = 0;
  private recentOperateTime: number = 0;
  private recentCreateTime: number = 0;
  private readonly windowMs: number;

  constructor(windowMs: number = DEFAULT_RECENT_ACTION_WINDOW_MS) {
    this.windowMs = Math.max(0, windowMs);
  }

  recordClick(now: number = Date.now()): void {
    this.recentClickTime = now;
  }

  recordOperate(now: number = Date.now()): void {
    this.recentOperateTime = now;
  }

  recordCreate(now: number = Date.now()): void {
    this.recentCreateTime = now;
  }

  record(kind: BrowserRecentActionKind, now: number = Date.now()): void {
    if (kind === 'click') {
      this.recordClick(now);
      return;
    }
    if (kind === 'operate') {
      this.recordOperate(now);
      return;
    }
    this.recordCreate(now);
  }

  isRecentAction(now: number = Date.now()): boolean {
    return this.isRecentTime(this.recentClickTime, now) ||
      this.isRecentTime(this.recentOperateTime, now) ||
      this.isRecentTime(this.recentCreateTime, now);
  }

  reset(): void {
    this.recentClickTime = 0;
    this.recentOperateTime = 0;
    this.recentCreateTime = 0;
  }

  snapshot(): BrowserRecentActionSnapshot {
    return {
      recentClickTime: this.recentClickTime,
      recentOperateTime: this.recentOperateTime,
      recentCreateTime: this.recentCreateTime,
      windowMs: this.windowMs
    };
  }

  private isRecentTime(timestamp: number, now: number): boolean {
    return timestamp > 0 && now >= timestamp && now - timestamp <= this.windowMs;
  }
}
