import urlUtils from '@ohos.url';
import { looksLikeUrl, normalizeUrl } from '../../common/utils/UrlUtils';

export interface BookmarkAddDraft {
  title: string;
  url: string;
  folderId: string;
  titleError: ResourceStr;
  urlError: ResourceStr;
  saveError: ResourceStr;
  saving: boolean;
  choosingFolder: boolean;
}

export function createBookmarkAddDraft(title: string = '', url: string = '', folderId: string = ''): BookmarkAddDraft {
  return {
    title: title.trim().length > 0 ? title : url,
    url: url,
    folderId: folderId,
    titleError: '',
    urlError: '',
    saveError: '',
    saving: false,
    choosingFolder: false
  };
}

export function validateBookmarkAddDraft(draft: BookmarkAddDraft): BookmarkAddDraft {
  const title = draft.title.trim();
  const rawUrl = draft.url.trim();
  let normalizedUrl = rawUrl;
  let urlError: ResourceStr = '';
  if (rawUrl.length <= 0) {
    urlError = $r('app.string.bookmark_url_required');
  } else {
    try {
      if (!looksLikeUrl(rawUrl) || /\s/.test(rawUrl)) {
        throw new Error('Invalid bookmark URL');
      }
      normalizedUrl = normalizeUrl(rawUrl);
      const parsed = urlUtils.URL.parseURL(normalizedUrl);
      if ((parsed.protocol === 'http:' || parsed.protocol === 'https:') && parsed.hostname.length <= 0) {
        throw new Error('Missing bookmark host');
      }
    } catch (_error) {
      urlError = $r('app.string.bookmark_add_url_invalid');
    }
  }
  return {
    title: title,
    url: normalizedUrl,
    folderId: draft.folderId,
    titleError: title.length > 0 ? '' : $r('app.string.bookmark_name_required'),
    urlError: urlError,
    saveError: '',
    saving: false,
    choosingFolder: false
  };
}

export function isBookmarkAddDraftValid(draft: BookmarkAddDraft): boolean {
  return draft.titleError === '' && draft.urlError === '';
}

export function cloneBookmarkAddDraft(draft: BookmarkAddDraft): BookmarkAddDraft {
  return {
    title: draft.title,
    url: draft.url,
    folderId: draft.folderId,
    titleError: draft.titleError,
    urlError: draft.urlError,
    saveError: draft.saveError,
    saving: draft.saving,
    choosingFolder: draft.choosingFolder
  };
}
