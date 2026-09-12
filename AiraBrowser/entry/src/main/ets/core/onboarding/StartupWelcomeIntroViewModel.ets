export type StartupWelcomeIntroActionId = 'personal_server' | 'webdav';

export interface StartupWelcomeIntroActionState {
  id: StartupWelcomeIntroActionId;
  label: string;
}

export interface StartupWelcomeIntroHeroState {
  title: string;
  subtitle: string;
}

export interface StartupWelcomeIntroFacts {
  /** Huawei account sign-in is an Official-only capability. */
  huaweiAccountAvailable: boolean;
  /** Basic service mode hides account and sync entirely. */
  optionalServiceAvailable: boolean;
}

export interface StartupWelcomeIntroViewState {
  hero: StartupWelcomeIntroHeroState;
  /** The real Huawei ID button is rendered inline, not as a plain action row. */
  showHuaweiLogin: boolean;
  actions: StartupWelcomeIntroActionState[];
  skipActionLabel: string;
}

const STARTUP_WELCOME_INTRO_HERO_SIGN_IN: StartupWelcomeIntroHeroState = {
  title: '开启跨设备同步',
  subtitle: '登录华为账号，或连接你自己的服务器，让书签、历史记录和常用设置在各设备之间保持一致。'
};

const STARTUP_WELCOME_INTRO_HERO_SELF_HOSTED: StartupWelcomeIntroHeroState = {
  title: '开启跨设备同步',
  subtitle: '连接个人服务器或 WebDAV，让书签、历史记录和常用设置在各设备之间保持一致。'
};

const STARTUP_WELCOME_INTRO_HERO_BASIC_MODE: StartupWelcomeIntroHeroState = {
  title: '欢迎使用 Aira',
  subtitle: '当前处于精简模式，账号与同步功能需要切换到全量模式后使用。你可以先直接开始浏览。'
};

const STARTUP_WELCOME_INTRO_SKIP_ACTION_LABEL: string = '暂时跳过';

export class StartupWelcomeIntroViewModel {
  buildState(facts: StartupWelcomeIntroFacts): StartupWelcomeIntroViewState {
    return {
      hero: this.resolveHero(facts),
      showHuaweiLogin: facts.optionalServiceAvailable && facts.huaweiAccountAvailable,
      actions: this.buildActions(facts),
      skipActionLabel: STARTUP_WELCOME_INTRO_SKIP_ACTION_LABEL
    };
  }

  private buildActions(facts: StartupWelcomeIntroFacts): StartupWelcomeIntroActionState[] {
    if (!facts.optionalServiceAvailable) {
      return [];
    }
    return [
      {
        id: 'personal_server',
        label: '使用个人服务器同步'
      },
      {
        id: 'webdav',
        label: 'WebDAV 同步'
      }
    ];
  }

  private resolveHero(facts: StartupWelcomeIntroFacts): StartupWelcomeIntroHeroState {
    if (!facts.optionalServiceAvailable) {
      return STARTUP_WELCOME_INTRO_HERO_BASIC_MODE;
    }
    return facts.huaweiAccountAvailable
      ? STARTUP_WELCOME_INTRO_HERO_SIGN_IN
      : STARTUP_WELCOME_INTRO_HERO_SELF_HOSTED;
  }
}
