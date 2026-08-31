import { HomeSearchPanelDetent } from './HomeSearchPanelDetentViewModel';

export type BrowserBottomAddressPanelBackAction =
  'release_address_focus' |
  'collapse_to_low' |
  'pass_through';

export interface BrowserBottomAddressPanelBackRequest {
  visible: boolean;
  addressFocused: boolean;
  panelDetent: HomeSearchPanelDetent;
}

export class BrowserBottomAddressPanelBackController {
  resolveBackAction(request: BrowserBottomAddressPanelBackRequest): BrowserBottomAddressPanelBackAction {
    if (!request.visible) {
      return 'pass_through';
    }
    if (request.panelDetent === 'middle') {
      return 'collapse_to_low';
    }
    if (request.addressFocused) {
      return 'release_address_focus';
    }
    return 'pass_through';
  }
}
