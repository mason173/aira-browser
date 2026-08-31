import { webview } from '@kit.ArkWeb';
import { BrowserWebLoadDataPayload } from '../../../core/browser/BrowserWebLoadCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  MarkdownDocumentTheme,
  MarkdownDocumentViewerService,
  MARKDOWN_CODE_BLOCK_BACKGROUND_COLOR
} from '../../../services/markdown/MarkdownDocumentViewerService';

const ELEMENT_INSPECTION_CODE_SCROLL_KEY_STORAGE_KEY: string =
  'aira.elementInspection.codePreview.scrollKey';
const ELEMENT_INSPECTION_CODE_SCROLL_Y_STORAGE_KEY: string =
  'aira.elementInspection.codePreview.scrollY';

@Component
export struct ElementInspectionCodePreview {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) @Watch('reloadCode')
  private storedAccentColor: string = '';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) @Watch('reloadCode')
  private storedDividerColor: string = '';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) @Watch('reloadCode')
  private storedPrimaryTextColor: string = '';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) @Watch('reloadCode')
  private storedSecondaryTextColor: string = '';
  @Prop @Watch('reloadCode') code: string = '';
  private readonly markdownViewerService: MarkdownDocumentViewerService = new MarkdownDocumentViewerService();
  private readonly webController: webview.WebviewController = new webview.WebviewController();
  private webControllerAttached: boolean = false;
  private activeCodeKey: string = '';
  private lastLoadedPayloadKey: string = '';
  private loadSequence: number = 0;
  private pendingScrollRestoreSequence: number = -1;

  aboutToAppear(): void {
    this.activeCodeKey = this.resolveCodeKey(this.code);
    this.ensureStoredScrollState(this.activeCodeKey);
  }

  aboutToDisappear(): void {
    this.webControllerAttached = false;
    this.lastLoadedPayloadKey = '';
    this.pendingScrollRestoreSequence = -1;
  }

  build() {
    Web({
      src: '',
      controller: this.webController
    })
      .width('100%')
      .height('100%')
      .backgroundColor(MARKDOWN_CODE_BLOCK_BACKGROUND_COLOR)
      .javaScriptAccess(true)
      .domStorageAccess(false)
      .zoomAccess(false)
      .onScroll((event: OnScrollEvent) => {
        this.handleCodeScroll(event);
      })
      .onControllerAttached(() => {
        this.webControllerAttached = true;
        this.reloadCode();
      })
      .onLoadFinished(() => {
        this.handleCodeLoadFinished();
      })
  }

  private reloadCode(): void {
    const codeKey = this.resolveCodeKey(this.code);
    this.ensureStoredScrollState(codeKey);
    this.activeCodeKey = codeKey;
    if (!this.webControllerAttached) {
      return;
    }
    const payloadKey = this.resolvePayloadKey(codeKey);
    if (this.lastLoadedPayloadKey === payloadKey) {
      return;
    }
    this.loadSequence += 1;
    const loadSequence = this.loadSequence;
    const initialScrollY = this.resolveStoredScrollY(codeKey);
    this.pendingScrollRestoreSequence = initialScrollY > 0 ? loadSequence : -1;
    try {
      const payload: BrowserWebLoadDataPayload = this.markdownViewerService.buildCodeBlockPayload({
        code: this.code,
        language: 'html',
        theme: this.buildMarkdownTheme(),
        initialScrollY: initialScrollY
      });
      this.webController.loadData(
        payload.data,
        payload.mimeType,
        payload.encoding,
        payload.baseUrl,
        payload.historyUrl
      );
      this.lastLoadedPayloadKey = payloadKey;
    } catch (_error) {
      this.pendingScrollRestoreSequence = -1;
    }
  }

  private handleCodeScroll(event: OnScrollEvent): void {
    const scrollY = Math.max(0, Math.round(event.yOffset));
    if (this.pendingScrollRestoreSequence === this.loadSequence) {
      const expectedScrollY = this.resolveStoredScrollY(this.activeCodeKey);
      if (Math.abs(scrollY - expectedScrollY) > 2) {
        return;
      }
      this.pendingScrollRestoreSequence = -1;
    }
    AppStorage.setOrCreate(ELEMENT_INSPECTION_CODE_SCROLL_KEY_STORAGE_KEY, this.activeCodeKey);
    AppStorage.setOrCreate(ELEMENT_INSPECTION_CODE_SCROLL_Y_STORAGE_KEY, scrollY);
  }

  private handleCodeLoadFinished(): void {
    if (this.pendingScrollRestoreSequence === this.loadSequence) {
      this.pendingScrollRestoreSequence = -1;
    }
  }

  private ensureStoredScrollState(codeKey: string): void {
    const storedCodeKey = AppStorage.get<string>(ELEMENT_INSPECTION_CODE_SCROLL_KEY_STORAGE_KEY) ?? '';
    if (storedCodeKey !== codeKey) {
      AppStorage.setOrCreate(ELEMENT_INSPECTION_CODE_SCROLL_KEY_STORAGE_KEY, codeKey);
      AppStorage.setOrCreate(ELEMENT_INSPECTION_CODE_SCROLL_Y_STORAGE_KEY, 0);
      return;
    }
    if (AppStorage.get<number>(ELEMENT_INSPECTION_CODE_SCROLL_Y_STORAGE_KEY) === undefined) {
      AppStorage.setOrCreate(ELEMENT_INSPECTION_CODE_SCROLL_Y_STORAGE_KEY, 0);
    }
  }

  private resolveStoredScrollY(codeKey: string): number {
    const storedCodeKey = AppStorage.get<string>(ELEMENT_INSPECTION_CODE_SCROLL_KEY_STORAGE_KEY) ?? '';
    if (storedCodeKey !== codeKey) {
      return 0;
    }
    return Math.max(0, Math.round(AppStorage.get<number>(ELEMENT_INSPECTION_CODE_SCROLL_Y_STORAGE_KEY) ?? 0));
  }

  private resolveCodeKey(value: string): string {
    let hash: number = 2166136261;
    for (let index = 0; index < value.length; index += 1) {
      hash = Math.imul(hash ^ value.charCodeAt(index), 16777619);
    }
    return `${value.length}:${(hash >>> 0).toString(16)}`;
  }

  private resolvePayloadKey(codeKey: string): string {
    return [
      codeKey,
      this.storedAccentColor,
      this.storedDividerColor,
      this.storedPrimaryTextColor,
      this.storedSecondaryTextColor
    ].join('|');
  }

  private buildMarkdownTheme(): MarkdownDocumentTheme {
    return {
      pageBackground: MARKDOWN_CODE_BLOCK_BACKGROUND_COLOR,
      surfaceBackground: MARKDOWN_CODE_BLOCK_BACKGROUND_COLOR,
      primaryText: this.storedPrimaryTextColor,
      secondaryText: this.storedSecondaryTextColor,
      divider: this.storedDividerColor,
      pressedBackground: MARKDOWN_CODE_BLOCK_BACKGROUND_COLOR,
      accent: this.storedAccentColor
    };
  }
}
