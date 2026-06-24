import { useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import { useTranslation } from 'react-i18next';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { toast } from '@/components/ui/sonner';
import { useLeafTabSyncRuntimeController } from '@/features/sync/bookmarks/useBookmarkWebdavSyncRuntimeController';
import type { LeafTabSyncFacade } from '@/features/sync/app/LeafTabSyncContracts';
import QRCodeStyling from 'qr-code-styling';
import {
  RiArrowLeftSLine,
  RiArrowRightSLine,
  RiCheckFill,
  RiCloudFill,
  RiEyeFill,
  RiEyeOffFill,
  RiHardDrive3Fill,
  RiLogoutBoxRLine,
  RiMoreFill,
  RiSlidersFill,
  RiUserFill,
} from '@/icons/ri-compat';
import { ensureOriginPermission } from '@/utils/extensionPermissions';
import {
  readWebdavStorageStateFromStorage,
  WEBDAV_DEFAULT_SYNC_BY_SCHEDULE,
  WEBDAV_DEFAULT_SYNC_INTERVAL_MINUTES,
  WEBDAV_STORAGE_KEYS,
  writeWebdavStorageStateToStorage,
} from '@/utils/webdavConfig';
import type { LeafTabSyncAnalysis, LeafTabSyncInitialChoice } from '@/sync/leaftab';
import {
  clearAiraDesktopLoginProfile,
  createAiraDesktopLoginSession,
  pollAiraDesktopLoginStatus,
  readAiraDesktopLoginProfile,
  writeAiraDesktopLoginProfile,
  type AiraDesktopLoginSession,
} from './desktopLogin';

type PopupView = 'home' | 'webdav' | 'advanced' | 'cloud' | 'login';

type WebdavProviderOption = {
  id: string;
  label: string;
  url?: string;
  iconUrl: string;
};

type ConfiguredHomeState = {
  nickname: string;
  uid: string;
  userId: string;
  avatarUri: string;
  identityStatus: string;
  membershipPlan: string;
  membershipStatus: string;
  isDesktopLoggedIn: boolean;
  lastSyncLabel: string;
  localDataLabel: string;
  remoteDataLabel: string;
  syncStartLabel: string;
  webdavEnabled: boolean;
};

type WebdavHomeState = {
  configured: boolean;
  enabled: boolean;
  statusLabel: string;
  lastSyncLabel: string;
  localDataLabel: string;
  remoteDataLabel: string;
  syncStartLabel: string;
};

type PopupSyncRuntime = Pick<LeafTabSyncFacade, 'state' | 'actions'>;

const resolveSyncStatusLabel = (enabled: boolean, t: ReturnType<typeof useTranslation>['t']) => {
  return enabled
    ? t('popup.dashboard.webdavEnabledStatus', { defaultValue: 'WebDAV 已开启' })
    : t('popup.dashboard.disabledStatus', { defaultValue: '未启用' });
};

const resolveActiveSyncStatusLabel = (
  cloudEnabled: boolean,
  webdavEnabled: boolean,
  t: ReturnType<typeof useTranslation>['t'],
) => {
  if (cloudEnabled && webdavEnabled) {
    return t('popup.dashboard.dualEnabledStatus', { defaultValue: '双重同步已开启' });
  }
  if (cloudEnabled) {
    return t('popup.dashboard.cloudEnabledStatus', { defaultValue: '云同步已开启' });
  }
  if (webdavEnabled) {
    return t('popup.dashboard.webdavEnabledStatus', { defaultValue: 'WebDAV 已开启' });
  }
  return t('popup.dashboard.disabledStatus', { defaultValue: '未启用' });
};

const resolveLastSyncLabel = (
  cloudEnabled: boolean,
  webdavEnabled: boolean,
  cloudLabel: string,
  webdavLabel: string,
) => {
  if (cloudEnabled && !webdavEnabled) return cloudLabel || webdavLabel;
  return webdavLabel || cloudLabel;
};

const formatLastSync = (raw: string | null, fallback: string) => {
  if (!raw) return fallback;

  const timestamp = Date.parse(raw);
  if (!Number.isFinite(timestamp)) return raw;

  return new Intl.DateTimeFormat(undefined, {
    year: 'numeric',
    month: 'numeric',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    second: '2-digit',
  }).format(new Date(timestamp));
};

const getShortUid = (source: string) => {
  const normalized = source.trim();
  if (!normalized) return 'AIRA-0000';

  let hash = 0;
  for (let index = 0; index < normalized.length; index += 1) {
    hash = ((hash << 5) - hash + normalized.charCodeAt(index)) | 0;
  }

  return `AIRA-${Math.abs(hash).toString(36).toUpperCase().slice(0, 6).padStart(6, '0')}`;
};

function blobToDataUrl(blob: Blob) {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || ''));
    reader.onerror = () => reject(reader.error ?? new Error('Unable to render QR code.'));
    reader.readAsDataURL(blob);
  });
}

async function createStyledQrDataUrl(payload: string) {
  const qrCode = new QRCodeStyling({
    width: 176,
    height: 176,
    type: 'svg',
    data: payload,
    margin: 4,
    qrOptions: {
      errorCorrectionLevel: 'M',
    },
    dotsOptions: {
      type: 'rounded',
      color: '#0F172A',
    },
    cornersSquareOptions: {
      type: 'extra-rounded',
      color: '#0F172A',
    },
    cornersDotOptions: {
      type: 'square',
      color: '#0F172A',
    },
    backgroundOptions: {
      color: '#FFFFFF',
    },
  });
  const raw = await qrCode.getRawData('svg');
  if (raw instanceof Blob) {
    return blobToDataUrl(raw);
  }
  throw new Error('Unable to render QR code.');
}

