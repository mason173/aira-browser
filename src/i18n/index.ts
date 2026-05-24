import i18n from 'i18next';
import type { BackendModule } from 'i18next';
import { initReactI18next } from 'react-i18next';
import LanguageDetector from 'i18next-browser-languagedetector';
import { localeLoaders, SUPPORTED_LANGUAGES, type SupportedLanguage } from '@/i18n/localeLoaders';

function normalizeLanguage(language: string): SupportedLanguage {
  const normalized = String(language || '').trim().toLowerCase();
  if (!normalized) return 'en';
  if (normalized.startsWith('zh')) return 'zh';
  return 'en';
}

const dynamicLocaleBackend: BackendModule = {
  type: 'backend',
  init: () => {},
  read: async (language, namespace, callback) => {
    try {
      const loader = localeLoaders[normalizeLanguage(language)];
      const module = await loader();
      const namespaceData = module.default?.[namespace as 'translation'] || module.default.translation;
      callback(null, namespaceData);
    } catch (error) {
      callback(error as Error, false);
    }
  },
};

export const i18nReady = i18n
  .use(dynamicLocaleBackend)
  .use(LanguageDetector)
  .use(initReactI18next)
  .init(({
    fallbackLng: 'en',
    debug: false,
    logger: {
      log: (...args: any[]) => {
        const first = args[0];
        if (typeof first === 'string' && first.includes('locize.com')) return;
        if (typeof console !== 'undefined' && typeof console.log === 'function') console.log(...args);
      },
      warn: (...args: any[]) => {
        if (typeof console !== 'undefined' && typeof console.warn === 'function') console.warn(...args);
      },
      error: (...args: any[]) => {
        if (typeof console !== 'undefined' && typeof console.error === 'function') console.error(...args);
      },
    },
    interpolation: {
      escapeValue: false
    },
    detection: {
      order: ['localStorage', 'navigator'],
      caches: [],
      lookupLocalStorage: 'i18nextLng'
    },
    react: {
      useSuspense: false,
    },
    ns: ['translation'],
    defaultNS: 'translation',
    nonExplicitSupportedLngs: true,
    supportedLngs: SUPPORTED_LANGUAGES,
  } as any));

export default i18n;
