import { webview } from '@kit.ArkWeb';

export interface AiraLegalWebStyleTheme {
  styleId: string;
  pageBackground: string;
  primaryText: string;
  secondaryText: string;
}

export class AiraLegalWebStyleService {
  apply(controller: webview.WebviewController, theme: AiraLegalWebStyleTheme): void {
    controller.runJavaScript(this.buildStyleScript(theme))
      .catch((_error: Error) => {});
  }

  private buildStyleScript(theme: AiraLegalWebStyleTheme): string {
    const styleId = JSON.stringify(theme.styleId);
    const pageBackground = JSON.stringify(theme.pageBackground);
    const primaryText = JSON.stringify(theme.primaryText);
    const secondaryText = JSON.stringify(theme.secondaryText);
    return `
;(function airaApplyLegalWebStyle() {
  var styleId = ${styleId};
  var pageBackground = ${pageBackground};
  var primaryText = ${primaryText};
  var secondaryText = ${secondaryText};
  if (!document.documentElement) {
    return 'missing-document';
  }
  var style = document.getElementById(styleId);
  if (!style) {
    style = document.createElement('style');
    style.id = styleId;
    style.setAttribute('data-aira-legal-style', 'theme');
    (document.head || document.documentElement).appendChild(style);
  }
  style.textContent = [
    'html {',
    '  background: ' + pageBackground + ' !important;',
    '  margin: 0 !important;',
    '  padding: 0 !important;',
    '  overscroll-behavior-y: auto !important;',
    '}',
    'body {',
    '  box-sizing: border-box !important;',
    '  max-width: 900px !important;',
    '  min-height: 100vh !important;',
    '  background: transparent !important;',
    '  color: ' + primaryText + ' !important;',
    '  margin: 0 auto !important;',
    '  padding: calc(44px + env(safe-area-inset-top)) calc(24px + env(safe-area-inset-right)) calc(96px + env(safe-area-inset-bottom)) calc(24px + env(safe-area-inset-left)) !important;',
    '  font-family: sans-serif !important;',
    '  line-height: 1.65 !important;',
    '  -webkit-text-size-adjust: 100% !important;',
    '}',
    'body *, body *::before, body *::after {',
    '  box-sizing: border-box !important;',
    '}',
    'body, body * {',
    '  color: ' + primaryText + ' !important;',
    '}',
    'main, article, section, .container, .content {',
    '  background: transparent !important;',
    '}',
    'p, li, div, span {',
    '  font-size: 15px !important;',
    '  line-height: 24px !important;',
    '}',
    'p + p {',
    '  margin-top: 10px !important;',
    '}',
    'h1, h2, h3, h4, h5, h6 {',
    '  color: ' + primaryText + ' !important;',
    '  font-weight: 700 !important;',
    '  margin-top: 32px !important;',
    '  margin-bottom: 12px !important;',
    '  line-height: 1.4 !important;',
    '}',
    'small, time, .date, .update, .updated, .subtitle, .desc, .description {',
    '  color: ' + secondaryText + ' !important;',
    '}',
    'a {',
    '  color: ' + primaryText + ' !important;',
    '}',
    '.table-wrap, table {',
    '  max-width: 100% !important;',
    '}',
    '.table-wrap {',
    '  overflow-x: auto !important;',
    '  -webkit-overflow-scrolling: touch !important;',
    '}',
    'table {',
    '  border-collapse: collapse !important;',
    '}',
    '@media (max-width: 480px) {',
    '  body {',
    '    padding: calc(40px + env(safe-area-inset-top)) calc(24px + env(safe-area-inset-right)) calc(96px + env(safe-area-inset-bottom)) calc(24px + env(safe-area-inset-left)) !important;',
    '  }',
    '}'
  ].join('\\n');
  return 'ok';
})();`;
  }
}
