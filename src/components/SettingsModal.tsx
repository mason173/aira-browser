import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Switch, SwitchThumb } from "@/components/animate-ui/primitives/radix/switch";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { useTranslation } from 'react-i18next';
import { useEffect, useState, useMemo } from "react";
import {
  RiArrowLeftSLine,
  RiCheckFill,
  RiCheckboxBlankFill,
  RiComputerFill,
  RiDownload2Fill,
  RiFlashlightFill,
  RiInformationFill,
  RiMoonFill,
  RiSunFill,
  RiUpload2Fill,
} from "@/icons/ri-compat";
import { useTheme } from "next-themes";
import type { WebdavConfig } from "@/types/webdav";
/// <reference types="chrome" />
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { DISPLAY_MODE_OPTIONS, type DisplayMode } from "@/displayMode/config";
import type { WallpaperMode } from "@/wallpaper/types";
import aboutIcon from "@/assets/abouticon.svg";
import {
  ADAPTIVE_NEUTRAL_ACCENT,
  DEFAULT_ACCENT_COLOR,
  getWallpaperAccentSlotKey,
  resolveAccentDetailColor,
  resolveAdaptiveNeutralAccent,
} from "@/utils/accentColor";
import {
  DEFAULT_WALLPAPER_ACCENT_PALETTE,
  resolveWallpaperAccentPalette,
} from "@/utils/dynamicAccentColor";

interface SettingsModalProps {
  isOpen: boolean;
  onOpenChange: (open: boolean) => void;
  shortcutsCount?: number;
  displayMode: DisplayMode;
  onDisplayModeChange: (mode: DisplayMode) => void;
  shortcutCompactShowTitle: boolean;
  onShortcutCompactShowTitleChange: (show: boolean) => void;
  shortcutGridColumns: number;
  onShortcutGridColumnsChange: (columns: number) => void;
  openInNewTab: boolean;
  onOpenInNewTabChange: (checked: boolean) => void;
  preventDuplicateNewTab: boolean;
  onPreventDuplicateNewTabChange: (checked: boolean) => void;
  showTime: boolean;
  onShowTimeChange: (checked: boolean) => void;
  onExportData: () => void | Promise<void>;
  onOpenImportSourceDialog: () => void;
  wallpaperMode: WallpaperMode;
  onWallpaperModeChange: (mode: WallpaperMode) => void;
  bingWallpaper: string;
  customWallpaper: string | null;
  onCustomWallpaperChange: (url: string) => void;
  colorWallpaperId: string;
  onColorWallpaperIdChange: (id: string) => void;
  wallpaperMaskOpacity: number;
  onWallpaperMaskOpacityChange: (value: number) => void;
  onOpenWebdavConfig?: (options?: { enableAfterSave?: boolean; showConnectionFields?: boolean }) => void;
  onWebdavSync?: (config: WebdavConfig) => Promise<void>;
  onWebdavEnable?: () => Promise<void> | void;
  onWebdavDisable?: (options?: { clearLocal?: boolean }) => Promise<void> | void;
  onOpenWallpaperSettings?: () => void;
  onOpenShortcutIconSettings?: () => void;
}

