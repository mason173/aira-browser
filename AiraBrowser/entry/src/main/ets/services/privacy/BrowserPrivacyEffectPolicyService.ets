import {
  BrowserDataBoundary,
  BrowserDataBoundaryInput
} from '../../common/models/BrowserModels';
import { BrowserProfileBoundaryService } from '../../core/browser/BrowserProfileBoundaryService';

export type BrowserPrivacyEffectOutcome = 'allow' | 'deny' | 'confirm';
export type BrowserPrivacyEffectClassification =
  'ambient_trace' |
  'session_local_state' |
  'explicit_user_persistence' |
  'remote_account_sync_mutation' |
  'unclassified';
export type BrowserPrivacyEffectTargetScope =
  'private_session_state' |
  'persistent_private_data' |
  'regular_profile_data' |
  'device_preferences' |
  'user_selected_external_location' |
  'remote_account_sync_state';
export type BrowserPrivacyEffectIntent =
  'download_settings_read' |
  'download_settings_write' |
  'settings_device_preference_read' |
  'settings_device_preference_write' |
  'app_service_mode_sync_deactivation' |
  'download_session_task_read' |
  'download_session_task_write' |
  'download_file_export' |
  'download_session_cleanup' |
  'membership_entitlement_read' |
  'huawei_account_login' |
  'huawei_account_sign_out' |
  'huawei_account_identity_reconcile' |
  'membership_account_profile_reconcile' |
  'membership_purchase' |
  'membership_restore_purchase' |
  'membership_subscription_management' |
  'history_visit_write' |
  'regular_profile_management_read' |
  'regular_profile_management_navigation' |
  'regular_profile_management_mutation' |
  'regular_profile_management_share' |
  'regular_profile_management_export' |
  'private_bookmark_share' |
  'private_bookmark_export' |
  'offline_page_save' |
  'user_script_export' |
  'browser_open_in_regular_profile';

export type BrowserPrivacyDataKind =
  'history_visit' |
  'tab_session_restore' |
  'recently_closed_tab' |
  'home_shortcuts' |
  'private_bookmarks' |
  'adblock_stats' |
  'http_fallback_exception' |
  'https_first_retry_provenance';

export interface BrowserPrivacyEffectRequest {
  intent: string;
  requestingBoundary: BrowserDataBoundary;
  targetScope: BrowserPrivacyEffectTargetScope;
  targetIsClear: boolean;
}

export interface BrowserPrivacyEffectDecision {
  intent: string;
  outcome: BrowserPrivacyEffectOutcome;
  classification: BrowserPrivacyEffectClassification;
  targetScope: BrowserPrivacyEffectTargetScope;
  reason: string;
  diagnosticSummary: string;
}

export interface BrowserPrivacyDataPolicy {
  boundary: BrowserDataBoundary;
  persistentReadAllowed: boolean;
  persistentWriteAllowed: boolean;
  reason: string;
  summaryLine: string;
}

interface BrowserPrivacyEffectCatalogEntry {
  intent: BrowserPrivacyEffectIntent;
  classification: BrowserPrivacyEffectClassification;
  targetScope: BrowserPrivacyEffectTargetScope;
}

interface BrowserPrivacyDataPolicyMatrixItem {
  persistentReadAllowed: boolean;
  persistentWriteAllowed: boolean;
  reason: string;
}

