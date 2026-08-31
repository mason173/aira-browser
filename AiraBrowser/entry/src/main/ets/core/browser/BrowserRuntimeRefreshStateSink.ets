import { WebTabRuntimeRecord } from '../web/WebTabRuntime';

export interface BrowserRuntimeRefreshStateSink {
  applyReplacementRuntimeState: (runtime: WebTabRuntimeRecord) => void;
}
