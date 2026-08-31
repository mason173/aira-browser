import {
  BrowserMediaResourceSessionSnapshot,
  BrowserMediaResourcesOverlayAction,
  createBrowserMediaResourceSessionSnapshot
} from '../../../core/browser/BrowserMediaResourceSessionCoordinator';
import { BrowserSystemSheetType } from '../../../core/browser/BrowserShellRuntimeContracts';
import {
  AppProxyQuickSheetAction,
  AppProxyQuickSheetState
} from '../../../core/settings/AppProxyQuickSheetCoordinator';
import {
  BrowserUserScriptApplicationAction
} from '../../../core/userscripts/BrowserUserScriptApplicationCoordinator';
import { UserScriptPageActionsState } from '../../../features/userscripts/UserScriptRuntimeModels';
import { MediaResourceAction } from '../../../features/mediaDiscovery/MediaResourceProjectionModels';
import { AppProxyQuickSheetContent } from '../settings/AppProxyQuickSheetContent';
import { UserScriptPageActionsSheet } from '../userscripts/UserScriptPageActionsSheet';
import { BrowserMediaResourcesSheet } from './BrowserMediaResourcesSheet';

export function isBrowserToolbarSystemSheetType(type: BrowserSystemSheetType): boolean {
  return type === 'userScriptPageActions' || type === 'appProxyQuick' || type === 'resourceCandidates';
}

@Component
export struct BrowserToolbarSystemSheetContent {
  @Prop type: BrowserSystemSheetType = 'none';
  @Prop userScriptState: UserScriptPageActionsState = {
    url: '',
    message: '',
    hasPage: false,
    hasMatchingScripts: false,
    hasMenuCommands: false,
    matchingScriptCount: 0,
    commands: [],
    scripts: []
  };
  @Prop appProxyState: AppProxyQuickSheetState = {
    globalEnabled: false,
    hasProfiles: false,
    profiles: [],
    switchingGlobalEnabled: false,
    switchingProfileId: '',
    toolbarActive: false
  };
  @Prop mediaResourceState: BrowserMediaResourceSessionSnapshot = createBrowserMediaResourceSessionSnapshot();
  onUserScriptAction: (action: BrowserUserScriptApplicationAction) => void =
    (_action: BrowserUserScriptApplicationAction): void => {};
  onAppProxyAction: (action: AppProxyQuickSheetAction) => void =
    (_action: AppProxyQuickSheetAction): void => {};
  onMediaResourceAction: (action: BrowserMediaResourcesOverlayAction) => void =
    (_action: BrowserMediaResourcesOverlayAction): void => {};

  build() {
    if (this.type === 'userScriptPageActions') {
      UserScriptPageActionsSheet({
        state: this.userScriptState,
        onAction: (action: BrowserUserScriptApplicationAction) => {
          this.onUserScriptAction(action);
        }
      })
        .width('100%')
        .height('100%')
    } else if (this.type === 'appProxyQuick') {
      AppProxyQuickSheetContent({
        state: this.appProxyState,
        onClose: () => {
          this.onAppProxyAction({ type: 'dismiss' });
        },
        onToggleGlobalEnabled: (enabled: boolean) => {
          this.onAppProxyAction({ type: 'toggle_global', enabled: enabled });
        },
        onSelectProfile: (profileId: string) => {
          this.onAppProxyAction({ type: 'select_profile', profileId: profileId });
        },
        onOpenSettings: () => {
          this.onAppProxyAction({ type: 'open_settings' });
        }
      })
        .width('100%')
        .height('100%')
    } else if (this.type === 'resourceCandidates') {
      BrowserMediaResourcesSheet({
        candidates: this.mediaResourceState.resourceListItems,
        counts: this.mediaResourceState.resourceTabCounts,
        manifestParsingCandidateId: this.mediaResourceState.resourceManifestParsingCandidateId,
        manifestParseResult: this.mediaResourceState.resourceManifestParseResult,
        scanning: this.mediaResourceState.resourceScanInProgress,
        onClose: () => {
          this.onMediaResourceAction({ type: 'close' });
        },
        onAction: (candidateId: string, action: MediaResourceAction) => {
          this.onMediaResourceAction({
            type: 'resource',
            candidateId: candidateId,
            resourceAction: action
          });
        }
      })
        .width('100%')
        .height('100%')
    }
  }
}
