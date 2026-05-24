export type SupportedLanguage = 'zh' | 'en';

export type LocaleModule = {
  default: {
    translation: Record<string, unknown>;
  };
};

export const SUPPORTED_LANGUAGES = ['zh', 'en'] as const;

export const localeLoaders: Record<SupportedLanguage, () => Promise<LocaleModule>> = {
  zh: () => import('@/i18n/locales/zh'),
  en: () => import('@/i18n/locales/en'),
};
