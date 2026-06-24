import { useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import { useTranslation } from 'react-i18next';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  RiArrowLeftSLine,
  RiArrowRightSLine,
  RiEyeFill,
  RiEyeOffFill,
  RiHardDrive3Fill,
} from '@/icons/ri-compat';

type PopupView = 'home' | 'webdav';

type WebdavProviderOption = {
  id: string;
  label: string;
  url?: string;
};

function QrPlaceholder() {
  return (
    <div className="flex justify-center px-4 pt-4">
      <div
        className="h-44 w-44 rounded-[8px] border border-dashed border-border bg-secondary/30"
        aria-hidden="true"
      />
    </div>
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

function PopupHome({ onOpenWebdav }: { onOpenWebdav: () => void }) {
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

  return (
    <main className="w-[360px] max-w-full overflow-hidden bg-background text-foreground">
      {view === 'home' ? (
        <PopupHome onOpenWebdav={() => setView('webdav')} />
      ) : (
        <WebdavConfigPage onBack={() => setView('home')} />
      )}
    </main>
  );
}
