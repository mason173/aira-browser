import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserLaunchPayload } from '../../app/runtime/BrowserWindowRuntime';
import {
  WebAppInstallRepository,
  sharedWebAppInstallRepository
} from '../../data/webapps/WebAppInstallRepository';

const DOMAIN = 0x0000;
const TAG = 'WebAppMission';

export class DesktopWebEntryMissionIdentityService {
  private installRepository: WebAppInstallRepository;

  constructor(installRepository: WebAppInstallRepository = sharedWebAppInstallRepository) {
    this.installRepository = installRepository;
  }

  apply(context: common.UIAbilityContext, launchPayload: BrowserLaunchPayload, windowId: string, source: string = 'launch'): void {
    if (launchPayload.shortcut === undefined || windowId === 'window-main') {
      return;
    }
    const title = launchPayload.shortcut.title.trim();
    if (title.length > 0) {
      context.setMissionLabel(title)
        .then(() => {
          hilog.info(DOMAIN, TAG, 'Applied mission label from %{public}s for %{public}s.', source, windowId);
        })
        .catch((error: Error) => {
          hilog.warn(DOMAIN, TAG, 'Failed to set mission label: %{public}s', JSON.stringify(error));
        });
    }
    if (title.length > 0) {
      return;
    }
    this.installRepository.findByShortcutId(launchPayload.shortcut.shortcutId)
      .then((record) => {
        const recordTitle = record?.title.trim() ?? '';
        if (recordTitle.length > 0) {
          context.setMissionLabel(recordTitle)
            .then(() => {
              hilog.info(DOMAIN, TAG, 'Applied mission label from record for %{public}s.', windowId);
            })
            .catch((error: Error) => {
              hilog.warn(DOMAIN, TAG, 'Failed to set mission label from record: %{public}s', JSON.stringify(error));
            });
        }
      })
      .catch((error: Error) => {
        hilog.warn(DOMAIN, TAG, 'Failed to resolve mission identity record: %{public}s', JSON.stringify(error));
      });
  }
}
