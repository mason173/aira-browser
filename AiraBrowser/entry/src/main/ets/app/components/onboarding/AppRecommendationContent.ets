/**
 * The app catalog behind 设置 → 应用推荐.
 *
 * This is the one file that changes when Aira offers a different app: add an entry (or
 * replace the current one) and the settings page's card, and the detail sheet that card
 * opens, follow without any further change.
 *
 * `id` is the identity the page opens a card by. It is stable for as long as the same app
 * is on offer; it is not stored anywhere, because the catalog is opened on demand rather
 * than announced.
 *
 * Order matters: the page lists the catalog in order.
 *
 * Copy and artwork are bundled with the app on purpose. A hosted catalog would need a
 * network read to draw and a hosted endpoint the Community distribution must not call;
 * bundled content keeps the page offline and credential-free.
 */

/** One sample review in the scrolling band. Every field is localized copy, never a brand string. */
export interface AppRecommendationReview {
  key: string;
  author: ResourceStr;
  avatar: Resource;
  title: ResourceStr;
  message: ResourceStr;
}

/** One centred question-and-answer block under the reviews. */
export interface AppRecommendationFaq {
  key: string;
  icon: Resource;
  title: ResourceStr;
  text: ResourceStr;
}

export interface AppRecommendationEntry {
  id: string;
  /** AppGallery package id of the offered app. This is the only store identity Aira keeps. */
  storeId: string;
  icon: ResourceStr;
  name: ResourceStr;
  tagline: ResourceStr;
  /** The two-laurel product phrase; an empty list shows no laurel row. */
  badges: ResourceStr[];
  reviewsTitle: ResourceStr;
  reviews: AppRecommendationReview[];
  faqsTitle: ResourceStr;
  faqs: AppRecommendationFaq[];
}

function shengxiEntry(): AppRecommendationEntry {
  return {
    id: 'shengxi',
    storeId: 'com.noctide.sleep',
    icon: $r('app.media.app_recommendation_shengxi'),
    name: $r('app.string.app_recommendation_app_name'),
    tagline: $r('app.string.app_recommendation_tagline'),
    badges: [
      $r('app.string.app_recommendation_badge_sleep'),
      $r('app.string.app_recommendation_badge_focus')
    ],
    reviewsTitle: $r('app.string.app_recommendation_reviews_title'),
    reviews: [
      {
        key: 'rain',
        author: $r('app.string.app_recommendation_review_author_rain'),
        avatar: $r('app.media.app_recommendation_review_avatar_clear'),
        title: $r('app.string.app_recommendation_review_title_rain'),
        message: $r('app.string.app_recommendation_review_message_rain')
      },
      {
        key: 'nap',
        author: $r('app.string.app_recommendation_review_author_nap'),
        avatar: $r('app.media.app_recommendation_review_avatar_spending'),
        title: $r('app.string.app_recommendation_review_title_nap'),
        message: $r('app.string.app_recommendation_review_message_nap')
      },
      {
        key: 'focus',
        author: $r('app.string.app_recommendation_review_author_focus'),
        avatar: $r('app.media.app_recommendation_review_avatar_simple'),
        title: $r('app.string.app_recommendation_review_title_focus'),
        message: $r('app.string.app_recommendation_review_message_focus')
      },
      {
        key: 'content',
        author: $r('app.string.app_recommendation_review_author_content'),
        avatar: $r('app.media.app_recommendation_review_avatar_cycles'),
        title: $r('app.string.app_recommendation_review_title_content'),
        message: $r('app.string.app_recommendation_review_message_content')
      },
      {
        key: 'quiet',
        author: $r('app.string.app_recommendation_review_author_quiet'),
        avatar: $r('app.media.app_recommendation_review_avatar_tidy'),
        title: $r('app.string.app_recommendation_review_title_quiet'),
        message: $r('app.string.app_recommendation_review_message_quiet')
      }
    ],
    faqsTitle: $r('app.string.app_recommendation_faq_title'),
    faqs: [
      {
        key: 'content',
        icon: $r('sys.symbol.music_note_list'),
        title: $r('app.string.app_recommendation_faq_content_title'),
        text: $r('app.string.app_recommendation_faq_content_text')
      },
      {
        key: 'background',
        icon: $r('sys.symbol.play_fill'),
        title: $r('app.string.app_recommendation_faq_background_title'),
        text: $r('app.string.app_recommendation_faq_background_text')
      },
      {
        key: 'nap',
        icon: $r('sys.symbol.timer'),
        title: $r('app.string.app_recommendation_faq_nap_title'),
        text: $r('app.string.app_recommendation_faq_nap_text')
      }
    ]
  };
}

export function buildEmptyAppRecommendationEntry(): AppRecommendationEntry {
  return {
    id: '',
    storeId: '',
    icon: '',
    name: '',
    tagline: '',
    badges: [],
    reviewsTitle: '',
    reviews: [],
    faqsTitle: '',
    faqs: []
  };
}

/** Every app Aira offers in 设置 → 应用推荐, in the order the page lists them. */
export function appRecommendationCatalog(): AppRecommendationEntry[] {
  return [
    shengxiEntry()
  ];
}

export function appRecommendationEntryFor(id: string): AppRecommendationEntry | undefined {
  const entries = appRecommendationCatalog();
  for (let index = 0; index < entries.length; index++) {
    if (entries[index].id === id) {
      return entries[index];
    }
  }
  return undefined;
}
