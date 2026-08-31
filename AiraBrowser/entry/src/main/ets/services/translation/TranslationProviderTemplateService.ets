import {
  TranslationProviderTemplate,
  TranslationProviderTemplateId
} from '../../common/models/BrowserModels';

export class TranslationProviderTemplateService {
  listTemplates(): TranslationProviderTemplate[] {
    return [
      {
        id: 'aira_system',
        displayName: 'Aira 系统翻译',
        description: '由 Aira 提供的网页翻译服务，可能使用 Aira 云服务和必要第三方机器翻译服务处理页面文字。',
        setupStatus: 'configured',
        requiresSecret: false,
        supportsDirectClientRequest: false,
        builtIn: true,
        requiresPro: false
      },
      {
        id: 'custom_http',
        displayName: '自定义接口',
        description: '使用你自己的 HTTPS 翻译接口，适合把官方服务商鉴权放在自有服务端代理里。',
        setupStatus: 'configured',
        requiresSecret: false,
        supportsDirectClientRequest: true,
        builtIn: false,
        requiresPro: false
      },
      {
        id: 'deepl',
        displayName: 'DeepL',
        description: '填写自己的 API Key，清风会请求 DeepL 官方翻译接口。',
        setupStatus: 'configured',
        requiresSecret: true,
        supportsDirectClientRequest: true,
        builtIn: false,
        requiresPro: false
      },
      {
        id: 'google_cloud',
        displayName: 'Google Cloud Translation',
        description: '填写自己的 API Key，清风会请求 Google Cloud Translation 官方接口。',
        setupStatus: 'configured',
        requiresSecret: true,
        supportsDirectClientRequest: true,
        builtIn: false,
        requiresPro: false
      },
      {
        id: 'tencent_cloud',
        displayName: '腾讯云机器翻译',
        description: '填写 SecretId、SecretKey 和地域，清风会使用腾讯云 API3 签名请求。',
        setupStatus: 'configured',
        requiresSecret: true,
        supportsDirectClientRequest: true,
        builtIn: false,
        requiresPro: false
      },
      {
        id: 'baidu',
        displayName: '百度翻译',
        description: '填写 App ID 与密钥，清风会请求百度翻译开放平台接口。',
        setupStatus: 'configured',
        requiresSecret: true,
        supportsDirectClientRequest: true,
        builtIn: false,
        requiresPro: false
      },
      {
        id: 'microsoft',
        displayName: 'Microsoft Translator',
        description: '填写订阅 Key 和区域，清风会请求 Microsoft Translator 官方接口。',
        setupStatus: 'configured',
        requiresSecret: true,
        supportsDirectClientRequest: true,
        builtIn: false,
        requiresPro: false
      },
      {
        id: 'alibaba_cloud',
        displayName: '阿里云机器翻译',
        description: '填写 AccessKey ID、AccessKey Secret 和地域，清风会使用阿里云签名请求。',
        setupStatus: 'configured',
        requiresSecret: true,
        supportsDirectClientRequest: true,
        builtIn: false,
        requiresPro: false
      },
      {
        id: 'volcano',
        displayName: '火山引擎机器翻译',
        description: '填写 Access Key、Secret Key 和区域，清风会使用火山引擎签名请求。',
        setupStatus: 'configured',
        requiresSecret: true,
        supportsDirectClientRequest: true,
        builtIn: false,
        requiresPro: false
      },
      {
        id: 'youdao',
        displayName: '有道智云翻译',
        description: '填写应用 ID 与应用密钥，清风会请求有道智云官方接口。',
        setupStatus: 'configured',
        requiresSecret: true,
        supportsDirectClientRequest: true,
        builtIn: false,
        requiresPro: false
      }
    ];
  }

  listConfigurableTemplates(): TranslationProviderTemplate[] {
    return this.listTemplates().filter((template: TranslationProviderTemplate) => !template.builtIn);
  }

  findTemplate(templateId: TranslationProviderTemplateId): TranslationProviderTemplate {
    const template = this.listTemplates().find((item: TranslationProviderTemplate) => item.id === templateId);
    if (template !== undefined) {
      return template;
    }
    return this.listTemplates()[0];
  }

  buildTemplateLabel(templateId: TranslationProviderTemplateId | string): string {
    const template = this.listTemplates().find((item: TranslationProviderTemplate) => item.id === templateId);
    return template?.displayName ?? '自定义接口';
  }
}
