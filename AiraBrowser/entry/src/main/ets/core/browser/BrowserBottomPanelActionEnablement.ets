import { BrowserBottomPanelActionId } from './BrowserBottomPanelActionCatalog';

export interface BrowserBottomPanelActionEnablement {
  enabled: boolean;
  disabledMessage: string;
}

export type BrowserBottomPanelActionEnablementById =
  Record<string, BrowserBottomPanelActionEnablement | undefined>;

export function resolveBrowserBottomPanelActionEnablement(
  enablementById: BrowserBottomPanelActionEnablementById,
  actionId: BrowserBottomPanelActionId,
  fallbackEnabled: boolean = true,
  fallbackDisabledMessage: string = ''
): BrowserBottomPanelActionEnablement {
  return enablementById[actionId] ?? {
    enabled: fallbackEnabled,
    disabledMessage: fallbackDisabledMessage
  };
}
