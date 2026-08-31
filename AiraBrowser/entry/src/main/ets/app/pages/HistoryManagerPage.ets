import { HistoryManagerScreen } from '../components/history/HistoryManagerScreen';
import { HistoryManagerScreenController } from '../../features/history/HistoryManagerScreenController';
import { HistoryFeature } from '../../features/history/HistoryFeature';
import {
  sharedHistoryRepository,
  sharedPreferencesRepository,
  sharedRecentlyClosedTabRepository
} from '../bootstrap/BrowserAppRuntime';

@Entry({ useSharedStorage: true })
@Component
struct HistoryManagerPage {
  private historyFeature: HistoryFeature =
    new HistoryFeature(sharedHistoryRepository, sharedPreferencesRepository, sharedRecentlyClosedTabRepository);
  private controller: HistoryManagerScreenController = new HistoryManagerScreenController(this.historyFeature);

  onBackPress(): boolean {
    return this.controller.handleBackPress();
  }

  build() {
    Column() {
      HistoryManagerScreen({
        controller: this.controller,
        historyFeature: this.historyFeature
      })
    }
    .width('100%')
    .height('100%')
  }
}
