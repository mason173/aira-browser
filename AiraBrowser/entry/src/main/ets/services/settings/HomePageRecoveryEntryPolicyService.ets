export type HomePageRecoveryEntry = 'favorites' | 'recently_closed' | 'settings_button';

export interface HomePageRecoveryEntryVisibility {
  showFavorites: boolean;
  showRecentlyClosed: boolean;
  showSettingsButton: boolean;
}

export interface HomePageRecoveryEntryDecision {
  allowed: boolean;
  message: string;
}

const CLASSIC_HOME_PAGE_RECOVERY_ENTRIES: HomePageRecoveryEntry[] = [
  'favorites',
  'recently_closed',
  'settings_button'
];
const HOME_PAGE_RECOVERY_ENTRY_REQUIRED_MESSAGE: string =
  '收藏、最近关闭和主页设置按钮至少保留一项';
const CENTERED_HOME_PAGE_RECOVERY_ENTRY_REQUIRED_MESSAGE: string =
  '收藏和主页设置按钮至少保留一项';

export class HomePageRecoveryEntryPolicyService {
  resolveChange(
    entry: HomePageRecoveryEntry,
    visible: boolean,
    current: HomePageRecoveryEntryVisibility,
    activeEntries?: HomePageRecoveryEntry[]
  ): HomePageRecoveryEntryDecision {
    const entries = activeEntries ?? CLASSIC_HOME_PAGE_RECOVERY_ENTRIES;
    if (visible || entries.indexOf(entry) < 0) {
      return {
        allowed: true,
        message: ''
      };
    }
    const remainingEntryCount = this.countRemainingEntries(entry, current, entries);
    return {
      allowed: remainingEntryCount > 0,
      message: remainingEntryCount > 0 ? '' : this.resolveBlockedMessage(entries)
    };
  }

  resolveSettingsButtonVisibility(
    current: HomePageRecoveryEntryVisibility,
    activeEntries?: HomePageRecoveryEntry[]
  ): boolean {
    const entries = activeEntries ?? CLASSIC_HOME_PAGE_RECOVERY_ENTRIES;
    if (this.hasVisibleEntry(current, entries)) {
      return current.showSettingsButton;
    }
    return entries.indexOf('settings_button') >= 0 ? true : current.showSettingsButton;
  }

  private countRemainingEntries(
    entry: HomePageRecoveryEntry,
    current: HomePageRecoveryEntryVisibility,
    entries: HomePageRecoveryEntry[]
  ): number {
    return (this.entryRemains('favorites', entry, entries, current.showFavorites) ? 1 : 0) +
      (this.entryRemains('recently_closed', entry, entries, current.showRecentlyClosed) ? 1 : 0) +
      (this.entryRemains('settings_button', entry, entries, current.showSettingsButton) ? 1 : 0);
  }

  private entryRemains(
    candidate: HomePageRecoveryEntry,
    changing: HomePageRecoveryEntry,
    entries: HomePageRecoveryEntry[],
    visible: boolean
  ): boolean {
    return candidate !== changing && entries.indexOf(candidate) >= 0 && visible;
  }

  private hasVisibleEntry(
    current: HomePageRecoveryEntryVisibility,
    entries: HomePageRecoveryEntry[]
  ): boolean {
    return (entries.indexOf('favorites') >= 0 && current.showFavorites) ||
      (entries.indexOf('recently_closed') >= 0 && current.showRecentlyClosed) ||
      (entries.indexOf('settings_button') >= 0 && current.showSettingsButton);
  }

  private resolveBlockedMessage(entries: HomePageRecoveryEntry[]): string {
    if (entries.indexOf('recently_closed') >= 0) {
      return HOME_PAGE_RECOVERY_ENTRY_REQUIRED_MESSAGE;
    }
    return CENTERED_HOME_PAGE_RECOVERY_ENTRY_REQUIRED_MESSAGE;
  }
}
