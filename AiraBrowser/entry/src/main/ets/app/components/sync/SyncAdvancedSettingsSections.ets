import { AiraSyncRemoteKind } from '../../../common/models/AiraSyncModels';
import {
  SyncAdvancedProviderActionState,
  SyncAdvancedSettingsViewModel
} from '../../../core/sync/SyncAdvancedSettingsViewModel';
import { SettingsActionButton } from '../settings/SettingsRows';
import { SettingsSection } from '../settings/SettingsLayout';

@Component
export struct SyncAdvancedOperationsSection {
  @Prop mergeActionLabel: string = '立即合并同步';
  @Prop actionState: SyncAdvancedProviderActionState = {
    showHuaweiCloud: false,
    showHuaweiSpace: false,
    showWebdav: false,
    mergeRequiresPro: false
  };
  @Prop isBusy: boolean = false;
  @Prop isPrivateSession: boolean = false;
  @Prop accentColor: ResourceColor = '';
  @Prop pressedBackgroundColor: ResourceColor = '';
  private viewModel: SyncAdvancedSettingsViewModel = new SyncAdvancedSettingsViewModel();
  onMerge?: () => void;
  onCheckProvider?: (remoteKind: AiraSyncRemoteKind) => void;

  build() {
    Column({ space: 16 }) {
      SettingsSection({ title: '合并同步' }) {
        this.buildActionButton(this.mergeActionLabel, () => {
          this.onMerge?.();
        }, this.actionState.mergeRequiresPro)
      }
      if (this.actionState.showHuaweiCloud) {
        this.buildProviderOperationSection('aira_cloud')
      }
      if (this.actionState.showHuaweiSpace) {
        this.buildProviderOperationSection('huawei_space')
      }
      if (this.actionState.showWebdav) {
        this.buildProviderOperationSection('webdav')
      }
    }
    .width('100%')
  }

  @Builder
  private buildProviderOperationSection(remoteKind: AiraSyncRemoteKind) {
    SettingsSection({ title: this.resolveProviderSectionTitle(remoteKind) }) {
      this.buildActionButton(this.viewModel.resolveProviderCheckActionLabel(remoteKind), () => {
        this.onCheckProvider?.(remoteKind);
      })
    }
  }

  @Builder
  private buildActionButton(
    label: string,
    action: () => void,
    requiresPro: boolean = false
  ) {
    SettingsActionButton({
      title: label,
      emphasis: 'primary',
      isEnabled: !this.isBusy && !this.isPrivateSession,
      membershipBadge: requiresPro ? 'pro' : 'none',
      accentColor: this.accentColor,
      pressedBackgroundColor: this.pressedBackgroundColor,
      onAction: action
    })
  }

  private resolveProviderSectionTitle(remoteKind: AiraSyncRemoteKind): string {
    return remoteKind === 'aira_cloud'
      ? 'Aira 云同步'
      : this.viewModel.resolveProviderServiceName(remoteKind);
  }
}

@Component
export struct SyncAdvancedProviderSelectionSection {
  @Prop actionState: SyncAdvancedProviderActionState = {
    showHuaweiCloud: false,
    showHuaweiSpace: false,
    showWebdav: false,
    mergeRequiresPro: false
  };
  @Prop activeRemoteKind: AiraSyncRemoteKind = 'none';
  @Prop isBusy: boolean = false;
  @Prop isPrivateSession: boolean = false;
  @Prop accentColor: ResourceColor = '';
  @Prop pressedBackgroundColor: ResourceColor = '';
  onSelectProvider?: (remoteKind: AiraSyncRemoteKind) => void;

  build() {
    Column() {
      if (this.countConfiguredProviders() > 1) {
        SettingsSection({ title: '当前同步方式' }) {
          if (this.actionState.showHuaweiSpace) {
            this.buildProviderSwitchButtons('huawei_space')
          }
          if (this.actionState.showWebdav) {
            this.buildProviderSwitchButtons('webdav')
          }
          if (this.actionState.showHuaweiCloud) {
            this.buildProviderSwitchButtons('aira_cloud')
          }
        }
      }
    }
    .width('100%')
  }

  @Builder
  private buildActionButton(
    label: string,
    remoteKind: AiraSyncRemoteKind
  ) {
    SettingsActionButton({
      title: this.activeRemoteKind === remoteKind ? `${label}（当前）` : label,
      emphasis: 'primary',
      isEnabled: !this.isBusy && !this.isPrivateSession && this.activeRemoteKind !== remoteKind,
      accentColor: this.accentColor,
      pressedBackgroundColor: this.pressedBackgroundColor,
      onAction: () => {
        this.onSelectProvider?.(remoteKind);
      }
    })
  }

  @Builder
  private buildProviderSwitchButtons(remoteKind: AiraSyncRemoteKind) {
    this.buildActionButton(`改用${this.resolveProviderLabel(remoteKind)}`, remoteKind)
  }

  private countConfiguredProviders(): number {
    let count = 0;
    if (this.actionState.showHuaweiCloud) {
      count++;
    }
    if (this.actionState.showHuaweiSpace) {
      count++;
    }
    if (this.actionState.showWebdav) {
      count++;
    }
    return count;
  }

  private resolveProviderLabel(remoteKind: AiraSyncRemoteKind): string {
    if (remoteKind === 'aira_cloud') {
      return 'Aira 云同步';
    }
    if (remoteKind === 'huawei_space') {
      return '华为云空间';
    }
    return 'WebDAV';
  }
}
