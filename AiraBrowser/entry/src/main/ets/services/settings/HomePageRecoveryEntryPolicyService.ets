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

const HOME_PAGE_RECOVERY_ENTRY_REQUIRED_MESSAGE: string =
  '收藏、最近关闭和主页设置按钮至少保留一项';

export class HomePageRecoveryEntryPolicyService {
  resolveChange(
    entry: HomePageRecoveryEntry,
    visible: boolean,
    current: HomePageRecoveryEntryVisibility
  ): HomePageRecoveryEntryDecision {
    if (visible) {
      return {
        allowed: true,
        message: ''
      };
    }
    const remainingEntryCount = (entry === 'favorites' ? 0 : (current.showFavorites ? 1 : 0)) +
      (entry === 'recently_closed' ? 0 : (current.showRecentlyClosed ? 1 : 0)) +
      (entry === 'settings_button' ? 0 : (current.showSettingsButton ? 1 : 0));
    return {
      allowed: remainingEntryCount > 0,
      message: remainingEntryCount > 0 ? '' : HOME_PAGE_RECOVERY_ENTRY_REQUIRED_MESSAGE
    };
  }

  resolveSettingsButtonVisibility(current: HomePageRecoveryEntryVisibility): boolean {
    if (current.showFavorites || current.showRecentlyClosed || current.showSettingsButton) {
      return current.showSettingsButton;
    }
    return true;
  }
}
