import { common } from '@kit.AbilityKit';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import router from '@ohos.router';
import {
  AdBlockPreferences,
  AdBlockSettings,
  BrowserDownloadAutoClearPolicy,
  BrowserDownloadSettings,
  BrowserPreferences,
  BrowserPrivateDownloadFilePolicy,
  BrowserPrivateDownloadRecordPolicy,
  BrowserProfileId,
  BrowserUserAgentSettings,
  PasswordManagerPreferences,
  PasswordManagerSettings
} from '../../../common/models/BrowserModels';
import { BrowserBoundaryRouteState } from '../../../common/utils/RouteParamUtils';
import { SettingsCenterDestination } from '../../../core/settings/SettingsCenterViewModel';
import {
  BrowserThemeViewState,
  BrowserThemeViewStateFactory
} from '../../../core/theme/BrowserThemeViewState';
import {
  AdBlockSettingsViewModel,
  AdBlockSettingsViewState
} from '../../../core/adblock/AdBlockSettingsViewModel';
import {
  AdBlockRiskConsentSheetState,
  AdBlockRiskConsentViewModel
} from '../../../core/adblock/AdBlockRiskConsentViewModel';
import {
  AdBlockSettingsBoundary,
  AdBlockSettingsCoordinator,
  AdBlockSettingsMutationResult
} from '../../../core/adblock/AdBlockSettingsCoordinator';
import {
  PasswordSettingsViewModel,
  PasswordSettingsViewState
} from '../../../core/password/PasswordSettingsViewModel';
import {
  WebpageTranslationSettingsViewModel,
  WebpageTranslationSettingsViewState
} from '../../../core/translation/WebpageTranslationSettingsViewModel';
import {
  TranslationSettingsBoundary,
  TranslationSettingsCoordinator,
  TranslationSettingsMutationResult
} from '../../../core/translation/TranslationSettingsCoordinator';
import {
  DownloadSettingsSectionState,
  DownloadSettingsViewModel
} from '../../../core/download/DownloadSettingsViewModel';
import {
  BrowserUserAgentSettingsViewModel,
  BrowserUserAgentSettingsViewState
} from '../../../core/settings/BrowserUserAgentSettingsViewModel';
import {
  UserScriptManagementAction,
  UserScriptManagementEffect,
  UserScriptManagementSessionCoordinator,
  UserScriptManagementSheet,
  UserScriptManagementSnapshot,
  UserScriptManagementSurfaceFacts,
  UserScriptManagementTransition
} from '../../../core/userscripts/UserScriptManagementSessionCoordinator';
import {
  AD_BLOCK_CUSTOM_RULES_ROUTE,
  MANUAL_ELEMENT_HIDE_SETTINGS_ROUTE,
  TRANSLATION_PROVIDER_CONFIG_ROUTE,
  TRANSLATION_PROVIDER_EDIT_ROUTE,
  USER_SCRIPT_DETAIL_ROUTE
} from '../../router/AppRoutes';
import {
  sharedAdBlockRepository,
  sharedAdBlockRuntimeGenerationCoordinator,
  sharedBrowserUserAgentSettingsRepository,
  createUserScriptManagementSessionCoordinator,
  sharedPasswordSettingsRepository,
  sharedPreferencesRepository,
  sharedTranslationSecretStore,
  sharedTranslationSettingsRepository
} from '../../bootstrap/BrowserAppRuntime';
import { AdBlockSettingsContent } from '../adblock/AdBlockSettingsScreen';
import { AdBlockRiskConsentSheet } from '../adblock/AdBlockRiskConsentSheet';
import {
  BrowserDownloadSettingsContent,
  BrowserDownloadSettingsSubpage
} from '../browser/BrowserDownloadSettingsScreen';
import { PasswordSettingsContent } from '../password/PasswordSettingsScreen';
import { SearchSettingsHost } from '../search/SearchSettingsHost';
import { WebpageTranslationSettingsContent } from '../translation/WebpageTranslationSettingsScreen';
import { TranslationProviderWorkspaceHost } from '../translation/TranslationProviderWorkspaceHost';
import { UserScriptRiskConsentSheet } from '../userscripts/UserScriptRiskConsentSheet';
import { UserScriptUpdateSheet } from '../userscripts/UserScriptUpdateSheet';
import { UserScriptManagementHost } from '../userscripts/UserScriptManagementHost';
import { UserScriptsScreen } from '../userscripts/UserScriptsScreen';
import { SyncExperienceHost } from '../sync/SyncExperienceHost';
import { BrowserUserAgentSettingsScreen } from './BrowserUserAgentSettingsScreen';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import { SettingsInlineDetailPanel } from './SettingsInlineDetailPanel';
import { SettingsPresentationScrollBody } from './SettingsLayout';
import { UserScriptExportService } from '../../../services/userscripts/UserScriptExportService';
import { CustomHomepageSettingsScreen } from '../customhome/CustomHomepageSettingsScreen';
import { AiraProScreen } from '../membership/AiraProScreen';
import { AppProxySettingsScreen } from './AppProxySettingsScreen';
import { BrowserToolbarCustomizationScreen } from './BrowserToolbarCustomizationScreen';
import {
  CustomHomepageSettingsPageBinding
} from '../../../core/customhome/CustomHomepageSettingsPageBinding';

interface EmbeddedSettingsRouteParams extends BrowserBoundaryRouteState {
  providerId?: string;
  host?: string;
  origin?: string;
  profileId?: BrowserProfileId;
}

