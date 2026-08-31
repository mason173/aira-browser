import {
  BrowserPrivacyProtectionOverviewCoordinator
} from '../../../core/settings/BrowserPrivacyProtectionOverviewCoordinator';
import {
  BrowserPrivacyProtectionDayState,
  BrowserPrivacyProtectionOverviewState
} from '../../../core/settings/BrowserPrivacyProtectionOverviewViewModel';
import {
  sharedAdBlockRepository,
  sharedPreferencesRepository
} from '../../bootstrap/BrowserAppRuntime';
import { SettingsGroupCard } from './SettingsLayout';
import { SettingsDesktopGroup } from './SettingsDesktopRows';

@Component
export struct BrowserPrivacyProtectionOverview {
  private readonly coordinator: BrowserPrivacyProtectionOverviewCoordinator =
    new BrowserPrivacyProtectionOverviewCoordinator(sharedAdBlockRepository, sharedPreferencesRepository);
  @Prop surfaceBackground: ResourceColor = '';
  @Prop accentColor: ResourceColor = '';
  @Prop pressedBackground: ResourceColor = '';
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop desktopPresentation: boolean = false;
  @Prop @Watch('handleRefreshRevision') refreshRevision: number = 0;
  @State private state: BrowserPrivacyProtectionOverviewState = this.coordinator.buildState();

  aboutToAppear(): void {
    this.refresh();
  }

  build() {
    Column() {
      if (this.desktopPresentation) {
        SettingsDesktopGroup({ surfaceColor: this.surfaceBackground }) {
          this.buildOverviewContent()
        }
      } else {
        SettingsGroupCard({ surfaceColor: this.surfaceBackground }) {
          this.buildOverviewContent()
        }
      }
    }
    .width('100%')
  }

  @Builder
  private buildOverviewContent() {
    Column({ space: 14 }) {
          Column({ space: 4 }) {
            Text('近 7 天网页保护')
              .width('100%')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.secondaryTextColor)

            Row({ space: 8 }) {
              Text(this.state.lastSevenDaysTotalLabel)
                .fontSize(this.desktopPresentation ? 28 : 32)
                .fontWeight(this.desktopPresentation ? FontWeight.Medium : FontWeight.Bold)
                .fontColor(this.primaryTextColor)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Text('次保护')
                .fontSize(13)
                .fontColor(this.secondaryTextColor)
                .maxLines(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          this.buildChart()
          this.buildSelectedDayDetail()
          this.buildProtectionStatus()
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 14, bottom: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildChart() {
    Row({ space: this.desktopPresentation ? 0 : 4 }) {
      ForEach(this.state.days, (day: BrowserPrivacyProtectionDayState, index: number) => {
        Row() {
          this.buildChartDay(day, index)
        }
        .layoutWeight(1)
        .height(116)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }, (day: BrowserPrivacyProtectionDayState): string => `${day.dayStartedAt}`)
    }
    .width('100%')
  }

  @Builder
  private buildChartDay(day: BrowserPrivacyProtectionDayState, index: number) {
    Button() {
      Column({ space: 7 }) {
        Column() {
          Column()
            .width(12)
            .height(day.barHeight)
            .backgroundColor(this.accentColor)
            .borderRadius({ topLeft: 6, topRight: 6, bottomLeft: 2, bottomRight: 2 })
            .opacity(index === this.state.selectedDayIndex ? 1 : 0.42)
        }
        .width('100%')
        .height(88)
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.Center)

        Text(day.shortLabel)
          .fontSize(11)
          .fontWeight(index === this.state.selectedDayIndex ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(index === this.state.selectedDayIndex ? this.primaryTextColor : this.secondaryTextColor)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width(this.desktopPresentation ? 64 : '100%')
    .height(116)
    .padding(0)
    .type(ButtonType.Normal)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .stateEffect(true)
    .backgroundColor(index === this.state.selectedDayIndex ? this.pressedBackground :
      $r('sys.color.ohos_id_color_background_transparent'))
    .borderRadius(10)
    .accessibilityText(`${day.detailLabel} ${day.totalActionCount} 次保护`)
    .onClick((): void => {
      this.selectDay(index);
    })
  }

  @Builder
  private buildSelectedDayDetail() {
    Column({ space: 5 }) {
      Text(`${this.state.selectedDay.detailLabel} · ${this.state.selectedDay.totalActionCount} 次`)
        .width('100%')
        .fontSize(this.desktopPresentation ? 13 : 14)
        .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
        .fontColor(this.primaryTextColor)

      Text(this.state.detailBreakdownLabel)
        .width('100%')
        .fontSize(12)
        .lineHeight(18)
        .fontColor(this.secondaryTextColor)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 10, bottom: 10 })
    .backgroundColor(this.pressedBackground)
    .borderRadius(this.desktopPresentation ? 8 : 12)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildProtectionStatus() {
    Row({ space: 8 }) {
      Text(this.state.filterStatusLabel)
        .layoutWeight(1)
        .fontSize(12)
        .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
        .fontColor(this.state.filterEnabled ? this.accentColor : this.secondaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 10, right: 10, top: 7, bottom: 7 })
        .backgroundColor(this.pressedBackground)
        .borderRadius(this.desktopPresentation ? 8 : 12)

      Text(`防跟踪：${this.state.trackingModeLabel}`)
        .layoutWeight(1)
        .fontSize(12)
        .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
        .fontColor(this.secondaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 10, right: 10, top: 7, bottom: 7 })
        .backgroundColor(this.pressedBackground)
        .borderRadius(this.desktopPresentation ? 8 : 12)
    }
    .width('100%')
  }

  private selectDay(index: number): void {
    this.state = this.coordinator.buildState(index);
  }

  private handleRefreshRevision(): void {
    this.refresh();
  }

  private refresh(): void {
    const selectedDayIndex: number = this.state.selectedDayIndex;
    this.state = this.coordinator.buildState(selectedDayIndex);
    void this.coordinator.refreshState(selectedDayIndex)
      .then((state: BrowserPrivacyProtectionOverviewState): void => {
        this.state = state;
      })
      .catch((_error: Error): void => {});
  }
}
