import { BrowserTopActionPromptState } from '../../../core/browser/BrowserTopFloatingPromptCoordinator';
import { BrowserTopPromptIcon } from './BrowserTopPromptIcon';
import {
  FloatingPromptActionButton,
  FloatingPromptCard
} from '../common/FloatingPromptCard';

const HIDDEN_TOP_ACTION_PROMPT_STATE: BrowserTopActionPromptState = {
  visible: false,
  key: '',
  topOffsetVp: 0,
  title: '',
  subtitle: '',
  fallbackLabel: '',
  iconUri: '',
  actionText: ''
};

@Component
export struct BrowserTopActionPromptCard {
  @Prop state: BrowserTopActionPromptState = HIDDEN_TOP_ACTION_PROMPT_STATE;
  @Prop visible: boolean = false;
  @Prop subtitleMaxLines: number = 1;
  @Prop showAction: boolean = true;
  onOpen: () => void = () => {};
  onDismiss: () => void = () => {};

  build() {
    FloatingPromptCard({
      title: this.state.title,
      subtitle: this.state.subtitle,
      subtitleMaxLines: this.subtitleMaxLines,
      loading: false,
      progress: 100,
      leading: () => {
        this.buildLeadingIcon()
      },
      trailing: () => {
        if (this.showAction) {
          this.buildTrailingActions()
        }
      }
    })
  }

  @Builder
  private buildLeadingIcon() {
    BrowserTopPromptIcon({
      iconUri: this.state.iconUri,
      iconPixelMap: this.state.iconUri.trim().length > 0 ? undefined : this.state.favicon,
      airaIconId: this.state.airaIconId,
      airaIconColor: this.state.iconColor,
      airaIconBackgroundColor: this.state.iconBackgroundColor,
      fallbackLabel: this.state.fallbackLabel
    })
  }

  @Builder
  private buildTrailingActions() {
    FloatingPromptActionButton({
      text: this.resolveActionText(),
      actionEnabled: this.resolveVisible(),
      onAction: () => {
        if (this.resolveVisible()) {
          this.onOpen();
        }
      }
    })
  }

  private resolveVisible(): boolean {
    return this.visible && this.state.visible && this.state.key.length > 0;
  }

  private resolveActionText(): string {
    const actionText = this.state.actionText.trim();
    return actionText.length > 0 ? actionText : '查看';
  }
}
