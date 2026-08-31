/*
 * Sanitized ArkUI structure sample for a browser Search settings page.
 *
 * This sample keeps only the current settings-page layout:
 * - page scaffold
 * - grouped navigation rows
 * - grouped switch rows
 * - footer copy
 * - bottom maintenance action
 *
 * Plug these callbacks into your own app state. The file intentionally omits
 * engine storage, suggestion fetching, history storage, dialogs, routing, and
 * paid-feature checks.
 */

type SettingsRowPosition = 'single' | 'first' | 'middle' | 'last';
type ActionButtonEmphasis = 'primary' | 'danger';

interface SearchSettingsUiState {
  defaultEngineName: string;
  quickSwitchingEnabled: boolean;
  fallbackEnabled: boolean;
  fallbackEngineName: string;
  fallbackSelectable: boolean;
  fallbackNoticeEnabled: boolean;
  externalSearchSummary: string;
  historySuggestionsEnabled: boolean;
  networkSuggestionsEnabled: boolean;
}

const PAGE_BACKGROUND: string = '#F6F8FB';
const SURFACE_BACKGROUND: string = '#FFFFFF';
const CONTROL_BACKGROUND: string = '#EEF2F6';
const PRESSED_BACKGROUND: string = '#DDE4EC';
const TEXT_PRIMARY: string = '#111318';
const TEXT_SECONDARY: string = '#5F6875';
const DIVIDER: string = '#E3E8EF';
const ACCENT: string = '#0A59F7';
const DANGER: string = '#C2413A';
const APP_HORIZONTAL_PADDING: number = 16;
const HEADER_HEIGHT: number = 54;
const CONTENT_SPACE: number = 18;
const GROUP_RADIUS: number = 22;
const GROUP_PADDING: number = 4;
const ROW_RADIUS: number = 18;
const ROW_HORIZONTAL_PADDING: number = 16;
const ROW_VERTICAL_PADDING: number = 14;
const ROW_SPACE: number = 12;
const SECTION_TITLE_LEFT_PADDING: number = 6;
const ACTION_BUTTON_HEIGHT: number = 44;

@Entry
@Component
struct SearchSettingsStructureDemoPage {
  @State private state: SearchSettingsUiState = {
    defaultEngineName: 'Bing',
    quickSwitchingEnabled: true,
    fallbackEnabled: false,
    fallbackEngineName: '',
    fallbackSelectable: true,
    fallbackNoticeEnabled: true,
    externalSearchSummary: '已开启',
    historySuggestionsEnabled: true,
    networkSuggestionsEnabled: true
  };

  build() {
    SettingsScaffoldLite({
      title: '搜索',
      onBack: () => {
        // Connect to your app navigation.
      }
    }) {
      SettingsScrollBodyLite() {
        this.buildSearchEngineSection()
        this.buildMoreSearchMethodsSection()
        this.buildSuggestionsSection()
        this.buildClearSearchHistoryAction()
      }
    }
  }

  @Builder
  private buildSearchEngineSection() {
    SettingsSectionLite({ title: '搜索引擎' }) {
      SettingsGroupCardLite() {
        NavigationRowLite({
          title: '默认搜索引擎',
          value: this.state.defaultEngineName,
          rowPosition: 'first',
          onAction: () => {
            // Open default engine picker.
          }
        })

        SettingsGroupDividerLite()

        SwitchRowLite({
          title: '快速切换搜索引擎',
          checked: this.state.quickSwitchingEnabled,
          rowPosition: 'middle',
          onChange: (enabled: boolean) => {
            this.state.quickSwitchingEnabled = enabled;
          }
        })

        SettingsGroupDividerLite()

        SwitchRowLite({
          title: '智能搜索回退',
          checked: this.state.fallbackEnabled,
          isEnabled: this.state.fallbackSelectable,
          rowPosition: 'middle',
          onChange: (enabled: boolean) => {
            this.state.fallbackEnabled = enabled;
          }
        })

        SettingsGroupDividerLite()

        NavigationRowLite({
          title: '备用搜索引擎',
          value: this.resolveFallbackEngineName(),
          isEnabled: this.state.fallbackEnabled && this.state.fallbackSelectable,
          rowPosition: 'middle',
          onAction: () => {
            // Open fallback engine picker.
          }
        })

        SettingsGroupDividerLite()

        SwitchRowLite({
          title: '回退提示',
          checked: this.state.fallbackNoticeEnabled,
          isEnabled: this.state.fallbackEnabled,
          rowPosition: 'last',
          onChange: (enabled: boolean) => {
            this.state.fallbackNoticeEnabled = enabled;
          }
        })
      }

      SettingsFooterTextLite({
        text: '主搜索引擎不可用时，可切换到备用搜索引擎完成本次搜索。'
      })
    }
  }

