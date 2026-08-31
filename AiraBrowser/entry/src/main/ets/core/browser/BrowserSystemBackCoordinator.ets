export type BrowserSystemBackAction =
  'navigate_web_back' |
  'prompt_exit' |
  'allow_system_default';

export interface BrowserSystemBackRequest {
  showHomePage: boolean;
  webPageVisible: boolean;
  webAppMode: boolean;
  lastExitPromptAt: number;
  now: number;
}

const EXIT_PROMPT_INTERVAL_MS: number = 2000;

export class BrowserSystemBackCoordinator {
  resolveBackAction(request: BrowserSystemBackRequest): BrowserSystemBackAction {
    if (request.webPageVisible) {
      return 'navigate_web_back';
    }
    if (request.showHomePage && request.now - request.lastExitPromptAt > EXIT_PROMPT_INTERVAL_MS) {
      return 'prompt_exit';
    }
    return 'allow_system_default';
  }
}
