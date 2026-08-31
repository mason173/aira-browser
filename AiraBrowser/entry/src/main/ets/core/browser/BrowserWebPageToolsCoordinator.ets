import {
  BrowserUserAgentPresetId,
  SitePermissionKind,
  SitePermissionRule
} from '../../common/models/BrowserModels';
import { BrowserDesktopSiteMode } from '../../services/web/BrowserUserAgentService';
import { BrowserScreenOrientationMode } from './BrowserScreenOrientationViewModel';
import {
  BrowserSiteControlsRuntimeCoordinator,
  BrowserSiteControlsUserAction
} from './BrowserSiteControlsRuntimeCoordinator';
import {
  BrowserTransientSurfaceCoordinator,
  BrowserTransientSurfaceUpdate
} from './BrowserTransientSurfaceCoordinator';

export type BrowserWebPageToolsSheetType =
  'none' |
  'screenOrientation' |
  'desktopSiteMode' |
  'userAgentPreset' |
  'siteInfo';

export interface BrowserWebPageToolsSnapshot {
  type: BrowserWebPageToolsSheetType;
}

export interface BrowserWebPageToolsPresentationConfig {
  revealDelayMs: number;
  dismissDurationMs: number;
  useNativeSystemSheet: () => boolean;
}

export interface BrowserWebPageToolsOverlayAction {
  type: 'dismiss' |
    'navigate_back' |
    'select_screen_orientation' |
    'select_desktop_site_mode' |
    'open_default_user_agent' |
    'select_user_agent_preset' |
    'select_custom_user_agent' |
    'site_controls';
  screenOrientationMode?: BrowserScreenOrientationMode;
  desktopSiteMode?: BrowserDesktopSiteMode;
  presetId?: BrowserUserAgentPresetId;
  recordId?: string;
  siteControlsAction?: BrowserSiteControlsUserAction;
  permissionKind?: SitePermissionKind;
  permissionRule?: SitePermissionRule;
}

interface BrowserWebPageToolsFullscreenActionOwner {
  applyScreenOrientationMode(mode: BrowserScreenOrientationMode): Promise<void>;
}

interface BrowserWebPageToolsUserAgentActionOwner {
  selectDesktopSiteMode(mode: BrowserDesktopSiteMode): void;
  openUserAgentPresetSheet(replaceCurrentSheet?: boolean): void;
  selectUserAgentPreset(presetId: BrowserUserAgentPresetId): void;
  selectCustomUserAgent(recordId: string): void;
}

export interface BrowserWebPageToolsActionDependencies {
  resolveFullscreenActionOwner: () => BrowserWebPageToolsFullscreenActionOwner;
  resolveUserAgentActionOwner: () => BrowserWebPageToolsUserAgentActionOwner;
}

export class BrowserWebPageToolsCoordinator {
  private readonly transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator;
  private readonly siteControlsCoordinator: BrowserSiteControlsRuntimeCoordinator;
  private readonly actionDependencies: BrowserWebPageToolsActionDependencies;
  private readonly publishSnapshot: (snapshot: BrowserWebPageToolsSnapshot) => void;
  private readonly presentationConfig: BrowserWebPageToolsPresentationConfig;
  private currentSnapshot: BrowserWebPageToolsSnapshot = {
    type: 'none'
  };
  private returnSheetType: BrowserWebPageToolsSheetType = 'none';

  constructor(
    transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator,
    siteControlsCoordinator: BrowserSiteControlsRuntimeCoordinator,
    actionDependencies: BrowserWebPageToolsActionDependencies,
    publishSnapshot: (snapshot: BrowserWebPageToolsSnapshot) => void,
    presentationConfig: BrowserWebPageToolsPresentationConfig
  ) {
    this.transientSurfaceCoordinator = transientSurfaceCoordinator;
    this.siteControlsCoordinator = siteControlsCoordinator;
    this.actionDependencies = actionDependencies;
    this.publishSnapshot = publishSnapshot;
    this.presentationConfig = presentationConfig;
    this.siteControlsCoordinator.bindPageToolsSurface(this);
  }

  snapshot(): BrowserWebPageToolsSnapshot {
    return this.currentSnapshot;
  }