type EmbeddedUserScriptSheet = 'none' | 'riskConsent' | 'updateCheck' | 'adBlockRiskConsent';

@Component
export struct SettingsEmbeddedDetailPanel {
  private themeViewStateFactory: BrowserThemeViewStateFactory = new BrowserThemeViewStateFactory();
  private adBlockViewModel: AdBlockSettingsViewModel = new AdBlockSettingsViewModel();
  private adBlockRiskConsentViewModel: AdBlockRiskConsentViewModel = new AdBlockRiskConsentViewModel();
  private adBlockSettingsCoordinator: AdBlockSettingsCoordinator = new AdBlockSettingsCoordinator(
    sharedAdBlockRepository,
    sharedAdBlockRuntimeGenerationCoordinator
  );
  private translationSettingsCoordinator: TranslationSettingsCoordinator = new TranslationSettingsCoordinator(
    sharedTranslationSettingsRepository,
    sharedTranslationSecretStore
  );
  private passwordViewModel: PasswordSettingsViewModel = new PasswordSettingsViewModel();
  private translationViewModel: WebpageTranslationSettingsViewModel = new WebpageTranslationSettingsViewModel();
  private downloadViewModel: DownloadSettingsViewModel = new DownloadSettingsViewModel();
  private settingsNavigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private inlineDetailScroller: Scroller = new Scroller();
  private passwordSettingsScroller: Scroller = new Scroller();
  private adBlockSettingsScroller: Scroller = new Scroller();
  private translationSettingsScroller: Scroller = new Scroller();
  private downloadSettingsScroller: Scroller = new Scroller();
  private userAgentViewModel: BrowserUserAgentSettingsViewModel = new BrowserUserAgentSettingsViewModel();
  private userScriptManagementSession: UserScriptManagementSessionCoordinator =
    createUserScriptManagementSessionCoordinator();
  private userScriptExportService: UserScriptExportService = new UserScriptExportService();
  customHomepagePageBinding: CustomHomepageSettingsPageBinding = new CustomHomepageSettingsPageBinding();
  @Prop shellFamily: 'phone' | 'large_screen' = 'phone';
  @Prop
  @Watch('refreshState')
  selectedDestination: SettingsCenterDestination = 'general';
  @Prop
  @Watch('refreshState')
  dataScope: string = '';
  @Prop
  @Watch('refreshState')
  privacyMode: string = '';
  @Prop
  @Watch('refreshState')
  boundarySource: string = '';
  @Prop
  @Watch('refreshState')
  settingsRefreshRevision: number = 0;
  @Prop surfaceBackground: ResourceColor = '';
  @Prop dividerColor: ResourceColor = '';
  @Prop accentColor: ResourceColor = '';
  @Prop onAccentColor: ResourceColor = '';
  @Prop pressedBackground: ResourceColor = '';
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop revealTargetId: string = '';
  @Prop revealRevision: number = 0;
  onSelectDestination?: (destination: SettingsCenterDestination) => void;
  onOpenAppProxySettings?: () => void;
  onOpenEmbeddedSubpage?: (subpageId: string) => void;
  onOpenUserScriptGallerySource?: (url: string) => void;
  onSettingsChanged?: () => void;
  @State private theme: BrowserThemeViewState =
    this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  @State private adBlockState: AdBlockSettingsViewState =
    this.buildAdBlockViewState(sharedAdBlockRepository.getSettings());
  @State private adBlockRiskConsentState: AdBlockRiskConsentSheetState =
    this.adBlockRiskConsentViewModel.buildState();
  @State private passwordState: PasswordSettingsViewState =
    this.passwordViewModel.buildState(sharedPasswordSettingsRepository.getSettings());
  @State private translationState: WebpageTranslationSettingsViewState =
    this.translationViewModel.buildState(sharedTranslationSettingsRepository.getSettings());
  @State private downloadState: DownloadSettingsSectionState =
    this.downloadViewModel.buildState(sharedPreferencesRepository.getPreferences().downloads);
  @State private askBeforeDownload: boolean = sharedPreferencesRepository.getPreferences().downloads.askBeforeDownload;
  @State private allowCellularDownloads: boolean =
    sharedPreferencesRepository.getPreferences().downloads.allowCellularDownloads;
  @State private autoResumeAfterRestart: boolean =
    sharedPreferencesRepository.getPreferences().downloads.autoResumeAfterRestart;
  @State private autoClearPolicy: BrowserDownloadAutoClearPolicy =
    sharedPreferencesRepository.getPreferences().downloads.autoClearPolicy;
  @State private privateFilePolicy: BrowserPrivateDownloadFilePolicy =
    sharedPreferencesRepository.getPreferences().downloads.privateFilePolicy;
  @State private privateRecordPolicy: BrowserPrivateDownloadRecordPolicy =
    sharedPreferencesRepository.getPreferences().downloads.privateRecordPolicy;
  @State private userAgentState: BrowserUserAgentSettingsViewState =
    this.userAgentViewModel.buildState(sharedBrowserUserAgentSettingsRepository.getSettings());
  @State private userScriptManagementSnapshot: UserScriptManagementSnapshot =
    this.userScriptManagementSession.snapshot();
  @State private userScriptSheetVisible: boolean = false;
  @State private userScriptActiveSheet: EmbeddedUserScriptSheet = 'none';
  @State private appProxyWorkspaceVisible: boolean = false;
  @State private translationWorkspaceView: 'none' | 'selection' | 'config' = 'none';
  @State private translationWorkspaceProviderId: string = '';
  private pendingAdBlockEnableAfterConsent: boolean = false;

