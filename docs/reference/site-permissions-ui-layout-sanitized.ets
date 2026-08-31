/*
 * Sanitized ArkUI layout sample for a browser "Permissions & Site Settings" screen.
 *
 * This file is intentionally standalone:
 * - no product brand names
 * - no business infrastructure, persistence, navigation, or analytics code
 * - no generated icon catalog or private theme storage keys
 * - no real permission persistence logic
 *
 * Replace the sample state and callback placeholders with your own app state.
 */

type SettingsRowPosition = 'single' | 'first' | 'middle' | 'last';

type OverviewCardKind =
  'location' |
  'camera' |
  'microphone' |
  'sensor' |
  'clipboard' |
  'open_app' |
  'external_actions' |
  'content_filter_exception' |
  'desktop_site' |
  'clear_on_close';

interface OverviewCardState {
  id: OverviewCardKind;
  title: string;
  count: number;
  selected?: boolean;
  iconLabel: string;
}

interface SiteRecordState {
  id: string;
  title: string;
  host: string;
}

const PAGE_BACKGROUND: string = '#F6F8FB';
const SURFACE_BACKGROUND: string = '#FFFFFF';
const CONTROL_BACKGROUND: string = '#EEF2F6';
const PRESSED_BACKGROUND: string = '#DDE4EC';
const TEXT_PRIMARY: string = '#111318';
const TEXT_SECONDARY: string = '#5F6875';
const DIVIDER: string = '#E3E8EF';
const ACCENT: string = '#0A59F7';
const APP_HORIZONTAL_PADDING: number = 16;
const LIST_SPACE: number = 18;
const SECTION_TITLE_LEFT_PADDING: number = 6;
const GROUP_RADIUS: number = 22;
const GROUP_PADDING: number = 4;
const ROW_RADIUS: number = 18;
const ROW_HORIZONTAL_PADDING: number = 16;
const ROW_VERTICAL_PADDING: number = 14;
const OVERVIEW_CARD_GAP: number = 10;
const OVERVIEW_CARD_HEIGHT: number = 88;
const OVERVIEW_CARD_RADIUS: number = 18;
const OVERVIEW_ICON_SIZE: number = 30;
const SITE_ROW_HEIGHT: number = 58;
const SITE_ROW_CARD_PADDING: number = 4;

@Entry
@Component
struct SitePermissionSettingsDemoPage {
  @State private query: string = '';
  @State private allowCookies: boolean = true;
  @State private allowThirdPartyCookies: boolean = true;
  @State private pressedCardId: string = '';
  @State private pressedSiteId: string = '';

  private permissionCards: OverviewCardState[] = [
    { id: 'location', title: '位置信息', count: 2, iconLabel: 'LOC' },
    { id: 'camera', title: '摄像头', count: 1, iconLabel: 'CAM' },
    { id: 'microphone', title: '麦克风', count: 0, iconLabel: 'MIC' },
    { id: 'sensor', title: '传感器', count: 0, iconLabel: 'SNS' },
    { id: 'clipboard', title: '剪贴板', count: 3, iconLabel: 'CLP' }
  ];

  private siteSettingCards: OverviewCardState[] = [
    { id: 'open_app', title: '打开应用', count: 1, iconLabel: 'APP' },
    { id: 'external_actions', title: '外部动作', count: 2, iconLabel: 'EXT' },
    { id: 'content_filter_exception', title: '网页内容过滤例外', count: 1, iconLabel: 'FLT' },
    { id: 'desktop_site', title: '网站版本', count: 4, iconLabel: 'WEB' },
    { id: 'clear_on_close', title: '关闭后清除', count: 1, iconLabel: 'CLR' }
  ];

  private siteRows: SiteRecordState[] = [
    { id: 'example-news', title: 'Example News', host: 'news.example.com' },
    { id: 'example-video', title: 'Example Video', host: 'video.example.com' },
    { id: 'example-shop', title: 'Example Shop', host: 'shop.example.com' }
  ];

