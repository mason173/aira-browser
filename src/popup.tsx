import { createRoot } from 'react-dom/client';
import { ThemeProvider } from 'next-themes';
import { I18nextProvider } from 'react-i18next';
import './index.css';
import { PopupApp } from '@/popup/PopupApp';
import { popupI18n, popupI18nReady } from '@/popup/i18n';

function toDocumentLanguage(language: string) {
  const normalized = String(language || '').trim().toLowerCase();
  if (normalized.startsWith('zh')) return 'zh-CN';
  return 'en';
}

function syncDocumentLanguage(language: string) {
  const resolvedLanguage = toDocumentLanguage(language);
  document.documentElement.lang = resolvedLanguage;
  document.body.lang = resolvedLanguage;
}

await popupI18nReady;
syncDocumentLanguage(popupI18n.language);
popupI18n.on('languageChanged', syncDocumentLanguage);
document.documentElement.dataset.popup = 'true';

createRoot(document.getElementById('root')!).render(
  <I18nextProvider i18n={popupI18n}>
    <ThemeProvider attribute="class" defaultTheme="system" enableSystem>
      <PopupApp />
    </ThemeProvider>
  </I18nextProvider>,
);
