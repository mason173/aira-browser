import { common } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import {
  AppRecommendationEntry,
  AppRecommendationFaq,
  AppRecommendationFeature,
  AppRecommendationReview,
  appRecommendationCatalog,
  appRecommendationEntryFor
} from './RecommendationCatalog';
import { openRecommendedApp } from './RecommendationStore';

export const RECOMMENDATIONS_ROUTE: string = 'app-recommendations';
export const RECOMMENDATION_DETAIL_PREFIX: string = 'app-recommendations/';

export function recommendationTitle(context: UIContext, hostId: string, selectedId: string = ''): string {
  const title = appRecommendationEntryFor(selectedId, hostId)?.name ?? $r('app.string.app_recommendation_title');
  return typeof title === 'string' ? title : context.getHostContext()?.resourceManager.getStringSync(title.id) ?? '';
}

@Component
export struct RecommendationContent {
  @Prop hostId: string = '';
  @Prop selectedId: string = '';
  @Prop foreground: ResourceColor = $r('app.color.foreground');
  @Prop secondary: ResourceColor = $r('app.color.muted_foreground');
  @Prop surface: ResourceColor = $r('app.color.card');
  @Prop accent: ResourceColor = $r('app.color.primary');
  onSelect: (id: string) => void = (_id: string): void => {};
  @State private openingStore: boolean = false;

