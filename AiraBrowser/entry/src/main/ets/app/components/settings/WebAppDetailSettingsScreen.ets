import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { WebAppSettingsDetailState } from '../../../core/webapps/WebAppSettingsViewModel';
import {
  SiteCustomizationDetailViewState
} from '../../../core/sitecustomization/SiteCustomizationManagementViewModel';
import { SiteJavaScriptPolicy } from '../../../core/sitecustomization/SiteCustomizationManagementCoordinator';
import { isPrivateBoundaryRoute } from '../../../common/utils/RouteParamUtils';
import { SiteIconView } from '../common/SiteIconView';
import { SiteCustomizationDetailSections } from '../sitecustomization/SiteCustomizationDetailScreen';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_OUTLINE_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { SettingsHdsScaffold } from './SettingsHdsScaffold';
import {
  SettingsFooterText,
  SettingsGroupCard,
  SettingsPresentationScrollBody,
  SettingsSection
} from './SettingsLayout';
import { SettingsSwitchRow } from './SettingsRows';

export type WebAppDetailSettingsPresentationMode = 'standalone' | 'embedded';

@Component
export struct WebAppDetailSettingsScreen {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_OUTLINE_KEY) private storedOutlineColor: string = '#26000000';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: WebAppSettingsDetailState = {
    shortcutId: '',
    title: '网页应用',
    subtitle: '',
    iconPath: '',
    defaultFullscreen: false,
    siteHost: '',
    siteOrigin: '',
    canOpenSiteSettings: false,
    exists: false
  };
  @Prop siteState: SiteCustomizationDetailViewState = {
    host: '',
    origin: '',
    title: '',
    summary: '',
    externalNavigationPolicy: 'ask',
    hasExternalNavigationRule: false,
    desktopSiteSummary: '跟随全局',
    hasDesktopSiteRule: false,
    privateSiteEnabled: false,
    preserveCookiesOnClose: false,
    hasPrivateSiteRule: false,
    javaScriptPolicy: 'default',
    hasJavaScriptRule: false,
    javaScriptCanApply: true,
    permissionGroups: [],
    hasAnyRules: false,
    resetEnabled: false,
    hasUnreadableEntry: false
  };
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop presentationMode: WebAppDetailSettingsPresentationMode = 'standalone';
  @Prop desktopPresentation: boolean = false;
  onBack?: () => void;
  onDefaultFullscreenChange?: (enabled: boolean) => void;
  onTogglePrivateSite?: (enabled: boolean) => void;
  onTogglePrivateSitePreserveCookies?: (enabled: boolean) => void;
  onOpenPermission?: (kind: string) => void;
  onOpenDesktopSite?: () => void;
  onSelectJavaScriptPolicy?: (policy: SiteJavaScriptPolicy) => void;
  onToggleExternalNavigation?: (policy: string, followDefault: boolean) => void;
  onResetSite?: () => void;
  @Prop siteRenderVersion: number = 0;

  build() {
    if (this.presentationMode === 'embedded' && !this.desktopPresentation) {
      Column() {
        this.buildEmbeddedHeader()
        this.buildContent()
      }
      .width('100%')
      .height('100%')
    } else if (this.presentationMode === 'standalone') {
      SettingsHdsScaffold({
        title: this.state.title,
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        showPrivateIndicator: isPrivateBoundaryRoute(this.dataScope, this.privacyMode),
        onBack: () => {
          this.onBack?.();
        }
      }) {
        this.buildContent()
      }
    } else {
      this.buildContent()
    }
  }

  @Builder
  private buildEmbeddedHeader() {
    Row({ space: 10 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor([this.storedSecondaryTextColor])
      }
      .width(36)
      .height(36)
      .type(ButtonType.Circle)
      .backgroundColor(this.storedPressedBackgroundColor)
      .stateEffect(true)
      .onClick(() => {
        this.onBack?.();
      })

      Text(this.state.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .height(56)
    .padding({ left: 4, right: 4 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildContent() {
    SettingsPresentationScrollBody({
      desktopPresentation: this.desktopPresentation,
      topPadding: this.presentationMode === 'embedded' ? 0 : 16,
      bottomPadding: 28
    }) {
      this.buildHero()
      if (this.state.exists) {
        this.buildDisplaySection()
        this.buildSiteControls()
      } else {
        this.buildMissingState()
      }
    }
  }

  @Builder
  private buildHero() {
    Column({ space: 8 }) {
      SiteIconView({
        iconUri: this.state.iconPath,
        fallbackLabel: this.state.title,
        iconSize: 62,
        cornerRadius: 18,
        frameBorderWidth: 0.5,
        containerBackgroundColor: this.storedPressedBackgroundColor,
        frameBorderColor: this.storedOutlineColor,
        textColor: this.storedSecondaryTextColor,
        imageContentScale: 1,
        fallbackFontSize: 24,
        syncLoad: true
      })

      Text(this.state.title)
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.state.subtitle.trim().length > 0) {
        Text(this.state.subtitle)
          .width('100%')
          .fontSize(13)
          .fontColor(this.storedSecondaryTextColor)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildDisplaySection() {
    SettingsSection({ title: '显示' }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsSwitchRow({
          title: '全屏模式',
          desktopPresentation: this.desktopPresentation,
          checked: this.state.defaultFullscreen,
          rowPosition: 'single',
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onChange: (enabled: boolean) => {
            this.onDefaultFullscreenChange?.(enabled);
          }
        })
      }
      SettingsFooterText({
        text: '打开后，从桌面进入这个网页应用时会让网页从屏幕顶部开始显示。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  @Builder
  private buildSiteControls() {
    if (this.state.canOpenSiteSettings) {
      SettingsFooterText({
        text: '下面这些设置只影响这个网页应用对应的站点。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
      SiteCustomizationDetailSections({
        state: this.siteState,
        renderVersion: this.siteRenderVersion,
        desktopPresentation: this.desktopPresentation,
        onTogglePrivateSite: (enabled: boolean) => {
          this.onTogglePrivateSite?.(enabled);
        },
        onTogglePrivateSitePreserveCookies: (enabled: boolean) => {
          this.onTogglePrivateSitePreserveCookies?.(enabled);
        },
        onOpenPermission: (kind: string) => {
          this.onOpenPermission?.(kind);
        },
        onOpenDesktopSite: () => {
          this.onOpenDesktopSite?.();
        },
        onSelectJavaScriptPolicy: (policy: SiteJavaScriptPolicy) => {
          this.onSelectJavaScriptPolicy?.(policy);
        },
        onToggleExternalNavigation: (policy: string, followDefault: boolean) => {
          this.onToggleExternalNavigation?.(policy, followDefault);
        },
        onReset: () => {
          this.onResetSite?.();
        }
      })
    }
  }

  @Builder
  private buildMissingState() {
    Text('这个网页应用记录不存在，可能已经被移除。')
      .width('100%')
      .fontSize(14)
      .lineHeight(20)
      .fontColor(this.storedSecondaryTextColor)
      .textAlign(TextAlign.Center)
      .padding({ left: 24, right: 24, top: 28 })
  }

}
