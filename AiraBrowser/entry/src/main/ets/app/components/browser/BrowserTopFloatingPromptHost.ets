import {
  BrowserTopFloatingPromptAction,
  BrowserTopFloatingPromptHostState
} from '../../../core/browser/BrowserTopFloatingPromptCoordinator';
import { BrowserGestureOnboardingTopPromptState } from '../../../core/browser/BrowserGestureOnboardingPromptCoordinator';
import { BrowserExternalNavigationPromptCard } from './BrowserExternalNavigationPromptCard';
import { BrowserTopActionPromptCard } from './BrowserTopActionPromptCard';
import { WebpageTranslationPanel } from '../translation/WebpageTranslationPanel';
import {
  TopFloatingOverlayHost,
  TopFloatingSwipeDismissContainer
} from '../common/TopFloatingSurface';
import {
  FLOATING_PROMPT_CARD_ANIMATION_MS,
  FLOATING_PROMPT_CARD_HEIGHT,
  FLOATING_PROMPT_CARD_HIDDEN_OFFSET_Y,
  FLOATING_PROMPT_CARD_HORIZONTAL_MARGIN,
  FLOATING_PROMPT_CARD_ICON_SIZE,
  FLOATING_PROMPT_CARD_TOP_GAP,
  FloatingPromptCard,
  FloatingPromptCloseButton
} from '../common/FloatingPromptCard';
import {
  DEFAULT_WEBPAGE_TRANSLATION_PANEL_STATE
} from '../../../core/translation/WebpageTranslationCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BrowserTopFloatingPromptLayoutState,
  BrowserTopFloatingPromptLayoutViewModel
} from '../../../core/browser/BrowserTopFloatingPromptLayoutViewModel';

const HIDDEN_TOP_FLOATING_PROMPT_STATE: BrowserTopFloatingPromptHostState = {
  mounted: false,
  activeKind: 'background_open',
  urlThreat: {
    visible: false,
    key: '',
    topOffsetVp: 0,
    title: '',
    subtitle: '',
    fallbackLabel: '',
    iconUri: '',
    actionText: ''
  },
  backgroundOpen: {
    visible: false,
    key: '',
    topOffsetVp: 0,
    title: '',
    subtitle: '',
    fallbackLabel: '',
    iconUri: '',
    actionText: '',
    tabId: '',
    progress: 0,
    isLoading: false
  },
  novelPrompt: {
    visible: false,
    key: '',
    kind: '',
    topOffsetVp: 0,
    title: '',
    subtitle: '',
    fallbackLabel: '',
    iconUri: '',
    actionText: ''
  },
  userScriptInstall: {
    visible: false,
    key: '',
    topOffsetVp: 0,
    title: '',
    subtitle: '',
    fallbackLabel: '',
    iconUri: '',
    actionText: ''
  },
  offlineSave: {
    visible: false,
    key: '',
    topOffsetVp: 0,
    title: '',
    subtitle: '',
    fallbackLabel: '',
    iconUri: '',
    actionText: ''
  },
  externalNavigation: {
    state: {
      visible: false,
      tabId: '',
      url: '',
      sourcePageUrl: '',
      title: '',
      subtitle: '',
      appName: '',
      originLabel: '',
      iconUri: '',
      trigger: 'automatic',
      createdAt: 0
    },
    topOffsetVp: 0
  },
  webpageTranslation: {
    visible: false,
    state: DEFAULT_WEBPAGE_TRANSLATION_PANEL_STATE,
    topOffsetVp: 0
  },
  gestureOnboarding: {
    visible: false,
    key: '',
    topOffsetVp: 0,
    title: '',
    subtitle: ''
  }
};

export const BROWSER_TOP_FLOATING_PROMPT_HOST_Z_INDEX: number = 220;
const BROWSER_TOP_FLOATING_PROMPT_HOST_EXTRA_HEIGHT: number = 28;
const BROWSER_TOP_FLOATING_PROMPT_SWIPE_FLYOUT_OFFSET_Y: number =
  -(FLOATING_PROMPT_CARD_HEIGHT + FLOATING_PROMPT_CARD_TOP_GAP + 24);

