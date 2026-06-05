import { useMemo, type ComponentType, type ReactNode } from 'react';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  RiCheckboxCircleFill,
  RiErrorWarningFill,
  RiHardDrive3Fill,
  RiRefreshFill,
  RiSettings4Fill,
} from '@/icons/ri-compat';
import { useTranslation } from 'react-i18next';
import type { LeafTabSyncAnalysis } from '@/sync/leaftab';
import type { SyncState } from '@/sync/stateMachine';
import { cn } from '@/components/ui/utils';

export interface LeafTabSyncDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  webdavAnalysis: LeafTabSyncAnalysis | null;
  syncState: SyncState;
  ready?: boolean;
  hasConfig?: boolean;
  busy?: boolean;
  bookmarkScopeLabel?: string;
  summaryText?: string;
  webdavConfigured?: boolean;
  webdavEnabled?: boolean;
  webdavSyncBookmarksEnabled?: boolean;
  webdavProfileLabel?: string;
  webdavUrlLabel?: string;
  webdavLastSyncLabel?: string;
  webdavNextSyncLabel?: string;
  onSyncNow: () => void;
  onOpenSetupConfig?: () => void;
  onOpenConfig?: () => void;
  onWebdavOverwriteLocal?: () => void;
  onWebdavOverwriteRemote?: () => void;
}

type StatusTone = 'neutral' | 'info' | 'success' | 'danger';

type ProviderModel = {
  icon: ComponentType<{ className?: string }>;
  title: string;
  subtitle: string;
  localShortcutCount: string;
  localBookmarkCount: string;
  remoteShortcutCount: string;
  remoteBookmarkCount: string;
  lastSyncLabel: string;
  nextSyncLabel: string;
  statusLabel: string;
  statusTone: StatusTone;
  statusIcon: ComponentType<{ className?: string }>;
  statusSpin?: boolean;
  scopeLabel: string;
};

const formatMetricCount = (value: number | null | undefined) => {
  return typeof value === 'number' && Number.isFinite(value) ? String(value) : '...';
};

const toneClasses: Record<StatusTone, string> = {
  neutral: 'border-border/60 bg-background text-muted-foreground',
  info: 'border-primary/20 bg-primary/10 text-primary',
  success: 'border-emerald-500/20 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400',
  danger: 'border-red-500/20 bg-red-500/10 text-red-600 dark:text-red-300',
};

function MetricTile({
  label,
  value,
}: {
  label: string;
  value: string;
}) {
  return (
    <div className="min-w-0 text-center">
      <div className="text-[24px] font-semibold tracking-tight text-foreground">{value}</div>
      <div className="mt-1 text-xs font-medium text-muted-foreground">{label}</div>
    </div>
  );
}

function StatusBadge({
  tone,
  icon: Icon,
  label,
  spin = false,
}: {
  tone: StatusTone;
  icon: ComponentType<{ className?: string }>;
  label: string;
  spin?: boolean;
}) {
  return (
    <div className={cn('inline-flex items-center gap-2 rounded-full border px-3 py-1.5 text-sm', toneClasses[tone])}>
      <Icon className={cn('size-3.5', spin ? 'animate-spin' : '')} />
      <span>{label}</span>
    </div>
  );
}

function DetailRow({
  label,
  value,
  valueClassName,
}: {
  label: string;
  value: string;
  valueClassName?: string;
}) {
  return (
    <div className="flex flex-col gap-1 py-1.5 sm:flex-row sm:items-start sm:justify-between sm:gap-4">
      <span className="text-sm text-muted-foreground">{label}</span>
      <span className={cn('text-sm leading-6 text-foreground sm:max-w-[70%] sm:text-right', valueClassName)}>
        {value}
      </span>
    </div>
  );
}

function IconActionButton({
  icon: Icon,
  label,
  onClick,
  disabled = false,
}: {
  icon: ComponentType<{ className?: string }>;
  label: string;
  onClick?: () => void;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      className="inline-flex h-11 w-11 items-center justify-center rounded-full border border-border/70 bg-background text-foreground transition-colors hover:bg-accent/60 hover:text-foreground disabled:pointer-events-none disabled:opacity-50 dark:border-border/70 dark:bg-background dark:hover:bg-accent/50"
      onClick={onClick}
      disabled={disabled}
      aria-label={label}
      title={label}
    >
      <Icon className="size-4" />
    </button>
  );
}

