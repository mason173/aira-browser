import { Want } from '@kit.AbilityKit';
import {
  UserScriptInstallSessionCoordinator,
  UserScriptInstallSourceResult
} from './UserScriptInstallSessionCoordinator';
import { UserScriptExternalImportService } from '../../services/userscripts/UserScriptExternalImportService';
import {
  UserScriptExternalImportEnvelope,
  UserScriptExternalImportRuntime
} from './UserScriptExternalImportRuntime';

export interface UserScriptExternalImportLaunchHost {
  waitForContentReady: () => Promise<void>;
  openUserScripts: (source: string) => Promise<boolean>;
}

export class UserScriptExternalImportCoordinator {
  private readonly installSession: UserScriptInstallSessionCoordinator;
  private readonly externalImportService: UserScriptExternalImportService;
  private requestSequence: number = 0;
  private latestRequestId: string = '';
  private ingressDestroyed: boolean = false;

  constructor(
    installSession: UserScriptInstallSessionCoordinator,
    externalImportService: UserScriptExternalImportService = new UserScriptExternalImportService()
  ) {
    this.installSession = installSession;
    this.externalImportService = externalImportService;
  }

  handleExternalImportWant(
    want: Want,
    source: string,
    host: UserScriptExternalImportLaunchHost
  ): boolean {
    if (!this.externalImportService.isCandidate(want)) {
      return false;
    }
    const requestId = `external_user_script_${Date.now()}_${++this.requestSequence}`;
    this.latestRequestId = requestId;
    void this.prepareAndStage(want, requestId, source, host);
    return true;
  }

  destroyExternalImportIngress(): void {
    this.ingressDestroyed = true;
    this.installSession.reset();
    UserScriptExternalImportRuntime.consume();
  }

  private async prepareAndStage(
    want: Want,
    requestId: string,
    source: string,
    host: UserScriptExternalImportLaunchHost
  ): Promise<void> {
    let envelope: UserScriptExternalImportEnvelope;
    try {
      const uri = this.externalImportService.resolveSourceUri(want);
      this.installSession.reset();
      const result: UserScriptInstallSourceResult = await this.installSession.loadSource({
        type: 'file_uri',
        uri: uri
      });
      envelope = this.buildEnvelope(requestId, result);
    } catch (error) {
      envelope = {
        requestId: requestId,
        status: 'failed',
        errorMessage: this.externalImportService.buildUserFacingError(error)
      };
    }
    if (this.ingressDestroyed || requestId !== this.latestRequestId) {
      return;
    }
    const stageResult = UserScriptExternalImportRuntime.stage(envelope);
    if (stageResult.notifiedListenerCount > 0) {
      return;
    }
    await host.waitForContentReady();
    if (this.ingressDestroyed || !UserScriptExternalImportRuntime.isPending(requestId)) {
      return;
    }
    let handled = false;
    try {
      handled = await host.openUserScripts(source);
    } catch (_error) {
    }
    if (!handled) {
      UserScriptExternalImportRuntime.consume(requestId);
    }
  }

  private buildEnvelope(
    requestId: string,
    result: UserScriptInstallSourceResult
  ): UserScriptExternalImportEnvelope {
    switch (result.status) {
      case 'loaded':
        return {
          requestId: requestId,
          status: 'prepared',
          errorMessage: ''
        };
      case 'duplicate':
        return {
          requestId: requestId,
          status: 'failed',
          errorMessage: `“${result.duplicate.scriptName}”已经安装。`
        };
      case 'failed':
        return {
          requestId: requestId,
          status: 'failed',
          errorMessage: result.errorMessage
        };
      case 'cancelled':
        return {
          requestId: requestId,
          status: 'failed',
          errorMessage: '用户脚本导入已取消。'
        };
    }
  }
}
