import { AdBlockDailyProtectionActivity } from '../../common/models/BrowserModels';

const WEEKDAY_LABELS: string[] = ['日', '一', '二', '三', '四', '五', '六'];

export interface BrowserPrivacyProtectionOverviewInput {
  activities: AdBlockDailyProtectionActivity[];
  selectedDayIndex: number;
  filterEnabled: boolean;
  enhancedTrackingProtectionEnabled: boolean;
}

export interface BrowserPrivacyProtectionDayState {
  dayStartedAt: number;
  shortLabel: string;
  detailLabel: string;
  requestBlockingCount: number;
  linkCleaningCount: number;
  elementHidingCount: number;
  totalActionCount: number;
  barHeight: number;
}

export interface BrowserPrivacyProtectionOverviewState {
  days: BrowserPrivacyProtectionDayState[];
  selectedDayIndex: number;
  selectedDay: BrowserPrivacyProtectionDayState;
  lastSevenDaysTotalLabel: string;
  filterEnabled: boolean;
  filterStatusLabel: string;
  trackingModeLabel: string;
  detailBreakdownLabel: string;
}

export class BrowserPrivacyProtectionOverviewViewModel {
  buildState(input: BrowserPrivacyProtectionOverviewInput): BrowserPrivacyProtectionOverviewState {
    const rawDays: BrowserPrivacyProtectionDayState[] = input.activities.map(
      (activity: AdBlockDailyProtectionActivity, index: number): BrowserPrivacyProtectionDayState =>
        this.buildDayState(activity, index === input.activities.length - 1)
    );
    const normalizedDays: BrowserPrivacyProtectionDayState[] = rawDays.length > 0 ? rawDays : [
      this.buildDayState({
        dayStartedAt: Date.now(),
        networkBlockedCount: 0,
        urlParameterRemovedCount: 0,
        cosmeticElementHiddenCount: 0,
        manualElementHiddenCount: 0,
        totalProtectionActionCount: 0
      }, true)
    ];
    let maximumCount: number = 0;
    let lastSevenDaysTotal: number = 0;
    for (let index: number = 0; index < normalizedDays.length; index += 1) {
      maximumCount = Math.max(maximumCount, normalizedDays[index].totalActionCount);
      lastSevenDaysTotal += normalizedDays[index].totalActionCount;
    }
    const days: BrowserPrivacyProtectionDayState[] = normalizedDays.map(
      (day: BrowserPrivacyProtectionDayState): BrowserPrivacyProtectionDayState => {
        return {
          dayStartedAt: day.dayStartedAt,
          shortLabel: day.shortLabel,
          detailLabel: day.detailLabel,
          requestBlockingCount: day.requestBlockingCount,
          linkCleaningCount: day.linkCleaningCount,
          elementHidingCount: day.elementHidingCount,
          totalActionCount: day.totalActionCount,
          barHeight: this.resolveBarHeight(day.totalActionCount, maximumCount)
        };
      }
    );
    const selectedDayIndex: number = this.normalizeSelectedDayIndex(input.selectedDayIndex, days.length);
    const selectedDay: BrowserPrivacyProtectionDayState = days[selectedDayIndex];
    return {
      days: days,
      selectedDayIndex: selectedDayIndex,
      selectedDay: selectedDay,
      lastSevenDaysTotalLabel: this.formatCount(lastSevenDaysTotal),
      filterEnabled: input.filterEnabled,
      filterStatusLabel: input.filterEnabled ? '过滤已开启' : '过滤已关闭',
      trackingModeLabel: input.enhancedTrackingProtectionEnabled ? '增强' : '标准',
      detailBreakdownLabel: this.buildBreakdownLabel(selectedDay)
    };
  }

  private buildDayState(
    activity: AdBlockDailyProtectionActivity,
    isToday: boolean
  ): BrowserPrivacyProtectionDayState {
    const requestBlockingCount: number = Math.max(0, Math.floor(activity.networkBlockedCount));
    const linkCleaningCount: number = Math.max(0, Math.floor(activity.urlParameterRemovedCount));
    const elementHidingCount: number = Math.max(
      0,
      Math.floor(activity.cosmeticElementHiddenCount) + Math.floor(activity.manualElementHiddenCount)
    );
    const totalActionCount: number = requestBlockingCount + linkCleaningCount +
      elementHidingCount;
    const date: Date = new Date(activity.dayStartedAt);
    const weekdayLabel: string = WEEKDAY_LABELS[date.getDay()];
    return {
      dayStartedAt: activity.dayStartedAt,
      shortLabel: isToday ? '今' : weekdayLabel,
      detailLabel: isToday ? '今天' : `周${weekdayLabel}`,
      requestBlockingCount: requestBlockingCount,
      linkCleaningCount: linkCleaningCount,
      elementHidingCount: elementHidingCount,
      totalActionCount: totalActionCount,
      barHeight: 4
    };
  }

  private buildBreakdownLabel(day: BrowserPrivacyProtectionDayState): string {
    return `请求 ${this.formatCount(day.requestBlockingCount)}　链接 ${this.formatCount(day.linkCleaningCount)}` +
      `　元素 ${this.formatCount(day.elementHidingCount)}`;
  }

  private resolveBarHeight(value: number, maximumCount: number): number {
    if (value <= 0 || maximumCount <= 0) {
      return 4;
    }
    return Math.max(4, Math.round(value / maximumCount * 88));
  }

  private normalizeSelectedDayIndex(index: number, dayCount: number): number {
    if (index < 0) {
      return 0;
    }
    if (index >= dayCount) {
      return dayCount - 1;
    }
    return Math.floor(index);
  }

  private formatCount(value: number): string {
    const normalized: number = Math.max(0, Math.floor(value));
    if (normalized >= 100000000) {
      return `${Math.floor(normalized / 100000000)}亿`;
    }
    if (normalized >= 10000) {
      const whole: number = Math.floor(normalized / 10000);
      const decimal: number = Math.floor((normalized % 10000) / 1000);
      return decimal > 0 ? `${whole}.${decimal}万` : `${whole}万`;
    }
    return `${normalized}`;
  }
}
