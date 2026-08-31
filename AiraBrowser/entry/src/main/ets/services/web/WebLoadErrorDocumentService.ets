import { BrowserWebLoadDataPayload } from '../../core/browser/BrowserWebLoadCoordinator';
import { WebLoadErrorPresentation } from './WebLoadErrorPresentationService';

export const WEB_LOAD_ERROR_DOCUMENT_BASE_URL: string = 'aira://error-document';
export const WEB_LOAD_ERROR_DOCUMENT_RETRY_URL: string = 'aira://error-document/retry';
export const WEB_LOAD_ERROR_DOCUMENT_SETTINGS_URL: string = 'aira://error-document/settings';

export interface WebLoadErrorDocumentLayoutOptions {
  bottomChromeInsetVp: number;
  accentColor?: string;
  onAccentColor?: string;
  darkAccentColor?: string;
  darkOnAccentColor?: string;
}

export class WebLoadErrorDocumentService {
  buildPayload(
    presentation: WebLoadErrorPresentation,
    targetUrl: string,
    layoutOptions?: WebLoadErrorDocumentLayoutOptions
  ): BrowserWebLoadDataPayload {
    const normalizedUrl = targetUrl.trim();
    return {
      data: this.buildHtml(presentation, normalizedUrl, layoutOptions),
      mimeType: 'text/html',
      encoding: 'UTF-8',
      baseUrl: normalizedUrl.length > 0 ? normalizedUrl : WEB_LOAD_ERROR_DOCUMENT_BASE_URL,
      historyUrl: normalizedUrl.length > 0 ? normalizedUrl : WEB_LOAD_ERROR_DOCUMENT_BASE_URL
    };
  }