  aboutToAppear(): void {
    if (this.shellFamily !== 'large_screen') {
      this.userScriptManagementSession.setObserver((transition: UserScriptManagementTransition): void => {
        this.applyUserScriptManagementTransition(transition);
      });
    }
    this.refreshState();
  }

  build() {
    if (!this.canOpenSelectedDestination()) {
      Column() {
        this.buildInlinePanel()
      }
      .width('100%')
      .height('100%')
    } else {
      Column() {
        this.buildSelectedPanel()
      }
      .width('100%')
      .height('100%')
      .bindSheet($$this.userScriptSheetVisible, this.buildUserScriptActiveSheet(), {
        // Large-screen consent/update sheets use the same centered presentation.
        preferType: this.shellFamily === 'large_screen' ? SheetType.CENTER : SheetType.BOTTOM,
        height: this.shellFamily === 'large_screen' ? SheetSize.FIT_CONTENT : SheetSize.LARGE,
        dragBar: this.shellFamily !== 'large_screen',
        showClose: false,
        onDisappear: () => {
          this.handleUserScriptSheetDisappear();
        }
      })
    }
  }

  @Builder
  private buildSelectedPanel() {
    if (!this.canOpenSelectedDestination()) {
      this.buildInlinePanel()
    } else if (this.shellFamily === 'large_screen' && this.appProxyWorkspaceVisible) {
      this.buildAppProxyPanel()
    } else if (this.shellFamily === 'large_screen' && this.translationWorkspaceView !== 'none') {
      this.buildTranslationProviderWorkspace()
    } else if (this.selectedDestination === 'search') {
      this.buildSearchPanel()
    } else if (this.selectedDestination === 'custom_homepage') {
      this.buildCustomHomepagePanel()
    } else if (this.selectedDestination === 'toolbar_customization') {
      this.buildToolbarCustomizationPanel()
    } else if (this.selectedDestination === 'passwords') {
      this.buildPasswordPanel()
    } else if (this.selectedDestination === 'ad_blocker') {
      this.buildAdBlockPanel()
    } else if (this.selectedDestination === 'webpage_translation') {
      this.buildTranslationPanel()
    } else if (this.selectedDestination === 'downloads') {
      this.buildDownloadPanel()
    } else if (this.selectedDestination === 'user_scripts') {
      this.buildUserScriptsPanel()
    } else if (this.selectedDestination === 'user_agent') {
      this.buildUserAgentPanel()
    } else if (this.selectedDestination === 'sync') {
      this.buildSyncPanel()
    } else if (this.selectedDestination === 'aira_pro') {
      this.buildAiraProPanel()
    } else {
      this.buildInlinePanel()
    }
  }

  private canOpenSelectedDestination(): boolean {
    if (sharedPreferencesRepository.getPreferences().appServiceMode !== 'basic') {
      return true;
    }
    switch (this.selectedDestination) {
      case 'sync':
        return false;
      default:
        return true;
    }
  }

  private areOptionalServicesEnabled(): boolean {
    return sharedPreferencesRepository.getPreferences().appServiceMode !== 'basic';
  }

  @Builder
  private buildUserScriptActiveSheet() {
    if (this.userScriptActiveSheet === 'riskConsent') {
      this.buildUserScriptRiskConsentSheet()
    } else if (this.userScriptActiveSheet === 'updateCheck') {
      this.buildUserScriptUpdateSheet()
    } else if (this.userScriptActiveSheet === 'adBlockRiskConsent') {
      this.buildAdBlockRiskConsentSheet()
    } else {
      Column()
    }
  }

  @Builder
  private buildAdBlockRiskConsentSheet() {
    AdBlockRiskConsentSheet({
      state: this.adBlockRiskConsentState,
      layoutMode: this.shellFamily,
      onAccept: () => {
        this.acceptAdBlockRiskConsent();
      },
      onDecline: () => {
        this.declineAdBlockRiskConsent();
      }
    })
  }

  @Builder
  private buildUserScriptRiskConsentSheet() {
    UserScriptRiskConsentSheet({
      state: this.userScriptManagementSnapshot.riskConsent,
      layoutMode: this.shellFamily,
      onAccept: () => {
        this.userScriptManagementSession.action(UserScriptManagementAction.acceptRiskConsent());
      },
      onDecline: () => {
        this.userScriptManagementSession.action(UserScriptManagementAction.declineRiskConsent());
      }
    })
  }

  @Builder
  private buildUserScriptUpdateSheet() {
    UserScriptUpdateSheet({
      results: this.userScriptManagementSnapshot.updateResults,
      checking: this.userScriptManagementSnapshot.updateChecking,
      updating: this.userScriptManagementSnapshot.updateInstalling,
      layoutMode: this.shellFamily,
      onUpdateSelected: () => {
        this.userScriptManagementSession.action(UserScriptManagementAction.installAvailableUpdates());
      },
      onClose: () => {
        this.userScriptManagementSession.action(UserScriptManagementAction.sheetDismissed('updateCheck'));
      }
    })
  }

