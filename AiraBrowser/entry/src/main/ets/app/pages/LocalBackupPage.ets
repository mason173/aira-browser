import { LocalBackupScreen } from '../components/backup/LocalBackupScreen';

@Entry
@Component
struct LocalBackupPage {
  build() {
    Column() {
      LocalBackupScreen()
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
