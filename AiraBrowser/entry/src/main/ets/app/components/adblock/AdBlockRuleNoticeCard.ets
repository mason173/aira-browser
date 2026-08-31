import { SettingsNoticeCard } from '../settings/SettingsNoticeCard';

@Component
export struct AdBlockRuleNoticeCard {
  @Prop desktopPresentation: boolean = false;
  onClosed: () => void = () => {};

  build() {
    SettingsNoticeCard({
      title: '规则不是越多越好',
      message: '第三方规则仅在你确认后联网下载，自定义规则由你自行导入和管理。规则过多可能拖慢网页或误拦内容，请遵守网站条款与法律法规。',
      desktopPresentation: this.desktopPresentation,
      onClosed: () => {
        this.onClosed();
      }
    })
  }
}
