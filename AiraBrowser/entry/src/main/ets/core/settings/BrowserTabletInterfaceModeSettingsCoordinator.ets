import { BrowserDataBoundaryInput } from '../../common/models/BrowserModels';
import { BrowserTabletInterfaceMode } from '../../common/models/BrowserDevicePresentationModels';
import { BrowserTabletInterfaceModeRepository } from '../../data/preferences/BrowserTabletInterfaceModeRepository';
import {
  BrowserDeviceFormFactor,
  BrowserDeviceFormFactorCoordinator
} from '../browser/BrowserDeviceFormFactorCoordinator';
import { BrowserTabletInterfaceModePolicy } from '../browser/BrowserTabletInterfaceModePolicy';
import { BrowserWindowPresentationProfileInputService } from '../../services/browser/BrowserWindowPresentationProfileInputService';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';
import {
  BrowserTabletInterfaceModeTransitionConsumer,
  sharedBrowserTabletInterfaceModeTransitionOwner
} from './BrowserTabletInterfaceModeTransitionOwner';

export interface BrowserTabletInterfaceModeOptionState {
  mode: BrowserTabletInterfaceMode;
  title: string;
}

export interface BrowserTabletInterfaceModeSettingsState {
  visible: boolean;
  detectedFormFactor: BrowserDeviceFormFactor;
  selectedMode: BrowserTabletInterfaceMode;
  selectedLabel: string;
  options: BrowserTabletInterfaceModeOptionState[];
  footerText: string;
}

export class BrowserTabletInterfaceModeSettingsCoordinator {
  private readonly repository: BrowserTabletInterfaceModeRepository;
  private readonly privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private readonly profileBoundaryService: BrowserProfileBoundaryService;
  private readonly deviceFormFactorCoordinator: BrowserDeviceFormFactorCoordinator =
    new BrowserDeviceFormFactorCoordinator();
  private readonly interfaceModePolicy: BrowserTabletInterfaceModePolicy =
    new BrowserTabletInterfaceModePolicy();
  private readonly presentationInputService: BrowserWindowPresentationProfileInputService =
    new BrowserWindowPresentationProfileInputService();

  constructor(
    repository: BrowserTabletInterfaceModeRepository,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()
  ) {
    this.repository = repository;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
  }

  buildState(): BrowserTabletInterfaceModeSettingsState {
    return this.buildStateForMode(this.repository.getMode());
  }

  buildStateForMode(mode: BrowserTabletInterfaceMode): BrowserTabletInterfaceModeSettingsState {
    const detectedFormFactor = this.resolveDetectedFormFactor();
    const foldableDevice = this.presentationInputService.resolveFoldableDevice();
    const selectedMode = this.resolveSelectedModeForDevice(mode, detectedFormFactor, foldableDevice);
    return {
      visible: this.isSettingVisible(detectedFormFactor, mode),
      detectedFormFactor: detectedFormFactor,
      selectedMode: selectedMode,
      selectedLabel: this.resolveLabel(selectedMode),
      options: this.resolveOptions(detectedFormFactor, foldableDevice),
      footerText: this.resolveFooterText(detectedFormFactor, foldableDevice)
    };
  }

  setMode(
    mode: BrowserTabletInterfaceMode,
    boundaryInput: BrowserDataBoundaryInput,
    consumer: BrowserTabletInterfaceModeTransitionConsumer = 'phone_native_settings_handoff'
  ): Promise<BrowserTabletInterfaceModeSettingsState> {
    if (!this.canWriteDevicePreference(boundaryInput)) {
      return Promise.reject(new Error('Tablet interface mode device preference write privacy effect was not allowed.'));
    }
    if (this.repository.getMode() === mode) {
      return Promise.resolve(this.buildStateForMode(mode));
    }
    const transitionId = sharedBrowserTabletInterfaceModeTransitionOwner.begin(mode, consumer);
    return this.repository.setMode(mode)
      .then((savedMode: BrowserTabletInterfaceMode): BrowserTabletInterfaceModeSettingsState => {
        return this.buildStateForMode(savedMode);
      })
      .catch((error: Error): BrowserTabletInterfaceModeSettingsState => {
        sharedBrowserTabletInterfaceModeTransitionOwner.cancel(transitionId);
        throw error;
      });
  }

