import {
  CustomHomepageChoiceViewState
} from './CustomHomepageSettingsViewModel';
import { BrowserDeviceFormFactor } from '../browser/BrowserDeviceFormFactorCoordinator';

export const CUSTOM_HOMEPAGE_RETURN_HOME_SOURCE: string = 'custom_homepage_settings';
export const CUSTOM_HOMEPAGE_RETURN_HOME_VALUE: string = '1';

interface CustomHomepageReturnHomeRouteParams {
  dataScope: string;
  privacyMode: string;
  boundarySource: string;
  returnHome: string;
  returnHomeToken: string;
}

export interface CustomHomepagePreviewState {
  choiceId: string;
  closing: boolean;
  closeTrigger: number;
}

export type CustomHomepagePreviewOrientation = 'portrait' | 'landscape' | 'square';

export interface CustomHomepagePreviewLayoutInput {
  formFactor: BrowserDeviceFormFactor;
  viewportWidth: number;
  viewportHeight: number;
  availableWidth: number;
}

export interface CustomHomepagePreviewLayoutState {
  cardWidth: number;
  cardHeight: number;
  listHeight: number;
  cardGap: number;
  cardRadius: number;
  sidePeek: number;
  orientation: CustomHomepagePreviewOrientation;
}

export interface CustomHomepageCarouselLayoutInput {
  viewportWidth: number;
  viewportHeight: number;
  availableWidth: number;
  availableHeight: number;
}

const CUSTOM_HOMEPAGE_PHONE_CARD_WIDTH: number = 172;
const CUSTOM_HOMEPAGE_PHONE_CARD_HEIGHT: number = 340;
const CUSTOM_HOMEPAGE_PREVIEW_TITLE_HEIGHT: number = 24;
const CUSTOM_HOMEPAGE_PREVIEW_TITLE_GAP: number = 8;
const CUSTOM_HOMEPAGE_PREVIEW_CARD_GAP: number = 18;
const CUSTOM_HOMEPAGE_PREVIEW_CARD_RADIUS: number = 18;

export class CustomHomepagePreviewViewModel {
  buildLayoutState(input: CustomHomepagePreviewLayoutInput): CustomHomepagePreviewLayoutState {
    const orientation = this.resolveOrientation(input.viewportWidth, input.viewportHeight);
    const formFactor = this.resolveLayoutFormFactor(input.formFactor, input.viewportWidth);
    let cardWidth = CUSTOM_HOMEPAGE_PHONE_CARD_WIDTH;
    let cardHeight = CUSTOM_HOMEPAGE_PHONE_CARD_HEIGHT;
    if (formFactor === 'tablet') {
      if (orientation === 'landscape') {
        cardWidth = this.resolveResponsiveWidth(input.availableWidth, 280, 360, 0.52);
        cardHeight = Math.round(cardWidth * 2 / 3);
      } else {
        cardWidth = this.resolveResponsiveWidth(input.availableWidth, 220, 288, 0.68);
        cardHeight = Math.round(cardWidth * 4 / 3);
      }
    } else if (formFactor === 'two_in_one' || formFactor === 'pc') {
      cardWidth = this.resolveResponsiveWidth(input.availableWidth, 300, 420, 0.56);
      cardHeight = Math.round(cardWidth * 9 / 16);
    } else {
      cardWidth = Math.min(CUSTOM_HOMEPAGE_PHONE_CARD_WIDTH, Math.max(1, input.availableWidth - 4));
      cardHeight = Math.round(cardWidth * CUSTOM_HOMEPAGE_PHONE_CARD_HEIGHT /
        CUSTOM_HOMEPAGE_PHONE_CARD_WIDTH);
    }
    return {
      cardWidth: cardWidth,
      cardHeight: cardHeight,
      listHeight: cardHeight + CUSTOM_HOMEPAGE_PREVIEW_TITLE_HEIGHT + CUSTOM_HOMEPAGE_PREVIEW_TITLE_GAP,
      cardGap: CUSTOM_HOMEPAGE_PREVIEW_CARD_GAP,
      cardRadius: CUSTOM_HOMEPAGE_PREVIEW_CARD_RADIUS,
      sidePeek: 0,
      orientation: orientation
    };
  }