  isActive(type: BrowserWebPageToolsSheetType): boolean {
    return this.currentSnapshot.type === type;
  }

  open(type: BrowserWebPageToolsSheetType, replaceCurrentSheet: boolean = false): void {
    if (type === 'none') {
      return;
    }
    this.returnSheetType = replaceCurrentSheet ? this.currentSnapshot.type : 'none';
    this.updateSnapshot(type);
    if (replaceCurrentSheet) {
      return;
    }
    this.transientSurfaceCoordinator.present({
      id: 'web_page_tools',
      revealDelayMs: this.presentationConfig.revealDelayMs,
      dismissDurationMs: this.presentationConfig.dismissDurationMs,
      systemSheetType: this.presentationConfig.useNativeSystemSheet() ? 'webPageTools' : 'none',
      shouldReveal: (): boolean => this.currentSnapshot.type === type
    });
  }

  close(): void {
    if (this.currentSnapshot.type === 'siteInfo') {
      this.siteControlsCoordinator.closeApplicationSurface();
      return;
    }
    this.dismiss();
  }

  handleBack(): void {
    if (this.currentSnapshot.type === 'siteInfo') {
      this.siteControlsCoordinator.handleApplicationSurfaceBack();
      return;
    }
    this.navigateBackOrDismiss();
  }

  handleOverlayAction(action: BrowserWebPageToolsOverlayAction): void {
    switch (action.type) {
      case 'dismiss':
        this.close();
        return;
      case 'navigate_back':
        this.navigateBackOrDismiss();
        return;
      case 'select_screen_orientation':
        if (action.screenOrientationMode !== undefined) {
          void this.actionDependencies.resolveFullscreenActionOwner()
            .applyScreenOrientationMode(action.screenOrientationMode);
        }
        return;
      case 'select_desktop_site_mode':
        if (action.desktopSiteMode !== undefined) {
          this.actionDependencies.resolveUserAgentActionOwner().selectDesktopSiteMode(action.desktopSiteMode);
        }
        return;
      case 'open_default_user_agent':
        this.actionDependencies.resolveUserAgentActionOwner().openUserAgentPresetSheet(true);
        return;
      case 'select_user_agent_preset':
        if (action.presetId !== undefined) {
          this.actionDependencies.resolveUserAgentActionOwner().selectUserAgentPreset(action.presetId);
        }
        return;
      case 'select_custom_user_agent':
        if (action.recordId !== undefined) {
          this.actionDependencies.resolveUserAgentActionOwner().selectCustomUserAgent(action.recordId);
        }
        return;
      case 'site_controls':
        if (action.siteControlsAction !== undefined) {
          this.siteControlsCoordinator.handleUserAction(
            action.siteControlsAction,
            action.permissionKind,
            action.permissionRule
          );
        }
        return;
    }
  }

  dismiss(): void {
    this.transientSurfaceCoordinator.dismiss('web_page_tools');
  }

  reset(): void {
    if (this.currentSnapshot.type === 'siteInfo') {
      this.siteControlsCoordinator.resetApplicationSurface();
    }
    this.returnSheetType = 'none';
    this.updateSnapshot('none');
    this.transientSurfaceCoordinator.reset('web_page_tools');
  }

  handleTransientSurfaceUpdate(update: BrowserTransientSurfaceUpdate): void {
    if (update.lane !== 'custom_bottom' || update.surfaceId !== 'web_page_tools' ||
      (update.reason !== 'dismissed' && update.reason !== 'reset')) {
      return;
    }
    if (this.currentSnapshot.type === 'siteInfo') {
      this.siteControlsCoordinator.resetApplicationSurface();
    }
    this.returnSheetType = 'none';
    this.updateSnapshot('none');
  }

  private navigateBackOrDismiss(): void {
    if (this.returnSheetType !== 'none') {
      const targetSheetType = this.returnSheetType;
      this.returnSheetType = 'none';
      this.updateSnapshot(targetSheetType);
      return;
    }
    this.dismiss();
  }

  private updateSnapshot(type: BrowserWebPageToolsSheetType): void {
    this.currentSnapshot = {
      type: type
    };
    this.publishSnapshot(this.currentSnapshot);
  }
}
