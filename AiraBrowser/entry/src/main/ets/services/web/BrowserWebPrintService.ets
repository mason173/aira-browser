import { common } from '@kit.AbilityKit';
import { BusinessError, print } from '@kit.BasicServicesKit';
import { webview } from '@kit.ArkWeb';
import { BrowserRuntimeLifecyclePort } from './BrowserRuntimeLifecyclePort';

export interface BrowserWebPrintRequest {
  controller: webview.WebviewController;
  context: common.UIAbilityContext;
  title: string;
  printBackground: boolean;
  onStatusMessage?: (message: string) => void;
}

export interface BrowserWebPrintFromLifecyclePortRequest {
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  context: common.UIAbilityContext;
  title: string;
  printBackground: boolean;
  onStatusMessage?: (message: string) => void;
}

export interface BrowserWebPrintAvailabilityFacts {
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  showHomePage: boolean;
  showTabsSheet: boolean;
  webPageVisible: boolean;
}

export interface BrowserWebPrintResult {
  ok: boolean;
  message: string;
  code?: number;
}

const DEFAULT_WEB_PRINT_JOB_NAME = 'Aira Web Page';
const MAX_WEB_PRINT_JOB_NAME_LENGTH = 80;

export class BrowserWebPrintService {
  canPrintCurrentPage(facts: BrowserWebPrintAvailabilityFacts): boolean {
    return !facts.showHomePage && !facts.showTabsSheet && facts.webPageVisible &&
      facts.runtimeLifecyclePort.resolveActiveController() !== undefined;
  }

  async printCurrentPageFromLifecyclePort(
    request: BrowserWebPrintFromLifecyclePortRequest
  ): Promise<BrowserWebPrintResult> {
    const controller = request.runtimeLifecyclePort.resolveActiveController();
    if (controller === undefined) {
      return {
        ok: false,
        message: '当前页面暂时无法打印。'
      };
    }
    return await this.printCurrentPage({
      controller: controller,
      context: request.context,
      title: request.title,
      printBackground: request.printBackground,
      onStatusMessage: request.onStatusMessage
    });
  }

  async printCurrentPage(request: BrowserWebPrintRequest): Promise<BrowserWebPrintResult> {
    let adapter: print.PrintDocumentAdapter;
    try {
      request.controller.setPrintBackground(request.printBackground);
      adapter = request.controller.createWebPrintDocumentAdapter(this.resolveJobName(request.title));
    } catch (error) {
      return this.buildFailureResult(error, '当前页面暂时无法创建打印内容。');
    }

    try {
      const attributes: print.PrintAttributes = {};
      const task: print.PrintTask = await print.print(this.resolveJobName(request.title), adapter, attributes,
        request.context);
      task.on('succeed', () => {
        request.onStatusMessage?.('打印任务已完成。');
      });
      task.on('fail', () => {
        request.onStatusMessage?.('打印任务失败。');
      });
      task.on('cancel', () => {
        request.onStatusMessage?.('已取消打印。');
      });
      task.on('block', () => {
        request.onStatusMessage?.('打印任务暂时受阻。');
      });
      return {
        ok: true,
        message: '正在打开系统打印。'
      };
    } catch (error) {
      return this.buildFailureResult(error, '打印暂时无法启动。');
    }
  }

  private resolveJobName(title: string): string {
    const normalized = title.trim().replace(/\s+/g, ' ');
    if (normalized.length <= 0) {
      return DEFAULT_WEB_PRINT_JOB_NAME;
    }
    if (normalized.length <= MAX_WEB_PRINT_JOB_NAME_LENGTH) {
      return normalized;
    }
    return normalized.substring(0, MAX_WEB_PRINT_JOB_NAME_LENGTH);
  }

  private buildFailureResult(error: Object, fallbackMessage: string): BrowserWebPrintResult {
    const businessError = error as BusinessError;
    if (businessError?.code === 201) {
      return {
        ok: false,
        message: '缺少打印权限，暂时无法打印网页。',
        code: businessError.code
      };
    }
    return {
      ok: false,
      message: fallbackMessage,
      code: businessError?.code
    };
  }
}
