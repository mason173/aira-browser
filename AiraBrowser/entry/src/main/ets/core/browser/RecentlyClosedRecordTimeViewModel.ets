const MINUTE_MS: number = 60 * 1000;
const HOUR_MS: number = 60 * MINUTE_MS;
const DAY_MS: number = 24 * HOUR_MS;

export class RecentlyClosedRecordTimeViewModel {
  formatClosedTime(closedAt: number, now: number = Date.now()): string {
    if (!Number.isFinite(closedAt) || closedAt <= 0) {
      return '刚刚';
    }
    const elapsedMs = Math.max(0, now - closedAt);
    if (elapsedMs < MINUTE_MS) {
      return '刚刚';
    }
    if (elapsedMs < HOUR_MS) {
      return `${Math.max(1, Math.floor(elapsedMs / MINUTE_MS))} 分钟前`;
    }
    if (elapsedMs < DAY_MS && this.isSameDay(closedAt, now)) {
      return `${Math.max(1, Math.floor(elapsedMs / HOUR_MS))} 小时前`;
    }
    const dayDiff = this.resolveCalendarDayDiff(closedAt, now);
    if (dayDiff === 1) {
      return `昨天 ${this.formatClockTime(closedAt)}`;
    }
    if (dayDiff === 2) {
      return `前天 ${this.formatClockTime(closedAt)}`;
    }
    if (this.isSameYear(closedAt, now)) {
      return `${this.formatMonthDay(closedAt)} ${this.formatClockTime(closedAt)}`;
    }
    return `${this.formatYearMonthDay(closedAt)} ${this.formatClockTime(closedAt)}`;
  }

  private resolveCalendarDayDiff(timestamp: number, now: number): number {
    const target = new Date(timestamp);
    const current = new Date(now);
    const targetStart = new Date(target.getFullYear(), target.getMonth(), target.getDate()).getTime();
    const currentStart = new Date(current.getFullYear(), current.getMonth(), current.getDate()).getTime();
    return Math.floor((currentStart - targetStart) / DAY_MS);
  }

  private isSameDay(timestamp: number, now: number): boolean {
    return this.resolveCalendarDayDiff(timestamp, now) === 0;
  }

  private isSameYear(timestamp: number, now: number): boolean {
    return new Date(timestamp).getFullYear() === new Date(now).getFullYear();
  }

  private formatClockTime(timestamp: number): string {
    const date = new Date(timestamp);
    return `${this.pad2(date.getHours())}:${this.pad2(date.getMinutes())}`;
  }

  private formatMonthDay(timestamp: number): string {
    const date = new Date(timestamp);
    return `${this.pad2(date.getMonth() + 1)}-${this.pad2(date.getDate())}`;
  }

  private formatYearMonthDay(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getFullYear()}-${this.formatMonthDay(timestamp)}`;
  }

  private pad2(value: number): string {
    return `${value}`.padStart(2, '0');
  }
}
