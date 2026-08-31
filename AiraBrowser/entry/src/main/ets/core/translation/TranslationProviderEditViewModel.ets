import {
  TranslationProviderConfig,
  TranslationProviderTemplate,
  TranslationProviderTemplateId
} from '../../common/models/BrowserModels';
import { TranslationProviderTemplateService } from '../../services/translation/TranslationProviderTemplateService';

export interface TranslationProviderEditFieldView {
  key: string;
  label: string;
  placeholder: string;
  secure: boolean;
}

export interface TranslationProviderEditDraft {
  providerId: string;
  templateId: TranslationProviderTemplateId;
  displayName: string;
  endpoint: string;
  apiKey: string;
  appId: string;
  secretKey: string;
  region: string;
  model: string;
}

export interface TranslationProviderEditState {
  title: string;
  displayName: string;
  endpoint: string;
  apiKey: string;
  appId: string;
  secretKey: string;
  region: string;
  model: string;
  description: string;
  helperText: string;
  errorMessage: string;
  saveEnabled: boolean;
  fields: TranslationProviderEditFieldView[];
}

export class TranslationProviderEditViewModel {
  private templateService: TranslationProviderTemplateService = new TranslationProviderTemplateService();

  buildInitialDraft(templateId: TranslationProviderTemplateId = 'custom_http'): TranslationProviderEditDraft {
    return this.buildDraftForTemplate(templateId);
  }

  buildDraftForTemplate(templateId: TranslationProviderTemplateId): TranslationProviderEditDraft {
    const template = this.templateService.findTemplate(templateId);
    return {
      providerId: '',
      templateId: template.id,
      displayName: template.displayName,
      endpoint: '',
      apiKey: '',
      appId: '',
      secretKey: '',
      region: '',
      model: ''
    };
  }

  updateDraft(
    draft: TranslationProviderEditDraft,
    key: 'displayName' | 'endpoint' | 'apiKey' | 'appId' | 'secretKey' | 'region' | 'model',
    value: string
  ): TranslationProviderEditDraft {
    return {
      providerId: draft.providerId,
      templateId: draft.templateId,
      displayName: key === 'displayName' ? value : draft.displayName,
      endpoint: key === 'endpoint' ? value : draft.endpoint,
      apiKey: key === 'apiKey' ? value : draft.apiKey,
      appId: key === 'appId' ? value : draft.appId,
      secretKey: key === 'secretKey' ? value : draft.secretKey,
      region: key === 'region' ? value : draft.region,
      model: key === 'model' ? value : draft.model
    };
  }

  buildState(draft: TranslationProviderEditDraft, persistedError: string = ''): TranslationProviderEditState {
    const template = this.templateService.findTemplate(draft.templateId);
    const validationError = persistedError.length > 0 ? persistedError : this.buildValidationError(draft);
    return {
      title: '配置服务商',
      displayName: draft.displayName,
      endpoint: draft.endpoint,
      apiKey: draft.apiKey,
      appId: draft.appId,
      secretKey: draft.secretKey,
      region: draft.region,
      model: draft.model,
      description: template.description,
      helperText: this.buildHelperText(template),
      errorMessage: validationError,
      saveEnabled: validationError.length === 0,
      fields: this.buildFields(template.id)
    };
  }

  buildProvider(draft: TranslationProviderEditDraft): TranslationProviderConfig {
    const template = this.templateService.findTemplate(draft.templateId);
    return {
      id: draft.providerId.trim(),
      templateId: template.id,
      displayName: draft.displayName.trim().length > 0 ? draft.displayName.trim() : template.displayName,
      endpoint: draft.endpoint.trim(),
      apiKey: draft.apiKey.trim(),
      appId: draft.appId.trim(),
      secretKey: draft.secretKey.trim(),
      region: draft.region.trim(),
      model: draft.model.trim(),
      optionsJson: '{}',
      secretRefsJson: '{}',
      status: 'configured',
      failureReason: '',
      updatedAt: Date.now()
    };
  }

  buildDraftFromProvider(provider: TranslationProviderConfig): TranslationProviderEditDraft {
    return {
      providerId: provider.id,
      templateId: provider.templateId,
      displayName: provider.displayName,
      endpoint: provider.endpoint,
      apiKey: provider.apiKey,
      appId: provider.appId,
      secretKey: provider.secretKey,
      region: provider.region,
      model: provider.model
    };
  }

