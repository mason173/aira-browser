import router from '@ohos.router';
import { NovelBookshelfScreen } from '../components/novel/NovelBookshelfScreen';
import { NovelBookshelfBook } from '../../features/novel/NovelLibraryModels';
import { BrowserWindowRuntime } from '../runtime/BrowserWindowRuntime';

interface NovelBookshelfPageParams {
  dataScope?: string;
  privacyMode?: string;
}

@Entry({ useSharedStorage: true })
@Component
struct NovelBookshelfPage {
  @State private dataScope: string = '';
  @State private privacyMode: string = '';

  aboutToAppear(): void {
    this.refreshParams();
  }

  onPageShow(): void {
    this.refreshParams();
  }

  build() {
    Column() {
      NovelBookshelfScreen({
        persistentAccessAllowed: this.isPersistentAccessAllowed(),
        layoutMode: BrowserWindowRuntime.resolveActiveShellPresentationSurface() === 'large_screen' ?
          'large_screen' : 'phone',
        onOpenBook: (book: NovelBookshelfBook): void => {
          this.openBook(book);
        },
        onOpenOriginalPage: (book: NovelBookshelfBook): void => {
          this.openOriginalPage(book);
        }
      })
    }
    .width('100%')
    .height('100%')
  }

  private openBook(book: NovelBookshelfBook): void {
    if (!this.isPersistentAccessAllowed()) {
      return;
    }
    void BrowserWindowRuntime.openNovelBookshelfBook(book);
  }

  private openOriginalPage(book: NovelBookshelfBook): void {
    if (!this.isPersistentAccessAllowed()) {
      return;
    }
    BrowserWindowRuntime.openNovelBookshelfOriginalPage(book);
  }

  private refreshParams(): void {
    const params = router.getParams() as NovelBookshelfPageParams | undefined;
    this.dataScope = params?.dataScope ?? '';
    this.privacyMode = params?.privacyMode ?? '';
  }

  private isPersistentAccessAllowed(): boolean {
    return this.privacyMode === 'regular' && this.dataScope === 'profile_persistent';
  }
}
