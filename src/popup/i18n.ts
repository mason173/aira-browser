import { createInstance } from 'i18next';
import { initReactI18next } from 'react-i18next';

function detectPopupLanguage() {
  try {
    const stored = localStorage.getItem('i18nextLng');
    if (stored?.toLowerCase().startsWith('zh')) return 'zh';
  } catch {}

  const language = navigator.language || '';
  return language.toLowerCase().startsWith('zh') ? 'zh' : 'en';
}

export const popupI18n = createInstance();

export const popupI18nReady = popupI18n
  .use(initReactI18next)
  .init({
    lng: detectPopupLanguage(),
    fallbackLng: 'en',
    supportedLngs: ['en', 'zh'],
    interpolation: {
      escapeValue: false,
    },
    react: {
      useSuspense: false,
    },
    resources: {
      en: {
        translation: {
          common: {
            back: 'Back',
            save: 'Save',
          },
          popup: {
            home: {
              webdavOnlyTitle: 'Use WebDAV sync only',
              webdavOnlyDesc: 'Configure WebDAV to sync browser bookmarks',
            },
            webdav: {
              hidePassword: 'Hide password',
              showPassword: 'Show password',
            },
          },
          settings: {
            backup: {
              webdav: {
                entry: 'WebDAV Sync',
                password: 'Password',
                passwordPlaceholder: 'Optional',
                providerCustom: 'Custom service',
                providerLabel: 'WebDAV provider',
                providers: {
                  jianguoyun: 'Jianguoyun',
                },
                url: 'WebDAV URL',
                username: 'Username',
                usernamePlaceholder: 'Optional',
              },
            },
          },
        },
      },
      zh: {
        translation: {
          common: {
            back: '返回',
            save: '保存',
          },
          popup: {
            home: {
              webdavOnlyTitle: '仅使用 WebDAV 同步',
              webdavOnlyDesc: '配置 WebDAV 后同步浏览器书签',
            },
            webdav: {
              hidePassword: '隐藏密码',
              showPassword: '显示密码',
            },
          },
          settings: {
            backup: {
              webdav: {
                entry: 'WebDAV 同步',
                password: '密码',
                passwordPlaceholder: '可选',
                providerCustom: '自定义服务',
                providerLabel: 'WebDAV 服务商',
                providers: {
                  jianguoyun: '坚果云',
                },
                url: 'WebDAV 地址',
                username: '用户名',
                usernamePlaceholder: '可选',
              },
            },
          },
        },
      },
    },
  });
