import { describe, expect, it } from '@ohos/hypium';
import { BrowserDownloadSettings } from '../main/ets/common/models/BrowserModels';
import {
  DownloadQueryService,
  DownloadTaskQueryState
} from '../main/ets/core/download/DownloadQueryService';
import { DownloadV2Engine } from '../main/ets/core/downloadv2/DownloadV2Engine';
import { InMemoryDownloadV2Repository } from '../main/ets/data/downloadv2/DownloadV2Repository';
import { PreferencesRepository } from '../main/ets/data/preferences/PreferencesRepository';
import { createDownloadV2BoundarySnapshot } from '../main/ets/domain/downloadv2/DownloadV2TaskEntity';
import { DownloadTaskBoundary } from '../main/ets/domain/download/DownloadTypes';
import {
  DownloadFileResolutionAdapter,
  DownloadLocalDeleteResult,
  DownloadPersistResult,
  DownloadTemporaryTargetPlan
} from '../main/ets/services/download/DownloadFileResolutionService';
import {
  DownloadPolicyService,
  DownloadSavePolicy,
  DownloadSessionCleanupPolicy
} from '../main/ets/services/download/DownloadPolicyService';
import { DownloadRuntimeService } from '../main/ets/services/download/DownloadRuntimeService';
import { DownloadV2Service } from '../main/ets/services/downloadv2/DownloadV2Service';

