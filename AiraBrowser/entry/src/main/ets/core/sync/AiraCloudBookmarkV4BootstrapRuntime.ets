import { common } from '@kit.AbilityKit';
import { AiraSyncSettings } from '../../common/models/AiraSyncModels';
import { AiraMembershipState } from '../../common/models/MembershipModels';
import { AiraCloudBookmarkV4BootstrapRecord } from '../../common/models/AiraCloudBookmarkV4BootstrapModels';
import { BrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import { LocalBackupSelection } from '../../features/backup/LocalBackupModels';
import { LocalBackupCoordinator } from '../backup/LocalBackupCoordinator';
import { AiraCloudBookmarkV4BootstrapStateStore } from '../../data/sync/AiraCloudBookmarkV4BootstrapStateStore';
import { MembershipFeature } from '../../features/membership/MembershipFeature';
import { SyncService } from '../../services/sync/SyncService';
import { AiraCloudBookmarkV4BootstrapCoordinator } from './AiraCloudBookmarkV4BootstrapCoordinator';
import { AiraCloudBookmarkV4BootstrapPolicyService } from './AiraCloudBookmarkV4BootstrapPolicyService';
import {
  AiraCloudBookmarkV4BootstrapViewModelService,
  AiraCloudBookmarkV4BootstrapViewState
} from './AiraCloudBookmarkV4BootstrapViewModelService';

export const AIRA_CLOUD_BOOKMARK_V4_BOOTSTRAP_REVISION_KEY: string =
  'aira.cloud.bookmark.v4.bootstrap.revision';

const AIRA_CLOUD_V4_BOOKMARK_BACKUP_SELECTION: LocalBackupSelection = {
  bookmarks: true,
  history: false,
  personalization: false,
  userScripts: false,
  userScriptValues: false
};

const AIRA_CLOUD_V4_BOOKMARK_BACKUP_BOUNDARY: BrowserBoundaryRouteState = {
  dataScope: '',
  privacyMode: '',
  boundarySource: 'aira_cloud_v4_bootstrap'
};

export class AiraCloudBookmarkV4BootstrapRuntime {
  private readonly syncService: SyncService;
  private readonly membershipFeature: MembershipFeature;
  private readonly stateStore: AiraCloudBookmarkV4BootstrapStateStore;
  private readonly coordinator: AiraCloudBookmarkV4BootstrapCoordinator;
  private readonly localBackupCoordinator: LocalBackupCoordinator;
  private readonly policy: AiraCloudBookmarkV4BootstrapPolicyService =
    new AiraCloudBookmarkV4BootstrapPolicyService();
  private readonly viewModel: AiraCloudBookmarkV4BootstrapViewModelService =
    new AiraCloudBookmarkV4BootstrapViewModelService();
  private viewState: AiraCloudBookmarkV4BootstrapViewState = this.hiddenState();
  private record?: AiraCloudBookmarkV4BootstrapRecord;
  private initialized: boolean = false;
  private operationRunning: boolean = false;
  private reconcileTask: Promise<void> = Promise.resolve();

  constructor(
    syncService: SyncService,
    membershipFeature: MembershipFeature,
    stateStore: AiraCloudBookmarkV4BootstrapStateStore,
    coordinator: AiraCloudBookmarkV4BootstrapCoordinator,
    localBackupCoordinator: LocalBackupCoordinator
  ) {
    this.syncService = syncService;
    this.membershipFeature = membershipFeature;
    this.stateStore = stateStore;
    this.coordinator = coordinator;
    this.localBackupCoordinator = localBackupCoordinator;
    AppStorage.setOrCreate(AIRA_CLOUD_BOOKMARK_V4_BOOTSTRAP_REVISION_KEY, 0);
  }

  initialize(): Promise<void> {
    return this.reconcile();
  }

  reconcile(): Promise<void> {
    const next = this.reconcileTask.then(
      (): Promise<void> => this.reconcileNow(),
      (): Promise<void> => this.reconcileNow()
    );
    this.reconcileTask = next.catch((): void => {});
    return next;
  }

  getViewState(): AiraCloudBookmarkV4BootstrapViewState {
    return {
      visible: this.viewState.visible,
      status: this.viewState.status,
      primaryAction: this.viewState.primaryAction,
      recoveryAvailable: this.viewState.recoveryAvailable,
      uid: this.viewState.uid,
      errorMessage: this.viewState.errorMessage
    };
  }

  isAutomaticBookmarkSyncAllowed(): boolean {
    if (this.operationRunning) {
      return false;
    }
    const settings = this.syncService.getAiraSyncSettings();
    const membership = this.membershipFeature.getState();
    const decision = this.policy.evaluate(settings, membership, this.record);
    if (!this.initialized && this.isPotentialLegacyCandidate(settings, membership)) {
      return false;
    }
    return !decision.required;
  }

  hasRecoveryPoint(): boolean {
    return this.record !== undefined && this.record.status !== 'opted_out' &&
      this.record.backupId.length > 0 && this.record.backupSha256.length > 0;
  }

  async start(context: common.UIAbilityContext): Promise<void> {
    const uid = this.viewState.uid.trim();
    if (uid.length === 0 || this.viewState.status === 'running') {
      return;
    }
    const exportOutcome = await this.localBackupCoordinator.exportBackup(
      context,
      AIRA_CLOUD_V4_BOOKMARK_BACKUP_SELECTION,
      AIRA_CLOUD_V4_BOOKMARK_BACKUP_BOUNDARY
    );
    if (exportOutcome.status === 'cancelled') {
      return;
    }
    if (exportOutcome.status === 'failed') {
      this.publishFailure(uid, new Error(exportOutcome.message));
      this.bump();
      return;
    }
    this.publishRunning(uid);
    try {
      const record = await this.coordinator.run(uid);
      this.record = record;
      this.viewState = this.viewModel.fromRecord(record);
    } catch (error) {
      this.publishFailure(uid, error as Error);
    } finally {
      this.operationRunning = false;
      this.bump();
    }
  }

  async acknowledgeNativeV4Activation(uid: string, commitId: string): Promise<void> {
    this.record = await this.coordinator.acknowledgeNativeV4Activation(uid, commitId);
    await this.reconcile();
  }

  async restoreBackupAndDisable(): Promise<void> {
    const uid = this.viewState.uid.trim();
    const recordUid = this.record?.uid.trim() ?? '';
    const targetUid = uid.length > 0 ? uid : recordUid;
    if (targetUid.length === 0 || this.viewState.status === 'running' || !this.hasRecoveryPoint()) {
      return;
    }
    this.publishRunning(targetUid);
    try {
      const record = await this.coordinator.restoreBackupAndDisable(targetUid);
      this.record = record;
      this.viewState = this.viewModel.fromRecord(record);
    } catch (error) {
      this.publishFailure(targetUid, error as Error);
    } finally {
      this.operationRunning = false;
      this.bump();
    }
  }

  private async reconcileNow(): Promise<void> {
    const settings = await this.syncService.initializeAiraSyncSettings();
    const membership = await this.membershipFeature.loadState();
    const uid = settings.huaweiCloud.uid.trim();
    this.record = uid.length > 0 ? await this.stateStore.load(uid) : undefined;
    const decision = this.policy.evaluate(settings, membership, this.record);
    this.initialized = true;
    if (!decision.required) {
      this.viewState = this.hiddenState();
    } else if (this.record?.status === 'failed') {
      this.viewState = this.viewModel.fromRecord(this.record);
    } else {
      this.viewState = this.viewModel.required(decision.uid);
    }
    this.bump();
  }

  private isPotentialLegacyCandidate(settings: AiraSyncSettings,
    membership: AiraMembershipState): boolean {
    return this.policy.evaluate(settings, membership, this.record).required;
  }

  private hiddenState(): AiraCloudBookmarkV4BootstrapViewState {
    return {
      visible: false,
      status: 'hidden',
      primaryAction: 'none',
      recoveryAvailable: false,
      uid: '',
      errorMessage: ''
    };
  }

  private publishRunning(uid: string): void {
    this.operationRunning = true;
    this.viewState = {
      visible: true,
      status: 'running',
      primaryAction: 'none',
      recoveryAvailable: false,
      uid: uid,
      errorMessage: ''
    };
    this.bump();
  }

  private publishFailure(uid: string, error: Error): void {
    this.viewState = {
      visible: true,
      status: 'failed',
      primaryAction: 'retry',
      recoveryAvailable: this.hasRecoveryPoint(),
      uid: uid,
      errorMessage: error.message.length > 0 ? error.message : '操作失败，请稍后重试。'
    };
  }

  private bump(): void {
    const revision = AppStorage.get<number>(AIRA_CLOUD_BOOKMARK_V4_BOOTSTRAP_REVISION_KEY) ?? 0;
    AppStorage.setOrCreate(AIRA_CLOUD_BOOKMARK_V4_BOOTSTRAP_REVISION_KEY, revision + 1);
  }
}
