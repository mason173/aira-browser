import { WebLoadErrorPresentation } from '../../../services/web/WebLoadErrorPresentationService';
import { BrowserWebLoadErrorSurfaceAction } from '../../../core/browser/BrowserWebPageLifecycleApplicationCoordinator';
import { BrowserWebErrorSurface } from './BrowserWebErrorSurface';

@Component
export struct BrowserWebErrorLayer {
  @Prop visible: boolean = false;
  @Prop presentation: WebLoadErrorPresentation = {
    title: '',
    summary: '',
    host: '',
    primaryActionLabel: '重新加载',
    secondaryActionLabel: '打开首页',
    tertiaryActionLabel: '复制详情',
    detailLabel: '错误详情',
    detailText: '',
    hints: []
  };
  @Prop bottomChromeInsetVp: number = 0;
  onAction: (action: BrowserWebLoadErrorSurfaceAction) => void =
    (_action: BrowserWebLoadErrorSurfaceAction): void => {};

  build() {
    if (this.visible) {
      BrowserWebErrorSurface({
        presentation: this.presentation,
        bottomChromeInsetVp: this.bottomChromeInsetVp,
        onReload: () => {
          this.onAction('reload');
        },
        onSecondaryAction: () => {
          this.onAction('open_network_settings');
        }
      })
        .width('100%')
        .height('100%')
        .zIndex(1)
    }
  }
}
