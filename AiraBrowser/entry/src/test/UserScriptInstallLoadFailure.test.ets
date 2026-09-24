import { describe, expect, it } from '@ohos/hypium';
import {
  resolveUserScriptDesktopColumnCount,
  resolveUserScriptInstallLoadErrorMessage,
  resolveUserScriptInstallLoadFailureTitle,
  resolveUserScriptInstallSurfaceMode
} from '../main/ets/core/userscripts/UserScriptsSettingsViewModel';
import {
  describeUserScriptSourceTransportFailure,
  isUserScriptSourceUnreachableErrorCode,
  UserScriptHttpErrorShape,
  USER_SCRIPT_SOURCE_DOWNLOAD_FAILED_MESSAGE,
  USER_SCRIPT_SOURCE_UNREACHABLE_MESSAGE
} from '../main/ets/services/userscripts/UserScriptSourceFetchService';

const UNREACHABLE_MESSAGE: string = USER_SCRIPT_SOURCE_UNREACHABLE_MESSAGE;

export default function userScriptInstallLoadFailureTest(): void {
  describe('UserScript install load failure', () => {
    it('keeps a network failure visible instead of an empty install surface', 0, () => {
      const message = resolveUserScriptInstallLoadErrorMessage('', false, UNREACHABLE_MESSAGE);

      expect(message).assertEqual(UNREACHABLE_MESSAGE);
      expect(resolveUserScriptInstallSurfaceMode('', false, message)).assertEqual('failure');
      expect(resolveUserScriptInstallLoadFailureTitle(message)).assertEqual('无法连接脚本地址');
    });

    it('keeps the desktop script grid to the pane width', 0, () => {
      expect(resolveUserScriptDesktopColumnCount(0)).assertEqual(1);
      expect(resolveUserScriptDesktopColumnCount(520)).assertEqual(1);
      expect(resolveUserScriptDesktopColumnCount(700)).assertEqual(2);
      expect(resolveUserScriptDesktopColumnCount(1024)).assertEqual(3);
      expect(resolveUserScriptDesktopColumnCount(1600)).assertEqual(4);
    });

    it('shows loading while a retry is in flight and content after the source arrives', 0, () => {
      expect(resolveUserScriptInstallLoadErrorMessage('', true, UNREACHABLE_MESSAGE)).assertEqual('');
      expect(resolveUserScriptInstallSurfaceMode('', true, UNREACHABLE_MESSAGE)).assertEqual('loading');
      expect(resolveUserScriptInstallSurfaceMode('// ==UserScript==', false, UNREACHABLE_MESSAGE))
        .assertEqual('content');
    });

    it('describes blocked or unreachable script hosts as a retryable network failure', 0, () => {
      expect(isUserScriptSourceUnreachableErrorCode(2300006)).assertTrue();
      expect(isUserScriptSourceUnreachableErrorCode(2300007)).assertTrue();
      expect(isUserScriptSourceUnreachableErrorCode(2300028)).assertTrue();
      const hostError: UserScriptHttpErrorShape = { code: 2300006 };
      const unknownError: UserScriptHttpErrorShape = { code: 2300999 };
      const textError: UserScriptHttpErrorShape = { message: "Couldn't resolve host name" };
      expect(describeUserScriptSourceTransportFailure(hostError))
        .assertEqual(USER_SCRIPT_SOURCE_UNREACHABLE_MESSAGE);
      expect(describeUserScriptSourceTransportFailure(unknownError))
        .assertEqual(USER_SCRIPT_SOURCE_DOWNLOAD_FAILED_MESSAGE);
      expect(describeUserScriptSourceTransportFailure(textError))
        .assertEqual(USER_SCRIPT_SOURCE_UNREACHABLE_MESSAGE);
    });
  });
}
