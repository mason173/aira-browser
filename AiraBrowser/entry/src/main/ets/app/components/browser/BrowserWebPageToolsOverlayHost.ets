import {
  BrowserUserAgentPresetId,
  SitePermissionKind,
  SitePermissionRule
} from '../../../common/models/BrowserModels';
import {
  BrowserFullscreenSessionPresentation
} from '../../../core/browser/BrowserFullscreenSessionCoordinator';
import {
  BrowserScreenOrientationMode
} from '../../../core/browser/BrowserScreenOrientationViewModel';
import {
  BrowserSiteControlsApplicationSnapshot,
  BrowserSiteControlsUserAction
} from '../../../core/browser/BrowserSiteControlsRuntimeCoordinator';
import {
  BrowserUserAgentActionPresentation
} from '../../../core/browser/BrowserUserAgentActionCoordinator';
import {
  BrowserWebPageToolsOverlayAction,
  BrowserWebPageToolsSheetType
} from '../../../core/browser/BrowserWebPageToolsCoordinator';
import {
  BrowserDesktopSiteMode
} from '../../../services/web/BrowserUserAgentService';
import { BrowserDesktopSiteModeSheet } from './BrowserDesktopSiteModeSheet';
import { BrowserScreenOrientationSheet } from './BrowserScreenOrientationSheet';
import {
  BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX,
  WEB_PAGE_TOOLS_OVERLAY_ANIMATION_DURATION_MS
} from './BrowserShellPresentationTokens';
import { BrowserSiteInfoSheet } from './BrowserSiteInfoSheet';
import { BrowserUserAgentPresetSheet } from './BrowserUserAgentPresetSheet';
import { BrowserAdaptiveModalOverlay } from './BrowserAdaptiveModalOverlay';

@Component
export struct BrowserWebPageToolsContent {
  @Prop sheetType: BrowserWebPageToolsSheetType = 'none';
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  @Prop fullscreenPresentation: BrowserFullscreenSessionPresentation;
  @Prop userAgentPresentation: BrowserUserAgentActionPresentation;
  @Prop siteControlsSnapshot: BrowserSiteControlsApplicationSnapshot;
  onAction: (action: BrowserWebPageToolsOverlayAction) => void =
    (_action: BrowserWebPageToolsOverlayAction) => {};

  build() {
    if (this.sheetType === 'screenOrientation') {
      this.buildScreenOrientationSheet()
    } else if (this.sheetType === 'desktopSiteMode') {
      this.buildDesktopSiteModeSheet()
    } else if (this.sheetType === 'userAgentPreset') {
      this.buildUserAgentPresetSheet()
    } else if (this.sheetType === 'siteInfo') {
      this.buildSiteInfoSheet()
    } else {
      Column().width('100%').height('100%')
    }
  }

  @Builder
  private buildScreenOrientationSheet() {
    BrowserScreenOrientationSheet({
      layoutMode: this.layoutMode,
      selectedMode: this.fullscreenPresentation.screenOrientationMode,
      options: this.fullscreenPresentation.screenOrientationOptions,
      onClose: (): void => {
        this.onAction({ type: 'dismiss' });
      },
      onSelectMode: (mode: BrowserScreenOrientationMode): void => {
        this.onAction({ type: 'select_screen_orientation', screenOrientationMode: mode });
      }
    })
  }

  @Builder
  private buildDesktopSiteModeSheet() {
    BrowserDesktopSiteModeSheet({
      layoutMode: this.layoutMode,
      state: this.userAgentPresentation.desktopSiteModeSheetState,
      onClose: (): void => {
        this.onAction({ type: 'dismiss' });
      },
      onSelectMode: (mode: BrowserDesktopSiteMode): void => {
        this.onAction({ type: 'select_desktop_site_mode', desktopSiteMode: mode });
      },
      onOpenDefaultUserAgent: (): void => {
        this.onAction({ type: 'open_default_user_agent' });
      }
    })
  }