  @Builder
  private buildInlinePanel() {
    SettingsPresentationScrollBody({
      desktopPresentation: this.shellFamily === 'large_screen',
      bottomPadding: 18,
      scroller: this.inlineDetailScroller
    }) {
      SettingsInlineDetailPanel({
        shellFamily: this.shellFamily,
        selectedDestination: this.selectedDestination,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource,
        surfaceBackground: this.surfaceBackground,
        dividerColor: this.dividerColor,
        accentColor: this.accentColor,
        onAccentColor: this.onAccentColor,
        pressedBackground: this.pressedBackground,
        primaryTextColor: this.primaryTextColor,
        secondaryTextColor: this.secondaryTextColor,
        revealTargetId: this.revealTargetId,
        revealRevision: this.revealRevision,
        scroller: this.inlineDetailScroller,
        onOpenAppProxySettings: () => {
          if (this.shellFamily === 'large_screen') {
            this.appProxyWorkspaceVisible = true;
            return;
          }
          this.onOpenAppProxySettings?.();
        },
        onOpenEmbeddedSubpage: (subpageId: string) => {
          this.onOpenEmbeddedSubpage?.(subpageId);
        },
        onSettingsChanged: () => {
          this.handleSettingsChanged();
        }
      })
    }
  }

  @Builder
  private buildSearchPanel() {
    SearchSettingsHost({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource,
      refreshRevision: this.settingsRefreshRevision,
      showBackButton: false,
      showTitleBar: false,
      useTopSafeInset: false,
      contentKind: 'unframed',
      largeScreenInline: true,
      desktopPresentation: this.shellFamily === 'large_screen',
      revealTargetId: this.revealTargetId,
      revealRevision: this.revealRevision,
      onSettingsChanged: () => {
        this.handleSettingsChanged();
      }
    })
  }

  @Builder
  private buildCustomHomepagePanel() {
    CustomHomepageSettingsScreen({
      presentationMode: 'embedded',
      desktopPresentation: this.shellFamily === 'large_screen',
      pageBinding: this.customHomepagePageBinding
    })
  }

  @Builder
  private buildToolbarCustomizationPanel() {
    BrowserToolbarCustomizationScreen({
      showTitleBar: false,
      showBackButton: false,
      useTopSafeInset: false,
      desktopPresentation: this.shellFamily === 'large_screen',
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      onSettingsChanged: () => {
        this.handleSettingsChanged();
      }
    })
      .width('100%')
      .height('100%')
  }

  @Builder
  private buildPasswordPanel() {
    SettingsPresentationScrollBody({
      contentSpace: 18,
      desktopPresentation: this.shellFamily === 'large_screen',
      bottomPadding: 18,
      scroller: this.passwordSettingsScroller
    }) {
      PasswordSettingsContent({
        state: this.passwordState,
        surfaceBackground: this.theme.surfaceBackground,
        controlBackground: this.theme.controlBackground,
        pressedBackground: this.theme.pressedBackground,
        primaryTextColor: this.theme.textPrimary,
        secondaryTextColor: this.theme.textSecondary,
        accentColor: this.theme.accent,
        desktopPresentation: this.shellFamily === 'large_screen',
        revealTargetId: this.revealTargetId,
        revealRevision: this.revealRevision,
        scroller: this.passwordSettingsScroller,
        onOfficialVaultChange: (enabled: boolean) => {
          this.updatePasswordPreference('officialVaultEnabled', enabled);
        },
        onRegularAutofillChange: (enabled: boolean) => {
          this.updatePasswordPreference('regularAutofillEnabled', enabled);
        },
        onRegularSavePromptChange: (enabled: boolean) => {
          this.updatePasswordPreference('regularSavePromptEnabled', enabled);
        },
        onPrivateAutofillChange: (enabled: boolean) => {
          this.updatePasswordPreference('privateAutofillEnabled', enabled);
        }
      })
    }
  }

  @Builder
  private buildAdBlockPanel() {
    this.buildAdBlockMainPanel()
  }

  @Builder
  private buildAdBlockMainPanel() {
    SettingsPresentationScrollBody({
      contentSpace: 18,
      desktopPresentation: this.shellFamily === 'large_screen',
      bottomPadding: 18,
      scroller: this.adBlockSettingsScroller,
      clipContent: true
    }) {
      AdBlockSettingsContent({
        state: this.adBlockState,
        surfaceBackground: this.theme.surfaceBackground,
        pressedBackground: this.theme.pressedBackground,
        primaryTextColor: this.theme.textPrimary,
        secondaryTextColor: this.theme.textSecondary,
        accentColor: this.theme.accent,
        controlsEnabled: this.areOptionalServicesEnabled(),
        desktopPresentation: this.shellFamily === 'large_screen',
        revealTargetId: this.revealTargetId,
        revealRevision: this.revealRevision,
        scroller: this.adBlockSettingsScroller,
        onEnabledChange: (enabled: boolean) => {
          this.updateAdBlockPreference('enabled', enabled);
        },
        onOpenCustomRules: () => {
          this.openAdBlockCustomRules();
        },
        onOpenManualElementHideSettings: () => {
          this.openManualElementHideSettings();
        },
        onClearStats: () => {
          this.confirmClearAdBlockStats();
        },
        onRemoveException: (host: string) => {
          this.removeAdBlockException(host);
        }
      })
    }
  }