  build() {
    Column() {
      BrowserSettingsScaffold({
        title: '权限与站点设置',
        onBack: () => {
          // Hook this to your app navigation.
        }
      }) {
        List({ space: LIST_SPACE }) {
          ListItem() {
            SettingsSearchField({
              text: this.query,
              placeholder: '搜索站点',
              onChange: (value: string) => {
                this.query = value;
              }
            })
          }
          .width('100%')

          ListItem() {
            this.buildCookieSection()
          }
          .width('100%')

          ListItem() {
            this.buildOverviewSection('权限', this.permissionCards)
          }
          .width('100%')

          ListItem() {
            this.buildOverviewSection('站点设置', this.siteSettingCards)
          }
          .width('100%')

          if (this.filteredSites().length > 0) {
            ListItem() {
              SectionTitle({ title: '已自定义站点' })
            }
            .width('100%')
            .margin({ bottom: -8 })

            ForEach(this.filteredSites(), (site: SiteRecordState, index: number) => {
              ListItem() {
                this.buildSiteRowCard(site, index, this.filteredSites().length)
              }
              .width('100%')
            }, (site: SiteRecordState) => site.id)
          } else {
            ListItem() {
              EmptyState({
                title: '没有找到这个站点',
                message: '换个关键词再试试'
              })
            }
            .width('100%')
          }
        }
        .layoutWeight(1)
        .width('100%')
        .padding({
          left: APP_HORIZONTAL_PADDING,
          right: APP_HORIZONTAL_PADDING,
          top: 16,
          bottom: 28
        })
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PAGE_BACKGROUND)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private buildCookieSection() {
    SettingsSection({ title: 'Cookie' }) {
      GroupCard() {
        SettingsSwitchRowLite({
          title: '允许 Cookie',
          checked: this.allowCookies,
          rowPosition: 'first',
          onChange: (checked: boolean) => {
            this.allowCookies = checked;
          }
        })

        GroupDivider()

        SettingsSwitchRowLite({
          title: '允许第三方 Cookie',
          checked: this.allowThirdPartyCookies,
          rowPosition: 'last',
          onChange: (checked: boolean) => {
            this.allowThirdPartyCookies = checked;
          }
        })
      }
    }
  }

  @Builder
  private buildOverviewSection(title: string, cards: OverviewCardState[]) {
    SettingsSection({ title: title }) {
      Column({ space: OVERVIEW_CARD_GAP }) {
        ForEach(this.chunkCards(cards), (row: OverviewCardState[], rowIndex: number) => {
          Row({ space: OVERVIEW_CARD_GAP }) {
            ForEach(row, (card: OverviewCardState) => {
              OverviewCard({
                card: card,
                pressed: this.pressedCardId === card.id,
                onPressChange: (pressed: boolean) => {
                  this.pressedCardId = pressed ? card.id : '';
                },
                onAction: () => {
                  // Hook this to your capability detail page.
                }
              })
            }, (card: OverviewCardState) => card.id)

            if (row.length === 1) {
              Blank()
                .layoutWeight(1)
            }
          }
          .width('100%')
        }, (_row: OverviewCardState[], rowIndex: number) => `${title}-${rowIndex}`)
      }
      .width('100%')
    }
  }

  @Builder
  private buildSiteRowCard(site: SiteRecordState, index: number, total: number) {
    Column() {
      SiteRecordRowLite({
        title: site.title,
        host: site.host,
        pressed: this.pressedSiteId === site.id,
        rowBorderRadius: this.resolveSiteRowBorderRadius(index, total),
        showDivider: index < total - 1,
        onPressChange: (pressed: boolean) => {
          this.pressedSiteId = pressed ? site.id : '';
        },
        onAction: () => {
          // Hook this to your per-site settings page.
        }
      })
    }
    .width('100%')
    .padding({
      left: SITE_ROW_CARD_PADDING,
      right: SITE_ROW_CARD_PADDING,
      top: index === 0 ? SITE_ROW_CARD_PADDING : 0,
      bottom: index >= total - 1 ? SITE_ROW_CARD_PADDING : 0
    })
    .backgroundColor(SURFACE_BACKGROUND)
    .borderRadius(this.resolveSiteRowCardRadius(index, total))
    .clip(true)
  }

  private filteredSites(): SiteRecordState[] {
    const normalizedQuery = this.query.trim().toLowerCase();
    if (normalizedQuery.length <= 0) {
      return this.siteRows;
    }
    return this.siteRows.filter((site: SiteRecordState): boolean => {
      return site.title.toLowerCase().indexOf(normalizedQuery) >= 0 ||
        site.host.toLowerCase().indexOf(normalizedQuery) >= 0;
    });
  }

  private chunkCards(cards: OverviewCardState[]): OverviewCardState[][] {
    const rows: OverviewCardState[][] = [];
    for (let index = 0; index < cards.length; index += 2) {
      rows.push(cards.slice(index, index + 2));
    }
    return rows;
  }

  private resolveSiteRowCardRadius(index: number, total: number): number | BorderRadiuses {
    if (total <= 1) {
      return GROUP_RADIUS;
    }
    if (index === 0) {
      return {
        topLeft: GROUP_RADIUS,
        topRight: GROUP_RADIUS,
        bottomLeft: 0,
        bottomRight: 0
      };
    }
    if (index >= total - 1) {
      return {
        topLeft: 0,
        topRight: 0,
        bottomLeft: GROUP_RADIUS,
        bottomRight: GROUP_RADIUS
      };
    }
    return 0;
  }

  private resolveSiteRowBorderRadius(index: number, total: number): number | BorderRadiuses {
    if (total <= 1) {
      return ROW_RADIUS;
    }
    if (index === 0) {
      return {
        topLeft: ROW_RADIUS,
        topRight: ROW_RADIUS,
        bottomLeft: 0,
        bottomRight: 0
      };
    }
    if (index >= total - 1) {
      return {
        topLeft: 0,
        topRight: 0,
        bottomLeft: ROW_RADIUS,
        bottomRight: ROW_RADIUS
      };
    }
    return 0;
  }
}

@Component
struct BrowserSettingsScaffold {
  @Prop title: string = '';
  onBack?: () => void;
  @BuilderParam content: () => void = this.emptyBuilder;

  build() {
    Column() {
      Row({ space: 8 }) {
        Button() {
          Text('<')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_SECONDARY)
        }
        .width(36)
        .height(36)
        .type(ButtonType.Circle)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .stateEffect(true)
        .onClick(() => {
          this.onBack?.();
        })

        Text(this.title)
          .layoutWeight(1)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(54)
      .padding({ left: 12, right: 16 })
      .alignItems(VerticalAlign.Center)

      Divider()
        .width('100%')
        .height(1)
        .color(DIVIDER)

      this.content()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PAGE_BACKGROUND)
  }

  @Builder
  private emptyBuilder() {
  }
}

@Component
struct SettingsSection {
  @Prop title: string = '';
  @BuilderParam content: () => void = this.emptyBuilder;

  build() {
    Column({ space: 10 }) {
      if (this.title.length > 0) {
        SectionTitle({ title: this.title })
      }

      this.content()
    }
    .width('100%')
  }

  @Builder
  private emptyBuilder() {
  }
}

@Component
struct SectionTitle {
  @Prop title: string = '';

  build() {
    Text(this.title)
      .width('100%')
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(TEXT_SECONDARY)
      .padding({ left: SECTION_TITLE_LEFT_PADDING })
  }
}

@Component
struct GroupCard {
  @BuilderParam content: () => void = this.emptyBuilder;

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding({
      left: GROUP_PADDING,
      right: GROUP_PADDING,
      top: GROUP_PADDING,
      bottom: GROUP_PADDING
    })
    .backgroundColor(SURFACE_BACKGROUND)
    .borderRadius(GROUP_RADIUS)
    .clip(true)
  }

  @Builder
  private emptyBuilder() {
  }
}

@Component
struct GroupDivider {
  build() {
    Divider()
      .width('100%')
      .height(1)
      .color(DIVIDER)
      .margin({ left: ROW_HORIZONTAL_PADDING, right: ROW_HORIZONTAL_PADDING })
  }
}

@Component
struct SettingsSearchField {
  @Prop text: string = '';
  @Prop placeholder: string = '';
  onChange: (value: string) => void = (_value: string) => {};

