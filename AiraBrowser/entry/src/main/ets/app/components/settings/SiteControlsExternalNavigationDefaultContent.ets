import { ExternalNavigationAppOpenPolicy } from '../../../common/models/BrowserModels';
import { SettingsExternalNavigationCoordinator } from '../../../core/settings/SettingsExternalNavigationCoordinator';
import { sharedPreferencesRepository } from '../../bootstrap/BrowserAppRuntime';
import { SettingsFooterText, SettingsGroupCard, SettingsGroupDivider } from './SettingsLayout';
import { SettingsOptionRow } from './SettingsRows';

interface SiteControlsExternalNavigationDefaultOption {
  value: ExternalNavigationAppOpenPolicy;
  label: string;
}

@Component
export struct SiteControlsExternalNavigationDefaultContent {
  private readonly coordinator: SettingsExternalNavigationCoordinator =
    new SettingsExternalNavigationCoordinator(sharedPreferencesRepository);
  @Prop surfaceBackground: ResourceColor = '';
  @Prop dividerColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop accentColor: ResourceColor = '';
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop desktopPresentation: boolean = false;
  @State private selectedPolicy: ExternalNavigationAppOpenPolicy =
    sharedPreferencesRepository.getPreferences().externalNavigation.appOpenPolicy;
  @State private isSelectingOption: boolean = false;
  onPolicyApplied?: () => void;

  aboutToAppear(): void {
    this.isSelectingOption = false;
    this.refreshState();
  }

  build() {
    Column({ space: 10 }) {
      SettingsGroupCard({
        surfaceColor: this.surfaceBackground,
        desktopPresentation: this.desktopPresentation
      }) {
        ForEach(this.buildOptions(), (option: SiteControlsExternalNavigationDefaultOption, index: number) => {
          SettingsOptionRow({
            title: option.label,
            desktopPresentation: this.desktopPresentation,
            rowPosition: this.resolveRowPosition(index, this.buildOptions().length),
            isSelected: option.value === this.selectedPolicy,
            isEnabled: !this.isSelectingOption,
            selectedIndicatorColor: this.accentColor,
            radioGroup: 'site-controls-external-navigation-default',
            radioValue: option.value,
            onAction: (): void => {
              this.requestSelectPolicy(option.value);
            }
          })
          if (index < this.buildOptions().length - 1) {
            SettingsGroupDivider({ dividerColor: this.dividerColor })
          }
        }, (option: SiteControlsExternalNavigationDefaultOption): string =>
          `${option.value}:${option.value === this.selectedPolicy ? 'selected' : 'idle'}:` +
            `${this.isSelectingOption ? 'saving' : 'ready'}`)
      }

      SettingsFooterText({
        text: '控制网站尝试打开其他应用时，是先询问、直接允许，还是始终阻止。',
        secondaryTextColor: this.secondaryTextColor
      })
    }
    .width('100%')
  }

  private requestSelectPolicy(policy: ExternalNavigationAppOpenPolicy): void {
    if (this.isSelectingOption) {
      return;
    }
    if (policy === this.selectedPolicy) {
      this.onPolicyApplied?.();
      return;
    }
    this.isSelectingOption = true;
    this.coordinator.setAppOpenPolicy(policy, {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    })
      .then((): void => {
        this.isSelectingOption = false;
        this.refreshState();
        this.onPolicyApplied?.();
      })
      .catch((_error: Error): void => {
        this.isSelectingOption = false;
        this.refreshState();
      });
  }

  private refreshState(): void {
    this.selectedPolicy = sharedPreferencesRepository.getPreferences().externalNavigation.appOpenPolicy;
  }

  private buildOptions(): SiteControlsExternalNavigationDefaultOption[] {
    return [
      { value: 'ask', label: '跳转前询问' },
      { value: 'allow', label: '始终允许' },
      { value: 'block', label: '阻止' }
    ];
  }

  private resolveRowPosition(index: number, total: number): 'single' | 'first' | 'middle' | 'last' {
    if (total <= 1) {
      return 'single';
    }
    if (index === 0) {
      return 'first';
    }
    if (index === total - 1) {
      return 'last';
    }
    return 'middle';
  }
}
