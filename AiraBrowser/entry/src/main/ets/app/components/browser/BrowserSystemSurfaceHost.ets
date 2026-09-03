import {
  BrowserSystemSurfacePresentation,
  BrowserSystemSurfacePresentationViewModel,
  resolveNovelReaderSystemSurfaceLayout
} from '../../../core/browser/BrowserSystemSurfacePresentationViewModel';
import { BrowserSystemSheetSnapshot } from '../../../core/browser/BrowserTransientSurfaceCoordinator';
import {
  HomeShortcutSelectionAction,
  HomeShortcutSelectionState
} from '../../../core/shortcuts/HomeShortcutSelectionCoordinator';
import { HomePageSettingsDialog } from './HomePageSettingsSheet';
import { HomeShortcutSelectionDialog } from './HomeShortcutSelectionDialog';
import { UserScriptInstallDialog } from '../userscripts/UserScriptInstallDialog';
import { UserScriptPackageSuccessResult } from '../../../core/userscripts/UserScriptPackageLifecycleCoordinator';
import {
  BrowserUserScriptInstallBoundary
} from '../../../core/userscripts/BrowserUserScriptApplicationCoordinator';
import {
  BrowserDataScope,
  BrowserSessionPrivacyMode
} from '../../../common/models/BrowserModels';
import { BrowserAdaptiveModalOverlay } from './BrowserAdaptiveModalOverlay';
import { createCenteredDialogMaterial } from '../common/CenteredDialogSurface';

