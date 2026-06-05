export type SearchBarTheme = {
  foregroundTone: 'dark' | 'light';
  surfaceClassName: string;
  triggerToneClassName: string;
  clearButtonClassName: string;
  inputClassName: string;
  placeholderClassName: string;
  inlinePreviewClassName: string;
  linkIconClassName: string;
  dropdownSurfaceClassName: string;
  dropdownRowClassName: string;
  dropdownRowSelectedClassName: string;
  dropdownSecondaryTextClassName: string;
  engineDropdownSurfaceClassName: string;
  engineDropdownItemClassName: string;
  engineDropdownItemSelectedClassName: string;
  dropdownStatusLoadingContainerClassName: string;
  dropdownStatusInfoContainerClassName: string;
  dropdownStatusDotClassName: string;
  dropdownStatusTextClassName: string;
  dropdownStatusButtonClassName: string;
  dropdownClearButtonClassName: string;
  dropdownEmptyStateClassName: string;
  dropdownFooterClassName: string;
};

const SEARCH_THEME_TOKEN_CLASSES = {
  surfaceClassName: 'overflow-hidden bg-transparent text-[var(--search-ui-surface-foreground)] shadow-none',
  triggerToneClassName: 'text-[var(--search-ui-trigger-foreground)] transition-colors hover:text-[var(--search-ui-trigger-foreground-hover)]',
  clearButtonClassName: 'text-[var(--search-ui-clear-foreground)] hover:bg-[var(--search-ui-clear-background-hover)] hover:text-[var(--search-ui-clear-foreground-hover)]',
  inputClassName: 'bg-transparent dark:bg-transparent text-[var(--search-ui-input-foreground)] placeholder:text-[var(--search-ui-placeholder-foreground)]',
  placeholderClassName: 'text-[var(--search-ui-placeholder-foreground)]',
  inlinePreviewClassName: 'bg-muted text-muted-foreground',
  linkIconClassName: 'text-[var(--search-ui-subtle-foreground)]',
  dropdownSurfaceClassName: 'overflow-hidden bg-transparent text-[var(--search-ui-surface-foreground)] shadow-none',
  dropdownRowClassName: 'text-[var(--search-ui-foreground)] hover:bg-accent hover:text-accent-foreground focus:bg-accent focus:text-accent-foreground',
  dropdownRowSelectedClassName: 'bg-accent text-accent-foreground',
  dropdownSecondaryTextClassName: 'text-[var(--search-ui-subtle-foreground)]',
  engineDropdownSurfaceClassName: 'overflow-hidden bg-transparent text-[var(--search-ui-engine-item-foreground)] shadow-none',
  engineDropdownItemClassName: 'text-[var(--search-ui-engine-item-foreground)] hover:bg-accent hover:text-accent-foreground focus:bg-accent focus:text-accent-foreground',
  engineDropdownItemSelectedClassName: 'bg-accent text-accent-foreground',
  dropdownStatusLoadingContainerClassName: 'bg-muted',
  dropdownStatusInfoContainerClassName: 'bg-muted',
  dropdownStatusDotClassName: 'bg-[var(--search-ui-status-dot)]',
  dropdownStatusTextClassName: 'text-[var(--search-ui-foreground)]',
  dropdownStatusButtonClassName: 'bg-accent text-accent-foreground hover:bg-accent',
  dropdownClearButtonClassName: 'text-[var(--search-ui-subtle-foreground)] hover:text-[var(--search-ui-foreground)]',
  dropdownEmptyStateClassName: 'text-[var(--search-ui-subtle-foreground)]',
  dropdownFooterClassName: 'border-[var(--frosted-ui-border)] text-[var(--search-ui-subtle-foreground)]',
} satisfies Omit<SearchBarTheme, 'foregroundTone'>;

const darkForegroundSearchTheme: SearchBarTheme = {
  foregroundTone: 'dark',
  ...SEARCH_THEME_TOKEN_CLASSES,
};

