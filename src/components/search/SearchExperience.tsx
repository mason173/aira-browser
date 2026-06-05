import { memo, useCallback, useEffect, useMemo, useRef, useState, type CSSProperties, type KeyboardEvent, type RefObject } from 'react';
import { useTranslation } from 'react-i18next';
import { useTheme } from 'next-themes';
import type { RemoteSearchSuggestionItem } from '@/types';
import { useSearch } from '@/hooks/useSearch';
import { getCachedRemoteSearchSuggestions, getRemoteSearchSuggestionsFromExtension } from '@/utils/remoteSearchSuggestions';
import { normalizeSearchQuery } from '@/utils/searchHelpers';
import { SearchField, type SearchFieldValueChangeHandler } from '@/components/search/SearchField';
import { shouldBlockSearchSubmitForIme } from '@/components/search/searchInputKeyboard';
import { resolveSearchBarTheme } from '@/components/search/searchBarTheme';
import { FrostedSurface } from '@/components/frosted/FrostedSurface';
import {
  focusSearchInputElement,
  type SearchActivationFocusOptions,
  type SearchActivationHandle,
} from '@/components/search/searchActivation.shared';
import type { Shortcut } from '@/types';
import type { WallpaperMode } from '@/wallpaper/types';
import type { ShortcutIconAppearance } from '@/types';

export type SlashCommandDialogTarget =
  | 'settings-home'
  | 'search-settings'
  | 'shortcut-guide'
  | 'shortcut-icon-settings'
  | 'wallpaper-settings'
  | 'about';

export type SearchInteractionState = {
  historyOpen: boolean;
  dropdownOpen: boolean;
  typingBurst: boolean;
};

export interface SearchExperienceProps {
  inputRef: RefObject<HTMLInputElement | null>;
  openInNewTab: boolean;
  shortcuts: Shortcut[];
  tabSwitchSearchEngine: boolean;
  searchPrefixEnabled: boolean;
  searchSiteDirectEnabled: boolean;
  searchSiteShortcutEnabled: boolean;
  searchAnyKeyCaptureEnabled: boolean;
  searchCalculatorEnabled: boolean;
  searchRotatingPlaceholderEnabled: boolean;
  disablePlaceholderAnimation?: boolean;
  lightweightSearchUi?: boolean;
  searchHeight: number;
  searchInputFontSize: number;
  searchHorizontalPadding: number;
  searchActionSize: number;
  blankMode?: boolean;
  forceWhiteTheme?: boolean;
  subtleDarkTone?: boolean;
  searchSurfaceStyle?: CSSProperties;
  searchSurfaceTone?: 'default' | 'drawer';
  suggestionsPlacement?: 'bottom' | 'top';
  currentWallpaperMode?: WallpaperMode;
  currentColorWallpaperId?: string;
  darkModeAutoDimWallpaperEnabled?: boolean;
  currentShortcutIconAppearance?: ShortcutIconAppearance;
  currentShortcutIconCornerRadius?: number;
  currentShortcutIconScale?: number;
  shortcutShowTitleEnabled?: boolean;
  currentShortcutGridColumns?: number;
  preventDuplicateNewTab?: boolean;
  showTime?: boolean;
  activeSyncProvider?: 'webdav' | 'none';
  interactionDisabled?: boolean;
  onEditShortcutAction?: (target: { shortcut: Shortcut; index: number; parentFolderId?: string | null }) => void;
  onDeleteShortcutAction?: (target: { shortcut: Shortcut; index: number; parentFolderId?: string | null }) => void;
  onAddShortcutAction?: (target: { title: string; url: string; icon?: string }) => void;
  onSetShowTimeAction?: (nextValue: boolean) => void;
  onSetWallpaperModeAction?: (nextValue: WallpaperMode) => void;
  onSetShortcutIconAppearanceAction?: (nextValue: ShortcutIconAppearance) => void;
  onSetSearchTabSwitchEngineAction?: (nextValue: boolean) => void;
  onSetSearchPrefixEnabledAction?: (nextValue: boolean) => void;
  onSetSearchSiteDirectEnabledAction?: (nextValue: boolean) => void;
  onSetSearchSiteShortcutEnabledAction?: (nextValue: boolean) => void;
  onSetSearchAnyKeyCaptureEnabledAction?: (nextValue: boolean) => void;
  onSetSearchCalculatorEnabledAction?: (nextValue: boolean) => void;
  onSetSearchRotatingPlaceholderEnabledAction?: (nextValue: boolean) => void;
  onSetShortcutShowTitleAction?: (nextValue: boolean) => void;
  onSetPreventDuplicateNewTabAction?: (nextValue: boolean) => void;
  onSetDarkModeAutoDimWallpaperAction?: (nextValue: boolean) => void;
  onInteractionStateChange?: (state: SearchInteractionState) => void;
  onOpenSlashCommandDialog?: (target: SlashCommandDialogTarget) => void;
  onActivationHandleChange?: (handle: SearchActivationHandle | null) => void;
}