@Component
export struct BrowserSystemSurfaceHost {
  @Link phoneSheetVisible: boolean;
  @Link selectionState: HomeShortcutSelectionState;
  @Prop @Watch('syncPresentation') systemSheet: BrowserSystemSheetSnapshot = {
    visible: false,
    type: 'none'
  };
  @Prop @Watch('syncPresentation') shellFamily: 'phone' | 'large_screen' = 'phone';
  @Prop @Watch('syncPrivateModeVisible') privateModeVisible: boolean = false;
  @State private currentPrivateModeVisible: boolean = false;
  @State private currentUserScriptInstallUrl: string = '';
  @State private currentUserScriptInstallDataScope: BrowserDataScope = 'profile_persistent';
  @State private currentUserScriptInstallPrivacyMode: BrowserSessionPrivacyMode = 'regular';
  resolveUserScriptInstallUrl: () => string = () => '';
  resolveUserScriptInstallBoundary: () => BrowserUserScriptInstallBoundary = () => {
    return {
      dataScope: 'profile_persistent',
      privacyMode: 'regular'
    };
  };
  onSelectionAction: (action: HomeShortcutSelectionAction) => void =
    (_action: HomeShortcutSelectionAction) => {};
  onSelectionBack: () => void = () => {};
  onHomeSettingsWallpaperChanged: () => void = () => {};
  onUserScriptInstalled: (result: UserScriptPackageSuccessResult) => void =
    (_result: UserScriptPackageSuccessResult) => {};
  onCloseRequested: () => void = () => {};
  onDisappear: () => void = () => {};
  @BuilderParam largeScreenReadingContent: () => void = this.emptyContent;
  @State private largeScreenDialogVisible: boolean = false;
  @State private largeScreenNovelReaderDialogVisible: boolean = false;
  @State private largeScreenNovelReaderDialogTitle: string = '';
  @State private largeScreenNovelReaderDialogPreferredWidth: number = 600;
  @State private largeScreenNovelReaderDialogPreferredHeight: number = 560;
  @State private largeScreenNovelReaderDialogSoftMinWidth: number = 500;
  @State private largeScreenNovelReaderDialogMaxWidth: number = 640;
  @State private largeScreenNovelReaderDialogSoftMinHeight: number = 420;
  @State private largeScreenNovelReaderDialogMaxHeight: number = 600;
  private homeShortcutDialogOpen: boolean = false;
  private homeSettingsDialogOpen: boolean = false;
  private userScriptInstallDialogOpen: boolean = false;
  private readonly presentationViewModel: BrowserSystemSurfacePresentationViewModel =
    new BrowserSystemSurfacePresentationViewModel();
  private homeShortcutDialogController: CustomDialogController = new CustomDialogController({
    builder: HomeShortcutSelectionDialog({
      state: $selectionState,
      onAction: (action: HomeShortcutSelectionAction): void => {
        this.onSelectionAction(action);
      },
      onClose: (): void => {
        this.onCloseRequested();
      },
      onBack: (): void => {
        this.onSelectionBack();
      }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: false,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
    onWillDismiss: (_dismissDialogAction: DismissDialogAction): void => {
      this.onSelectionBack();
    }
  });
  private homeSettingsDialogController: CustomDialogController = new CustomDialogController({
    builder: HomePageSettingsDialog({
      privateModeVisible: $currentPrivateModeVisible,
      onWallpaperChanged: (): void => {
        this.onHomeSettingsWallpaperChanged();
      },
      onClose: (): void => {
        this.onCloseRequested();
      }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: false,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
    onWillDismiss: (_dismissDialogAction: DismissDialogAction): void => {
      this.onCloseRequested();
    }
  });
  private userScriptInstallDialogController: CustomDialogController = new CustomDialogController({
    builder: UserScriptInstallDialog({
      installSourceUrl: $currentUserScriptInstallUrl,
      dataScope: this.currentUserScriptInstallDataScope,
      privacyMode: this.currentUserScriptInstallPrivacyMode,
      onRequestClose: (): void => {
        this.onCloseRequested();
      },
      onInstalled: (result: UserScriptPackageSuccessResult): void => {
        this.onUserScriptInstalled(result);
      }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: false,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
    onWillDismiss: (_dismissDialogAction: DismissDialogAction): void => {
      this.onCloseRequested();
    }
  });

  aboutToAppear(): void {
    this.syncPrivateModeVisible();
    this.syncPresentation();
  }

  aboutToDisappear(): void {
    this.phoneSheetVisible = false;
    this.largeScreenDialogVisible = false;
    this.largeScreenNovelReaderDialogVisible = false;
    this.closeHomeShortcutDialog();
    this.closeHomeSettingsDialog();
    this.closeUserScriptInstallDialog();
  }

  build() {
    Column() {
      this.buildLargeScreenNovelReaderDialog()
    }
    .width(0)
    .height(0)
  }

  @Builder
  private buildLargeScreenNovelReaderDialog() {
    BrowserAdaptiveModalOverlay({
      visible: this.largeScreenNovelReaderDialogVisible,
      layoutMode: 'large_screen',
      title: this.largeScreenNovelReaderDialogTitle,
      desktopWidth: this.largeScreenNovelReaderDialogPreferredWidth,
      desktopHeight: this.largeScreenNovelReaderDialogPreferredHeight,
      desktopMinWidth: this.largeScreenNovelReaderDialogSoftMinWidth,
      desktopMaxWidth: this.largeScreenNovelReaderDialogMaxWidth,
      desktopMinHeight: this.largeScreenNovelReaderDialogSoftMinHeight,
      desktopMaxHeight: this.largeScreenNovelReaderDialogMaxHeight,
      onDismiss: (): void => {
        this.onCloseRequested();
      },
      onDidDismiss: (): void => {
        this.handleLargeScreenNovelReaderDialogDisappear();
      }
    }) {
      if (this.systemSheet.type === 'novelCatalog') {
        Column() {
          this.largeScreenReadingContent()
        }
        .width('100%')
        .height('100%')
      } else {
        Scroll() {
          Column() {
            this.largeScreenReadingContent()
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .scrollBar(BarState.Auto)
      }
    }
  }

  private syncPresentation(): void {
    const presentation = this.presentationViewModel.resolve(this.systemSheet, this.shellFamily);
    const novelReaderDialogLayout = resolveNovelReaderSystemSurfaceLayout(this.systemSheet.type);
    this.phoneSheetVisible = presentation.phoneSheetVisible;
    this.largeScreenDialogVisible = this.isLargeScreenDialogVisible(presentation);
    this.largeScreenNovelReaderDialogTitle = presentation.largeScreenNovelReaderDialogTitle;
    this.largeScreenNovelReaderDialogPreferredWidth = novelReaderDialogLayout.preferredWidth;
    this.largeScreenNovelReaderDialogPreferredHeight = novelReaderDialogLayout.preferredHeight;
    this.largeScreenNovelReaderDialogSoftMinWidth = novelReaderDialogLayout.softMinWidth;
    this.largeScreenNovelReaderDialogMaxWidth = novelReaderDialogLayout.maxWidth;
    this.largeScreenNovelReaderDialogSoftMinHeight = novelReaderDialogLayout.softMinHeight;
    this.largeScreenNovelReaderDialogMaxHeight = novelReaderDialogLayout.maxHeight;
    this.largeScreenNovelReaderDialogVisible = presentation.largeScreenNovelReaderDialogVisible;

    if (presentation.largeScreenHomeShortcutDialogVisible) {
      this.openHomeShortcutDialog();
    } else if (this.closeHomeShortcutDialog() && !this.largeScreenDialogVisible) {
      this.onDisappear();
    }

    if (presentation.largeScreenHomeSettingsDialogVisible) {
      this.openHomeSettingsDialog();
    } else if (this.closeHomeSettingsDialog() && !this.largeScreenDialogVisible) {
      this.onDisappear();
    }

    if (presentation.largeScreenUserScriptInstallDialogVisible) {
      this.openUserScriptInstallDialog();
    } else if (this.closeUserScriptInstallDialog() && !this.largeScreenDialogVisible) {
      this.onDisappear();
    }
  }

  private handleLargeScreenNovelReaderDialogDisappear(): void {
    if (!this.systemSheet.visible) {
      this.onDisappear();
    }
  }

  private syncPrivateModeVisible(): void {
    this.currentPrivateModeVisible = this.privateModeVisible;
  }

  private isLargeScreenDialogVisible(presentation: BrowserSystemSurfacePresentation): boolean {
    return presentation.largeScreenHomeShortcutDialogVisible ||
      presentation.largeScreenHomeSettingsDialogVisible ||
      presentation.largeScreenUserScriptInstallDialogVisible ||
      presentation.largeScreenNovelReaderDialogVisible;
  }

  private openHomeShortcutDialog(): void {
    if (this.homeShortcutDialogOpen) {
      return;
    }
    this.homeShortcutDialogOpen = true;
    this.homeShortcutDialogController.open();
  }

  private closeHomeShortcutDialog(): boolean {
    if (!this.homeShortcutDialogOpen) {
      return false;
    }
    this.homeShortcutDialogOpen = false;
    this.homeShortcutDialogController.close();
    return true;
  }

  private openHomeSettingsDialog(): void {
    if (this.homeSettingsDialogOpen) {
      return;
    }
    this.homeSettingsDialogOpen = true;
    this.homeSettingsDialogController.open();
  }

  private closeHomeSettingsDialog(): boolean {
    if (!this.homeSettingsDialogOpen) {
      return false;
    }
    this.homeSettingsDialogOpen = false;
    this.homeSettingsDialogController.close();
    return true;
  }

  private openUserScriptInstallDialog(): void {
    if (this.userScriptInstallDialogOpen) {
      return;
    }
    this.currentUserScriptInstallUrl = this.resolveUserScriptInstallUrl();
    const boundary = this.resolveUserScriptInstallBoundary();
    this.currentUserScriptInstallDataScope = boundary.dataScope;
    this.currentUserScriptInstallPrivacyMode = boundary.privacyMode;
    this.userScriptInstallDialogOpen = true;
    this.userScriptInstallDialogController.open();
  }

  private closeUserScriptInstallDialog(): boolean {
    if (!this.userScriptInstallDialogOpen) {
      return false;
    }
    this.userScriptInstallDialogOpen = false;
    this.userScriptInstallDialogController.close();
    return true;
  }

  @Builder
  private emptyContent() {
  }
}
