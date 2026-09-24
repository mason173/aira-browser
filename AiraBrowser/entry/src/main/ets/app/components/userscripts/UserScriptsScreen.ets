import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  resolveUserScriptDesktopColumnCount,
  USER_SCRIPT_DESKTOP_CARD_GAP_VP,
  UserScriptRowView,
  UserScriptValueRecoveryViewState,
  UserScriptsSettingsState
} from '../../../core/userscripts/UserScriptsSettingsViewModel';
import { AppEmptyState } from '../common/AppEmptyState';
import { SiteIconView } from '../common/SiteIconView';
import { BrowserDesktopContextMenu, BrowserDesktopContextMenuItem, buildBrowserDesktopMenuOptions } from '../browser/BrowserDesktopContextMenu';
import { SettingsSwitchRow } from '../settings/SettingsRows';
import {
  SETTINGS_DESKTOP_SCROLLBAR_GUTTER,
  SettingsGroupCard,
  SettingsSection
} from '../settings/SettingsLayout';
import { SettingsNoticeCard } from '../settings/SettingsNoticeCard';
import {
  ManagementHdsMenuAction,
  ManagementHdsScaffold
} from '../common/ManagementHdsScaffold';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  createFloatingGlassMaterialIfAvailable,
  resolveFloatingGlassMaterialBackgroundColor,
  resolveFloatingGlassMaterialTintForMode,
  systemMaterialModifier
} from '../common/FloatingGlassMaterialTokens';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { USER_SCRIPT_FEATURE_TITLE } from '../../../core/userscripts/UserScriptFeatureCopy';
import {
  SettingsDesktopWorkspaceHeader,
  SettingsDesktopWorkspaceHeaderAction
} from '../settings/SettingsDesktopWorkspaceHeader';

const USER_SCRIPTS_SECTION_CORNER_RADIUS: number = 22;
const USER_SCRIPT_DESKTOP_CARD_RADIUS_VP: number = 16;
const USER_SCRIPT_DESKTOP_CARD_MIN_HEIGHT_VP: number = 196;

class UserScriptDesktopCardRow {
  readonly key: string;
  readonly cards: UserScriptRowView[];
  readonly spacerCount: number;

  constructor(key: string, cards: UserScriptRowView[], spacerCount: number) {
    this.key = key;
    this.cards = cards;
    this.spacerCount = spacerCount;
  }
}

@Component
export struct UserScriptsScreen {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: UserScriptsSettingsState = {
    autoUpdateEnabled: false,
    rows: [],
    hasScripts: false
  };
  onToggleScript: (scriptId: string, enabled: boolean) => void = (_scriptId: string, _enabled: boolean) => {};
  onEditScript: (scriptId: string) => void = (_scriptId: string) => {};
  onUpdateScript: (scriptId: string) => void = (_scriptId: string) => {};
  onExportScript: (scriptId: string) => void = (_scriptId: string) => {};
  onUpdateAllScripts: () => void = () => {};
  onAutoUpdateChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onDeleteScript: (scriptId: string) => void = (_scriptId: string) => {};
  onDismissNotice: () => void = () => {};
  onBack: () => void = () => {};
  @Prop showBackButton: boolean = true;
  @Prop showTitleBar: boolean = true;
  @Prop useTopSafeInset: boolean = true;
  @Prop desktopPresentation: boolean = false;
  @Prop useCardLayout: boolean = false;
  @Prop showNotice: boolean = true;
  @Prop valueRecovery: UserScriptValueRecoveryViewState = {
    visible: false,
    title: '',
    message: ''
  };
  @State pressedScriptId: string = '';
  @State contextMenuScriptId: string = '';
  @State private desktopContentWidthVp: number = 0;
  onAddFromUrl: () => void = () => {};
  onImportFromFile: () => void = () => {};
  onEditSource: () => void = () => {};
  onOpenGallerySource: (url: string) => void = (_url: string) => {};