  build() {
    TextInput({ text: this.text, placeholder: this.placeholder })
      .width('100%')
      .height(46)
      .fontSize(15)
      .fontColor(TEXT_PRIMARY)
      .placeholderColor(TEXT_SECONDARY)
      .backgroundColor(CONTROL_BACKGROUND)
      .borderRadius(14)
      .padding({ left: 12, right: 12 })
      .onChange((value: string) => {
        this.onChange(value);
      })
  }
}

@Component
struct SettingsSwitchRowLite {
  @Prop title: string = '';
  @Prop checked: boolean = false;
  @Prop rowPosition: SettingsRowPosition = 'single';
  @State private pressed: boolean = false;
  onChange: (checked: boolean) => void = (_checked: boolean) => {};

  build() {
    Row({ space: 12 }) {
      Text(this.title)
        .layoutWeight(1)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Toggle({ type: ToggleType.Switch, isOn: this.checked })
        .selectedColor(ACCENT)
        .onChange((checked: boolean) => {
          this.onChange(checked);
        })
    }
    .width('100%')
    .backgroundColor(this.pressed ? PRESSED_BACKGROUND : Color.Transparent)
    .borderRadius(resolveRowRadius(this.rowPosition))
    .clip(true)
    .padding({
      left: ROW_HORIZONTAL_PADDING,
      right: ROW_HORIZONTAL_PADDING,
      top: ROW_VERTICAL_PADDING,
      bottom: ROW_VERTICAL_PADDING
    })
    .alignItems(VerticalAlign.Center)
    .onTouch((event: TouchEvent) => {
      this.pressed = event.type === TouchType.Down;
    })
  }
}

@Component
struct OverviewCard {
  @Prop card: OverviewCardState = {
    id: 'location',
    title: '',
    count: 0,
    iconLabel: ''
  };
  @Prop pressed: boolean = false;
  onPressChange: (pressed: boolean) => void = (_pressed: boolean) => {};
  onAction: () => void = () => {};

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Stack({ alignContent: Alignment.Center }) {
          Text(this.card.iconLabel)
            .fontSize(9)
            .fontWeight(FontWeight.Bold)
            .fontColor(SURFACE_BACKGROUND)
        }
        .width(OVERVIEW_ICON_SIZE)
        .height(OVERVIEW_ICON_SIZE)
        .borderRadius(10)
        .backgroundColor(this.resolveIconColor())