function ProviderCard({
  model,
  securityCard,
  actionArea,
}: {
  model: ProviderModel;
  securityCard?: ReactNode;
  actionArea?: ReactNode;
}) {
  const { t } = useTranslation();
  const ProviderIcon = model.icon;

  return (
    <section className="overflow-hidden px-0">
      <div className="mx-auto flex w-full max-w-[520px] flex-col gap-5 py-2">
        <div className="mx-auto grid w-full max-w-[520px] grid-cols-[minmax(0,1fr)_auto] items-center gap-4">
          <div className="flex min-w-0 items-center gap-4">
            <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-[18px] border border-border/60 bg-background/70 text-primary">
              <ProviderIcon className="size-5" />
            </div>
            <div className="flex min-w-0 min-h-12 flex-col justify-center">
              <div className="truncate text-lg font-semibold tracking-tight text-foreground">
                {model.title}
              </div>
              <div className="mt-0.5 text-sm leading-5 text-muted-foreground">
                {model.subtitle}
              </div>
            </div>
          </div>
          <div className="flex items-center justify-end self-center">
            <StatusBadge
              tone={model.statusTone}
              icon={model.statusIcon}
              label={model.statusLabel}
              spin={model.statusSpin}
            />
          </div>
        </div>

        <div className="mx-auto grid w-full max-w-[520px] grid-cols-2 gap-x-4 gap-y-3 sm:grid-cols-4">
          <MetricTile
            label={t('leaftabSyncDialog.metrics.localBookmarks', { defaultValue: '本地书签' })}
            value={model.localBookmarkCount}
          />
          <MetricTile
            label={t('leaftabSyncDialog.metrics.remoteBookmarks', { defaultValue: '云端书签' })}
            value={model.remoteBookmarkCount}
          />
        </div>

        {securityCard ? (
          <div>
            {securityCard}
          </div>
        ) : null}

        <div className="space-y-1">
          <DetailRow
            label={t('leaftabSyncDialog.details.lastSync', { defaultValue: '上次同步' })}
            value={model.lastSyncLabel}
          />
          <DetailRow
            label={t('leaftabSyncDialog.details.nextSync', { defaultValue: '下次同步' })}
            value={model.nextSyncLabel}
          />
          <DetailRow
            label={t('leaftabSyncDialog.details.scope', { defaultValue: '同步范围' })}
            value={model.scopeLabel}
          />
        </div>
      </div>

      {actionArea ? (
        <div className="mt-5 flex flex-wrap gap-2 border-t border-border/60 pt-4">
          {actionArea}
        </div>
      ) : null}
    </section>
  );
}

