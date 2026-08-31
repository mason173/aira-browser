import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { AIRA_FEATURE_WEBAPP_INSTALL } from '../../common/constants/MembershipFeatureKeys';
import {
  WebAppInstallRepository,
  sharedWebAppInstallRepository
} from '../../data/webapps/WebAppInstallRepository';
import { MembershipFeature } from '../../features/membership/MembershipFeature';
import { EntitlementContext } from '../../services/membership/EntitlementService';
import {
  DesktopShortcutResult,
  DesktopShortcutService
} from '../../services/shortcuts/DesktopShortcutService';
import {
  WebAppInstallIconSelection,
  WebAppInstallIconSelectionService
} from '../../services/webapps/WebAppInstallIconSelectionService';
import {
  WebAppInstallDraft,
  WebAppInstallPolicyService
} from '../../services/webapps/WebAppInstallPolicyService';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { FeatureGateCoordinator } from '../membership/FeatureGateCoordinator';

export interface WebAppInstallShellSnapshot {
  context: common.UIAbilityContext;
  entitlementContext: EntitlementContext;
  tabId: string;
  url: string;
  title: string;
  favicon?: image.PixelMap;
}

export interface WebAppInstallDialogSnapshot {
  title: string;
  url: string;
  iconUri: string;
  iconCustomized: boolean;
  iconProcessing: boolean;
}

export interface WebAppInstallUpdateTitleAction {
  type: 'update_title';
  title: string;
}

export interface WebAppInstallSelectIconAction {
  type: 'select_icon';
}

export interface WebAppInstallRestoreDefaultIconAction {
  type: 'restore_default_icon';
}

export interface WebAppInstallConfirmAction {
  type: 'confirm';
}

export type WebAppInstallDialogAction =
  WebAppInstallUpdateTitleAction |
  WebAppInstallSelectIconAction |
  WebAppInstallRestoreDefaultIconAction |
  WebAppInstallConfirmAction;

export interface WebAppInstallShell {
  captureSnapshot: () => WebAppInstallShellSnapshot;
  publishDialogSnapshot: (snapshot: WebAppInstallDialogSnapshot) => void;
  openDialog: () => void;
  showToast: (message: string) => void;
}

interface WebAppInstallSession {
  id: number;
  snapshot: WebAppInstallShellSnapshot;
  draft: WebAppInstallDraft;
  defaultIconPath: string;
  customIcon?: WebAppInstallIconSelection;
}

export class WebAppInstallCoordinator {
  private membershipFeature: MembershipFeature;
  private featureGateCoordinator: FeatureGateCoordinator;
  private runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  private shell: WebAppInstallShell;
  private policyService: WebAppInstallPolicyService;
  private shortcutService: DesktopShortcutService;
  private iconSelectionService: WebAppInstallIconSelectionService;
  private installRepository: WebAppInstallRepository;
  private session?: WebAppInstallSession;
  private sessionSequence: number = 0;
  private dialogSnapshot: WebAppInstallDialogSnapshot = {
    title: '',
    url: '',
    iconUri: '',
    iconCustomized: false,
    iconProcessing: false
  };

  constructor(
    membershipFeature: MembershipFeature,
    featureGateCoordinator: FeatureGateCoordinator,
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    shell: WebAppInstallShell,
    policyService: WebAppInstallPolicyService = new WebAppInstallPolicyService(),
    shortcutService: DesktopShortcutService = new DesktopShortcutService(),
    iconSelectionService: WebAppInstallIconSelectionService = new WebAppInstallIconSelectionService(),
    installRepository: WebAppInstallRepository = sharedWebAppInstallRepository
  ) {
    this.membershipFeature = membershipFeature;
    this.featureGateCoordinator = featureGateCoordinator;
    this.runtimeLifecyclePort = runtimeLifecyclePort;
    this.shell = shell;
    this.policyService = policyService;
    this.shortcutService = shortcutService;
    this.iconSelectionService = iconSelectionService;
    this.installRepository = installRepository;
  }

  getDialogSnapshot(): WebAppInstallDialogSnapshot {
    return this.dialogSnapshot;
  }

