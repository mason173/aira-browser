import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  ReaderModeAction,
  ReaderModePreferences,
  ReaderModeViewState
} from '../../../features/reader/ReaderModeModels';
import {
  NovelReaderAction,
  NovelReaderPreferences,
  NovelReaderSnapshot
} from '../../../features/novel/NovelReaderModels';
import {
  ReadingPresentationMode,
  ReadingSurfaceAppearance
} from '../../../features/reading/ReadingSurfaceModels';
import { BrowserSystemSheetType } from '../../../core/browser/BrowserShellRuntimeContracts';
import {
  resolveNovelReaderSystemSurfaceTitle
} from '../../../core/browser/BrowserSystemSurfacePresentationViewModel';
import {
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { APP_STANDARD_HORIZONTAL_PADDING } from '../common/AppLayoutTokens';
import { NovelReaderCatalogSheet } from '../browser/NovelReaderCatalogSheet';
import {
  SettingsGroupCard,
  SettingsGroupDivider
} from '../settings/SettingsLayout';
import { SettingsSwitchRow } from '../settings/SettingsRows';
import {
  ReadingSurfaceSettingsPanel,
  ReadingSurfaceSettingsPanelKind
} from './ReadingSurfaceSettingsPanel';

export function isReadingExperienceSystemSheetType(type: BrowserSystemSheetType): boolean {
  return type === 'readerText' || type === 'readerAppearance' || type === 'readerSettings' ||
    type === 'novelCatalog' || type === 'novelReaderText' ||
    type === 'novelReaderAppearance' || type === 'novelReaderSettings';
}

export function resolveReadingExperienceSystemSheetHeight(type: BrowserSystemSheetType): SheetSize {
  if (type === 'readerText' || type === 'readerAppearance' || type === 'readerSettings' ||
    type === 'novelReaderText' || type === 'novelReaderAppearance' || type === 'novelReaderSettings') {
    return SheetSize.FIT_CONTENT;
  }
  return SheetSize.LARGE;
}

export function resolveReadingExperienceSystemSheetTitle(
  type: BrowserSystemSheetType
): SheetTitleOptions | undefined {
  if (type === 'crossDeviceTabs') {
    return { title: '电脑标签页' };
  }
  const novelReaderTitle: string = resolveNovelReaderSystemSurfaceTitle(type);
  if (novelReaderTitle.length > 0) {
    return { title: novelReaderTitle };
  }
  if (type === 'readerAppearance') {
    return { title: '亮度与主题' };
  }
  if (type === 'readerSettings') {
    return { title: '阅读设置' };
  }
  if (type === 'readerText') {
    return { title: '文字' };
  }
  return undefined;
}

@Component
export struct ReadingExperienceSystemSheet {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceColor: string = '#FFFFFF';
  @Prop type: BrowserSystemSheetType = 'readerText';
  @Prop readerState: ReaderModeViewState;
  @Prop readerPresentationMode: ReadingPresentationMode = 'vertical';
  @Prop novelState: NovelReaderSnapshot;
  @Prop bottomSafeInsetVp: number = 0;
  onReaderAction: (action: ReaderModeAction) => void = (_action: ReaderModeAction): void => {};
  onNovelAction: (action: NovelReaderAction) => void = (_action: NovelReaderAction): void => {};

  build() {
    if (this.type === 'novelCatalog') {
      Column() {
        Stack() {
          NovelReaderCatalogSheet({
            bookTitle: this.novelState.bookTitle,
            bookAuthor: this.novelState.bookAuthor,
            sourceHost: this.novelState.sourceHost,
            currentChapterUrl: this.novelState.pageUrl,
            catalog: this.novelState.catalog,
            catalogLoadingMore: this.novelState.catalogLoadingMore,
            catalogLoadingRangeStart: this.novelState.catalogLoadingRangeStart,
            catalogLoadingRangeEnd: this.novelState.catalogLoadingRangeEnd,
            catalogHasMore: this.novelState.catalogHasMore,
            catalogTotalHint: this.novelState.catalogTotalHint,
            catalogRangeExtentHint: this.novelState.catalogRangeExtentHint,
            catalogSupportsRandomAccess: this.novelState.catalogSupportsRandomAccess,
            onSelectChapter: (chapterId: string): void => {
              this.onNovelAction({ type: 'select_chapter', chapterId: chapterId });
            },
            onLoadRange: (startOrdinal: number, endOrdinal: number): void => {
              this.onNovelAction({
                type: 'load_catalog_range',
                startOrdinal: startOrdinal,
                endOrdinal: endOrdinal
              });
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: this.resolveBottomSafePadding() })
      .backgroundColor(this.storedPageBackgroundColor)
    } else {
      Column() {
        ReadingSurfaceSettingsPanel({
          panel: this.resolvePanel(),
          appearance: this.resolveAppearance(),
          mode: this.resolvePresentationMode(),
          useAppThemeColors: true,
          showPageModeOptions: !this.isNovelComicMode(),
          horizontalPadding: APP_STANDARD_HORIZONTAL_PADDING,
          onAppearanceChange: (appearance: ReadingSurfaceAppearance): void => {
            this.applyAppearance(appearance);
          },
          onModeChange: (mode: ReadingPresentationMode): void => {
            this.applyPresentationMode(mode);
          },
          settingsExtension: (): void => {
            if (this.isNovelControlSheet()) {
              this.buildNovelSettingsExtension()
            }
          }
        })
      }
      .width('100%')
      .padding({ bottom: this.resolveBottomSafePadding() })
      .backgroundColor(this.storedPageBackgroundColor)
    }
  }

  @Builder
  private buildNovelSettingsExtension() {
    SettingsGroupCard({ surfaceColor: this.storedSurfaceColor }) {
      if (this.isNovelComicMode()) {
        SettingsSwitchRow({
          title: '显示系统状态栏',
          checked: this.novelState.preferences.systemStatusBarVisible,
          rowPosition: 'first',
          onChange: (enabled: boolean): void => {
            this.onNovelAction({ type: 'status_bar_visibility_change', visible: enabled });
          }
        })
      } else {
        SettingsSwitchRow({
          title: '自动阅读',
          checked: this.novelState.preferences.autoReadingEnabled,
          rowPosition: 'first',
          onChange: (enabled: boolean): void => {
            this.onNovelAction({ type: 'auto_reading_change', enabled: enabled });
          }
        })
        SettingsGroupDivider({})
        SettingsSwitchRow({
          title: '显示系统状态栏',
          checked: this.novelState.preferences.systemStatusBarVisible,
          rowPosition: 'middle',
          onChange: (enabled: boolean): void => {
            this.onNovelAction({ type: 'status_bar_visibility_change', visible: enabled });
          }
        })
        SettingsGroupDivider({})
        SettingsSwitchRow({
          title: '显示章节名称',
          checked: this.novelState.preferences.chapterNameVisible,
          rowPosition: 'middle',
          onChange: (enabled: boolean): void => {
            this.onNovelAction({ type: 'chapter_name_visibility_change', visible: enabled });
          }
        })
        SettingsGroupDivider({})
        SettingsSwitchRow({
          title: '显示页码',
          checked: this.novelState.preferences.pageNumberVisible,
          rowPosition: 'last',
          onChange: (enabled: boolean): void => {
            this.onNovelAction({ type: 'page_number_visibility_change', visible: enabled });
          }
        })
      }
    }
  }

  private resolvePanel(): ReadingSurfaceSettingsPanelKind {
    if (this.type === 'readerAppearance' || this.type === 'novelReaderAppearance') {
      return 'appearance';
    }
    if (this.type === 'readerSettings' || this.type === 'novelReaderSettings') {
      return 'settings';
    }
    return 'text';
  }

  private isNovelControlSheet(): boolean {
    return this.type === 'novelReaderText' || this.type === 'novelReaderAppearance' ||
      this.type === 'novelReaderSettings';
  }

  private isNovelComicMode(): boolean {
    return this.isNovelControlSheet() && this.novelState.contentKind === 'comic';
  }

  private resolveAppearance(): ReadingSurfaceAppearance {
    if (this.isNovelControlSheet()) {
      const preferences: NovelReaderPreferences = this.novelState.preferences;
      return {
        fontSize: preferences.fontSize,
        theme: preferences.theme,
        lineHeight: preferences.lineHeight,
        pageWidth: preferences.pageWidth,
        brightnessMode: preferences.brightnessMode,
        brightnessPercent: preferences.brightnessPercent
      };
    }
    const preferences: ReaderModePreferences = this.readerState.preferences;
    return {
      fontSize: preferences.fontSize,
      theme: preferences.theme,
      lineHeight: preferences.lineHeight,
      pageWidth: preferences.pageWidth,
      brightnessMode: preferences.brightnessMode,
      brightnessPercent: preferences.brightnessPercent
    };
  }

  private resolvePresentationMode(): ReadingPresentationMode {
    return this.isNovelControlSheet() ? this.novelState.preferences.pageMode : this.readerPresentationMode;
  }

  private applyAppearance(appearance: ReadingSurfaceAppearance): void {
    if (this.isNovelControlSheet()) {
      this.onNovelAction({ type: 'reading_appearance_change', appearance: appearance });
      return;
    }
    this.onReaderAction({ type: 'reading_appearance_change', appearance: appearance });
  }

  private applyPresentationMode(mode: ReadingPresentationMode): void {
    if (this.isNovelControlSheet()) {
      this.onNovelAction({ type: 'reading_page_mode_change', mode: mode });
      return;
    }
    this.onReaderAction({ type: 'reading_presentation_mode_change', mode: mode });
  }

  private resolveBottomSafePadding(): number {
    return Math.max(20, Math.ceil(this.bottomSafeInsetVp) + 12);
  }
}