const REMOTE_SUGGESTION_DEBOUNCE_MS = 120;
const MAX_NUMBER_HOTKEY_SLOTS = 10;

function resolveNumberHotkeyIndex(key: string): number | null {
  if (key >= '1' && key <= '9') {
    return Number(key) - 1;
  }
  if (key === '0') return 9;
  return null;
}

function useRemoteSuggestions(searchValue: string, enabled: boolean) {
  const normalizedQuery = useMemo(() => normalizeSearchQuery(searchValue), [searchValue]);
  const [items, setItems] = useState<RemoteSearchSuggestionItem[]>([]);

  useEffect(() => {
    if (!enabled || !normalizedQuery) {
      setItems([]);
      return;
    }

    const cachedItems = getCachedRemoteSearchSuggestions('360', searchValue);
    if (cachedItems) {
      setItems(cachedItems.filter((item): item is RemoteSearchSuggestionItem => item.type === 'remote').slice(0, 10));
      return;
    }

    let canceled = false;
    const timerId = window.setTimeout(() => {
      void getRemoteSearchSuggestionsFromExtension({
        provider: '360',
        query: searchValue,
        limit: 10,
      }).then((nextItems) => {
        if (!canceled) {
          setItems(nextItems.filter((item): item is RemoteSearchSuggestionItem => item.type === 'remote'));
        }
      }).catch(() => {
        if (!canceled) {
          setItems([]);
        }
      });
    }, REMOTE_SUGGESTION_DEBOUNCE_MS);

    return () => {
      canceled = true;
      window.clearTimeout(timerId);
    };
  }, [enabled, normalizedQuery, searchValue]);

  return items;
}

function openSearchValue(args: {
  value: string;
  openSearchWithQuery: (query: string) => void;
}) {
  const query = args.value.trim();
  if (!query) return;
  args.openSearchWithQuery(query);
}

