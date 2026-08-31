import {
  BrowserResolvedThemeMode,
  BrowserThemePaletteId
} from '../../common/models/BrowserModels';
import { BrowserThemePaletteService } from '../../services/theme/BrowserThemePaletteService';

export interface WebAppearancePolicy {
  darkMode: WebDarkMode;
  forceDarkAccess: boolean;
  backgroundColor: string;
  prefersDarkColorScheme: boolean;
}

const DEFAULT_WEB_APPEARANCE_POLICY: WebAppearancePolicy = {
  darkMode: WebDarkMode.Auto,
  forceDarkAccess: true,
  backgroundColor: '#FFFFFF',
  prefersDarkColorScheme: false
};

export interface WebAppearancePolicyThemeRequest {
  paletteId: BrowserThemePaletteId;
  resolvedThemeMode: BrowserResolvedThemeMode;
  forceDarkWebContentEnabled?: boolean;
}

export function resolveWebAppearancePolicy(
  policy?: WebAppearancePolicy
): WebAppearancePolicy {
  if (policy === undefined) {
    return DEFAULT_WEB_APPEARANCE_POLICY;
  }
  return {
    darkMode: policy.darkMode,
    forceDarkAccess: policy.forceDarkAccess === true,
    backgroundColor: policy.backgroundColor,
    prefersDarkColorScheme: policy.prefersDarkColorScheme === true
  };
}

export function resolveWebAppearancePolicyForTheme(
  request: WebAppearancePolicyThemeRequest,
  paletteService: BrowserThemePaletteService = new BrowserThemePaletteService()
): WebAppearancePolicy {
  const tokens = paletteService.resolveTokens(
    request.paletteId,
    request.resolvedThemeMode
  );
  const shouldForceDarkWeb = request.forceDarkWebContentEnabled !== false && tokens.mode === 'dark';
  return resolveWebAppearancePolicy({
    darkMode: shouldForceDarkWeb ? WebDarkMode.On : WebDarkMode.Off,
    forceDarkAccess: shouldForceDarkWeb,
    backgroundColor: tokens.pageBackground,
    prefersDarkColorScheme: shouldForceDarkWeb
  });
}

export function buildWebAppearanceDocumentStartScript(policy: WebAppearancePolicy): string {
  const resolvedPolicy = resolveWebAppearancePolicy(policy);
  const backgroundLiteral = JSON.stringify(resolvedPolicy.backgroundColor);
  const colorSchemeLiteral = JSON.stringify(resolvedPolicy.prefersDarkColorScheme ? 'dark' : 'light');
  return `
(function airaWebAppearanceBootstrap() {
  var background = ${backgroundLiteral};
  var colorScheme = ${colorSchemeLiteral};
  var styleId = '__airaWebAppearanceBootstrapStyle';
  if (document.documentElement && document.documentElement.style) {
    document.documentElement.style.colorScheme = colorScheme;
  }
  var style = document.getElementById(styleId);
  if (!style) {
    style = document.createElement('style');
    style.id = styleId;
    (document.head || document.documentElement).appendChild(style);
  }
  style.textContent = 'html, body { background-color: ' + background + '; color-scheme: ' + colorScheme + '; }';
})();
`;
}

export function buildWebAppearanceDocumentStartScriptItem(policy: WebAppearancePolicy): ScriptItem {
  return {
    script: buildWebAppearanceDocumentStartScript(policy),
    scriptRules: ['.*']
  };
}
