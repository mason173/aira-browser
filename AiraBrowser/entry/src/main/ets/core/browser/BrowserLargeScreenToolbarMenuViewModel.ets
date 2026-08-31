import {
  BrowserBottomAddressPanelAction,
  BrowserBottomAddressPanelActionId,
  BrowserBottomAddressPanelViewModel
} from './BrowserBottomAddressPanelViewModel';
import { BrowserBottomPanelActionSnapshot } from './BrowserBottomPanelActionPresentationCoordinator';
import { BrowserLargeScreenInputProfile } from './BrowserLargeScreenTabStripViewModel';

/** Projects the existing phone-toolbar action snapshot into one desktop menu. */
export class BrowserLargeScreenToolbarMenuViewModel {
  private readonly bottomPanelViewModel: BrowserBottomAddressPanelViewModel =
    new BrowserBottomAddressPanelViewModel();

  resolveActions(
    snapshot: BrowserBottomPanelActionSnapshot | undefined,
    inputProfile: BrowserLargeScreenInputProfile,
    webZoomAvailable: boolean = false
  ): BrowserBottomAddressPanelAction[] {
    if (snapshot === undefined) {
      return [];
    }
    const primaryActions = snapshot.primaryActionOverrides ??
      this.bottomPanelViewModel.buildPrimaryActions(snapshot.actionInput, 8);
    const secondaryActions = snapshot.secondaryActionOverrides ??
      this.bottomPanelViewModel.buildSecondaryActions(snapshot.actionInput, primaryActions);
    const actions = this.mergeUniqueActions(primaryActions, secondaryActions);
    if (inputProfile === 'touch') {
      return actions;
    }
    return actions
      .filter((action: BrowserBottomAddressPanelAction): boolean =>
        this.isAvailableForPointerShell(action.id))
      .map((action: BrowserBottomAddressPanelAction): BrowserBottomAddressPanelAction =>
        this.projectPointerAction(action, webZoomAvailable));
  }

  private mergeUniqueActions(
    primaryActions: BrowserBottomAddressPanelAction[],
    secondaryActions: BrowserBottomAddressPanelAction[]
  ): BrowserBottomAddressPanelAction[] {
    const result: BrowserBottomAddressPanelAction[] = [];
    primaryActions.concat(secondaryActions).forEach((action: BrowserBottomAddressPanelAction): void => {
      if (!result.some((candidate: BrowserBottomAddressPanelAction): boolean => candidate.id === action.id)) {
        result.push(action);
      }
    });
    return result;
  }

  private isAvailableForPointerShell(actionId: BrowserBottomAddressPanelActionId): boolean {
    return actionId !== 'bookmark' &&
      actionId !== 'home' &&
      actionId !== 'siteInfo' &&
      actionId !== 'fullScreenMode' &&
      actionId !== 'sendToDesktop' &&
      actionId !== 'screenOrientation';
  }

  private projectPointerAction(
    action: BrowserBottomAddressPanelAction,
    webZoomAvailable: boolean
  ): BrowserBottomAddressPanelAction {
    if (action.id !== 'textZoom') {
      return action;
    }
    return {
      id: action.id,
      title: '网页缩放',
      trailingText: action.trailingText,
      icon: action.icon,
      imageIcon: action.imageIcon,
      airaIconId: action.airaIconId,
      enabled: webZoomAvailable,
      disabledMessage: webZoomAvailable ? '' : '当前页面暂不可缩放',
      selected: action.selected,
      renderVersion: action.renderVersion
    };
  }
}
