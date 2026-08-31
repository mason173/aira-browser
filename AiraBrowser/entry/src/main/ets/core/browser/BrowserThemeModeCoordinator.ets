import { ConfigurationConstant } from '@kit.AbilityKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  BrowserDataScope,
  BrowserResolvedThemeMode,
  BrowserSessionPrivacyMode,
  BrowserThemeMode,
  normalizeBrowserDataScope,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from './BrowserProfileBoundaryService';

export interface BrowserThemeModeBoundary {
  privacyMode?: BrowserSessionPrivacyMode | string;
  dataScope?: BrowserDataScope | string;
}

export interface BrowserThemeModeMutationResult {
  allowed: boolean;
  mode: BrowserThemeMode;
  message: string;
}

export class BrowserThemeModeCoordinator {
  private static resolvedSystemThemeMode?: BrowserResolvedThemeMode;
  private preferencesRepository: PreferencesRepository;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;

  constructor(
    preferencesRepository: PreferencesRepository,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()
  ) {
    this.preferencesRepository = preferencesRepository;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
  }

  resolveCurrentMode(): BrowserThemeMode {
    return this.preferencesRepository.getPreferences().themeMode;
  }

  resolveEffectiveMode(mode: BrowserThemeMode = this.resolveCurrentMode()): BrowserResolvedThemeMode {
    if (mode === 'light' || mode === 'dark') {
      return mode;
    }
    if (BrowserThemeModeCoordinator.resolvedSystemThemeMode !== undefined) {
      return BrowserThemeModeCoordinator.resolvedSystemThemeMode;
    }
    const colorMode = AppRuntimeContext.getUIAbilityContext().config.colorMode;
    return this.resolveColorMode(colorMode);
  }

  syncSystemColorMode(colorMode: ConfigurationConstant.ColorMode | undefined): BrowserResolvedThemeMode {
    const resolvedMode = this.resolveColorMode(colorMode);
    BrowserThemeModeCoordinator.resolvedSystemThemeMode = resolvedMode;
    return resolvedMode;
  }

  resolveMenuTitle(mode: BrowserThemeMode = this.resolveCurrentMode()): string {
    if (mode === 'light') {
      return '浅色模式';
    }
    if (mode === 'dark') {
      return '深色模式';
    }
    return '跟随系统';
  }

  resolveMenuIcon(mode: BrowserThemeMode = this.resolveCurrentMode()): Resource {
    if (mode === 'light') {
      return $r('sys.symbol.sun_max_fill');
    }
    if (mode === 'dark') {
      return $r('sys.symbol.moon_fill');
    }
    return $r('sys.symbol.square_fill_grid_2x2');
  }

  resolveNextMode(mode: BrowserThemeMode = this.resolveCurrentMode()): BrowserThemeMode {
    if (mode === 'light') {
      return 'dark';
    }
    if (mode === 'dark') {
      return 'system';
    }
    return 'light';
  }

  async toggleThemeMode(): Promise<BrowserThemeMode> {
    const nextMode = this.resolveNextMode();
    return this.setThemeMode(nextMode);
  }

  async setThemeMode(mode: BrowserThemeMode): Promise<BrowserThemeMode> {
    const normalizedMode = this.preferencesRepository.normalizeThemeModeForPersistence(mode);
    await this.preferencesRepository.updateThemeMode(normalizedMode);
    this.applyThemeMode(normalizedMode);
    return normalizedMode;
  }

  async setThemeModeForBoundary(
    mode: BrowserThemeMode,
    boundary: BrowserThemeModeBoundary
  ): Promise<BrowserThemeModeMutationResult> {
    const privacyMode = normalizeBrowserSessionPrivacyMode(boundary.privacyMode);
    const dataScope = normalizeBrowserDataScope(boundary.dataScope, privacyMode);
    const decision = this.privacyEffectPolicy.decide({
      intent: 'settings_device_preference_write',
      requestingBoundary: this.profileBoundaryService.buildBoundary({
        dataScope: dataScope,
        privacyMode: privacyMode
      }),
      targetScope: 'device_preferences',
      targetIsClear: true
    });
    if (decision.outcome !== 'allow') {
      return {
        allowed: false,
        mode: this.resolveCurrentMode(),
        message: '当前会话不可修改全局外观偏好。'
      };
    }
    const nextMode = await this.setThemeMode(mode);
    return {
      allowed: true,
      mode: nextMode,
      message: '外观模式已更新。'
    };
  }

  applyThemeMode(mode: BrowserThemeMode): void {
    const applicationContext = AppRuntimeContext.getApplicationContext();
    const colorMode = mode === 'dark'
      ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      : mode === 'light'
        ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
        : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    applicationContext.setColorMode(colorMode);
  }

  private resolveColorMode(colorMode: ConfigurationConstant.ColorMode | undefined): BrowserResolvedThemeMode {
    return colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? 'dark' : 'light';
  }
}
