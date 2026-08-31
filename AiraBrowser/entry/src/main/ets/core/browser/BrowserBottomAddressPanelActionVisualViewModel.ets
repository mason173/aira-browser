import { BrowserBottomAddressPanelAction } from './BrowserBottomAddressPanelViewModel';

export interface BrowserBottomAddressPanelActionVisualInput {
  defaultSelectedBackgroundColor: ResourceColor;
  appProxyActiveBackgroundColor: ResourceColor;
  selectedForegroundColor: ResourceColor;
}

export interface BrowserBottomAddressPanelActionVisualState {
  backgroundColor?: ResourceColor;
  imageFillColor?: ResourceColor;
}

export class BrowserBottomAddressPanelActionVisualViewModel {
  buildState(
    action: BrowserBottomAddressPanelAction,
    input: BrowserBottomAddressPanelActionVisualInput
  ): BrowserBottomAddressPanelActionVisualState {
    if (action.selected !== true) {
      return {};
    }
    if (action.id === 'appProxySettings') {
      return {
        backgroundColor: input.appProxyActiveBackgroundColor,
        imageFillColor: input.selectedForegroundColor
      };
    }
    return {
      backgroundColor: input.defaultSelectedBackgroundColor,
      imageFillColor: input.selectedForegroundColor
    };
  }
}
