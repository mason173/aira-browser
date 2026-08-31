import { InstalledUserScriptState } from './UserScriptMetadataModels';

export interface UserScriptExecutionReport {
  scriptId: string;
  success: boolean;
  errorMessage: string;
  /** Best-effort page-side execution duration used only for performance diagnostics. */
  durationMs?: number;
}

export type UserScriptRuntimeBlockReason = 'none' | 'private_mode';

export interface UserScriptRuntimeEligibility {
  executionAllowed: boolean;
  blockReason: UserScriptRuntimeBlockReason;
  matchingScripts: InstalledUserScriptState[];
}

export interface UserScriptInjectionSummary {
  injectedScriptCount: number;
  executionReportCount: number;
  failedScriptCount: number;
  failedScriptNames: string[];
  url: string;
  skipReason: string;
}

export interface UserScriptPageMenuCommandView {
  id: string;
  scriptId: string;
  commandId: string;
  scriptName: string;
  commandName: string;
}

export interface UserScriptPageScriptStatusView {
  scriptId: string;
  scriptName: string;
  iconUrl: string;
}

export interface UserScriptPageActionsState {
  url: string;
  message: string;
  hasPage: boolean;
  hasMatchingScripts: boolean;
  hasMenuCommands: boolean;
  matchingScriptCount: number;
  commands: UserScriptPageMenuCommandView[];
  scripts: UserScriptPageScriptStatusView[];
}