  @Builder
  private buildTranslationPanel() {
    SettingsPresentationScrollBody({
      contentSpace: 18,
      desktopPresentation: this.shellFamily === 'large_screen',
      bottomPadding: 18,
      scroller: this.translationSettingsScroller
    }) {
      WebpageTranslationSettingsContent({
        state: this.translationState,
        dividerColor: this.dividerColor,
        surfaceBackground: this.theme.surfaceBackground,
        accentColor: this.theme.accent,
        controlsEnabled: this.areOptionalServicesEnabled(),
        desktopPresentation: this.shellFamily === 'large_screen',
        revealTargetId: this.revealTargetId,
        revealRevision: this.revealRevision,
        scroller: this.translationSettingsScroller,
        onEnabledChange: (enabled: boolean) => {
          this.updateTranslationPreference('enabled', enabled);
        },
        onAllowPrivateTabsChange: (enabled: boolean) => {
          this.updateTranslationPreference('allowInPrivateTabs', enabled);
        },
        onOpenProviderSelection: () => {
          this.openProviderSelection();
        },
        onEditActiveProvider: () => {
          this.openActiveProviderEditor();
        },
        onSelectTargetLanguage: (languageCode: string) => {
          this.updateTranslationPreference('preferredTargetLanguage', languageCode);
        }
      })
    }
  }

  @Builder
  private buildDownloadPanel() {
    SettingsPresentationScrollBody({
      contentSpace: 18,
      desktopPresentation: this.shellFamily === 'large_screen',
      bottomPadding: 18,
      scroller: this.downloadSettingsScroller
    }) {
      BrowserDownloadSettingsContent({
        viewState: this.downloadState,
        askBeforeDownload: this.askBeforeDownload,
        allowCellularDownloads: this.allowCellularDownloads,
        autoResumeAfterRestart: this.autoResumeAfterRestart,
        autoClearPolicy: this.autoClearPolicy,
        privateFilePolicy: this.privateFilePolicy,
        privateRecordPolicy: this.privateRecordPolicy,
        dividerColor: this.dividerColor,
        surfaceBackground: this.theme.surfaceBackground,
        primaryTextColor: this.theme.textPrimary,
        secondaryTextColor: this.theme.textSecondary,
        accentColor: this.theme.accent,
        desktopPresentation: this.shellFamily === 'large_screen',
        revealTargetId: this.revealTargetId,
        revealRevision: this.revealRevision,
        scroller: this.downloadSettingsScroller,
        onAskBeforeDownloadChange: (enabled: boolean) => {
          this.updateDownloadSettings({ askBeforeDownload: enabled });
        },
        onAllowCellularDownloadsChange: (enabled: boolean) => {
          this.updateDownloadSettings({ allowCellularDownloads: enabled });
        },
        onAutoResumeAfterRestartChange: (enabled: boolean) => {
          this.updateDownloadSettings({ autoResumeAfterRestart: enabled });
        },
        onOpenSubpage: (subpage: BrowserDownloadSettingsSubpage) => {
          this.openDownloadSettingsOption(subpage);
        }
      })
    }
  }

  private updateDownloadSettings(patch: Partial<BrowserDownloadSettings>): void {
    const previousSettings = sharedPreferencesRepository.getPreferences().downloads;
    const nextSettings = this.downloadViewModel.buildSettingsPatch(previousSettings, patch);
    this.applyDownloadSettingsState(nextSettings);
    sharedPreferencesRepository.updateDownloadSettings(nextSettings)
      .then((preferences: BrowserPreferences) => {
        this.applyDownloadSettingsState(preferences.downloads);
        this.handleSettingsChanged();
      })
      .catch((_error: Error) => {
        this.applyDownloadSettingsState(previousSettings);
      });
  }

  private openDownloadSettingsOption(subpage: BrowserDownloadSettingsSubpage): void {
    if (this.shellFamily === 'large_screen' && this.onOpenEmbeddedSubpage !== undefined) {
      this.onOpenEmbeddedSubpage(subpage);
      return;
    }
    this.settingsNavigationCoordinator.openDownloadSettingsOption(subpage, this.buildBoundaryState());
  }

  @Builder
  private buildUserScriptsPanel() {
    if (this.shellFamily === 'large_screen') {
      UserScriptManagementHost({
        presentationMode: 'native_tab',
        settingsWorkspacePresentation: true,
        refreshRevision: this.settingsRefreshRevision,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource,
        onRequestClose: () => {
          this.onSelectDestination?.('general');
        },
        onRequestOpenGallerySource: (url: string) => {
          this.onOpenUserScriptGallerySource?.(url);
        },
        onSettingsChanged: () => {
          this.handleSettingsChanged();
        }
      })
      .width('100%')
      .height('100%')
    } else {
      UserScriptsScreen({
        state: this.userScriptManagementSnapshot.settings,
        showNotice: this.userScriptManagementSnapshot.showNotice,
        showBackButton: false,
        showTitleBar: false,
        useTopSafeInset: false,
        onToggleScript: (scriptId: string, enabled: boolean) => {
          this.userScriptManagementSession.action(UserScriptManagementAction.toggleScript(scriptId, enabled));
        },
        onEditScript: (scriptId: string) => {
          this.openUserScriptDetailPage(scriptId);
        },
        onUpdateScript: (scriptId: string) => {
          this.userScriptManagementSession.action(UserScriptManagementAction.checkScriptUpdate(scriptId));
        },
        onExportScript: (scriptId: string) => {
          this.userScriptManagementSession.action(UserScriptManagementAction.requestExportScript(scriptId));
        },
        onUpdateAllScripts: () => {
          this.userScriptManagementSession.action(UserScriptManagementAction.checkAllUpdates());
        },
        onAutoUpdateChange: (enabled: boolean) => {
          this.userScriptManagementSession.action(UserScriptManagementAction.setAutoUpdate(enabled));
        },
        onDeleteScript: (scriptId: string) => {
          this.userScriptManagementSession.action(UserScriptManagementAction.requestDeleteScript(scriptId));
        },
        onDismissNotice: () => {
          this.userScriptManagementSession.action(UserScriptManagementAction.dismissNotice());
        }
      })
    }
  }

