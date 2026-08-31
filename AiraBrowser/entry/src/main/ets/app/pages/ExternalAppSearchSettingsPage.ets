import { ExternalAppSearchSettingsHost } from '../components/search/ExternalAppSearchSettingsHost';

@Entry
@Component
struct ExternalAppSearchSettingsPage {
  build() {
    Column() {
      ExternalAppSearchSettingsHost()
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