@Component
export struct BrowserTopFloatingPromptHost {
  @Prop @Watch('reconcileMountedState') state: BrowserTopFloatingPromptHostState =
    HIDDEN_TOP_FLOATING_PROMPT_STATE;
  @State private promptEntered: boolean = false;
  @State private containerWidthVp: number = 0;
  private promptEnterTimer: number = 0;
  private mountedObserved: boolean = false;
  private layoutViewModel: BrowserTopFloatingPromptLayoutViewModel =
    new BrowserTopFloatingPromptLayoutViewModel();
  onAction: (action: BrowserTopFloatingPromptAction) => void =
    (_action: BrowserTopFloatingPromptAction): void => {};

  aboutToAppear(): void {
    this.reconcileMountedState();
  }

  aboutToDisappear(): void {
    this.clearPromptEnterTimer();
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.state.mounted) {
        TopFloatingOverlayHost({
          visible: this.isPromptPresentationReady(),
          topOffsetVp: this.resolveTopOffsetVp(),
          horizontalMarginVp: FLOATING_PROMPT_CARD_HORIZONTAL_MARGIN,
          explicitWidthVp: this.resolvePromptLayout().surfaceWidthVp,
          explicitLeftVp: this.resolvePromptLayout().surfaceLeftVp,
          topGapVp: FLOATING_PROMPT_CARD_TOP_GAP,
          hiddenOffsetYVp: FLOATING_PROMPT_CARD_HIDDEN_OFFSET_Y,
          zIndexValue: 96,
          animationDurationMs: FLOATING_PROMPT_CARD_ANIMATION_MS,
          visibleHitTestMode: HitTestMode.Default
        }) {
          TopFloatingSwipeDismissContainer({
            active: this.isPromptPresentationReady(),
            resetKey: this.resolveSwipeResetKey(),
            flyoutOffsetYVp: BROWSER_TOP_FLOATING_PROMPT_SWIPE_FLYOUT_OFFSET_Y,
            onDismissed: () => {
              this.dismissActivePrompt();
            }
          }) {
            this.buildActivePromptCard()
          }
        }
      }
    }
    .width('100%')
    .height(this.resolveHostHeightVp())
    .hitTestBehavior(this.state.mounted ? HitTestMode.Default : HitTestMode.None)
    .zIndex(BROWSER_TOP_FLOATING_PROMPT_HOST_Z_INDEX)
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const nextWidthVp = this.parseAreaDimension(newArea.width);
      if (nextWidthVp > 0 && nextWidthVp !== this.containerWidthVp) {
        this.containerWidthVp = nextWidthVp;
      }
    })
  }

  private reconcileMountedState(): void {
    if (this.mountedObserved === this.state.mounted) {
      return;
    }
    this.mountedObserved = this.state.mounted;
    this.clearPromptEnterTimer();
    this.promptEntered = false;
    this.containerWidthVp = 0;
    if (!this.state.mounted) {
      return;
    }
    this.promptEnterTimer = setTimeout(() => {
      this.promptEnterTimer = 0;
      this.promptEntered = true;
    }, 30);
  }

  private clearPromptEnterTimer(): void {
    if (this.promptEnterTimer !== 0) {
      clearTimeout(this.promptEnterTimer);
      this.promptEnterTimer = 0;
    }
  }

  private resolvePromptLayout(): BrowserTopFloatingPromptLayoutState {
    return this.layoutViewModel.resolve({
      containerWidthVp: this.containerWidthVp,
      horizontalMarginVp: FLOATING_PROMPT_CARD_HORIZONTAL_MARGIN
    });
  }

  private isPromptPresentationReady(): boolean {
    return this.containerWidthVp > 0 && this.resolveActivePromptVisible();
  }

  private parseAreaDimension(value: Length): number {
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  @Builder
  private buildActivePromptCard() {
    if (this.state.activeKind === 'url_threat') {
      BrowserTopActionPromptCard({
        visible: this.promptEntered && this.state.urlThreat.visible,
        state: this.state.urlThreat,
        subtitleMaxLines: 2,
        showAction: false,
        onDismiss: () => {
          this.onAction({ type: 'dismiss_url_threat' });
        }
      })
    } else if (this.state.activeKind === 'external_navigation') {
      BrowserExternalNavigationPromptCard({
        state: this.state.externalNavigation.state,
        onOpen: () => {
          this.onAction({ type: 'external_navigation', externalNavigationAction: 'open' });
        }
      })
    } else if (this.state.activeKind === 'background_open') {
      BrowserTopActionPromptCard({
        visible: this.promptEntered && this.state.backgroundOpen.visible,
        state: this.state.backgroundOpen,
        onOpen: () => {
          this.onAction({ type: 'open_background_tab', tabId: this.state.backgroundOpen.tabId });
        },
        onDismiss: () => {
          this.onAction({ type: 'dismiss_background_tab', tabId: this.state.backgroundOpen.tabId });
        }
      })
    } else if (this.state.activeKind === 'novel') {
      BrowserTopActionPromptCard({
        visible: this.promptEntered && this.state.novelPrompt.visible,
        state: this.state.novelPrompt,
        onOpen: () => {
          this.onAction({
            type: 'activate_novel_prompt',
            novelPromptKind: this.state.novelPrompt.kind
          });
        },
        onDismiss: () => {
          this.onAction({ type: 'dismiss_novel_prompt' });
        }
      })
    } else if (this.state.activeKind === 'user_script_install') {
      BrowserTopActionPromptCard({
        visible: this.promptEntered && this.state.userScriptInstall.visible,
        state: this.state.userScriptInstall,
        onOpen: () => {
          this.onAction({ type: 'open_user_script_manager' });
        },
        onDismiss: () => {
          this.onAction({ type: 'dismiss_user_script_install' });
        }
      })
    } else if (this.state.activeKind === 'offline_save') {
      BrowserTopActionPromptCard({
        visible: this.promptEntered && this.state.offlineSave.visible,
        state: this.state.offlineSave,
        onOpen: () => {
          this.onAction({ type: 'open_offline_save' });
        },
        onDismiss: () => {
          this.onAction({ type: 'dismiss_offline_save' });
        }
      })
    } else if (this.state.activeKind === 'webpage_translation') {
      WebpageTranslationPanel({
        state: this.state.webpageTranslation.state,
        onClose: () => {
          this.onAction({ type: 'webpage_translation', webpageTranslationAction: 'close_panel' });
        },
        onTranslate: () => {
          this.onAction({ type: 'webpage_translation', webpageTranslationAction: 'translate' });
        },
        onRestoreOriginal: () => {
          this.onAction({ type: 'webpage_translation', webpageTranslationAction: 'restore_original' });
        },
        onShowBilingualTranslation: () => {
          this.onAction({ type: 'webpage_translation', webpageTranslationAction: 'show_bilingual' });
        },
        onShowTranslationOnly: () => {
          this.onAction({ type: 'webpage_translation', webpageTranslationAction: 'show_translation_only' });
        },
        onCancel: () => {
          this.onAction({ type: 'webpage_translation', webpageTranslationAction: 'cancel' });
        },
        onOpenTargetLanguage: () => {
          this.onAction({ type: 'webpage_translation', webpageTranslationAction: 'open_target_language' });
        }
      })
    } else if (this.state.activeKind === 'gesture_onboarding') {
      BrowserGestureOnboardingPromptCard({
        visible: this.promptEntered && this.state.gestureOnboarding.visible,
        state: this.state.gestureOnboarding,
        onDismiss: () => {
          this.onAction({ type: 'dismiss_gesture_onboarding' });
        }
      })
    }
  }

  private resolveHostHeightVp(): number {
    return this.state.mounted
      ? this.resolveTopOffsetVp() + FLOATING_PROMPT_CARD_TOP_GAP + FLOATING_PROMPT_CARD_HEIGHT +
        BROWSER_TOP_FLOATING_PROMPT_HOST_EXTRA_HEIGHT
      : 0;
  }

  private resolveTopOffsetVp(): number {
    if (this.state.activeKind === 'url_threat') {
      return this.state.urlThreat.topOffsetVp;
    }
    if (this.state.activeKind === 'external_navigation') {
      return this.state.externalNavigation.topOffsetVp;
    }
    if (this.state.activeKind === 'offline_save') {
      return this.state.offlineSave.topOffsetVp;
    }
    if (this.state.activeKind === 'novel') {
      return this.state.novelPrompt.topOffsetVp;
    }
    if (this.state.activeKind === 'user_script_install') {
      return this.state.userScriptInstall.topOffsetVp;
    }
    if (this.state.activeKind === 'webpage_translation') {
      return this.state.webpageTranslation.topOffsetVp;
    }
    if (this.state.activeKind === 'gesture_onboarding') {
      return this.state.gestureOnboarding.topOffsetVp;
    }
    return this.state.backgroundOpen.topOffsetVp;
  }

  private resolveActivePromptVisible(): boolean {
    if (!this.promptEntered || this.containerWidthVp <= 0) {
      return false;
    }
    if (this.state.activeKind === 'url_threat') {
      return this.state.urlThreat.visible;
    }
    if (this.state.activeKind === 'external_navigation') {
      return this.state.externalNavigation.state.visible;
    }
    if (this.state.activeKind === 'background_open') {
      return this.state.backgroundOpen.visible;
    }
    if (this.state.activeKind === 'novel') {
      return this.state.novelPrompt.visible;
    }
    if (this.state.activeKind === 'user_script_install') {
      return this.state.userScriptInstall.visible;
    }
    if (this.state.activeKind === 'offline_save') {
      return this.state.offlineSave.visible;
    }
    if (this.state.activeKind === 'webpage_translation') {
      return this.state.webpageTranslation.visible;
    }
    if (this.state.activeKind === 'gesture_onboarding') {
      return this.state.gestureOnboarding.visible;
    }
    return false;
  }

  private resolveSwipeResetKey(): string {
    if (this.state.activeKind === 'url_threat') {
      return this.state.urlThreat.key;
    }
    if (this.state.activeKind === 'external_navigation') {
      const promptState = this.state.externalNavigation.state;
      return `${promptState.tabId}:${promptState.url}:${promptState.appName}:${promptState.createdAt}`;
    }
    if (this.state.activeKind === 'offline_save') {
      return this.state.offlineSave.key;
    }
    if (this.state.activeKind === 'novel') {
      return this.state.novelPrompt.key;
    }
    if (this.state.activeKind === 'user_script_install') {
      return this.state.userScriptInstall.key;
    }
    if (this.state.activeKind === 'webpage_translation') {
      const translationState = this.state.webpageTranslation.state;
      return `${translationState.status}:${translationState.providerTemplateId}:${translationState.targetLanguage}:${translationState.title}`;
    }
    if (this.state.activeKind === 'gesture_onboarding') {
      return this.state.gestureOnboarding.key;
    }
    return this.state.backgroundOpen.key;
  }

  private dismissActivePrompt(): void {
    if (this.state.activeKind === 'url_threat') {
      this.onAction({ type: 'dismiss_url_threat' });
      return;
    }
    if (this.state.activeKind === 'external_navigation') {
      this.onAction({ type: 'external_navigation', externalNavigationAction: 'dismiss' });
      return;
    }
    if (this.state.activeKind === 'offline_save') {
      this.onAction({ type: 'dismiss_offline_save' });
      return;
    }
    if (this.state.activeKind === 'novel') {
      this.onAction({ type: 'dismiss_novel_prompt' });
      return;
    }
    if (this.state.activeKind === 'user_script_install') {
      this.onAction({ type: 'dismiss_user_script_install' });
      return;
    }
    if (this.state.activeKind === 'webpage_translation') {
      this.onAction({ type: 'webpage_translation', webpageTranslationAction: 'close_panel' });
      return;
    }
    if (this.state.activeKind === 'gesture_onboarding') {
      this.onAction({ type: 'dismiss_gesture_onboarding' });
      return;
    }
    this.onAction({ type: 'dismiss_background_tab', tabId: this.state.backgroundOpen.tabId });
  }
}

