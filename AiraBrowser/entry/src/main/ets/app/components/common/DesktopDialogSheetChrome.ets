import { display, LengthMetrics } from '@kit.ArkUI';
import { DesktopDialogTier } from '../../../core/browser/BrowserDialogPresentationTokens';
import { DesktopDialogWidthViewModel } from '../../../core/browser/DesktopDialogWidthViewModel';
import { BrowserWindowRuntime } from '../../runtime/BrowserWindowRuntime';
import { resolveCenteredDialogSurfaceColor } from './CenteredDialogSurface';

const desktopDialogWidthViewModel: DesktopDialogWidthViewModel = new DesktopDialogWidthViewModel();

export function isLargeScreenDialogShell(): boolean {
  return BrowserWindowRuntime.resolveActiveShellPresentationSurface() === 'large_screen';
}

export function shouldCenterDialogSheet(callerRequestedCenter: boolean): boolean {
  return callerRequestedCenter || isLargeScreenDialogShell();
}

function readDisplayExtentVp(extentPx: number, densityPixels: number): number {
  if (!Number.isFinite(extentPx) || extentPx <= 0 ||
    !Number.isFinite(densityPixels) || densityPixels <= 0) {
    return 0;
  }
  return extentPx / densityPixels;
}

function readWindowExtentsVp(): number[] {
  try {
    const defaultDisplay = display.getDefaultDisplaySync();
    return [
      readDisplayExtentVp(defaultDisplay.width, defaultDisplay.densityPixels),
      readDisplayExtentVp(defaultDisplay.height, defaultDisplay.densityPixels)
    ];
  } catch (_error) {
    return [0, 0];
  }
}

/**
 * Large-screen sheets are centered dialogs. Phone options are returned unchanged
 * unless the caller already asked for a centered sheet. Missing a desktop prop
 * must not silently fall back to a bottom sheet.
 */
export function applyDesktopDialogSheetChrome(
  options: SheetOptions,
  tier: DesktopDialogTier,
  callerRequestedCenter: boolean = false,
  useTierMaxHeight: boolean = false
): SheetOptions {
  // Phone sheets return below without desktop chrome, but they still need this.
  // bindSheet defaults to RenderStrategy.FAST. With top blur, that mode samples
  // the dark mask into the top corners. OFFSCREEN draws the sheet first, then clips.
  options.radiusRenderStrategy = RenderStrategy.OFFSCREEN;
  if (!shouldCenterDialogSheet(callerRequestedCenter)) {
    return options;
  }
  const extents = readWindowExtentsVp();
  const layout = desktopDialogWidthViewModel.resolve(tier, extents[0], extents[1]);
  options.preferType = SheetType.CENTER;
  options.dragBar = false;
  options.showClose = false;
  options.width = layout.widthVp;
  options.radius = LengthMetrics.vp(layout.cornerRadiusVp);
  options.height = useTierMaxHeight ? layout.maxHeightVp : SheetSize.FIT_CONTENT;
  if (options.backgroundColor === undefined) {
    options.backgroundColor = resolveCenteredDialogSurfaceColor();
  }
  return options;
}
