import { BrowserTabState } from '../../tabs/TabManager';
import { BrowserProfileBoundaryService } from '../BrowserProfileBoundaryService';

export type BrowserTabsOverviewSection = 'tabs' | 'privacy';

export class BrowserTabsOverviewSectionPolicy {
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();

  resolveTabsForSection(
    tabs: BrowserTabState[],
    section: BrowserTabsOverviewSection
  ): BrowserTabState[] {
    return tabs.filter((tab: BrowserTabState) => this.belongsToSection(tab, section));
  }

  resolveSectionForTab(tab: BrowserTabState | undefined): BrowserTabsOverviewSection {
    return this.isPrivateTab(tab) ? 'privacy' : 'tabs';
  }

  isPrivateTab(tab: BrowserTabState | undefined): boolean {
    if (tab === undefined) {
      return false;
    }
    return this.profileBoundaryService.isSessionEphemeral(
      this.profileBoundaryService.buildBoundaryInput(tab.profileId, tab.privacyMode, tab.dataScope)
    );
  }

  belongsToSection(tab: BrowserTabState, section: BrowserTabsOverviewSection): boolean {
    if (tab.isHome) {
      return false;
    }
    return section === 'privacy' ? this.isPrivateTab(tab) : !this.isPrivateTab(tab);
  }
}