export default function downloadPrivacyPolicyTest(): void {
  describe('Download privacy owner', () => {
    it('reads and writes device-wide Download Settings from a private session', 0, async () => {
      const preferencesRepository = new PreferencesRepository();
      const downloadPolicy = new DownloadPolicyService(preferencesRepository);
      const privateBoundary: DownloadTaskBoundary = {
        windowId: 'private-window-1',
        profileId: 'profile-main',
        privacyMode: 'private',
        dataScope: 'session_ephemeral'
      };
      const initialSettings = downloadPolicy.readSettings(privateBoundary);
      const nextSettings: BrowserDownloadSettings = {
        defaultLocation: initialSettings.defaultLocation,
        askBeforeDownload: false,
        allowCellularDownloads: initialSettings.allowCellularDownloads,
        autoResumeAfterRestart: initialSettings.autoResumeAfterRestart,
        autoClearPolicy: initialSettings.autoClearPolicy,
        privateFilePolicy: initialSettings.privateFilePolicy,
        privateRecordPolicy: initialSettings.privateRecordPolicy
      };

      const committedSettings = await downloadPolicy.updateSettings(privateBoundary, nextSettings);

      expect(committedSettings.askBeforeDownload).assertFalse();
      expect(downloadPolicy.readSettings(privateBoundary).askBeforeDownload).assertFalse();
    });

    it('keeps private Download save and cleanup semantics unchanged', 0, async () => {
      const preferencesRepository = new PreferencesRepository();
      const downloadPolicy = new DownloadPolicyService(preferencesRepository);
      const privateBoundary: DownloadTaskBoundary = {
        windowId: 'private-window-1',
        profileId: 'profile-main',
        privacyMode: 'private',
        dataScope: 'session_ephemeral'
      };

      const exportPolicy: DownloadSavePolicy = downloadPolicy.resolveSavePolicy(privateBoundary);
      const cleanupPolicy: DownloadSessionCleanupPolicy = downloadPolicy.resolveSessionCleanupPolicy(privateBoundary);
      const tempOnlySettings: BrowserDownloadSettings = {
        defaultLocation: exportPolicy.settings.defaultLocation,
        askBeforeDownload: exportPolicy.settings.askBeforeDownload,
        allowCellularDownloads: exportPolicy.settings.allowCellularDownloads,
        autoResumeAfterRestart: exportPolicy.settings.autoResumeAfterRestart,
        autoClearPolicy: exportPolicy.settings.autoClearPolicy,
        privateFilePolicy: 'session_temp_only',
        privateRecordPolicy: exportPolicy.settings.privateRecordPolicy
      };
      await downloadPolicy.updateSettings(privateBoundary, tempOnlySettings);
      const tempOnlyPolicy: DownloadSavePolicy = downloadPolicy.resolveSavePolicy(privateBoundary);

      expect(exportPolicy.isPrivateSession).assertTrue();
      expect(exportPolicy.destinationMode).assertEqual('user_selected_location');
      expect(exportPolicy.reason).assertEqual('private_prompt_for_location');
      expect(exportPolicy.requiresConfirmation).assertTrue();
      expect(exportPolicy.privateRecordPolicy).assertEqual('keep_until_window_close');
      expect(tempOnlyPolicy.destinationMode).assertEqual('default_location');
      expect(tempOnlyPolicy.reason).assertEqual('private_session_temp_only');
      expect(tempOnlyPolicy.requiresConfirmation).assertFalse();
      expect(cleanupPolicy.shouldClearSessionRecordsOnWindowClose).assertTrue();
      expect(cleanupPolicy.shouldDeleteSessionTempFilesOnWindowClose).assertTrue();
      expect(downloadPolicy.canReadSessionTasks(privateBoundary)).assertTrue();
      expect(downloadPolicy.canWriteSessionTasks(privateBoundary)).assertTrue();
      expect(downloadPolicy.canExportFile(privateBoundary, true)).assertTrue();
      expect(downloadPolicy.canExportFile(privateBoundary, false)).assertFalse();
      expect(downloadPolicy.canCleanupSession(privateBoundary)).assertTrue();
    });

    it('isolates private Download tasks by the full requesting boundary', 0, () => {
      const query = new DownloadQueryService();
      const privateBoundary: DownloadTaskBoundary = {
        windowId: 'private-window-1',
        profileId: 'profile-main',
        privacyMode: 'private',
        dataScope: 'session_ephemeral'
      };
      const tasks: DownloadTaskQueryState[] = [
        buildTask('exact-private', 'private-window-1', 'private', 'session_ephemeral', 5),
        buildTask('other-private-window', 'private-window-2', 'private', 'session_ephemeral', 4),
        buildTask('missing-private-window', '', 'private', 'session_ephemeral', 3),
        buildTask('regular-task', 'private-window-1', 'regular', 'profile_persistent', 2),
        buildTask('scope-mismatch', 'private-window-1', 'private', 'profile_persistent', 1)
      ];

      const visibleTasks = query.listTasks({ tasks: tasks, boundary: privateBoundary });

      expect(visibleTasks.length).assertEqual(1);
      expect(visibleTasks[0].guid).assertEqual('exact-private');

      const regularBoundary: DownloadTaskBoundary = {
        windowId: 'regular-window-1',
        profileId: 'profile-main',
        privacyMode: 'regular',
        dataScope: 'profile_persistent'
      };
      const regularTasks: DownloadTaskQueryState[] = [
        buildTask('exact-regular', 'regular-window-1', 'regular', 'profile_persistent', 3),
        buildTask('legacy-regular-without-window', '', 'regular', 'profile_persistent', 2),
        buildTask('other-regular-window', 'regular-window-2', 'regular', 'profile_persistent', 1)
      ];
      const visibleRegularTasks = query.listTasks({ tasks: regularTasks, boundary: regularBoundary });

      expect(visibleRegularTasks.length).assertEqual(2);
      expect(visibleRegularTasks[0].guid).assertEqual('exact-regular');
      expect(visibleRegularTasks[1].guid).assertEqual('legacy-regular-without-window');
    });

    it('executes private export and window cleanup through the Download owner', 0, async () => {
      const preferencesRepository = new PreferencesRepository();
      const downloadPolicy = new DownloadPolicyService(preferencesRepository);
      const repository = new InMemoryDownloadV2Repository();
      const engine = new DownloadV2Engine(repository);
      const fileResolution = new FakeDownloadFileResolutionService();
      const downloadV2 = new DownloadV2Service(
        engine,
        undefined,
        repository,
        undefined,
        fileResolution,
        downloadPolicy
      );
      const runtime = new DownloadRuntimeService(undefined, downloadPolicy, downloadV2, fileResolution);
      const exportBoundary = buildPrivateBoundary('private-export-window');
      createCompletedTask(engine, 'private-export', exportBoundary, '/tmp/private-export.part');

      const exported = await runtime.saveTaskToSystemDownloadsForBoundary('private-export', exportBoundary);

      expect(exported).assertTrue();
      expect(fileResolution.exportedPaths.length).assertEqual(1);
      expect(fileResolution.exportedPaths[0]).assertEqual('/tmp/private-export.part');
      expect(downloadV2.findTask('private-export')?.persistence.finalFileUri)
        .assertEqual('file://system-downloads/private-export.bin');
      expect(fileResolution.deletedPaths.indexOf('/tmp/private-export.part') >= 0).assertTrue();

      const cleanupBoundary = buildPrivateBoundary('private-cleanup-window');
      const otherBoundary = buildPrivateBoundary('private-other-window');
      createCompletedTask(engine, 'private-cleanup', cleanupBoundary, '/tmp/private-cleanup.part');
      createCompletedTask(engine, 'private-other', otherBoundary, '/tmp/private-other.part');

      const removedCount = runtime.clearPrivateDownloadSessionForWindow('private-cleanup-window');

      expect(removedCount).assertEqual(1);
      expect(downloadV2.findTask('private-cleanup') === undefined).assertTrue();
      expect(downloadV2.findTask('private-other') !== undefined).assertTrue();
      expect(fileResolution.deletedPaths.indexOf('/tmp/private-cleanup.part') >= 0).assertTrue();
    });
  });
}

