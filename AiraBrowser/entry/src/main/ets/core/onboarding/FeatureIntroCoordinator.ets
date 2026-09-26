import {
  sharedFeatureIntroRepository,
  sharedStartupWelcomeIntroRepository
} from '../../app/bootstrap/BrowserAppRuntime';
import {
  FeatureIntroExitDestination,
  resolveFeatureIntroExitDestination
} from './FeatureIntroRoutePolicy';

export interface FeatureIntroHost {
  leave: (destination: FeatureIntroExitDestination) => void;
}

export class FeatureIntroCoordinator {
  private readonly host: FeatureIntroHost;
  private leaving: boolean = false;

  constructor(host: FeatureIntroHost) {
    this.host = host;
  }

  finish(): void {
    if (this.leaving) {
      return;
    }
    this.leaving = true;
    const leave = (): void => {
      this.host.leave(resolveFeatureIntroExitDestination(
        sharedStartupWelcomeIntroRepository.hasCompletedCurrentVersion()
      ));
    };
    sharedFeatureIntroRepository.completeCurrentVersion()
      .then((): void => {
        leave();
      })
      .catch((_error: Error) => {
        leave();
      });
  }

  abandonLeave(): void {
    this.leaving = false;
  }
}
