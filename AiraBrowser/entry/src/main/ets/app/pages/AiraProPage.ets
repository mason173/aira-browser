import { AiraProScreen } from '../components/membership/AiraProScreen';
import { BrowserWindowRuntime } from '../runtime/BrowserWindowRuntime';

@Entry
@Component
struct AiraProPage {
  build() {
    Column() {
      AiraProScreen({
        presentationMode: 'page',
        pageLayoutMode: BrowserWindowRuntime.resolveActiveShellPresentationSurface() === 'large_screen' ?
          'large_screen' : 'phone'
      })
    }
    .width('100%')
    .height('100%')
  }
}
