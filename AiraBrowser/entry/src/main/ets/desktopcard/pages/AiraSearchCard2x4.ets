import {
  hasBuiltInDesktopCardSearchEngineIcon,
  resolveDesktopCardSearchEngineIcon
} from '../components/DesktopCardSearchEngineIcon';

let airaSearchCard2x4Storage = new LocalStorage();

@Entry(airaSearchCard2x4Storage)
@Component
struct AiraSearchCard2x4 {
  @LocalStorageProp('searchEngineId') private searchEngineId: string = '';
  private readonly fullSize: string = '100%';
  private readonly searchAction: string = 'router';

  build() {
    Column() {
      FormLink({
        action: this.searchAction,
        moduleName: 'entry',
        abilityName: 'EntryAbility',
        params: {
          'aira.appShortcut': 'search'
        }
      }) {
        Row({ space: 12 }) {
          if (hasBuiltInDesktopCardSearchEngineIcon(this.searchEngineId)) {
            Image(resolveDesktopCardSearchEngineIcon(this.searchEngineId))
              .width(24)
              .height(24)
              .objectFit(ImageFit.Contain)
          } else {
            Image(resolveDesktopCardSearchEngineIcon(this.searchEngineId))
              .width(24)
              .height(24)
              .objectFit(ImageFit.Contain)
              .fillColor($r('app.color.desktop_widget_outline_foreground'))
          }
          Text($r('app.string.aira_search_card_placeholder'))
            .layoutWeight(1)
            .fontSize(15)
            .fontColor($r('app.color.desktop_widget_outline_foreground'))
            .maxLines(1)
        }
        .width(this.fullSize)
        .height(52)
        .padding({ left: 16, right: 16 })
        .backgroundColor($r('app.color.desktop_widget_transparent_background'))
        .border({ width: 1.5, color: $r('app.color.desktop_widget_outline_foreground') })
        .borderRadius(18)
      }
      .width(this.fullSize)

      Row({ space: 6 }) {
        FormLink({
          action: this.searchAction,
          moduleName: 'entry',
          abilityName: 'EntryAbility',
          params: { 'aira.appShortcut': 'bookmarks' }
        }) {
          Column({ space: 7 }) {
            Image($r('app.media.app_widget_shortcut_bookmarks'))
              .width(27)
              .height(27)
              .objectFit(ImageFit.Contain)
              .fillColor($r('app.color.desktop_widget_outline_foreground'))
            Text($r('app.string.app_shortcut_bookmarks'))
              .fontSize(12)
              .fontColor($r('app.color.desktop_widget_outline_foreground'))
              .maxLines(1)
          }
          .width(this.fullSize)
          .alignItems(HorizontalAlign.Center)
        }
        .layoutWeight(1)

        FormLink({
          action: this.searchAction,
          moduleName: 'entry',
          abilityName: 'EntryAbility',
          params: { 'aira.appShortcut': 'history' }
        }) {
          Column({ space: 7 }) {
            Image($r('app.media.app_widget_shortcut_history'))
              .width(27)
              .height(27)
              .objectFit(ImageFit.Contain)
              .fillColor($r('app.color.desktop_widget_outline_foreground'))
            Text($r('app.string.app_shortcut_history'))
              .fontSize(12)
              .fontColor($r('app.color.desktop_widget_outline_foreground'))
              .maxLines(1)
          }
          .width(this.fullSize)
          .alignItems(HorizontalAlign.Center)
        }
        .layoutWeight(1)

        FormLink({
          action: this.searchAction,
          moduleName: 'entry',
          abilityName: 'EntryAbility',
          params: { 'aira.appShortcut': 'downloads' }
        }) {
          Column({ space: 7 }) {
            Image($r('app.media.app_widget_shortcut_downloads'))
              .width(27)
              .height(27)
              .objectFit(ImageFit.Contain)
              .fillColor($r('app.color.desktop_widget_outline_foreground'))
            Text($r('app.string.app_shortcut_downloads'))
              .fontSize(12)
              .fontColor($r('app.color.desktop_widget_outline_foreground'))
              .maxLines(1)
          }
          .width(this.fullSize)
          .alignItems(HorizontalAlign.Center)
        }
        .layoutWeight(1)

        FormLink({
          action: this.searchAction,
          moduleName: 'entry',
          abilityName: 'EntryAbility',
          params: { 'aira.appShortcut': 'settings' }
        }) {
          Column({ space: 7 }) {
            Image($r('app.media.app_widget_shortcut_settings'))
              .width(27)
              .height(27)
              .objectFit(ImageFit.Contain)
              .fillColor($r('app.color.desktop_widget_outline_foreground'))
            Text($r('app.string.app_shortcut_settings'))
              .fontSize(12)
              .fontColor($r('app.color.desktop_widget_outline_foreground'))
              .maxLines(1)
          }
          .width(this.fullSize)
          .alignItems(HorizontalAlign.Center)
        }
        .layoutWeight(1)
      }
      .width(this.fullSize)
    }
    .width(this.fullSize)
    .height(this.fullSize)
    .padding({ left: 16, right: 16, top: 24, bottom: 24 })
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor($r('app.color.desktop_widget_transparent_background'))
    .border({ width: 1.5, color: $r('app.color.desktop_widget_outline_foreground') })
    .borderRadius(24)
    .clip(true)
  }
}