  private buildFields(templateId: TranslationProviderTemplateId): TranslationProviderEditFieldView[] {
    switch (templateId) {
      case 'custom_http':
        return [
          { key: 'displayName', label: '名称', placeholder: '例如 我的翻译服务', secure: false },
          { key: 'endpoint', label: 'HTTPS Endpoint', placeholder: 'https://api.example.com/translate', secure: false }
        ];
      case 'baidu':
      case 'youdao':
        return [
          { key: 'displayName', label: '名称', placeholder: '例如 百度翻译', secure: false },
          { key: 'appId', label: 'App ID', placeholder: '填写你的应用 ID', secure: false },
          { key: 'secretKey', label: '应用密钥', placeholder: '填写你的应用密钥', secure: true }
        ];
      case 'tencent_cloud':
        return [
          { key: 'displayName', label: '名称', placeholder: '例如 腾讯云翻译', secure: false },
          { key: 'appId', label: 'SecretId', placeholder: '填写你的 SecretId', secure: false },
          { key: 'secretKey', label: 'SecretKey', placeholder: '填写你的 SecretKey', secure: true },
          { key: 'region', label: '地域', placeholder: '例如 ap-shanghai', secure: false }
        ];
      case 'alibaba_cloud':
        return [
          { key: 'displayName', label: '名称', placeholder: '例如 阿里云翻译', secure: false },
          { key: 'appId', label: 'AccessKey ID', placeholder: '填写你的 AccessKey ID', secure: false },
          { key: 'secretKey', label: 'AccessKey Secret', placeholder: '填写你的 AccessKey Secret', secure: true },
          { key: 'region', label: '地域', placeholder: '例如 cn-hangzhou', secure: false }
        ];
      case 'volcano':
        return [
          { key: 'displayName', label: '名称', placeholder: '例如 火山翻译', secure: false },
          { key: 'appId', label: 'Access Key', placeholder: '填写你的 Access Key', secure: false },
          { key: 'secretKey', label: 'Secret Key', placeholder: '填写你的 Secret Key', secure: true },
          { key: 'region', label: '区域', placeholder: '例如 cn-north-1', secure: false }
        ];
      case 'microsoft':
        return [
          { key: 'displayName', label: '名称', placeholder: '例如 Microsoft Translator', secure: false },
          { key: 'apiKey', label: '订阅 Key', placeholder: '填写你的订阅 Key', secure: true },
          { key: 'region', label: '区域', placeholder: '例如 eastasia', secure: false }
        ];
      case 'google_cloud':
        return [
          { key: 'displayName', label: '名称', placeholder: '例如 Google Cloud', secure: false },
          { key: 'apiKey', label: 'API Key', placeholder: '填写你的 API Key', secure: true },
          { key: 'model', label: '项目或模型', placeholder: '可选', secure: false }
        ];
      default:
        return [
          { key: 'displayName', label: '名称', placeholder: '例如 DeepL', secure: false },
          { key: 'apiKey', label: 'API Key', placeholder: '填写你的 API Key', secure: true }
        ];
    }
  }

  private buildValidationError(draft: TranslationProviderEditDraft): string {
    if (draft.displayName.trim().length === 0) {
      return '请填写服务名称。';
    }
    if (draft.templateId === 'custom_http') {
      const endpoint = draft.endpoint.trim();
      if (!endpoint.toLowerCase().startsWith('https://')) {
        return '自定义翻译服务必须使用 HTTPS endpoint。';
      }
      const lowerEndpoint = endpoint.toLowerCase();
      if (lowerEndpoint.indexOf('?') >= 0 &&
        (lowerEndpoint.indexOf('key=') >= 0 || lowerEndpoint.indexOf('token=') >= 0 ||
          lowerEndpoint.indexOf('secret=') >= 0 || lowerEndpoint.indexOf('password=') >= 0)) {
        return '不要把 API 密钥放在 URL 查询参数中。';
      }
      return '';
    }
    switch (draft.templateId) {
      case 'deepl':
      case 'google_cloud':
      case 'microsoft':
        return draft.apiKey.trim().length > 0 ? '' : '请填写该服务商的 API Key。';
      case 'baidu':
      case 'youdao':
        return draft.appId.trim().length > 0 && draft.secretKey.trim().length > 0
          ? ''
          : '请填写该服务商的应用 ID 和应用密钥。';
      case 'tencent_cloud':
        return draft.appId.trim().length > 0 && draft.secretKey.trim().length > 0
          ? ''
          : '请填写腾讯云 SecretId 和 SecretKey。';
      case 'alibaba_cloud':
      case 'volcano':
        return draft.appId.trim().length > 0 && draft.secretKey.trim().length > 0
          ? ''
          : '请填写 Access Key 和 Secret Key。';
      default:
        return '';
    }
    return '';
  }

  private buildHelperText(template: TranslationProviderTemplate): string {
    if (template.id === 'custom_http') {
      return '清风会用 POST JSON 发送 sourceLanguage、targetLanguage 和 texts 数组；响应可返回 items、translations 或 results。';
    }
    return '清风会直接请求该服务商官方接口。翻译前会提示你确认页面文字将发送到所选服务。';
  }
}
