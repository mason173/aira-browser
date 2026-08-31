import { AbilityConstant, common } from '@kit.AbilityKit';
import {
  DownloadRuntimeDiagnosticEvent,
  DownloadRuntimeDiagnosticRecorder
} from '../../common/models/RuntimeDiagnosticModels';

/**
 * Crash diagnostics are intentionally disabled in the open-source client.
 * Keep this compatibility surface so existing runtime owners do not need to
 * know whether the selected distribution includes private diagnostics.
 */
export class AppCrashDiagnosticsService implements DownloadRuntimeDiagnosticRecorder {
  setCollectionEnabled(_enabled: boolean): void {
    // Reserved for a future explicit local-export flow.
  }

  initialize(_context: common.Context, _launchParam?: AbilityConstant.LaunchParam): void {
    // Automatic fault collection and cloud upload are not part of the client.
  }

  recordLifecycle(_context: common.Context, _source: string, _message: string = ''): void {
    // Intentionally empty.
  }

  recordDiagnostic(
    _context: common.Context,
    _module: string,
    _owner: string,
    _operation: string,
    _state: string,
    _result: string
  ): void {
    // Intentionally empty.
  }

  recordDiagnosticCheckpoint(
    _context: common.Context,
    _module: string,
    _owner: string,
    _operation: string,
    _state: string,
    _result: string
  ): void {
    // Intentionally empty.
  }

  recordDiagnosticAndWait(
    _context: common.Context,
    _module: string,
    _owner: string,
    _operation: string,
    _state: string,
    _result: string
  ): Promise<void> {
    return Promise.resolve();
  }

  recordDownloadRuntimeDiagnostic(_event: DownloadRuntimeDiagnosticEvent): void {
    // Intentionally empty.
  }

  recordDownloadRuntimeDiagnosticAndWait(_event: DownloadRuntimeDiagnosticEvent): Promise<void> {
    return Promise.resolve();
  }

  notifyForeground(_context: common.Context): void {
    // Intentionally empty.
  }

  handleDelayedFaultReports(_context: common.Context): void {
    // Intentionally empty; no platform fault extension is registered.
  }
}
