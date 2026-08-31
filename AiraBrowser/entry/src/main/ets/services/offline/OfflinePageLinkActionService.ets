import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { pasteboard } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { BrowserProfileBoundaryService } from '../../core/browser/BrowserProfileBoundaryService';
import { BrowserPrivacyEffectPolicyService } from '../privacy/BrowserPrivacyEffectPolicyService';

export interface OfflinePageLinkActionResult {
  ok: boolean;
  message: string;
}

export class OfflinePageLinkActionService {
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService();
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();

  async copyOriginalUrl(
    url: string,
    dataScope: string,
    privacyMode: string
  ): Promise<OfflinePageLinkActionResult> {
    if (!this.isManagementShareAllowed(dataScope, privacyMode)) {
      return {
        ok: false,
        message: '当前隐私策略不允许复制离线页面链接'
      };
    }
    const normalizedUrl = url.trim();
    if (normalizedUrl.length === 0) {
      return {
        ok: false,
        message: '原网页链接不可用'
      };
    }

    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, normalizedUrl);
      await pasteboard.getSystemPasteboard().setData(data);
      return {
        ok: true,
        message: '已复制链接'
      };
    } catch (_error) {
      return {
        ok: false,
        message: '复制失败，请稍后重试'
      };
    }
  }

  async shareOriginalUrl(
    context: common.UIAbilityContext,
    title: string,
    url: string,
    dataScope: string,
    privacyMode: string
  ): Promise<OfflinePageLinkActionResult> {
    if (!this.isManagementShareAllowed(dataScope, privacyMode)) {
      return {
        ok: false,
        message: '当前隐私策略不允许分享离线页面链接'
      };
    }
    const normalizedUrl = url.trim();
    if (normalizedUrl.length === 0) {
      return {
        ok: false,
        message: '原网页链接不可用'
      };
    }

    const normalizedTitle = title.trim().length > 0 ? title.trim() : normalizedUrl;
    try {
      await this.showSharePanel(context, normalizedTitle, normalizedUrl);
      return {
        ok: true,
        message: '已打开分享面板'
      };
    } catch (_error) {
      const copyResult = await this.copyOriginalUrl(normalizedUrl, dataScope, privacyMode);
      if (copyResult.ok) {
        return {
          ok: true,
          message: '已复制链接，可手动分享'
        };
      }
      return {
        ok: false,
        message: '分享失败，请稍后重试'
      };
    }
  }

  private async showSharePanel(
    context: common.UIAbilityContext,
    title: string,
    url: string
  ): Promise<void> {
    const sharedData = new systemShare.SharedData({
      utd: uniformTypeDescriptor.UniformDataType.HYPERLINK,
      content: url,
      title: title,
      description: url
    });
    const controller = new systemShare.ShareController(sharedData);
    await controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT
    });
  }

  private isManagementShareAllowed(dataScope: string, privacyMode: string): boolean {
    return this.privacyEffectPolicy.decide({
      intent: 'regular_profile_management_share',
      requestingBoundary: this.profileBoundaryService.buildBoundary({
        dataScope: dataScope,
        privacyMode: privacyMode
      }),
      targetScope: 'regular_profile_data',
      targetIsClear: true
    }).outcome === 'allow';
  }
}