const BROWSER_PRIVACY_EFFECT_CATALOG: BrowserPrivacyEffectCatalogEntry[] = [
  {
    intent: 'download_settings_read',
    classification: 'session_local_state',
    targetScope: 'device_preferences'
  },
  {
    intent: 'download_settings_write',
    classification: 'explicit_user_persistence',
    targetScope: 'device_preferences'
  },
  {
    intent: 'settings_device_preference_read',
    classification: 'session_local_state',
    targetScope: 'device_preferences'
  },
  {
    intent: 'settings_device_preference_write',
    classification: 'explicit_user_persistence',
    targetScope: 'device_preferences'
  },
  {
    intent: 'app_service_mode_sync_deactivation',
    classification: 'remote_account_sync_mutation',
    targetScope: 'remote_account_sync_state'
  },
  {
    intent: 'download_session_task_read',
    classification: 'session_local_state',
    targetScope: 'private_session_state'
  },
  {
    intent: 'download_session_task_write',
    classification: 'session_local_state',
    targetScope: 'private_session_state'
  },
  {
    intent: 'download_file_export',
    classification: 'explicit_user_persistence',
    targetScope: 'user_selected_external_location'
  },
  {
    intent: 'download_session_cleanup',
    classification: 'session_local_state',
    targetScope: 'private_session_state'
  },
  {
    intent: 'membership_entitlement_read',
    classification: 'session_local_state',
    targetScope: 'private_session_state'
  },
  {
    intent: 'huawei_account_login',
    classification: 'remote_account_sync_mutation',
    targetScope: 'remote_account_sync_state'
  },
  {
    intent: 'huawei_account_sign_out',
    classification: 'remote_account_sync_mutation',
    targetScope: 'remote_account_sync_state'
  },
  {
    intent: 'huawei_account_identity_reconcile',
    classification: 'remote_account_sync_mutation',
    targetScope: 'remote_account_sync_state'
  },
  {
    intent: 'membership_account_profile_reconcile',
    classification: 'remote_account_sync_mutation',
    targetScope: 'remote_account_sync_state'
  },
  {
    intent: 'membership_purchase',
    classification: 'remote_account_sync_mutation',
    targetScope: 'remote_account_sync_state'
  },
  {
    intent: 'membership_restore_purchase',
    classification: 'remote_account_sync_mutation',
    targetScope: 'remote_account_sync_state'
  },
  {
    intent: 'membership_subscription_management',
    classification: 'remote_account_sync_mutation',
    targetScope: 'remote_account_sync_state'
  },
  {
    intent: 'history_visit_write',
    classification: 'ambient_trace',
    targetScope: 'regular_profile_data'
  },
  {
    intent: 'regular_profile_management_read',
    classification: 'explicit_user_persistence',
    targetScope: 'regular_profile_data'
  },
  {
    intent: 'regular_profile_management_navigation',
    classification: 'explicit_user_persistence',
    targetScope: 'regular_profile_data'
  },
  {
    intent: 'regular_profile_management_mutation',
    classification: 'explicit_user_persistence',
    targetScope: 'regular_profile_data'
  },
  {
    intent: 'regular_profile_management_share',
    classification: 'explicit_user_persistence',
    targetScope: 'regular_profile_data'
  },
  {
    intent: 'regular_profile_management_export',
    classification: 'explicit_user_persistence',
    targetScope: 'user_selected_external_location'
  },
  {
    intent: 'private_bookmark_share',
    classification: 'explicit_user_persistence',
    targetScope: 'user_selected_external_location'
  },
  {
    intent: 'private_bookmark_export',
    classification: 'explicit_user_persistence',
    targetScope: 'user_selected_external_location'
  },
  {
    intent: 'offline_page_save',
    classification: 'explicit_user_persistence',
    targetScope: 'regular_profile_data'
  },
  {
    intent: 'user_script_export',
    classification: 'explicit_user_persistence',
    targetScope: 'user_selected_external_location'
  },
  {
    intent: 'browser_open_in_regular_profile',
    classification: 'explicit_user_persistence',
    targetScope: 'regular_profile_data'
  }
];

export class BrowserPrivacyEffectPolicyService {
  private profileBoundaryService: BrowserProfileBoundaryService;

  constructor(profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()) {
    this.profileBoundaryService = profileBoundaryService;
  }

  decide(request: BrowserPrivacyEffectRequest): BrowserPrivacyEffectDecision {
    const entry = this.resolveCatalogEntry(request.intent);
    const isPrivateSession = this.profileBoundaryService.isSessionEphemeral(request.requestingBoundary);
    if (entry === undefined) {
      return this.buildDecision(
        request,
        isPrivateSession ? 'deny' : 'allow',
        'unclassified',
        isPrivateSession ? 'unclassified_private_effect' : 'unclassified_regular_unchanged'
      );
    }
    if (entry.targetScope !== request.targetScope) {
      return this.buildDecision(request, 'deny', entry.classification, 'catalog_target_scope_mismatch');
    }
    if (isPrivateSession && entry.classification === 'remote_account_sync_mutation') {
      return this.buildDecision(request, 'deny', entry.classification, 'private_remote_mutation_blocked');
    }
    if (isPrivateSession && entry.classification === 'ambient_trace') {
      return this.buildDecision(request, 'deny', entry.classification, 'private_ambient_trace_blocked');
    }
    if (!request.targetIsClear &&
      (request.targetScope === 'regular_profile_data' || request.targetScope === 'remote_account_sync_state')) {
      return this.buildDecision(request, 'confirm', entry.classification, 'cross_scope_confirmation_required');
    }
    if (!request.targetIsClear && request.targetScope === 'user_selected_external_location') {
      return this.buildDecision(request, 'deny', entry.classification, 'external_target_not_selected');
    }
    return this.buildDecision(request, 'allow', entry.classification, 'catalog_effect_allowed');
  }

