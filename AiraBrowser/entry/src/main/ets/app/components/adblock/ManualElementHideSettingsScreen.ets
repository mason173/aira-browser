import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  ManualElementHideSettingsViewState,
  ManualElementHideSiteRowViewState
} from '../../../core/adblock/ManualElementHideSettingsViewModel';
import { AppEmptyState } from '../common/AppEmptyState';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsPresentationScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';
import { SettingsNavigationRow } from '../settings/SettingsRows';
import { SiteIconView } from '../common/SiteIconView';
import { resolveSiteIconFallbackLabel } from '../../../common/utils/SiteIconFallbackUtils';
import {
  SiteIconListPresenter,
  SiteIconListRenderState,
  SiteIconListResolvedIcon,
  SiteIconListTarget
} from '../../../core/siteicons/SiteIconListPresenter';
import { isPrivateBoundaryRoute } from '../../../common/utils/RouteParamUtils';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import {
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';

@Component
export struct ManualElementHideSettingsScreen {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private settingsScroller: Scroller = new Scroller();
  private siteIconListPresenter: SiteIconListPresenter = new SiteIconListPresenter();
  @StorageProp(BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY)
  private storedSiteIconCornerRadiusRatio: number = 0.3;
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Watch('syncSiteIcons')
  @Prop state: ManualElementHideSettingsViewState = {
    summaryText: '还没有清理过页面元素',
    rows: [],
    hasRows: false
  };
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop pageBackground: ResourceColor | undefined = undefined;
  @Prop surfaceBackground: ResourceColor | undefined = undefined;
  @Prop pressedBackground: ResourceColor | undefined = undefined;
  @Prop dividerColor: ResourceColor | undefined = undefined;
  @Prop primaryTextColor: ResourceColor | undefined = undefined;
  @Prop secondaryTextColor: ResourceColor | undefined = undefined;
  @Prop useTopSafeInset: boolean = true;
  @Prop desktopPresentation: boolean = false;
  @State private iconStates: SiteIconListRenderState[] = [];
  onOpenSite: (host: string) => void = (_host: string) => {};
  onBack?: () => void;

  aboutToAppear(): void {
    this.siteIconListPresenter.bindDomainUpdates(
      (): SiteIconListTarget[] => this.buildSiteIconTargets(),
      (result: SiteIconListResolvedIcon): void => this.applyResolvedSiteIcon(result)
    );
    this.syncSiteIcons();
  }

  aboutToDisappear(): void {
    this.siteIconListPresenter.dispose();
  }

  build() {
    SettingsHdsScaffold({
      title: '已清理页面元素',
      backIconKind: 'back',
      pageBackground: this.resolvePageBackground(),
      headerButtonBackground: this.resolvePressedBackground(),
      primaryTextColor: this.resolvePrimaryTextColor(),
      dividerColor: this.resolveDividerColor(),
      showPrivateIndicator: isPrivateBoundaryRoute(this.dataScope, this.privacyMode),
      showBackButton: !this.desktopPresentation,
      showTitleBar: !this.desktopPresentation,
      useTopSafeInset: this.useTopSafeInset,
      desktopPresentation: this.desktopPresentation,
      scrollers: [this.settingsScroller],
      onBack: () => {
        if (this.onBack !== undefined) {
          this.onBack();
          return;
        }
        this.navigationCoordinator.back();
      }
    }) {
      Column() {
        SettingsPresentationScrollBody({
          contentSpace: 18,
          desktopPresentation: this.desktopPresentation,
          topPadding: 16,
          bottomPadding: 32,
          scroller: this.settingsScroller,
          clipContent: true
        }) {
          this.buildSummarySection()
          this.buildSiteSection()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.resolvePageBackground())
    }
  }

  @Builder
  private buildSummarySection() {
    SettingsSection({
      title: '概览',
      secondaryTextColor: this.resolveSecondaryTextColor()
    }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text(this.state.summaryText)
              .width('100%')
              .fontSize(this.desktopPresentation ? 15 : 16)
              .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
              .fontColor(this.resolvePrimaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text('关闭某个网站后，刷新或再次打开时不再自动隐藏')
              .width('100%')
              .fontSize(13)
              .lineHeight(18)
              .fontColor(this.resolveSecondaryTextColor())
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .alignItems(VerticalAlign.Center)
      }
    }
  }

  @Builder
  private buildSiteSection() {
    if (this.state.hasRows) {
      SettingsSection({
        title: '网站',
        secondaryTextColor: this.resolveSecondaryTextColor()
      }) {
        Column({ space: 10 }) {
          ForEach(this.state.rows, (item: ManualElementHideSiteRowViewState) => {
            SettingsGroupCard({
              surfaceColor: this.resolveSurfaceBackground(),
              desktopPresentation: this.desktopPresentation
            }) {
              this.buildSiteRow(item)
            }
          }, (item: ManualElementHideSiteRowViewState) => item.id)
        }
        .width('100%')
      }
    } else {
      AppEmptyState({
        airaIconId: 'browser.toolbar.manualElementHide',
        title: '还没有清理过页面元素',
        message: '在网页里使用“标记广告”后，站点会出现在这里',
        topPadding: 72,
        bottomPadding: 72,
        fillHeight: false,
        primaryTextColor: this.resolvePrimaryTextColor(),
        secondaryTextColor: this.resolveSecondaryTextColor()
      })
    }
  }

  @Builder
  private buildSiteRow(item: ManualElementHideSiteRowViewState) {
    SettingsNavigationRow({
      title: item.title,
      desktopPresentation: this.desktopPresentation,
      value: `${item.ruleCount} 项`,
      rowPosition: 'single',
      useCustomLeading: true,
      primaryTextColor: this.resolvePrimaryTextColor(),
      secondaryTextColor: this.resolveSecondaryTextColor(),
      pressedBackgroundColor: this.resolvePressedBackground(),
      onAction: () => {
        this.onOpenSite(item.host);
      },
      customLeading: () => {
        this.buildSiteIcon(item)
      }
    })
  }

  @Builder
  private buildSiteIcon(item: ManualElementHideSiteRowViewState) {
    SiteIconView({
      iconUri: this.getIconState(item.id)?.path ?? '',
      iconPixelMap: this.getIconState(item.id)?.pixelMap,
      fallbackLabel: resolveSiteIconFallbackLabel(item.title, item.host),
      iconSize: 34,
      cornerRadiusRatio: this.storedSiteIconCornerRadiusRatio,
      frameBorderWidth: 0,
      containerBackgroundColor: this.storedControlBackgroundColor,
      textColor: this.resolvePrimaryTextColor(),
      preferPixelMap: this.getIconState(item.id)?.pixelMap !== undefined,
      sourceRevision: this.getIconState(item.id)?.sourceRevision ?? 0,
      onIconLoadError: (iconUri: string, sourceRevision: number) => {
        this.resolveSiteIconPixelMap(item, iconUri, sourceRevision);
      }
    })
  }

  private syncSiteIcons(): void {
    this.iconStates = this.iconStates.filter((icon: SiteIconListRenderState): boolean => {
      return this.state.rows.some((row: ManualElementHideSiteRowViewState): boolean => row.id === icon.id);
    });
    this.siteIconListPresenter.resolveTargets(
      this.buildSiteIconTargets(),
      (result: SiteIconListResolvedIcon): void => this.applyResolvedSiteIcon(result),
      {
        shouldSkipTarget: (target: SiteIconListTarget): boolean =>
          this.siteIconListPresenter.hasResolvedIcon(this.iconStates, target)
      }
    );
  }

  private buildSiteIconTargets(): SiteIconListTarget[] {
    return this.state.rows.map((item: ManualElementHideSiteRowViewState): SiteIconListTarget => {
      return this.buildSiteIconTarget(item);
    });
  }

  private buildSiteIconTarget(item: ManualElementHideSiteRowViewState): SiteIconListTarget {
    return {
      id: item.id,
      url: item.host.length > 0 ? `https://${item.host}/` : '',
      domain: item.host
    };
  }

  private applyResolvedSiteIcon(result: SiteIconListResolvedIcon): void {
    this.iconStates = this.siteIconListPresenter.applyResolvedIcon(this.iconStates, result);
  }

  private resolveSiteIconPixelMap(
    item: ManualElementHideSiteRowViewState,
    iconUri: string,
    sourceRevision: number
  ): void {
    this.siteIconListPresenter.resolvePixelMapAfterUriFailure(
      this.buildSiteIconTarget(item),
      iconUri,
      sourceRevision,
      (result: SiteIconListResolvedIcon): void => this.applyResolvedSiteIcon(result)
    );
  }

  private getIconState(id: string): SiteIconListRenderState | undefined {
    return this.iconStates.find((item: SiteIconListRenderState): boolean => item.id === id);
  }

  private resolvePageBackground(): ResourceColor {
    return this.pageBackground === undefined ? this.storedPageBackgroundColor : this.pageBackground;
  }

  private resolveSurfaceBackground(): ResourceColor {
    return this.surfaceBackground === undefined ? this.storedSurfaceBackgroundColor : this.surfaceBackground;
  }

  private resolvePressedBackground(): ResourceColor {
    return this.pressedBackground === undefined ? this.storedPressedBackgroundColor : this.pressedBackground;
  }

  private resolveDividerColor(): ResourceColor {
    return this.dividerColor === undefined ? this.storedDividerColor : this.dividerColor;
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return this.primaryTextColor === undefined ? this.storedPrimaryTextColor : this.primaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return this.secondaryTextColor === undefined ? this.storedSecondaryTextColor : this.secondaryTextColor;
  }
}
