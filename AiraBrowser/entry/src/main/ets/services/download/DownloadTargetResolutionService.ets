import { DownloadTaskBoundary } from '../../domain/download/DownloadTypes';
import { resolveAppResourceText } from '../../core/resources/AppResourceText';
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
import { resolveCustomDownloadDirectory } from './DownloadLocationDirectoryService';
import { DownloadV2DestinationSnapshot } from '../../domain/downloadv2/DownloadV2Types';

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
  destination: DownloadV2DestinationSnapshot;
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

  resolveDestinationSnapshot(boundary: DownloadTaskBoundary): DownloadV2DestinationSnapshot {
    return this.buildDestinationSnapshot(this.downloadPolicyService.resolveSavePolicy(boundary));
  }

  validateDestination(destination: DownloadV2DestinationSnapshot): Promise<boolean> {
    return this.fileResolutionService.validateDestination(destination);
  }

  selectDestination(fileName: string): Promise<DownloadV2DestinationSnapshot | undefined> {
    return this.fileResolutionService.selectDestination(fileName);
  }

  resolveCompletionTargetPolicy(
    boundary: DownloadTaskBoundary,
    suggestedFileName: string,
    destination?: DownloadV2DestinationSnapshot
  ): DownloadCompletionTargetPolicy {
    const savePolicy = this.downloadPolicyService.resolveSavePolicy(boundary);
    const fileName = this.fileResolutionService.sanitizeFileName(suggestedFileName);
    const tempDisplayPath = this.buildTempDisplayPath(fileName, savePolicy.isPrivateSession);
    const selectedDestination = destination ?? this.buildDestinationSnapshot(savePolicy);
    const reason = selectedDestination.kind === 'session_temp' ? 'private_session_temp_only'
      : selectedDestination.kind === 'prompt' ? 'private_prompt_for_location' : this.resolvePlanReason(savePolicy);
    if (selectedDestination.kind === 'session_temp') {
      return {
        shouldPromptForExport: false,
        tempDisplayPath: tempDisplayPath,
        completionMessage: resolveAppResourceText($r('app.string.download_private_completed', fileName)),
        reason: reason
      };
    }
    return {
      shouldPromptForExport: true,
      tempDisplayPath: tempDisplayPath,
      completionMessage: resolveAppResourceText($r('app.string.download_temp_completed', fileName)),
      reason: reason
    };
  }

  private buildTargetPlan(
    fileName: string,
    temporaryTarget: DownloadTemporaryTargetPlan,
    savePolicy: DownloadSavePolicy
  ): DownloadTargetPlan {
    const destination = this.buildDestinationSnapshot(savePolicy);
    const reason = this.resolvePlanReason(savePolicy);
    const tempDisplayPath = this.buildTempDisplayPath(fileName, savePolicy.isPrivateSession);
    const storageMode: DownloadTargetStorageMode =
      savePolicy.reason === 'private_session_temp_only' ? 'session_temp_only' : 'app_temp_then_export';
    const completionExportPolicy: DownloadCompletionExportPolicy =
      storageMode === 'session_temp_only' ? 'keep_temp_only' : 'prompt_after_completion';
    return {
      destination: destination,
      fileName: fileName,
      tempFilePath: temporaryTarget.targetPath,
      partialFilePath: temporaryTarget.targetPath,
      tempDisplayPath: tempDisplayPath,
      initialDisplayPath: this.resolveInitialDisplayPath(fileName, savePolicy, completionExportPolicy, tempDisplayPath),
      storageMode: storageMode,
      completionExportPolicy: completionExportPolicy,
      conflictAction: this.filenameConflictService.buildOriginalPlan(fileName).conflictAction,
      reason: reason,
      isPrivateSession: savePolicy.isPrivateSession
    };
  }

  private buildDestinationSnapshot(savePolicy: DownloadSavePolicy): DownloadV2DestinationSnapshot {
    if (savePolicy.isPrivateSession) {
      return { kind: savePolicy.reason === 'private_session_temp_only' ? 'session_temp' : 'prompt' };
    }
    const customDirectory = resolveCustomDownloadDirectory(savePolicy.settings);
    return customDirectory === undefined ? { kind: 'system_downloads' } : {
      kind: 'directory', uri: customDirectory.uri, label: customDirectory.label
    };
  }

  private resolveInitialDisplayPath(
    fileName: string,
    savePolicy: DownloadSavePolicy,
    completionExportPolicy: DownloadCompletionExportPolicy,
    tempDisplayPath: string
  ): string {
    if (completionExportPolicy !== 'prompt_after_completion') {
      return tempDisplayPath;
    }
    if (!savePolicy.isPrivateSession) {
      const customDirectory = resolveCustomDownloadDirectory(savePolicy.settings);
      if (customDirectory !== undefined) {
        return `${customDirectory.label}/${fileName}`;
      }
    }
    return resolveAppResourceText($r('app.string.download_choose_location_later'));
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
    const directoryName = isPrivateSession
      ? resolveAppResourceText($r('app.string.download_private_temp_dir'))
      : resolveAppResourceText($r('app.string.download_temp_dir'));
    return `${directoryName}/${fileName}`;
  }
}