  async begin(): Promise<void> {
    const requestId = this.sessionSequence + 1;
    this.sessionSequence = requestId;
    const previousSession = this.session;
    this.session = undefined;
    await this.iconSelectionService.discard(previousSession?.customIcon);
    const currentUsage = (await this.installRepository.getAll()).length;
    const accessSnapshot = this.shell.captureSnapshot();
    const entitlementContext: EntitlementContext = {
      dataScope: accessSnapshot.entitlementContext.dataScope,
      privacyMode: accessSnapshot.entitlementContext.privacyMode,
      loggedIn: accessSnapshot.entitlementContext.loggedIn,
      currentUsage: currentUsage
    };
    if (!await this.featureGateCoordinator.ensureAccess(AIRA_FEATURE_WEBAPP_INSTALL, entitlementContext) ||
      requestId !== this.sessionSequence) {
      return;
    }
    const snapshot = this.shell.captureSnapshot();
    const currentUrl = snapshot.url.trim();
    if (currentUrl.length === 0) {
      this.shell.showToast('当前没有可安装为应用的网址。');
      return;
    }
    const currentTitle = snapshot.title.trim().length > 0 ? snapshot.title.trim() : currentUrl;
    const draftPromise = this.buildDraft(snapshot, currentUrl, currentTitle);
    const defaultIconPromise = this.prepareDefaultIcon(snapshot, currentUrl);
    const draft = await draftPromise;
    const defaultIconPath = await defaultIconPromise;
    if (requestId !== this.sessionSequence) {
      return;
    }
    const session: WebAppInstallSession = {
      id: requestId,
      snapshot: snapshot,
      draft: draft,
      defaultIconPath: defaultIconPath
    };
    this.session = session;
    this.publishDialogSnapshot({
      title: draft.defaultTitle.trim().length > 0 ? draft.defaultTitle.trim() : currentTitle,
      url: draft.launchUrl.trim().length > 0 ? draft.launchUrl.trim() : currentUrl,
      iconUri: this.toPreviewUri(defaultIconPath),
      iconCustomized: false,
      iconProcessing: false
    });
    this.shell.openDialog();
  }

  handleDialogAction(action: WebAppInstallDialogAction): void {
    switch (action.type) {
      case 'update_title':
        this.updateTitle(action.title);
        return;
      case 'select_icon':
        void this.selectCustomIcon();
        return;
      case 'restore_default_icon':
        this.restoreDefaultIcon();
        return;
      case 'confirm':
        this.confirm();
        return;
    }
  }

  async handleDialogDismissed(): Promise<void> {
    const session = this.session;
    if (session === undefined) {
      return;
    }
    this.session = undefined;
    this.sessionSequence += 1;
    if (this.dialogSnapshot.iconProcessing) {
      this.publishDialogSnapshot({
        title: this.dialogSnapshot.title,
        url: this.dialogSnapshot.url,
        iconUri: this.dialogSnapshot.iconUri,
        iconCustomized: this.dialogSnapshot.iconCustomized,
        iconProcessing: false
      });
    }
    await this.iconSelectionService.discard(session.customIcon);
  }

  private updateTitle(title: string): void {
    if (this.session === undefined || title === this.dialogSnapshot.title) {
      return;
    }
    this.publishDialogSnapshot({
      title: title,
      url: this.dialogSnapshot.url,
      iconUri: this.dialogSnapshot.iconUri,
      iconCustomized: this.dialogSnapshot.iconCustomized,
      iconProcessing: this.dialogSnapshot.iconProcessing
    });
  }

  private async selectCustomIcon(): Promise<void> {
    const session = this.session;
    if (session === undefined || this.dialogSnapshot.iconProcessing) {
      return;
    }
    this.publishIconSnapshot(session, true);
    try {
      const selection = await this.iconSelectionService.pickAndPrepare(session.snapshot.context);
      if (this.session?.id !== session.id) {
        await this.iconSelectionService.discard(selection);
        return;
      }
      if (selection === undefined) {
        this.publishIconSnapshot(session, false);
        return;
      }
      const previousSelection = session.customIcon;
      session.customIcon = selection;
      this.publishIconSnapshot(session, false);
      await this.iconSelectionService.discard(previousSelection);
    } catch (error) {
      if (this.session?.id !== session.id) {
        return;
      }
      this.publishIconSnapshot(session, false);
      this.shell.showToast(this.resolveIconErrorMessage(error));
    }
  }