function formatCountdownTime(remainingMs: number) {
  const totalSeconds = Math.max(0, Math.ceil(remainingMs / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${String(seconds).padStart(2, '0')}`;
}

function readConfiguredHomeState(t: ReturnType<typeof useTranslation>['t']): ConfiguredHomeState | null {
  try {
    const desktopLoginProfile = readAiraDesktopLoginProfile();
    if (desktopLoginProfile && desktopLoginProfile.uid) {
      const webdavEnabled = (localStorage.getItem(WEBDAV_STORAGE_KEYS.syncEnabled) ?? 'false') === 'true';
      return {
        nickname: desktopLoginProfile.displayName,
        uid: desktopLoginProfile.uidSuffix ? `AIRA-${desktopLoginProfile.uidSuffix}` : getShortUid(desktopLoginProfile.uid),
        userId: desktopLoginProfile.uid,
        avatarUri: desktopLoginProfile.avatarUri,
        identityStatus: t('popup.profile.signedIn', { defaultValue: '已登录' }),
        membershipPlan: desktopLoginProfile.membershipPlan,
        membershipStatus: desktopLoginProfile.membershipStatus,
        isDesktopLoggedIn: true,
        lastSyncLabel: formatLastSync(
          localStorage.getItem('webdav_last_sync_at'),
          t('popup.dashboard.lastSyncPlaceholder', { defaultValue: '6/24/2026, 10:45:55 AM' }),
        ),
        localDataLabel: t('popup.dashboard.dataCountUnknown', { defaultValue: '未读取' }),
        remoteDataLabel: t('popup.dashboard.dataCountUnknown', { defaultValue: '未读取' }),
        syncStartLabel: t('popup.advanced.syncStartValue', { defaultValue: 'WebDAV 已建立' }),
        webdavEnabled,
      };
    }
    return null;
  } catch {
    return null;
  }
}

function readWebdavHomeState(t: ReturnType<typeof useTranslation>['t']): WebdavHomeState {
  try {
    const configured = Boolean((localStorage.getItem(WEBDAV_STORAGE_KEYS.url) || '').trim());
    const enabled = configured && (localStorage.getItem(WEBDAV_STORAGE_KEYS.syncEnabled) ?? 'false') === 'true';
    return {
      configured,
      enabled,
      statusLabel: enabled
        ? t('popup.dashboard.enabled', { defaultValue: '已开启' })
        : t('popup.dashboard.disabled', { defaultValue: '未开启' }),
      lastSyncLabel: formatLastSync(
        localStorage.getItem('webdav_last_sync_at'),
        t('popup.dashboard.lastSyncPlaceholder', { defaultValue: '6/24/2026, 10:45:55 AM' }),
      ),
      localDataLabel: t('popup.dashboard.dataCountUnknown', { defaultValue: '未读取' }),
      remoteDataLabel: t('popup.dashboard.dataCountUnknown', { defaultValue: '未读取' }),
      syncStartLabel: t('popup.advanced.syncStartValue', { defaultValue: 'WebDAV 已建立' }),
    };
  } catch {
    return {
      configured: false,
      enabled: false,
      statusLabel: t('popup.dashboard.disabled', { defaultValue: '未开启' }),
      lastSyncLabel: t('popup.dashboard.lastSyncPlaceholder', { defaultValue: '6/24/2026, 10:45:55 AM' }),
      localDataLabel: t('popup.dashboard.dataCountUnknown', { defaultValue: '未读取' }),
      remoteDataLabel: t('popup.dashboard.dataCountUnknown', { defaultValue: '未读取' }),
      syncStartLabel: t('popup.advanced.syncStartValue', { defaultValue: 'WebDAV 已建立' }),
    };
  }
}

function resolveMembershipLabel(plan: string, t: ReturnType<typeof useTranslation>['t']) {
  const normalized = plan.trim().toLowerCase();
  if (normalized === 'pro') {
    return t('popup.profile.membershipPro', { defaultValue: 'Aira Pro' });
  }
  if (normalized === 'club') {
    return t('popup.profile.membershipClub', { defaultValue: 'Aira Club' });
  }
  return t('popup.profile.membershipGuest', { defaultValue: '未开通会员' });
}

function formatBookmarkDataLabel(
  summary: LeafTabSyncAnalysis['localSummary'] | LeafTabSyncAnalysis['remoteSummary'] | null | undefined,
  fallback: string,
) {
  if (!summary) return fallback;
  return `${summary.bookmarkFolders} 个文件夹，${summary.bookmarkItems} 个书签`;
}

function FirstSyncChoiceDialog({ syncRuntime }: { syncRuntime: PopupSyncRuntime }) {
  const { t } = useTranslation();
  const request = syncRuntime.state.leafTabInitialSyncChoiceRequest;
  const localLabel = formatBookmarkDataLabel(
    request?.localSummary,
    t('popup.dashboard.dataCountUnknown', { defaultValue: '未读取' }),
  );
  const remoteLabel = formatBookmarkDataLabel(
    request?.remoteSummary,
    t('popup.dashboard.dataCountUnknown', { defaultValue: '未读取' }),
  );

  return (
    <Dialog
      open={Boolean(request)}
      onOpenChange={(open) => {
        if (!open) {
          syncRuntime.actions.resolveLeafTabInitialSyncChoice(null);
        }
      }}
    >
      <DialogContent className="max-w-[328px] rounded-[24px] p-5">
        <DialogHeader className="text-left">
          <DialogTitle>{t('popup.firstSync.title', { defaultValue: '选择首次同步方式' })}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div className="grid grid-cols-[88px_minmax(0,1fr)] gap-x-3 gap-y-2 text-sm">
            <span className="text-muted-foreground">{t('popup.firstSync.local', { defaultValue: '本机' })}</span>
            <span className="font-medium text-foreground">{localLabel}</span>
            <span className="text-muted-foreground">{t('popup.firstSync.remote', { defaultValue: '远端' })}</span>
            <span className="font-medium text-foreground">{remoteLabel}</span>
          </div>
          <div className="grid gap-2">
            <Button
              type="button"
              className="h-10 rounded-[8px]"
              onClick={() => syncRuntime.actions.resolveLeafTabInitialSyncChoice('merge')}
            >
              {t('popup.firstSync.merge', { defaultValue: '合并' })}
            </Button>
            <Button
              type="button"
              variant="outline"
              className="h-10 rounded-[8px]"
              onClick={() => syncRuntime.actions.resolveLeafTabInitialSyncChoice('push-local')}
            >
              {t('popup.firstSync.pushLocal', { defaultValue: '本机覆盖远端' })}
            </Button>
            <Button
              type="button"
              variant="outline"
              className="h-10 rounded-[8px]"
              onClick={() => syncRuntime.actions.resolveLeafTabInitialSyncChoice('pull-remote')}
            >
              {t('popup.firstSync.pullRemote', { defaultValue: '远端覆盖本机' })}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

function SyncProgressDialog({ syncRuntime }: { syncRuntime: PopupSyncRuntime }) {
  const { t } = useTranslation();
  const progress = syncRuntime.state.leafTabSyncProgress;
  const progressValue = Math.max(0, Math.min(100, Math.round(progress.progress)));

  return (
    <Dialog
      open={progress.open}
      onOpenChange={(open) => {
        if (!open) {
          syncRuntime.actions.handleDismissSyncProgress();
        }
      }}
    >
      <DialogContent
        className="max-w-[328px] rounded-[20px] p-5"
        onInteractOutside={(event) => {
          if (progress.inProgress) event.preventDefault();
        }}
        onEscapeKeyDown={(event) => {
          if (progress.inProgress) event.preventDefault();
        }}
      >
        <DialogHeader className="text-left">
          <DialogTitle>{progress.title || t('popup.progress.syncingTitle', { defaultValue: '正在同步书签' })}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div className="h-2 overflow-hidden rounded-full bg-muted">
            <div
              className="h-full rounded-full bg-primary transition-all duration-300"
              style={{ width: `${progressValue}%` }}
            />
          </div>
          <div className="grid grid-cols-[72px_minmax(0,1fr)] gap-x-3 gap-y-2 text-sm">
            <span className="text-muted-foreground">{t('popup.progress.status', { defaultValue: '状态' })}</span>
            <span className="font-medium text-foreground">{progress.detail}</span>
            <span className="text-muted-foreground">{t('popup.progress.progress', { defaultValue: '进度' })}</span>
            <span className="font-medium text-foreground">{progressValue}%</span>
          </div>
          {!progress.inProgress ? (
            <Button
              type="button"
              className="h-10 w-full rounded-[8px]"
              onClick={() => syncRuntime.actions.handleDismissSyncProgress()}
            >
              {t('popup.progress.done', { defaultValue: '知道了' })}
            </Button>
          ) : null}
        </div>
      </DialogContent>
    </Dialog>
  );
}

function LoginQrPanel({ onLoggedIn }: { onLoggedIn: () => void }) {
  const { t } = useTranslation();
  const [session, setSession] = useState<AiraDesktopLoginSession | null>(null);
  const [qrDataUrl, setQrDataUrl] = useState('');
  const [status, setStatus] = useState<'loading' | 'pending' | 'confirmed' | 'expired' | 'error'>('loading');
  const [message, setMessage] = useState('');
  const [remainingMs, setRemainingMs] = useState(0);
  const [refreshNonce, setRefreshNonce] = useState(0);

  useEffect(() => {
    let disposed = false;
    let timer = 0;

    const clearPollTimer = () => {
      if (timer > 0) {
        window.clearTimeout(timer);
        timer = 0;
      }
    };

    const schedulePoll = (nextSession: AiraDesktopLoginSession, delayMs: number) => {
      clearPollTimer();
      timer = window.setTimeout(() => {
        pollAiraDesktopLoginStatus(nextSession)
          .then((result) => {
            if (disposed) return;
            if (result.status === 'confirmed') {
              writeAiraDesktopLoginProfile({
                ...result.account,
                loggedInAt: new Date().toISOString(),
              });
              setStatus('confirmed');
              setMessage(t('popup.login.success', { defaultValue: '已登录 Aira 同步助手' }));
              onLoggedIn();
              return;
            }
            if (result.status === 'expired') {
              setSession(null);
              setQrDataUrl('');
              setRemainingMs(0);
              setStatus('loading');
              setMessage(t('popup.login.refreshing', { defaultValue: '二维码已过期，正在刷新' }));
              setRefreshNonce((value) => value + 1);
              return;
            }
            setStatus('pending');
            setMessage(t('popup.login.waiting', { defaultValue: '等待 Aira 手机端确认' }));
            schedulePoll(nextSession, result.pollIntervalMs);
          })
          .catch((error: Error) => {
            if (disposed) return;
            setStatus('error');
            setMessage(error.message || t('popup.login.error', { defaultValue: '二维码登录暂时不可用' }));
          });
      }, delayMs);
    };

    setStatus('loading');
    setRemainingMs(0);
    setMessage(t('popup.login.loading', { defaultValue: '正在生成二维码' }));
    createAiraDesktopLoginSession()
      .then(async (nextSession) => {
        if (disposed) return;
        const nextQrDataUrl = await createStyledQrDataUrl(nextSession.qrPayload);
        if (disposed) return;
        setSession(nextSession);
        setQrDataUrl(nextQrDataUrl);
        setRemainingMs(Math.max(0, nextSession.expiresAt - Date.now()));
        setStatus('pending');
        setMessage(t('popup.login.waiting', { defaultValue: '等待 Aira 手机端确认' }));
        schedulePoll(nextSession, nextSession.pollIntervalMs);
      })
      .catch((error: Error) => {
        if (disposed) return;
        setStatus('error');
        setMessage(error.message || t('popup.login.error', { defaultValue: '二维码登录暂时不可用' }));
      });

    return () => {
      disposed = true;
      clearPollTimer();
    };
  }, [onLoggedIn, refreshNonce, t]);

  useEffect(() => {
    if (!session || status !== 'pending') return undefined;

    const updateCountdown = () => {
      const nextRemainingMs = Math.max(0, session.expiresAt - Date.now());
      setRemainingMs(nextRemainingMs);
      if (nextRemainingMs <= 0) {
        setSession(null);
        setQrDataUrl('');
        setStatus('loading');
        setMessage(t('popup.login.refreshing', { defaultValue: '二维码已过期，正在刷新' }));
        setRefreshNonce((value) => value + 1);
      }
    };

    updateCountdown();
    const interval = window.setInterval(updateCountdown, 1000);
    return () => window.clearInterval(interval);
  }, [session, status, t]);

  const canRefresh = status === 'error';

  return (
    <div className="flex flex-col items-center px-4 pt-4 text-center">
      <div className="flex h-44 w-44 items-center justify-center rounded-[14px] border border-border bg-white p-1 shadow-sm">
        {qrDataUrl ? (
          <img
            src={qrDataUrl}
            alt={t('popup.login.qrAlt', { defaultValue: 'Aira desktop login QR code' })}
            className="h-full w-full rounded-[10px]"
          />
        ) : (
          <div className="h-full w-full animate-pulse rounded-[10px] bg-secondary/40" aria-hidden="true" />
        )}
      </div>
      <p className="mt-3 max-w-64 text-sm font-medium leading-5 text-foreground">
        {t('popup.login.qrHint', { defaultValue: '请使用Aira扫一扫登录开启书签云同步' })}
      </p>
      <p className="mt-1 max-w-64 text-xs leading-4 text-muted-foreground">
        {message}
      </p>
      {session && status === 'pending' && (
        <p className="mt-1 text-[10px] leading-4 text-muted-foreground">
          {t('popup.login.expiresIn', {
            defaultValue: '{{time}} 后自动刷新',
            time: formatCountdownTime(remainingMs),
          })}
        </p>
      )}
      {canRefresh && (
        <Button
          type="button"
          variant="outline"
          className="mt-3 h-9 rounded-[8px]"
          onClick={() => {
            setSession(null);
            setQrDataUrl('');
            setStatus('loading');
            setRefreshNonce((value) => value + 1);
          }}
        >
          {t('popup.login.refresh', { defaultValue: '刷新二维码' })}
        </Button>
      )}
    </div>
  );
}

function ProfileAvatar({ profile }: { profile: ConfiguredHomeState }) {
  const [imageFailed, setImageFailed] = useState(false);
  const avatarUri = profile.avatarUri.trim();
  const canShowImage = avatarUri.length > 0 && !imageFailed && (
    avatarUri.startsWith('https://') ||
    avatarUri.startsWith('http://') ||
    avatarUri.startsWith('data:')
  );

  return (
    <div className="flex h-12 w-12 items-center justify-center overflow-hidden rounded-full bg-secondary text-muted-foreground">
      {canShowImage ? (
        <img
          src={avatarUri}
          alt=""
          className="h-full w-full object-cover"
          onError={() => setImageFailed(true)}
        />
      ) : (
        <RiUserFill className="size-6" />
      )}
    </div>
  );
}

function ProfileHeader({
  profile,
  onLogout,
}: {
  profile: ConfiguredHomeState;
  onLogout: () => void;
}) {
  const { t } = useTranslation();
  const [menuOpen, setMenuOpen] = useState(false);

  return (
    <header className="relative px-4 pb-3 pt-4 text-center">
      {profile.isDesktopLoggedIn && (
        <div className="absolute right-3 top-3">
          <button
            type="button"
            className="flex h-8 w-8 items-center justify-center rounded-[8px] text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
            onClick={() => setMenuOpen((value) => !value)}
            aria-label={t('popup.profile.moreActions', { defaultValue: '更多操作' })}
            title={t('popup.profile.moreActions', { defaultValue: '更多操作' })}
          >
            <RiMoreFill className="size-5" />
          </button>
          {menuOpen && (
            <div className="absolute right-0 top-9 z-20 w-32 overflow-hidden rounded-[8px] border border-border bg-popover py-1 text-left shadow-lg">
              <button
                type="button"
                className="flex h-9 w-full items-center gap-2 px-3 text-sm text-foreground transition-colors hover:bg-accent"
                onClick={() => {
                  setMenuOpen(false);
                  onLogout();
                }}
              >
                <RiLogoutBoxRLine className="size-4 text-muted-foreground" />
                <span>{t('popup.profile.logout', { defaultValue: '退出登录' })}</span>
              </button>
            </div>
          )}
        </div>
      )}
      <div className="mx-auto flex flex-col items-center px-8 py-1">
        <ProfileAvatar profile={profile} />
        <div className="mt-2 text-sm font-semibold leading-5 text-foreground">
          {profile.nickname}
        </div>
        <div className="mt-1 flex items-center gap-1.5">
          <StatusBadge>{resolveMembershipLabel(profile.membershipPlan, t)}</StatusBadge>
          <span className="text-[10px] leading-4 text-muted-foreground">{profile.identityStatus}</span>
        </div>
        <div
          className="mt-1 max-w-[280px] truncate text-xs leading-4 text-muted-foreground"
          title={profile.userId}
        >
          {t('popup.profile.userIdInline', {
            defaultValue: '用户ID：{{uid}}',
            uid: profile.userId || profile.uid,
          })}
        </div>
      </div>
    </header>
  );
}

function StatusBadge({ children }: { children: ReactNode }) {
  return (
    <span className="rounded-full bg-muted px-2 py-0.5 text-[10px] font-semibold uppercase leading-4 text-muted-foreground">
      {children}
    </span>
  );
}

function PanelRow({
  icon,
  title,
  badge,
  status,
  onClick,
}: {
  icon: ReactNode;
  title: string;
  badge?: string;
  status: string;
  onClick?: () => void;
}) {
  const content = (
    <>
      {icon ? (
        <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-[8px] bg-muted text-muted-foreground">
          {icon}
        </span>
      ) : null}
      <span className="min-w-0 flex-1 truncate text-sm font-medium leading-5 text-foreground">
        {title}
      </span>
      {badge ? <StatusBadge>{badge}</StatusBadge> : null}
      <span className="shrink-0 text-xs leading-5 text-muted-foreground">{status}</span>
      {onClick ? <RiArrowRightSLine className="size-4 shrink-0 text-muted-foreground" /> : null}
    </>
  );

  if (!onClick) {
    return (
      <div className="flex min-h-11 w-full items-center gap-3 px-3 py-2.5 text-left">
        {content}
      </div>
    );
  }

  return (
    <button
      type="button"
      className="flex min-h-11 w-full items-center gap-3 px-3 py-2.5 text-left transition-colors hover:bg-accent/70"
      onClick={onClick}
    >
      {content}
    </button>
  );
}

function SectionLabel({ children }: { children: ReactNode }) {
  return (
    <h2 className="px-1 text-xs font-medium leading-4 text-muted-foreground">
      {children}
    </h2>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex min-h-10 items-center justify-between gap-3 border-b border-border px-3 py-2.5 last:border-b-0">
      <span className="shrink-0 text-sm font-medium leading-5 text-foreground">{label}</span>
      <span className="min-w-0 truncate text-right text-xs leading-5 text-muted-foreground">{value}</span>
    </div>
  );
}

function ConfiguredHome({
  profile,
  syncRuntime,
  onLogout,
  onOpenCloud,
  onOpenWebdav,
  onOpenAdvanced,
}: {
  profile: ConfiguredHomeState;
  syncRuntime: PopupSyncRuntime;
  onLogout: () => void;
  onOpenCloud: () => void;
  onOpenWebdav: () => void;
  onOpenAdvanced: () => void;
}) {
  const { t } = useTranslation();
  const syncing = syncRuntime.state.topNavSyncStatus === 'syncing';
  const cloudEnabled = syncRuntime.state.leafTabCloudSyncEnabled;
  const webdavEnabled = profile.webdavEnabled;
  const dualEnabled = cloudEnabled && webdavEnabled;
  const webdavAnalysis = syncRuntime.state.leafTabWebdavSyncAnalysis;
  const cloudAnalysis = syncRuntime.state.leafTabCloudSyncAnalysis;
  const localDataLabel = formatBookmarkDataLabel(
    (webdavAnalysis || cloudAnalysis)?.localSummary,
    profile.localDataLabel,
  );
  const cloudDataLabel = formatBookmarkDataLabel(cloudAnalysis?.remoteSummary, profile.remoteDataLabel);
  const webdavDataLabel = formatBookmarkDataLabel(webdavAnalysis?.remoteSummary, profile.remoteDataLabel);
  const singleRemoteDataLabel = cloudEnabled && !webdavEnabled ? cloudDataLabel : webdavDataLabel;
  const membershipLabel = resolveMembershipLabel(profile.membershipPlan, t);

  return (
    <section className="min-h-[480px] bg-background">
      <ProfileHeader profile={profile} onLogout={onLogout} />

      <div className="space-y-3 px-3 pb-3">
        <div className="overflow-hidden rounded-[8px] border border-border bg-card">
          <PanelRow
            icon={<RiCloudFill className="size-4" />}
            title={t('popup.dashboard.bookmarkCloudSync', { defaultValue: '书签云同步' })}
            badge="PRO"
            status={cloudEnabled
              ? t('popup.dashboard.enabled', { defaultValue: '已开启' })
              : t('popup.dashboard.disabled', { defaultValue: '未开启' })}
            onClick={onOpenCloud}
          />
          <div className="mx-3 border-t border-border" />
          <PanelRow
            icon={<RiHardDrive3Fill className="size-4" />}
            title={t('settings.backup.webdav.entry', { defaultValue: 'WebDAV 同步' })}
            status={webdavEnabled
              ? t('popup.dashboard.enabled', { defaultValue: '已开启' })
              : t('popup.dashboard.disabled', { defaultValue: '未开启' })}
            onClick={onOpenWebdav}
          />
        </div>

        <div className="space-y-2">
          <SectionLabel>{t('popup.profile.accountInfo', { defaultValue: '账号信息' })}</SectionLabel>
          <div className="overflow-hidden rounded-[8px] border border-border bg-card">
            <InfoRow
              label={t('popup.profile.userId', { defaultValue: '用户ID' })}
              value={profile.userId || profile.uid}
            />
            <InfoRow
              label={t('popup.profile.identityStatus', { defaultValue: '身份状态' })}
              value={profile.identityStatus}
            />
            <InfoRow
              label={t('popup.profile.membershipType', { defaultValue: '会员类型' })}
              value={membershipLabel}
            />
          </div>
        </div>

        <div className="space-y-2">
          <SectionLabel>{t('popup.dashboard.syncStatusTitle', { defaultValue: '同步状态' })}</SectionLabel>
          <div className="overflow-hidden rounded-[8px] border border-border bg-card">
            <InfoRow
              label={t('popup.dashboard.syncStatus', { defaultValue: '同步状态' })}
              value={resolveActiveSyncStatusLabel(cloudEnabled, webdavEnabled, t)}
            />
            <InfoRow
              label={t('popup.dashboard.lastSync', { defaultValue: '最近同步' })}
              value={resolveLastSyncLabel(
                cloudEnabled,
                webdavEnabled,
                syncRuntime.state.leafTabCloudLastSyncLabel,
                profile.lastSyncLabel,
              )}
            />
            <InfoRow
              label={t('popup.dashboard.localData', { defaultValue: '本机数据' })}
              value={localDataLabel}
            />
            {dualEnabled ? (
              <>
                <InfoRow
                  label={t('popup.dashboard.cloudData', { defaultValue: '云同步数据' })}
                  value={cloudDataLabel}
                />
                <InfoRow
                  label={t('popup.dashboard.webdavData', { defaultValue: 'WebDAV 数据' })}
                  value={webdavDataLabel}
                />
              </>
            ) : (
              <InfoRow
                label={cloudEnabled
                  ? t('popup.dashboard.cloudData', { defaultValue: '云同步数据' })
                  : t('popup.dashboard.webdavData', { defaultValue: 'WebDAV 数据' })}
                value={singleRemoteDataLabel}
              />
            )}
          </div>
        </div>

        <Button
          type="button"
          className="h-10 w-full rounded-[8px] text-sm font-medium"
          disabled={syncing}
          onClick={() => {
            void syncRuntime.actions.handleActiveSyncNowFromCenter();
          }}
        >
          {syncing
            ? t('popup.dashboard.syncing', { defaultValue: '同步中...' })
            : (cloudEnabled || webdavEnabled)
              ? t('popup.dashboard.syncNow', { defaultValue: '立即同步' })
              : t('popup.cloud.enableBookmarkSync', { defaultValue: '开启书签云同步' })}
        </Button>

        <div className="space-y-2">
          <SectionLabel>{t('popup.dashboard.syncToolsTitle', { defaultValue: '同步工具' })}</SectionLabel>
          <button
            type="button"
            className="flex min-h-11 w-full items-center gap-3 rounded-[8px] border border-border bg-card px-3 py-2.5 text-left transition-colors hover:bg-accent"
            onClick={onOpenAdvanced}
          >
            <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-[8px] bg-muted text-muted-foreground">
              <RiSlidersFill className="size-4" />
            </span>
            <span className="min-w-0 flex-1 text-sm font-medium leading-5 text-foreground">
              {t('popup.dashboard.advancedOptions', { defaultValue: '高级同步选项' })}
            </span>
            <RiArrowRightSLine className="size-4 shrink-0 text-muted-foreground" />
          </button>
        </div>
      </div>
    </section>
  );
}

function MenuItem({
  icon,
  title,
  description,
  status,
  onClick,
}: {
  icon: ReactNode;
  title: string;
  description: string;
  status?: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      className="flex w-full items-center gap-3 rounded-[8px] border border-border bg-background px-3 py-3 text-left transition-colors hover:bg-accent"
      onClick={onClick}
    >
      <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-[8px] bg-secondary text-foreground">
        {icon}
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-sm font-medium leading-5 text-foreground">{title}</span>
        <span className="mt-0.5 block truncate text-xs leading-4 text-muted-foreground">{description}</span>
      </span>
      {status ? <span className="shrink-0 text-xs leading-5 text-muted-foreground">{status}</span> : null}
      <RiArrowRightSLine className="size-4 shrink-0 text-muted-foreground" />
    </button>
  );
}

function LoggedOutHome({
  webdavState,
  syncRuntime,
  onOpenLogin,
  onOpenWebdav,
  onOpenAdvanced,
}: {
  webdavState: WebdavHomeState;
  syncRuntime: PopupSyncRuntime;
  onOpenLogin: () => void;
  onOpenWebdav: () => void;
  onOpenAdvanced: () => void;
}) {
  const { t } = useTranslation();
  const syncing = syncRuntime.state.topNavSyncStatus === 'syncing';
  const webdavAnalysis = syncRuntime.state.leafTabWebdavSyncAnalysis;
  const localDataLabel = formatBookmarkDataLabel(webdavAnalysis?.localSummary, webdavState.localDataLabel);
  const remoteDataLabel = formatBookmarkDataLabel(webdavAnalysis?.remoteSummary, webdavState.remoteDataLabel);

  return (
    <section className="min-h-[360px] bg-background">
      <header className="px-4 pb-3 pt-4 text-center">
        <div className="mx-auto flex flex-col items-center py-1">
          <div className="flex h-12 w-12 items-center justify-center rounded-full bg-secondary text-muted-foreground">
            <RiUserFill className="size-6" />
          </div>
          <Button
            type="button"
            variant="ghost"
            className="mt-2 h-8 rounded-[8px] px-2 text-sm font-medium text-primary hover:bg-transparent hover:text-primary/80"
            onClick={onOpenLogin}
          >
            {t('popup.profile.loginNow', { defaultValue: '立即登录' })}
          </Button>
        </div>
      </header>

      <div className="space-y-3 px-3 pb-3">
        {!webdavState.configured ? (
          <MenuItem
            icon={<RiHardDrive3Fill className="size-4" />}
            title={t('popup.home.webdavOnlyTitle', { defaultValue: '仅使用 WebDAV 同步' })}
            description={t('popup.home.webdavOnlyDesc', { defaultValue: '配置 WebDAV 后同步浏览器书签' })}
            status={webdavState.statusLabel}
            onClick={onOpenWebdav}
          />
        ) : (
          <>
            <div className="overflow-hidden rounded-[8px] border border-border bg-card">
              <PanelRow
                icon={<RiHardDrive3Fill className="size-4" />}
                title={t('settings.backup.webdav.entry', { defaultValue: 'WebDAV 同步' })}
                status={webdavState.statusLabel}
                onClick={onOpenWebdav}
              />
            </div>

            <div className="space-y-2">
              <SectionLabel>{t('popup.dashboard.syncStatusTitle', { defaultValue: '同步状态' })}</SectionLabel>
              <div className="overflow-hidden rounded-[8px] border border-border bg-card">
                <InfoRow
                  label={t('popup.dashboard.syncStatus', { defaultValue: '同步状态' })}
                  value={resolveSyncStatusLabel(webdavState.enabled, t)}
                />
                <InfoRow
                  label={t('popup.dashboard.lastSync', { defaultValue: '最近同步' })}
                  value={webdavState.lastSyncLabel}
                />
                <InfoRow
                  label={t('popup.dashboard.localData', { defaultValue: '本机数据' })}
                  value={localDataLabel}
                />
                <InfoRow
                  label={t('popup.dashboard.remoteData', { defaultValue: 'WebDAV 数据' })}
                  value={remoteDataLabel}
                />
              </div>
            </div>

            <Button
              type="button"
              className="h-10 w-full rounded-[8px] text-sm font-medium"
              disabled={syncing}
              onClick={() => {
                if (!webdavState.enabled) {
                  onOpenWebdav();
                  return;
                }
                void syncRuntime.actions.handleActiveSyncNowFromCenter();
              }}
            >
              {syncing
                ? t('popup.dashboard.syncing', { defaultValue: '同步中...' })
                : webdavState.enabled
                  ? t('popup.dashboard.syncNow', { defaultValue: '立即同步' })
                  : t('popup.dashboard.enableWebdavSync', { defaultValue: '开启 WebDAV 同步' })}
            </Button>

            <div className="space-y-2">
              <SectionLabel>{t('popup.dashboard.syncToolsTitle', { defaultValue: '同步工具' })}</SectionLabel>
              <button
                type="button"
                className="flex min-h-11 w-full items-center gap-3 rounded-[8px] border border-border bg-card px-3 py-2.5 text-left transition-colors hover:bg-accent"
                onClick={onOpenAdvanced}
              >
                <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-[8px] bg-muted text-muted-foreground">
                  <RiSlidersFill className="size-4" />
                </span>
                <span className="min-w-0 flex-1 text-sm font-medium leading-5 text-foreground">
                  {t('popup.dashboard.advancedOptions', { defaultValue: '高级同步选项' })}
                </span>
                <RiArrowRightSLine className="size-4 shrink-0 text-muted-foreground" />
              </button>
            </div>
          </>
        )}
      </div>
    </section>
  );
}

function PopupHome({
  syncRuntime,
  onLogout,
  onOpenLogin,
  onOpenCloud,
  onOpenWebdav,
  onOpenAdvanced,
  localVersion,
}: {
  syncRuntime: PopupSyncRuntime;
  onLogout: () => void;
  onOpenLogin: () => void;
  onOpenCloud: () => void;
  onOpenWebdav: () => void;
  onOpenAdvanced: () => void;
  localVersion: number;
}) {
  const { t } = useTranslation();
  const configuredHomeState = useMemo(() => readConfiguredHomeState(t), [localVersion, t]);
  const webdavHomeState = useMemo(() => readWebdavHomeState(t), [localVersion, t]);

  if (configuredHomeState) {
    return (
      <ConfiguredHome
        profile={configuredHomeState}
        syncRuntime={syncRuntime}
        onLogout={onLogout}
        onOpenCloud={onOpenCloud}
        onOpenWebdav={onOpenWebdav}
        onOpenAdvanced={onOpenAdvanced}
      />
    );
  }

  return (
    <LoggedOutHome
      webdavState={webdavHomeState}
      syncRuntime={syncRuntime}
      onOpenLogin={onOpenLogin}
      onOpenWebdav={onOpenWebdav}
      onOpenAdvanced={onOpenAdvanced}
    />
  );
}

function LoginQrPage({ onOpenWebdav, onLoggedIn }: { onOpenWebdav: () => void; onLoggedIn: () => void }) {
  const { t } = useTranslation();

  return (
    <section className="flex min-h-[320px] flex-col">
      <LoginQrPanel onLoggedIn={onLoggedIn} />

      <div className="mt-5 px-3 pb-3">
        <MenuItem
          icon={<RiHardDrive3Fill className="size-4" />}
          title={t('popup.home.webdavOnlyTitle', { defaultValue: '仅使用 WebDAV 同步' })}
          description={t('popup.home.webdavOnlyDesc', { defaultValue: '配置 WebDAV 后同步浏览器书签' })}
          onClick={onOpenWebdav}
        />
      </div>
    </section>
  );
}

function AdvancedSection({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <div className="space-y-2">
      <SectionLabel>{title}</SectionLabel>
      {children}
    </div>
  );
}

function AdvancedSyncPage({
  profile,
  syncRuntime,
  onBack,
  onOpenWebdav,
}: {
  profile: ConfiguredHomeState | null;
  syncRuntime: PopupSyncRuntime;
  onBack: () => void;
  onOpenWebdav: () => void;
}) {
  const { t } = useTranslation();
  const syncing = syncRuntime.state.topNavSyncStatus === 'syncing';
  const webdavConfigured = syncRuntime.state.leafTabWebdavConfigured;
  const fallbackProfile = profile ?? {
    nickname: t('popup.profile.defaultNickname', { defaultValue: '请登录' }),
    uid: 'AIRA-0000',
    userId: 'AIRA-0000',
    avatarUri: '',
    identityStatus: t('popup.profile.notSignedIn', { defaultValue: '未登录' }),
    membershipPlan: 'guest',
    membershipStatus: 'missing_profile',
    isDesktopLoggedIn: false,
    lastSyncLabel: t('popup.dashboard.lastSyncPlaceholder', { defaultValue: '6/24/2026, 10:45:55 AM' }),
    localDataLabel: t('popup.dashboard.dataCountPlaceholder', { defaultValue: '723 个文件夹，9212 个书签' }),
    remoteDataLabel: t('popup.dashboard.dataCountPlaceholder', { defaultValue: '723 个文件夹，9212 个书签' }),
    syncStartLabel: t('popup.advanced.syncStartValue', { defaultValue: 'WebDAV 已建立' }),
    webdavEnabled: true,
  };
  const webdavAnalysis = syncRuntime.state.leafTabSyncAnalysisRemoteKind === 'webdav'
    ? syncRuntime.state.leafTabSyncAnalysis
    : null;
  const remoteDataLabel = formatBookmarkDataLabel(webdavAnalysis?.remoteSummary, fallbackProfile.remoteDataLabel);

  const runOverwrite = async (mode: Extract<LeafTabSyncInitialChoice, 'pull-remote' | 'push-local'>) => {
    const confirmed = window.confirm(mode === 'pull-remote'
      ? t('popup.advanced.overwriteLocalConfirm', {
        defaultValue: '将用 WebDAV 数据覆盖本机书签。继续吗？',
      })
      : t('popup.advanced.overwriteRemoteConfirm', {
        defaultValue: '将用本机书签覆盖 WebDAV 数据。继续吗？',
      }));
    if (!confirmed) return;
    await syncRuntime.actions.handleWebdavOverwriteFromCenter(mode);
  };

  return (
    <section className="max-h-[600px] min-h-[520px] overflow-y-auto bg-background">
      <PopupHeader
        title={t('popup.dashboard.advancedOptions', { defaultValue: '高级同步选项' })}
        onBack={onBack}
      />

      <div className="space-y-3 px-3 py-3">
        <AdvancedSection title={t('popup.advanced.currentStatus', { defaultValue: '当前状态' })}>
          <div className="overflow-hidden rounded-[8px] border border-border bg-card">
            <InfoRow
              label={t('popup.advanced.enableMode', { defaultValue: '启用方式' })}
              value={t('popup.advanced.enableModeValue', { defaultValue: 'WebDAV 同步' })}
            />
            <InfoRow
              label={t('popup.advanced.syncStart', { defaultValue: '同步起点' })}
              value={fallbackProfile.syncStartLabel}
            />
            <InfoRow
              label={t('popup.advanced.remoteData', { defaultValue: '远端数据' })}
              value={t('popup.advanced.remoteDataValue', {
                data: remoteDataLabel,
                defaultValue: `WebDAV ${remoteDataLabel}`,
              })}
            />
            <InfoRow
              label={t('popup.dashboard.lastSync', { defaultValue: '最近同步' })}
              value={t('popup.advanced.lastSyncValue', {
                time: fallbackProfile.lastSyncLabel,
                defaultValue: `WebDAV ${fallbackProfile.lastSyncLabel}`,
              })}
            />
          </div>
        </AdvancedSection>

        {!webdavConfigured ? (
          <AdvancedSection title={t('popup.advanced.bookmarkCloudSync', { defaultValue: 'WebDAV 同步' })}>
            <Button
              type="button"
              className="h-10 w-full rounded-[8px]"
              onClick={onOpenWebdav}
            >
              {t('popup.dashboard.enableWebdavSync', { defaultValue: '开启 WebDAV 同步' })}
            </Button>
          </AdvancedSection>
        ) : (
          <>
            <AdvancedSection title={t('popup.advanced.mergeSync', { defaultValue: '合并同步' })}>
              <Button
                type="button"
                className="h-10 w-full rounded-[8px]"
                disabled={syncing}
                onClick={() => void syncRuntime.actions.handleLeafTabSync({ mode: 'merge', allowConfigPrompt: false, requestBookmarkPermission: true })}
              >
                {syncing ? t('popup.dashboard.syncing', { defaultValue: '同步中...' }) : t('popup.advanced.mergeNow', { defaultValue: '立即合并同步' })}
              </Button>
            </AdvancedSection>

            <AdvancedSection title={t('popup.advanced.bookmarkCloudSync', { defaultValue: 'WebDAV 同步' })}>
              <div className="space-y-2">
                <Button
                  type="button"
                  variant="outline"
                  className="h-10 w-full rounded-[8px]"
                  disabled={syncing}
                  onClick={() => void syncRuntime.actions.handleWebdavRefreshAnalysis()}
                >
                  {t('popup.advanced.checkRemoteData', { defaultValue: '检查 WebDAV 数据' })}
                </Button>
                <Button
                  type="button"
                  variant="outline"
                  className="h-10 w-full rounded-[8px]"
                  disabled={syncing}
                  onClick={() => void runOverwrite('push-local')}
                >
                  {t('popup.advanced.overwriteRemote', { defaultValue: '本机覆盖 WebDAV' })}
                </Button>
                <Button
                  type="button"
                  variant="destructive"
                  className="h-10 w-full rounded-[8px]"
                  disabled={syncing}
                  onClick={() => void runOverwrite('pull-remote')}
                >
                  {t('popup.advanced.overwriteLocal', { defaultValue: 'WebDAV 覆盖本机' })}
                </Button>
              </div>
            </AdvancedSection>

            <AdvancedSection title={t('popup.advanced.syncStart', { defaultValue: '同步起点' })}>
              <Button
                type="button"
                variant="outline"
                className="h-10 w-full rounded-[8px]"
                disabled={syncing}
                onClick={() => void syncRuntime.actions.handleLeafTabSync({ mode: 'push-local', allowConfigPrompt: false, requestBookmarkPermission: true })}
              >
                {t('popup.advanced.rebuildSyncStart', { defaultValue: '重建 WebDAV 同步起点' })}
              </Button>
            </AdvancedSection>

            <AdvancedSection title={t('popup.advanced.dangerZone', { defaultValue: '危险操作' })}>
              <Button
                type="button"
                variant="destructive"
                className="h-10 w-full rounded-[8px]"
                disabled
              >
                {t('popup.advanced.clearRemoteRecords', { defaultValue: '清除 WebDAV 同步记录' })}
              </Button>
            </AdvancedSection>
          </>
        )}
      </div>
    </section>
  );
}

function BookmarkCloudPage({
  profile,
  onBack,
  onOpenLogin,
  syncRuntime,
}: {
  profile: ConfiguredHomeState | null;
  onBack: () => void;
  onOpenLogin: () => void;
  syncRuntime: PopupSyncRuntime;
}) {
  const { t } = useTranslation();
  const accountName = syncRuntime.state.leafTabCloudLoggedIn
    ? (profile?.nickname || t('popup.profile.signedIn', { defaultValue: '已登录' }))
    : t('popup.profile.notSignedIn', { defaultValue: '未登录' });
  const membershipLabel = resolveMembershipLabel(profile?.membershipPlan || 'guest', t);
  const syncing = syncRuntime.state.topNavSyncStatus === 'syncing';
  const cloudLoggedIn = syncRuntime.state.leafTabCloudLoggedIn;
  const cloudEnabled = syncRuntime.state.leafTabCloudSyncEnabled;

  return (
    <section className="min-h-[360px] bg-background">
      <PopupHeader
        title={t('popup.dashboard.bookmarkCloudSync', { defaultValue: '书签云同步' })}
        onBack={onBack}
      />

      <div className="space-y-3 px-3 py-3">
        <AdvancedSection title={t('popup.advanced.currentStatus', { defaultValue: '当前状态' })}>
          <div className="overflow-hidden rounded-[8px] border border-border bg-card">
            <InfoRow
              label={t('popup.cloud.account', { defaultValue: '账号' })}
              value={accountName}
            />
            <InfoRow
              label={t('popup.cloud.membership', { defaultValue: '会员' })}
              value={membershipLabel}
            />
            <InfoRow
              label={t('popup.cloud.bookmarkSync', { defaultValue: '书签同步' })}
              value={cloudEnabled
                ? t('popup.dashboard.enabled', { defaultValue: '已开启' })
                : t('popup.dashboard.disabled', { defaultValue: '未开启' })}
            />
          </div>
        </AdvancedSection>

        <Button
          type="button"
          className="h-10 w-full rounded-[8px]"
          disabled={syncing}
          onClick={() => {
            if (!cloudLoggedIn) {
              onOpenLogin();
            } else if (cloudEnabled) {
              void syncRuntime.actions.handleCloudSyncNowFromCenter();
            } else {
              void syncRuntime.actions.handleEnableCloudSync();
            }
          }}
        >
          {syncing
            ? t('popup.dashboard.syncing', { defaultValue: '同步中...' })
            : !cloudLoggedIn
              ? t('popup.cloud.loginAndEnable', { defaultValue: '使用账号登录并开启' })
              : cloudEnabled
                ? t('popup.cloud.resync', { defaultValue: '重新同步' })
                : t('popup.cloud.enableBookmarkSync', { defaultValue: '开启书签云同步' })}
        </Button>

        {cloudEnabled ? (
          <Button
            type="button"
            variant="destructive"
            className="h-10 w-full rounded-[8px]"
            disabled={syncing}
            onClick={() => {
              const confirmed = window.confirm(t('popup.cloud.disableConfirm', {
                defaultValue: '关闭后会停止书签云同步，本机书签不会删除；WebDAV 同步不会受到影响。继续吗？',
              }));
              if (confirmed) {
                void syncRuntime.actions.handleDisableCloudSync();
              }
            }}
          >
            {t('popup.cloud.disableBookmarkSync', { defaultValue: '关闭书签云同步' })}
          </Button>
        ) : null}
      </div>
    </section>
  );
}

function PopupHeader({
  title,
  onBack,
}: {
  title: string;
  onBack: () => void;
}) {
  const { t } = useTranslation();

  return (
    <header className="flex h-12 items-center gap-2 border-b border-border px-2">
      <button
        type="button"
        className="flex h-9 w-9 items-center justify-center rounded-[8px] text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
        onClick={onBack}
        aria-label={t('common.back', { defaultValue: '返回' })}
        title={t('common.back', { defaultValue: '返回' })}
      >
        <RiArrowLeftSLine className="size-5" />
      </button>
      <h1 className="min-w-0 truncate text-sm font-semibold text-foreground">{title}</h1>
    </header>
  );
}

function NativeField({
  label,
  children,
}: {
  label: string;
  children: ReactNode;
}) {
  return (
    <div className="space-y-1.5">
      <Label className="text-xs font-medium text-muted-foreground">{label}</Label>
      {children}
    </div>
  );
}

function WebdavProviderIcon({ provider }: { provider: WebdavProviderOption }) {
  return (
    <span className="flex h-8 w-8 shrink-0 items-center justify-center overflow-hidden rounded-[8px] bg-secondary">
      <img
        src={provider.iconUrl}
        alt=""
        className="h-6 w-6 object-contain"
      />
    </span>
  );
}

function WebdavProviderPickerPage({
  providers,
  selectedProviderId,
  onSelect,
  onBack,
}: {
  providers: WebdavProviderOption[];
  selectedProviderId: string;
  onSelect: (providerId: string) => void;
  onBack: () => void;
}) {
  const { t } = useTranslation();

  return (
    <section className="min-h-[520px] bg-background">
      <PopupHeader
        title={t('settings.backup.webdav.providerLabel', { defaultValue: 'WebDAV 服务商' })}
        onBack={onBack}
      />

      <div className="px-4 py-4">
        <div className="overflow-hidden rounded-[8px] border border-border bg-card">
          {providers.map((item) => {
            const selected = item.id === selectedProviderId;
            return (
              <button
                key={item.id}
                type="button"
                className="flex min-h-14 w-full items-center gap-3 border-b border-border px-3 py-2.5 text-left transition-colors last:border-b-0 hover:bg-accent/70"
                onClick={() => onSelect(item.id)}
              >
                <WebdavProviderIcon provider={item} />
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-sm font-medium leading-5 text-foreground">{item.label}</span>
                  {item.url ? (
                    <span className="mt-0.5 block truncate text-xs leading-4 text-muted-foreground">{item.url}</span>
                  ) : null}
                </span>
                {selected ? <RiCheckFill className="size-4 shrink-0 text-primary" /> : null}
              </button>
            );
          })}
        </div>
      </div>
    </section>
  );
}

function WebdavConfigPage({
  syncRuntime,
  onBack,
  onSaved,
}: {
  syncRuntime: PopupSyncRuntime;
  onBack: () => void;
  onSaved: (options?: { syncAfterSave?: boolean }) => void;
}) {
  const { t } = useTranslation();
  const [provider, setProvider] = useState('custom');
  const [url, setUrl] = useState('');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [saving, setSaving] = useState(false);
  const [showProviderPicker, setShowProviderPicker] = useState(false);
  const syncing = syncRuntime.state.topNavSyncStatus === 'syncing' || saving;
  const hasConfig = url.trim().length > 0 && username.trim().length > 0 && password.length > 0;
  const isEnabled = readWebdavStorageStateFromStorage(t('settings.backup.webdav.defaultProfileName', { defaultValue: '默认配置' })).syncEnabled && url.trim().length > 0;

  const providers = useMemo<WebdavProviderOption[]>(() => ([
    {
      id: 'custom',
      label: t('settings.backup.webdav.providerCustom', { defaultValue: '自定义服务' }),
      iconUrl: '/webdav-providers/webdav_provider_custom.svg',
    },
    {
      id: 'jianguoyun',
      label: t('settings.backup.webdav.providers.jianguoyun', { defaultValue: '坚果云' }),
      url: 'https://dav.jianguoyun.com/dav/',
      iconUrl: '/webdav-providers/webdav_provider_jianguoyun.svg',
    },
    {
      id: 'pcloud-us',
      label: 'pCloud (US)',
      url: 'https://webdav.pcloud.com/',
      iconUrl: '/webdav-providers/webdav_provider_pcloud_us.svg',
    },
    {
      id: 'pcloud-eu',
      label: 'pCloud (EU)',
      url: 'https://ewebdav.pcloud.com/',
      iconUrl: '/webdav-providers/webdav_provider_pcloud_eu.svg',
    },
    {
      id: 'gmx-mediacenter',
      label: 'GMX MediaCenter',
      url: 'https://webdav.mc.gmx.net/',
      iconUrl: '/webdav-providers/webdav_provider_gmx_mediacenter.svg',
    },
    {
      id: 'kdrive',
      label: 'kDrive',
      url: 'https://IDkDrive.connect.kdrive.infomaniak.com/',
      iconUrl: '/webdav-providers/webdav_provider_kdrive.svg',
    },
    {
      id: 'koofr',
      label: 'Koofr',
      url: 'https://app.koofr.net/dav/Koofr/',
      iconUrl: '/webdav-providers/webdav_provider_koofr.svg',
    },
  ]), [t]);

  const selectedProvider = useMemo(() => {
    return providers.find((item) => item.id === provider) ?? {
      id: 'custom',
      label: t('settings.backup.webdav.providerCustom', { defaultValue: '自定义服务' }),
      iconUrl: '/webdav-providers/webdav_provider_custom.svg',
    };
  }, [provider, providers]);

  useEffect(() => {
    const saved = readWebdavStorageStateFromStorage(t('settings.backup.webdav.defaultProfileName', { defaultValue: '默认配置' }));
    setUrl(saved.url);
    setUsername(saved.username);
    setPassword(saved.password);
    const normalizeUrl = (value: string | undefined) => (value || '').trim().replace(/\/+$/, '');
    const matchedProvider = providers.find((item) => normalizeUrl(item.url) === normalizeUrl(saved.url));
    setProvider(matchedProvider?.id || 'custom');
  }, [providers, t]);

  const handleProviderChange = (nextProvider: string) => {
    setProvider(nextProvider);
    const selectedProvider = providers.find((item) => item.id === nextProvider);
    if (selectedProvider?.url) {
      setUrl(selectedProvider.url);
    }
    setShowProviderPicker(false);
  };

  const saveWebdavConfig = async (activate: boolean) => {
    const trimmedUrl = url.trim();
    if (!trimmedUrl) {
      toast.error(t('settings.backup.webdav.urlRequired', { defaultValue: '请输入 WebDAV 地址' }));
      return;
    }

    setSaving(true);
    try {
      if (activate) {
        const granted = await ensureOriginPermission(trimmedUrl, { requestIfNeeded: true }).catch(() => false);
        if (!granted) {
          toast.error(t('settings.backup.webdav.originPermissionDenied', {
            defaultValue: '未授予 WebDAV 站点访问权限，无法启用同步。',
          }));
          return;
        }
      }

      const current = readWebdavStorageStateFromStorage(t('settings.backup.webdav.defaultProfileName', { defaultValue: '默认配置' }));
      writeWebdavStorageStateToStorage({
        ...current,
        url: trimmedUrl,
        username,
        password,
        syncEnabled: activate,
        syncBookmarksEnabled: true,
        syncBySchedule: current.syncBySchedule ?? WEBDAV_DEFAULT_SYNC_BY_SCHEDULE,
        autoSyncToastEnabled: current.autoSyncToastEnabled,
        syncIntervalMinutes: current.syncIntervalMinutes || WEBDAV_DEFAULT_SYNC_INTERVAL_MINUTES,
      }, t('settings.backup.webdav.defaultProfileName', { defaultValue: '默认配置' }));
      window.dispatchEvent(new CustomEvent('webdav-config-changed'));
      window.dispatchEvent(new CustomEvent('webdav-sync-status-changed'));
      toast.success(t('settings.backup.webdav.configSaved', { defaultValue: 'WebDAV 配置已保存' }));
    } finally {
      setSaving(false);
    }
  };

  const handlePrimaryAction = async () => {
    await saveWebdavConfig(true);
    onSaved({ syncAfterSave: true });
  };

  const handleDisable = async () => {
    const confirmed = window.confirm(t('settings.backup.webdav.disableConfirm', {
      defaultValue: '关闭后会停止通过 WebDAV 同步书签，本机书签和已填写的 WebDAV 配置不会删除。',
    }));
    if (!confirmed) return;
    await saveWebdavConfig(false);
    toast.success(t('settings.backup.webdav.disabledToast', { defaultValue: '已关闭 WebDAV 同步' }));
    onSaved();
  };

  const primaryActionTitle = syncing
    ? (isEnabled
      ? t('settings.backup.webdav.syncingAction', { defaultValue: '正在同步 WebDAV' })
      : t('settings.backup.webdav.enablingAction', { defaultValue: '正在启用 WebDAV 同步' }))
    : (isEnabled
      ? t('settings.backup.webdav.syncNowAction', { defaultValue: '立即同步' })
      : t('settings.backup.webdav.enableSyncAction', { defaultValue: '启用 WebDAV 同步' }));

  if (showProviderPicker) {
    return (
      <WebdavProviderPickerPage
        providers={providers}
        selectedProviderId={provider}
        onSelect={handleProviderChange}
        onBack={() => setShowProviderPicker(false)}
      />
    );
  }

  return (
    <section className="min-h-[520px] bg-background">
      <PopupHeader
        title={t('settings.backup.webdav.entry', { defaultValue: 'WebDAV 同步' })}
        onBack={onBack}
      />

      <div className="space-y-4 px-4 py-4">
        <div className="overflow-hidden rounded-[8px] border border-border bg-card">
          <button
            type="button"
            className="flex min-h-12 w-full items-center gap-3 px-3 py-2.5 text-left transition-colors hover:bg-accent/70"
            onClick={() => setShowProviderPicker(true)}
          >
            <span className="min-w-0 flex-1 text-sm font-medium leading-5 text-foreground">
              {t('settings.backup.webdav.providerLabel', { defaultValue: 'WebDAV 服务商' })}
            </span>
            <span className="max-w-[120px] truncate text-sm leading-5 text-muted-foreground">
              {selectedProvider.label}
            </span>
            <RiArrowRightSLine className="size-4 shrink-0 text-muted-foreground" />
          </button>
        </div>

        <NativeField label={t('settings.backup.webdav.url', { defaultValue: 'WebDAV 地址' })}>
          <Input
            value={url}
            onChange={(event) => setUrl(event.target.value)}
            placeholder="https://example.com/dav"
            className="h-10 rounded-[8px]"
          />
        </NativeField>

        <NativeField label={t('settings.backup.webdav.username', { defaultValue: '用户名' })}>
          <Input
            value={username}
            onChange={(event) => setUsername(event.target.value)}
            placeholder={t('settings.backup.webdav.usernamePlaceholder', { defaultValue: '可选' })}
            className="h-10 rounded-[8px]"
          />
        </NativeField>

        <NativeField label={t('settings.backup.webdav.password', { defaultValue: '密码' })}>
          <div className="relative">
            <Input
              type={showPassword ? 'text' : 'password'}
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              placeholder={t('settings.backup.webdav.passwordPlaceholder', { defaultValue: '可选' })}
              className="h-10 rounded-[8px] pr-10"
            />
            <button
              type="button"
              className="absolute right-1 top-1/2 flex h-8 w-8 -translate-y-1/2 items-center justify-center rounded-[8px] text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
              onClick={() => setShowPassword((value) => !value)}
              aria-label={showPassword
                ? t('popup.webdav.hidePassword', { defaultValue: '隐藏密码' })
                : t('popup.webdav.showPassword', { defaultValue: '显示密码' })}
              title={showPassword
                ? t('popup.webdav.hidePassword', { defaultValue: '隐藏密码' })
                : t('popup.webdav.showPassword', { defaultValue: '显示密码' })}
            >
              {showPassword ? <RiEyeOffFill className="size-4" /> : <RiEyeFill className="size-4" />}
            </button>
          </div>
        </NativeField>
      </div>

      <div className="border-t border-border px-4 py-3">
        <Button
          type="button"
          className="h-10 w-full rounded-[8px]"
          disabled={syncing || !hasConfig}
          onClick={() => void handlePrimaryAction()}
        >
          {primaryActionTitle}
        </Button>
        {isEnabled ? (
          <Button
            type="button"
            variant="outline"
            className="mt-3 h-10 w-full rounded-[8px] text-destructive hover:text-destructive"
            disabled={syncing}
            onClick={() => void handleDisable()}
          >
            {t('settings.backup.webdav.disableSyncAction', { defaultValue: '关闭 WebDAV 同步' })}
          </Button>
        ) : null}
      </div>
    </section>
  );
}

export function PopupApp() {
  const [view, setView] = useState<PopupView>('home');
  const [leafTabSyncDialogOpen, setLeafTabSyncDialogOpen] = useState(true);
  const [localVersion, setLocalVersion] = useState(0);
  const [pendingWebdavSyncAfterSave, setPendingWebdavSyncAfterSave] = useState(false);
  const { t } = useTranslation();
  const syncRuntime = useLeafTabSyncRuntimeController({
    setWebdavDialogOpen: (open) => {
      if (open) setView('webdav');
    },
    setLeafTabSyncDialogOpen,
    leafTabSyncDialogOpen,
    setWebdavEnableAfterConfigSave: () => {},
    setWebdavShowConnectionFields: () => {},
    setSyncConfigBackTarget: () => {},
    isDragging: false,
  });
  const configuredHomeState = useMemo(() => {
    void localVersion;
    return readConfiguredHomeState(t);
  }, [localVersion, t]);

  useEffect(() => {
    const refresh = () => setLocalVersion((value) => value + 1);
    window.addEventListener('webdav-config-changed', refresh);
    window.addEventListener('webdav-sync-status-changed', refresh);
    return () => {
      window.removeEventListener('webdav-config-changed', refresh);
      window.removeEventListener('webdav-sync-status-changed', refresh);
    };
  }, []);

  useEffect(() => {
    if (!pendingWebdavSyncAfterSave || !syncRuntime.state.leafTabSyncHasConfig) return;
    setPendingWebdavSyncAfterSave(false);
    void syncRuntime.actions.handleWebdavSyncNowFromCenter();
  }, [
    pendingWebdavSyncAfterSave,
    syncRuntime.actions,
    syncRuntime.state.leafTabSyncHasConfig,
  ]);

  return (
    <main className="w-[360px] max-w-full overflow-hidden bg-background text-foreground [font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe_UI',sans-serif]">
      {view === 'home' && (
        <PopupHome
          syncRuntime={syncRuntime}
          localVersion={localVersion}
          onLogout={() => {
            clearAiraDesktopLoginProfile();
            setLocalVersion((value) => value + 1);
            toast.success(t('popup.profile.loggedOut', { defaultValue: '已退出登录' }));
          }}
          onOpenLogin={() => setView('login')}
          onOpenCloud={() => setView('cloud')}
          onOpenWebdav={() => setView('webdav')}
          onOpenAdvanced={() => setView('advanced')}
        />
      )}
      {view === 'webdav' && (
        <WebdavConfigPage
          syncRuntime={syncRuntime}
          onBack={() => setView('home')}
          onSaved={(options) => {
            setLocalVersion((value) => value + 1);
            setPendingWebdavSyncAfterSave(Boolean(options?.syncAfterSave));
            setView('home');
          }}
        />
      )}
      {view === 'advanced' && (
        <AdvancedSyncPage
          profile={configuredHomeState}
          syncRuntime={syncRuntime}
          onBack={() => setView('home')}
          onOpenWebdav={() => setView('webdav')}
        />
      )}
      {view === 'cloud' && (
        <BookmarkCloudPage
          profile={configuredHomeState}
          onBack={() => setView('home')}
          onOpenLogin={() => setView('login')}
          syncRuntime={syncRuntime}
        />
      )}
      {view === 'login' && (
        <LoginQrPage
          onOpenWebdav={() => setView('webdav')}
          onLoggedIn={() => {
            setLocalVersion((value) => value + 1);
            setView('home');
          }}
        />
      )}
      <FirstSyncChoiceDialog syncRuntime={syncRuntime} />
      <SyncProgressDialog syncRuntime={syncRuntime} />
    </main>
  );
}
