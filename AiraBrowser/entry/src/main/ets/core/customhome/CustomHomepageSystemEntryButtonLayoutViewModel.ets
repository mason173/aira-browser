interface CustomHomepageSystemEntryButtonLayoutInput {
  viewportWidth: number;
  viewportHeight: number;
}

interface CustomHomepageSystemEntryButtonLayoutState {
  left: number;
  top: number;
}

export const CUSTOM_HOMEPAGE_SYSTEM_ENTRY_HIT_SIZE: number = 72;

export class CustomHomepageSystemEntryButtonLayoutViewModel {
  buildLayout(input: CustomHomepageSystemEntryButtonLayoutInput): CustomHomepageSystemEntryButtonLayoutState {
    return {
      left: Math.max(0, input.viewportWidth - CUSTOM_HOMEPAGE_SYSTEM_ENTRY_HIT_SIZE),
      top: Math.max(0, input.viewportHeight - CUSTOM_HOMEPAGE_SYSTEM_ENTRY_HIT_SIZE)
    };
  }
}