class FakeDownloadFileResolutionService implements DownloadFileResolutionAdapter {
  exportedPaths: string[] = [];
  deletedPaths: string[] = [];

  async resolveTemporaryTarget(
    _suggestedFileName: string,
    _now?: number
  ): Promise<DownloadTemporaryTargetPlan | undefined> {
    return undefined;
  }

  sanitizeFileName(fileName: string): string {
    return fileName;
  }

  resolveUriFromLocalPath(path: string): string {
    return `file://${path}`;
  }

  async persistToSystemDownloads(
    localPath: string,
    _suggestedFileName: string
  ): Promise<DownloadPersistResult | undefined> {
    this.exportedPaths.push(localPath);
    return {
      status: 'exported',
      finalFileUri: 'file://system-downloads/private-export.bin',
      finalDisplayPath: 'Download/private-export.bin',
      isExported: true
    };
  }

  async deleteLocalPath(path: string): Promise<DownloadLocalDeleteResult> {
    this.deletedPaths.push(path);
    return 'deleted';
  }

  async movePublicDocumentToTrash(_uri: string): Promise<DownloadLocalDeleteResult> {
    return 'deleted';
  }
}

function buildPrivateBoundary(windowId: string): DownloadTaskBoundary {
  return {
    windowId: windowId,
    profileId: 'profile-main',
    privacyMode: 'private',
    dataScope: 'session_ephemeral'
  };
}

function createCompletedTask(
  engine: DownloadV2Engine,
  guid: string,
  boundary: DownloadTaskBoundary,
  tempFilePath: string
): void {
  engine.createTask({
    guid: guid,
    suggestedFileName: `${guid}.bin`,
    request: {
      url: `https://example.com/${guid}.bin`,
      method: 'GET'
    },
    boundary: createDownloadV2BoundarySnapshot(
      boundary.profileId,
      boundary.privacyMode,
      boundary.dataScope,
      boundary.windowId
    ),
    requiresConfirmation: false
  });
  engine.synchronizeTask(guid, {
    status: 'completed',
    progress: {
      totalBytes: 16,
      receivedBytes: 16,
      speedBytesPerSecond: 0
    },
    persistence: {
      tempFilePath: tempFilePath,
      partialFilePath: tempFilePath,
      writtenBytes: 16
    },
    timing: {
      completedAt: 1,
      updatedAt: 1
    }
  });
}

function buildTask(
  guid: string,
  windowId: string,
  privacyMode: string,
  dataScope: string,
  updatedAt: number
): DownloadTaskQueryState {
  return {
    id: `task-${guid}`,
    guid: guid,
    status: 'completed',
    riskLevel: 'safe',
    createdAt: updatedAt,
    updatedAt: updatedAt,
    windowId: windowId,
    profileId: 'profile-main',
    privacyMode: privacyMode,
    dataScope: dataScope
  };
}
