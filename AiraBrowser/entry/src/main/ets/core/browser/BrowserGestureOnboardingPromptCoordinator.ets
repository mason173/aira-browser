import { GestureOnboardingPromptRepository } from '../../data/onboarding/GestureOnboardingPromptRepository';

const GESTURE_ONBOARDING_PROMPT_DELAY_MS: number = 1400;
const GESTURE_ONBOARDING_PROMPT_KEY: string = 'bottom_gesture_onboarding_v1';

export interface BrowserGestureOnboardingPromptEligibilityInput {
  shellFamily: 'phone' | 'large_screen';
  appVisible: boolean;
  privateMode: boolean;
  blockingSurfaceVisible: boolean;
  topOffsetVp: number;
}

export interface BrowserGestureOnboardingTopPromptState {
  visible: boolean;
  key: string;
  topOffsetVp: number;
  title: string;
  subtitle: string;
}

export const HIDDEN_BROWSER_GESTURE_ONBOARDING_TOP_PROMPT_STATE: BrowserGestureOnboardingTopPromptState = {
  visible: false,
  key: '',
  topOffsetVp: 0,
  title: '',
  subtitle: ''
};

const VISIBLE_BROWSER_GESTURE_ONBOARDING_PROMPT_COPY: BrowserGestureOnboardingTopPromptState = {
  visible: true,
  key: GESTURE_ONBOARDING_PROMPT_KEY,
  topOffsetVp: 0,
  title: '底部手势提示',
  subtitle: '两侧上滑回主页 · 中间上滑打开工具'
};

export class BrowserGestureOnboardingPromptCoordinator {
  private repository: GestureOnboardingPromptRepository;
  private scheduleTimer: number = -1;
  private generation: number = 0;

  constructor(repository: GestureOnboardingPromptRepository) {
    this.repository = repository;
  }

  scheduleFirstPrompt(
    inputProvider: () => BrowserGestureOnboardingPromptEligibilityInput,
    onStateChange: (state: BrowserGestureOnboardingTopPromptState) => void
  ): void {
    this.cancelScheduleTimer();
    if (this.repository.hasCompleted()) {
      return;
    }
    const scheduleGeneration = this.generation + 1;
    this.generation = scheduleGeneration;
    this.scheduleTimer = setTimeout(() => {
      this.scheduleTimer = -1;
      if (this.generation !== scheduleGeneration) {
        return;
      }
      const input = inputProvider();
      const nextState = this.showIfEligible(input);
      if (nextState.visible) {
        onStateChange(nextState);
      }
    }, GESTURE_ONBOARDING_PROMPT_DELAY_MS);
  }

  buildTopPromptState(
    state: BrowserGestureOnboardingTopPromptState,
    topOffsetVp: number
  ): BrowserGestureOnboardingTopPromptState {
    if (!state.visible) {
      return HIDDEN_BROWSER_GESTURE_ONBOARDING_TOP_PROMPT_STATE;
    }
    return {
      visible: true,
      key: state.key,
      topOffsetVp: topOffsetVp,
      title: state.title,
      subtitle: state.subtitle
    };
  }

  dismiss(state: BrowserGestureOnboardingTopPromptState): BrowserGestureOnboardingTopPromptState {
    this.cancelScheduleTimer();
    this.generation += 1;
    if (state.visible) {
      this.repository.dismiss()
        .then(() => {})
        .catch((_error: Error) => {});
    }
    return {
      visible: false,
      key: state.key,
      topOffsetVp: state.topOffsetVp,
      title: state.title,
      subtitle: state.subtitle
    };
  }

  dispose(): BrowserGestureOnboardingTopPromptState {
    this.cancelScheduleTimer();
    this.generation += 1;
    return HIDDEN_BROWSER_GESTURE_ONBOARDING_TOP_PROMPT_STATE;
  }

  private showIfEligible(
    input: BrowserGestureOnboardingPromptEligibilityInput
  ): BrowserGestureOnboardingTopPromptState {
    if (!this.shouldShow(input)) {
      return HIDDEN_BROWSER_GESTURE_ONBOARDING_TOP_PROMPT_STATE;
    }
    const nextGeneration = this.generation + 1;
    this.generation = nextGeneration;
    const nextState: BrowserGestureOnboardingTopPromptState = {
      visible: true,
      key: `${GESTURE_ONBOARDING_PROMPT_KEY}:${nextGeneration}`,
      topOffsetVp: input.topOffsetVp,
      title: VISIBLE_BROWSER_GESTURE_ONBOARDING_PROMPT_COPY.title,
      subtitle: VISIBLE_BROWSER_GESTURE_ONBOARDING_PROMPT_COPY.subtitle
    };
    this.repository.markShown()
      .then(() => {})
      .catch((_error: Error) => {});
    return nextState;
  }

  private shouldShow(input: BrowserGestureOnboardingPromptEligibilityInput): boolean {
    return input.shellFamily === 'phone' &&
      !this.repository.hasCompleted() &&
      input.appVisible &&
      !input.privateMode &&
      !input.blockingSurfaceVisible;
  }

  private cancelScheduleTimer(): void {
    if (this.scheduleTimer >= 0) {
      clearTimeout(this.scheduleTimer);
      this.scheduleTimer = -1;
    }
  }
}