  build() {
    Column() {
      if (this.selectedId.length === 0) {
        Column() {
          ForEach(appRecommendationCatalog(this.hostId), (entry: AppRecommendationEntry, index: number) => {
            if (index > 0) {
              Divider().color($r('app.color.divider'))
            }
            this.AppRow(entry)
          }, (entry: AppRecommendationEntry): string => entry.id)
        }
        .width('100%')
        .backgroundColor(this.surface)
        .borderRadius($r('app.float.list_detail_card_radius'))
        .clip(true)
      } else {
        ForEach(appRecommendationCatalog(this.hostId), (entry: AppRecommendationEntry) => {
          if (entry.id === this.selectedId) {
            this.AppDetails(entry)
          }
        }, (entry: AppRecommendationEntry): string => entry.id)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private AppRow(entry: AppRecommendationEntry) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: $r('app.float.gap_list') }) {
        Image(entry.icon)
          .width($r('app.float.icon_button_size'))
          .height($r('app.float.icon_button_size'))
          .borderRadius($r('app.float.avatar_sm_radius'))
          .draggable(false)
        Column() {
          Text(entry.name)
            .fontSize($r('app.float.font_size_body'))
            .fontWeight($r('app.integer.font_weight_medium'))
            .fontColor(this.foreground)
          Text(entry.tagline)
            .fontSize($r('app.float.font_size_caption'))
            .lineHeight($r('app.float.line_height_caption'))
            .fontColor(this.secondary)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize($r('app.float.icon_size_secondary'))
          .fontColor([this.secondary])
      }
      .width('100%')
      .padding($r('app.float.padding_list'))
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
    .onClick(() => this.onSelect(entry.id))
  }

  @Builder
  private AppDetails(entry: AppRecommendationEntry) {
    Column({ space: $r('app.float.gap_section') }) {
      Column({ space: $r('app.float.gap_intro_row') }) {
        Image(entry.icon)
          .width($r('app.float.avatar_size'))
          .height($r('app.float.avatar_size'))
          .borderRadius($r('app.float.avatar_sm_radius'))
          .draggable(false)
        Text(entry.name)
          .fontSize($r('app.float.font_size_display'))
          .fontWeight($r('app.integer.font_weight_semibold'))
          .fontColor(this.foreground)
        Text(entry.tagline)
          .fontSize($r('app.float.font_size_body'))
          .lineHeight($r('app.float.line_height_body'))
          .fontColor(this.secondary)
          .textAlign(TextAlign.Center)
        if (entry.badges.length > 0) {
          Row({ space: $r('app.float.gap_list') }) {
            ForEach(entry.badges, (badge: ResourceStr) => {
              Text(badge)
                .fontSize($r('app.float.font_size_caption'))
                .fontColor(this.accent)
            })
          }
        }
        Button($r('app.string.app_recommendation_open_market'))
          .width('100%')
          .height($r('app.float.button_height'))
          .fontSize($r('app.float.font_size_button'))
          .fontColor($r('app.color.primary_foreground'))
          .backgroundColor(this.accent)
          .enabled(!this.openingStore)
          .onClick((): void => { void this.openMarket(entry.storeId); })
      }
      .width('100%')

      if (entry.features.length > 0) {
        Column({ space: $r('app.float.gap_row') }) {
          this.SectionTitle(entry.featuresTitle)
          Column() {
            ForEach(entry.features, (feature: AppRecommendationFeature, index: number) => {
              if (index > 0) {
                Divider().color($r('app.color.divider'))
              }
              Row({ space: $r('app.float.gap_list') }) {
                Image(feature.icon)
                  .width($r('app.float.icon_size'))
                  .height($r('app.float.icon_size'))
                  .fillColor(feature.plate)
                  .draggable(false)
                Text(feature.title)
                  .fontSize($r('app.float.font_size_body'))
                  .lineHeight($r('app.float.line_height_body'))
                  .fontColor(this.foreground)
              }
              .width('100%')
              .padding($r('app.float.padding_list'))
            }, (feature: AppRecommendationFeature): string => feature.key)
          }
          .width('100%')
          .backgroundColor(this.surface)
          .borderRadius($r('app.float.list_detail_card_radius'))
          .clip(true)
        }
        .width('100%')
      }

      if (entry.reviews.length > 0) {
        Column({ space: $r('app.float.gap_row') }) {
          this.SectionTitle($r('app.string.app_recommendation_fictional_reviews_title'))
          Scroll() {
            Row({ space: $r('app.float.gap_row') }) {
              ForEach(entry.reviews, (review: AppRecommendationReview) => {
                this.ReviewCard(review)
              }, (review: AppRecommendationReview): string => review.key)
            }
            .alignItems(VerticalAlign.Top)
          }
          .width('100%')
          .scrollable(ScrollDirection.Horizontal)
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Off)
        }
        .width('100%')
      }

      if (entry.faqs.length > 0) {
        Column({ space: $r('app.float.gap_list') }) {
          this.SectionTitle(entry.faqsTitle)
          ForEach(entry.faqs, (faq: AppRecommendationFaq) => {
            Column({ space: $r('app.float.gap_intro_row') }) {
              Text(faq.title)
                .fontSize($r('app.float.font_size_body'))
                .fontWeight($r('app.integer.font_weight_medium'))
                .fontColor(this.foreground)
              Text(faq.text)
                .fontSize($r('app.float.font_size_caption'))
                .lineHeight($r('app.float.line_height_caption'))
                .fontColor(this.secondary)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding($r('app.float.padding_list'))
            .backgroundColor(this.surface)
            .borderRadius($r('app.float.list_detail_card_radius'))
          }, (faq: AppRecommendationFaq): string => faq.key)
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SectionTitle(title: ResourceStr) {
    Text(title)
      .width('100%')
      .fontSize($r('app.float.font_size_subtitle'))
      .fontWeight($r('app.integer.font_weight_semibold'))
      .fontColor(this.foreground)
  }

  @Builder
  private ReviewCard(review: AppRecommendationReview) {
    Column({ space: $r('app.float.gap_intro_row') }) {
      Row({ space: $r('app.float.gap_icon') }) {
        Image(review.avatar)
          .width($r('app.float.icon_size_secondary'))
          .height($r('app.float.icon_size_secondary'))
          .borderRadius($r('app.float.avatar_sm_radius'))
          .draggable(false)
        Text(review.author)
          .fontSize($r('app.float.font_size_micro'))
          .fontColor(this.secondary)
      }
      Text(review.title)
        .fontSize($r('app.float.font_size_body'))
        .fontWeight($r('app.integer.font_weight_semibold'))
        .fontColor(this.foreground)
      Text(review.message)
        .fontSize($r('app.float.font_size_caption'))
        .lineHeight($r('app.float.line_height_caption'))
        .fontColor(this.secondary)
    }
    .width($r('app.float.app_recommendation_review_card_width'))
    .alignItems(HorizontalAlign.Start)
    .padding($r('app.float.padding_list'))
    .backgroundColor(this.surface)
    .borderRadius($r('app.float.list_detail_card_radius'))
  }

  private async openMarket(storeId: string): Promise<void> {
    const ui = this.getUIContext();
    const context = ui.getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined || this.openingStore) {
      return;
    }
    this.openingStore = true;
    const opened = await openRecommendedApp(context, storeId);
    this.openingStore = false;
    if (!opened) {
      ui.getPromptAction().showToast({ message: $r('app.string.app_recommendation_market_error') });
    }
  }
}
