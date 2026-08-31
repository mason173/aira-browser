import router from '@ohos.router';
import { OfflinePageViewerScreen } from '../components/offline/OfflinePageViewerScreen';
import {
  OfflinePageViewerBackAction,
  OfflinePageViewerBackState,
  OfflinePageViewerViewModel
} from '../../core/offline/OfflinePageViewerViewModel';

@Entry
@Component
struct OfflinePageViewerPage {
  private viewerViewModel: OfflinePageViewerViewModel = new OfflinePageViewerViewModel();
  @State pageId: string = '';
  @State dataScope: string = 'profile_persistent';
  @State privacyMode: string = 'regular';
  @State backState: OfflinePageViewerBackState = this.viewerViewModel.createInitialBackState();
  @State backRequestAction: OfflinePageViewerBackAction = 'route_back';
  @State backRequestVersion: number = 0;

  aboutToAppear(): void {
    try {
      const params = router.getParams() as Record<string, string | undefined> | undefined;
      this.pageId = params?.pageId ?? '';
      this.dataScope = params?.dataScope ?? 'profile_persistent';
      this.privacyMode = params?.privacyMode ?? 'regular';
    } catch (_error) {
      this.pageId = '';
      this.dataScope = 'profile_persistent';
      this.privacyMode = 'regular';
    }
  }

  build() {
    Column() {
      OfflinePageViewerScreen({
        pageId: this.pageId,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        backRequestAction: this.backRequestAction,
        backRequestVersion: this.backRequestVersion,
        onBackStateChange: (state: OfflinePageViewerBackState) => {
          this.backState = state;
        }
      })
    }
    .width('100%')
    .height('100%')
  }

  onBackPress(): boolean {
    const action = this.viewerViewModel.resolveBackAction(this.backState);
    if (action === 'route_back') {
      return false;
    }
    this.backRequestAction = action;
    this.backRequestVersion += 1;
    return true;
  }
}
