import {
  BuiltInSearchEngineVisibilityRowView
} from '../../../core/search/SearchEngineManagementViewModel';
import { SearchEngineId } from '../../../common/models/BrowserModels';
import { BrowserThemeViewState } from '../../../core/theme/BrowserThemeViewState';
import { isPrivateBoundaryRoute } from '../../../common/utils/RouteParamUtils';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsPresentationScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';
import { SearchEngineIconResources } from './SearchEngineIconResources';
import {
  SettingsTargetRevealController,
  SettingsTargetRevealRegion
} from '../settings/SettingsTargetReveal';

@Component
export struct SearchBuiltInEngineVisibilityScreen {
  private settingsScroller: Scroller = new Scroller();
  @Prop rows: BuiltInSearchEngineVisibilityRowView[] = [];
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop theme: BrowserThemeViewState;
  @Prop useTopSafeInset: boolean = true;
  @Prop desktopPresentation: boolean = false;
  @Prop @Watch('handleRevealRequest') revealTargetId: string = '';
  @Prop @Watch('handleRevealRequest') revealRevision: number = 0;
  @State private highlightedTargetId: string = '';
  private revealController: SettingsTargetRevealController = new SettingsTargetRevealController(
    (targetId: string): void => {
      this.highlightedTargetId = targetId;
    }
  );
  onBack: () => void = () => {};
  onToggleEngine: (engineId: SearchEngineId, enabled: boolean) => void = (_engineId: SearchEngineId, _enabled: boolean) => {};

  aboutToAppear(): void {
    this.revealController.bindScroller(this.settingsScroller);
    this.handleRevealRequest();
  }

  aboutToDisappear(): void {
    this.revealController.dispose();
  }

  build() {
    SettingsHdsScaffold({
      title: '更多搜索引擎',
      backIconKind: 'back',
      pageBackground: this.theme.pageBackground,
      headerButtonBackground: this.theme.controlBackground,
      primaryTextColor: this.theme.textPrimary,
      dividerColor: this.theme.divider,
      showPrivateIndicator: isPrivateBoundaryRoute(this.dataScope, this.privacyMode),
      showBackButton: !this.desktopPresentation,
      showTitleBar: !this.desktopPresentation,
      useTopSafeInset: this.useTopSafeInset,
      desktopPresentation: this.desktopPresentation,
      onBack: () => {
        this.onBack();
      }
    }) {
      SettingsPresentationScrollBody({
        contentSpace: 18,
        desktopPresentation: this.desktopPresentation,
        topPadding: 16,
        bottomPadding: 32,
        scroller: this.settingsScroller,
        onContentAreaChanged: (area: Area): void => {
          this.revealController.rememberContentArea(area);
        }
      }) {
        SettingsSection({
          title: '显示在常用列表',
          secondaryTextColor: this.theme.textSecondary
        }) {
          SettingsGroupCard({
            surfaceColor: this.theme.surfaceBackground,
            desktopPresentation: this.desktopPresentation
          }) {
            ForEach(this.rows, (row: BuiltInSearchEngineVisibilityRowView, index: number) => {
              this.buildEngineRow(row)
              if (index < this.rows.length - 1) {
                SettingsGroupDivider({ dividerColor: this.theme.divider })
              }
            }, (row: BuiltInSearchEngineVisibilityRowView) => this.resolveRowKey(row))
          }
        }
      }
    }
  }

  @Builder
  private buildEngineRow(row: BuiltInSearchEngineVisibilityRowView) {
    SettingsTargetRevealRegion({
      targetId: `search_engine_${row.id}`,
      highlightedTargetId: this.highlightedTargetId,
      accentColor: this.theme.accent,
      onAreaChanged: (targetId: string, area: Area): void => {
        this.revealController.rememberTargetArea(targetId, area);
      }
    }) {
      Row({ space: 12 }) {
        this.buildLeadingIcon(row)

        Row({ space: 8 }) {
          Text(row.title)
            .fontSize(this.desktopPresentation ? 15 : 16)
            .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
            .fontColor(row.canDisable ? this.theme.textPrimary : this.theme.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (row.isDefault) {
            Text('默认')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.theme.accent)
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .backgroundColor(this.theme.controlBackground)
              .borderRadius(7)
          }
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)

        Toggle({ type: ToggleType.Switch, isOn: row.isEnabled })
          .enabled(row.canDisable)
          .opacity(row.canDisable ? 1 : 0.48)
          .selectedColor(this.theme.accent)
          .onChange((enabled: boolean) => {
            if (row.canDisable && row.isEnabled !== enabled) {
              this.onToggleEngine(row.id, enabled);
            }
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .alignItems(VerticalAlign.Center)
    }
  }

  private handleRevealRequest(): void {
    this.revealController.request(this.revealTargetId, this.revealRevision);
  }

  @Builder
  private buildLeadingIcon(row: BuiltInSearchEngineVisibilityRowView) {
    if (SearchEngineIconResources.builtInIcon(row.id) !== undefined) {
      Stack() {
        Image(SearchEngineIconResources.builtInIcon(row.id))
          .width(28)
          .height(28)
          .objectFit(ImageFit.Contain)
      }
      .width(38)
      .height(38)
      .borderRadius(12)
      .clip(true)
      .backgroundColor(this.theme.surfaceBackground)
      .borderWidth(1)
      .borderColor(this.theme.divider)
    } else {
      Row() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor([this.theme.accent])
      }
      .width(38)
      .height(38)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.theme.controlBackground)
      .borderRadius(12)
    }
  }

  private resolveRowKey(row: BuiltInSearchEngineVisibilityRowView): string {
    return `${row.id}:${row.isEnabled ? '1' : '0'}:${row.isDefault ? '1' : '0'}`;
  }
}