  @Builder
  private buildUserAgentPanel() {
    BrowserUserAgentSettingsScreen({
      state: this.userAgentState,
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      showBackButton: false,
      showTitleBar: false,
      useTopSafeInset: false,
      contentKind: 'unframed',
      useCenteredSheet: this.shellFamily === 'large_screen',
      desktopPresentation: this.shellFamily === 'large_screen',
      revealTargetId: this.revealTargetId,
      revealRevision: this.revealRevision,
      onSettingsChange: (settings: BrowserUserAgentSettings): void => {
        this.userAgentState = this.userAgentViewModel.buildState(settings);
        this.handleSettingsChanged();
      }
    })
  }

  @Builder
  private buildSyncPanel() {
    SyncExperienceHost({
      showBackButton: false,
      showTitleBar: false,
      useTopSafeInset: false,
      contentKind: 'unframed',
      useLargeScreenSelectionDialog: true,
      desktopPresentation: this.shellFamily === 'large_screen',
      onOpenAiraPro: () => {
        this.onSelectDestination?.('aira_pro');
      },
      onExit: () => {
        if (this.onSelectDestination !== undefined) {
          this.onSelectDestination('general');
          return;
        }
        this.settingsNavigationCoordinator.back();
      }
    })
  }

  @Builder
  private buildAiraProPanel() {
    AiraProScreen({
      presentationMode: 'workspace',
      embeddedDataScope: this.dataScope,
      embeddedPrivacyMode: this.privacyMode,
      embeddedBoundarySource: this.boundarySource,
      onRequestClose: () => {
        this.onSelectDestination?.('general');
      }
    })
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildAppProxyPanel() {
    AppProxySettingsScreen({
      presentationMode: 'native_tab',
      settingsWorkspacePresentation: true,
      embeddedDataScope: this.dataScope,
      embeddedPrivacyMode: this.privacyMode,
      embeddedBoundarySource: this.boundarySource,
      refreshRevision: this.settingsRefreshRevision,
      onWorkspaceBack: () => {
        this.appProxyWorkspaceVisible = false;
      }
    })
      .width('100%')
      .height('100%')
  }

  @Builder
  private buildTranslationProviderWorkspace() {
    TranslationProviderWorkspaceHost({
      startMode: this.translationWorkspaceView === 'config' ? 'config' : 'selection',
      initialProviderId: this.translationWorkspaceProviderId,
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      onBack: () => {
        this.translationWorkspaceView = 'none';
        this.translationWorkspaceProviderId = '';
        this.refreshState();
      },
      onSettingsChanged: () => {
        this.refreshState();
        this.handleSettingsChanged();
      }
    })
      .width('100%')
      .height('100%')
  }

  private refreshState(): void {
    if (this.selectedDestination !== 'advanced_settings') {
      this.appProxyWorkspaceVisible = false;
    }
    if (this.selectedDestination !== 'webpage_translation') {
      this.translationWorkspaceView = 'none';
      this.translationWorkspaceProviderId = '';
    }
    this.theme = this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
    this.adBlockState = this.buildAdBlockViewState(sharedAdBlockRepository.getSettings());
    this.passwordState = this.passwordViewModel.buildState(sharedPasswordSettingsRepository.getSettings());
    this.translationState = this.translationViewModel.buildState(
      sharedTranslationSettingsRepository.getSettings()
    );
    this.applyDownloadSettingsState(sharedPreferencesRepository.getPreferences().downloads);
    this.userAgentState = this.userAgentViewModel.buildState(sharedBrowserUserAgentSettingsRepository.getSettings());
    if (this.shellFamily !== 'large_screen') {
      this.activateUserScriptManagementSession();
    }
    this.loadAdBlockSettingsIfVisible();
  }

  private activateUserScriptManagementSession(): void {
    this.userScriptManagementSession.activate(new UserScriptManagementSurfaceFacts(
      this.selectedDestination === 'user_scripts' && this.canOpenSelectedDestination(),
      {
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        loggedIn: true
      }
    ));
  }

  private loadAdBlockSettingsIfVisible(): void {
    if (this.selectedDestination !== 'ad_blocker') {
      return;
    }
    sharedAdBlockRepository.initializeMetadata()
      .then(() => {
        this.adBlockState = this.buildAdBlockViewState(sharedAdBlockRepository.getSettings());
      })
      .catch((_error: Error) => undefined);
  }

  private applyDownloadSettingsState(settings: BrowserDownloadSettings): void {
    this.downloadState = this.downloadViewModel.buildState(settings);
    this.askBeforeDownload = settings.askBeforeDownload;
    this.allowCellularDownloads = settings.allowCellularDownloads;
    this.autoResumeAfterRestart = settings.autoResumeAfterRestart;
    this.autoClearPolicy = settings.autoClearPolicy;
    this.privateFilePolicy = settings.privateFilePolicy;
    this.privateRecordPolicy = settings.privateRecordPolicy;
  }

  private updatePasswordPreference(
    key: 'officialVaultEnabled' | 'regularAutofillEnabled' | 'regularSavePromptEnabled' | 'privateAutofillEnabled',
    enabled: boolean
  ): void {
    const current = sharedPasswordSettingsRepository.getSettings().preferences;
    const nextPreferences: PasswordManagerPreferences =
      this.passwordViewModel.buildPreferencesPatch(current, key, enabled);
    const previousState = this.passwordState;
    const currentSettings = sharedPasswordSettingsRepository.getSettings();
    this.passwordState = this.passwordViewModel.buildState({
      provider: currentSettings.provider,
      preferences: nextPreferences,
      officialVaultVerifiedAt: currentSettings.officialVaultVerifiedAt,
      officialVaultVerificationNote: currentSettings.officialVaultVerificationNote,
      selfHostedCredentialStoreEnabled: currentSettings.selfHostedCredentialStoreEnabled,
      updatedAt: currentSettings.updatedAt
    });
    sharedPasswordSettingsRepository.updatePreferences(nextPreferences)
      .then((settings: PasswordManagerSettings) => {
        this.passwordState = this.passwordViewModel.buildState(settings);
        this.handleSettingsChanged();
      })
      .catch((_error: Error) => {
        this.passwordState = previousState;
      });
  }

  private updateAdBlockPreference(key: 'enabled' | 'updateOnForeground', enabled: boolean): void {
    if (key === 'enabled' && enabled) {
      this.adBlockRiskConsentState = this.adBlockRiskConsentViewModel.buildState();
      this.pendingAdBlockEnableAfterConsent = true;
      this.openUserScriptSheet('adBlockRiskConsent');
      return;
    }
    this.applyAdBlockPreference(key, enabled);
  }

  private acceptAdBlockRiskConsent(): void {
    const shouldEnable = this.pendingAdBlockEnableAfterConsent;
    this.pendingAdBlockEnableAfterConsent = false;
    this.closeUserScriptSheet();
    if (shouldEnable) {
      this.applyAdBlockPreference('enabled', true);
    }
  }

  private declineAdBlockRiskConsent(): void {
    this.pendingAdBlockEnableAfterConsent = false;
    this.closeUserScriptSheet();
    this.adBlockState = this.buildAdBlockViewState(sharedAdBlockRepository.getSettings());
  }

  private applyAdBlockPreference(key: 'enabled' | 'updateOnForeground', enabled: boolean): void {
    const current = sharedAdBlockRepository.getSettings().preferences;
    const nextPreferences: AdBlockPreferences = this.adBlockViewModel.buildPreferencesPatch(current, key, enabled);
    const previousState = this.adBlockState;
    const currentSettings = sharedAdBlockRepository.getSettings();
    this.adBlockState = this.buildAdBlockViewState({
      preferences: nextPreferences,
      siteExceptions: currentSettings.siteExceptions,
      customRuleSources: currentSettings.customRuleSources,
      stats: currentSettings.stats,
      lastRuleUpdateAt: currentSettings.lastRuleUpdateAt,
      engineUnavailableReason: currentSettings.engineUnavailableReason,
      updatedAt: currentSettings.updatedAt
    });
    this.adBlockSettingsCoordinator.updatePreferences(nextPreferences, this.buildAdBlockSettingsBoundary())
      .then((result: AdBlockSettingsMutationResult) => {
        if (!result.allowed) {
          this.adBlockState = previousState;
          return;
        }
        this.adBlockState = this.buildAdBlockViewState(result.settings);
        this.handleSettingsChanged();
      })
      .catch((_error: Error) => {
        this.adBlockState = previousState;
      });
  }

  private confirmClearAdBlockStats(): void {
    showCenteredAlertDialog({
      title: '清空拦截统计',
      message: '清空后不会影响网页内容过滤规则和站点例外。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清空',
        fontColor: $r('app.color.permission_blocked'),
        action: () => {
          this.clearAdBlockStats();
        }
      }
    });
  }

