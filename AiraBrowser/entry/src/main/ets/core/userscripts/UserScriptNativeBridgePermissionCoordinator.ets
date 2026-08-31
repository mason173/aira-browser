import { UserScriptRuntimeStateRepository } from '../../data/userscripts/UserScriptRuntimeStateRepository';
import { UserScriptInjectionPhase } from '../../features/userscripts/UserScriptRuntimeStateModels';
import {
  RawUserScriptNativeBridgePayload,
  UserScriptNativeBridgeRoute,
  UserScriptNativeBridgeTokenRecord,
  UserScriptNativeBridgeValidation
} from '../../features/userscripts/UserScriptNativeBridgeModels';
import { UserScriptCapabilityContractService } from '../../services/userscripts/UserScriptCapabilityContractService';
import { UserScriptMatchService } from '../../services/userscripts/UserScriptMatchService';
import { UserScriptRuntimeReadinessCoordinator } from './UserScriptRuntimeReadinessCoordinator';

export class UserScriptNativeBridgePermissionCoordinator {
  private runtimeStateRepository: UserScriptRuntimeStateRepository;
  private readinessCoordinator: UserScriptRuntimeReadinessCoordinator;
  private capabilityContract: UserScriptCapabilityContractService = new UserScriptCapabilityContractService();
  private matchService: UserScriptMatchService = new UserScriptMatchService();

  constructor(
    runtimeStateRepository: UserScriptRuntimeStateRepository,
    readinessCoordinator: UserScriptRuntimeReadinessCoordinator
  ) {
    this.runtimeStateRepository = runtimeStateRepository;
    this.readinessCoordinator = readinessCoordinator;
  }

  validate(
    payload: RawUserScriptNativeBridgePayload,
    currentUrl: string,
    route: UserScriptNativeBridgeRoute,
    tokenRecords: Record<string, UserScriptNativeBridgeTokenRecord | undefined>
  ): UserScriptNativeBridgeValidation {
    const scriptId = String(payload.scriptId ?? '').trim();
    const token = String(payload.token ?? '').trim();
    const capability = String(payload.capability ?? '').trim();
    if (scriptId.length === 0 || token.length === 0 || capability.length === 0) {
      return this.failValidation('missing-bridge-auth');
    }
    const tokenRecord = tokenRecords[token];
    // Tokens are process-memory nonces. Route, grant, enabled state, and the
    // current URL remain the authority checks for every individual request.
    if (tokenRecord === undefined || tokenRecord.scriptId !== scriptId) {
      return this.failValidation('invalid-bridge-token');
    }
    if (String(payload.kind ?? '').trim() !== route.requestKind || capability !== route.capability) {
      return this.failValidation('capability-mismatch');
    }
    const script = this.readinessCoordinator.findExecutionReadyScript(scriptId);
    if (script === undefined || !script.enabled) {
      return this.failValidation('script-disabled');
    }
    if (!this.capabilityContract.hasGrant(script, route.capability)) {
      return this.failValidation('grant-denied');
    }
    const pageUrl = currentUrl.trim();
    if (pageUrl.length === 0) {
      return this.failValidation('missing-page-url');
    }
    if (!this.matchService.matchesScript(script, pageUrl)) {
      return this.failValidation('url-not-matched');
    }
    return {
      ok: true,
      scriptId: script.id,
      message: ''
    };
  }

  recordBridgeRejected(
    payload: RawUserScriptNativeBridgePayload,
    currentUrl: string,
    capability: string,
    reason: string,
    authorizedScriptId: string
  ): void {
    const scriptId = authorizedScriptId.trim().length > 0 ?
      authorizedScriptId.trim() :
      String(payload.scriptId ?? '').trim();
    if (scriptId.length === 0) {
      return;
    }
    const runtimeScript = this.readinessCoordinator.findExecutionReadyScript(scriptId);
    const injectionPhase: UserScriptInjectionPhase = runtimeScript?.runAt ?? 'unknown';
    void this.runtimeStateRepository.recordBridgeRejected(
      scriptId,
      currentUrl.trim(),
      injectionPhase,
      capability,
      reason
    );
  }

  private failValidation(message: string): UserScriptNativeBridgeValidation {
    return {
      ok: false,
      scriptId: '',
      message: message
    };
  }

}
