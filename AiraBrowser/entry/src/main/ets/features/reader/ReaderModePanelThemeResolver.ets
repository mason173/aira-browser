import { ReaderModeTheme } from './ReaderModeModels';

export interface ReaderModePanelThemeTokens {
  panelBackgroundColor: string;
  dragHandleColor: string;
  inputBackgroundColor: string;
  cardBackgroundColor: string;
  pressedBackgroundColor: string;
  iconColor: string;
  primaryTextColor: string;
  secondaryTextColor: string;
}

export function resolveReaderModePanelTheme(theme: ReaderModeTheme): ReaderModePanelThemeTokens {
  if (theme === 'dark') {
    return {
      panelBackgroundColor: '#171717',
      dragHandleColor: '#2A2A2A',
      inputBackgroundColor: '#2A2A2A',
      cardBackgroundColor: '#2A2A2A',
      pressedBackgroundColor: '#363636',
      iconColor: '#F2F2F2',
      primaryTextColor: '#F2F2F2',
      secondaryTextColor: '#B8B8B8'
    };
  }
  if (theme === 'charcoal') {
    return {
      panelBackgroundColor: '#252627',
      dragHandleColor: '#333537',
      inputBackgroundColor: '#333537',
      cardBackgroundColor: '#333537',
      pressedBackgroundColor: '#3E4143',
      iconColor: '#E8E6DF',
      primaryTextColor: '#E8E6DF',
      secondaryTextColor: '#B9B5AA'
    };
  }
  if (theme === 'sage') {
    return {
      panelBackgroundColor: '#E8F1E6',
      dragHandleColor: '#DCE8D9',
      inputBackgroundColor: '#DCE8D9',
      cardBackgroundColor: '#F3F8F1',
      pressedBackgroundColor: '#D0DECC',
      iconColor: '#1D2A1F',
      primaryTextColor: '#1D2A1F',
      secondaryTextColor: '#5B6B5B'
    };
  }
  if (theme === 'sepia') {
    return {
      panelBackgroundColor: '#F4ECD8',
      dragHandleColor: '#E8DDC2',
      inputBackgroundColor: '#E8DDC2',
      cardBackgroundColor: '#FBF4E4',
      pressedBackgroundColor: '#D8CAA9',
      iconColor: '#3E321C',
      primaryTextColor: '#3E321C',
      secondaryTextColor: '#6C5F45'
    };
  }
  if (theme === 'paper') {
    return {
      panelBackgroundColor: '#F8F6EF',
      dragHandleColor: '#EDE7DA',
      inputBackgroundColor: '#EDE7DA',
      cardBackgroundColor: '#FFFDF8',
      pressedBackgroundColor: '#E2DBCC',
      iconColor: '#2B2924',
      primaryTextColor: '#2B2924',
      secondaryTextColor: '#6E685D'
    };
  }
  return {
    panelBackgroundColor: '#FFFFFF',
    dragHandleColor: '#F0F1F3',
    inputBackgroundColor: '#F0F1F3',
    cardBackgroundColor: '#FFFFFF',
    pressedBackgroundColor: '#E8EAEE',
    iconColor: '#111827',
    primaryTextColor: '#111827',
    secondaryTextColor: '#5F6670'
  };
}