  /**
   * Size one carousel card from the device aspect ratio, then fit it into the picker
   * so the neighboring card can still peek in from the side.
   */
  buildCarouselLayoutState(input: CustomHomepageCarouselLayoutInput): CustomHomepagePreviewLayoutState {
    const viewportWidth = Math.max(1, input.viewportWidth);
    const viewportHeight = Math.max(1, input.viewportHeight);
    const availableWidth = Math.max(1, input.availableWidth);
    const availableHeight = Math.max(1, input.availableHeight);
    const aspect = viewportWidth / viewportHeight;
    const sidePeek = Math.max(16, Math.round(availableWidth * 0.075));
    const cardGap = 16;
    const titleBlock = 36;
    const actionBlock = 100;
    const contentHeight = Math.max(180, availableHeight - titleBlock - actionBlock);
    const maxWidth = Math.max(120, availableWidth - sidePeek * 2);
    let cardWidth = maxWidth;
    let cardHeight = cardWidth / aspect;
    if (cardHeight > contentHeight) {
      cardHeight = contentHeight;
      cardWidth = cardHeight * aspect;
    }
    cardWidth = Math.max(120, Math.round(cardWidth));
    cardHeight = Math.max(160, Math.round(cardWidth / aspect));
    if (cardHeight > contentHeight) {
      cardHeight = Math.max(160, Math.round(contentHeight));
      cardWidth = Math.max(120, Math.round(cardHeight * aspect));
    }
    const radius = Math.max(16, Math.min(32, Math.round(cardWidth * 0.08)));
    return {
      cardWidth: cardWidth,
      cardHeight: cardHeight,
      listHeight: cardHeight,
      cardGap: cardGap,
      cardRadius: radius,
      sidePeek: sidePeek,
      orientation: this.resolveOrientation(viewportWidth, viewportHeight)
    };
  }

  buildInitialState(): CustomHomepagePreviewState {
    return {
      choiceId: '',
      closing: false,
      closeTrigger: 0
    };
  }

  openPreview(
    current: CustomHomepagePreviewState,
    choice: CustomHomepageChoiceViewState,
    busy: boolean
  ): CustomHomepagePreviewState {
    if (busy) {
      return current;
    }
    return {
      choiceId: choice.id,
      closing: false,
      closeTrigger: current.closeTrigger
    };
  }

  requestClose(current: CustomHomepagePreviewState): CustomHomepagePreviewState {
    if (current.choiceId.length <= 0 || current.closing) {
      return current;
    }
    return {
      choiceId: current.choiceId,
      closing: true,
      closeTrigger: current.closeTrigger + 1
    };
  }

  finishClose(current: CustomHomepagePreviewState): CustomHomepagePreviewState {
    return {
      choiceId: '',
      closing: false,
      closeTrigger: current.closeTrigger
    };
  }

  resolvePreviewChoiceIndex(choices: CustomHomepageChoiceViewState[], choiceId: string): number {
    for (let index = 0; index < choices.length; index++) {
      if (choices[index].id === choiceId) {
        return index;
      }
    }
    return -1;
  }

  buildReturnHomeRouteParams(): CustomHomepageReturnHomeRouteParams {
    return {
      dataScope: '',
      privacyMode: '',
      boundarySource: CUSTOM_HOMEPAGE_RETURN_HOME_SOURCE,
      returnHome: CUSTOM_HOMEPAGE_RETURN_HOME_VALUE,
      returnHomeToken: `${Date.now()}`
    };
  }

  private resolveLayoutFormFactor(
    formFactor: BrowserDeviceFormFactor,
    viewportWidth: number
  ): BrowserDeviceFormFactor {
    if (formFactor === 'car') {
      return 'phone';
    }
    if (formFactor !== 'unknown') {
      return formFactor;
    }
    if (viewportWidth >= 840) {
      return 'pc';
    }
    if (viewportWidth >= 600) {
      return 'tablet';
    }
    return 'phone';
  }

  private resolveOrientation(width: number, height: number): CustomHomepagePreviewOrientation {
    if (width > height) {
      return 'landscape';
    }
    if (height > width) {
      return 'portrait';
    }
    return 'square';
  }

  private resolveResponsiveWidth(
    availableWidth: number,
    minimumWidth: number,
    maximumWidth: number,
    widthRatio: number
  ): number {
    const boundedAvailableWidth = Math.max(1, availableWidth - 4);
    const preferredWidth = Math.round(boundedAvailableWidth * widthRatio);
    return Math.min(boundedAvailableWidth, Math.max(minimumWidth, Math.min(maximumWidth, preferredWidth)));
  }
}