const HIDDEN_GESTURE_ONBOARDING_PROMPT_STATE: BrowserGestureOnboardingTopPromptState = {
  visible: false,
  key: '',
  topOffsetVp: 0,
  title: '',
  subtitle: ''
};

@Component
struct BrowserGestureOnboardingPromptCard {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @Prop visible: boolean = false;
  @Prop state: BrowserGestureOnboardingTopPromptState = HIDDEN_GESTURE_ONBOARDING_PROMPT_STATE;
  onDismiss: () => void = () => {};

  build() {
    FloatingPromptCard({
      title: this.state.title,
      subtitle: this.state.subtitle,
      subtitleMaxLines: 1,
      loading: false,
      progress: 100,
      leading: () => {
        this.buildLeadingIcon()
      },
      trailing: () => {
        this.buildTrailingActions()
      }
    })
  }

  @Builder
  private buildLeadingIcon() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r('sys.symbol.house_fill'))
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor([this.storedAccentColor])
    }
    .width(FLOATING_PROMPT_CARD_ICON_SIZE)
    .height(FLOATING_PROMPT_CARD_ICON_SIZE)
    .borderRadius(12)
    .backgroundColor(this.storedPressedBackgroundColor)
  }

  @Builder
  private buildTrailingActions() {
    FloatingPromptCloseButton({
      onAction: () => {
        if (this.visible && this.state.visible) {
          this.onDismiss();
        }
      }
    })
  }
}