  buildHtml(
    presentation: WebLoadErrorPresentation,
    targetUrl: string,
    layoutOptions?: WebLoadErrorDocumentLayoutOptions
  ): string {
    const bottomChromeInset = Math.max(0, Math.ceil(layoutOptions?.bottomChromeInsetVp ?? 0));
    const detailHtml = this.escapeHtml(presentation.detailText).replace(/\n/g, '<br>');
    const accentColor = this.resolveCssColor(layoutOptions?.accentColor, '#0A59F7');
    const onAccentColor = this.resolveCssColor(layoutOptions?.onAccentColor, '#FFFFFF');
    const darkAccentColor = this.resolveCssColor(layoutOptions?.darkAccentColor, accentColor);
    const darkOnAccentColor = this.resolveCssColor(layoutOptions?.darkOnAccentColor, onAccentColor);
    const detailBlockHtml = presentation.detailText.trim().length > 0
      ? `<div class="details">${detailHtml}</div>`
      : '';
    const hintsHtml = presentation.hints
      .map((hint: string): string => `<li>${this.escapeHtml(hint)}</li>`)
      .join('');
    return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="aira-error-document-url" content="${this.escapeHtml(targetUrl)}">
<title>${this.escapeHtml(presentation.title)}</title>
<style>
  :root {
    color-scheme: light dark;
    --page-bg: #ffffff;
    --text-primary: #1f1f1f;
    --text-secondary: rgba(0, 0, 0, 0.58);
    --stroke: rgba(0, 0, 0, 0.12);
    --primary: ${accentColor};
    --on-primary: ${onAccentColor};
    --browser-bottom-inset: ${bottomChromeInset}px;
    font-family: system-ui, sans-serif;
  }
  * { box-sizing: border-box; }
  html { min-height: 100%; background: var(--page-bg); }
  body {
    margin: 0;
    min-height: 100vh;
    overflow-x: hidden;
    overflow-y: auto;
    background: var(--page-bg);
    color: var(--text-primary);
  }
  .page {
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    align-items: stretch;
    justify-content: center;
    gap: 28px;
    padding: 48px 28px max(40px, calc(var(--browser-bottom-inset) + 28px));
  }
  main {
    width: min(100%, 480px);
    flex: 0 0 auto;
    display: flex;
    flex-direction: column;
    align-self: center;
    justify-content: center;
    text-align: center;
    padding: 0;
  }
  .actions {
    width: min(100%, 480px);
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    align-items: stretch;
    gap: 14px;
  }
  .icon-box {
    width: 64px;
    height: 64px;
    margin: 0 auto 24px;
    display: grid;
    place-items: center;
    border: 1px solid var(--stroke);
    border-radius: 18px;
  }
  .globe-icon {
    width: 36px;
    height: 36px;
    color: var(--text-primary);
  }
  h1 { margin: 0 0 10px; font-size: 22px; font-weight: 600; letter-spacing: 0; }
  p { margin: 0; color: var(--text-secondary); font-size: 14px; line-height: 1.6; }
  .primary-button {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 46px;
    border-radius: 23px;
    background: var(--primary);
    color: var(--on-primary);
    text-decoration: none;
    font-size: 16px;
    font-weight: 600;
    -webkit-tap-highlight-color: transparent;
  }
  .text-button {
    display: inline-flex;
    align-self: center;
    align-items: center;
    justify-content: center;
    min-height: 36px;
    padding: 0 10px;
    color: var(--text-secondary);
    text-decoration: none;
    font-size: 14px;
    -webkit-tap-highlight-color: transparent;
  }
  .details { margin-top: 24px; color: var(--text-secondary); font-size: 12px; line-height: 1.6; word-break: break-word; }
  ul { margin: 12px 0 0; padding: 0; list-style: none; color: var(--text-secondary); font-size: 12px; line-height: 1.7; }
  @media (prefers-color-scheme: dark) {
    :root {
      --page-bg: #1C2026;
      --text-primary: #f1f1f1;
      --text-secondary: rgba(255, 255, 255, 0.66);
      --stroke: rgba(255, 255, 255, 0.16);
      --primary: ${darkAccentColor};
      --on-primary: ${darkOnAccentColor};
    }
  }
</style>
</head>
<body>
<div class="page">
<main>
  <div class="icon-box" aria-hidden="true">
    <svg class="globe-icon" viewBox="0 0 48 48" fill="none">
      <circle cx="24" cy="24" r="17" stroke="currentColor" stroke-width="3.2"/>
      <path d="M7 24H41" stroke="currentColor" stroke-width="3.2" stroke-linecap="round"/>
      <path d="M24 7C29 12.2 31.5 17.8 31.5 24C31.5 30.2 29 35.8 24 41" stroke="currentColor" stroke-width="3.2" stroke-linecap="round"/>
      <path d="M24 7C19 12.2 16.5 17.8 16.5 24C16.5 30.2 19 35.8 24 41" stroke="currentColor" stroke-width="3.2" stroke-linecap="round"/>
      <path d="M11.5 13.5C15 16.2 19.2 17.5 24 17.5C28.8 17.5 33 16.2 36.5 13.5" stroke="currentColor" stroke-width="3.2" stroke-linecap="round"/>
      <path d="M11.5 34.5C15 31.8 19.2 30.5 24 30.5C28.8 30.5 33 31.8 36.5 34.5" stroke="currentColor" stroke-width="3.2" stroke-linecap="round"/>
    </svg>
  </div>
  <h1>${this.escapeHtml(presentation.title)}</h1>
  <p>${this.escapeHtml(presentation.summary)}</p>
  ${detailBlockHtml}
  <ul>${hintsHtml}</ul>
</main>
<div class="actions">
  <a class="primary-button" href="${WEB_LOAD_ERROR_DOCUMENT_RETRY_URL}">再试一次</a>
  <a class="text-button" href="${WEB_LOAD_ERROR_DOCUMENT_SETTINGS_URL}">转到系统设置</a>
</div>
</div>
</body>
</html>`;
  }

  private escapeHtml(value: string): string {
    return value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  private resolveCssColor(value: string | undefined, fallback: string): string {
    const normalized = value?.trim() ?? '';
    return normalized.length > 0 ? normalized : fallback;
  }

}
