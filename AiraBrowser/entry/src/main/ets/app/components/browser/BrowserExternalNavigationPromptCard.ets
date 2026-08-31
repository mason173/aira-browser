import { ExternalNavigationPromptState } from '../../../core/browser/ExternalNavigationPromptViewModel';
import { BrowserTopPromptIcon } from './BrowserTopPromptIcon';
import {
  FloatingPromptActionButton,
  FloatingPromptCard
} from '../common/FloatingPromptCard';

const HIDDEN_EXTERNAL_NAVIGATION_PROMPT_STATE: ExternalNavigationPromptState = {
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
};

@Component
export struct BrowserExternalNavigationPromptCard {
  @Prop state: ExternalNavigationPromptState = HIDDEN_EXTERNAL_NAVIGATION_PROMPT_STATE;
  onOpen: () => void = (): void => {};

  build() {
    FloatingPromptCard({
      title: this.resolveTitle(),
      subtitle: this.resolveSubtitle(),
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
    BrowserTopPromptIcon({
      iconUri: this.resolveIconUri(),
      iconPixelMap: this.resolvePromptState().favicon,
      fallbackLabel: this.resolveFallbackLabel()
    })
  }

  @Builder
  private buildTrailingActions() {
    FloatingPromptActionButton({
      text: '打开',
      actionEnabled: this.resolveVisible(),
      onAction: () => {
        if (this.resolveVisible()) {
          this.onOpen();
        }
      }
    })
  }

  private resolvePromptState(): ExternalNavigationPromptState {
    return this.state === undefined ? HIDDEN_EXTERNAL_NAVIGATION_PROMPT_STATE : this.state;
  }

  private resolveVisible(): boolean {
    return this.resolvePromptState().visible;
  }

  private resolveTitle(): string {
    return this.resolvePromptState().title;
  }

  private resolveSubtitle(): string {
    return this.resolvePromptState().subtitle;
  }

  private resolveIconUri(): string {
    return this.resolvePromptState().iconUri;
  }

  private resolveFallbackLabel(): string {
    const promptState = this.resolvePromptState();
    return promptState.originLabel.length > 0 ? promptState.originLabel : promptState.appName;
  }
}
