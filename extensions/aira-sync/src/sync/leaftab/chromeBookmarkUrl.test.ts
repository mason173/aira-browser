import { describe, expect, test } from 'vitest';
import {
  canonicalizeSnapshotBookmarkUrls,
  normalizeChromeBookmarkUrl,
} from './chromeBookmarkUrl';

describe('normalizeChromeBookmarkUrl', () => {
  test('encodes raw spaces that Chrome bookmarks reject as Invalid URL', () => {
    expect(normalizeChromeBookmarkUrl('https://example.com/foo bar')).toBe('https://example.com/foo%20bar');
  });

  test.each([
    ['https://例子.测试', 'https://xn--fsqu00a.xn--0zwm56d/'],
    ['https://bücher.example', 'https://xn--bcher-kva.example/'],
    ['https://EXAMPLE.COM:443', 'https://example.com/'],
    ['http://EXAMPLE.COM:80', 'http://example.com/'],
    ['ftp://EXAMPLE.COM:21', 'ftp://example.com/'],
    ['https://example.com:8443', 'https://example.com:8443/'],
    ['https://example.com/a/../b', 'https://example.com/b'],
    [
      'https://example.com/中文?q=你好#片段',
      'https://example.com/%E4%B8%AD%E6%96%87?q=%E4%BD%A0%E5%A5%BD#%E7%89%87%E6%AE%B5',
    ],
  ])('matches browser serialization for %s', (input, expected) => {
    expect(normalizeChromeBookmarkUrl(input)).toBe(expected);
    expect(normalizeChromeBookmarkUrl(expected)).toBe(expected);
  });

  test.each([
    'https://example.com/path',
    'https://example.com/path/',
    'https://example.com/a%2Fb?q=first+second&next=%2F#section',
    'https://example.com/Path?q=1&q=2',
    'https://example.com/path?q=2&q=1',
    'mailto:user@example.com',
    'file:///C:/Docs/example.html',
    'data:text/plain,hello%20world',
    'chrome://bookmarks/',
  ])('preserves significant URL components and non-web schemes: %s', (url) => {
    expect(normalizeChromeBookmarkUrl(url)).toBe(url);
  });

  test('retains the existing whitespace fallback for malformed URLs', () => {
    expect(normalizeChromeBookmarkUrl('https://exa mple.com/foo bar'))
      .toBe('https://exa%20mple.com/foo%20bar');
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
  test('canonicalizes shared URLs without mutating metadata or App-private bookmarks', () => {
    const snapshot = {
      bookmarkItems: {
        international: { id: 'international', url: 'https://例子.测试', revision: 7, title: 'Example' },
        unchanged: { id: 'unchanged', url: 'https://example.com/path' },
      },
      appPrivateBookmarks: { bookmarkItems: { private: { url: 'https://例子.测试' } } },
    };
    const result = canonicalizeSnapshotBookmarkUrls(snapshot);

    expect(result.bookmarkItems.international).toEqual({
      ...snapshot.bookmarkItems.international,
      url: 'https://xn--fsqu00a.xn--0zwm56d/',
    });
    expect(snapshot.bookmarkItems.international.url).toBe('https://例子.测试');
    expect(result.bookmarkItems.unchanged).toBe(snapshot.bookmarkItems.unchanged);
    expect(result.appPrivateBookmarks).toBe(snapshot.appPrivateBookmarks);
    expect(canonicalizeSnapshotBookmarkUrls(result)).toBe(result);
  });

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
