import { SyncAdditionalBackupHost } from '../components/sync/SyncAdditionalBackupHost';

@Entry
@Component
struct SyncAdditionalBackupPage {
  build() {
    Column() {
      SyncAdditionalBackupHost({ mode: 'overview' })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