export default function SettingsModal({
  isOpen,
  onOpenChange,
  shortcutsCount = 0,
  displayMode,
  onDisplayModeChange,
  shortcutCompactShowTitle,
  onShortcutCompactShowTitleChange,
  shortcutGridColumns,
  onShortcutGridColumnsChange,
  openInNewTab,
  onOpenInNewTabChange,
  preventDuplicateNewTab,
  onPreventDuplicateNewTabChange,
  showTime,
  onShowTimeChange,
  onExportData,
  onOpenImportSourceDialog,
  wallpaperMode,
  onWallpaperModeChange,
  bingWallpaper,
  customWallpaper,
  onCustomWallpaperChange,
  colorWallpaperId,
  onColorWallpaperIdChange,
  wallpaperMaskOpacity,
  onWallpaperMaskOpacityChange,
  onOpenWebdavConfig,
  onWebdavSync,
  onWebdavEnable,
  onWebdavDisable,
  onOpenWallpaperSettings,
  onOpenShortcutIconSettings,
}: SettingsModalProps) {
  const { t, i18n } = useTranslation();
  const { theme, setTheme, resolvedTheme } = useTheme();
  void shortcutCompactShowTitle;
  void onShortcutCompactShowTitleChange;
  void shortcutGridColumns;
  void onShortcutGridColumnsChange;
  void onWallpaperModeChange;
  void onCustomWallpaperChange;
  void onColorWallpaperIdChange;
  void wallpaperMaskOpacity;
  void onWallpaperMaskOpacityChange;
  void shortcutsCount;
  void onOpenWebdavConfig;
  void onWebdavSync;
  void onWebdavEnable;
  void onWebdavDisable;
  const [mounted, setMounted] = useState(false);
  const [accentColor, setAccentColor] = useState<string>(DEFAULT_ACCENT_COLOR);
  const [recommendedAccentPalette, setRecommendedAccentPalette] = useState<string[]>(DEFAULT_WALLPAPER_ACCENT_PALETTE);
  const [appVersion, setAppVersion] = useState<string>('—');
  const [settingsPage, setSettingsPage] = useState<'main' | 'about'>('main');

  const isDarkTheme = resolvedTheme === 'dark';
  const colorOptions = useMemo(() => {
    const recommendedOptions = Array.from({ length: 6 }, (_, index) => ({
      name: getWallpaperAccentSlotKey(index),
      value: recommendedAccentPalette[index] || DEFAULT_WALLPAPER_ACCENT_PALETTE[index],
      accentDetailColor: resolveAccentDetailColor(recommendedAccentPalette[index] || DEFAULT_WALLPAPER_ACCENT_PALETTE[index]),
      label: t('settings.accent.recommended', {
        index: index + 1,
        defaultValue: `Recommended ${index + 1}`,
      }),
    }));
    return [
      ...recommendedOptions,
      {
        name: ADAPTIVE_NEUTRAL_ACCENT,
        value: resolveAdaptiveNeutralAccent(isDarkTheme),
        accentDetailColor: resolveAccentDetailColor(resolveAdaptiveNeutralAccent(isDarkTheme)),
        label: t('settings.accent.adaptiveNeutral', {
          defaultValue: 'Adaptive neutral',
        }),
      },
    ];
  }, [isDarkTheme, recommendedAccentPalette, t]);
  const currentThemeValue = mounted ? (theme ?? 'system') : 'system';
  const renderDisplayModeIcon = (mode: DisplayMode, className: string) => {
    if (mode === 'fresh') return <RiFlashlightFill className={className} />;
    return <RiCheckboxBlankFill className={className} />;
  };
  const renderThemeModeIcon = (mode: 'system' | 'light' | 'dark', className: string) => {
    if (mode === 'light') return <RiSunFill className={className} />;
    if (mode === 'dark') return <RiMoonFill className={className} />;
    return <RiComputerFill className={className} />;
  };

  const changeLanguage = (value: string) => {
    i18n.changeLanguage(value);
    localStorage.setItem('i18nextLng', value);
  };
  const languageValue = useMemo(() => {
    const raw = (i18n.language || '').trim();
    if (!raw) return 'zh';
    const lowered = raw.toLowerCase();
    if (lowered.startsWith('zh')) return 'zh';
    if (lowered.startsWith('en')) return 'en';
    return 'en';
  }, [i18n.language]);
  const settingsHeroCopy = useMemo(() => {
    const isChinese = languageValue === 'zh';
    return {
      title: isChinese ? 'Aira 新标签页' : 'Aira New Tab',
      subtitle: isChinese ? 'Minimal by Design. Powerful in Use.' : 'Minimal by Design. Powerful in Use.',
      badges: isChinese
        ? ['开源', '浏览器书签', 'WebDAV 同步']
        : ['Open Source', 'Browser Bookmarks', 'WebDAV Sync'],
    };
  }, [languageValue]);

  useEffect(() => {
    setMounted(true);
    const syncAccent = () => {
      const savedColor = localStorage.getItem('accentColor') || DEFAULT_ACCENT_COLOR;
      setAccentColor(savedColor);
    };
    syncAccent();
    window.addEventListener('leaftab-accent-color-changed', syncAccent);
    return () => window.removeEventListener('leaftab-accent-color-changed', syncAccent);
  }, []);
  useEffect(() => {
    if (!isOpen) setSettingsPage('main');
  }, [isOpen]);
  useEffect(() => {
    let canceled = false;
    resolveWallpaperAccentPalette({
      wallpaperMode,
      bingWallpaper,
      customWallpaper,
      colorWallpaperId,
    })
      .then((palette) => {
        if (canceled) return;
        setRecommendedAccentPalette(
          palette.length >= 6
            ? palette.slice(0, 6)
            : [...palette, ...DEFAULT_WALLPAPER_ACCENT_PALETTE].slice(0, 6),
        );
      })
      .catch(() => {
        if (canceled) return;
        setRecommendedAccentPalette(DEFAULT_WALLPAPER_ACCENT_PALETTE);
      });
    return () => {
      canceled = true;
    };
  }, [bingWallpaper, colorWallpaperId, customWallpaper, wallpaperMode]);
  useEffect(() => {
    try {
      if (typeof chrome !== 'undefined' && chrome.runtime?.getManifest) {
        const manifest = chrome.runtime.getManifest();
        const v = manifest.version_name || manifest.version || '—';
        setAppVersion(v);
        return;
      }
    } catch {}
    try {
      fetch('/manifest.json')
        .then((r) => r.json())
        .then((m) => setAppVersion(m?.version_name || m?.version || '—'))
        .catch(() => setAppVersion('0.1.0'));
    } catch {
      setAppVersion('0.1.0');
    }
  }, []);

  const handleColorChange = (colorName: string) => {
    setAccentColor(colorName);
    localStorage.setItem('accentColor', colorName);
    document.documentElement.setAttribute('data-accent-color', colorName);
    window.dispatchEvent(new Event('leaftab-accent-color-changed'));
  };

  const handleOpenShortcutIconSettings = () => {
    onOpenChange(false);
    onOpenShortcutIconSettings?.();
  };

  const handleOpenWallpaperSettings = () => {
    onOpenChange(false);
    onOpenWallpaperSettings?.();
  };

  return (
    <>
    <Dialog open={isOpen} onOpenChange={onOpenChange}>
        <DialogContent
          data-testid="settings-modal"
          surfaceVariant="frosted"
          className="sm:max-w-[600px] max-h-[calc(100vh-1.5rem)] border-border text-foreground rounded-[32px] overflow-visible"
        >
        <DialogHeader className="pb-3 pr-8">
          <DialogTitle className="text-foreground">
            {settingsPage === 'about' ? t('settings.about.title') : t('settings.title')}
          </DialogTitle>
        </DialogHeader>
        <ScrollArea
          className="max-h-[78vh]"
          scrollBarClassName="data-[orientation=vertical]:translate-x-4"
        >
          {settingsPage === 'about' ? (
          <div className="flex flex-col gap-5">
            <div>
              <Button
                type="button"
                variant="ghost"
                size="sm"
                className="-ml-2 h-8 gap-1 rounded-xl px-2 text-muted-foreground hover:text-foreground"
                onClick={() => setSettingsPage('main')}
              >
                <RiArrowLeftSLine className="size-4" />
                {t('common.back')}
              </Button>
            </div>
            <div className="relative flex flex-col items-center justify-center px-4 py-3 text-center">
              <div className="frosted-control-surface relative flex h-[64px] w-[64px] items-center justify-center rounded-[20px] ring-1 ring-border/60">
                <img
                  src={aboutIcon}
                  alt=""
                  aria-hidden="true"
                  className="h-[34px] w-[34px]"
                  draggable={false}
                />
              </div>
              <h2 className="mt-4 text-[18px] font-bold leading-none text-foreground">
                Aira
              </h2>
              <p className="mt-3 max-w-[420px] text-sm leading-6 text-muted-foreground">
                {t('settings.about.intro')}
              </p>
            </div>
            <div className="frosted-control-surface flex flex-col gap-3 rounded-2xl p-4">
              <div className="flex items-center justify-between gap-3">
                <div className="flex items-center gap-2">
                  <RiInformationFill className="size-4 text-primary" />
                  <span className="text-sm font-medium text-foreground">
                    {t('settings.about.version')}
                  </span>
                </div>
                <span className="text-sm font-medium text-muted-foreground">
                  v{appVersion}
                </span>
              </div>
              <Separator className="bg-border/60" />
              <div className="flex flex-col gap-2 text-xs leading-5 text-muted-foreground">
                <span>{t('settings.about.highlights.bookmarks')}</span>
                <span>{t('settings.about.highlights.sync')}</span>
                <span>{t('settings.about.highlights.privacy')}</span>
              </div>
            </div>
          </div>
          ) : (
          <div className="flex flex-col gap-5">
            <div className="relative flex flex-col items-center justify-center px-4 pt-1 text-center">
              <div className="frosted-control-surface relative flex h-[48px] w-[48px] items-center justify-center rounded-[16px] ring-1 ring-border/60">
                <img
                  src={aboutIcon}
                  alt=""
                  aria-hidden="true"
                  className="h-[26px] w-[26px]"
                  draggable={false}
                />
              </div>
              <div className="relative mt-3 flex w-full max-w-[420px] flex-col items-center gap-0.5">
                <h2 className="max-w-full text-[16px] font-bold leading-none tracking-[-0.03em] text-foreground">
                  {settingsHeroCopy.title}
                </h2>
                <p className="max-w-[240px] text-[10px] font-normal leading-[1.25] text-foreground/78">
                  {settingsHeroCopy.subtitle}
                </p>
              </div>
              <div className="relative mt-1.5 flex flex-wrap items-center justify-center gap-x-2 text-[10px] font-medium text-foreground/70">
                {settingsHeroCopy.badges.map((badge, index) => (
                  <div key={badge} className="inline-flex items-center gap-x-2">
                    {index > 0 ? <span aria-hidden="true" className="text-foreground/35">•</span> : null}
                    <span>{badge}</span>
                  </div>
                ))}
              </div>
            </div>
            {/* Display Mode Selection */}
            <div className="flex flex-col gap-3">
              <div className="grid grid-cols-3 gap-3">
                {DISPLAY_MODE_OPTIONS.map((option) => (
                  <button
                    key={option.value}
                    type="button"
                    className={`flex h-11 items-center justify-center gap-2.5 rounded-xl px-3 py-2 text-center transition-all ${displayMode === option.value ? 'bg-primary/10 text-primary' : 'frosted-control-surface text-foreground'}`}
                    onClick={() => { onDisplayModeChange(option.value); onOpenChange(false); }}
                  >
                    {renderDisplayModeIcon(option.value, "size-4.5 shrink-0")}
                    <div className="text-sm font-medium leading-none">
                      {t(option.labelKey)}
                    </div>
                  </button>
                ))}
                <div
                  className="frosted-control-surface inline-flex h-11 items-center gap-1 rounded-full p-1"
                  role="radiogroup"
                  aria-label={t('settings.theme.label')}
                >
                  {([
                    { value: 'system', label: t('settings.theme.system') },
                    { value: 'light', label: t('settings.theme.light') },
                    { value: 'dark', label: t('settings.theme.dark') },
                  ] as const).map((option) => {
                    const selected = currentThemeValue === option.value;
                    return (
                      <button
                        key={option.value}
                        type="button"
                        role="radio"
                        aria-checked={selected}
                        aria-label={option.label}
                        className={`flex h-full flex-1 items-center justify-center rounded-full transition-all focus:outline-none focus-visible:ring-0 ${selected ? 'bg-primary text-primary-foreground shadow-sm' : 'text-foreground/60 hover:bg-background/50 hover:text-foreground'}`}
                        onClick={() => setTheme(option.value)}
                      >
                        {renderThemeModeIcon(option.value, "size-4.5")}
                      </button>
                    );
                  })}
                </div>
              </div>
            </div>
            <div className="flex flex-col gap-3">
            <div className="flex w-full items-center justify-center px-2">
              <div className="grid w-full grid-cols-4 place-items-center gap-x-3 gap-y-3 sm:grid-cols-7">
                {colorOptions.map((option) => (
                  <button
                    key={option.name}
                    onClick={() => handleColorChange(option.name)}
                    className={`relative flex size-10 appearance-none items-center justify-center overflow-hidden rounded-full border-none outline-none ring-0 shadow-none transition-transform focus:outline-none focus-visible:outline-none focus-visible:ring-0 ${accentColor === option.name ? 'scale-105 brightness-[1.02]' : 'hover:scale-[1.04]'}`}
                    style={{ backgroundColor: option.value, border: 'none', boxShadow: 'none' }}
                    aria-label={option.label}
                  >
                    {accentColor === option.name ? (
                      <RiCheckFill
                        className="size-5 stroke-[3]"
                        style={{ color: option.accentDetailColor }}
                      />
                    ) : null}
                  </button>
                ))}
              </div>
            </div>
            </div>
            <Separator className="bg-border/60" />
            <div className="flex items-center justify-between space-x-2">
              <div className="flex flex-col space-y-1 items-start">
                <span className="text-sm font-medium leading-none">{t('wallpaper.mode')}</span>
                <span className="font-normal text-xs text-muted-foreground">{t('wallpaper.modeDesc')}</span>
              </div>
              <Button
                variant="secondary"
                size="sm"
                className="!h-[34px] !min-w-[108px] px-6 gap-2 rounded-xl shrink-0"
                onClick={handleOpenWallpaperSettings}
                >
                  {t('settings.shortcutsLayout.set')}
                </Button>
              </div>
              <div className="flex items-center justify-between gap-3">
                <div className="flex flex-col space-y-1 items-start">
                  <span className="text-sm font-medium leading-none">{t('settings.shortcutIconSettings.label', { defaultValue: '图标设置' })}</span>
                  <span className="font-normal text-xs text-muted-foreground">{t('settings.shortcutIconSettings.entryDescription', { defaultValue: '调整快捷方式图标的颜色模式与圆角' })}</span>
                </div>
                <Button
                  variant="secondary"
                  size="sm"
                  className="!h-[34px] !min-w-[108px] px-6 gap-2 rounded-xl shrink-0"
                  onClick={handleOpenShortcutIconSettings}
                >
                  {t('settings.shortcutIconSettings.open', { defaultValue: '打开' })}
                </Button>
              </div>
            <Separator className="bg-border/60" />
            <div className="flex items-center justify-between space-x-2">
              <div className="flex flex-col space-y-1 items-start">
                <span className="text-sm font-medium leading-none">{t('settings.newTabMode.label')}</span>
                <span className="font-normal text-xs text-muted-foreground">{t('settings.newTabMode.description')}</span>
              </div>
              <Switch
                id="new-tab-mode"
                checked={openInNewTab}
                onCheckedChange={onOpenInNewTabChange}
                className="relative flex h-6 w-10 items-center justify-start rounded-full border border-border p-0.5 transition-colors data-[state=checked]:justify-end data-[state=checked]:bg-primary data-[state=unchecked]:bg-input"
              >
                <SwitchThumb className="h-full aspect-square rounded-full" pressedAnimation={{ width: 22 }} />
              </Switch>
            </div>
            <div className="flex items-center justify-between space-x-2">
              <div className="flex flex-col space-y-1 items-start">
                <span className="text-sm font-medium leading-none">{t('settings.preventDuplicateNewTab.label')}</span>
                <span className="font-normal text-xs text-muted-foreground">{t('settings.preventDuplicateNewTab.description')}</span>
              </div>
              <Switch
                id="prevent-duplicate-newtab"
                checked={preventDuplicateNewTab}
                onCheckedChange={onPreventDuplicateNewTabChange}
                className="relative flex h-6 w-10 items-center justify-start rounded-full border border-border p-0.5 transition-colors data-[state=checked]:justify-end data-[state=checked]:bg-primary data-[state=unchecked]:bg-input"
              >
                <SwitchThumb className="h-full aspect-square rounded-full" pressedAnimation={{ width: 22 }} />
              </Switch>
            </div>

            <div className="flex items-center justify-between space-x-2">
              <div className="flex flex-col space-y-1 items-start">
                <span className="text-sm font-medium leading-none">{t('settings.showTime.label')}</span>
                <span className="font-normal text-xs text-muted-foreground">{t('settings.showTime.description')}</span>
              </div>
              <Switch
                id="show-time"
                checked={showTime}
                onCheckedChange={onShowTimeChange}
                className="relative flex h-6 w-10 items-center justify-start rounded-full border border-border p-0.5 transition-colors data-[state=checked]:justify-end data-[state=checked]:bg-primary data-[state=unchecked]:bg-input"
              >
                <SwitchThumb className="h-full aspect-square rounded-full" pressedAnimation={{ width: 22 }} />
              </Switch>
            </div>
          <Separator className="bg-border/60" />
          <div className="flex items-center justify-between space-x-2">
            <div className="flex flex-col space-y-1 items-start">
              <span className="text-sm font-medium leading-none">{t('settings.language.label')}</span>
              <span className="font-normal text-xs text-muted-foreground">{t('settings.language.description')}</span>
            </div>
            <Select value={languageValue} onValueChange={changeLanguage}>
              <SelectTrigger className="w-[126px] border-none text-foreground focus:ring-0 focus:ring-offset-0">
                <SelectValue placeholder={t('settings.language.selectPlaceholder')} />
              </SelectTrigger>
              <SelectContent portalled={false} className="bg-popover border-border text-popover-foreground">
                <SelectItem value="zh" className="focus:bg-accent focus:text-accent-foreground">{t('languages.zh')}</SelectItem>
                <SelectItem value="en" className="focus:bg-accent focus:text-accent-foreground">{t('languages.en')}</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="flex flex-col gap-3 py-2">
            <div className="flex flex-col space-y-1 items-start">
              <span className="text-sm font-medium leading-none">
                {t('settings.backup.bookmarksLabel', { defaultValue: '书签导入导出' })}
              </span>
              <span className="font-normal text-xs text-muted-foreground">
                {t('settings.backup.bookmarksDescription', { defaultValue: '支持 Chrome、Edge 等浏览器的书签 HTML 格式' })}
              </span>
            </div>
            <div className="flex gap-2">
              <Button 
                variant="secondary" 
                size="sm" 
                className="flex-1 gap-2 rounded-xl"
                onClick={() => {
                  onOpenChange(false);
                  onOpenImportSourceDialog();
                }}
              >
                <RiDownload2Fill className="size-4" />
                {t('settings.backup.importBookmarks', { defaultValue: '导入书签' })}
              </Button>
              <Button 
                variant="secondary" 
                size="sm" 
                className="flex-1 gap-2 rounded-xl"
                onClick={() => {
                  onOpenChange(false);
                  void onExportData();
                }}
              >
                <RiUpload2Fill className="size-4" />
                {t('settings.backup.exportBookmarks', { defaultValue: '导出书签' })}
              </Button>
            </div>
          </div>

          <Separator className="bg-border/60" />
          <div className="flex items-center justify-between gap-3">
            <div className="flex flex-col space-y-1 items-start">
              <span className="text-sm font-medium leading-none">{t('settings.about.label')}</span>
              <span className="font-normal text-xs text-muted-foreground">{t('settings.about.description')}</span>
            </div>
            <Button
              variant="secondary"
              size="sm"
              className="!h-[34px] !min-w-[108px] px-6 gap-2 rounded-xl shrink-0"
              onClick={() => setSettingsPage('about')}
            >
              {t('settings.about.open')}
            </Button>
          </div>

          <div className="pt-1 flex flex-col items-center">
            <span className="text-xs text-muted-foreground">
              {t('settings.privacyPolicy')}
            </span>
            <div className="text-[10px] text-muted-foreground/60">
              &copy; {new Date().getFullYear()} Aira. {t('settings.copyright')}
            </div>
            <div className="text-[10px] text-muted-foreground/60 flex items-center gap-2">
              <span className="text-[10px] text-muted-foreground/60">
                v{appVersion}
              </span>
            </div>
          </div>

          </div>
          )}
        </ScrollArea>
      </DialogContent>
    </Dialog>
    </>
  );
}
