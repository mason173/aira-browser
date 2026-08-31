import { BrowserResolvedThemeMode } from '../../common/models/BrowserModels';

const BROWSER_OPERATIONAL_ICON_LIGHT: string = '#4D4D4D';
const BROWSER_OPERATIONAL_ICON_DARK: string = '#F7F8FA';

export function resolveBrowserOperationalIconColor(
  mode: BrowserResolvedThemeMode | string
): ResourceColor {
  return `${mode}` === 'dark' ? BROWSER_OPERATIONAL_ICON_DARK : BROWSER_OPERATIONAL_ICON_LIGHT;
}