export const SearchExperience = memo(function LiteSearchExperience({
  inputRef,
  openInNewTab,
  tabSwitchSearchEngine,
  searchPrefixEnabled,
  searchSiteDirectEnabled,
  searchSiteShortcutEnabled,
  searchAnyKeyCaptureEnabled,
  searchCalculatorEnabled,
  searchRotatingPlaceholderEnabled,
  disablePlaceholderAnimation = false,
  lightweightSearchUi = true,
  searchHeight,
  searchInputFontSize,
  searchHorizontalPadding,
  searchActionSize,
  blankMode = false,
  forceWhiteTheme = false,
  subtleDarkTone = false,
  searchSurfaceStyle,
  searchSurfaceTone = 'default',
  suggestionsPlacement = 'bottom',
  interactionDisabled = false,
  onInteractionStateChange,
  onOpenSlashCommandDialog,
  onActivationHandleChange,
}: SearchExperienceProps) {
  void tabSwitchSearchEngine;
  void searchPrefixEnabled;
  void searchSiteDirectEnabled;
  void searchSiteShortcutEnabled;
  void searchAnyKeyCaptureEnabled;
  void searchCalculatorEnabled;
  void searchRotatingPlaceholderEnabled;
  void onOpenSlashCommandDialog;
  const { t } = useTranslation();
  const { resolvedTheme } = useTheme();
  const {
    searchValue,
    searchEngine,
    dropdownOpen,
    setDropdownOpen,
    setSearchValue,
    handleSearchChange,
    handleEngineSelect,
    cycleSearchEngine,
    openSearchWithQuery,
  } = useSearch(openInNewTab, {
    prefixEnabled: false,
    siteDirectEnabled: false,
    personalizationEnabled: false,
    fuzzyMatchEnabled: false,
  });
  const [panelOpen, setPanelOpen] = useState(false);
  const [highlightedIndex, setHighlightedIndex] = useState(-1);
  const [suggestionModifierHeld, setSuggestionModifierHeld] = useState(false);
  const focusedPrintableCapturePendingRef = useRef(false);
  const remoteItems = useRemoteSuggestions(searchValue, panelOpen && !interactionDisabled);
  const theme = resolveSearchBarTheme({
    blankMode,
    forceWhiteTheme,
    subtleDarkTone,
    resolvedTheme,
  });
  const showPanel = panelOpen && remoteItems.length > 0 && !interactionDisabled;

  useEffect(() => {
    onInteractionStateChange?.({
      historyOpen: showPanel,
      dropdownOpen,
      typingBurst: false,
    });
  }, [dropdownOpen, onInteractionStateChange, showPanel]);

  useEffect(() => {
    if (highlightedIndex >= remoteItems.length) {
      setHighlightedIndex(remoteItems.length > 0 ? 0 : -1);
    }
  }, [highlightedIndex, remoteItems.length]);

  useEffect(() => {
    if (!showPanel) {
      setSuggestionModifierHeld(false);
      return undefined;
    }

    const syncModifierState = (event?: globalThis.KeyboardEvent) => {
      setSuggestionModifierHeld(Boolean(event?.metaKey || event?.ctrlKey));
    };
    const handleKeyDown = (event: globalThis.KeyboardEvent) => syncModifierState(event);
    const handleKeyUp = (event: globalThis.KeyboardEvent) => syncModifierState(event);
    const handleWindowBlur = () => setSuggestionModifierHeld(false);

    window.addEventListener('keydown', handleKeyDown, true);
    window.addEventListener('keyup', handleKeyUp, true);
    window.addEventListener('blur', handleWindowBlur);
    return () => {
      window.removeEventListener('keydown', handleKeyDown, true);
      window.removeEventListener('keyup', handleKeyUp, true);
      window.removeEventListener('blur', handleWindowBlur);
    };
  }, [showPanel]);

  const closePanel = useCallback(() => {
    setPanelOpen(false);
    setHighlightedIndex(-1);
  }, []);

  const focusSearchInput = useCallback((options?: SearchActivationFocusOptions) => {
    if (interactionDisabled) return;
    const input = inputRef.current;
    if (!input) return;
    focusSearchInputElement(input, options);
    if (options?.openHistory && searchValue.trim()) {
      setPanelOpen(true);
      if (options.openHistory === 'first') {
        setHighlightedIndex(remoteItems.length > 0 ? 0 : -1);
      } else if (options.openHistory === 'none') {
        setHighlightedIndex(-1);
      }
    }
  }, [inputRef, interactionDisabled, remoteItems.length, searchValue]);

  const appendSearchInputText = useCallback((text: string) => {
    if (interactionDisabled || text.length === 0) return;
    const nextValue = `${inputRef.current?.value || searchValue}${text}`;
    focusedPrintableCapturePendingRef.current = false;
    setSearchValue(nextValue);
    setPanelOpen(Boolean(nextValue.trim()));
    focusSearchInput();
  }, [focusSearchInput, inputRef, interactionDisabled, searchValue, setSearchValue]);

  useEffect(() => {
    const handleNativeInput = (event: Event) => {
      if (event.target !== inputRef.current) return;
      focusedPrintableCapturePendingRef.current = false;
    };
    const handleFocusOut = (event: FocusEvent) => {
      if (event.target !== inputRef.current) return;
      focusedPrintableCapturePendingRef.current = false;
    };

    document.addEventListener('input', handleNativeInput, true);
    document.addEventListener('focusout', handleFocusOut, true);
    return () => {
      document.removeEventListener('input', handleNativeInput, true);
      document.removeEventListener('focusout', handleFocusOut, true);
    };
  }, [inputRef]);

  const activationHandle = useMemo<SearchActivationHandle | null>(() => {
    if (interactionDisabled) return null;
    return {
      id: 'home-search',
      inputRef,
      anyKeyCaptureEnabled: searchAnyKeyCaptureEnabled,
      focusInput: focusSearchInput,
      appendText: appendSearchInputText,
      armFocusedPrintableCapture: () => {
        focusedPrintableCapturePendingRef.current = true;
      },
      consumeFocusedPrintableCapture: () => {
        if (!focusedPrintableCapturePendingRef.current) return false;
        focusedPrintableCapturePendingRef.current = false;
        return true;
      },
    };
  }, [
    appendSearchInputText,
    focusSearchInput,
    inputRef,
    interactionDisabled,
    searchAnyKeyCaptureEnabled,
  ]);

  useEffect(() => {
    onActivationHandleChange?.(activationHandle);
    return () => onActivationHandleChange?.(null);
  }, [activationHandle, onActivationHandleChange]);

  const submitValue = useCallback((value: string) => {
    openSearchValue({
      value,
      openSearchWithQuery,
    });
    closePanel();
  }, [closePanel, openSearchWithQuery]);

  const handleValueChange = useCallback<SearchFieldValueChangeHandler>((nextValue, nativeEvent) => {
    handleSearchChange(nextValue, nativeEvent);
    setPanelOpen(Boolean(nextValue.trim()));
    setHighlightedIndex(-1);
  }, [handleSearchChange]);

  const handleSubmit = useCallback(() => {
    const selectedItem = highlightedIndex >= 0 ? remoteItems[highlightedIndex] : null;
    submitValue(selectedItem?.value || searchValue);
  }, [highlightedIndex, remoteItems, searchValue, submitValue]);

  const handleKeyDown = useCallback((event: KeyboardEvent<HTMLDivElement>) => {
    if (shouldBlockSearchSubmitForIme(event)) return;
    const hasNumberHotkeyModifier = (event.metaKey || event.ctrlKey) && !event.altKey;
    if (showPanel && hasNumberHotkeyModifier) {
      const hotkeyIndex = resolveNumberHotkeyIndex(event.key);
      if (hotkeyIndex !== null && hotkeyIndex < MAX_NUMBER_HOTKEY_SLOTS) {
        const selectedItem = remoteItems[hotkeyIndex];
        if (selectedItem) {
          event.preventDefault();
          event.stopPropagation();
          submitValue(selectedItem.value);
        }
        return;
      }
    }
    if (event.key === 'Enter') {
      event.preventDefault();
      handleSubmit();
      return;
    }
    if (event.key === 'Escape') {
      closePanel();
      return;
    }
    if (event.key === 'Tab' && tabSwitchSearchEngine) {
      event.preventDefault();
      cycleSearchEngine(event.shiftKey ? -1 : 1);
      if (dropdownOpen) setDropdownOpen(false);
      return;
    }
    if (event.key === 'ArrowDown' && remoteItems.length > 0) {
      event.preventDefault();
      setPanelOpen(true);
      setHighlightedIndex((current) => (current + 1 + remoteItems.length) % remoteItems.length);
      return;
    }
    if (event.key === 'ArrowUp' && remoteItems.length > 0) {
      event.preventDefault();
      setPanelOpen(true);
      setHighlightedIndex((current) => (current <= 0 ? remoteItems.length - 1 : current - 1));
    }
  }, [
    closePanel,
    cycleSearchEngine,
    dropdownOpen,
    handleSubmit,
    remoteItems,
    setDropdownOpen,
    showPanel,
    submitValue,
    tabSwitchSearchEngine,
  ]);

  return (
    <div className="relative w-full" data-search-ui="true" onKeyDown={handleKeyDown}>
      <SearchField
        value={searchValue}
        onValueChange={handleValueChange}
        inputRef={inputRef}
        onFocusContainer={() => inputRef.current?.focus()}
        onInputFocus={() => {
          if (searchValue.trim()) setPanelOpen(true);
        }}
        onOpenHistory={() => {
          if (searchValue.trim()) setPanelOpen(true);
        }}
        onClear={() => {
          setSearchValue('');
          closePanel();
        }}
        placeholder={t('search.placeholder')}
        disablePlaceholderAnimation={disablePlaceholderAnimation}
        lightweightPlaceholderAnimation={lightweightSearchUi}
        theme={theme}
        height={searchHeight}
        inputFontSize={searchInputFontSize}
        horizontalPadding={searchHorizontalPadding}
        searchActionSize={searchActionSize}
        surfaceStyle={searchSurfaceStyle}
        surfaceTone={searchSurfaceTone}
        searchEngine={searchEngine}
        onEngineSelect={handleEngineSelect}
        dropdownOpen={dropdownOpen}
        onEngineOpenChange={setDropdownOpen}
        showEngineSwitcher
        panelExpanded={showPanel}
        interactionDisabled={interactionDisabled}
      />
      {showPanel ? (
        <FrostedSurface
          preset="search-panel"
          radiusClassName="rounded-[24px]"
          surfaceClassName={theme.dropdownSurfaceClassName}
          contentClassName="relative z-[1] flex flex-col gap-0.5"
          className={`absolute left-0 right-0 z-[16000] rounded-[24px] p-2 ${
            suggestionsPlacement === 'top' ? 'bottom-[calc(100%+10px)]' : 'top-[calc(100%+10px)]'
          }`}
          surfaceTone={searchSurfaceTone}
          showBorder={false}
        >
          {remoteItems.map((item, index) => (
            <button
              key={`${item.provider}:${item.value}`}
              type="button"
              className={`flex w-full items-center rounded-[18px] px-4 py-2.5 text-left text-sm transition-colors ${
                highlightedIndex === index ? 'bg-primary/14 text-foreground' : 'text-foreground hover:bg-muted/70'
              }`}
              onMouseEnter={() => setHighlightedIndex(index)}
              onMouseDown={(event) => event.preventDefault()}
              onClick={() => submitValue(item.value)}
            >
              <span
                aria-hidden={!suggestionModifierHeld}
                className={`inline-flex shrink-0 overflow-hidden transition-[max-width,margin] duration-300 ease-out ${
                  suggestionModifierHeld ? 'max-w-8 mr-2' : 'max-w-0 mr-0'
                }`}
              >
                <span
                  className={`inline-flex h-5 min-w-5 items-center justify-center rounded-full bg-current/12 px-1.5 text-[11px] font-medium text-current transition-[opacity,transform] duration-300 ease-out origin-left ${
                    suggestionModifierHeld ? 'opacity-100 scale-100' : 'opacity-0 scale-0'
                  }`}
                >
                  {String(index + 1)}
                </span>
              </span>
              <span className="min-w-0 truncate">{item.label}</span>
            </button>
          ))}
        </FrostedSurface>
      ) : null}
    </div>
  );
});
