import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from '@/components/ui/sonner';
import { Button } from '@/components/ui/button';
import ShortcutIcon from '@/components/ShortcutIcon';
import type { ScenarioMode } from '@/scenario/scenario';
import type { Shortcut, ShortcutDraft, ShortcutIconAppearance } from '@/types';
import { extractDomainFromUrl } from '@/utils';
import { getShortcutIconSmoothClipPathStyles } from '@/utils/shortcutIconSettings';

const PREVIEW_SIZE = 56;

type PopupShortcutComposerProps = {
  initialShortcut?: Partial<Shortcut> | null;
  title: string;
  description: ReactNode;
  scenarioModes: ScenarioMode[];
  selectedScenarioId: string;
  onScenarioChange: (scenarioId: string) => void;
  onCancel: () => void;
  onSave: (
    value: ShortcutDraft,
    localOnly?: {
      useCustomIcon?: boolean;
      customIconDataUrl?: string | null;
    },
  ) => void;
  iconCornerRadius?: number;
  iconAppearance?: ShortcutIconAppearance;
};

export function PopupShortcutComposer({
  initialShortcut,
  title,
  description,
  scenarioModes,
  selectedScenarioId,
  onScenarioChange,
  onCancel,
  onSave,
  iconCornerRadius,
  iconAppearance,
}: PopupShortcutComposerProps) {
  const { t } = useTranslation();
  const [shortcutTitle, setShortcutTitle] = useState(initialShortcut?.title || '');
  const [shortcutUrl, setShortcutUrl] = useState(initialShortcut?.url || '');

  const initialTitle = initialShortcut?.title || '';
  const initialUrl = initialShortcut?.url || '';
  const initialShortcutId = typeof initialShortcut?.id === 'string' ? initialShortcut.id : '';

  useEffect(() => {
    setShortcutTitle(initialTitle);
    setShortcutUrl(initialUrl);
  }, [initialTitle, initialUrl]);

  const domain = useMemo(() => extractDomainFromUrl(shortcutUrl), [shortcutUrl]);

  const handleSave = () => {
    if (!shortcutTitle.trim() || !shortcutUrl.trim()) {
      toast.error(t('shortcutModal.errors.fillAll'), {
        description: t('shortcutModal.errors.fillAllDesc'),
      });
      return;
    }

    onSave({
      title: shortcutTitle.trim(),
      url: shortcutUrl.trim(),
      icon: initialShortcut?.icon || '',
      iconRendering: 'favicon',
      iconColor: '',
    });
  };

  const previewShapeStyle = getShortcutIconSmoothClipPathStyles(iconCornerRadius);
  const scenarioLabel = scenarioModes.find((mode) => mode.id === selectedScenarioId)?.name || '';

  return (
    <div className="flex min-w-0 flex-col overflow-hidden rounded-[24px] border border-border/70 bg-background/92 shadow-[0_20px_60px_rgba(15,23,42,0.16)] backdrop-blur-xl">
      <div className="border-b border-border/60 px-4 pb-3.5 pt-4">
        <h1 className="text-[18px] font-semibold tracking-[-0.02em] text-foreground">{title}</h1>
        <div className="mt-1 text-[12.5px] leading-5 text-muted-foreground">{description}</div>
      </div>

      <div className="space-y-4 px-4 py-4">
        <div className="flex min-w-0 items-center gap-3 rounded-[18px] border border-border/70 bg-secondary/20 px-3 py-3">
          <div className="shrink-0" style={previewShapeStyle}>
            <ShortcutIcon
              icon={initialShortcut?.icon || ''}
              url={shortcutUrl}
              shortcutId={initialShortcutId}
              allowStoredCustomIcon={false}
              size={PREVIEW_SIZE}
              frame="never"
              fallbackStyle="emptyicon"
              fallbackLabel={shortcutTitle}
              iconRendering="favicon"
              iconCornerRadius={iconCornerRadius}
              iconAppearance={iconAppearance}
            />
          </div>
          <div className="min-w-0 flex-1">
            <div className="truncate text-sm font-semibold text-foreground">
              {shortcutTitle.trim() || t('shortcutModal.namePlaceholder')}
            </div>
            <div className="mt-0.5 truncate text-xs text-muted-foreground">
              {domain || t('popupShortcut.previewWaiting', { defaultValue: '等待输入网址' })}
            </div>
            {scenarioLabel ? (
              <div className="mt-1 truncate text-[11px] text-muted-foreground/80">
                {t('popupShortcut.targetScenario', {
                  defaultValue: '将保存到「{{name}}」场景',
                  name: scenarioLabel,
                })}
              </div>
            ) : null}
          </div>
        </div>

        <div className="space-y-3">
          <label className="block space-y-1.5">
            <span className="px-1 text-xs font-medium text-muted-foreground">
              {t('shortcutModal.namePlaceholder')}
            </span>
            <input
              data-testid="shortcut-modal-title"
              type="text"
              value={shortcutTitle}
              onChange={(event) => setShortcutTitle(event.target.value)}
              placeholder={t('shortcutModal.namePlaceholder')}
              className="h-10 w-full min-w-0 rounded-[14px] border border-border/80 bg-secondary/20 px-3 text-[14px] text-foreground outline-none transition-colors placeholder:text-muted-foreground/65 focus:border-primary"
            />
          </label>

          <label className="block space-y-1.5">
            <span className="px-1 text-xs font-medium text-muted-foreground">
              {t('shortcutModal.urlPlaceholder')}
            </span>
            <input
              data-testid="shortcut-modal-url"
              type="text"
              value={shortcutUrl}
              onChange={(event) => setShortcutUrl(event.target.value)}
              placeholder={t('shortcutModal.urlPlaceholder')}
              className="h-10 w-full min-w-0 rounded-[14px] border border-border/80 bg-secondary/20 px-3 text-[13.5px] text-foreground outline-none transition-colors placeholder:text-muted-foreground/65 focus:border-primary"
            />
          </label>

          {scenarioModes.length > 1 ? (
            <label className="block space-y-1.5">
              <span className="px-1 text-xs font-medium text-muted-foreground">
                {t('popupShortcut.scenarioLabel', { defaultValue: '保存到情景模式' })}
              </span>
              <select
                data-testid="popup-scenario-select"
                value={selectedScenarioId}
                onChange={(event) => onScenarioChange(event.target.value)}
                className="h-10 w-full min-w-0 rounded-[14px] border border-border/80 bg-secondary/20 px-3 text-[13.5px] text-foreground outline-none transition-colors focus:border-primary"
              >
                {scenarioModes.map((mode) => (
                  <option key={mode.id} value={mode.id}>
                    {mode.name}
                  </option>
                ))}
              </select>
            </label>
          ) : null}
        </div>
      </div>

      <div className="grid grid-cols-2 gap-2 border-t border-border/60 px-4 py-3.5">
        <Button
          type="button"
          variant="outline"
          onClick={onCancel}
          data-testid="shortcut-modal-cancel"
          className="h-10 rounded-[14px]"
        >
          {t('common.cancel')}
        </Button>
        <Button
          type="button"
          onClick={handleSave}
          data-testid="shortcut-modal-save"
          className="h-10 rounded-[14px]"
        >
          {t('common.save')}
        </Button>
      </div>
    </div>
  );
}