  @Builder
  private buildMoreSearchMethodsSection() {
    SettingsSectionLite({ title: '更多搜索方式' }) {
      SettingsGroupCardLite() {
        NavigationRowLite({
          title: '跨应用搜索',
          value: this.state.externalSearchSummary,
          rowPosition: 'single',
          onAction: () => {
            // Open external search settings.
          }
        })
      }
    }
  }

  @Builder
  private buildSuggestionsSection() {
    SettingsSectionLite({ title: '搜索建议' }) {
      SettingsGroupCardLite() {
        SwitchRowLite({
          title: '搜索历史建议',
          checked: this.state.historySuggestionsEnabled,
          rowPosition: 'first',
          onChange: (enabled: boolean) => {
            this.state.historySuggestionsEnabled = enabled;
          }
        })

        SettingsGroupDividerLite()

        SwitchRowLite({
          title: '网络搜索建议',
          checked: this.state.networkSuggestionsEnabled,
          rowPosition: 'last',
          onChange: (enabled: boolean) => {
            this.state.networkSuggestionsEnabled = enabled;
          }
        })
      }

      SettingsFooterTextLite({
        text: '可按需控制本机历史建议和网络联想建议。'
      })
    }
  }

  @Builder
  private buildClearSearchHistoryAction() {
    ActionButtonLite({
      title: '清除搜索历史',
      emphasis: 'danger',
      onAction: () => {
        // Show your confirmation dialog before clearing data.
      }
    })
  }

  private resolveFallbackEngineName(): string {
    return this.state.fallbackEngineName.length > 0 ? this.state.fallbackEngineName : '未选择';
  }
}

@Component
struct SettingsScaffoldLite {
  @Prop title: string = '';
  onBack: () => void = () => {};
  @BuilderParam content: () => void = this.emptyBuilder;

