import { image } from '@kit.ImageKit';
import {
  ExternalNavigationPromptState,
  ExternalNavigationPromptTrigger,
  ExternalNavigationPromptViewModel
} from './ExternalNavigationPromptViewModel';

export interface BrowserExternalNavigationInfoBarPromptInput {
  tabId: string;
  url: string;
  appName: string;
  sourcePageUrl: string;
  createdAt: number;
  originLabel: string;
  dataScopeLabel: string;
  iconUri?: string;
  favicon?: image.PixelMap;
  trigger: ExternalNavigationPromptTrigger;
}

export interface BrowserExternalNavigationInfoBarRecord {
  id: string;
  tabId: string;
  url: string;
  appName: string;
  sourcePageUrl: string;
  createdAt: number;
}

export interface BrowserExternalNavigationInfoBarShowPlan {
  record: BrowserExternalNavigationInfoBarRecord;
  promptState: ExternalNavigationPromptState;
}

export type BrowserExternalNavigationInfoBarDecisionAction =
  'none' |
  'open_external' |
  'suppress_after_cancel';

export interface BrowserExternalNavigationInfoBarDecisionPlan {
  action: BrowserExternalNavigationInfoBarDecisionAction;
  tabId: string;
  url: string;
  promptState: ExternalNavigationPromptState;
}

export class BrowserInfoBarQueue {
  private readonly externalNavigationPromptViewModel: ExternalNavigationPromptViewModel =
    new ExternalNavigationPromptViewModel();
  private externalNavigationRecord?: BrowserExternalNavigationInfoBarRecord;

  createHiddenExternalNavigationState(): ExternalNavigationPromptState {
    return this.externalNavigationPromptViewModel.createHiddenState();
  }

  enqueueExternalNavigationPrompt(
    input: BrowserExternalNavigationInfoBarPromptInput
  ): BrowserExternalNavigationInfoBarShowPlan {
    const record: BrowserExternalNavigationInfoBarRecord = {
      id: this.buildRecordId(input.tabId, input.url, input.createdAt),
      tabId: input.tabId.trim(),
      url: input.url.trim(),
      appName: input.appName.trim(),
      sourcePageUrl: input.sourcePageUrl.trim(),
      createdAt: input.createdAt
    };
    this.externalNavigationRecord = record;
    return {
      record: record,
      promptState: this.externalNavigationPromptViewModel.buildState({
        tabId: record.tabId,
        url: record.url,
        sourcePageUrl: record.sourcePageUrl,
        appName: record.appName,
        originLabel: input.originLabel,
        dataScopeLabel: input.dataScopeLabel,
        iconUri: input.iconUri,
        favicon: input.favicon,
        trigger: input.trigger,
        now: record.createdAt
      })
    };
  }

  private consumeExternalNavigation(): BrowserExternalNavigationInfoBarRecord | undefined {
    const record = this.externalNavigationRecord;
    this.externalNavigationRecord = undefined;
    return record;
  }

  consumeExternalNavigationConfirm(): BrowserExternalNavigationInfoBarDecisionPlan {
    return this.buildDecisionPlan(this.consumeExternalNavigation(), 'open_external');
  }

  consumeExternalNavigationDismiss(): BrowserExternalNavigationInfoBarDecisionPlan {
    return this.buildDecisionPlan(this.consumeExternalNavigation(), 'suppress_after_cancel');
  }

  clearExternalNavigation(): void {
    this.externalNavigationRecord = undefined;
  }

  private buildRecordId(tabId: string, url: string, createdAt: number): string {
    return `${tabId.trim()}:${createdAt}:${url.trim()}`;
  }

  private buildDecisionPlan(
    record: BrowserExternalNavigationInfoBarRecord | undefined,
    action: BrowserExternalNavigationInfoBarDecisionAction
  ): BrowserExternalNavigationInfoBarDecisionPlan {
    if (record === undefined || record.tabId.length <= 0 || record.url.length <= 0) {
      return {
        action: 'none',
        tabId: '',
        url: '',
        promptState: this.externalNavigationPromptViewModel.createHiddenState()
      };
    }
    return {
      action: action,
      tabId: record.tabId,
      url: record.url,
      promptState: this.externalNavigationPromptViewModel.createHiddenState()
    };
  }
}
