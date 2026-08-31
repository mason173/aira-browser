import { BrowserDataScope, BrowserSessionPrivacyMode } from '../../common/models/BrowserModels';
import { BrowserTabState } from '../tabs/TabManager';
import { BrowserProfileBoundaryService } from './BrowserProfileBoundaryService';

export interface BrowserOpenTabsButtonCountInput {
  tabs: BrowserTabState[];
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
}

export class BrowserOpenTabsButtonViewModel {
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();

  resolveTabCount(input: BrowserOpenTabsButtonCountInput): number {
    const currentIsPrivateBoundary = this.profileBoundaryService.isSessionEphemeral(
      this.profileBoundaryService.buildBoundaryInput('profile-main', input.privacyMode, input.dataScope)
    );
    return input.tabs.filter((tab: BrowserTabState) => {
      if (tab.isHome) {
        return false;
      }
      return this.isTabSessionEphemeral(tab) === currentIsPrivateBoundary;
    }).length;
  }

  private isTabSessionEphemeral(tab: BrowserTabState): boolean {
    return this.profileBoundaryService.isSessionEphemeral(
      this.profileBoundaryService.buildBoundaryInput(tab.profileId, tab.privacyMode, tab.dataScope)
    );
  }
}