  private clearAdBlockStats(): void {
    this.adBlockSettingsCoordinator.clearStats(this.buildAdBlockSettingsBoundary())
      .then((result: AdBlockSettingsMutationResult) => {
        if (!result.allowed) {
          return;
        }
        this.adBlockState = this.buildAdBlockViewState(result.settings);
        this.handleSettingsChanged();
      })
      .catch((_error: Error) => {});
  }

  private removeAdBlockException(host: string): void {
    this.adBlockSettingsCoordinator.removeSiteException(host, this.buildAdBlockSettingsBoundary())
      .then((result: AdBlockSettingsMutationResult) => {
        if (!result.allowed) {
          return;
        }
        this.adBlockState = this.buildAdBlockViewState(result.settings);
        this.handleSettingsChanged();
      })
      .catch((_error: Error) => {});
  }

  private updateTranslationPreference(
    key: 'enabled' | 'allowInPrivateTabs' | 'preferredTargetLanguage',
    value: boolean | string | number
  ): void {
    const previousState = this.translationState;
    this.translationSettingsCoordinator.updatePreference(key, value, this.buildTranslationSettingsBoundary())
      .then((result: TranslationSettingsMutationResult) => {
        this.translationState = result.allowed ? this.translationViewModel.buildState(result.settings) : previousState;
        if (!result.allowed) {
          return;
        }
        this.handleSettingsChanged();
      })
      .catch((_error: Error) => {
        this.translationState = previousState;
      });
  }

  private openProviderSelection(): void {
    if (this.shellFamily === 'large_screen') {
      this.translationWorkspaceProviderId = '';
      this.translationWorkspaceView = 'selection';
      return;
    }
    router.pushUrl({
      url: TRANSLATION_PROVIDER_EDIT_ROUTE,
      params: this.buildBoundaryState()
    }).catch((_error: Error) => {});
  }

