import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import {
  SettingsLegalDocumentSectionState,
  SettingsLegalDocumentState,
  SettingsLegalDocumentViewModel
} from '../../core/settings/SettingsLegalDocumentViewModel';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import { SettingsScrollBody } from '../components/settings/SettingsLayout';

@Entry
@Component
struct SettingsAutoRenewalNoticePage {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  private viewModel: SettingsLegalDocumentViewModel = new SettingsLegalDocumentViewModel();
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  @State private state: SettingsLegalDocumentState = this.viewModel.buildAutoRenewalNoticeState();

  aboutToAppear(): void {
    this.state = this.viewModel.buildAutoRenewalNoticeState();
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: this.state.title,
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        contentKind: 'readable',
        onBack: () => {
          this.navigationCoordinator.back();
        }
      }) {
        SettingsScrollBody({
          contentSpace: 14,
          topPadding: 4,
          bottomPadding: 24
        }) {
          this.buildLeadCard()
          ForEach(this.state.sections, (section: SettingsLegalDocumentSectionState) => {
            this.buildSectionCard(section)
          }, (section: SettingsLegalDocumentSectionState) => section.id)
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildLeadCard() {
    Column({ space: 8 }) {
      Text(this.state.updatedAt)
        .width('100%')
        .fontSize(12)
        .lineHeight(17)
        .fontColor(this.storedSecondaryTextColor)

      Text(this.state.lead)
        .width('100%')
        .fontSize(14)
        .lineHeight(22)
        .fontColor(this.storedPrimaryTextColor)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(22)
  }

  @Builder
  private buildSectionCard(section: SettingsLegalDocumentSectionState) {
    Column({ space: 12 }) {
      Text(section.title)
        .width('100%')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)

      Column({ space: 8 }) {
        ForEach(section.paragraphs, (paragraph: string) => {
          Text(paragraph)
            .width('100%')
            .fontSize(14)
            .lineHeight(22)
            .fontColor(this.storedPrimaryTextColor)
        }, (paragraph: string) => paragraph)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (section.items.length > 0) {
        Divider()
          .strokeWidth(1)
          .color(this.storedDividerColor)
        Column({ space: 8 }) {
          ForEach(section.items, (item: string) => {
            this.buildDocumentItem(item)
          }, (item: string) => item)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(22)
  }

  @Builder
  private buildDocumentItem(item: string) {
    Row({ space: 9 }) {
      Circle()
        .width(6)
        .height(6)
        .fill(this.storedAccentColor)
        .margin({ top: 8 })

      Text(item)
        .layoutWeight(1)
        .fontSize(14)
        .lineHeight(21)
        .fontColor(this.storedSecondaryTextColor)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}
