import { SyncExperienceHost } from '../components/sync/SyncExperienceHost';

@Entry
@Component
struct SyncSettingsPage {
  build() {
    Column() {
      SyncExperienceHost()
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
