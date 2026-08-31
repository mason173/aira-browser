import { TranslationProviderTemplateId } from '../../common/models/BrowserModels';

export class TranslationProviderLogoViewModel {
  resolveLogo(templateId: TranslationProviderTemplateId): Resource {
    switch (templateId) {
      case 'aira_system':
        return $r('app.media.startup_brand_icon');
      case 'deepl':
        return $r('app.media.translation_provider_deepl');
      case 'google_cloud':
        return $r('app.media.translation_provider_google_cloud');
      case 'tencent_cloud':
        return $r('app.media.translation_provider_tencent_cloud');
      case 'baidu':
        return $r('app.media.translation_provider_baidu');
      case 'microsoft':
        return $r('app.media.translation_provider_microsoft');
      case 'alibaba_cloud':
        return $r('app.media.translation_provider_alibaba_cloud');
      case 'volcano':
        return $r('app.media.translation_provider_volcano');
      case 'youdao':
        return $r('app.media.translation_provider_youdao');
      case 'custom_http':
        return $r('app.media.translation_provider_custom_http');
      default:
        return $r('app.media.translation_provider_custom_http');
    }
  }
}