        Text(this.card.title)
          .layoutWeight(1)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(`${this.card.count} 个网站`)
        .width('100%')
        .fontSize(14)
        .fontColor(TEXT_SECONDARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .layoutWeight(1)
    .height(OVERVIEW_CARD_HEIGHT)
    .padding({ left: 14, right: 14, top: 13, bottom: 13 })
    .backgroundColor(this.resolveCardBackground())
    .border({
      width: this.card.selected === true ? 1.5 : 0,
      color: ACCENT
    })
    .borderRadius(OVERVIEW_CARD_RADIUS)
    .clip(true)
    .alignItems(HorizontalAlign.Start)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.onPressChange(true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.onPressChange(false);
      }
    })
    .onClick(() => {
      this.onAction();
    })
  }

  private resolveCardBackground(): ResourceColor {
    if (this.pressed || this.card.selected === true) {
      return PRESSED_BACKGROUND;
    }
    return SURFACE_BACKGROUND;
  }

  private resolveIconColor(): ResourceColor {
    switch (this.card.id) {
      case 'location':
        return '#2E8B57';
      case 'camera':
        return '#5B6EE1';
      case 'microphone':
        return '#7A54B8';
      case 'sensor':
        return '#B35F2A';
      case 'clipboard':
        return '#2F7E91';
      case 'open_app':
        return '#3D72B4';
      case 'external_actions':
        return '#64748B';
      case 'content_filter_exception':
        return '#9A6B2F';
      case 'desktop_site':
        return '#475569';
      case 'clear_on_close':
        return '#B34A4A';
      default:
        return ACCENT;
    }
  }
}

@Component
struct SiteRecordRowLite {
  @Prop title: string = '';
  @Prop host: string = '';
  @Prop pressed: boolean = false;
  @Prop showDivider: boolean = false;
  @Prop rowBorderRadius: number | BorderRadiuses = ROW_RADIUS;
  onPressChange: (pressed: boolean) => void = (_pressed: boolean) => {};
  onAction: () => void = () => {};

  build() {
    Column() {
      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.Center }) {
          Text(this.resolveFallbackLabel())
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(SURFACE_BACKGROUND)
        }
        .width(36)
        .height(36)
        .borderRadius(12)
        .backgroundColor('#78909C')

        Column({ space: 2 }) {
          Text(this.title)
            .width('100%')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.host)
            .width('100%')
            .fontSize(13)
            .fontColor(TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text('>')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_SECONDARY)
      }
      .width('100%')
      .height(SITE_ROW_HEIGHT)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      if (this.showDivider) {
        Divider()
          .width('100%')
          .height(1)
          .color(DIVIDER)
          .margin({ left: 60, right: 12 })
      }
    }
    .width('100%')
    .backgroundColor(this.pressed ? PRESSED_BACKGROUND : Color.Transparent)
    .borderRadius(this.rowBorderRadius)
    .clip(true)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.onPressChange(true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.onPressChange(false);
      }
    })
    .onClick(() => {
      this.onAction();
    })
  }

  private resolveFallbackLabel(): string {
    const trimmedTitle = this.title.trim();
    if (trimmedTitle.length > 0) {
      return trimmedTitle.substring(0, 1).toUpperCase();
    }
    const trimmedHost = this.host.trim();
    return trimmedHost.length > 0 ? trimmedHost.substring(0, 1).toUpperCase() : '?';
  }
}

@Component
struct EmptyState {
  @Prop title: string = '';
  @Prop message: string = '';

  build() {
    Column({ space: 8 }) {
      Text(this.title)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_PRIMARY)

      Text(this.message)
        .fontSize(14)
        .fontColor(TEXT_SECONDARY)
    }
    .width('100%')
    .padding({ top: 92, bottom: 92 })
    .alignItems(HorizontalAlign.Center)
  }
}

function resolveRowRadius(position: SettingsRowPosition): number | BorderRadiuses {
  if (position === 'single') {
    return ROW_RADIUS;
  }
  if (position === 'first') {
    return {
      topLeft: ROW_RADIUS,
      topRight: ROW_RADIUS,
      bottomLeft: 0,
      bottomRight: 0
    };
  }
  if (position === 'last') {
    return {
      topLeft: 0,
      topRight: 0,
      bottomLeft: ROW_RADIUS,
      bottomRight: ROW_RADIUS
    };
  }
  return 0;
}