  private restoreDefaultIcon(): void {
    const session = this.session;
    if (session === undefined || this.dialogSnapshot.iconProcessing || session.customIcon === undefined) {
      return;
    }
    const previousSelection = session.customIcon;
    session.customIcon = undefined;
    this.publishIconSnapshot(session, false);
    void this.iconSelectionService.discard(previousSelection);
  }

  private confirm(): void {
    const session = this.session;
    if (session === undefined) {
      this.shell.showToast('安装信息已失效，请重新打开。');
      return;
    }
    if (this.dialogSnapshot.iconProcessing) {
      this.shell.showToast('图标正在处理中，请稍候。');
      return;
    }
    this.session = undefined;
    this.sessionSequence += 1;
    const title = this.dialogSnapshot.title;
    void this.confirmDetachedSession(session, title);
  }

  private async confirmDetachedSession(session: WebAppInstallSession, title: string): Promise<void> {
    const launchUrl = session.draft.launchUrl.trim().length > 0
      ? session.draft.launchUrl.trim()
      : session.snapshot.url.trim();
    if (launchUrl.length === 0) {
      await this.iconSelectionService.discard(session.customIcon);
      this.shell.showToast('当前没有可安装为应用的网址。');
      return;
    }
    const label = title.trim().length > 0 ? title.trim() : launchUrl;
    const context = session.snapshot.context;
    this.shell.showToast('正在打开系统确认...');
    try {
      const result: DesktopShortcutResult = await this.shortcutService.addWebPageShortcut(context, {
        url: launchUrl,
        title: label,
        bundleName: context.abilityInfo.bundleName,
        moduleName: context.abilityInfo.moduleName,
        abilityName: context.abilityInfo.name,
        favicon: session.snapshot.favicon,
        preparedIconPath: session.defaultIconPath,
        customIconPath: session.customIcon?.filePath,
        origin: session.draft.origin,
        scope: session.draft.scope,
        manifestUrl: session.draft.manifestUrl,
        themeColor: session.draft.themeColor,
        backgroundColor: session.draft.backgroundColor,
        display: session.draft.display,
        currentUrl: launchUrl
      });
      if (result.ok) {
        try {
          await this.membershipFeature.recordUsage(AIRA_FEATURE_WEBAPP_INSTALL);
        } catch (_error) {
        }
      }
      this.shell.showToast(result.message);
    } catch (_error) {
      this.shell.showToast('添加到桌面失败，请稍后重试。');
    } finally {
      await this.iconSelectionService.discard(session.customIcon);
    }
  }

  private async buildDraft(
    snapshot: WebAppInstallShellSnapshot,
    currentUrl: string,
    currentTitle: string
  ): Promise<WebAppInstallDraft> {
    try {
      return await this.policyService.buildDraftForCurrentPageFromLifecyclePort(
        this.runtimeLifecyclePort,
        snapshot.tabId,
        currentUrl,
        currentTitle
      );
    } catch (_error) {
      return this.policyService.buildDefaultDraft(currentUrl, currentTitle);
    }
  }

  private async prepareDefaultIcon(snapshot: WebAppInstallShellSnapshot, currentUrl: string): Promise<string> {
    try {
      return await this.shortcutService.prepareWebPageShortcutIcon(snapshot.context, {
        url: currentUrl,
        favicon: snapshot.favicon
      });
    } catch (_error) {
      return '';
    }
  }

  private publishIconSnapshot(session: WebAppInstallSession, iconProcessing: boolean): void {
    this.publishDialogSnapshot({
      title: this.dialogSnapshot.title,
      url: this.dialogSnapshot.url,
      iconUri: session.customIcon?.previewUri ?? this.toPreviewUri(session.defaultIconPath),
      iconCustomized: session.customIcon !== undefined,
      iconProcessing: iconProcessing
    });
  }

  private publishDialogSnapshot(snapshot: WebAppInstallDialogSnapshot): void {
    this.dialogSnapshot = snapshot;
    this.shell.publishDialogSnapshot(snapshot);
  }

  private toPreviewUri(path: string): string {
    const normalized = path.trim();
    if (normalized.length === 0 || normalized.startsWith('file://')) {
      return normalized;
    }
    return fileUri.getUriFromPath(normalized);
  }

  private resolveIconErrorMessage(error: Object | undefined): string {
    if (error instanceof Error && error.message.trim().length > 0) {
      return error.message.trim();
    }
    return '无法处理这张图片，请换一张再试。';
  }
}
