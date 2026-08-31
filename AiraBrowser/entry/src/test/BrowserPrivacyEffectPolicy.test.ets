import { describe, expect, it } from '@ohos/hypium';
import { buildBrowserDataBoundary } from '../main/ets/common/models/BrowserModels';
import { BrowserPrivacyEffectPolicyService } from
  '../main/ets/services/privacy/BrowserPrivacyEffectPolicyService';

export default function browserPrivacyEffectPolicyTest(): void {
  describe('BrowserPrivacyEffectPolicy', () => {
    it('allows explicit Download Settings persistence from regular and private sessions', 0, () => {
      const policy = new BrowserPrivacyEffectPolicyService();
      const regularDecision = policy.decide({
        intent: 'download_settings_write',
        requestingBoundary: buildBrowserDataBoundary({
          privacyMode: 'regular',
          dataScope: 'profile_persistent'
        }),
        targetScope: 'device_preferences',
        targetIsClear: true
      });
      const privateDecision = policy.decide({
        intent: 'download_settings_write',
        requestingBoundary: buildBrowserDataBoundary({
          privacyMode: 'private',
          dataScope: 'session_ephemeral',
          sessionId: 'private-window-1'
        }),
        targetScope: 'device_preferences',
        targetIsClear: true
      });

      expect(regularDecision.outcome).assertEqual('allow');
      expect(privateDecision.outcome).assertEqual('allow');
      expect(privateDecision.classification).assertEqual('explicit_user_persistence');
      expect(privateDecision.targetScope).assertEqual('device_preferences');
    });

    it('keeps ambient History blocked and persistent private Bookmarks allowed', 0, () => {
      const policy = new BrowserPrivacyEffectPolicyService();
      const privateBoundary = buildBrowserDataBoundary({
        privacyMode: 'private',
        dataScope: 'session_ephemeral',
        sessionId: 'private-window-2'
      });

      const historyPolicy = policy.resolveDataPolicyForBoundary('history_visit', privateBoundary);
      const bookmarkPolicy = policy.resolveDataPolicyForBoundary('private_bookmarks', privateBoundary);

      expect(historyPolicy.persistentWriteAllowed).assertFalse();
      expect(historyPolicy.reason).assertEqual('private_not_persisted');
      expect(bookmarkPolicy.persistentReadAllowed).assertTrue();
      expect(bookmarkPolicy.persistentWriteAllowed).assertTrue();
      expect(bookmarkPolicy.reason).assertEqual('private_bookmarks_persistent_scope');
    });

    it('fails closed for an unclassified private effect without changing regular behavior', 0, () => {
      const policy = new BrowserPrivacyEffectPolicyService();
      const regularDecision = policy.decide({
        intent: 'unclassified_feature_effect',
        requestingBoundary: buildBrowserDataBoundary({
          privacyMode: 'regular',
          dataScope: 'profile_persistent'
        }),
        targetScope: 'regular_profile_data',
        targetIsClear: true
      });
      const privateDecision = policy.decide({
        intent: 'unclassified_feature_effect',
        requestingBoundary: buildBrowserDataBoundary({
          privacyMode: 'private',
          dataScope: 'session_ephemeral',
          sessionId: 'private-window-secret'
        }),
        targetScope: 'private_session_state',
        targetIsClear: true
      });

      expect(regularDecision.outcome).assertEqual('allow');
      expect(privateDecision.outcome).assertEqual('deny');
      expect(privateDecision.classification).assertEqual('unclassified');
      expect(privateDecision.reason).assertEqual('unclassified_private_effect');
      expect(privateDecision.diagnosticSummary.indexOf('private-window-secret') < 0).assertTrue();
      expect(privateDecision.diagnosticSummary.indexOf('unclassified_feature_effect') < 0).assertTrue();
    });

    it('denies ambient History writes and confirms an unclear regular-profile transition', 0, () => {
      const policy = new BrowserPrivacyEffectPolicyService();
      const privateBoundary = buildBrowserDataBoundary({
        privacyMode: 'private',
        dataScope: 'session_ephemeral'
      });
      const historyDecision = policy.decide({
        intent: 'history_visit_write',
        requestingBoundary: privateBoundary,
        targetScope: 'regular_profile_data',
        targetIsClear: false
      });
      const transitionDecision = policy.decide({
        intent: 'browser_open_in_regular_profile',
        requestingBoundary: privateBoundary,
        targetScope: 'regular_profile_data',
        targetIsClear: false
      });

      expect(historyDecision.outcome).assertEqual('deny');
      expect(historyDecision.classification).assertEqual('ambient_trace');
      expect(transitionDecision.outcome).assertEqual('confirm');
      expect(transitionDecision.reason).assertEqual('cross_scope_confirmation_required');
    });

    it('catalogs every Download tracer intent exactly once', 0, () => {
      const policy = new BrowserPrivacyEffectPolicyService();
      const expectedDownloadIntents: string[] = [
        'download_settings_read',
        'download_settings_write',
        'download_session_task_read',
        'download_session_task_write',
        'download_file_export',
        'download_session_cleanup'
      ];
      expectedDownloadIntents.forEach((intent: string) => {
        const targetScope = resolveDownloadTargetScope(intent);
        const decision = policy.decide({
          intent: intent,
          requestingBoundary: buildBrowserDataBoundary({
            privacyMode: 'private',
            dataScope: 'session_ephemeral'
          }),
          targetScope: targetScope,
          targetIsClear: true
        });
        expect(decision.classification === 'unclassified').assertFalse();
      });
    });

    it('catalogs regular profile management and user-script export effects', 0, () => {
      const policy = new BrowserPrivacyEffectPolicyService();
      const regularBoundary = buildBrowserDataBoundary({
        privacyMode: 'regular',
        dataScope: 'profile_persistent'
      });
      const privateBoundary = buildBrowserDataBoundary({
        privacyMode: 'private',
        dataScope: 'session_ephemeral',
        sessionId: 'private-management-test'
      });
      const managementRead = policy.decide({
        intent: 'regular_profile_management_read',
        requestingBoundary: regularBoundary,
        targetScope: 'regular_profile_data',
        targetIsClear: true
      });
      const managementMutation = policy.decide({
        intent: 'regular_profile_management_mutation',
        requestingBoundary: privateBoundary,
        targetScope: 'regular_profile_data',
        targetIsClear: true
      });
      const exportDecision = policy.decide({
        intent: 'user_script_export',
        requestingBoundary: privateBoundary,
        targetScope: 'user_selected_external_location',
        targetIsClear: true
      });
      const unresolvedExport = policy.decide({
        intent: 'user_script_export',
        requestingBoundary: privateBoundary,
        targetScope: 'user_selected_external_location',
        targetIsClear: false
      });

      expect(managementRead.outcome).assertEqual('allow');
      expect(managementRead.classification).assertEqual('explicit_user_persistence');
      expect(managementMutation.outcome).assertEqual('allow');
      expect(managementMutation.targetScope).assertEqual('regular_profile_data');
      expect(exportDecision.outcome).assertEqual('allow');
      expect(exportDecision.classification).assertEqual('explicit_user_persistence');
      expect(unresolvedExport.outcome).assertEqual('deny');
      expect(unresolvedExport.reason).assertEqual('external_target_not_selected');
    });
  });
}

function resolveDownloadTargetScope(intent: string):
  'private_session_state' | 'device_preferences' | 'user_selected_external_location' {
  if (intent === 'download_settings_read' || intent === 'download_settings_write') {
    return 'device_preferences';
  }
  if (intent === 'download_file_export') {
    return 'user_selected_external_location';
  }
  return 'private_session_state';
}
