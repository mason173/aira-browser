import { DownloadTaskBoundary } from '../../domain/download/DownloadTypes';
import { DownloadV2CapturedRequest } from '../../features/downloadv2/DownloadV2CaptureTypes';
import {
  DownloadFilenameConflictAction,
  DownloadFilenameConflictService
} from './DownloadFilenameConflictService';
import {
  DownloadFileResolutionAdapter,
  DownloadFileResolutionService,
  DownloadTemporaryTargetPlan
} from './DownloadFileResolutionService';
import {
  DownloadPolicyService,
  DownloadSavePolicy
} from './DownloadPolicyService';

export type DownloadTargetStorageMode =
  'app_temp_then_export' |
  'session_temp_only';

export type DownloadCompletionExportPolicy =
  'prompt_after_completion' |
  'keep_temp_only';

export type DownloadTargetPlanReason =
  'regular_system_downloads' |
  'ask_before_download' |
  'private_prompt_for_location' |
  'private_session_temp_only';

export interface DownloadTargetPlan {
  fileName: string;
  tempFilePath: string;
  partialFilePath: string;
  tempDisplayPath: string;
  initialDisplayPath: string;
  storageMode: DownloadTargetStorageMode;
  completionExportPolicy: DownloadCompletionExportPolicy;
  conflictAction: DownloadFilenameConflictAction;
  reason: DownloadTargetPlanReason;
  isPrivateSession: boolean;
}

export interface DownloadCompletionTargetPolicy {
  shouldPromptForExport: boolean;
  tempDisplayPath: string;
  completionMessage: string;
  reason: DownloadTargetPlanReason;
}

export class DownloadTargetResolutionService {
  private fileResolutionService: DownloadFileResolutionAdapter;
  private downloadPolicyService: DownloadPolicyService;
  private filenameConflictService: DownloadFilenameConflictService = new DownloadFilenameConflictService();

  constructor(
    fileResolutionService: DownloadFileResolutionAdapter = new DownloadFileResolutionService(),
    downloadPolicyService: DownloadPolicyService = new DownloadPolicyService()
  ) {
    this.fileResolutionService = fileResolutionService;
    this.downloadPolicyService = downloadPolicyService;
  }

  async resolveTargetPlan(request: DownloadV2CapturedRequest): Promise<DownloadTargetPlan | undefined> {
    const savePolicy = this.downloadPolicyService.resolveSavePolicy({
      windowId: request.boundary.windowId,
      profileId: request.boundary.profileId,
      privacyMode: request.boundary.privacyMode,
      dataScope: request.boundary.dataScope,
      sourcePageUrl: request.boundary.sourcePageUrl
    });
    const sanitizedFileName = this.fileResolutionService.sanitizeFileName(request.suggestedFileName);
    const temporaryTarget = await this.fileResolutionService.resolveTemporaryTarget(sanitizedFileName);
    if (temporaryTarget === undefined) {
      return undefined;
    }
    return this.buildTargetPlan(sanitizedFileName, temporaryTarget, savePolicy);
  }

  resolveCompletionTargetPolicy(
    boundary: DownloadTaskBoundary,
    suggestedFileName: string
  ): DownloadCompletionTargetPolicy {
    const savePolicy = this.downloadPolicyService.resolveSavePolicy(boundary);
    const fileName = this.fileResolutionService.sanitizeFileName(suggestedFileName);
    const reason = this.resolvePlanReason(savePolicy);
    const tempDisplayPath = this.buildTempDisplayPath(fileName, savePolicy.isPrivateSession);
    if (savePolicy.reason === 'private_session_temp_only') {
      return {
        shouldPromptForExport: false,
        tempDisplayPath: tempDisplayPath,
        completionMessage: `私密下载完成，文件仅保存在本次会话临时目录：${fileName}。`,
        reason: reason
      };
    }
    return {
      shouldPromptForExport: true,
      tempDisplayPath: tempDisplayPath,
      completionMessage: `下载完成，文件仍保存在 Aira 临时下载目录：${fileName}。`,
      reason: reason
    };
  }

  private buildTargetPlan(
    fileName: string,
    temporaryTarget: DownloadTemporaryTargetPlan,
    savePolicy: DownloadSavePolicy
  ): DownloadTargetPlan {
    const reason = this.resolvePlanReason(savePolicy);
    const tempDisplayPath = this.buildTempDisplayPath(fileName, savePolicy.isPrivateSession);
    const storageMode: DownloadTargetStorageMode =
      savePolicy.reason === 'private_session_temp_only' ? 'session_temp_only' : 'app_temp_then_export';
    const completionExportPolicy: DownloadCompletionExportPolicy =
      storageMode === 'session_temp_only' ? 'keep_temp_only' : 'prompt_after_completion';
    return {
      fileName: fileName,
      tempFilePath: temporaryTarget.targetPath,
      partialFilePath: temporaryTarget.targetPath,
      tempDisplayPath: tempDisplayPath,
      initialDisplayPath: completionExportPolicy === 'prompt_after_completion'
        ? '完成后选择系统下载位置'
        : tempDisplayPath,
      storageMode: storageMode,
      completionExportPolicy: completionExportPolicy,
      conflictAction: this.filenameConflictService.buildOriginalPlan(fileName).conflictAction,
      reason: reason,
      isPrivateSession: savePolicy.isPrivateSession
    };
  }

  private resolvePlanReason(savePolicy: DownloadSavePolicy): DownloadTargetPlanReason {
    switch (savePolicy.reason) {
      case 'ask_before_download':
        return 'ask_before_download';
      case 'private_prompt_for_location':
        return 'private_prompt_for_location';
      case 'private_session_temp_only':
        return 'private_session_temp_only';
      case 'default_location':
      default:
        return 'regular_system_downloads';
    }
  }

  private buildTempDisplayPath(fileName: string, isPrivateSession: boolean): string {
    const directoryName = isPrivateSession ? 'Aira 私密临时下载目录' : 'Aira 临时下载目录';
    return `${directoryName}/${fileName}`;
  }
}