  @Builder
  private buildUserAgentPresetSheet() {
    BrowserUserAgentPresetSheet({
      layoutMode: this.layoutMode,
      selectedPresetId: this.userAgentPresentation.selectedPresetId,
      selectedMode: this.userAgentPresentation.selectedMode,
      mobileOptions: this.userAgentPresentation.userAgentPresetSheetState.mobileOptions,
      desktopOptions: this.userAgentPresentation.userAgentPresetSheetState.desktopOptions,
      customOptions: this.userAgentPresentation.userAgentPresetSheetState.customUserAgents,
      onBack: (): void => {
        this.onAction({ type: 'navigate_back' });
      },
      onSelectPreset: (presetId: BrowserUserAgentPresetId): void => {
        this.onAction({ type: 'select_user_agent_preset', presetId: presetId });
      },
      onSelectCustomUserAgent: (recordId: string): void => {
        this.onAction({ type: 'select_custom_user_agent', recordId: recordId });
      }
    })
  }

  @Builder
  private buildSiteInfoSheet() {
    BrowserSiteInfoSheet({
      snapshot: this.siteControlsSnapshot,
      onAction: (
        action: BrowserSiteControlsUserAction,
        permissionKind?: SitePermissionKind,
        permissionRule?: SitePermissionRule
      ): void => {
        this.onAction({
          type: 'site_controls',
          siteControlsAction: action,
          permissionKind: permissionKind,
          permissionRule: permissionRule
        });
      }
    })
  }
}

@Component
export struct BrowserWebPageToolsLargeScreenOverlayHost {
  @Prop visible: boolean = false;
  @Prop sheetType: BrowserWebPageToolsSheetType = 'none';
  @Prop fullscreenPresentation: BrowserFullscreenSessionPresentation;
  @Prop userAgentPresentation: BrowserUserAgentActionPresentation;
  @Prop siteControlsSnapshot: BrowserSiteControlsApplicationSnapshot;
  onAction: (action: BrowserWebPageToolsOverlayAction) => void =
    (_action: BrowserWebPageToolsOverlayAction) => {};

  build() {
    if (this.sheetType === 'siteInfo') {
      Row().width(0).height(0)
    } else {
      BrowserAdaptiveModalOverlay({
        visible: this.visible,
        layoutMode: 'large_screen',
        title: this.resolveDialogTitle(),
        animationDurationMs: WEB_PAGE_TOOLS_OVERLAY_ANIMATION_DURATION_MS,
        zIndexValue: BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX,
        desktopWidth: '76%',
        desktopHeight: this.resolveDesktopDialogHeight(),
        desktopMinWidth: 520,
        desktopMaxWidth: 680,
        desktopMinHeight: this.resolveDesktopDialogMinHeight(),
        desktopMaxHeight: this.resolveDesktopDialogMaxHeight(),
        onDismiss: () => this.onAction({ type: 'dismiss' })
      }) {
        BrowserWebPageToolsContent({
          sheetType: this.sheetType,
          layoutMode: 'large_screen',
          fullscreenPresentation: this.fullscreenPresentation,
          userAgentPresentation: this.userAgentPresentation,
          siteControlsSnapshot: this.siteControlsSnapshot,
          onAction: (action: BrowserWebPageToolsOverlayAction): void => {
            this.onAction(action);
          }
        })
      }
    }
  }

  private resolveDialogTitle(): string {
    if (this.sheetType === 'desktopSiteMode') {
      return '网站版本';
    }
    if (this.sheetType === 'userAgentPreset') {
      return '网页标识';
    }
    if (this.sheetType === 'screenOrientation') {
      return '屏幕方向';
    }
    return '站点信息';
  }

  private resolveDesktopDialogHeight(): Length {
    if (this.sheetType === 'userAgentPreset') {
      return '76%';
    }
    if (this.sheetType === 'desktopSiteMode') {
      return 420;
    }
    return 380;
  }

  private resolveDesktopDialogMinHeight(): number {
    return this.sheetType === 'userAgentPreset' ? 420 : 360;
  }

  private resolveDesktopDialogMaxHeight(): number {
    return this.sheetType === 'userAgentPreset' ? 620 : 460;
  }
}
