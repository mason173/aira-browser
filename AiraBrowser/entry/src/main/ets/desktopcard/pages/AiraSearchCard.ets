import {
  hasBuiltInDesktopCardSearchEngineIcon,
  resolveDesktopCardSearchEngineIcon
} from '../components/DesktopCardSearchEngineIcon';

let airaSearchCardStorage = new LocalStorage();

@Entry(airaSearchCardStorage)
@Component
struct AiraSearchCard {
  @LocalStorageProp('searchEngineId') private searchEngineId: string = '';
  readonly actionType: string = 'router';
  readonly targetAbilityName: string = 'EntryAbility';
  readonly fullSize: string = '100%';

  build() {
    FormLink({
      action: this.actionType,
      moduleName: 'entry',
      abilityName: this.targetAbilityName,
      params: {
        'aira.appShortcut': 'search'
      }
    }) {
      Row() {
        if (hasBuiltInDesktopCardSearchEngineIcon(this.searchEngineId)) {
          Image(resolveDesktopCardSearchEngineIcon(this.searchEngineId))
            .width(28)
            .height(28)
            .objectFit(ImageFit.Contain)
        } else {
          Image(resolveDesktopCardSearchEngineIcon(this.searchEngineId))
            .width(28)
            .height(28)
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
      .height(this.fullSize)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .backgroundColor($r('app.color.desktop_widget_transparent_background'))
      .border({ width: 1.5, color: $r('app.color.desktop_widget_outline_foreground') })
      .borderRadius(24)
      .clip(true)
    }
  }
}
