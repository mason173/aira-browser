import { BrowserResolvedThemeMode, BrowserThemePaletteId } from '../../common/models/BrowserModels';
import { BrowserThemePalette } from '../../features/theme/BrowserThemePaletteModels';
import { BrowserThemePaletteService } from '../../services/theme/BrowserThemePaletteService';

export interface ThemePaletteOptionState {
  id: BrowserThemePaletteId;
  title: string;
  subtitle: string;
  previewColor: string;
  darkPreviewColor: string;
  isSelected: boolean;
}

export interface ThemePaletteOptionGroupState {
  id: string;
  title: string;
  options: ThemePaletteOptionState[];
}

export interface ThemePaletteSettingsState {
  title: string;
  isPrivateContext: boolean;
  pageBackground: string;
  surfaceBackground: string;
  controlBackground: string;
  accentColor: string;
  textPrimary: string;
  textSecondary: string;
  groups: ThemePaletteOptionGroupState[];
}

export class BrowserThemePaletteViewModel {
  private paletteService: BrowserThemePaletteService = new BrowserThemePaletteService();

  buildState(
    selectedPaletteId: BrowserThemePaletteId,
    mode: BrowserResolvedThemeMode,
    dataScope: string = '',
    privacyMode: string = ''
  ): ThemePaletteSettingsState {
    const isPrivateContext = dataScope === 'session_ephemeral' || privacyMode === 'private';
    const resolvedTokens = this.paletteService.resolveTokens(
      selectedPaletteId,
      mode
    );
    const options = this.paletteService.listPalettes().map((palette: BrowserThemePalette): ThemePaletteOptionState => {
      return {
        id: palette.id,
        title: palette.title,
        subtitle: palette.subtitle,
        previewColor: palette.previewColor,
        darkPreviewColor: palette.dark.pageBackground,
        isSelected: palette.id === selectedPaletteId
      };
    });
    return {
      title: '主题色',
      isPrivateContext,
      pageBackground: resolvedTokens.pageBackground,
      surfaceBackground: resolvedTokens.surfaceBackground,
      controlBackground: resolvedTokens.controlBackground,
      accentColor: resolvedTokens.accent,
      textPrimary: resolvedTokens.textPrimary,
      textSecondary: resolvedTokens.textSecondary,
      groups: [
        {
          id: 'all',
          title: '全部主题色',
          options: options
        }
      ]
    };
  }

  resolvePaletteLabel(id: BrowserThemePaletteId): string {
    return this.paletteService.resolvePaletteLabel(id);
  }

}
