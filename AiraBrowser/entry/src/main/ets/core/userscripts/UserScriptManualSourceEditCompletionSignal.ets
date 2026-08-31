export const USER_SCRIPT_MANUAL_SOURCE_EDIT_COMPLETION_REVISION_KEY: string =
  'aira.userscripts.manualSourceEditCompletionRevision';

export class UserScriptManualSourceEditCompletionSignal {
  bump(): number {
    const nextRevision =
      (AppStorage.get<number>(USER_SCRIPT_MANUAL_SOURCE_EDIT_COMPLETION_REVISION_KEY) ?? 0) + 1;
    AppStorage.setOrCreate(USER_SCRIPT_MANUAL_SOURCE_EDIT_COMPLETION_REVISION_KEY, nextRevision);
    return nextRevision;
  }
}