  resolveDataPolicy(kind: BrowserPrivacyDataKind, input: BrowserDataBoundaryInput): BrowserPrivacyDataPolicy {
    return this.resolveDataPolicyForBoundary(kind, this.profileBoundaryService.buildBoundary(input));
  }

  resolveDataPolicyForBoundary(
    kind: BrowserPrivacyDataKind,
    boundary: BrowserDataBoundary
  ): BrowserPrivacyDataPolicy {
    const matrix = this.profileBoundaryService.isSessionEphemeral(boundary)
      ? this.resolveSessionEphemeralDataPolicy(kind)
      : this.resolveProfilePersistentDataPolicy();
    return this.buildDataPolicy(kind, boundary, matrix);
  }

  shouldWritePersistentDataForBoundary(kind: BrowserPrivacyDataKind, boundary: BrowserDataBoundary): boolean {
    return this.resolveDataPolicyForBoundary(kind, boundary).persistentWriteAllowed;
  }

  private resolveCatalogEntry(intent: string): BrowserPrivacyEffectCatalogEntry | undefined {
    return BROWSER_PRIVACY_EFFECT_CATALOG.find((entry: BrowserPrivacyEffectCatalogEntry): boolean => {
      return entry.intent === intent;
    });
  }

  private resolveProfilePersistentDataPolicy(): BrowserPrivacyDataPolicyMatrixItem {
    return {
      persistentReadAllowed: true,
      persistentWriteAllowed: true,
      reason: 'profile_persistent'
    };
  }

  private resolveSessionEphemeralDataPolicy(kind: BrowserPrivacyDataKind): BrowserPrivacyDataPolicyMatrixItem {
    switch (kind) {
      case 'private_bookmarks':
        return {
          persistentReadAllowed: true,
          persistentWriteAllowed: true,
          reason: 'private_bookmarks_persistent_scope'
        };
      case 'home_shortcuts':
        return {
          persistentReadAllowed: true,
          persistentWriteAllowed: false,
          reason: 'private_home_reads_profile_shortcuts_readonly'
        };
      case 'history_visit':
      case 'tab_session_restore':
      case 'recently_closed_tab':
      case 'adblock_stats':
      case 'http_fallback_exception':
      case 'https_first_retry_provenance':
        return {
          persistentReadAllowed: false,
          persistentWriteAllowed: false,
          reason: 'private_not_persisted'
        };
      default:
        return {
          persistentReadAllowed: false,
          persistentWriteAllowed: false,
          reason: 'unclassified_private_data_effect'
        };
    }
  }

  private buildDataPolicy(
    kind: BrowserPrivacyDataKind,
    boundary: BrowserDataBoundary,
    matrix: BrowserPrivacyDataPolicyMatrixItem
  ): BrowserPrivacyDataPolicy {
    return {
      boundary: boundary,
      persistentReadAllowed: matrix.persistentReadAllowed,
      persistentWriteAllowed: matrix.persistentWriteAllowed,
      reason: matrix.reason,
      summaryLine: `privacyDataPolicy kind=${kind} profile=${boundary.profileId} privacy=${boundary.privacyMode} ` +
        `dataScope=${boundary.dataScope} session=${boundary.sessionId} partition=${boundary.storagePartitionId} ` +
        `persistentRead=${matrix.persistentReadAllowed ? 1 : 0} ` +
        `persistentWrite=${matrix.persistentWriteAllowed ? 1 : 0} reason=${matrix.reason}`
    };
  }

  private buildDecision(
    request: BrowserPrivacyEffectRequest,
    outcome: BrowserPrivacyEffectOutcome,
    classification: BrowserPrivacyEffectClassification,
    reason: string
  ): BrowserPrivacyEffectDecision {
    const boundary = request.requestingBoundary;
    const diagnosticIntent = classification === 'unclassified' ? 'unclassified' : request.intent;
    return {
      intent: request.intent,
      outcome: outcome,
      classification: classification,
      targetScope: request.targetScope,
      reason: reason,
      diagnosticSummary: `privacyEffect intent=${diagnosticIntent} outcome=${outcome} class=${classification} ` +
        `target=${request.targetScope} targetClear=${request.targetIsClear ? 1 : 0} ` +
        `privacy=${boundary.privacyMode} dataScope=${boundary.dataScope} reason=${reason}`
    };
  }
}
