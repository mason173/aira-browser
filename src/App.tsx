/// <reference types="chrome" />

import {
  lazy,
  Suspense,
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type ChangeEvent,
  type CSSProperties,
} from 'react';
import { flushSync } from 'react-dom';
import { useTranslation } from 'react-i18next';
import { useTheme } from 'next-themes';
import {
  applyShortcutDropIntent,
  dissolveFolder,
  mergeShortcutsIntoNewFolder,
  moveShortcutsIntoFolder,
  ROOT_SHORTCUTS_PATH,
  type FolderExtractDragStartPayload,
  type FolderShortcutDropIntent,
  type RootShortcutDropIntent,
  type ShortcutDropIntent,
} from '@airatab/workspace-core';
import defaultWallpaperSrc from '@/assets/Default_wallpaper.webp?url';
import defaultProfile from '@/assets/profiles/default-profile.json';
import { Toaster, toast } from '@/components/ui/sonner';
import { HomeInteractiveSurface } from '@/components/home/HomeInteractiveSurface';
import { ShortcutSelectionShell } from '@/components/home/ShortcutSelectionShell';
import {
  getFolderPreviewRoot,
  getFolderPreviewSlotEntries,
  getFolderPreviewTitle,
} from '@/components/shortcuts/folderPreviewRegistry';
import { WallpaperBackdropProvider } from '@/components/wallpaper/WallpaperBackdropContext';
import {
  useFolderTransitionActiveFolderId,
  useFolderTransitionController,
  useFolderTransitionState,
  type ShortcutFolderOpeningSourceSnapshot,
} from '@/components/folderTransition/useFolderTransitionController';
import { FolderTransitionDocumentEffects } from '@/components/folderTransition/FolderTransitionDocumentEffects';
import { ShortcutAppProvider } from '@/features/shortcuts/app/ShortcutAppContext';
import { openCreateShortcutEditor } from '@/features/shortcuts/app/shortcutEditorState';
import { useShortcutStore } from '@/features/shortcuts/model/useShortcutStore';
import { useShortcutUiState } from '@/features/shortcuts/model/useShortcutUiState';
import { useShortcutActions } from '@/hooks/useShortcutActions';
import { useShortcutWorkspaceController } from '@/features/shortcuts/workspace/useShortcutWorkspaceController';
import { createLeaftabGridEngineHostAdapter } from '@/features/shortcuts/gridEngine/leaftabGridEngineHostAdapter';
import { getColorWallpaperGradient } from '@/components/wallpaper/colorWallpapers';
import { DEFAULT_SHORTCUT_CARD_VARIANT, clampShortcutGridColumns } from '@/components/shortcuts/shortcutCardVariant';
import { getDisplayModeLayoutFlags } from '@/displayMode/config';
import { useInitialReveal } from '@/hooks/useInitialReveal';
import { useNewtabBootstrapFocus } from '@/hooks/useNewtabBootstrapFocus';
import { useResponsiveLayout } from '@/hooks/useResponsiveLayout';
import { useSettings } from '@/hooks/useSettings';
import { useWallpaper } from '@/hooks/useWallpaper';
import { useBlurredWallpaperAsset } from '@/hooks/useBlurredWallpaperAsset';
import { useLiteDisplayWallpaperSrc } from '@/hooks/useLiteDisplayWallpaperSrc';
import { useWallpaperRevealController } from '@/hooks/useWallpaperRevealController';
import { scaleShortcutIconSize } from '@/utils/shortcutIconSettings';
import { normalizeShortcutIconColor } from '@/utils/shortcutIconPreferences';
import {
  findShortcutById,
  isShortcutFolder,
  isShortcutLink,
  pruneEmptyShortcutFolders,
} from '@/utils/shortcutFolders';
import {
  normalizeScenarioModesList as normalizeScenarioModesListRaw,
  normalizeScenarioShortcuts as normalizeScenarioShortcutsRaw,
} from '@/utils/shortcutsPayload';
import { hasShortcutUrlConflict } from '@/utils/shortcutIdentity';
import {
  persistLocalProfileSnapshot,
} from '@/utils/localProfileStorage';
import { recordRecentShortcutAddition } from '@/utils/recentShortcutAdditions';
import { applyDynamicAccentColor, resolveAccentColorSelection } from '@/utils/dynamicAccentColor';
import { DEFAULT_ACCENT_COLOR } from '@/utils/accentColor';
import type { Shortcut, ShortcutDraft, ShortcutFolderDisplayMode, ShortcutIconAppearance } from '@/types';
import type { SlashCommandDialogTarget } from '@/components/search/searchSlashCommands';
import type { WallpaperMode } from '@/wallpaper/types';
import type { RotatableWallpaperMode, WallpaperRotationInterval } from '@/wallpaper/rotation';
import type { WebdavConfigDialogProps } from '@/components/WebdavConfigDialog';

type FolderOverlaySnapshotRect = {
  left: number;
  top: number;
  width: number;
  height: number;
};

const BOOT_SHIELD_HANDOFF_REMOVE_MS = 260;
const LazyShortcutFolderCompactOverlay = lazy(() => import('@/components/ShortcutFolderCompactOverlay').then((module) => ({
  default: module.ShortcutFolderCompactOverlay,
})));
const LazyShortcutFolderNameDialog = lazy(() => import('@/components/ShortcutFolderNameDialog').then((module) => ({
  default: module.ShortcutFolderNameDialog,
})));
const LazySettingsModal = lazy(() => import('@/components/SettingsModal'));
const LazyWallpaperSelector = lazy(() => import('@/components/WallpaperSelector'));
const LazyWebdavConfigDialog = lazy(() => import('@/components/WebdavConfigDialog').then((module) => ({
  default: module.WebdavConfigDialog,
})));
const LazyBookmarkWebdavSyncHost = lazy(() => import('@/features/sync/bookmarks/BookmarkWebdavSyncHost').then((module) => ({
  default: module.BookmarkWebdavSyncHost,
})));
const LazyShortcutIconSettingsDialog = lazy(() => import('@/components/ShortcutIconSettingsDialog').then((module) => ({
  default: module.ShortcutIconSettingsDialog,
})));
const LazyShortcutModal = lazy(() => import('@/components/ShortcutModal'));
const LazyConfirmDialog = lazy(() => import('@/components/ConfirmDialog'));

function copyFolderOverlaySnapshotRect(rect: DOMRect | FolderOverlaySnapshotRect | null | undefined) {
  if (!rect) return null;
  return {
    left: rect.left,
    top: rect.top,
    width: rect.width,
    height: rect.height,
  };
}

function readElementBorderRadiusPx(element: HTMLElement | null | undefined) {
  if (!element || typeof window === 'undefined') return null;
  const computedStyle = window.getComputedStyle(element);
  const resolvedRadius = Number.parseFloat(computedStyle.borderTopLeftRadius || '0');
  return Number.isFinite(resolvedRadius) ? resolvedRadius : null;
}

function createFolderShortcutId() {
  try {
    if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
      return crypto.randomUUID();
    }
  } catch {}
  return `fld_${Date.now()}_${Math.random().toString(16).slice(2)}`;
}

function createShortcutId() {
  try {
    if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
      return crypto.randomUUID();
    }
  } catch {}
  return `sht_${Date.now()}_${Math.random().toString(16).slice(2)}`;
}

function readAccentColorSetting(): string {
  try {
    const stored = (localStorage.getItem('accentColor') || '').trim();
    return stored || DEFAULT_ACCENT_COLOR;
  } catch {
    return DEFAULT_ACCENT_COLOR;
  }
}

function resolveWallpaperMaskOpacityWithDarkModeAutoDim({
  userOpacity,
  isDarkTheme,
  autoDimEnabled,
}: {
  userOpacity: number;
  isDarkTheme: boolean;
  autoDimEnabled: boolean;
}) {
  const safeUserOpacity = Number.isFinite(userOpacity) ? Math.max(0, Math.min(100, userOpacity)) : 10;
  if (!isDarkTheme || !autoDimEnabled) return safeUserOpacity;
  const boostedRatio = 1 - (1 - safeUserOpacity / 100) * (1 - 0.12);
  return Math.max(safeUserOpacity, Math.min(85, boostedRatio * 100));
}

function openShortcutUrl(shortcut: Shortcut, openInNewTab: boolean) {
  if (isShortcutFolder(shortcut)) return;
  let url = shortcut.url.trim();
  if (!url || /^javascript:/i.test(url)) return;
  if (!/^[a-z][a-z0-9+.-]*:/i.test(url)) {
    url = `https://${url}`;
  }
  if (openInNewTab) {
    window.open(url, '_blank');
    return;
  }
  window.location.href = url;
}