  build() {
    Column() {
      if (this.desktopPresentation && this.showTitleBar) {
        SettingsDesktopWorkspaceHeader({
          title: USER_SCRIPT_FEATURE_TITLE,
          showTitle: false,
          showBackButton: this.showBackButton,
          primaryTextColor: this.storedPrimaryTextColor,
          iconColor: this.storedSecondaryTextColor,
          buttonBackgroundColor: this.storedPressedBackgroundColor,
          menuActions: this.buildDesktopHeaderMenuActions(),
          onBack: () => {
            this.onBack();
          }
        })
      }

      if (this.desktopPresentation) {
        this.buildContent()
      } else {
        ManagementHdsScaffold({
          title: USER_SCRIPT_FEATURE_TITLE,
          backIconKind: 'close',
          pageBackground: this.storedPageBackgroundColor,
          primaryTextColor: this.storedPrimaryTextColor,
          dividerColor: this.storedDividerColor,
          showBackButton: this.showBackButton,
          showTitleBar: this.showTitleBar,
          useTopSafeInset: this.useTopSafeInset,
          menuActions: this.buildHeaderMenuActions(),
          onBack: () => {
            this.onBack();
          }
        }) {
          this.buildContent()
        }
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildContent() {
    Scroll() {
      Column({ space: 16 }) {
        if (this.showNotice) {
          SettingsNoticeCard({
            icon: $r('sys.symbol.exclamationmark_shield_fill'),
            title: '脚本会改变网页行为',
            message: '只安装可信脚本；它们可能读取页面或影响网页功能。',
            desktopPresentation: this.desktopPresentation,
            onClosed: () => {
              this.onDismissNotice();
            }
          })
        }
        this.buildScriptsSection()
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: this.desktopPresentation ? 0 : 16,
        right: this.desktopPresentation ? SETTINGS_DESKTOP_SCROLLBAR_GUTTER : 16,
        top: 8,
        bottom: 32
      })
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
    }
      .layoutWeight(1)
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .clip(this.desktopPresentation)
  }

  private buildHeaderMenuActions(): ManagementHdsMenuAction[] {
    const actions: ManagementHdsMenuAction[] = [
      {
        label: '从 URL 添加',
        icon: $r('sys.symbol.link'),
        action: () => {
          this.onAddFromUrl();
        }
      },
      {
        label: '从文件导入',
        icon: $r('sys.symbol.folder'),
        action: () => {
          this.onImportFromFile();
        }
      },
      {
        label: '编辑或粘贴源码',
        icon: $r('sys.symbol.doc_text'),
        action: () => {
          this.onEditSource();
        }
      },
      {
        label: 'Greasy Fork',
        icon: $r('sys.symbol.compass_circle_fill'),
        action: () => {
          this.onOpenGallerySource('https://greasyfork.org/zh-CN/scripts');
        }
      },
      {
        label: 'OpenUserJS',
        icon: $r('sys.symbol.compass_circle_fill'),
        action: () => {
          this.onOpenGallerySource('https://openuserjs.org/');
        }
      },
      {
        label: 'Userscript.Zone',
        icon: $r('sys.symbol.compass_circle_fill'),
        action: () => {
          this.onOpenGallerySource('https://www.userscript.zone/');
        }
      },
      {
        label: '检查更新',
        icon: $r('sys.symbol.arrow_clockwise'),
        action: () => {
          this.onUpdateAllScripts();
        }
      }
    ];
    return actions;
  }

  private buildDesktopHeaderMenuActions(): SettingsDesktopWorkspaceHeaderAction[] {
    return [
      { label: '从 URL 添加', action: (): void => this.onAddFromUrl() },
      { label: '从文件导入', action: (): void => this.onImportFromFile() },
      { label: '编辑或粘贴源码', action: (): void => this.onEditSource() },
      { label: 'Greasy Fork', action: (): void => this.onOpenGallerySource('https://greasyfork.org/zh-CN/scripts') },
      { label: 'OpenUserJS', action: (): void => this.onOpenGallerySource('https://openuserjs.org/') },
      { label: 'Userscript.Zone', action: (): void => this.onOpenGallerySource('https://www.userscript.zone/') },
      { label: '检查更新', action: (): void => this.onUpdateAllScripts() }
    ];
  }


  @Builder
  private buildScriptsSection() {
    Column({ space: 16 }) {
      if (this.valueRecovery.visible) {
        this.buildValueStateRecoverySection()
      }
      this.buildScriptAutoUpdateSection()
      if (this.state.hasScripts) {
        Column({ space: 8 }) {
          this.buildSectionTitle('已安装脚本')
          if (this.useCardLayout) {
            this.buildDesktopScriptGrid()
          } else {
            Column({ space: 12 }) {
              ForEach(this.state.rows, (row: UserScriptRowView) => {
                this.buildScriptCard(row)
              }, (row: UserScriptRowView) => row.id)
            }
            .width('100%')
          }
        }
        .width('100%')
      } else {
        this.buildStandaloneEmptyState(
          'settings.userScripts',
          '还没有安装用户脚本',
          '导入脚本后，会在这里显示并可单独管理。'
        )
      }
    }
    .width('100%')
  }

  @Builder
  private buildValueStateRecoverySection() {
    SettingsNoticeCard({
      title: this.valueRecovery.title,
      message: this.valueRecovery.message,
      dismissible: false,
      desktopPresentation: this.desktopPresentation
    })
  }

  @Builder
  private buildScriptAutoUpdateSection() {
    SettingsSection({
      title: '更新策略',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      Column({ space: 8 }) {
        SettingsGroupCard({
          surfaceColor: this.storedSurfaceBackgroundColor,
          desktopPresentation: this.desktopPresentation
        }) {
          SettingsSwitchRow({
            title: '自动检查脚本更新',
            desktopPresentation: this.desktopPresentation,
            checked: this.state.autoUpdateEnabled,
            rowPosition: 'single',
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            pressedBackgroundColor: this.storedPressedBackgroundColor,
            onChange: (enabled: boolean) => {
              this.onAutoUpdateChange(enabled);
            }
          })
        }
      }
      .width('100%')
    }
  }

  @Builder
  private buildStandaloneEmptyState(iconId: AiraRenderableIconId, title: string, message: string) {
    AppEmptyState({
      airaIconId: iconId,
      title: title,
      message: message
    })
  }

  @Builder
  private buildDesktopScriptGrid() {
    Column({ space: USER_SCRIPT_DESKTOP_CARD_GAP_VP }) {
      ForEach(this.resolveDesktopCardRows(), (group: UserScriptDesktopCardRow) => {
        Row({ space: USER_SCRIPT_DESKTOP_CARD_GAP_VP }) {
          ForEach(group.cards, (row: UserScriptRowView) => {
            this.buildDesktopScriptCard(row)
          }, (row: UserScriptRowView) => row.id)
          ForEach(this.resolveDesktopSpacerIndexes(group.spacerCount), (index: number) => {
            Column()
              .layoutWeight(1)
          }, (index: number) => `${group.key}-pad-${index}`)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }, (group: UserScriptDesktopCardRow) => group.key)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onAreaChange((_oldArea: Area, area: Area) => {
      const widthVp = Number(area.width);
      if (!Number.isFinite(widthVp) || widthVp <= 0 || Math.abs(widthVp - this.desktopContentWidthVp) < 1) {
        return;
      }
      this.desktopContentWidthVp = widthVp;
    })
  }

  @Builder
  private buildDesktopScriptCard(row: UserScriptRowView) {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        SiteIconView({
          iconUri: row.iconUrl,
          fallbackAiraIconId: 'userscripts.defaultIcon',
          iconSize: 42,
          cornerRadius: 21,
          fit: ImageFit.Contain,
          containerBackgroundColor: this.storedPressedBackgroundColor,
          frameBorderColor: this.storedDividerColor,
          textColor: this.storedPrimaryTextColor
        })

        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text(row.title)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.storedPrimaryTextColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)

            if (row.version.length > 0) {
              Text(row.version)
                .fontSize(13)
                .fontColor(this.storedSecondaryTextColor)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 96 })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(row.description.length > 0 ? row.description : '没有说明')
            .width('100%')
            .fontSize(13)
            .lineHeight(20)
            .fontColor(this.storedSecondaryTextColor)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ minHeight: 60 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .opacity(row.enabled ? 1 : 0.62)

      Column({ space: 4 }) {
        Text(`ID：${row.id}`)
          .width('100%')
          .fontSize(12)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(`作用范围：${row.scopeSummary}`)
          .width('100%')
          .fontSize(12)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .opacity(row.enabled ? 1 : 0.62)

      Blank()
        .layoutWeight(1)

      Row({ space: 8 }) {
        this.buildDesktopCardAction('详情', row.id, 'detail')
        this.buildDesktopCardAction('移除', row.id, 'remove')
        Blank()
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: row.enabled })
          .selectedColor(this.storedAccentColor)
          .onChange((enabled: boolean) => {
            this.onToggleScript(row.id, enabled);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .constraintSize({ minHeight: USER_SCRIPT_DESKTOP_CARD_MIN_HEIGHT_VP })
    .padding(16)
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .border({ width: 1, color: this.storedDividerColor })
    .borderRadius(USER_SCRIPT_DESKTOP_CARD_RADIUS_VP)
    .clip(true)
    .bindContextMenu(this.buildScriptDesktopContextMenu(row), ResponseType.RightClick, buildBrowserDesktopMenuOptions({
      onAppear: () => {
        this.contextMenuScriptId = '';
      }
    }))
  }

  @Builder
  private buildDesktopCardAction(label: string, scriptId: string, action: string) {
    Button(label)
      .type(ButtonType.Normal)
      .height(32)
      .fontSize(13)
      .fontColor(this.storedAccentColor)
      .backgroundColor(Color.Transparent)
      .border({ width: 1, color: this.storedAccentColor })
      .borderRadius(16)
      .padding({ left: 14, right: 14 })
      .stateEffect(true)
      .onClick(() => {
        if (action === 'detail') {
          this.onEditScript(scriptId);
          return;
        }
        this.onDeleteScript(scriptId);
      })
  }

  @Builder
  private buildScriptCard(row: UserScriptRowView) {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        SiteIconView({
          iconUri: row.iconUrl,
          fallbackAiraIconId: 'userscripts.defaultIcon',
          iconSize: 40,
          cornerRadius: 10,
          fit: ImageFit.Contain,
          containerBackgroundColor: this.storedPressedBackgroundColor,
          frameBorderColor: this.storedDividerColor,
          textColor: this.storedPrimaryTextColor
        })

        Text(row.title)
          .fontSize(this.desktopPresentation ? 15 : 16)
          .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: row.enabled })
          .selectedColor(this.storedAccentColor)
          .onChange((enabled: boolean) => {
            this.onToggleScript(row.id, enabled);
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.pressedScriptId === row.id
        ? this.storedPressedBackgroundColor
        : $r('sys.color.ohos_id_color_background_transparent'))
      .borderRadius(this.desktopPresentation ? 8 : 18)
      .onTouch((event: TouchEvent) => {
        this.updatePressedScript(row.id, event.type);
      })
      .gesture(
        GestureGroup(
          GestureMode.Exclusive,
          LongPressGesture({ fingers: 1, repeat: false, duration: 450 })
            .onAction(() => {
              this.contextMenuScriptId = row.id;
            }),
          TapGesture()
            .onAction(() => {
              this.onEditScript(row.id);
            })
        )
      )
      .bindContextMenu(this.contextMenuScriptId === row.id, this.buildScriptContextMenu(row), {
        preview: this.buildScriptContextPreview(row),
        previewBorderRadius: 18,
        onDisappear: () => {
          this.contextMenuScriptId = '';
        }
      })
    }
    .width('100%')
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(this.desktopPresentation ? 8 : USER_SCRIPTS_SECTION_CORNER_RADIUS)
    .clip(true)
    .bindContextMenu(this.buildScriptDesktopContextMenu(row), ResponseType.RightClick, buildBrowserDesktopMenuOptions({
      onAppear: () => {
        this.contextMenuScriptId = '';
        this.pressedScriptId = row.id;
      },
      onDisappear: () => {
        if (this.pressedScriptId === row.id) {
          this.pressedScriptId = '';
        }
      }
    }))
  }

  @Builder
  private buildScriptContextPreview(row: UserScriptRowView) {
    Row({ space: 12 }) {
      SiteIconView({
        iconUri: row.iconUrl,
        fallbackAiraIconId: 'userscripts.defaultIcon',
        iconSize: 40,
        cornerRadius: 10,
        fit: ImageFit.Contain,
        containerBackgroundColor: this.storedPressedBackgroundColor,
        frameBorderColor: this.storedDividerColor,
        textColor: this.storedPrimaryTextColor
      })

      Text(row.title)
        .fontSize(this.desktopPresentation ? 15 : 16)
        .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(18)
  }

  @Builder
  private buildScriptContextMenu(row: UserScriptRowView) {
    Menu() {
      MenuItem({ content: '查看详情' })
        .onClick(() => {
          this.onEditScript(row.id);
        })
      MenuItem({ content: '检查更新' })
        .enabled(row.canUpdate)
        .onClick(() => {
          this.onUpdateScript(row.id);
        })
      MenuItem({ content: '导出脚本' })
        .onClick(() => {
          this.onExportScript(row.id);
        })
      MenuItem({ content: '删除脚本' })
        .onClick(() => {
          this.onDeleteScript(row.id);
        })
    }
    .width(216)
    .backgroundColor(resolveFloatingGlassMaterialBackgroundColor(
      $r('app.color.surface_floating_background')
    ))
    .attributeModifier(systemMaterialModifier(createFloatingGlassMaterialIfAvailable(
      resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
    )))
  }

  @Builder
  private buildScriptDesktopContextMenu(row: UserScriptRowView) {
    BrowserDesktopContextMenu() {
      MenuItemGroup() {
        BrowserDesktopContextMenuItem({
          label: '查看详情',
          onAction: (): void => {
            this.onEditScript(row.id);
          }
        })
        BrowserDesktopContextMenuItem({
          label: '检查更新',
          itemEnabled: row.canUpdate,
          onAction: (): void => {
            this.onUpdateScript(row.id);
          }
        })
        BrowserDesktopContextMenuItem({
          label: '导出脚本',
          onAction: (): void => {
            this.onExportScript(row.id);
          }
        })
      }

      MenuItemGroup() {
        BrowserDesktopContextMenuItem({
          label: '删除脚本',
          onAction: (): void => {
            this.onDeleteScript(row.id);
          }
        })
      }
    }
  }

  @Builder
  private buildSectionTitle(title: string) {
    Text(title)
      .width('100%')
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.storedSecondaryTextColor)
      .padding({ left: 6 })
  }

  private resolveDesktopCardRows(): UserScriptDesktopCardRow[] {
    const columnCount = resolveUserScriptDesktopColumnCount(this.desktopContentWidthVp);
    const groups: UserScriptDesktopCardRow[] = [];
    const rows = this.state.rows;
    for (let index = 0; index < rows.length; index += columnCount) {
      const cards = rows.slice(index, index + columnCount);
      const firstId = cards.length > 0 ? cards[0].id : `${index}`;
      const lastId = cards.length > 0 ? cards[cards.length - 1].id : `${index}`;
      groups.push(new UserScriptDesktopCardRow(
        `${firstId}:${lastId}:${cards.length}`,
        cards,
        columnCount - cards.length
      ));
    }
    return groups;
  }

  private resolveDesktopSpacerIndexes(count: number): number[] {
    const indexes: number[] = [];
    for (let index = 0; index < count; index += 1) {
      indexes.push(index);
    }
    return indexes;
  }

  private updatePressedScript(scriptId: string, type: TouchType): void {
    if (type === TouchType.Down) {
      this.pressedScriptId = scriptId;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressedScriptId = '';
    }
  }

}
