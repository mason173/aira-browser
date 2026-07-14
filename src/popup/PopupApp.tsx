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
import { SyncToggleField } from '@/components/sync/SyncSettingsFields';
import { useBookmarkSyncRuntimeController } from '@/features/sync/bookmarks/useBookmarkSyncRuntimeController';
import type { LeafTabSyncFacade } from '@/features/sync/app/LeafTabSyncContracts';
import { AIRA_CLOUD_SYNC_ENABLED_KEY } from '@/features/sync/app/leafTabSyncStorageKeys';
import QRCodeStyling from 'qr-code-styling';
import {
  RiArrowLeftSLine,
  RiArrowRightSLine,
  RiCheckFill,
  RiCloudFill,
  RiEyeFill,
  RiEyeOffFill,
  RiHardDrive3Fill,
  RiLoaderLine,
  RiLogoutBoxRLine,
  RiMoreFill,
  RiSlidersFill,
  RiUserFill,
} from '@/icons/ri-compat';
import { ensureOriginPermission } from '@/utils/extensionPermissions';
import {
  readWebdavStorageStateFromStorage,
  writeWebdavStorageStateToStorage,
} from '@/utils/webdavConfig';
import { writeExtensionStorageRecord } from '@/platform/extensionStorage';
import {
  readPhonePagePushEnabledFromLocalStorage,
  writePhonePagePushEnabled,
} from '@/features/phone-page-push/pagePushPreferences';
import {
  clearAiraDesktopLoginProfile,
  createAiraDesktopLoginSession,
  isAiraDesktopProfilePro,
  pollAiraDesktopLoginStatus,
  readAiraDesktopLoginProfile,
  refreshAiraDesktopMembershipProfile,
  writeAiraDesktopLoginProfile,
  type AiraDesktopLoginSession,
} from './desktopLogin';

type PopupView = 'home' | 'webdav' | 'sync-method' | 'advanced' | 'login';

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
  membershipExpiresAt: number;
  isDesktopLoggedIn: boolean;
  phonePagePushEnabled: boolean;
};

type PopupSyncRuntime = Pick<LeafTabSyncFacade, 'state' | 'actions'>;

const disableProOnlyLocalFeatures = () => {
  writePhonePagePushEnabled(false);
  localStorage.setItem(AIRA_CLOUD_SYNC_ENABLED_KEY, 'false');
  void writeExtensionStorageRecord({
    [AIRA_CLOUD_SYNC_ENABLED_KEY]: 'false',
  });
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
      const isPro = isAiraDesktopProfilePro(desktopLoginProfile);
      const phonePagePushEnabled = isPro && readPhonePagePushEnabledFromLocalStorage();
      return {
        nickname: desktopLoginProfile.displayName,
        uid: desktopLoginProfile.uidSuffix ? `AIRA-${desktopLoginProfile.uidSuffix}` : getShortUid(desktopLoginProfile.uid),
        userId: desktopLoginProfile.uid,
        avatarUri: desktopLoginProfile.avatarUri,
        identityStatus: t('popup.profile.signedIn', { defaultValue: '已登录' }),
        membershipPlan: desktopLoginProfile.membershipPlan,
        membershipExpiresAt: desktopLoginProfile.membershipExpiresAt,
        isDesktopLoggedIn: true,
        phonePagePushEnabled,
      };
    }
    return null;
  } catch {
    return null;
  }
}

async function refreshAndRequirePro(t: ReturnType<typeof useTranslation>['t']) {
  try {
    const latestProfile = await refreshAiraDesktopMembershipProfile(readAiraDesktopLoginProfile(), { force: true });
    if (isAiraDesktopProfilePro(latestProfile)) {
      return true;
    }
    disableProOnlyLocalFeatures();
    toast.error(t('popup.profile.proRequired', { defaultValue: '此功能需要 Aira Pro' }));
    return false;
  } catch {
    toast.error(t('popup.profile.membershipCheckFailed', { defaultValue: '会员状态校验失败，请稍后再试' }));
    return false;
  }
}