export default function LiteApp() {
  const { t } = useTranslation();
  const { resolvedTheme } = useTheme();
  const pageFocusRef = useRef<HTMLDivElement>(null);
  const folderOverlayWarmupPromiseRef = useRef<Promise<unknown> | null>(null);
  const folderOpenRequestIdRef = useRef(0);

  const {
    settingsOpen,
    setSettingsOpen,
    displayMode,
    setDisplayMode,
    openInNewTab,
    setOpenInNewTab,
    tabSwitchSearchEngine,
    setTabSwitchSearchEngine,
    searchPrefixEnabled,
    setSearchPrefixEnabled,
    searchSiteDirectEnabled,
    setSearchSiteDirectEnabled,
    searchSiteShortcutEnabled,
    setSearchSiteShortcutEnabled,
    searchAnyKeyCaptureEnabled,
    setSearchAnyKeyCaptureEnabled,
    searchCalculatorEnabled,
    setSearchCalculatorEnabled,
    searchRotatingPlaceholderEnabled,
    setSearchRotatingPlaceholderEnabled,
    preventDuplicateNewTab,
    setPreventDuplicateNewTab,
    is24Hour,
    setIs24Hour,
    showDate,
    setShowDate,
    showWeekday,
    setShowWeekday,
    showLunar,
    setShowLunar,
    timeAnimationMode,
    setTimeAnimationMode,
    timeFont,
    setTimeFont,
    showSeconds,
    setShowSeconds,
    showTime,
    setShowTime,
    shortcutCompactShowTitle,
    setShortcutCompactShowTitle,
    shortcutGridColumns,
    setShortcutGridColumns,
    shortcutIconAppearance,
    setShortcutIconAppearance,
    shortcutIconCornerRadius,
    setShortcutIconCornerRadius,
    shortcutIconScale,
    setShortcutIconScale,
  } = useSettings();
  const responsiveLayout = useResponsiveLayout();
  const initialRevealReady = useInitialReveal(false);
  const [manualHomeRevealReady] = useState(true);
  const effectiveInitialRevealReady = initialRevealReady && manualHomeRevealReady;
  const [accentColorSetting, setAccentColorSetting] = useState(() => readAccentColorSetting());
  const [wallpaperImageReadyTick, setWallpaperImageReadyTick] = useState(0);
  const [wallpaperSettingsOpen, setWallpaperSettingsOpen] = useState(false);
  const [shortcutIconSettingsOpen, setShortcutIconSettingsOpen] = useState(false);
  const [webdavDialogOpen, setWebdavDialogOpen] = useState(false);
  const [leafTabSyncDialogOpen, setLeafTabSyncDialogOpen] = useState(false);
  const [webdavEnableAfterConfigSave, setWebdavEnableAfterConfigSave] = useState(false);
  const [webdavShowConnectionFields, setWebdavShowConnectionFields] = useState(false);
  const [syncConfigBackTarget, setSyncConfigBackTarget] = useState<'settings' | 'sync-center'>('settings');
  const [confirmDisableWebdavSyncOpen, setConfirmDisableWebdavSyncOpen] = useState(false);
  const [webdavSyncHostMounted, setWebdavSyncHostMounted] = useState(false);
  const [webdavConfigDialogProps, setWebdavConfigDialogProps] = useState<WebdavConfigDialogProps | null>(null);
  const disableWebdavSyncRef = useRef<(() => void) | null>(null);
  const [shortcutDeleteOpen, setShortcutDeleteOpen] = useState(false);
  const [shortcutToDelete, setShortcutToDelete] = useState<{ index: number; shortcut: Shortcut; parentFolderId?: string | null } | null>(null);
  const bookmarkImportInputRef = useRef<HTMLInputElement | null>(null);

  useLayoutEffect(() => {
    if (typeof document === 'undefined') return;
    const bootShield = document.getElementById('boot-shield');
    if (!bootShield) return;
    const handoffFrame = window.requestAnimationFrame(() => {
      bootShield.style.opacity = '0';
    });
    const cleanupTimer = window.setTimeout(() => {
      bootShield.remove();
    }, BOOT_SHIELD_HANDOFF_REMOVE_MS);
    return () => {
      window.cancelAnimationFrame(handoffFrame);
      window.clearTimeout(cleanupTimer);
    };
  }, []);

  useNewtabBootstrapFocus(pageFocusRef);

  const normalizeScenarioModesList = useCallback((raw: unknown) => (
    normalizeScenarioModesListRaw(raw, t('scenario.unnamed')).slice(0, 1)
  ), [t]);
  const normalizeScenarioShortcuts = useCallback((raw: unknown) => normalizeScenarioShortcutsRaw(raw), []);
  const localDirtyRef = useRef(false);
  const markShortcutStateDirty = useCallback(() => {
    localDirtyRef.current = true;
  }, []);
  const shortcutStore = useShortcutStore({
    normalizeScenarioModesList,
    normalizeScenarioShortcuts,
    defaultScenarioShortcuts: defaultProfile?.data?.scenarioShortcuts,
    onScenarioShortcutsDirty: markShortcutStateDirty,
  });
  const uiState = useShortcutUiState();
  const shortcutActions = useShortcutActions({
    user: null,
    openInNewTab,
    translate: t,
    reportDomain: () => {},
    onShortcutCreated: (shortcut) => {
      recordRecentShortcutAddition(shortcut.url);
    },
    shortcutModalMode: uiState.shortcutModalMode,
    currentInsertIndex: uiState.currentInsertIndex,
    currentEditScenarioId: uiState.currentEditScenarioId,
    selectedShortcut: uiState.selectedShortcut,
    updateScenarioShortcuts: shortcutStore.updateScenarioShortcuts,
    localDirtyRef,
    setScenarioModes: shortcutStore.setScenarioModes,
    setScenarioShortcuts: shortcutStore.setScenarioShortcuts,
    setSelectedScenarioId: shortcutStore.setSelectedScenarioId,
    setScenarioEditOpen: uiState.setScenarioEditOpen,
    setCurrentEditScenarioId: uiState.setCurrentEditScenarioId,
    setContextMenu: uiState.setContextMenu,
    setShortcutEditOpen: uiState.setShortcutEditOpen,
    setSelectedShortcut: uiState.setSelectedShortcut,
    setCurrentInsertIndex: uiState.setCurrentInsertIndex,
    setShortcutDeleteOpen: setShortcutDeleteOpen,
  });
  const shortcutApp = useMemo(() => ({
    ...shortcutStore,
    ...uiState,
    ...shortcutActions,
    isDragging: false,
    setIsDragging: () => {},
    localDirtyRef,
  }), [shortcutActions, shortcutStore, uiState]);

  const {
    selectedScenarioId,
    scenarioShortcuts,
    shortcuts,
    setScenarioShortcuts,
  } = shortcutStore;

  useEffect(() => {
    persistLocalProfileSnapshot({
      scenarioModes: shortcutStore.scenarioModes,
      selectedScenarioId,
      scenarioShortcuts,
    });
  }, [scenarioShortcuts, selectedScenarioId, shortcutStore.scenarioModes]);

  const {
    editingFolderId,
    setEditingFolderId,
    pendingRootFolderMerge,
    folderNameDialogOpen,
    setFolderNameDialogOpen,
    externalShortcutDragSession,
    pendingExtractHiddenShortcutId,
    activePendingExtractDrag,
    rootDisplayShortcuts,
    startFolderExtractDrag,
    markRootShortcutDragStart,
    markRootShortcutDragEnd,
    commitPendingFolderExtractPreview,
    consumeExternalDragSession,
    requestRootFolderMerge,
    closeFolderNameDialog,
    completeFolderNameFlow,
  } = useShortcutWorkspaceController({
    selectedScenarioId,
    shortcuts,
    onCommitPendingExtractPreview: ({ scenarioId, previewShortcuts }) => {
      setScenarioShortcuts((prev) => ({
        ...prev,
        [scenarioId]: previewShortcuts,
      }));
      markShortcutStateDirty();
    },
  });
  const folderTransitionController = useFolderTransitionController();
  const folderTransitionState = useFolderTransitionState(folderTransitionController);
  const openFolderId = useFolderTransitionActiveFolderId(folderTransitionController);
  const openFolderShortcut = useMemo(() => (
    openFolderId ? findShortcutById(shortcuts, openFolderId) : null
  ), [openFolderId, shortcuts]);
  const editingFolderShortcut = useMemo(() => (
    editingFolderId ? findShortcutById(shortcuts, editingFolderId) : null
  ), [editingFolderId, shortcuts]);

  useEffect(() => {
    if (openFolderId && !openFolderShortcut) {
      folderTransitionController.clearImmediately();
    }
  }, [folderTransitionController, openFolderId, openFolderShortcut]);

  const {
    bingWallpaper,
    isBingWallpaperRefreshing,
    refreshBingWallpaper,
    customWallpaperLoaded,
    customWallpaper,
    setCustomWallpaper,
    customWallpaperGallery,
    appendCustomWallpapers,
    wallpaperRotationSettings,
    setWallpaperRotationInterval,
    wallpaperMode,
    setWallpaperMode,
    colorWallpaperId,
    setColorWallpaperId,
    wallpaperMaskOpacity,
    setWallpaperMaskOpacity,
    darkModeAutoDimWallpaperEnabled,
    setDarkModeAutoDimWallpaperEnabled,
  } = useWallpaper({
    customGalleryActive: wallpaperSettingsOpen,
  });
  const effectiveWallpaperMode: WallpaperMode = wallpaperMode;
  const colorWallpaperGradient = getColorWallpaperGradient(colorWallpaperId);
  const isDarkTheme = resolvedTheme === 'dark';
  const effectiveWallpaperMaskOpacity = useMemo(() => (
    resolveWallpaperMaskOpacityWithDarkModeAutoDim({
      userOpacity: wallpaperMaskOpacity,
      isDarkTheme,
      autoDimEnabled: darkModeAutoDimWallpaperEnabled,
    })
  ), [darkModeAutoDimWallpaperEnabled, isDarkTheme, wallpaperMaskOpacity]);
  const bingWallpaperDisplaySrc = bingWallpaper || defaultWallpaperSrc;
  const freshWallpaperSrc = effectiveWallpaperMode === 'custom'
    ? (customWallpaper || '')
    : effectiveWallpaperMode === 'bing'
      ? bingWallpaperDisplaySrc
      : defaultWallpaperSrc;
  const fallbackWallpaperBackdropSrc = effectiveWallpaperMode === 'custom'
    ? (customWallpaper || defaultWallpaperSrc)
    : effectiveWallpaperMode === 'bing'
      ? bingWallpaperDisplaySrc
      : defaultWallpaperSrc;
  const displayModeFlags = getDisplayModeLayoutFlags(displayMode);
  const modeLayersVisible = true;
  const showOverlayWallpaperLayer = displayModeFlags.showOverlayBackground;
  const overlayBackgroundImageSrc = displayMode === 'fresh'
    ? freshWallpaperSrc
    : effectiveWallpaperMode === 'custom'
      ? (customWallpaper || '')
      : effectiveWallpaperMode === 'bing'
        ? bingWallpaperDisplaySrc
        : defaultWallpaperSrc;
  const usesImageWallpaperLayer = effectiveWallpaperMode !== 'color';
  const liteOverlayBackgroundImageSrc = useLiteDisplayWallpaperSrc({
    sourceUrl: overlayBackgroundImageSrc,
    enabled: showOverlayWallpaperLayer && usesImageWallpaperLayer && Boolean(overlayBackgroundImageSrc),
  });
  const {
    effectiveOverlayWallpaperSrc,
    wallpaperAnimatedLayerStyle,
    handleOverlayImageReady,
  } = useWallpaperRevealController({
    wallpaperMode: effectiveWallpaperMode,
    overlayBackgroundImageSrc: liteOverlayBackgroundImageSrc,
    usesImageWallpaperLayer,
    showOverlayWallpaperLayer,
    disableRevealAnimation: false,
  });
  const handleOverlayWallpaperReady = useCallback(() => {
    handleOverlayImageReady();
    setWallpaperImageReadyTick((value) => value + 1);
  }, [handleOverlayImageReady]);
  const wallpaperBlurSourceUrl = effectiveWallpaperMode === 'color' ? '' : effectiveOverlayWallpaperSrc;
  const {
    blurredWallpaperSrc,
    blurredWallpaperAverageLuminance,
    blurredWallpaperReady,
  } = useBlurredWallpaperAsset({
    sourceUrl: wallpaperBlurSourceUrl,
    enabled: showOverlayWallpaperLayer && effectiveWallpaperMode !== 'color' && Boolean(wallpaperBlurSourceUrl),
  });

  useEffect(() => {
    document.documentElement.setAttribute('data-browser-target', 'chromium');
    return () => {
      document.documentElement.removeAttribute('data-browser-target');
    };
  }, []);

  useEffect(() => {
    const syncAccentColorSetting = () => {
      setAccentColorSetting(readAccentColorSetting());
    };
    window.addEventListener('leaftab-accent-color-changed', syncAccentColorSetting);
    return () => window.removeEventListener('leaftab-accent-color-changed', syncAccentColorSetting);
  }, []);

  useLayoutEffect(() => {
    let canceled = false;
    document.documentElement.setAttribute('data-accent-color', accentColorSetting);
    resolveAccentColorSelection(accentColorSetting, {
      wallpaperMode: effectiveWallpaperMode,
      bingWallpaper,
      customWallpaper,
      colorWallpaperId,
    }, {
      forceImageResample: wallpaperImageReadyTick > 0,
      isDarkTheme,
    })
      .then((hex) => {
        if (!canceled) applyDynamicAccentColor(hex);
      })
      .catch(() => {
        if (!canceled) applyDynamicAccentColor('#3b82f6');
      });
    return () => {
      canceled = true;
    };
  }, [
    accentColorSetting,
    bingWallpaper,
    colorWallpaperId,
    customWallpaper,
    effectiveWallpaperMode,
    isDarkTheme,
    wallpaperImageReadyTick,
  ]);

  const normalizedGridColumns = clampShortcutGridColumns(shortcutGridColumns, DEFAULT_SHORTCUT_CARD_VARIANT, responsiveLayout.density);
  const minShortcutRows = responsiveLayout.baseRows;
  const displayRows = Math.max(
    Math.ceil(shortcuts.length / Math.max(normalizedGridColumns, 1)),
    minShortcutRows,
  );
  const scaledCompactShortcutSize = scaleShortcutIconSize(responsiveLayout.compactShortcutSize, shortcutIconScale);
  const shortcutRowHeight = scaledCompactShortcutSize + 24;
  const shortcutRowGap = responsiveLayout.compactRowGap;
  const shortcutsAreaHeight = displayRows * shortcutRowHeight + Math.max(0, displayRows - 1) * shortcutRowGap;

  const folderNameDialogInitialName = pendingRootFolderMerge
    ? t('context.newFolder', { defaultValue: '新文件夹' })
    : (editingFolderShortcut?.title || '');
  const folderNameDialogTitle = pendingRootFolderMerge
    ? t('context.nameFolder', { defaultValue: '给分组起个名字' })
    : undefined;
  const folderNameDialogDescription = pendingRootFolderMerge
    ? t('context.nameFolderDesc', { defaultValue: '只有点确定后，这两个图标才会真正编成组。' })
    : undefined;

  const captureFolderOpeningSourceSnapshot = useCallback((folderId: string) => {
    const sourcePreview = getFolderPreviewRoot(folderId);
    const sourceRect = copyFolderOverlaySnapshotRect(sourcePreview?.getBoundingClientRect());
    if (!sourceRect) return null;
    const previewSlots = getFolderPreviewSlotEntries(folderId);
    const sourceChildSlotRects: FolderOverlaySnapshotRect[] = [];
    const sourceChildRects: ShortcutFolderOpeningSourceSnapshot['sourceChildRects'] = [];
    previewSlots.forEach((slot) => {
      const rect = copyFolderOverlaySnapshotRect(slot.element.getBoundingClientRect());
      if (!rect) return;
      sourceChildSlotRects[slot.index] = rect;
      sourceChildRects.push({
        childId: slot.childId,
        rect,
      });
    });
    return {
      folderId,
      sourceRect,
      sourceBorderRadius: readElementBorderRadiusPx(sourcePreview),
      sourceTitleRect: copyFolderOverlaySnapshotRect(getFolderPreviewTitle(folderId)?.getBoundingClientRect()),
      sourceChildRects,
      sourceChildSlotRects: sourceChildSlotRects.filter(Boolean),
    };
  }, []);

  const ensureFolderOverlayReady = useCallback(() => {
    if (!folderOverlayWarmupPromiseRef.current) {
      folderOverlayWarmupPromiseRef.current = import('@/components/ShortcutFolderCompactOverlay');
    }
    return folderOverlayWarmupPromiseRef.current;
  }, []);

  const handleShortcutActivate = useCallback((shortcut: Shortcut) => {
    if (isShortcutFolder(shortcut)) {
      const openRequestId = folderOpenRequestIdRef.current + 1;
      folderOpenRequestIdRef.current = openRequestId;
      void ensureFolderOverlayReady()
        .catch(() => null)
        .then(() => {
          if (folderOpenRequestIdRef.current !== openRequestId) return;
          folderTransitionController.openFolder(shortcut.id, captureFolderOpeningSourceSnapshot(shortcut.id));
        });
      return;
    }
    folderOpenRequestIdRef.current += 1;
    openShortcutUrl(shortcut, openInNewTab);
  }, [captureFolderOpeningSourceSnapshot, ensureFolderOverlayReady, folderTransitionController, openInNewTab]);

  const handleOpenShortcutEditor = useCallback((shortcutIndex: number, shortcut: Shortcut) => {
    if (isShortcutFolder(shortcut)) {
      setEditingFolderId(shortcut.id);
      setFolderNameDialogOpen(true);
      return;
    }
    uiState.setSelectedShortcut({ index: shortcutIndex, shortcut });
    uiState.setEditingTitle(shortcut.title);
    uiState.setEditingUrl(shortcut.url);
    uiState.setShortcutModalMode('edit');
    uiState.setShortcutEditOpen(true);
  }, [setEditingFolderId, setFolderNameDialogOpen, uiState]);

  const handleOpenFolderChildShortcutEditor = useCallback((folderId: string, shortcut: Shortcut) => {
    folderTransitionController.runAfterClose(folderId, () => {
      uiState.setSelectedShortcut({ index: -1, shortcut, parentFolderId: folderId });
      uiState.setEditingTitle(shortcut.title);
      uiState.setEditingUrl(shortcut.url);
      uiState.setShortcutModalMode('edit');
      uiState.setShortcutEditOpen(true);
    });
  }, [folderTransitionController, uiState]);

  const handleDeleteShortcutRequest = useCallback((target: { index: number; shortcut: Shortcut; parentFolderId?: string | null }) => {
    setShortcutToDelete(target);
    setShortcutDeleteOpen(true);
  }, []);

  const handleDeleteFolderChildShortcut = useCallback((folderId: string, shortcut: Shortcut) => {
    folderTransitionController.runAfterClose(folderId, () => {
      handleDeleteShortcutRequest({ index: -1, shortcut, parentFolderId: folderId });
    });
  }, [folderTransitionController, handleDeleteShortcutRequest]);

  const handleConfirmDeleteShortcut = useCallback(() => {
    if (!shortcutToDelete) return;
    setScenarioShortcuts((prev) => {
      const sourceShortcuts = prev[selectedScenarioId] ?? [];
      if (shortcutToDelete.parentFolderId) {
        const nextShortcuts = sourceShortcuts.map((item) => {
          if (item.id !== shortcutToDelete.parentFolderId || !isShortcutFolder(item)) return item;
          return {
            ...item,
            children: item.children?.filter((child) => child.id !== shortcutToDelete.shortcut.id) ?? [],
          };
        });
        return {
          ...prev,
          [selectedScenarioId]: pruneEmptyShortcutFolders(nextShortcuts),
        };
      }
      return {
        ...prev,
        [selectedScenarioId]: sourceShortcuts.filter((_, index) => index !== shortcutToDelete.index),
      };
    });
    markShortcutStateDirty();
    setShortcutDeleteOpen(false);
    setShortcutToDelete(null);
  }, [markShortcutStateDirty, selectedScenarioId, setScenarioShortcuts, shortcutToDelete]);

  const handleAddShortcutSearchAction = useCallback((target: { title: string; url: string; icon?: string }) => {
    const normalizedUrl = target.url.trim();
    if (!normalizedUrl) return;
    if (hasShortcutUrlConflict(shortcuts, normalizedUrl)) {
      toast.error(t('shortcutModal.errors.duplicateUrl', {
        defaultValue: '该网站已存在快捷方式',
      }));
      return;
    }
    const nextShortcut: Shortcut = {
      id: createShortcutId(),
      title: target.title.trim() || normalizedUrl,
      url: normalizedUrl,
      icon: target.icon || '',
      iconColor: normalizeShortcutIconColor(''),
    };
    setScenarioShortcuts((prev) => ({
      ...prev,
      [selectedScenarioId]: [nextShortcut, ...(prev[selectedScenarioId] || [])],
    }));
    markShortcutStateDirty();
    recordRecentShortcutAddition(nextShortcut.url);
    toast.success(t('search.shortcutAdded', { defaultValue: '已添加为快捷方式' }));
  }, [markShortcutStateDirty, selectedScenarioId, setScenarioShortcuts, shortcuts, t]);

  const handleShortcutDropIntent = useCallback((intent: ShortcutDropIntent) => {
    const sourceShortcuts = activePendingExtractDrag?.previewShortcuts ?? shortcuts;
    const outcome = applyShortcutDropIntent(sourceShortcuts, intent);
    if (outcome.kind === 'request-folder-merge') {
      requestRootFolderMerge({
        scenarioId: selectedScenarioId,
        activeShortcutId: outcome.activeShortcutId,
        targetShortcutId: outcome.targetShortcutId,
      });
      return;
    }
    if (outcome.kind !== 'update-shortcuts') return;
    setScenarioShortcuts((prev) => ({
      ...prev,
      [selectedScenarioId]: outcome.shortcuts,
    }));
    if (activePendingExtractDrag) {
      commitPendingFolderExtractPreview(outcome.shortcuts);
    }
    markShortcutStateDirty();
  }, [
    activePendingExtractDrag,
    commitPendingFolderExtractPreview,
    markShortcutStateDirty,
    requestRootFolderMerge,
    selectedScenarioId,
    setScenarioShortcuts,
    shortcuts,
  ]);

  const handleRootShortcutDropIntent = useCallback((intent: RootShortcutDropIntent) => {
    handleShortcutDropIntent(intent);
  }, [handleShortcutDropIntent]);
  const handleFolderShortcutDropIntent = useCallback((intent: FolderShortcutDropIntent) => {
    handleShortcutDropIntent(intent);
  }, [handleShortcutDropIntent]);
  const handleFolderExtractDragStart = useCallback((payload: FolderExtractDragStartPayload) => {
    flushSync(() => {
      startFolderExtractDrag(payload, {
        onCloseFolderOverlay: () => {
          folderTransitionController.clearImmediately();
        },
      });
    });
  }, [folderTransitionController, startFolderExtractDrag]);
  const handleRootShortcutDragStart = useCallback(() => {
    markRootShortcutDragStart();
  }, [markRootShortcutDragStart]);
  const handleRootShortcutDragEnd = useCallback(() => {
    markRootShortcutDragEnd();
  }, [markRootShortcutDragEnd]);
  const handleFolderEngineChildrenCommit = useCallback((folderId: string, children: Shortcut[]) => {
    setScenarioShortcuts((prev) => {
      const sourceShortcuts = prev[selectedScenarioId] ?? [];
      return {
        ...prev,
        [selectedScenarioId]: pruneEmptyShortcutFolders(sourceShortcuts.map((shortcut) => (
          shortcut.id === folderId && isShortcutFolder(shortcut)
            ? { ...shortcut, children }
            : shortcut
        ))),
      };
    });
    markShortcutStateDirty();
  }, [markShortcutStateDirty, selectedScenarioId, setScenarioShortcuts]);
  const handleRenameFolderInline = useCallback((folderId: string, name: string) => {
    const nextName = name.trim();
    if (!folderId || !nextName) return;
    setScenarioShortcuts((prev) => ({
      ...prev,
      [selectedScenarioId]: (prev[selectedScenarioId] ?? []).map((shortcut) => (
        shortcut.id === folderId && isShortcutFolder(shortcut)
          ? { ...shortcut, title: nextName }
          : shortcut
      )),
    }));
    markShortcutStateDirty();
  }, [markShortcutStateDirty, selectedScenarioId, setScenarioShortcuts]);
  const handleSaveFolderName = useCallback((name: string) => {
    const nextName = name.trim();
    if (!nextName) return;
    if (pendingRootFolderMerge) {
      setScenarioShortcuts((prev) => {
        const sourceShortcuts = prev[pendingRootFolderMerge.scenarioId] ?? [];
        const result = mergeShortcutsIntoNewFolder(
          sourceShortcuts,
          ROOT_SHORTCUTS_PATH,
          [pendingRootFolderMerge.activeShortcutId, pendingRootFolderMerge.targetShortcutId],
          (folderChildren) => ({
            id: createFolderShortcutId(),
            title: nextName,
            url: '',
            icon: '',
            kind: 'folder',
            folderDisplayMode: 'small',
            children: folderChildren,
          }),
        );
        if (!result) return prev;
        return {
          ...prev,
          [pendingRootFolderMerge.scenarioId]: result.nextShortcuts,
        };
      });
      markShortcutStateDirty();
      completeFolderNameFlow();
      return;
    }
    if (!editingFolderId) return;
    handleRenameFolderInline(editingFolderId, nextName);
    completeFolderNameFlow();
  }, [
    completeFolderNameFlow,
    editingFolderId,
    handleRenameFolderInline,
    markShortcutStateDirty,
    pendingRootFolderMerge,
    setScenarioShortcuts,
  ]);
  const handleSetFolderDisplayMode = useCallback((shortcutIndex: number, shortcut: Shortcut, mode: 'small' | 'large') => {
    if (!isShortcutFolder(shortcut)) return;
    const nextMode: ShortcutFolderDisplayMode = mode === 'large' ? 'large' : 'small';
    setScenarioShortcuts((prev) => {
      const sourceShortcuts = prev[selectedScenarioId] ?? [];
      const resolvedFolderId = sourceShortcuts[shortcutIndex]?.id === shortcut.id
        ? shortcut.id
        : sourceShortcuts.find((item) => item.id === shortcut.id)?.id;
      if (!resolvedFolderId) return prev;
      return {
        ...prev,
        [selectedScenarioId]: sourceShortcuts.map((item) => (
          item.id === resolvedFolderId && isShortcutFolder(item)
            ? { ...item, folderDisplayMode: nextMode }
            : item
        )),
      };
    });
    markShortcutStateDirty();
  }, [markShortcutStateDirty, selectedScenarioId, setScenarioShortcuts]);
  const handleCreateFolderFromSelection = useCallback((selectedShortcutIndexes: number[]) => {
    let createdFolderId = '';
    setScenarioShortcuts((prev) => {
      const sourceShortcuts = prev[selectedScenarioId] ?? [];
      const validIds = Array.from(new Set(
        selectedShortcutIndexes
          .filter((index) => Number.isInteger(index) && index >= 0 && index < sourceShortcuts.length)
          .map((index) => sourceShortcuts[index]?.id)
          .filter((id): id is string => Boolean(id)),
      ));
      const result = mergeShortcutsIntoNewFolder(sourceShortcuts, ROOT_SHORTCUTS_PATH, validIds, (folderChildren) => ({
        id: createFolderShortcutId(),
        title: t('context.newFolder', { defaultValue: '新文件夹' }),
        url: '',
        icon: '',
        kind: 'folder',
        folderDisplayMode: 'small',
        children: folderChildren,
      }));
      if (!result) return prev;
      createdFolderId = result.folder.id;
      return {
        ...prev,
        [selectedScenarioId]: result.nextShortcuts,
      };
    });
    markShortcutStateDirty();
    if (createdFolderId) {
      setEditingFolderId(createdFolderId);
      setFolderNameDialogOpen(true);
    }
  }, [markShortcutStateDirty, selectedScenarioId, setEditingFolderId, setFolderNameDialogOpen, setScenarioShortcuts, t]);
  const handleMoveSelectedShortcutsToFolder = useCallback((selectedShortcutIndexes: number[], targetFolderId: string) => {
    setScenarioShortcuts((prev) => {
      const sourceShortcuts = prev[selectedScenarioId] ?? [];
      const shortcutIds = selectedShortcutIndexes
        .filter((index) => Number.isInteger(index) && index >= 0 && index < sourceShortcuts.length)
        .filter((index) => isShortcutLink(sourceShortcuts[index]))
        .map((index) => sourceShortcuts[index]?.id)
        .filter((id): id is string => Boolean(id));
      const nextShortcuts = moveShortcutsIntoFolder(sourceShortcuts, ROOT_SHORTCUTS_PATH, shortcutIds, targetFolderId);
      if (!nextShortcuts) return prev;
      return {
        ...prev,
        [selectedScenarioId]: nextShortcuts,
      };
    });
    markShortcutStateDirty();
  }, [markShortcutStateDirty, selectedScenarioId, setScenarioShortcuts]);
  const handlePinSelectedShortcuts = useCallback((selectedShortcutIndexes: number[], position: 'top' | 'bottom') => {
    const validIndices = Array.from(new Set(selectedShortcutIndexes)).filter((index) => index >= 0 && index < shortcuts.length).sort((a, b) => a - b);
    if (validIndices.length === 0) return;
    const selectedSet = new Set(validIndices);
    const selectedItems = validIndices.map((index) => shortcuts[index]);
    const remainingItems = shortcuts.filter((_, index) => !selectedSet.has(index));
    const nextShortcuts = position === 'top' ? [...selectedItems, ...remainingItems] : [...remainingItems, ...selectedItems];
    shortcutActions.handleShortcutReorder(nextShortcuts);
    return position === 'top'
      ? selectedItems.map((_, index) => index)
      : selectedItems.map((_, index) => remainingItems.length + index);
  }, [shortcutActions, shortcuts]);
  const handleDissolveFolder = useCallback((shortcutIndex: number, shortcut: Shortcut) => {
    if (!isShortcutFolder(shortcut)) return;
    setScenarioShortcuts((prev) => {
      const sourceShortcuts = prev[selectedScenarioId] ?? [];
      const resolvedFolderId = sourceShortcuts[shortcutIndex]?.id === shortcut.id
        ? shortcut.id
        : sourceShortcuts.find((item) => item.id === shortcut.id)?.id;
      const nextShortcuts = resolvedFolderId ? dissolveFolder(sourceShortcuts, resolvedFolderId) : null;
      if (!nextShortcuts) return prev;
      return {
        ...prev,
        [selectedScenarioId]: nextShortcuts,
      };
    });
    markShortcutStateDirty();
    if (openFolderId === shortcut.id) {
      folderTransitionController.clearImmediately();
    }
  }, [folderTransitionController, markShortcutStateDirty, openFolderId, selectedScenarioId, setScenarioShortcuts]);
  const handleOpenWebdavSyncCenter = useCallback(() => {
    setWebdavSyncHostMounted(true);
    setSyncConfigBackTarget('sync-center');
    setWebdavDialogOpen(false);
    setSettingsOpen(false);
    setLeafTabSyncDialogOpen(true);
  }, [setSettingsOpen]);
  const handleOpenWebdavConfig = useCallback((options?: { enableAfterSave?: boolean; showConnectionFields?: boolean }) => {
    const shouldEnableAfterSave = options?.enableAfterSave ?? false;
    setWebdavSyncHostMounted(true);
    setSyncConfigBackTarget('settings');
    setWebdavEnableAfterConfigSave(Boolean(shouldEnableAfterSave));
    setWebdavShowConnectionFields(Boolean(options?.showConnectionFields ?? shouldEnableAfterSave));
    setWebdavDialogOpen(true);
    return true;
  }, []);
  const handleOpenSlashCommandDialog = useCallback((target: SlashCommandDialogTarget) => {
    if (target === 'sync-center') {
      handleOpenWebdavSyncCenter();
      return;
    }
    setSettingsOpen(true);
  }, [handleOpenWebdavSyncCenter, setSettingsOpen]);

  const topNavModeProps = useMemo(() => ({
    fadeOnIdle: true,
    onSettingsClick: () => setSettingsOpen(true),
    onSyncClick: handleOpenWebdavSyncCenter,
    syncStatus: 'idle' as const,
    leftSlot: null,
    introGuide: null,
  }), [handleOpenWebdavSyncCenter, setSettingsOpen]);
  const wallpaperClockBaseProps = useMemo(() => ({
    is24Hour,
    onIs24HourChange: setIs24Hour,
    showSeconds,
    onShowSecondsChange: setShowSeconds,
    showDate,
    onShowDateChange: setShowDate,
    showWeekday,
    onShowWeekdayChange: setShowWeekday,
    showLunar,
    onShowLunarChange: setShowLunar,
    timeAnimationMode,
    onTimeAnimationModeChange: setTimeAnimationMode,
    bingWallpaperUrl: bingWallpaper,
    onSettingsClick: () => setSettingsOpen(true),
    onSyncClick: handleOpenWebdavSyncCenter,
    syncStatus: 'idle' as const,
    wallpaperMode: effectiveWallpaperMode,
    customWallpaperLoaded,
    customWallpaper,
    colorWallpaperId,
    wallpaperMaskOpacity: effectiveWallpaperMaskOpacity,
    timeFont,
    onTimeFontChange: setTimeFont,
    layout: responsiveLayout,
  }), [
    bingWallpaper,
    colorWallpaperId,
    customWallpaper,
    customWallpaperLoaded,
    effectiveWallpaperMaskOpacity,
    effectiveWallpaperMode,
    handleOpenWebdavSyncCenter,
    is24Hour,
    responsiveLayout,
    setIs24Hour,
    setSettingsOpen,
    setShowDate,
    setShowLunar,
    setShowSeconds,
    setShowWeekday,
    setTimeAnimationMode,
    setTimeFont,
    showDate,
    showLunar,
    showSeconds,
    showWeekday,
    timeAnimationMode,
    timeFont,
  ]);
  const searchExperienceBaseProps = useMemo(() => ({
    openInNewTab,
    shortcuts,
    tabSwitchSearchEngine,
    searchPrefixEnabled,
    searchSiteDirectEnabled,
    searchSiteShortcutEnabled,
    searchAnyKeyCaptureEnabled,
    searchCalculatorEnabled,
    searchRotatingPlaceholderEnabled,
    disablePlaceholderAnimation: false,
    lightweightSearchUi: false,
    searchHeight: responsiveLayout.searchHeight,
    searchInputFontSize: responsiveLayout.searchInputFontSize,
    searchHorizontalPadding: responsiveLayout.searchHorizontalPadding,
    searchActionSize: responsiveLayout.searchActionSize,
    currentWallpaperMode: effectiveWallpaperMode,
    currentColorWallpaperId: colorWallpaperId,
    darkModeAutoDimWallpaperEnabled,
    currentShortcutIconAppearance: shortcutIconAppearance,
    currentShortcutIconCornerRadius: shortcutIconCornerRadius,
    currentShortcutIconScale: shortcutIconScale,
    shortcutShowTitleEnabled: shortcutCompactShowTitle,
    currentShortcutGridColumns: normalizedGridColumns,
    preventDuplicateNewTab,
    showTime,
    onEditShortcutAction: (target: { shortcut: Shortcut; index: number; parentFolderId?: string | null }) => {
      if (target.parentFolderId) {
        handleOpenFolderChildShortcutEditor(target.parentFolderId, target.shortcut);
        return;
      }
      handleOpenShortcutEditor(target.index, target.shortcut);
    },
    onDeleteShortcutAction: handleDeleteShortcutRequest,
    onAddShortcutAction: handleAddShortcutSearchAction,
    onSetShowTimeAction: setShowTime,
    onSetWallpaperModeAction: setWallpaperMode,
    onSetShortcutIconAppearanceAction: setShortcutIconAppearance,
    onSetSearchTabSwitchEngineAction: setTabSwitchSearchEngine,
    onSetSearchPrefixEnabledAction: setSearchPrefixEnabled,
    onSetSearchSiteDirectEnabledAction: setSearchSiteDirectEnabled,
    onSetSearchSiteShortcutEnabledAction: setSearchSiteShortcutEnabled,
    onSetSearchAnyKeyCaptureEnabledAction: setSearchAnyKeyCaptureEnabled,
    onSetSearchCalculatorEnabledAction: setSearchCalculatorEnabled,
    onSetSearchRotatingPlaceholderEnabledAction: setSearchRotatingPlaceholderEnabled,
    onSetShortcutShowTitleAction: setShortcutCompactShowTitle,
    onSetPreventDuplicateNewTabAction: setPreventDuplicateNewTab,
    onSetDarkModeAutoDimWallpaperAction: setDarkModeAutoDimWallpaperEnabled,
    onOpenSlashCommandDialog: handleOpenSlashCommandDialog,
  }), [
    colorWallpaperId,
    darkModeAutoDimWallpaperEnabled,
    effectiveWallpaperMode,
    handleAddShortcutSearchAction,
    handleDeleteShortcutRequest,
    handleOpenFolderChildShortcutEditor,
    handleOpenShortcutEditor,
    handleOpenSlashCommandDialog,
    normalizedGridColumns,
    openInNewTab,
    preventDuplicateNewTab,
    responsiveLayout,
    searchAnyKeyCaptureEnabled,
    searchCalculatorEnabled,
    searchPrefixEnabled,
    searchRotatingPlaceholderEnabled,
    searchSiteDirectEnabled,
    searchSiteShortcutEnabled,
    setDarkModeAutoDimWallpaperEnabled,
    setPreventDuplicateNewTab,
    setSearchAnyKeyCaptureEnabled,
    setSearchCalculatorEnabled,
    setSearchPrefixEnabled,
    setSearchRotatingPlaceholderEnabled,
    setSearchSiteDirectEnabled,
    setSearchSiteShortcutEnabled,
    setShortcutCompactShowTitle,
    setShortcutIconAppearance,
    setShowTime,
    setTabSwitchSearchEngine,
    setWallpaperMode,
    shortcutCompactShowTitle,
    shortcutIconAppearance,
    shortcutIconCornerRadius,
    shortcutIconScale,
    shortcuts,
    showTime,
    tabSwitchSearchEngine,
  ]);
  const shortcutEngineHostAdapter = useMemo(() => createLeaftabGridEngineHostAdapter({
    scenarioId: selectedScenarioId,
    shortcuts: rootDisplayShortcuts,
    surfaceStructureShortcuts: shortcuts,
    containerHeight: shortcutsAreaHeight,
    bottomInset: 0,
    gridColumns: normalizedGridColumns,
    minRows: minShortcutRows,
    layoutDensity: responsiveLayout.density,
    compactIconSize: scaledCompactShortcutSize,
    compactTitleFontSize: responsiveLayout.compactShortcutTitleSize,
    compactShowTitle: shortcutCompactShowTitle,
    highlightedShortcutId: null,
    iconCornerRadius: shortcutIconCornerRadius,
    iconAppearance: shortcutIconAppearance,
    disableReorderAnimation: Boolean(openFolderShortcut),
    onRootShortcutOpen: handleShortcutActivate,
    onFolderShortcutOpen: (shortcut) => openShortcutUrl(shortcut, openInNewTab),
    onShortcutContextMenu: shortcutActions.handleShortcutContextMenu,
    onShortcutReorder: shortcutActions.handleShortcutReorder,
    onShortcutDropIntent: handleRootShortcutDropIntent,
    onRootDragStart: handleRootShortcutDragStart,
    onRootDragEnd: handleRootShortcutDragEnd,
    onGridContextMenu: shortcutActions.handleGridContextMenu,
    externalDragSession: externalShortcutDragSession,
    onExternalDragSessionConsumed: consumeExternalDragSession,
    openFolderShortcut,
    onFolderOpenChange: (open) => {
      if (!open) folderTransitionController.requestClose();
    },
    onRenameFolder: handleRenameFolderInline,
    onFolderShortcutContextMenu: (event, folderId, shortcut) => {
      event.preventDefault();
      event.stopPropagation();
      uiState.setContextMenu({ x: event.clientX, y: event.clientY, kind: 'folder-shortcut', folderId, shortcut });
    },
    onFolderShortcutDropIntent: handleFolderShortcutDropIntent,
    onFolderExtractDragStart: handleFolderExtractDragStart,
    onFolderChildrenCommit: handleFolderEngineChildrenCommit,
  }), [
    consumeExternalDragSession,
    externalShortcutDragSession,
    folderTransitionController,
    handleFolderEngineChildrenCommit,
    handleFolderExtractDragStart,
    handleFolderShortcutDropIntent,
    handleRenameFolderInline,
    handleRootShortcutDragEnd,
    handleRootShortcutDragStart,
    handleRootShortcutDropIntent,
    handleShortcutActivate,
    minShortcutRows,
    normalizedGridColumns,
    openFolderShortcut,
    openInNewTab,
    responsiveLayout.compactShortcutTitleSize,
    responsiveLayout.density,
    rootDisplayShortcuts,
    scaledCompactShortcutSize,
    selectedScenarioId,
    shortcutActions.handleGridContextMenu,
    shortcutActions.handleShortcutContextMenu,
    shortcutActions.handleShortcutReorder,
    shortcutCompactShowTitle,
    shortcutIconAppearance,
    shortcutIconCornerRadius,
    shortcuts,
    shortcutsAreaHeight,
    uiState,
  ]);
  const homeMainContentBaseProps = useMemo(() => ({
    showTime,
    displayMode,
    is24Hour,
    onIs24HourChange: setIs24Hour,
    showSeconds,
    onShowSecondsChange: setShowSeconds,
    showDate,
    onShowDateChange: setShowDate,
    showWeekday,
    onShowWeekdayChange: setShowWeekday,
    showLunar,
    onShowLunarChange: setShowLunar,
    timeAnimationEnabled: false,
    timeAnimationMode,
    onTimeAnimationModeChange: setTimeAnimationMode,
    timeFont,
    onTimeFontChange: setTimeFont,
    layout: responsiveLayout,
    reduceMotionVisuals: false,
    topNavIntroCompleted: true,
  }), [
    displayMode,
    is24Hour,
    responsiveLayout,
    setIs24Hour,
    setShowDate,
    setShowLunar,
    setShowSeconds,
    setShowWeekday,
    setTimeAnimationMode,
    setTimeFont,
    showDate,
    showLunar,
    showSeconds,
    showTime,
    showWeekday,
    timeAnimationMode,
    timeFont,
  ]);
  const shortcutGridBaseProps = shortcutEngineHostAdapter.rootGridProps;

  const globalRevealUiStyle = useMemo<CSSProperties>(() => ({
    transform: 'scale(1)',
    transformOrigin: 'center center',
  }), []);
  const wallpaperBackdropValue = useMemo(() => ({
    wallpaperMode: effectiveWallpaperMode,
    colorWallpaperGradient,
    blurredWallpaperSrc,
    fallbackWallpaperSrc: effectiveWallpaperMode === 'color'
      ? ''
      : (liteOverlayBackgroundImageSrc || fallbackWallpaperBackdropSrc),
    blurredWallpaperAverageLuminance,
    effectiveWallpaperMaskOpacity,
  }), [
    blurredWallpaperAverageLuminance,
    blurredWallpaperSrc,
    colorWallpaperGradient,
    effectiveWallpaperMaskOpacity,
    effectiveWallpaperMode,
    fallbackWallpaperBackdropSrc,
    liteOverlayBackgroundImageSrc,
  ]);
  const homeSurfaceWallpaperBackdrop = useMemo(() => ({
    blurredWallpaperSrc,
    blurredWallpaperAverageLuminance,
    blurredWallpaperReady,
  }), [
    blurredWallpaperAverageLuminance,
    blurredWallpaperReady,
    blurredWallpaperSrc,
  ]);
  const handleShortcutModalOpenChange = useCallback((open: boolean) => {
    uiState.setShortcutEditOpen(open);
    if (!open) {
      uiState.setSelectedShortcut(null);
      uiState.setCurrentInsertIndex(null);
    }
  }, [uiState]);
  const handleBackToMainSettings = useCallback(() => {
    setWallpaperSettingsOpen(false);
    setShortcutIconSettingsOpen(false);
    setSettingsOpen(true);
  }, [setSettingsOpen]);
  const handleWallpaperSettingsOpenChange = useCallback((open: boolean) => {
    setWallpaperSettingsOpen(open);
    if (!open) setSettingsOpen(true);
  }, [setSettingsOpen]);
  const handleShortcutIconSettingsOpenChange = useCallback((open: boolean) => {
    setShortcutIconSettingsOpen(open);
    if (!open) setSettingsOpen(true);
  }, [setSettingsOpen]);
  const handleSaveShortcutIconStyle = useCallback((payload: {
    compactShowTitle: boolean;
    columns: number;
  }) => {
    setShortcutCompactShowTitle(payload.compactShowTitle);
    setShortcutGridColumns(payload.columns);
  }, [setShortcutCompactShowTitle, setShortcutGridColumns]);
  const handleSaveShortcutIconAppearance = useCallback((payload: {
    appearance: ShortcutIconAppearance;
    cornerRadius: number;
    scale: number;
  }) => {
    setShortcutIconAppearance(payload.appearance);
    setShortcutIconCornerRadius(payload.cornerRadius);
    setShortcutIconScale(payload.scale);
  }, [setShortcutIconAppearance, setShortcutIconCornerRadius, setShortcutIconScale]);
  const handleOpenWallpaperSettings = useCallback(() => {
    setSettingsOpen(false);
    setWallpaperSettingsOpen(true);
  }, [setSettingsOpen]);
  const handleOpenShortcutIconSettings = useCallback(() => {
    setSettingsOpen(false);
    setShortcutIconSettingsOpen(true);
  }, [setSettingsOpen]);
  const handleWallpaperRotationIntervalChange = useCallback((
    mode: RotatableWallpaperMode,
    interval: WallpaperRotationInterval,
  ) => {
    setWallpaperRotationInterval(mode, interval);
  }, [setWallpaperRotationInterval]);
  const handleExportBrowserBookmarks = useCallback(async () => {
    try {
      const { exportBrowserBookmarksAsHtml } = await import('@/utils/bookmarkHtml');
      const html = await exportBrowserBookmarksAsHtml();
      const blob = new Blob([html], { type: 'text/html;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = `bookmarks-${new Date().toISOString().slice(0, 10)}.html`;
      anchor.click();
      window.setTimeout(() => URL.revokeObjectURL(url), 1000);
      toast.success(t('settings.backup.exportSuccess', { defaultValue: '书签已导出' }));
    } catch (error) {
      toast.error(error instanceof Error ? error.message : t('settings.backup.exportError', { defaultValue: '书签导出失败' }));
    }
  }, [t]);

  const handleOpenBookmarkImport = useCallback(() => {
    bookmarkImportInputRef.current?.click();
  }, []);

  const handleBookmarkImportFileChange = useCallback(async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.currentTarget.files?.[0];
    event.currentTarget.value = '';
    if (!file) return;
    try {
      const html = await file.text();
      const { importBrowserBookmarksFromHtml } = await import('@/utils/bookmarkHtml');
      const result = await importBrowserBookmarksFromHtml(html);
      toast.success(t('settings.backup.bookmarkImportSuccess', {
        defaultValue: '已导入 {{count}} 个书签',
        count: result.bookmarkCount,
      }));
    } catch (error) {
      toast.error(error instanceof Error ? error.message : t('settings.backup.importError', { defaultValue: '书签导入失败，请检查文件格式' }));
    }
  }, [t]);

  return (
    <ShortcutAppProvider value={shortcutApp}>
      <div
        ref={pageFocusRef}
        tabIndex={-1}
        className="relative flex h-screen w-full flex-col items-center overflow-hidden bg-transparent focus:outline-none"
        style={{ backgroundColor: 'var(--initial-reveal-surface)' }}
      >
        <WallpaperBackdropProvider value={wallpaperBackdropValue}>
          <div className="relative h-full w-full" style={globalRevealUiStyle}>
            <ShortcutSelectionShell
              contextMenu={uiState.contextMenu}
              setContextMenu={uiState.setContextMenu}
              contextMenuRef={uiState.contextMenuRef}
              shortcuts={shortcuts}
              onCreateShortcut={(insertIndex) => openCreateShortcutEditor({
                setShortcutEditOpen: uiState.setShortcutEditOpen,
                setShortcutModalMode: uiState.setShortcutModalMode,
                setSelectedShortcut: uiState.setSelectedShortcut,
                setEditingTitle: uiState.setEditingTitle,
                setEditingUrl: uiState.setEditingUrl,
                setCurrentInsertIndex: uiState.setCurrentInsertIndex,
              }, insertIndex)}
              onEditShortcut={handleOpenShortcutEditor}
              onEditFolderShortcut={handleOpenFolderChildShortcutEditor}
              onDeleteShortcut={(index, shortcut) => handleDeleteShortcutRequest({ index, shortcut })}
              onDeleteFolderShortcut={handleDeleteFolderChildShortcut}
              onShortcutOpen={handleShortcutActivate}
              onDeleteSelectedShortcuts={shortcutActions.handleConfirmDeleteShortcuts}
              onCreateFolder={handleCreateFolderFromSelection}
              onPinSelectedShortcuts={handlePinSelectedShortcuts}
              onMoveSelectedShortcutsToFolder={handleMoveSelectedShortcutsToFolder}
              onDissolveFolder={handleDissolveFolder}
              onSetFolderDisplayMode={handleSetFolderDisplayMode}
            >
              <HomeInteractiveSurface
                initialRevealReady={effectiveInitialRevealReady}
                modeLayersVisible={modeLayersVisible}
                modeFlags={displayModeFlags}
                showOverlayWallpaperLayer={showOverlayWallpaperLayer}
                wallpaperAnimatedLayerStyle={wallpaperAnimatedLayerStyle}
                effectiveWallpaperMode={effectiveWallpaperMode}
                colorWallpaperGradient={colorWallpaperGradient}
                effectiveOverlayWallpaperSrc={effectiveOverlayWallpaperSrc}
                overlayBackgroundAlt="Rhythm Wallpaper"
                onOverlayImageReady={handleOverlayWallpaperReady}
                effectiveWallpaperMaskOpacity={effectiveWallpaperMaskOpacity}
                topNavModeProps={topNavModeProps}
                homeMainContentBaseProps={homeMainContentBaseProps}
                shortcutGridBaseProps={shortcutGridBaseProps}
                shortcutGridSelectionMode={false}
                shortcutGridHeatZoneInspectorEnabled={false}
                shortcutGridHiddenShortcutId={pendingExtractHiddenShortcutId}
                shortcutGridOpenFolderPreviewId={openFolderId}
                shortcutGridSelectedShortcutIndexes={new Set<number>()}
                onToggleShortcutSelection={() => {}}
                wallpaperClockBaseProps={wallpaperClockBaseProps}
                searchExperienceBaseProps={searchExperienceBaseProps}
                baseTimeAnimationEnabled={false}
                precomputedWallpaperBackdrop={homeSurfaceWallpaperBackdrop}
              />
            </ShortcutSelectionShell>
            {openFolderShortcut ? (
              <Suspense fallback={null}>
                <LazyShortcutFolderCompactOverlay
                  {...shortcutEngineHostAdapter.compactFolderOverlayProps}
                  transitionPhase={folderTransitionState.phase}
                  transitionProgress={folderTransitionState.progress}
                  openingSourceSnapshot={folderTransitionState.sourceSnapshot}
                  onOpeningLayoutReady={() => folderTransitionController.notifyOpeningReady(openFolderShortcut.id)}
                  onClosingLayoutReady={() => folderTransitionController.notifyClosingReady(openFolderShortcut.id)}
                  shortcut={openFolderShortcut}
                />
              </Suspense>
            ) : null}
            {folderNameDialogOpen ? (
              <Suspense fallback={null}>
                <LazyShortcutFolderNameDialog
                  open={folderNameDialogOpen}
                  onOpenChange={(open) => {
                    if (open) {
                      setFolderNameDialogOpen(true);
                      return;
                    }
                    closeFolderNameDialog();
                  }}
                  title={folderNameDialogTitle}
                  description={folderNameDialogDescription}
                  initialName={folderNameDialogInitialName}
                  onSubmit={handleSaveFolderName}
                />
              </Suspense>
            ) : null}
            <Suspense fallback={null}>
              {settingsOpen ? (
                <LazySettingsModal
                  isOpen={settingsOpen}
                  onOpenChange={setSettingsOpen}
                  shortcutsCount={shortcuts.length}
                  displayMode={displayMode}
                  onDisplayModeChange={setDisplayMode}
                  shortcutCompactShowTitle={shortcutCompactShowTitle}
                  onShortcutCompactShowTitleChange={setShortcutCompactShowTitle}
                  shortcutGridColumns={normalizedGridColumns}
                  onShortcutGridColumnsChange={setShortcutGridColumns}
                  openInNewTab={openInNewTab}
                  onOpenInNewTabChange={setOpenInNewTab}
                  preventDuplicateNewTab={preventDuplicateNewTab}
                  onPreventDuplicateNewTabChange={setPreventDuplicateNewTab}
                  showTime={showTime}
                  onShowTimeChange={setShowTime}
                  onExportData={handleExportBrowserBookmarks}
                  onOpenImportSourceDialog={handleOpenBookmarkImport}
                  onOpenSyncCenter={handleOpenWebdavSyncCenter}
                  onOpenWebdavConfig={handleOpenWebdavConfig}
                  wallpaperMode={effectiveWallpaperMode}
                  onWallpaperModeChange={setWallpaperMode}
                  bingWallpaper={bingWallpaper}
                  customWallpaper={customWallpaper}
                  onCustomWallpaperChange={setCustomWallpaper}
                  colorWallpaperId={colorWallpaperId}
                  onColorWallpaperIdChange={setColorWallpaperId}
                  wallpaperMaskOpacity={wallpaperMaskOpacity}
                  onWallpaperMaskOpacityChange={setWallpaperMaskOpacity}
                  onOpenWallpaperSettings={handleOpenWallpaperSettings}
                  onOpenShortcutIconSettings={handleOpenShortcutIconSettings}
                />
              ) : null}
            </Suspense>
            <input
              ref={bookmarkImportInputRef}
              type="file"
              accept=".html,.htm,text/html"
              className="hidden"
              onChange={handleBookmarkImportFileChange}
            />
            <Suspense fallback={null}>
              {wallpaperSettingsOpen ? (
                <LazyWallpaperSelector
                  mode={effectiveWallpaperMode}
                  onModeChange={setWallpaperMode}
                  bingWallpaper={bingWallpaper}
                  isBingWallpaperRefreshing={isBingWallpaperRefreshing}
                  onRefreshBingWallpaper={refreshBingWallpaper}
                  customWallpaper={customWallpaper}
                  customWallpaperGallery={customWallpaperGallery}
                  onAppendCustomWallpapers={appendCustomWallpapers}
                  onCustomWallpaperChange={setCustomWallpaper}
                  colorWallpaperId={colorWallpaperId}
                  onColorWallpaperIdChange={setColorWallpaperId}
                  wallpaperMaskOpacity={wallpaperMaskOpacity}
                  effectiveWallpaperMaskOpacity={effectiveWallpaperMaskOpacity}
                  onWallpaperMaskOpacityChange={setWallpaperMaskOpacity}
                  darkModeAutoDimWallpaperEnabled={darkModeAutoDimWallpaperEnabled}
                  onDarkModeAutoDimWallpaperEnabledChange={setDarkModeAutoDimWallpaperEnabled}
                  wallpaperRotationSettings={wallpaperRotationSettings}
                  onWallpaperRotationIntervalChange={handleWallpaperRotationIntervalChange}
                  open={wallpaperSettingsOpen}
                  onOpenChange={handleWallpaperSettingsOpenChange}
                  onBackToSettings={handleBackToMainSettings}
                  trigger={<span className="hidden" aria-hidden="true" />}
                />
              ) : null}
              {shortcutIconSettingsOpen ? (
                <LazyShortcutIconSettingsDialog
                  open={shortcutIconSettingsOpen}
                  onOpenChange={handleShortcutIconSettingsOpenChange}
                  onBackToSettings={handleBackToMainSettings}
                  compactShowTitle={shortcutCompactShowTitle}
                  columns={normalizedGridColumns}
                  onSaveStyle={handleSaveShortcutIconStyle}
                  appearance={shortcutIconAppearance}
                  cornerRadius={shortcutIconCornerRadius}
                  scale={shortcutIconScale}
                  onSave={handleSaveShortcutIconAppearance}
                />
              ) : null}
            </Suspense>
            <Suspense fallback={null}>
              {uiState.shortcutEditOpen ? (
                <LazyShortcutModal
                  isOpen={uiState.shortcutEditOpen}
                  onOpenChange={handleShortcutModalOpenChange}
                  mode={uiState.shortcutModalMode}
                  initialShortcut={uiState.selectedShortcut?.shortcut ?? null}
                  iconCornerRadius={shortcutIconCornerRadius}
                  iconScale={shortcutIconScale}
                  iconAppearance={shortcutIconAppearance}
                  onSave={(draft: ShortcutDraft, localOnly) => {
                    shortcutActions.handleSaveShortcutEdit(draft, localOnly);
                    markShortcutStateDirty();
                  }}
                />
              ) : null}
              {shortcutDeleteOpen ? (
                <LazyConfirmDialog
                  open={shortcutDeleteOpen}
                  onOpenChange={(open) => {
                    setShortcutDeleteOpen(open);
                    if (!open) setShortcutToDelete(null);
                  }}
                  title={t('deleteConfirm.title', { defaultValue: '删除快捷方式' })}
                  description={t('deleteConfirm.description', { defaultValue: '确定要删除这个快捷方式吗？' })}
                  onConfirm={handleConfirmDeleteShortcut}
                />
              ) : null}
              {webdavSyncHostMounted ? (
                <LazyBookmarkWebdavSyncHost
                  leafTabSyncDialogOpen={leafTabSyncDialogOpen}
                  webdavDialogOpen={webdavDialogOpen}
                  webdavEnableAfterConfigSave={webdavEnableAfterConfigSave}
                  webdavShowConnectionFields={webdavShowConnectionFields}
                  syncConfigBackTarget={syncConfigBackTarget}
                  setLeafTabSyncDialogOpen={setLeafTabSyncDialogOpen}
                  setWebdavDialogOpen={setWebdavDialogOpen}
                  setWebdavEnableAfterConfigSave={setWebdavEnableAfterConfigSave}
                  setWebdavShowConnectionFields={setWebdavShowConnectionFields}
                  setSyncConfigBackTarget={setSyncConfigBackTarget}
                  setSettingsOpen={setSettingsOpen}
                  setConfirmDisableWebdavSyncOpen={setConfirmDisableWebdavSyncOpen}
                  onWebdavConfigDialogPropsChange={setWebdavConfigDialogProps}
                  onDisableWebdavSyncChange={(handler) => {
                    disableWebdavSyncRef.current = handler;
                  }}
                />
              ) : null}
              {webdavDialogOpen && webdavConfigDialogProps ? (
                <LazyWebdavConfigDialog {...webdavConfigDialogProps} />
              ) : null}
              {confirmDisableWebdavSyncOpen ? (
                <LazyConfirmDialog
                  open={confirmDisableWebdavSyncOpen}
                  onOpenChange={setConfirmDisableWebdavSyncOpen}
                  title={t('settings.backup.webdav.disableConfirmTitle', { defaultValue: '关闭 WebDAV 同步' })}
                  description={t('settings.backup.webdav.disableConfirmDesc', {
                    defaultValue: '关闭后将不再自动同步。当前设备上的数据会保留。',
                  })}
                  confirmText={t('settings.backup.webdav.disableConfirmAction', { defaultValue: '关闭同步' })}
                  confirmButtonClassName="flex-1 bg-red-500 text-white hover:bg-red-500/90"
                  onConfirm={() => {
                    setConfirmDisableWebdavSyncOpen(false);
                    disableWebdavSyncRef.current?.();
                  }}
                />
              ) : null}
            </Suspense>
            <FolderTransitionDocumentEffects controller={folderTransitionController} />
          </div>
        </WallpaperBackdropProvider>
      </div>
      <Toaster offset={16} />
    </ShortcutAppProvider>
  );
}