  private openActiveProviderEditor(): void {
    const activeProviderId = sharedTranslationSettingsRepository.getSettings().activeProviderId;
    if (activeProviderId.length === 0) {
      this.openProviderSelection();
      return;
    }
    if (this.shellFamily === 'large_screen') {
      this.translationWorkspaceProviderId = activeProviderId;
      this.translationWorkspaceView = 'config';
      return;
    }
    const params = this.buildBoundaryState();
    params.providerId = activeProviderId;
    router.pushUrl({
      url: TRANSLATION_PROVIDER_CONFIG_ROUTE,
      params: params
    }).catch((_error: Error) => {});
  }

  private openAdBlockCustomRules(): void {
    if (this.shellFamily === 'large_screen') {
      this.onOpenEmbeddedSubpage?.('adblock_rules');
      return;
    }
    router.pushUrl({
      url: AD_BLOCK_CUSTOM_RULES_ROUTE,
      params: this.buildBoundaryState()
    }).catch((_error: Error) => {});
  }

  private openManualElementHideSettings(): void {
    if (this.shellFamily === 'large_screen') {
      this.onOpenEmbeddedSubpage?.('adblock_hidden_elements');
      return;
    }
    router.pushUrl({
      url: MANUAL_ELEMENT_HIDE_SETTINGS_ROUTE,
      params: this.buildBoundaryState()
    }).catch((_error: Error) => {});
  }

  private openUserScriptDetailPage(scriptId: string): void {
    router.pushUrl({
      url: USER_SCRIPT_DETAIL_ROUTE,
      params: {
        scriptId: scriptId
      }
    }).catch((_error: Error) => {});
  }

  private applyUserScriptManagementTransition(transition: UserScriptManagementTransition): void {
    this.userScriptManagementSnapshot = transition.snapshot;
    this.syncUserScriptSheet(transition.snapshot.activeSheet);
    transition.effects.forEach((effect: UserScriptManagementEffect) => {
      this.handleUserScriptManagementEffect(effect);
    });
  }

  private syncUserScriptSheet(sheet: UserScriptManagementSheet): void {
    if (sheet === 'none') {
      if (this.userScriptActiveSheet === 'riskConsent' || this.userScriptActiveSheet === 'updateCheck') {
        this.userScriptSheetVisible = false;
      }
      return;
    }
    this.userScriptActiveSheet = sheet;
    this.userScriptSheetVisible = true;
  }

  private handleUserScriptManagementEffect(effect: UserScriptManagementEffect): void {
    if (effect.kind === 'exit') {
      this.onSelectDestination?.('general');
      return;
    }
    if (effect.kind === 'message') {
      this.showToast(effect.message);
      return;
    }
    if (effect.kind === 'confirm_delete_script') {
      this.confirmDeleteScript(effect.scriptId, effect.scriptName);
      return;
    }
    if (effect.kind === 'settings_changed') {
      this.handleSettingsChanged();
      return;
    }
    if (effect.kind === 'export_script' && effect.script !== undefined) {
      this.userScriptExportService.exportScript(this.getPickerContext(), effect.script, {
        dataScope: this.dataScope,
        privacyMode: this.privacyMode
      })
        .then((result) => {
          this.showToast(result.message);
        })
        .catch((_error: Error) => {
          this.showToast('导出脚本失败，请稍后重试。');
        });
    }
  }

  private confirmDeleteScript(scriptId: string, scriptName: string): void {
    showCenteredAlertDialog({
      title: '删除用户脚本',
      message: `确定删除“${scriptName}”吗？`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.permission_blocked'),
        action: () => {
          this.userScriptManagementSession.action(UserScriptManagementAction.deleteScript(scriptId));
        }
      }
    });
  }

  private openUserScriptSheet(sheet: EmbeddedUserScriptSheet): void {
    this.userScriptActiveSheet = sheet;
    this.userScriptSheetVisible = true;
  }

  private closeUserScriptSheet(): void {
    this.userScriptSheetVisible = false;
  }

  private handleUserScriptSheetDisappear(): void {
    if (this.userScriptActiveSheet === 'adBlockRiskConsent') {
      this.pendingAdBlockEnableAfterConsent = false;
      this.adBlockState = this.buildAdBlockViewState(sharedAdBlockRepository.getSettings());
    } else if (this.userScriptActiveSheet === 'riskConsent' || this.userScriptActiveSheet === 'updateCheck') {
      const dismissedSheet: UserScriptManagementSheet = this.userScriptActiveSheet;
      this.userScriptManagementSession.action(UserScriptManagementAction.sheetDismissed(dismissedSheet));
    }
    this.userScriptSheetVisible = false;
    this.userScriptActiveSheet = 'none';
  }

  private handleSettingsChanged(): void {
    this.onSettingsChanged?.();
  }

  private buildAdBlockSettingsBoundary(): AdBlockSettingsBoundary {
    return new AdBlockSettingsBoundary(this.dataScope, this.privacyMode);
  }

  private buildAdBlockViewState(settings: AdBlockSettings): AdBlockSettingsViewState {
    return this.adBlockViewModel.buildState(
      this.adBlockSettingsCoordinator.projectSettingsForBoundary(settings, this.buildAdBlockSettingsBoundary())
    );
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1800
      });
    } catch (_error) {
    }
  }

  private getPickerContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private buildBoundaryState(): EmbeddedSettingsRouteParams {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    };
  }

  private buildTranslationSettingsBoundary(): TranslationSettingsBoundary {
    return new TranslationSettingsBoundary(this.dataScope, this.privacyMode);
  }

}
