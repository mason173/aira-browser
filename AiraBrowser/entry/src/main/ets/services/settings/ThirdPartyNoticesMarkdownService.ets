import { common } from '@kit.AbilityKit';
import buffer from '@ohos.buffer';
import { BrowserWebLoadDataPayload } from '../../core/browser/BrowserWebLoadCoordinator';
import {
  MarkdownDocumentTheme,
  MarkdownDocumentViewerService
} from '../markdown/MarkdownDocumentViewerService';

const THIRD_PARTY_NOTICES_RAW_FILE_NAME: string = 'third-party-notices.md';
const THIRD_PARTY_NOTICES_TITLE: string = '第三方开源许可';
const THIRD_PARTY_NOTICES_SOURCE_URL: string = 'https://aira.local/settings/third-party-notices.md';
const THIRD_PARTY_NOTICES_BASE_URL: string = 'https://aira.local/settings/';

export class ThirdPartyNoticesMarkdownService {
  private markdownViewerService: MarkdownDocumentViewerService = new MarkdownDocumentViewerService();

  buildPayload(context: common.Context, theme?: MarkdownDocumentTheme): BrowserWebLoadDataPayload {
    return this.markdownViewerService.buildPayloadFromMarkdown({
      title: THIRD_PARTY_NOTICES_TITLE,
      sourceUri: THIRD_PARTY_NOTICES_SOURCE_URL,
      markdown: this.readMarkdown(context),
      baseUrl: THIRD_PARTY_NOTICES_BASE_URL,
      historyUrl: THIRD_PARTY_NOTICES_SOURCE_URL,
      theme: theme
    });
  }

  private readMarkdown(context: common.Context): string {
    try {
      const rawFile = context.resourceManager.getRawFileContentSync(THIRD_PARTY_NOTICES_RAW_FILE_NAME);
      return buffer.from(rawFile.buffer).toString('utf8');
    } catch (_error) {
      return '# 第三方开源许可\n\n第三方许可声明暂时无法加载。';
    }
  }
}
