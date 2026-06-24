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
            profile: {
              defaultNickname: 'Sign in',
              openLogin: 'Sign in',
              accountInfo: 'Account',
              identityStatus: 'Identity',
              membershipClub: 'Aira Club',
              membershipGuest: 'No membership',
              membershipPro: 'Aira Pro',
              membershipType: 'Plan',
              loggedOut: 'Signed out',
              logout: 'Sign out',
              loginNow: 'Sign in now',
              loginPrompt: 'Scan with Aira on your phone to sign in',
              moreActions: 'More actions',
              notSignedIn: 'Not signed in',
              signedIn: 'Signed in',
              userId: 'User ID',
              userIdInline: 'User ID: {{uid}}',
              webdavOnly: 'WebDAV configured',
            },
            dashboard: {
              advancedOptions: 'Advanced sync options',
              bookmarkCloudSync: 'Bookmark Cloud Sync',
              dataCountPlaceholder: '723 folders, 9212 bookmarks',
              dataCountUnknown: 'Not loaded',
              disabled: 'Off',
              disabledStatus: 'Disabled',
              enabled: 'On',
              enabledStatus: 'Enabled',
              webdavEnabledStatus: 'WebDAV enabled',
              lastSync: 'Last sync',
              lastSyncPlaceholder: '6/24/2026, 10:45:55 AM',
              localData: 'Local data',
              remoteData: 'WebDAV data',
              syncNow: 'Sync now',
              syncStatus: 'Sync status',
              syncStatusTitle: 'Sync status',
              syncToolsTitle: 'Sync tools',
            },
            advanced: {
              bookmarkCloudSync: 'WebDAV sync',
              checkRemoteData: 'Check WebDAV data',
              clearRemoteRecords: 'Clear WebDAV sync records',
              currentStatus: 'Current status',
              dangerZone: 'Danger zone',
              enableMode: 'Mode',
              enableModeValue: 'WebDAV sync',
              lastSyncValue: 'WebDAV {{time}}',
              mergeNow: 'Merge sync now',
              mergeSync: 'Merge sync',
              overwriteLocal: 'WebDAV overwrites local',
              overwriteRemote: 'Local overwrites WebDAV',
              rebuildSyncStart: 'Rebuild WebDAV sync start',
              remoteData: 'Remote data',
              remoteDataValue: 'WebDAV {{data}}',
              syncStart: 'Sync start',
              syncStartValue: 'WebDAV created',
            },
            firstSync: {
              title: 'Choose first sync mode',
              local: 'Local',
              webdav: 'WebDAV',
              merge: 'Merge',
              pushLocal: 'Local overwrites WebDAV',
              pullRemote: 'WebDAV overwrites local',
            },
            cloud: {
              account: 'Account',
              bookmarkSync: 'Bookmark sync',
              defaultAccount: 'Leo',
              enableBookmarkSync: 'Enable bookmark cloud sync',
              membership: 'Plan',
              membershipValue: 'Aira Pro',
            },
            home: {
              webdavOnlyTitle: 'Use WebDAV sync only',
              webdavOnlyDesc: 'Configure WebDAV to sync browser bookmarks',
            },
            login: {
              qrHint: 'Scan with Aira to sign in and enable bookmark cloud sync',
              qrAlt: 'Aira desktop login QR code',
              loading: 'Generating QR code',
              waiting: 'Waiting for confirmation in Aira',
              success: 'Signed in to Aira Sync Assistant',
              expired: 'QR code expired. Refresh and try again',
              error: 'QR login is temporarily unavailable',
              refresh: 'Refresh QR code',
              refreshing: 'QR code expired. Refreshing',
              expiresAt: 'Expires at {{time}}',
              expiresIn: 'Auto refresh in {{time}}',
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
            profile: {
              defaultNickname: '请登录',
              openLogin: '请登录',
              accountInfo: '账号信息',
              identityStatus: '身份状态',
              membershipClub: 'Aira Club',
              membershipGuest: '未开通会员',
              membershipPro: 'Aira Pro',
              membershipType: '会员类型',
              loggedOut: '已退出登录',
              logout: '退出登录',
              loginNow: '立即登录',
              loginPrompt: '使用 Aira 手机端扫码登录',
              moreActions: '更多操作',
              notSignedIn: '未登录',
              signedIn: '已登录',
              userId: '用户ID',
              userIdInline: '用户ID：{{uid}}',
              webdavOnly: 'WebDAV 已配置',
            },
            dashboard: {
              advancedOptions: '高级同步选项',
              bookmarkCloudSync: '书签云同步',
              dataCountPlaceholder: '723 个文件夹，9212 个书签',
              dataCountUnknown: '未读取',
              disabled: '未开启',
              disabledStatus: '未启用',
              enabled: '已开启',
              enabledStatus: '已启用',
              webdavEnabledStatus: 'WebDAV 已开启',
              lastSync: '最近同步',
              lastSyncPlaceholder: '6/24/2026, 10:45:55 AM',
              localData: '本机数据',
              remoteData: 'WebDAV 数据',
              syncNow: '立即同步',
              syncStatus: '同步状态',
              syncStatusTitle: '同步状态',
              syncToolsTitle: '同步工具',
            },
            advanced: {
              bookmarkCloudSync: 'WebDAV 同步',
              checkRemoteData: '检查 WebDAV 数据',
              clearRemoteRecords: '清除 WebDAV 同步记录',
              currentStatus: '当前状态',
              dangerZone: '危险操作',
              enableMode: '启用方式',
              enableModeValue: 'WebDAV 同步',
              lastSyncValue: 'WebDAV {{time}}',
              mergeNow: '立即合并同步',
              mergeSync: '合并同步',
              overwriteLocal: 'WebDAV 覆盖本机',
              overwriteRemote: '本机覆盖 WebDAV',
              rebuildSyncStart: '重建 WebDAV 同步起点',
              remoteData: '远端数据',
              remoteDataValue: 'WebDAV {{data}}',
              syncStart: '同步起点',
              syncStartValue: 'WebDAV 已建立',
            },
            firstSync: {
              title: '选择首次同步方式',
              local: '本机',
              webdav: 'WebDAV',
              merge: '合并',
              pushLocal: '本机覆盖 WebDAV',
              pullRemote: 'WebDAV 覆盖本机',
            },
            cloud: {
              account: '账号',
              bookmarkSync: '书签同步',
              defaultAccount: 'Leo',
              enableBookmarkSync: '开启书签云同步',
              membership: '会员',
              membershipValue: 'Aira Pro',
            },
            home: {
              webdavOnlyTitle: '仅使用 WebDAV 同步',
              webdavOnlyDesc: '配置 WebDAV 后同步浏览器书签',
            },
            login: {
              qrHint: '请使用Aira扫一扫登录开启书签云同步',
              qrAlt: 'Aira 桌面登录二维码',
              loading: '正在生成二维码',
              waiting: '等待 Aira 手机端确认',
              success: '已登录 Aira 同步助手',
              expired: '二维码已过期，请刷新后重试',
              error: '二维码登录暂时不可用',
              refresh: '刷新二维码',
              refreshing: '二维码已过期，正在刷新',
              expiresAt: '有效期至 {{time}}',
              expiresIn: '{{time}} 后自动刷新',
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
