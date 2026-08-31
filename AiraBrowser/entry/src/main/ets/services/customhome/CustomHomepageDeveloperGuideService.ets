import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import buffer from '@ohos.buffer';
import { BrowserWebLoadDataPayload } from '../../core/browser/BrowserWebLoadCoordinator';
import {
  MarkdownDocumentTheme,
  MarkdownDocumentViewerService
} from '../markdown/MarkdownDocumentViewerService';

export interface CustomHomepageGuideTheme {
  pageBackground: string;
  surfaceBackground: string;
  primaryText: string;
  secondaryText: string;
  divider: string;
  accent: string;
}

export interface CustomHomepageGuideExportResult {
  ok: boolean;
  message: string;
}

const CUSTOM_HOMEPAGE_GUIDE_RAW_FILE_NAME: string = 'custom_homepage_developer_guide.md';
const CUSTOM_HOMEPAGE_GUIDE_FILE_NAME: string = 'Aira-Custom-Homepage-Developer-Guide.md';
const CUSTOM_HOMEPAGE_GUIDE_TITLE: string = 'Aira 自定义主页开发指南';
const CUSTOM_HOMEPAGE_GUIDE_SOURCE_URL: string = 'https://aira.local/settings/custom-homepage-developer-guide.md';
const CUSTOM_HOMEPAGE_GUIDE_BASE_URL: string = 'https://aira.local/settings/';
const CUSTOM_HOMEPAGE_GUIDE_SHARE_CACHE_DIR_NAME: string = 'custom-homepage-guide-share';

export class CustomHomepageDeveloperGuideService {
  private markdownViewerService: MarkdownDocumentViewerService = new MarkdownDocumentViewerService();

  buildPayload(context: common.Context, theme?: CustomHomepageGuideTheme): BrowserWebLoadDataPayload {
    return this.markdownViewerService.buildPayloadFromMarkdown({
      title: CUSTOM_HOMEPAGE_GUIDE_TITLE,
      sourceUri: CUSTOM_HOMEPAGE_GUIDE_SOURCE_URL,
      markdown: this.readMarkdown(context),
      baseUrl: CUSTOM_HOMEPAGE_GUIDE_BASE_URL,
      historyUrl: CUSTOM_HOMEPAGE_GUIDE_SOURCE_URL,
      theme: this.toMarkdownTheme(theme)
    });
  }

  shouldOpenGuideLinkInBrowser(url: string): boolean {
    const normalizedUrl = url.trim().toLowerCase();
    if (normalizedUrl.length === 0 || normalizedUrl.startsWith('https://aira.local/')) {
      return false;
    }
    return normalizedUrl.startsWith('http://') || normalizedUrl.startsWith('https://');
  }

  async shareMarkdown(context: common.UIAbilityContext): Promise<CustomHomepageGuideExportResult> {
    try {
      const uri = await this.writeMarkdownShareFile(context);
      await this.showSharePanel(context, uri);
      return {
        ok: true,
        message: '已打开分享面板'
      };
    } catch (error) {
      return {
        ok: false,
        message: `分享开发文档失败：${this.stringifyError(error)}`
      };
    }
  }

  private readMarkdown(context: common.Context): string {
    try {
      const rawFile = context.resourceManager.getRawFileContentSync(CUSTOM_HOMEPAGE_GUIDE_RAW_FILE_NAME);
      return buffer.from(rawFile.buffer).toString('utf8');
    } catch (error) {
      return [
        '# Aira 自定义主页开发指南',
        '',
        `开发文档加载失败：${this.stringifyError(error)}`
      ].join('\n');
    }
  }

  private toMarkdownTheme(theme: CustomHomepageGuideTheme | undefined): MarkdownDocumentTheme | undefined {
    if (theme === undefined) {
      return undefined;
    }
    return {
      pageBackground: theme.pageBackground,
      surfaceBackground: theme.surfaceBackground,
      primaryText: theme.primaryText,
      secondaryText: theme.secondaryText,
      divider: theme.divider,
      accent: theme.accent
    };
  }

  private async writeMarkdownShareFile(context: common.UIAbilityContext): Promise<string> {
    const dir = this.getShareCacheDir(context);
    await this.ensureDirectory(dir);
    const path = `${dir}/${CUSTOM_HOMEPAGE_GUIDE_FILE_NAME}`;
    await this.writeTextToUri(path, this.readMarkdown(context));
    return new fileUri.FileUri(path).toString();
  }

  private async showSharePanel(context: common.UIAbilityContext, uri: string): Promise<void> {
    const record: systemShare.SharedRecord = {
      utd: uniformTypeDescriptor.UniformDataType.FILE_URI,
      uri: uri,
      title: CUSTOM_HOMEPAGE_GUIDE_TITLE,
      label: CUSTOM_HOMEPAGE_GUIDE_FILE_NAME,
      description: CUSTOM_HOMEPAGE_GUIDE_TITLE
    };
    const data = new systemShare.SharedData(record);
    const controller = new systemShare.ShareController(data);
    await controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT
    });
  }

  private async writeTextToUri(uri: string, payload: string): Promise<void> {
    const file = await fileIo.open(uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, payload);
    } finally {
      await fileIo.close(file);
    }
  }

  private async ensureDirectory(path: string): Promise<void> {
    try {
      if (await fileIo.access(path)) {
        return;
      }
    } catch (_error) {
    }
    await fileIo.mkdir(path, true);
  }

  private getShareCacheDir(context: common.Context): string {
    return `${context.cacheDir}/${CUSTOM_HOMEPAGE_GUIDE_SHARE_CACHE_DIR_NAME}`;
  }

  private stringifyError(error: Object | undefined): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return JSON.stringify(error);
  }
}