const lightForegroundSearchTheme: SearchBarTheme = {
  foregroundTone: 'light',
  ...SEARCH_THEME_TOKEN_CLASSES,
};

function clamp01(value: number) {
  if (!Number.isFinite(value)) return 0;
  return Math.min(1, Math.max(0, value));
}

function resolveContrastRatio(args: {
  lighterLuminance: number;
  darkerLuminance: number;
}) {
  return (args.lighterLuminance + 0.05) / (args.darkerLuminance + 0.05);
}

function resolveWhiteForegroundContrast(backgroundLuminance: number) {
  return resolveContrastRatio({
    lighterLuminance: 1,
    darkerLuminance: clamp01(backgroundLuminance),
  });
}

function resolveBlackForegroundContrast(backgroundLuminance: number) {
  return resolveContrastRatio({
    lighterLuminance: clamp01(backgroundLuminance),
    darkerLuminance: 0,
  });
}

export function resolveSearchBarTheme(args: {
  blankMode?: boolean;
  forceWhiteTheme?: boolean;
  subtleDarkTone?: boolean;
  resolvedTheme?: string;
  backgroundLuminance?: number | null;
  backgroundLuminanceRange?: {
    darkest: number;
    brightest: number;
  } | null;
}): SearchBarTheme {
  void args.blankMode;
  void args.subtleDarkTone;
  const regionalAverageCandidate = args.backgroundLuminance;
  const regionalRangeCandidate = args.backgroundLuminanceRange;
  const hasRegionalLuminance = typeof regionalAverageCandidate === 'number'
    && Number.isFinite(regionalAverageCandidate);
  const normalizedAverageLuminance = hasRegionalLuminance ? clamp01(regionalAverageCandidate) : null;
  const hasRegionalRange = regionalRangeCandidate !== null
    && regionalRangeCandidate !== undefined
    && typeof regionalRangeCandidate.darkest === 'number'
    && Number.isFinite(regionalRangeCandidate.darkest)
    && typeof regionalRangeCandidate.brightest === 'number'
    && Number.isFinite(regionalRangeCandidate.brightest);
  const normalizedDarkestLuminance = hasRegionalRange
    ? clamp01(Math.min(regionalRangeCandidate.darkest, regionalRangeCandidate.brightest))
    : null;
  const normalizedBrightestLuminance = hasRegionalRange
    ? clamp01(Math.max(regionalRangeCandidate.darkest, regionalRangeCandidate.brightest))
    : null;

  const prefersDarkForeground = (() => {
    if (args.resolvedTheme === 'light') {
      return true;
    }

    if (args.resolvedTheme === 'dark') {
      return false;
    }

    if (normalizedDarkestLuminance !== null && normalizedBrightestLuminance !== null) {
      const sampledAverage = normalizedAverageLuminance ?? (
        (normalizedDarkestLuminance + normalizedBrightestLuminance) / 2
      );

      const whiteWorstContrast = resolveWhiteForegroundContrast(normalizedBrightestLuminance);
      const blackWorstContrast = resolveBlackForegroundContrast(normalizedDarkestLuminance);
      const whiteAverageContrast = resolveWhiteForegroundContrast(sampledAverage);
      const blackAverageContrast = resolveBlackForegroundContrast(sampledAverage);

      const blackClearlyDominant = (
        blackWorstContrast >= 6.1
        && blackAverageContrast >= 9.2
        && (blackWorstContrast - whiteWorstContrast) >= 2.3
        && (blackAverageContrast - whiteAverageContrast) >= 3.4
        && sampledAverage >= 0.6
        && normalizedDarkestLuminance >= 0.46
      );

      if (blackClearlyDominant) {
        return true;
      }

      return false;
    }

    if (normalizedAverageLuminance !== null) {
      return normalizedAverageLuminance >= 0.8;
    }

    if (args.forceWhiteTheme) {
      return false;
    }

    return args.resolvedTheme !== 'dark';
  })();

  if (prefersDarkForeground) {
    return darkForegroundSearchTheme;
  }

  return lightForegroundSearchTheme;
}
