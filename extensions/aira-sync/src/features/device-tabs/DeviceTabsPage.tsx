import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import {
  Globe2,
  Laptop,
  RefreshCw,
  Smartphone,
} from 'lucide-react';
import { RiArrowLeftSLine } from '@/icons/ri-compat';
import type { CrossDeviceTabDevice } from './deviceTabsModels';

export function DeviceTabsPage({
  enabled,
  devices,
  loading,
  error,
  onRefresh,
  onBack,
}: {
  enabled: boolean;
  devices: CrossDeviceTabDevice[];
  loading: boolean;
  error: unknown | null;
  onRefresh: () => Promise<void>;
  onBack: () => void;
}) {
  const { t } = useTranslation();
  const errorMessage = error
    ? String((error as Error)?.message || t('deviceTabs.states.unavailable', {
        defaultValue: '暂时无法读取手机标签页。',
      }))
    : '';

  return (
    <section className="min-h-[480px] bg-background">
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
        <h1 className="min-w-0 flex-1 truncate text-sm font-semibold text-foreground">
          {t('deviceTabs.title', { defaultValue: '手机标签页' })}
        </h1>
        <button
          type="button"
          className="flex h-9 w-9 items-center justify-center rounded-[8px] text-muted-foreground transition-colors hover:bg-accent hover:text-foreground disabled:opacity-50"
          onClick={() => void onRefresh()}
          disabled={!enabled || loading}
          aria-label={t('deviceTabs.actions.refresh', { defaultValue: '刷新' })}
          title={t('deviceTabs.actions.refresh', { defaultValue: '刷新' })}
        >
          <RefreshCw className={`size-4 ${loading ? 'animate-spin' : ''}`} />
        </button>
      </header>

      <div className="space-y-4 px-3 py-3">
        {!enabled ? (
          <EmptyState
            icon={<Laptop className="size-5" />}
            title={t('deviceTabs.states.disabled', { defaultValue: '跨设备标签页尚未开启' })}
          />
        ) : errorMessage ? (
          <EmptyState
            icon={<Laptop className="size-5" />}
            title={errorMessage}
          />
        ) : loading ? (
          <EmptyState
            icon={<RefreshCw className="size-5 animate-spin" />}
            title={t('deviceTabs.states.loading', { defaultValue: '正在读取在线手机...' })}
          />
        ) : devices.length === 0 ? (
          <EmptyState
            icon={<Smartphone className="size-5" />}
            title={t('deviceTabs.states.empty', { defaultValue: '当前没有在线手机' })}
          />
        ) : (
          <div className="space-y-5">
            {devices.map((device) => (
              <DeviceGroup key={device.deviceId} device={device} />
            ))}
          </div>
        )}
      </div>
    </section>
  );
}

function DeviceGroup({ device }: { device: CrossDeviceTabDevice }) {
  const { t } = useTranslation();
  const tabCount = device.tabs.length;
  const deviceLabel = device.deviceName
    || device.model
    || device.platform
    || t('deviceTabs.unknownPhone', { defaultValue: '手机' });
  return (
    <section className="space-y-2">
      <header className="flex min-h-5 items-center gap-3 px-1">
        <h2 className="min-w-0 flex-1 truncate text-xs font-medium leading-5 text-muted-foreground">
          {deviceLabel}
        </h2>
        <span className="shrink-0 text-xs text-muted-foreground">
          {t('deviceTabs.tabCount', { count: tabCount, defaultValue: `${tabCount} 个` })}
        </span>
      </header>
      <div className="space-y-2">
        {device.tabs.map((tab, index) => (
          <button
            key={`${tab.url}:${index}`}
            type="button"
            className="flex min-h-16 w-full items-center gap-3 rounded-[8px] border border-border bg-card px-3 py-2.5 text-left transition-colors hover:bg-accent/70"
            onClick={() => openRemoteTab(tab.url)}
            title={tab.title || tab.url}
          >
            <WebsiteIcon url={tab.url} />
            <span className="min-w-0 flex-1">
              <span className="block truncate text-sm font-medium leading-5 text-foreground">
                {tab.title || tab.url}
              </span>
              <span className="mt-0.5 block truncate text-xs leading-4 text-muted-foreground">
                {tab.url}
              </span>
            </span>
          </button>
        ))}
      </div>
    </section>
  );
}

function WebsiteIcon({ url }: { url: string }) {
  const [failed, setFailed] = useState(false);
  const faviconUrl = buildFaviconUrl(url);
  return (
    <span className="flex h-9 w-9 shrink-0 items-center justify-center overflow-hidden rounded-[8px] bg-muted text-muted-foreground">
      {faviconUrl && !failed ? (
        <img
          src={faviconUrl}
          alt=""
          className="h-5 w-5 object-contain"
          onError={() => setFailed(true)}
        />
      ) : (
        <Globe2 className="size-4" aria-hidden="true" />
      )}
    </span>
  );
}

function EmptyState({ icon, title }: { icon: React.ReactNode; title: string }) {
  return (
    <div className="flex min-h-40 flex-col items-center justify-center gap-3 px-6 text-center text-muted-foreground">
      <span className="flex h-10 w-10 items-center justify-center rounded-[8px] bg-muted">{icon}</span>
      <p className="text-sm leading-5">{title}</p>
    </div>
  );
}

function openRemoteTab(url: string): void {
  if (!globalThis.chrome?.tabs?.create) return;
  void globalThis.chrome.tabs.create({ url, active: true });
  window.close();
}

function buildFaviconUrl(pageUrl: string): string {
  const getUrl = globalThis.chrome?.runtime?.getURL;
  if (!getUrl) return '';
  const faviconUrl = new URL(getUrl('/_favicon/'));
  faviconUrl.searchParams.set('pageUrl', pageUrl);
  faviconUrl.searchParams.set('size', '32');
  return faviconUrl.toString();
}