export function LeafTabSyncDialog({
  open,
  onOpenChange,
  webdavAnalysis,
  syncState,
  ready = false,
  hasConfig = false,
  busy = false,
  bookmarkScopeLabel,
  summaryText,
  webdavConfigured = false,
  webdavEnabled = false,
  webdavSyncBookmarksEnabled = false,
  webdavProfileLabel,
  webdavUrlLabel,
  webdavLastSyncLabel,
  webdavNextSyncLabel,
  onSyncNow,
  onOpenSetupConfig,
  onOpenConfig,
  onWebdavOverwriteLocal,
  onWebdavOverwriteRemote,
}: LeafTabSyncDialogProps) {
  const { t } = useTranslation();
  void hasConfig;
  void summaryText;
  void webdavUrlLabel;
  void webdavSyncBookmarksEnabled;
  const resolvedBookmarkScope = bookmarkScopeLabel || t('leaftabSyncDialog.scopeDefault', { defaultValue: '书签' });

  const webdavModel = useMemo<ProviderModel>(() => {
    const syncing = syncState.status === 'syncing';
    const error = syncState.status === 'error';

    return {
      icon: RiHardDrive3Fill,
      title: webdavConfigured
        ? (webdavProfileLabel || t('leaftabSyncDialog.webdav.connectedFallback', { defaultValue: 'WebDAV' }))
        : t('leaftabSyncDialog.webdav.unconfiguredTitle', { defaultValue: 'WebDAV 未开启' }),
      subtitle: !webdavConfigured
        ? t('leaftabSyncDialog.webdav.unconfiguredSubtitle', { defaultValue: '未配置，先去配置' })
        : webdavEnabled
          ? t('leaftabSyncDialog.webdav.enabledSubtitle', { defaultValue: '已配置，可同步到 WebDAV' })
          : t('leaftabSyncDialog.webdav.disabledSubtitle', { defaultValue: '已配置，尚未启用同步' }),
      localShortcutCount: '-',
      localBookmarkCount: formatMetricCount(webdavAnalysis?.localSummary.bookmarkItems),
      remoteShortcutCount: '-',
      remoteBookmarkCount: formatMetricCount(webdavAnalysis?.remoteSummary.bookmarkItems),
      lastSyncLabel: webdavConfigured
        ? (webdavLastSyncLabel || t('leaftabSyncDialog.lastSyncEmpty', { defaultValue: '暂无记录' }))
        : t('leaftabSyncDialog.lastSyncUnavailable', { defaultValue: '未同步' }),
      nextSyncLabel: !webdavConfigured
        ? t('leaftabSyncDialog.webdav.configureToStart', { defaultValue: '配置后设置' })
        : webdavEnabled
          ? (webdavNextSyncLabel
            ? webdavNextSyncLabel
            : t('leaftabSyncDialog.autoSyncOn', { defaultValue: '自动同步已开启' }))
          : t('leaftabSyncDialog.webdav.enableToStart', { defaultValue: '已配置，待启用' }),
      statusLabel: !webdavConfigured
        ? t('settings.backup.webdav.notConfigured', { defaultValue: '未配置' })
        : error
          ? t('leaftabSyncCenter.status.error', { defaultValue: '同步失败' })
          : syncing
            ? t('leaftabSyncCenter.status.syncing', { defaultValue: '同步中' })
            : webdavEnabled
              ? t('settings.backup.webdav.enabled', { defaultValue: '已启用' })
              : t('settings.backup.webdav.disabled', { defaultValue: '未启用' }),
      statusTone: !webdavConfigured ? 'neutral' : error ? 'danger' : syncing ? 'info' : webdavEnabled ? 'success' : 'neutral',
      statusIcon: !webdavConfigured ? RiHardDrive3Fill : error ? RiErrorWarningFill : syncing ? RiRefreshFill : RiCheckboxCircleFill,
      statusSpin: syncing,
      scopeLabel: t('leaftabSyncDialog.webdav.bookmarksOnlyScope', {
        defaultValue: '{{scope}}',
        scope: resolvedBookmarkScope,
      }),
    };
  }, [
    resolvedBookmarkScope,
    syncState.status,
    t,
    webdavAnalysis,
    webdavConfigured,
    webdavEnabled,
    webdavLastSyncLabel,
    webdavNextSyncLabel,
    webdavProfileLabel,
    webdavSyncBookmarksEnabled,
  ]);

  const webdavNeedsConfiguration = !webdavConfigured || !webdavEnabled;
  const webdavPrimaryConfigureAction = webdavNeedsConfiguration ? (onOpenSetupConfig || onOpenConfig) : onOpenConfig;
  const webdavSettingsAction = webdavConfigured ? onOpenConfig : (onOpenSetupConfig || onOpenConfig);

  const actionArea = (
    <>
      <Button
        type="button"
        className="h-11 min-w-[160px] flex-1"
        onClick={webdavNeedsConfiguration ? webdavPrimaryConfigureAction : onSyncNow}
        disabled={busy || (webdavEnabled && !ready) || (webdavNeedsConfiguration && !webdavPrimaryConfigureAction)}
      >
        {webdavNeedsConfiguration ? (
          <RiSettings4Fill className="size-4" />
        ) : webdavEnabled ? (
          <RiRefreshFill className={cn('size-4', syncState.status === 'syncing' ? 'animate-spin' : '')} />
        ) : (
          <RiCheckboxCircleFill className="size-4" />
        )}
        {webdavNeedsConfiguration
          ? t('settings.backup.webdav.configureAction', { defaultValue: '去配置' })
          : webdavEnabled
            ? (syncState.status === 'syncing'
              ? t('leaftabSyncCenter.actions.syncing', { defaultValue: '同步中' })
              : t('settings.backup.webdav.sync', { defaultValue: '立即同步' }))
            : t('leaftabSyncDialog.enableSync', { defaultValue: '启用同步' })}
      </Button>
      <IconActionButton
        icon={RiSettings4Fill}
        label={t('settings.backup.webdav.configure', { defaultValue: '配置 WebDAV' })}
        onClick={webdavSettingsAction}
        disabled={busy || !webdavSettingsAction}
      />
      <Button
        type="button"
        variant="secondary"
        className="h-11 min-w-[136px] flex-1"
        onClick={onWebdavOverwriteLocal}
        disabled={busy || !webdavEnabled || !onWebdavOverwriteLocal}
      >
        {t('leaftabSyncDialog.remoteOverwriteLocal', { defaultValue: 'WebDAV 覆盖本地' })}
      </Button>
      <Button
        type="button"
        variant="secondary"
        className="h-11 min-w-[136px] flex-1"
        onClick={onWebdavOverwriteRemote}
        disabled={busy || !webdavEnabled || !onWebdavOverwriteRemote}
      >
        {t('leaftabSyncDialog.localOverwriteRemote', { defaultValue: '本地覆盖 WebDAV' })}
      </Button>
    </>
  );

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="overflow-visible rounded-[32px] border-border bg-background text-foreground sm:max-w-[560px]">
        <DialogHeader className="pb-3 pr-8">
          <DialogTitle>{t('leaftabSyncCenter.title', { defaultValue: '同步中心' })}</DialogTitle>
          <DialogDescription>
            {t('leaftabSyncDialog.webdavOnlyDescription', { defaultValue: '通过 WebDAV 同步浏览器书签。' })}
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-col gap-4">
          <ProviderCard model={webdavModel} actionArea={actionArea} />
        </div>
      </DialogContent>
    </Dialog>
  );
}
