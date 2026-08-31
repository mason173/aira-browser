import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';

export interface WebPageShareRequest {
  title?: string;
  url: string;
  description?: string;
}

export class WebPageShareService {
  async shareWebPage(context: common.UIAbilityContext, request: WebPageShareRequest): Promise<void> {
    const url = request.url.trim();
    if (url.length <= 0) {
      throw new Error('empty-share-url');
    }
    const title = this.resolveTitle(request.title, url);
    const data = new systemShare.SharedData({
      utd: uniformTypeDescriptor.UniformDataType.HYPERLINK,
      title: title,
      content: url,
      label: title,
      description: this.resolveDescription(request.description, url)
    });
    const controller = new systemShare.ShareController(data);
    await controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT
    });
  }

  async sharePlainText(context: common.UIAbilityContext, title: string, content: string): Promise<void> {
    const normalizedContent = content.trim();
    if (normalizedContent.length <= 0) {
      throw new Error('empty-share-text');
    }
    const normalizedTitle = title.trim().length > 0 ? title.trim() : '分享文本';
    const data = new systemShare.SharedData({
      utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
      title: normalizedTitle,
      content: normalizedContent,
      label: normalizedTitle,
      description: normalizedContent
    });
    const controller = new systemShare.ShareController(data);
    await controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT
    });
  }

  private resolveTitle(title: string | undefined, fallbackUrl: string): string {
    const normalizedTitle = title?.trim() ?? '';
    return normalizedTitle.length > 0 ? normalizedTitle : fallbackUrl;
  }

  private resolveDescription(description: string | undefined, fallbackUrl: string): string {
    const normalizedDescription = description?.trim() ?? '';
    return normalizedDescription.length > 0 ? normalizedDescription : fallbackUrl;
  }
}
