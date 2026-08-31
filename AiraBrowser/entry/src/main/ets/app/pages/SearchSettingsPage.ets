import { SearchSettingsHost } from '../components/search/SearchSettingsHost';
import { readSettingsTargetRouteState } from '../../common/utils/RouteParamUtils';

@Entry
@Component
struct SearchSettingsPage {
  @State private settingsRevealTargetId: string = '';

  aboutToAppear(): void {
    this.settingsRevealTargetId = readSettingsTargetRouteState().settingsRevealTargetId;
  }

  build() {
    Column() {
      SearchSettingsHost({
        revealTargetId: this.settingsRevealTargetId,
        revealRevision: this.settingsRevealTargetId.length > 0 ? 1 : 0
      })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
