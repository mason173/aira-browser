import { ReaderModeTheme } from '../../../common/models/BrowserModels';
import { sharedBrowserThemeModeCoordinator } from '../../bootstrap/BrowserAppRuntime';

export interface ReadingThemeTokens {
  backgroundColor: ResourceColor;
  controlBackgroundColor: ResourceColor;
  primaryTextColor: ResourceColor;
  secondaryTextColor: ResourceColor;
}

export function resolveEffectiveReadingTheme(theme: ReaderModeTheme): ReaderModeTheme {
  return theme === 'system'
    ? sharedBrowserThemeModeCoordinator.resolveEffectiveMode('system')
    : theme;
}

export function resolveReadingThemeTokens(theme: ReaderModeTheme): ReadingThemeTokens {
  if (theme === 'dark') {
    return {
      backgroundColor: $r('app.color.reader_theme_dark_background'),
      controlBackgroundColor: $r('app.color.reader_theme_dark_control_background'),
      primaryTextColor: $r('app.color.reader_theme_dark_text_primary'),
      secondaryTextColor: $r('app.color.reader_theme_dark_text_secondary')
    };
  }
  if (theme === 'charcoal') {
    return {
      backgroundColor: $r('app.color.reader_theme_charcoal_background'),
      controlBackgroundColor: $r('app.color.reader_theme_charcoal_control_background'),
      primaryTextColor: $r('app.color.reader_theme_charcoal_text_primary'),
      secondaryTextColor: $r('app.color.reader_theme_charcoal_text_secondary')
    };
  }
  if (theme === 'sage') {
    return {
      backgroundColor: $r('app.color.reader_theme_sage_background'),
      controlBackgroundColor: $r('app.color.reader_theme_sage_control_background'),
      primaryTextColor: $r('app.color.reader_theme_sage_text_primary'),
      secondaryTextColor: $r('app.color.reader_theme_sage_text_secondary')
    };
  }
  if (theme === 'sepia') {
    return {
      backgroundColor: $r('app.color.reader_theme_sepia_background'),
      controlBackgroundColor: $r('app.color.reader_theme_sepia_control_background'),
      primaryTextColor: $r('app.color.reader_theme_sepia_text_primary'),
      secondaryTextColor: $r('app.color.reader_theme_sepia_text_secondary')
    };
  }
  if (theme === 'paper') {
    return {
      backgroundColor: $r('app.color.reader_theme_paper_background'),
      controlBackgroundColor: $r('app.color.reader_theme_paper_control_background'),
      primaryTextColor: $r('app.color.reader_theme_paper_text_primary'),
      secondaryTextColor: $r('app.color.reader_theme_paper_text_secondary')
    };
  }
  return {
    backgroundColor: $r('app.color.reader_theme_light_background'),
    controlBackgroundColor: $r('app.color.reader_theme_light_control_background'),
    primaryTextColor: $r('app.color.reader_theme_light_text_primary'),
    secondaryTextColor: $r('app.color.reader_theme_light_text_secondary')
  };
}

export function resolveReadingThemeChipBackgroundColor(theme: ReaderModeTheme): ResourceColor {
  return theme === 'dark' || theme === 'charcoal'
    ? $r('app.color.reader_surface_chip_dark')
    : $r('app.color.reader_surface_chip_light');
}
