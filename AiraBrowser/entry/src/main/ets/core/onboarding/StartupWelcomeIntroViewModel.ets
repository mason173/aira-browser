export interface StartupWelcomeIntroSlideState {
  id: string;
  indexLabel: string;
  title: string;
  subtitle: string;
  illustrationKind: StartupWelcomeIntroIllustrationKind;
}

export type StartupWelcomeIntroIllustrationKind = 'speed' | 'privacy' | 'extensions' | 'sync';

export interface StartupWelcomeIntroViewState {
  slides: StartupWelcomeIntroSlideState[];
  finalActionLabel: string;
  nextActionLabel: string;
}

export class StartupWelcomeIntroViewModel {
  buildState(): StartupWelcomeIntroViewState {
    return {
      slides: [
        {
          id: 'speed',
          indexLabel: '01',
          title: '快到顺手，流畅到忘记等待',
          subtitle: 'Aira 让网页打开更快、滑动更顺，搜索、阅读、切换都轻盈自然。',
          illustrationKind: 'speed'
        },
        {
          id: 'privacy',
          indexLabel: '02',
          title: '少一点打扰，多一点安全感',
          subtitle: '按你导入的规则过滤网页内容与跟踪资源，守护你的浏览隐私。',
          illustrationKind: 'privacy'
        },
        {
          id: 'extensions',
          indexLabel: '03',
          title: '让浏览器按你的方式工作',
          subtitle: '支持用户脚本与插件扩展，从自动化到效率增强，打造专属于你的浏览体验。',
          illustrationKind: 'extensions'
        },
        {
          id: 'sync',
          indexLabel: '04',
          title: '书签随身，设备无界',
          subtitle: '与 Windows、Mac 同步书签，常用网站在每台设备上都触手可及。',
          illustrationKind: 'sync'
        }
      ],
      finalActionLabel: '开始使用',
      nextActionLabel: '下一页'
    };
  }
}
