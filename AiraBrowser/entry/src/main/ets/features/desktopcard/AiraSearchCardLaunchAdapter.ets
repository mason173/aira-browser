import { Want } from '@kit.AbilityKit';

const FORM_LINK_PARAMS_KEY: string = 'params';
const APP_SHORTCUT_KEY: string = 'aira.appShortcut';
const SEARCH_INVOCATION_SOURCE_KEY: string = 'aira.searchInvocationSource';
const SEARCH_SHORTCUT_TARGET: string = 'search';
const DESKTOP_CARD_SEARCH_SOURCE: string = 'desktop_card';

export function normalizeAiraSearchCardWant(want: Want): Want {
  const parameters = want.parameters as Record<string, Object> | undefined;
  if (parameters === undefined) {
    return want;
  }
  const rawFormLinkParameters = parameters[FORM_LINK_PARAMS_KEY];
  if (typeof rawFormLinkParameters !== 'string' || rawFormLinkParameters.length === 0) {
    return want;
  }
  try {
    const formLinkParameters = JSON.parse(rawFormLinkParameters) as Record<string, Object>;
    const shortcutTarget = String(formLinkParameters[APP_SHORTCUT_KEY] ?? '').trim();
    if (shortcutTarget === SEARCH_SHORTCUT_TARGET) {
      parameters[APP_SHORTCUT_KEY] = SEARCH_SHORTCUT_TARGET;
      parameters[SEARCH_INVOCATION_SOURCE_KEY] = DESKTOP_CARD_SEARCH_SOURCE;
    }
  } catch (_error) {
    return want;
  }
  return want;
}
