import { BrowserPreferencesChangeScope } from '../../data/preferences/PreferencesRepository';

export function isBrowserThemePresentationScope(scope: BrowserPreferencesChangeScope): boolean {
  return scope === 'theme_mode' || scope === 'appearance' || scope === 'general';
}
