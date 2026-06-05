import { describe, expect, it } from 'vitest';
import { resolveSearchBarTheme } from '@/components/search/searchBarTheme';

describe('resolveSearchBarTheme', () => {
  it('keeps light app theme on dark foreground tokens even when white search is requested', () => {
    expect(resolveSearchBarTheme({
      resolvedTheme: 'light',
      forceWhiteTheme: true,
    }).foregroundTone).toBe('dark');
  });

  it('uses light foreground tokens for explicit dark app theme', () => {
    expect(resolveSearchBarTheme({
      resolvedTheme: 'dark',
    }).foregroundTone).toBe('light');
  });
});
