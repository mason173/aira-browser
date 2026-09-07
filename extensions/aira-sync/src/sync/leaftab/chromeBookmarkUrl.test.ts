import { describe, expect, test } from 'vitest';
import {
  canonicalizeSnapshotBookmarkUrls,
  normalizeChromeBookmarkUrl,
} from './chromeBookmarkUrl';

describe('normalizeChromeBookmarkUrl', () => {
  test('encodes raw spaces that Chrome bookmarks reject as Invalid URL', () => {
    expect(normalizeChromeBookmarkUrl('https://example.com/foo bar')).toBe('https://example.com/foo%20bar');
  });

  test('keeps javascript bookmarklets so desktop and cloud stay aligned', () => {
    expect(normalizeChromeBookmarkUrl('javascript:alert(1)')).toBe('javascript:alert(1)');
  });

  test('restores bookmarklets that were saved with an https://javascript prefix', () => {
    expect(normalizeChromeBookmarkUrl(
      'https://javascript:var%20a=prompt(PLAYER._DownloadMonitor.context.dataset.title)',
    )).toBe('javascript:var a=prompt(PLAYER._DownloadMonitor.context.dataset.title)');
  });

  test('trims empty urls to an empty string', () => {
    expect(normalizeChromeBookmarkUrl('   ')).toBe('');
  });
});

describe('canonicalizeSnapshotBookmarkUrls', () => {
  test('rewrites only shared bookmark item urls that Chrome would reject', () => {
    const snapshot = {
      bookmarkItems: {
        spaced: { id: 'spaced', url: 'https://example.com/foo bar' },
        bookmarklet: { id: 'bookmarklet', url: 'javascript:alert(1)' },
      },
    };

    expect(canonicalizeSnapshotBookmarkUrls(snapshot)).toEqual({
      bookmarkItems: {
        spaced: { id: 'spaced', url: 'https://example.com/foo%20bar' },
        bookmarklet: { id: 'bookmarklet', url: 'javascript:alert(1)' },
      },
    });
  });
});
