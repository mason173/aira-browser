import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  SEARCH_ENGINE_PREFERENCES_NAME,
  SEARCH_ENGINE_SETTINGS_KEY
} from '../../common/constants/SearchPreferenceKeys';
import { DEFAULT_SEARCH_ENGINE_ID } from '../../common/models/BrowserModels';

const DOMAIN: number = 0x0000;
const TAG: string = 'DesktopCardSearchEngine';
const FORM_REGISTRY_PREFERENCES_NAME: string = 'aira_desktop_card_search_engine';
const FORM_IDS_KEY: string = 'form_ids';
const FORM_NOT_FOUND_ERROR_CODE: number = 16501001;
interface StoredSearchEngineSettings {
  defaultSearchEngineId?: string;
}

export class DesktopCardSearchEngineService {
  private applicationContext?: common.Context;

  bindApplicationContext(context: common.Context): void {
    this.applicationContext = context;
  }

  addForm(context: common.Context, formId: string): formBindingData.FormBindingData {
    const normalizedFormId = formId.trim();
    if (normalizedFormId.length > 0) {
      const formIds = this.readFormIds(context);
      if (formIds.indexOf(normalizedFormId) < 0) {
        formIds.push(normalizedFormId);
        this.writeFormIds(context, formIds);
      }
    }
    return this.createBindingData(this.readDefaultSearchEngineId(context));
  }

  removeForm(context: common.Context, formId: string): void {
    const normalizedFormId = formId.trim();
    if (normalizedFormId.length <= 0) {
      return;
    }
    this.removeFormIds(context, [normalizedFormId]);
  }

  refreshForm(context: common.Context, formId: string): void {
    const normalizedFormId = formId.trim();
    if (normalizedFormId.length <= 0) {
      return;
    }
    const bindingData = this.createBindingData(this.readDefaultSearchEngineId(context));
    this.updateForms(context, [normalizedFormId], bindingData).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'Form refresh failed: %{public}s', JSON.stringify(error));
    });
  }

  refreshRegisteredForms(defaultSearchEngineId: string): void {
    const context = this.applicationContext;
    if (context === undefined) {
      return;
    }
    const formIds = this.readFormIds(context);
    if (formIds.length <= 0) {
      return;
    }
    const bindingData = this.createBindingData(defaultSearchEngineId);
    this.updateForms(context, formIds, bindingData).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'Registered Form refresh failed: %{public}s', JSON.stringify(error));
    });
  }

  reconcileRunningForms(): void {
    const context = this.applicationContext;
    if (context === undefined) {
      return;
    }
    formProvider.getPublishedRunningFormInfos()
      .then((runningForms: formInfo.RunningFormInfo[]) => {
        const currentFormIds = this.readFormIds(context);
        const nextFormIds = currentFormIds.slice();
        runningForms.forEach((runningForm: formInfo.RunningFormInfo) => {
          // getPublishedRunningFormInfos() already returns only this bundle's Forms.
          // RunningFormInfo has no module, ability, or form-name fields to filter on.
          const normalizedFormId = runningForm.formId.trim();
          if (normalizedFormId.length <= 0 || nextFormIds.indexOf(normalizedFormId) >= 0) {
            return;
          }
          nextFormIds.push(normalizedFormId);
        });
        if (nextFormIds.length !== currentFormIds.length) {
          this.writeFormIds(context, nextFormIds);
        }
        this.refreshRegisteredForms(this.readDefaultSearchEngineId(context));
      })
      .catch((error: Error) => {
        hilog.warn(DOMAIN, TAG, 'Unable to reconcile running Forms: %{public}s', JSON.stringify(error));
      });
  }

  private async updateForms(
    context: common.Context,
    formIds: string[],
    bindingData: formBindingData.FormBindingData
  ): Promise<void> {
    const staleFormIds: string[] = [];
    for (let index = 0; index < formIds.length; index += 1) {
      const formId = formIds[index];
      try {
        await formProvider.updateForm(formId, bindingData);
      } catch (error) {
        const businessError = error as BusinessError;
        if (businessError.code === FORM_NOT_FOUND_ERROR_CODE) {
          staleFormIds.push(formId);
        } else {
          hilog.warn(
            DOMAIN,
            TAG,
            'Unable to update Form %{public}s: %{public}s',
            formId,
            JSON.stringify(error)
          );
        }
      }
    }
    if (staleFormIds.length > 0) {
      this.removeFormIds(context, staleFormIds);
    }
  }

  private createBindingData(defaultSearchEngineId: string): formBindingData.FormBindingData {
    return formBindingData.createFormBindingData({
      searchEngineId: this.normalizeSearchEngineId(defaultSearchEngineId)
    });
  }

  private readDefaultSearchEngineId(context: common.Context): string {
    try {
      const store = preferences.getPreferencesSync(context, { name: SEARCH_ENGINE_PREFERENCES_NAME });
      const value = store.getSync(SEARCH_ENGINE_SETTINGS_KEY, '');
      const rawSettings = typeof value === 'string' ? value : '';
      if (rawSettings.trim().length <= 0) {
        return DEFAULT_SEARCH_ENGINE_ID;
      }
      const settings = JSON.parse(rawSettings) as StoredSearchEngineSettings;
      return this.normalizeSearchEngineId(settings.defaultSearchEngineId ?? DEFAULT_SEARCH_ENGINE_ID);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to read default search engine: %{public}s', JSON.stringify(error));
      return DEFAULT_SEARCH_ENGINE_ID;
    }
  }

  private normalizeSearchEngineId(engineId: string): string {
    switch (engineId.trim()) {
      case 'google':
      case 'duckduckgo':
      case 'baidu':
      case 'bing':
      case 'qihoo':
      case 'sogou':
      case 'shenma':
      case 'brave':
      case 'startpage':
      case 'ecosia':
      case 'yandex':
        return engineId.trim();
      default:
        return '';
    }
  }

  private readFormIds(context: common.Context): string[] {
    try {
      const store = preferences.getPreferencesSync(context, { name: FORM_REGISTRY_PREFERENCES_NAME });
      const value = store.getSync(FORM_IDS_KEY, '[]');
      const rawFormIds = typeof value === 'string' ? value : '[]';
      const parsedFormIds = JSON.parse(rawFormIds) as string[];
      const formIds: string[] = [];
      parsedFormIds.forEach((formId: string) => {
        const normalizedFormId = formId.trim();
        if (normalizedFormId.length > 0 && formIds.indexOf(normalizedFormId) < 0) {
          formIds.push(normalizedFormId);
        }
      });
      return formIds;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to read Form registry: %{public}s', JSON.stringify(error));
      return [];
    }
  }

  private writeFormIds(context: common.Context, formIds: string[]): void {
    try {
      const store = preferences.getPreferencesSync(context, { name: FORM_REGISTRY_PREFERENCES_NAME });
      store.putSync(FORM_IDS_KEY, JSON.stringify(formIds));
      store.flushSync();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Unable to write Form registry: %{public}s', JSON.stringify(error));
    }
  }

  private removeFormIds(context: common.Context, formIdsToRemove: string[]): void {
    const currentFormIds = this.readFormIds(context);
    const nextFormIds = currentFormIds.filter((formId: string): boolean => {
      return formIdsToRemove.indexOf(formId) < 0;
    });
    if (nextFormIds.length !== currentFormIds.length) {
      this.writeFormIds(context, nextFormIds);
    }
  }
}

export const sharedDesktopCardSearchEngineService: DesktopCardSearchEngineService =
  new DesktopCardSearchEngineService();
