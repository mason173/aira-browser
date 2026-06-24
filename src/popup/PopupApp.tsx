import { useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import { useTranslation } from 'react-i18next';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  RiArrowLeftSLine,
  RiArrowRightSLine,
  RiCloudFill,
  RiEyeFill,
  RiEyeOffFill,
  RiHardDrive3Fill,
  RiSlidersFill,
  RiUserFill,
} from '@/icons/ri-compat';
import { WEBDAV_STORAGE_KEYS } from '@/utils/webdavConfig';

type PopupView = 'home' | 'webdav' | 'advanced' | 'cloud' | 'login';

type WebdavProviderOption = {
  id: string;
  label: string;
  url?: string;
};

type ConfiguredHomeState = {
  nickname: string;
  uid: string;
  lastSyncLabel: string;
  localDataLabel: string;
  remoteDataLabel: string;
  syncStartLabel: string;
  webdavEnabled: boolean;
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

function readConfiguredHomeState(t: ReturnType<typeof useTranslation>['t']): ConfiguredHomeState | null {
  try {
    const url = (localStorage.getItem(WEBDAV_STORAGE_KEYS.url) || '').trim();
    if (!url) return null;

    const profileName = (localStorage.getItem(WEBDAV_STORAGE_KEYS.profileName) || '').trim();
    const username = (localStorage.getItem(WEBDAV_STORAGE_KEYS.username) || '').trim();
    const displayName = profileName === '默认配置' ? '' : profileName;
    const deviceId = (localStorage.getItem('leaftab_sync_v1_device_id') || '').trim();
    const webdavEnabled = (localStorage.getItem(WEBDAV_STORAGE_KEYS.syncEnabled) ?? 'false') === 'true';

    return {
      nickname: displayName || username || t('popup.profile.defaultNickname', { defaultValue: '请登录' }),
      uid: deviceId || getShortUid(username || url),
      lastSyncLabel: formatLastSync(
        localStorage.getItem('webdav_last_sync_at'),
        t('popup.dashboard.lastSyncPlaceholder', { defaultValue: '6/24/2026, 10:45:55 AM' }),
      ),
      localDataLabel: t('popup.dashboard.dataCountPlaceholder', {
        defaultValue: '723 个文件夹，9212 个书签',
      }),
      remoteDataLabel: t('popup.dashboard.dataCountPlaceholder', {
        defaultValue: '723 个文件夹，9212 个书签',
      }),
      syncStartLabel: t('popup.advanced.syncStartValue', { defaultValue: '云端 已建立' }),
      webdavEnabled,
    };
  } catch {
    return null;
  }
}

function QrPlaceholder() {
  const { t } = useTranslation();

  return (
    <div className="flex flex-col items-center px-4 pt-4 text-center">
      <div
        className="h-44 w-44 rounded-[8px] border border-dashed border-border bg-secondary/30"
        aria-hidden="true"
      />
      <p className="mt-3 max-w-64 text-sm font-medium leading-5 text-foreground">
        {t('popup.login.qrHint', { defaultValue: '请使用Aira扫一扫登录开启书签云同步' })}
      </p>
    </div>
  );
}

function ProfileHeader({
  profile,
  onOpenLogin,
}: {
  profile: ConfiguredHomeState;
  onOpenLogin: () => void;
}) {
  const { t } = useTranslation();

  return (
    <header className="px-4 pb-3 pt-4 text-center">
      <button
        type="button"
        className="mx-auto flex flex-col items-center rounded-[8px] px-3 py-1 transition-colors hover:bg-accent"
        onClick={onOpenLogin}
        aria-label={t('popup.profile.openLogin', { defaultValue: '请登录' })}
        title={t('popup.profile.openLogin', { defaultValue: '请登录' })}
      >
      <div className="flex h-12 w-12 items-center justify-center rounded-full bg-secondary text-muted-foreground">
        <RiUserFill className="size-6" />
      </div>
      <div className="mt-2 text-sm font-semibold leading-5 text-foreground">
        {profile.nickname}
      </div>
      <div className="mt-1 text-xs leading-4 text-muted-foreground">
        {profile.uid}
      </div>
      </button>
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
  onOpenLogin,
  onOpenCloud,
  onOpenWebdav,
  onOpenAdvanced,
}: {
  profile: ConfiguredHomeState;
  onOpenLogin: () => void;
  onOpenCloud: () => void;
  onOpenWebdav: () => void;
  onOpenAdvanced: () => void;
}) {
  const { t } = useTranslation();

  return (
    <section className="min-h-[480px] bg-background">
      <ProfileHeader profile={profile} onOpenLogin={onOpenLogin} />

      <div className="space-y-3 px-3 pb-3">
        <div className="overflow-hidden rounded-[8px] border border-border bg-card">
          <PanelRow
            icon={<RiCloudFill className="size-4" />}
            title={t('popup.dashboard.bookmarkCloudSync', { defaultValue: '书签云同步' })}
            badge="PRO"
            status={t('popup.dashboard.disabled', { defaultValue: '未开启' })}
            onClick={onOpenCloud}
          />
          <div className="mx-3 border-t border-border" />
          <PanelRow
            icon={<RiHardDrive3Fill className="size-4" />}
            title={t('settings.backup.webdav.entry', { defaultValue: 'WebDAV 同步' })}
            status={profile.webdavEnabled
              ? t('popup.dashboard.enabled', { defaultValue: '已开启' })
              : t('popup.dashboard.disabled', { defaultValue: '未开启' })}
            onClick={onOpenWebdav}
          />
        </div>

        <div className="space-y-2">
          <SectionLabel>{t('popup.dashboard.syncStatusTitle', { defaultValue: '同步状态' })}</SectionLabel>
          <div className="overflow-hidden rounded-[8px] border border-border bg-card">
            <InfoRow
              label={t('popup.dashboard.syncStatus', { defaultValue: '同步状态' })}
              value={profile.webdavEnabled
                ? t('popup.dashboard.enabledStatus', { defaultValue: '已启用' })
                : t('popup.dashboard.disabledStatus', { defaultValue: '未启用' })}
            />
            <InfoRow
              label={t('popup.dashboard.lastSync', { defaultValue: '最近同步' })}
              value={profile.lastSyncLabel}
            />
            <InfoRow
              label={t('popup.dashboard.localData', { defaultValue: '本机数据' })}
              value={profile.localDataLabel}
            />
            <InfoRow
              label={t('popup.dashboard.remoteData', { defaultValue: '云端数据' })}
              value={profile.remoteDataLabel}
            />
          </div>
        </div>

        <Button type="button" className="h-10 w-full rounded-[8px] text-sm font-medium">
          {t('popup.dashboard.syncNow', { defaultValue: '立即同步' })}
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
  onClick,
}: {
  icon: ReactNode;
  title: string;
  description: string;
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
      <RiArrowRightSLine className="size-4 shrink-0 text-muted-foreground" />
    </button>
  );
}

function PopupHome({
  onOpenLogin,
  onOpenCloud,
  onOpenWebdav,
  onOpenAdvanced,
}: {
  onOpenLogin: () => void;
  onOpenCloud: () => void;
  onOpenWebdav: () => void;
  onOpenAdvanced: () => void;
}) {
  const { t } = useTranslation();
  const configuredHomeState = useMemo(() => readConfiguredHomeState(t), [t]);

  if (configuredHomeState) {
    return (
      <ConfiguredHome
        profile={configuredHomeState}
        onOpenLogin={onOpenLogin}
        onOpenCloud={onOpenCloud}
        onOpenWebdav={onOpenWebdav}
        onOpenAdvanced={onOpenAdvanced}
      />
    );
  }

  return <LoginQrPage onOpenWebdav={onOpenWebdav} />;
}

function LoginQrPage({ onOpenWebdav }: { onOpenWebdav: () => void }) {
  const { t } = useTranslation();

  return (
    <section className="flex min-h-[320px] flex-col">
      <QrPlaceholder />

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

function ActionButton({
  children,
  tone = 'default',
}: {
  children: ReactNode;
  tone?: 'default' | 'danger';
}) {
  return (
    <button
      type="button"
      className={[
        'h-10 w-full rounded-[8px] border border-border bg-card px-3 text-sm font-medium transition-colors hover:bg-accent',
        tone === 'danger' ? 'text-destructive' : 'text-foreground',
      ].join(' ')}
    >
      {children}
    </button>
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
  onBack,
}: {
  profile: ConfiguredHomeState | null;
  onBack: () => void;
}) {
  const { t } = useTranslation();
  const fallbackProfile = profile ?? {
    nickname: t('popup.profile.defaultNickname', { defaultValue: '请登录' }),
    uid: 'AIRA-0000',
    lastSyncLabel: t('popup.dashboard.lastSyncPlaceholder', { defaultValue: '6/24/2026, 10:45:55 AM' }),
    localDataLabel: t('popup.dashboard.dataCountPlaceholder', { defaultValue: '723 个文件夹，9212 个书签' }),
    remoteDataLabel: t('popup.dashboard.dataCountPlaceholder', { defaultValue: '723 个文件夹，9212 个书签' }),
    syncStartLabel: t('popup.advanced.syncStartValue', { defaultValue: '云端 已建立' }),
    webdavEnabled: true,
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
              value={t('popup.advanced.enableModeValue', { defaultValue: '书签云同步' })}
            />
            <InfoRow
              label={t('popup.advanced.syncStart', { defaultValue: '同步起点' })}
              value={fallbackProfile.syncStartLabel}
            />
            <InfoRow
              label={t('popup.advanced.remoteData', { defaultValue: '远端数据' })}
              value={t('popup.advanced.remoteDataValue', {
                data: fallbackProfile.remoteDataLabel,
                defaultValue: `云端 ${fallbackProfile.remoteDataLabel}`,
              })}
            />
            <InfoRow
              label={t('popup.dashboard.lastSync', { defaultValue: '最近同步' })}
              value={t('popup.advanced.lastSyncValue', {
                time: fallbackProfile.lastSyncLabel,
                defaultValue: `云端 ${fallbackProfile.lastSyncLabel}`,
              })}
            />
          </div>
        </AdvancedSection>

        <AdvancedSection title={t('popup.advanced.mergeSync', { defaultValue: '合并同步' })}>
          <ActionButton>{t('popup.advanced.mergeNow', { defaultValue: '立即合并同步' })}</ActionButton>
        </AdvancedSection>

        <AdvancedSection title={t('popup.advanced.bookmarkCloudSync', { defaultValue: '书签云同步' })}>
          <div className="space-y-2">
            <ActionButton>{t('popup.advanced.checkRemoteData', { defaultValue: '检查云端数据' })}</ActionButton>
            <ActionButton>{t('popup.advanced.overwriteRemote', { defaultValue: '本机覆盖云端' })}</ActionButton>
            <ActionButton tone="danger">{t('popup.advanced.overwriteLocal', { defaultValue: '云端覆盖本机' })}</ActionButton>
          </div>
        </AdvancedSection>

        <AdvancedSection title={t('popup.advanced.syncStart', { defaultValue: '同步起点' })}>
          <ActionButton>{t('popup.advanced.rebuildSyncStart', { defaultValue: '重建云端同步起点' })}</ActionButton>
        </AdvancedSection>

        <AdvancedSection title={t('popup.advanced.dangerZone', { defaultValue: '危险操作' })}>
          <ActionButton tone="danger">{t('popup.advanced.clearRemoteRecords', { defaultValue: '清除云端同步记录' })}</ActionButton>
        </AdvancedSection>
      </div>
    </section>
  );
}

function BookmarkCloudPage({
  profile,
  onBack,
}: {
  profile: ConfiguredHomeState | null;
  onBack: () => void;
}) {
  const { t } = useTranslation();
  const accountName = profile?.nickname || t('popup.cloud.defaultAccount', { defaultValue: 'Leo' });

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
              value={t('popup.cloud.membershipValue', { defaultValue: 'Aira Pro' })}
            />
            <InfoRow
              label={t('popup.cloud.bookmarkSync', { defaultValue: '书签同步' })}
              value={t('popup.dashboard.disabled', { defaultValue: '未开启' })}
            />
          </div>
        </AdvancedSection>

        <ActionButton>{t('popup.cloud.enableBookmarkSync', { defaultValue: '开启书签云同步' })}</ActionButton>
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

function WebdavConfigPage({ onBack }: { onBack: () => void }) {
  const { t } = useTranslation();
  const [provider, setProvider] = useState('custom');
  const [url, setUrl] = useState('');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);

  const providers = useMemo<WebdavProviderOption[]>(() => ([
    { id: 'custom', label: t('settings.backup.webdav.providerCustom', { defaultValue: '自定义服务' }) },
    { id: 'jianguoyun', label: t('settings.backup.webdav.providers.jianguoyun', { defaultValue: '坚果云' }), url: 'https://dav.jianguoyun.com/dav/' },
    { id: 'pcloud-us', label: 'pCloud (US)', url: 'https://webdav.pcloud.com' },
    { id: 'pcloud-eu', label: 'pCloud (EU)', url: 'https://ewebdav.pcloud.com' },
    { id: 'gmx', label: 'GMX MediaCenter', url: 'https://webdav.mc.gmx.net' },
    { id: 'koofr', label: 'Koofr', url: 'https://app.koofr.net/dav/Koofr' },
  ]), [t]);

  const handleProviderChange = (nextProvider: string) => {
    setProvider(nextProvider);
    const selectedProvider = providers.find((item) => item.id === nextProvider);
    if (selectedProvider?.url) {
      setUrl(selectedProvider.url);
    }
  };

  return (
    <section className="min-h-[420px] bg-background">
      <PopupHeader
        title={t('settings.backup.webdav.entry', { defaultValue: 'WebDAV 同步' })}
        onBack={onBack}
      />

      <div className="space-y-4 px-4 py-4">
        <NativeField label={t('settings.backup.webdav.providerLabel', { defaultValue: 'WebDAV 服务商' })}>
          <select
            value={provider}
            onChange={(event) => handleProviderChange(event.target.value)}
            className="h-10 w-full rounded-[8px] border border-input bg-input-background px-3 text-sm text-foreground outline-none transition-colors focus:border-ring"
          >
            {providers.map((item) => (
              <option key={item.id} value={item.id}>
                {item.label}
              </option>
            ))}
          </select>
        </NativeField>

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
        <Button type="button" className="h-10 w-full rounded-[8px]" disabled>
          {t('common.save', { defaultValue: '保存' })}
        </Button>
      </div>
    </section>
  );
}

export function PopupApp() {
  const [view, setView] = useState<PopupView>('home');
  const { t } = useTranslation();
  const configuredHomeState = useMemo(() => readConfiguredHomeState(t), [t]);

  return (
    <main className="w-[360px] max-w-full overflow-hidden bg-background text-foreground [font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe_UI',sans-serif]">
      {view === 'home' && (
        <PopupHome
          onOpenLogin={() => setView('login')}
          onOpenCloud={() => setView('cloud')}
          onOpenWebdav={() => setView('webdav')}
          onOpenAdvanced={() => setView('advanced')}
        />
      )}
      {view === 'webdav' && (
        <WebdavConfigPage onBack={() => setView('home')} />
      )}
      {view === 'advanced' && (
        <AdvancedSyncPage
          profile={configuredHomeState}
          onBack={() => setView('home')}
        />
      )}
      {view === 'cloud' && (
        <BookmarkCloudPage
          profile={configuredHomeState}
          onBack={() => setView('home')}
        />
      )}
      {view === 'login' && (
        <LoginQrPage onOpenWebdav={() => setView('webdav')} />
      )}
    </main>
  );
}