  requiresDesktopModeConfirmation(mode: BrowserTabletInterfaceMode): boolean {
    return mode === 'desktop' && this.resolveDetectedFormFactor() === 'phone' &&
      !this.presentationInputService.resolveFoldableDevice();
  }

  private resolveDetectedFormFactor(): BrowserDeviceFormFactor {
    // Device type is the primary signal; when the platform reports an
    // unrecognized type (notably emulators, which report "default"), fall back
    // to the display width — a screen ≥ 840vp is treated as a tablet. Mirrors
    // the large-screen shell eligibility (resolveShellEligibility) so this
    // setting stays in sync with the shell that actually switches modes.
    return this.deviceFormFactorCoordinator.resolveShellEligibility({
      platformDeviceType: this.presentationInputService.resolvePlatformDeviceType(),
      windowWidthVp: this.presentationInputService.resolveDisplayWidthVp()
    }).detectedFormFactor;
  }

  private isSettingVisible(
    detectedFormFactor: BrowserDeviceFormFactor,
    mode: BrowserTabletInterfaceMode
  ): boolean {
    return this.interfaceModePolicy.resolve({
      detectedFormFactor: detectedFormFactor,
      selectedMode: mode,
      pointerAvailable: false,
      foldState: 'unknown'
    }).settingVisible;
  }

  private resolveLabel(mode: BrowserTabletInterfaceMode): string {
    if (mode === 'touch') {
      return '触屏界面';
    }
    if (mode === 'desktop') {
      return '桌面界面';
    }
    return '自动';
  }

  private resolveSelectedModeForDevice(
    mode: BrowserTabletInterfaceMode,
    detectedFormFactor: BrowserDeviceFormFactor,
    foldableDevice: boolean
  ): BrowserTabletInterfaceMode {
    if (detectedFormFactor === 'phone' && !foldableDevice && mode === 'auto') {
      return 'touch';
    }
    return mode;
  }

  private resolveOptions(
    detectedFormFactor: BrowserDeviceFormFactor,
    foldableDevice: boolean
  ): BrowserTabletInterfaceModeOptionState[] {
    if (detectedFormFactor === 'phone' && !foldableDevice) {
      return [
        { mode: 'touch', title: '触屏界面' },
        { mode: 'desktop', title: '桌面界面' }
      ];
    }
    return [
      { mode: 'auto', title: '自动' },
      { mode: 'touch', title: '触屏界面' },
      { mode: 'desktop', title: '桌面界面' }
    ];
  }

  private resolveFooterText(
    detectedFormFactor: BrowserDeviceFormFactor,
    foldableDevice: boolean
  ): string {
    if (detectedFormFactor === 'phone' && !foldableDevice) {
      return '手机使用桌面界面可能出现内容过密、按钮过小或部分布局不适配。切换到桌面界面前需要再次确认。';
    }
    if (foldableDevice) {
      return '自动模式会在设备展开时使用桌面界面，收起时恢复触屏界面；半折叠或状态未知时保持当前界面。';
    }
    return '自动模式会在连接鼠标或触控板时使用桌面界面，断开后恢复触屏界面。物理键盘仍可在触屏界面中使用快捷键。';
  }

  private canWriteDevicePreference(boundaryInput: BrowserDataBoundaryInput): boolean {
    return this.privacyEffectPolicy.decide({
      intent: 'settings_device_preference_write',
      requestingBoundary: this.profileBoundaryService.buildBoundary(boundaryInput),
      targetScope: 'device_preferences',
      targetIsClear: true
    }).outcome === 'allow';
  }
}
