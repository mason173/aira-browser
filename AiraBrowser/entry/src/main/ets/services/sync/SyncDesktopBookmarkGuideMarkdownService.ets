import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import buffer from '@ohos.buffer';
import { BrowserWebLoadDataPayload } from '../../core/browser/BrowserWebLoadCoordinator';
import {
  MarkdownDocumentTheme,
  MarkdownDocumentViewerService
} from '../markdown/MarkdownDocumentViewerService';

const SYNC_DESKTOP_BOOKMARK_GUIDE_RAW_FILE_NAME: string = 'sync_desktop_bookmark_guide.md';
export const SYNC_DESKTOP_BOOKMARK_GUIDE_TITLE: string = 'Aira 跨设备使用指南';
const SYNC_DESKTOP_BOOKMARK_GUIDE_SOURCE_URL: string = 'https://aira.local/settings/sync-desktop-bookmark-guide.md';
const SYNC_DESKTOP_BOOKMARK_GUIDE_BASE_URL: string = 'https://aira.local/settings/';
const SYNC_DESKTOP_BOOKMARK_GUIDE_LOCAL_PACKAGE_URL: string = 'https://wwbgv.lanzoul.com/b00oe0qfcd';

interface SyncDesktopBookmarkGuideImagePlaceholder {
  placeholder: string;
  rawfileName: string;
}

export interface SyncDesktopBookmarkGuideLinkCopyResult {
  ok: boolean;
  message: string;
}

const SYNC_DESKTOP_BOOKMARK_GUIDE_IMAGES: SyncDesktopBookmarkGuideImagePlaceholder[] = [
  { placeholder: 'SYNC_DESKTOP_BOOKMARK_GUIDE_01_IMAGE', rawfileName: 'sync_desktop_bookmark_guide_01.png' },
  { placeholder: 'SYNC_DESKTOP_BOOKMARK_GUIDE_02_IMAGE', rawfileName: 'sync_desktop_bookmark_guide_02.png' },
  { placeholder: 'SYNC_DESKTOP_BOOKMARK_GUIDE_03_IMAGE', rawfileName: 'sync_desktop_bookmark_guide_03.png' },
  { placeholder: 'SYNC_DESKTOP_BOOKMARK_GUIDE_04_IMAGE', rawfileName: 'sync_desktop_bookmark_guide_04.png' },
  { placeholder: 'SYNC_DESKTOP_BOOKMARK_GUIDE_05_IMAGE', rawfileName: 'sync_desktop_bookmark_guide_05.png' }
];

export class SyncDesktopBookmarkGuideMarkdownService {
  private markdownViewerService: MarkdownDocumentViewerService = new MarkdownDocumentViewerService();

  async buildPayload(context: common.Context, theme?: MarkdownDocumentTheme): Promise<BrowserWebLoadDataPayload> {
    const markdown = this.applyImagePlaceholders(this.readMarkdown(context));
    return this.markdownViewerService.buildPayloadFromMarkdown({
      title: SYNC_DESKTOP_BOOKMARK_GUIDE_TITLE,
      sourceUri: SYNC_DESKTOP_BOOKMARK_GUIDE_SOURCE_URL,
      markdown: markdown,
      baseUrl: SYNC_DESKTOP_BOOKMARK_GUIDE_BASE_URL,
      historyUrl: SYNC_DESKTOP_BOOKMARK_GUIDE_SOURCE_URL,
      theme: theme
    });
  }

  shouldCopyGuideLink(url: string): boolean {
    const normalized = url.trim().toLowerCase();
    return normalized.startsWith('https://chromewebstore.google.com/') ||
      normalized.startsWith('https://microsoftedge.microsoft.com/addons/') ||
      normalized.startsWith('https://addons.mozilla.org/') ||
      normalized === SYNC_DESKTOP_BOOKMARK_GUIDE_LOCAL_PACKAGE_URL;
  }

  async copyGuideLink(url: string): Promise<SyncDesktopBookmarkGuideLinkCopyResult> {
    const normalizedUrl = url.trim();
    if (!this.shouldCopyGuideLink(normalizedUrl)) {
      return {
        ok: false,
        message: '插件链接暂未配置。'
      };
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, normalizedUrl);
      await pasteboard.getSystemPasteboard().setData(data);
      return {
        ok: true,
        message: '链接已复制，请在电脑中打开。'
      };
    } catch (_error) {
      return {
        ok: false,
        message: '复制失败，请稍后重试。'
      };
    }
  }

  private readMarkdown(context: common.Context): string {
    try {
      const rawFile = context.resourceManager.getRawFileContentSync(SYNC_DESKTOP_BOOKMARK_GUIDE_RAW_FILE_NAME);
      return buffer.from(rawFile.buffer).toString('utf8');
    } catch (error) {
      return [
        `# ${SYNC_DESKTOP_BOOKMARK_GUIDE_TITLE}`,
        '',
        `同步指南加载失败：${this.stringifyError(error)}`
      ].join('\n');
    }
  }

  private applyImagePlaceholders(markdown: string): string {
    let hydratedMarkdown = markdown;
    for (let index = 0; index < SYNC_DESKTOP_BOOKMARK_GUIDE_IMAGES.length; index += 1) {
      const image = SYNC_DESKTOP_BOOKMARK_GUIDE_IMAGES[index];
      const resourceUrl = `resource://rawfile/${image.rawfileName}`;
      hydratedMarkdown = hydratedMarkdown.replace(new RegExp(`\\{\\{${image.placeholder}\\}\\}`, 'g'), resourceUrl);
    }
    return hydratedMarkdown;
  }

  private stringifyError(error: Object | undefined): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return JSON.stringify(error);
  }
}