function isConfiguredHomeStatePro(profile: ConfiguredHomeState | null): boolean {
  if ((profile?.membershipPlan || '').trim().toLowerCase() !== 'pro') {
    return false;
  }
  const expiresAt = Number(profile?.membershipExpiresAt || 0);
  return expiresAt === 0 || expiresAt > Date.now();
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

function SyncProgressDialog({ syncRuntime }: { syncRuntime: PopupSyncRuntime }) {
  const { t } = useTranslation();
  const progress = syncRuntime.state.leafTabSyncProgress;
  const lastResult = syncRuntime.state.leafTabSyncLastResult;
  const pendingConflict = syncRuntime.state.leafTabPendingBookmarkConflict;
  const isConflict = Boolean(pendingConflict || lastResult?.kind === 'conflict') && !progress.inProgress;
  const conflictCount = lastResult?.kind === 'conflict'
    ? lastResult.mergeResult?.conflicts.length || 0
    : 0;
  const conflictRemoteKind = progress.remoteKind === 'aira-cloud' || progress.remoteKind === 'webdav'
    ? progress.remoteKind
    : pendingConflict?.provider || syncRuntime.state.leafTabSelectedSyncSource || 'webdav';
  const conflictRemoteLabel = conflictRemoteKind === 'aira-cloud'
    ? t('popup.progress.cloudRemote', { defaultValue: 'Aira 云端' })
    : t('popup.progress.webdavRemote', { defaultValue: 'WebDAV' });
  const resolveConflict = (choice: 'computer' | 'current-source') => {
    void syncRuntime.actions.handleResolveBookmarkConflict(choice);
  };

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
          <div className="flex flex-col items-center gap-4 py-2 text-center">
            {progress.inProgress ? (
              <RiLoaderLine
                aria-hidden="true"
                className="h-10 w-10 animate-spin text-primary"
                strokeWidth={2.2}
              />
            ) : isConflict ? (
              <RiSlidersFill
                aria-hidden="true"
                className="h-10 w-10 text-primary"
                strokeWidth={2.2}
              />
            ) : (
              <RiCheckFill
                aria-hidden="true"
                className="h-10 w-10 text-primary"
                strokeWidth={2.2}
              />
            )}
            <p className="text-sm font-medium leading-6 text-foreground">{progress.detail}</p>
          </div>
          {isConflict ? (
            <div className="grid gap-2">
              <p className="text-xs leading-5 text-muted-foreground">
                {conflictCount > 0
                  ? t('popup.progress.conflictHelpWithCount', {
                      count: conflictCount,
                      remote: conflictRemoteLabel,
                      defaultValue: `检测到 ${conflictCount} 处双向修改。非冲突内容会继续合并，请选择冲突部分以电脑还是 ${conflictRemoteLabel} 为准。`,
                    })
                  : t('popup.progress.conflictHelp', {
                      remote: conflictRemoteLabel,
                      defaultValue: `非冲突内容会继续合并，请选择冲突部分以电脑还是 ${conflictRemoteLabel} 为准。`,
                    })}
              </p>
              <Button
                type="button"
                className="h-10 w-full rounded-[8px]"
                onClick={() => resolveConflict('computer')}
              >
                {t('popup.progress.keepLocal', {
                  remote: conflictRemoteLabel,
                  defaultValue: '电脑书签优先',
                })}
              </Button>
              <Button
                type="button"
                variant="outline"
                className="h-10 w-full rounded-[8px]"
                onClick={() => resolveConflict('current-source')}
              >
                {t('popup.progress.useRemote', {
                  remote: conflictRemoteLabel,
                  defaultValue: '当前同步来源优先',
                })}
              </Button>
              <Button
                type="button"
                variant="ghost"
                className="h-10 w-full rounded-[8px]"
                onClick={() => syncRuntime.actions.handleDismissSyncProgress()}
              >
                {t('popup.progress.later', { defaultValue: '稍后处理' })}
              </Button>
            </div>
          ) : !progress.inProgress ? (
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
              const confirmedProfile = {
                ...result.account,
                desktopPushToken: nextSession.desktopPushToken,
                membershipCheckedAt: new Date().toISOString(),
                loggedInAt: new Date().toISOString(),
              };
              writeAiraDesktopLoginProfile(confirmedProfile);
              if (isAiraDesktopProfilePro(confirmedProfile)) {
                writePhonePagePushEnabled(true);
                window.dispatchEvent(new CustomEvent('phone-page-push-setting-changed'));
              }
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

function BookmarkSyncControls({
  syncRuntime,
  onSelectCloud,
  onOpenWebdav,
  onOpenSyncMethod,
  onOpenAdvanced,
}: {
  syncRuntime: PopupSyncRuntime;
  onSelectCloud: () => void;
  onOpenWebdav: () => void;
  onOpenSyncMethod: () => void;
  onOpenAdvanced: () => void;
}) {
  const { t } = useTranslation();
  const selectedSource = syncRuntime.state.leafTabSelectedSyncSource;
  const syncing = syncRuntime.state.topNavSyncStatus === 'syncing';
  const sourceLabel = selectedSource === 'aira-cloud' ? 'Aira 云同步' : 'WebDAV';
  const statusLabel = selectedSource === 'aira-cloud' && !syncRuntime.state.leafTabCloudLoggedIn
    ? t('popup.dashboard.loginRequired', { defaultValue: '需要重新登录 Aira' })
    : selectedSource === 'aira-cloud' && syncRuntime.state.leafTabCloudSyncStatus === 'pro-required'
      ? t('popup.dashboard.proRequired', { defaultValue: '需要有效的 Aira Pro' })
      : selectedSource === 'aira-cloud' && syncRuntime.state.leafTabCloudSyncStatus === 'disabled'
        ? t('popup.dashboard.disabledStatus', { defaultValue: '同步未启用' })
      : selectedSource === 'webdav' && !syncRuntime.state.leafTabWebdavConfigured
        ? t('popup.dashboard.webdavConfigRequired', { defaultValue: '需要配置 WebDAV' })
        : syncRuntime.state.topNavSyncStatus === 'conflict'
          ? t('popup.dashboard.conflictStatus', { defaultValue: '需要处理冲突' })
          : syncRuntime.state.topNavSyncStatus === 'error'
            ? t('popup.dashboard.errorStatus', { defaultValue: '同步已暂停，请检查配置' })
            : syncing
              ? t('popup.dashboard.syncing', { defaultValue: '同步中...' })
              : t('popup.dashboard.autoSyncEnabled', { defaultValue: '自动同步已开启' });
  const lastSyncLabel = selectedSource === 'aira-cloud'
    ? syncRuntime.state.leafTabCloudLastSyncLabel
    : syncRuntime.state.leafTabWebdavLastSyncLabel;
  const formatDataSummary = (summary: typeof syncRuntime.state.leafTabLocalSummary) => {
    if (syncRuntime.state.leafTabSummaryLoading && !summary) return '读取中...';
    if (!summary) return '尚未读取';
    return `${summary.bookmarkFolders} 个文件夹 · ${summary.bookmarkItems} 个书签`;
  };

  if (!selectedSource) {
    return (
      <div className="space-y-2">
        <SectionLabel>{t('popup.dashboard.chooseSyncMethod', { defaultValue: '选择书签同步方式' })}</SectionLabel>
        <MenuItem
          icon={<RiCloudFill className="size-4" />}
          title="Aira 云同步"
          description={t('popup.home.cloudDesc', { defaultValue: '需要 Aira 桌面登录和 Pro 权限' })}
          status="PRO"
          onClick={onSelectCloud}
        />
        <MenuItem
          icon={<RiHardDrive3Fill className="size-4" />}
          title="WebDAV"
          description={t('popup.home.webdavOnlyDesc', { defaultValue: '无需 Aira 登录，所有用户均可使用' })}
          onClick={onOpenWebdav}
        />
      </div>
    );
  }

  return (
    <div className="space-y-3">
      <div className="overflow-hidden rounded-[8px] border border-border bg-card">
        <PanelRow
          icon={selectedSource === 'aira-cloud'
            ? <RiCloudFill className="size-4" />
            : <RiHardDrive3Fill className="size-4" />}
          title={t('popup.dashboard.currentSyncMethod', { defaultValue: '当前同步方式' })}
          badge={selectedSource === 'aira-cloud' ? 'PRO' : undefined}
          status={sourceLabel}
          onClick={onOpenSyncMethod}
        />
      </div>

      <div className="space-y-2">
        <SectionLabel>{t('popup.dashboard.syncStatusTitle', { defaultValue: '同步状态' })}</SectionLabel>
        <div className="overflow-hidden rounded-[8px] border border-border bg-card">
          <InfoRow label={t('popup.dashboard.syncStatus', { defaultValue: '同步状态' })} value={statusLabel} />
          <InfoRow
            label={t('popup.dashboard.lastSync', { defaultValue: '最近同步' })}
            value={lastSyncLabel || t('popup.dashboard.neverSynced', { defaultValue: '尚未同步' })}
          />
          <InfoRow
            label={t('popup.dashboard.localData', { defaultValue: '本机数据' })}
            value={formatDataSummary(syncRuntime.state.leafTabLocalSummary)}
          />
          <InfoRow
            label={selectedSource === 'aira-cloud'
              ? t('popup.dashboard.cloudData', { defaultValue: '云端数据' })
              : t('popup.dashboard.webdavData', { defaultValue: 'WebDAV 数据' })}
            value={formatDataSummary(syncRuntime.state.leafTabRemoteSummary)}
          />
        </div>
      </div>

      <Button
        type="button"
        className="h-10 w-full rounded-[8px] text-sm font-medium"
        disabled={syncing}
        onClick={() => void syncRuntime.actions.handleActiveSyncNowFromCenter()}
      >
        {syncing
          ? t('popup.dashboard.syncing', { defaultValue: '同步中...' })
          : t('popup.dashboard.syncNow', { defaultValue: '立即同步' })}
      </Button>

      <Button
        type="button"
        variant="outline"
        className="h-10 w-full rounded-[8px] text-sm font-medium"
        disabled={syncing}
        onClick={onOpenSyncMethod}
      >
        {t('popup.dashboard.changeSyncMethod', { defaultValue: '更改同步方式' })}
      </Button>

      <div className="space-y-2">
        <SectionLabel>{t('popup.dashboard.syncToolsTitle', { defaultValue: '同步工具' })}</SectionLabel>
        <MenuItem
          icon={<RiSlidersFill className="size-4" />}
          title={t('popup.dashboard.advancedOptions', { defaultValue: '高级同步选项' })}
          description={t('popup.advanced.autoSyncDiagnosticsDesc', {
            defaultValue: '查看自动检查计划与最近错误',
          })}
          onClick={onOpenAdvanced}
        />
      </div>
    </div>
  );
}

function ConfiguredHome({
  profile,
  syncRuntime,
  onLogout,
  onSelectCloud,
  onOpenWebdav,
  onOpenSyncMethod,
  onOpenAdvanced,
}: {
  profile: ConfiguredHomeState;
  syncRuntime: PopupSyncRuntime;
  onLogout: () => void;
  onSelectCloud: () => void;
  onOpenWebdav: () => void;
  onOpenSyncMethod: () => void;
  onOpenAdvanced: () => void;
}) {
  const { t } = useTranslation();
  return (
    <section className="min-h-[480px] bg-background">
      <ProfileHeader profile={profile} onLogout={onLogout} />
      <div className="space-y-3 px-3 pb-3">
        <BookmarkSyncControls
          syncRuntime={syncRuntime}
          onSelectCloud={onSelectCloud}
          onOpenWebdav={onOpenWebdav}
          onOpenSyncMethod={onOpenSyncMethod}
          onOpenAdvanced={onOpenAdvanced}
        />

        <div className="space-y-2">
          <SectionLabel>{t('popup.profile.accountInfo', { defaultValue: '账号信息' })}</SectionLabel>
          <div className="overflow-hidden rounded-[8px] border border-border bg-card">
            <InfoRow label={t('popup.profile.userId', { defaultValue: '用户ID' })} value={profile.userId || profile.uid} />
            <InfoRow label={t('popup.profile.identityStatus', { defaultValue: '身份状态' })} value={profile.identityStatus} />
            <InfoRow
              label={t('popup.profile.membershipType', { defaultValue: '会员类型' })}
              value={resolveMembershipLabel(profile.membershipPlan, t)}
            />
          </div>
        </div>

        <div className="space-y-2">
          <SectionLabel>{t('popup.dashboard.phonePushTitle', { defaultValue: '手机联动' })}</SectionLabel>
          <div className="overflow-hidden rounded-[8px] border border-border bg-card px-3 py-2">
            <SyncToggleField
              label={t('popup.dashboard.phonePushEnabled', { defaultValue: '接收手机网页推送' })}
              description={isConfiguredHomeStatePro(profile)
                ? t('popup.dashboard.phonePushDesc', {
                    defaultValue: '开启后，这台电脑浏览器会自动接收并打开手机推送的当前网页。',
                  })
                : t('popup.dashboard.phonePushProDesc', {
                    defaultValue: '接收手机网页推送是 Aira Pro 功能，开通后可用。',
                  })}
              checked={profile.phonePagePushEnabled}
              disabled={!isConfiguredHomeStatePro(profile)}
              onCheckedChange={async (enabled) => {
                if (enabled && !(await refreshAndRequirePro(t))) {
                  window.dispatchEvent(new CustomEvent('phone-page-push-setting-changed'));
                  return;
                }
                writePhonePagePushEnabled(enabled);
                window.dispatchEvent(new CustomEvent('phone-page-push-setting-changed'));
              }}
            />
          </div>
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
  syncRuntime,
  onOpenLogin,
  onSelectCloud,
  onOpenWebdav,
  onOpenSyncMethod,
  onOpenAdvanced,
}: {
  syncRuntime: PopupSyncRuntime;
  onOpenLogin: () => void;
  onSelectCloud: () => void;
  onOpenWebdav: () => void;
  onOpenSyncMethod: () => void;
  onOpenAdvanced: () => void;
}) {
  const { t } = useTranslation();

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
        <BookmarkSyncControls
          syncRuntime={syncRuntime}
          onSelectCloud={onSelectCloud}
          onOpenWebdav={onOpenWebdav}
          onOpenSyncMethod={onOpenSyncMethod}
          onOpenAdvanced={onOpenAdvanced}
        />
      </div>
    </section>
  );
}

function PopupHome({
  syncRuntime,
  onLogout,
  onOpenLogin,
  onSelectCloud,
  onOpenWebdav,
  onOpenSyncMethod,
  onOpenAdvanced,
  localVersion,
}: {
  syncRuntime: PopupSyncRuntime;
  onLogout: () => void;
  onOpenLogin: () => void;
  onSelectCloud: () => void;
  onOpenWebdav: () => void;
  onOpenSyncMethod: () => void;
  onOpenAdvanced: () => void;
  localVersion: number;
}) {
  const { t } = useTranslation();
  const configuredHomeState = useMemo(() => readConfiguredHomeState(t), [localVersion, t]);

  if (configuredHomeState) {
    return (
      <ConfiguredHome
        profile={configuredHomeState}
        syncRuntime={syncRuntime}
        onLogout={onLogout}
        onSelectCloud={onSelectCloud}
        onOpenWebdav={onOpenWebdav}
        onOpenSyncMethod={onOpenSyncMethod}
        onOpenAdvanced={onOpenAdvanced}
      />
    );
  }

  return (
    <LoggedOutHome
      syncRuntime={syncRuntime}
      onOpenLogin={onOpenLogin}
      onSelectCloud={onSelectCloud}
      onOpenWebdav={onOpenWebdav}
      onOpenSyncMethod={onOpenSyncMethod}
      onOpenAdvanced={onOpenAdvanced}
    />
  );
}

function AdvancedSettingsPage({
  syncRuntime,
  onBack,
}: {
  syncRuntime: PopupSyncRuntime;
  onBack: () => void;
}) {
  const { t } = useTranslation();
  return (
    <section className="min-h-[360px] bg-background">
      <PopupHeader
        title={t('popup.dashboard.advancedOptions', { defaultValue: '高级同步选项' })}
        onBack={onBack}
      />
      <div className="space-y-2 px-3 py-3">
        <SectionLabel>
          {t('popup.advanced.autoSyncDiagnostics', { defaultValue: '自动同步诊断' })}
        </SectionLabel>
        <div className="overflow-hidden rounded-[8px] border border-border bg-card">
          <InfoRow
            label={t('popup.dashboard.lastAutoCheck', { defaultValue: '最近自动检查' })}
            value={syncRuntime.state.leafTabAutoSyncLastProbeLabel || '尚未检查'}
          />
          <InfoRow
            label={t('popup.dashboard.nextAutoCheck', { defaultValue: '下次自动检查' })}
            value={syncRuntime.state.leafTabAutoSyncNextProbeLabel || '未计划'}
          />
          <InfoRow
            label={t('popup.dashboard.autoSyncError', { defaultValue: '自动同步错误' })}
            value={syncRuntime.state.leafTabAutoSyncError || '无'}
          />
        </div>
      </div>
    </section>
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

function SyncMethodPage({
  profile,
  syncRuntime,
  onBack,
  onOpenLogin,
  onOpenWebdav,
  onSelected,
}: {
  profile: ConfiguredHomeState | null;
  syncRuntime: PopupSyncRuntime;
  onBack: () => void;
  onOpenLogin: () => void;
  onOpenWebdav: () => void;
  onSelected: () => void;
}) {
  const { t } = useTranslation();
  const selectedSource = syncRuntime.state.leafTabSelectedSyncSource;
  const syncing = syncRuntime.state.topNavSyncStatus === 'syncing';

  const selectCloud = async () => {
    if (!syncRuntime.state.leafTabCloudLoggedIn) {
      onOpenLogin();
      return;
    }
    const selected = await syncRuntime.actions.handleSelectSyncSource('aira-cloud');
    if (selected) {
      onSelected();
    }
  };

  return (
    <section className="min-h-[360px] bg-background">
      <PopupHeader
        title={t('popup.dashboard.changeSyncMethod', { defaultValue: '更改同步方式' })}
        onBack={onBack}
      />

      <div className="space-y-3 px-3 py-3">
        <p className="px-1 text-xs leading-5 text-muted-foreground">
          {t('popup.syncMethod.help', {
            defaultValue: '一次只使用一种书签同步方式。选择后会自动合并同步；只有真实双向冲突才会询问。',
          })}
        </p>

        <MenuItem
          icon={<RiCloudFill className="size-4" />}
          title="Aira 云同步"
          description={syncRuntime.state.leafTabCloudLoggedIn
            ? t('popup.syncMethod.cloudReady', {
                defaultValue: `${profile?.nickname || '当前账号'} · 需要 Aira Pro`,
              })
            : t('popup.home.cloudDesc', { defaultValue: '需要 Aira 桌面登录和 Pro 权限' })}
          status={selectedSource === 'aira-cloud'
            ? t('popup.syncMethod.current', { defaultValue: '当前使用' })
            : 'PRO'}
          onClick={() => {
            if (!syncing) {
              void selectCloud();
            }
          }}
        />

        <MenuItem
          icon={<RiHardDrive3Fill className="size-4" />}
          title="WebDAV"
          description={syncRuntime.state.leafTabWebdavConfigured
            ? syncRuntime.state.leafTabWebdavProfileLabel
            : t('popup.home.webdavOnlyDesc', { defaultValue: '无需 Aira 登录，所有用户均可使用' })}
          status={selectedSource === 'webdav'
            ? t('popup.syncMethod.current', { defaultValue: '当前使用' })
            : undefined}
          onClick={onOpenWebdav}
        />
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
  const hasConfig = url.trim().length > 0;

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

  const saveWebdavConfig = async () => {
    const trimmedUrl = url.trim();
    if (!trimmedUrl) {
      toast.error(t('settings.backup.webdav.urlRequired', { defaultValue: '请输入 WebDAV 地址' }));
      return false;
    }

    setSaving(true);
    try {
      const granted = await ensureOriginPermission(trimmedUrl, { requestIfNeeded: true }).catch(() => false);
      if (!granted) {
        toast.error(t('settings.backup.webdav.originPermissionDenied', {
          defaultValue: '未授予 WebDAV 站点访问权限，无法启用同步。',
        }));
        return false;
      }

      const current = readWebdavStorageStateFromStorage(t('settings.backup.webdav.defaultProfileName', { defaultValue: '默认配置' }));
      writeWebdavStorageStateToStorage({
        ...current,
        url: trimmedUrl,
        username,
        password,
        syncEnabled: false,
      }, t('settings.backup.webdav.defaultProfileName', { defaultValue: '默认配置' }));
      window.dispatchEvent(new CustomEvent('webdav-config-changed'));
      window.dispatchEvent(new CustomEvent('webdav-sync-status-changed'));
      toast.success(t('settings.backup.webdav.configSaved', { defaultValue: 'WebDAV 配置已保存' }));
      return true;
    } finally {
      setSaving(false);
    }
  };

  const handleSaveAndUse = async () => {
    const saved = await saveWebdavConfig();
    if (!saved) return;
    onSaved({ syncAfterSave: true });
  };

  const actionTitle = syncing
    ? t('settings.backup.webdav.enablingAction', { defaultValue: '正在连接 WebDAV' })
    : t('settings.backup.webdav.saveAndUseAction', { defaultValue: '保存并使用 WebDAV' });

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
          onClick={() => void handleSaveAndUse()}
        >
          {actionTitle}
        </Button>
      </div>
    </section>
  );
}

export function PopupApp() {
  const [view, setView] = useState<PopupView>('home');
  const [localVersion, setLocalVersion] = useState(0);
  const [pendingWebdavSyncAfterSave, setPendingWebdavSyncAfterSave] = useState(false);
  const [pendingCloudSelectionAfterLogin, setPendingCloudSelectionAfterLogin] = useState(false);
  const { t } = useTranslation();
  const syncRuntime = useBookmarkSyncRuntimeController({
    openWebdavConfig: () => setView('webdav'),
  });
  const configuredHomeState = useMemo(() => {
    void localVersion;
    return readConfiguredHomeState(t);
  }, [localVersion, t]);

  useEffect(() => {
    const refresh = () => setLocalVersion((value) => value + 1);
    window.addEventListener('webdav-config-changed', refresh);
    window.addEventListener('webdav-sync-status-changed', refresh);
    window.addEventListener('phone-page-push-setting-changed', refresh);
    return () => {
      window.removeEventListener('webdav-config-changed', refresh);
      window.removeEventListener('webdav-sync-status-changed', refresh);
      window.removeEventListener('phone-page-push-setting-changed', refresh);
    };
  }, []);

  useEffect(() => {
    const profile = readAiraDesktopLoginProfile();
    if (!profile?.uid) return;
    refreshAiraDesktopMembershipProfile(profile)
      .then((latestProfile) => {
        if (latestProfile && !isAiraDesktopProfilePro(latestProfile)) {
          disableProOnlyLocalFeatures();
        }
        setLocalVersion((value) => value + 1);
      })
      .catch(() => undefined);
  }, []);

  useEffect(() => {
    if (!pendingWebdavSyncAfterSave || !syncRuntime.state.leafTabSyncHasConfig) return;
    setPendingWebdavSyncAfterSave(false);
    void syncRuntime.actions.handleSelectSyncSource('webdav');
  }, [
    pendingWebdavSyncAfterSave,
    syncRuntime.actions,
    syncRuntime.state.leafTabSyncHasConfig,
  ]);

  useEffect(() => {
    if (!pendingCloudSelectionAfterLogin || !syncRuntime.state.leafTabCloudLoggedIn) return;
    setPendingCloudSelectionAfterLogin(false);
    void syncRuntime.actions.handleSelectSyncSource('aira-cloud');
  }, [
    pendingCloudSelectionAfterLogin,
    syncRuntime.actions,
    syncRuntime.state.leafTabCloudLoggedIn,
  ]);

  const selectCloudOrLogin = () => {
    if (!configuredHomeState?.isDesktopLoggedIn) {
      setPendingCloudSelectionAfterLogin(true);
      setView('login');
      return;
    }
    void syncRuntime.actions.handleSelectSyncSource('aira-cloud');
  };

  return (
    <main className="w-[360px] max-w-full overflow-hidden bg-background text-foreground [font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe_UI',sans-serif]">
      {view === 'home' && (
        <PopupHome
          syncRuntime={syncRuntime}
          localVersion={localVersion}
          onLogout={() => {
            clearAiraDesktopLoginProfile();
            disableProOnlyLocalFeatures();
            setLocalVersion((value) => value + 1);
            toast.success(t('popup.profile.loggedOut', { defaultValue: '已退出登录' }));
          }}
          onOpenLogin={() => setView('login')}
          onSelectCloud={selectCloudOrLogin}
          onOpenWebdav={() => setView('webdav')}
          onOpenSyncMethod={() => setView('sync-method')}
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
      {view === 'sync-method' && (
        <SyncMethodPage
          profile={configuredHomeState}
          syncRuntime={syncRuntime}
          onBack={() => setView('home')}
          onOpenLogin={() => {
            setPendingCloudSelectionAfterLogin(true);
            setView('login');
          }}
          onOpenWebdav={() => setView('webdav')}
          onSelected={() => setView('home')}
        />
      )}
      {view === 'advanced' && (
        <AdvancedSettingsPage
          syncRuntime={syncRuntime}
          onBack={() => setView('home')}
        />
      )}
      {view === 'login' && (
        <LoginQrPage
          onOpenWebdav={() => {
            setPendingCloudSelectionAfterLogin(false);
            setView('webdav');
          }}
          onLoggedIn={() => {
            setLocalVersion((value) => value + 1);
            setView(pendingCloudSelectionAfterLogin ? 'home' : 'sync-method');
          }}
        />
      )}
      <SyncProgressDialog syncRuntime={syncRuntime} />
    </main>
  );
}
