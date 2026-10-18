/**
 * The recommendation catalog. This is the one file that changes when Aira
 * recommends a different app: add an entry (or replace the current one) and the
 * card, the once-per-recommendation memory, and the homepage trigger follow
 * without any further change.
 *
 * `id` is the campaign identity, not the app identity, and it is the only key the
 * device-local memory stores. Keep it stable for as long as the same telling
 * should stay spent. Recommending the same app again is a new push and takes a
 * new id (for example `shengxi_2027`), because a user who closed the previous
 * card has not agreed to be told about the app forever — but has also not agreed
 * to be told the same thing twice.
 *
 * Order matters: the coordinator offers the first entry this device has not spent
 * and offers at most one per homepage arrival, so appending an entry queues it
 * behind the current one and replacing it promotes it immediately.
 *
 * Copy and artwork are bundled with the app on purpose. A hosted campaign would
 * need a network read to draw, a hosted endpoint the Community distribution must
 * not call, and a server-side record of whether the user has been told; bundled
 * content plus a device-local memory keeps the card offline and credential-free.
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
  /** AppGallery package id of the recommended app. This is the only store identity Aira keeps. */
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

/** Every recommendation Aira can offer, in the order the coordinator should offer them. */
export function appRecommendationCatalog(): AppRecommendationEntry[] {
  return [
    shengxiEntry()
  ];
}

/** The campaign ids in catalog order, which is all the once-per-recommendation owner needs. */
export function appRecommendationIds(): string[] {
  const ids: string[] = [];
  const entries = appRecommendationCatalog();
  for (let index = 0; index < entries.length; index++) {
    ids.push(entries[index].id);
  }
  return ids;
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