  build() {
    Column() {
      Row({ space: 8 }) {
        Button() {
          Text('<')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(ACCENT)
        }
        .width(36)
        .height(36)
        .type(ButtonType.Circle)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .stateEffect(true)
        .backgroundColor(CONTROL_BACKGROUND)
        .onClick(() => {
          this.onBack();
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
      .height(HEADER_HEIGHT)
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
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private emptyBuilder() {
  }
}

@Component
struct SettingsScrollBodyLite {
  @BuilderParam content: () => void = this.emptyBuilder;

  build() {
    Scroll() {
      Column({ space: CONTENT_SPACE }) {
        this.content()
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: APP_HORIZONTAL_PADDING,
        right: APP_HORIZONTAL_PADDING,
        top: 16,
        bottom: 32
      })
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder
  private emptyBuilder() {
  }
}

@Component
struct SettingsSectionLite {
  @Prop title: string = '';
  @BuilderParam content: () => void = this.emptyBuilder;

  build() {
    Column({ space: 10 }) {
      if (this.title.length > 0) {
        Text(this.title)
          .width('100%')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_SECONDARY)
          .padding({ left: SECTION_TITLE_LEFT_PADDING })
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
struct SettingsGroupCardLite {
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
struct SettingsGroupDividerLite {
  build() {
    Divider()
      .width('100%')
      .height(1)
      .color(DIVIDER)
      .margin({ left: ROW_HORIZONTAL_PADDING, right: ROW_HORIZONTAL_PADDING })
  }
}

@Component
struct NavigationRowLite {
  @Prop title: string = '';
  @Prop value: string = '';
  @Prop rowPosition: SettingsRowPosition = 'single';
  @Prop isEnabled: boolean = true;
  @State private pressed: boolean = false;
  onAction: () => void = () => {};

  build() {
    Row({ space: ROW_SPACE }) {
      Text(this.title)
        .layoutWeight(1)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isEnabled ? TEXT_PRIMARY : TEXT_SECONDARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.value)
        .constraintSize({ maxWidth: 180 })
        .fontSize(14)
        .fontColor(TEXT_SECONDARY)
        .textAlign(TextAlign.End)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text('>')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_SECONDARY)
    }
    .width('100%')
    .backgroundColor(this.resolveBackground())
    .borderRadius(resolveRowRadius(this.rowPosition))
    .clip(true)
    .padding({
      left: ROW_HORIZONTAL_PADDING,
      right: ROW_HORIZONTAL_PADDING,
      top: ROW_VERTICAL_PADDING,
      bottom: ROW_VERTICAL_PADDING
    })
    .alignItems(VerticalAlign.Center)
    .enabled(this.isEnabled)
    .opacity(this.isEnabled ? 1 : 0.48)
    .onTouch((event: TouchEvent) => {
      this.updatePressed(event.type);
    })
    .onClick(() => {
      if (this.isEnabled) {
        this.onAction();
      }
    })
  }

  private updatePressed(type: TouchType): void {
    if (!this.isEnabled) {
      this.pressed = false;
      return;
    }
    if (type === TouchType.Down) {
      this.pressed = true;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressed = false;
    }
  }

  private resolveBackground(): ResourceColor {
    return this.pressed && this.isEnabled ? PRESSED_BACKGROUND : Color.Transparent;
  }
}

@Component
struct SwitchRowLite {
  @Prop title: string = '';
  @Prop checked: boolean = false;
  @Prop rowPosition: SettingsRowPosition = 'single';
  @Prop isEnabled: boolean = true;
  @State private pressed: boolean = false;
  onChange: (checked: boolean) => void = (_checked: boolean) => {};

  build() {
    Row({ space: ROW_SPACE }) {
      Text(this.title)
        .layoutWeight(1)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isEnabled ? TEXT_PRIMARY : TEXT_SECONDARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Toggle({ type: ToggleType.Switch, isOn: this.checked })
        .enabled(this.isEnabled)
        .opacity(this.isEnabled ? 1 : 0.48)
        .selectedColor(ACCENT)
        .onChange((checked: boolean) => {
          if (this.isEnabled) {
            this.onChange(checked);
          }
        })
    }
    .width('100%')
    .backgroundColor(this.resolveBackground())
    .borderRadius(resolveRowRadius(this.rowPosition))
    .clip(true)
    .padding({
      left: ROW_HORIZONTAL_PADDING,
      right: ROW_HORIZONTAL_PADDING,
      top: ROW_VERTICAL_PADDING,
      bottom: ROW_VERTICAL_PADDING
    })
    .alignItems(VerticalAlign.Center)
    .enabled(this.isEnabled)
    .opacity(this.isEnabled ? 1 : 0.48)
    .onTouch((event: TouchEvent) => {
      this.updatePressed(event.type);
    })
  }

  private updatePressed(type: TouchType): void {
    if (!this.isEnabled) {
      this.pressed = false;
      return;
    }
    if (type === TouchType.Down) {
      this.pressed = true;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressed = false;
    }
  }

  private resolveBackground(): ResourceColor {
    return this.pressed && this.isEnabled ? PRESSED_BACKGROUND : Color.Transparent;
  }
}

@Component
struct SettingsFooterTextLite {
  @Prop text: string = '';

  build() {
    Text(this.text)
      .width('100%')
      .fontSize(13)
      .lineHeight(18)
      .fontColor(TEXT_SECONDARY)
      .padding({ left: SECTION_TITLE_LEFT_PADDING, right: SECTION_TITLE_LEFT_PADDING })
  }
}

@Component
struct ActionButtonLite {
  @Prop title: string = '';
  @Prop emphasis: ActionButtonEmphasis = 'primary';
  @State private pressed: boolean = false;
  onAction: () => void = () => {};

  build() {
    Button() {
      Text(this.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.emphasis === 'danger' ? DANGER : ACCENT)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(ACTION_BUTTON_HEIGHT)
    .type(ButtonType.Normal)
    .buttonStyle(ButtonStyleMode.NORMAL)
    .backgroundColor(this.pressed ? '#CFD8E3' : PRESSED_BACKGROUND)
    .borderRadius(ACTION_BUTTON_HEIGHT / 2)
    .padding({ left: 14, right: 14 })
    .stateEffect(false)
    .onTouch((event: TouchEvent) => {
      this.pressed = event.type === TouchType.Down;
    })
    .onClick(() => {
      this.onAction();
    })
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
