import { BrowserDataBoundaryInput } from '../../common/models/BrowserModels';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';
import { AppServiceModeGateService } from '../../services/settings/AppServiceModeGateService';
import { SyncActivationResult } from '../sync/SyncActivationModels';
import {
  sharedAiraSyncConfigStore,
  sharedHuaweiAccountMutationCoordinator,
  sharedPreferencesRepository,
  sharedStartupWelcomeIntroRepository
} from '../../app/bootstrap/BrowserAppRuntime';
import { hasStartupWelcomeIntroAccountOrSync } from './StartupWelcomeIntroCompletionPolicy';
import {
  StartupWelcomeIntroActionId,
  StartupWelcomeIntroFacts,
  StartupWelcomeIntroViewModel,
  StartupWelcomeIntroViewState
} from './StartupWelcomeIntroViewModel';

/** Result of the native Huawei ID button, decoupled from AccountKit types. */
export interface StartupWelcomeIntroLoginCredential {
  errorCode: number;
  errorMessage: string;
  authorizationCode: string;
  openId: string;
}

/**
 * Effects the welcome intro page must perform. The coordinator owns every
 * decision (distribution/service-mode gating, credential validation, sign-in,
 * completion write) so the page stays a UI shell.
 */
export interface StartupWelcomeIntroHost {
  setBusy: (busy: boolean) => void;
  showMessage: (message: string) => void;
  navigateToPersonalServer: () => void;
  navigateToWebdavConfig: () => void;
  openUserAgreement: () => void;
  openPrivacyPolicy: () => void;
  leaveIntro: () => void;
}

const STARTUP_WELCOME_LOGIN_CANCELLED_CODE: number = 1001502012;
const STARTUP_WELCOME_EMPTY_BOUNDARY: BrowserDataBoundaryInput = {
  dataScope: '',
  privacyMode: ''
};

export class StartupWelcomeIntroCoordinator {
  private readonly host: StartupWelcomeIntroHost;
  private readonly serviceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  private readonly viewModel: StartupWelcomeIntroViewModel = new StartupWelcomeIntroViewModel();
  private completionRequested: boolean = false;

  constructor(host: StartupWelcomeIntroHost) {
    this.host = host;
  }

  buildState(): StartupWelcomeIntroViewState {
    const facts: StartupWelcomeIntroFacts = {
      huaweiAccountAvailable: AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_account') &&
        sharedHuaweiAccountMutationCoordinator.canSignIn(STARTUP_WELCOME_EMPTY_BOUNDARY),
      optionalServiceAvailable: this.serviceModeGateService.canUseOptionalService()
    };
    return this.viewModel.buildState(facts);
  }

  handleAction(id: StartupWelcomeIntroActionId): void {
    if (id === 'personal_server') {
      this.host.navigateToPersonalServer();
      return;
    }
    this.host.navigateToWebdavConfig();
  }

  handleLoginCredential(credential: StartupWelcomeIntroLoginCredential): void {
    if (credential.errorCode !== 0) {
      if (credential.errorCode !== STARTUP_WELCOME_LOGIN_CANCELLED_CODE) {
        this.host.showMessage(
          credential.errorMessage.length > 0 ? credential.errorMessage : '华为账号登录失败'
        );
      }
      return;
    }
    if (credential.authorizationCode.length <= 0 && credential.openId.length <= 0) {
      this.host.showMessage('华为账号登录未完成');
      return;
    }
    this.host.setBusy(true);
    sharedHuaweiAccountMutationCoordinator.signIn(STARTUP_WELCOME_EMPTY_BOUNDARY)
      .then((result: SyncActivationResult) => {
        if (result.type === 'failed') {
          this.host.setBusy(false);
          this.host.showMessage(result.message.length > 0 ? result.message : result.title);
          return;
        }
        this.completeIntro();
      })
      .catch((_error: Error) => {
        this.host.setBusy(false);
        this.host.showMessage('华为账号登录失败');
      });
  }

  /** A provider page returns here after saving; hand off without a second tap. */
  finishIfConfiguredOnResume(): void {
    if (hasStartupWelcomeIntroAccountOrSync(sharedAiraSyncConfigStore.getSettings())) {
      this.completeIntro();
    }
  }

  openUserAgreement(): void {
    this.host.openUserAgreement();
  }

  openPrivacyPolicy(): void {
    this.host.openPrivacyPolicy();
  }

  completeIntro(): void {
    if (this.completionRequested) {
      return;
    }
    this.completionRequested = true;
    this.host.setBusy(true);
    sharedStartupWelcomeIntroRepository.completeCurrentVersion()
      .then((): void => {
        this.host.leaveIntro();
      })
      .catch((_error: Error) => {
        this.host.leaveIntro();
      });
  }
}
