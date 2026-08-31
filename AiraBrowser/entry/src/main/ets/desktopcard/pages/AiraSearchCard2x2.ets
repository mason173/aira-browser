import {
  hasBuiltInDesktopCardSearchEngineIcon,
  resolveDesktopCardSearchEngineIcon
} from '../components/DesktopCardSearchEngineIcon';

let airaSearchCard2x2Storage = new LocalStorage();

@Entry(airaSearchCard2x2Storage)
@Component
struct AiraSearchCard2x2 {
  @LocalStorageProp('searchEngineId') private searchEngineId: string = '';
  private readonly fullSize: string = '100%';
  private readonly searchAction: string = 'router';

  build() {
    FormLink({
      action: this.searchAction,
      moduleName: 'entry',
      abilityName: 'EntryAbility',
      params: {
        'aira.appShortcut': 'search'
      }
    }) {
      Column() {
        Text($r('app.string.aira_search_card_placeholder'))
          .width(this.fullSize)
          .fontSize(15)
          .fontWeight(FontWeight.Normal)
          .fontColor($r('app.color.desktop_widget_outline_foreground'))
          .textAlign(TextAlign.Center)
          .maxLines(1)

        Row() {
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
          Image($r('app.media.app_widget_navigation_arrow'))
            .width(20)
            .height(20)
            .objectFit(ImageFit.Contain)
            .rotate({ angle: 270 })
        }
        .width(this.fullSize)
        .height(46)
        .padding({ left: 10, right: 10 })
        .justifyContent(FlexAlign.SpaceBetween)
        .backgroundColor($r('app.color.desktop_widget_transparent_background'))
        .border({ width: 1.5, color: $r('app.color.desktop_widget_outline_foreground') })
        .borderRadius(18)
      }
      .width(this.fullSize)
      .height(this.fullSize)
      .padding({ left: 16, right: 16, top: 18, bottom: 18 })
      .justifyContent(FlexAlign.SpaceBetween)
      .backgroundColor($r('app.color.desktop_widget_transparent_background'))
      .border({ width: 1.5, color: $r('app.color.desktop_widget_outline_foreground') })
      .borderRadius(24)
      .clip(true)
    }
  }
}
