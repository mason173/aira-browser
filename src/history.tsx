import { createRoot } from 'react-dom/client';
import { I18nextProvider } from 'react-i18next';
import { ThemeProvider } from 'next-themes';
import { Toaster } from '@/components/ui/sonner';
import { HistoryApp } from '@/features/sync/history/HistoryApp';
import { popupI18n, popupI18nReady } from '@/popup/i18n';
import './index.css';

function toDocumentLanguage(language: string): string {
  return String(language || '').toLowerCase().startsWith('zh') ? 'zh-CN' : 'en';
}

await popupI18nReady;
document.documentElement.lang = toDocumentLanguage(popupI18n.language);
document.documentElement.dataset.history = 'true';

createRoot(document.getElementById('root')!).render(
  <I18nextProvider i18n={popupI18n}>
    <ThemeProvider attribute="class" defaultTheme="system" enableSystem>
      <HistoryApp />
      <Toaster />
    </ThemeProvider>
  </I18nextProvider>,
);
