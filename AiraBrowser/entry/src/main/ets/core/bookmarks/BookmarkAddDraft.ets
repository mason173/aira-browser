import urlUtils from '@ohos.url';
import { normalizeUrl } from '../../common/utils/UrlUtils';

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

export function validateBookmarkAddDraft(draft: BookmarkAddDraft, manualWebAddress: boolean = false): BookmarkAddDraft {
  let title = draft.title.trim();
  const rawUrl = draft.url.trim();
  let normalizedUrl = rawUrl;
  let urlError: ResourceStr = '';
  if (rawUrl.length <= 0) {
    urlError = $r('app.string.bookmark_url_required');
  } else {
    try {
      const candidate = normalizeUrl(rawUrl);
      if (candidate.length === 0 || /\s/.test(rawUrl) ||
        (manualWebAddress && !/^https?:\/\/[^/\\?#]/i.test(candidate))) {
        throw new Error('Invalid bookmark URL');
      }
      normalizedUrl = candidate;
      const parsed = urlUtils.URL.parseURL(normalizedUrl);
      const isWebAddress = parsed.protocol === 'http:' || parsed.protocol === 'https:';
      if (isWebAddress && parsed.hostname.length <= 0) {
        throw new Error('Missing bookmark host');
      }
      if (manualWebAddress && title.length === 0) {
        title = parsed.hostname;
      }
    } catch (_error) {
      urlError = $r('app.string.bookmark_add_url_invalid');
    }
  }
  return {
    title: title,
    url: normalizedUrl,
    folderId: draft.folderId,
    titleError: manualWebAddress || title.length > 0 ? '' : $r('app.string.bookmark_name_required'),
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
