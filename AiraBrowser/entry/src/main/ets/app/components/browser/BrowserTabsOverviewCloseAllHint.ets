import { BrowserBottomPanelResponsiveViewModel } from '../../../core/browser/BrowserBottomPanelResponsiveViewModel';
import { BrowserTabsOverviewSection } from '../../../core/browser/tabsOverview/BrowserTabsOverviewSectionPolicy';
import { BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_BLOCK_GAP,
  BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_BOTTOM_CLEARANCE,
  BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT,
  BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_OUTER_SIZE,
  BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_SEGMENT_INSET
} from './BrowserTabsOverviewBottomChrome';

const CLOSE_ALL_HINT_TEXT_WIDTH: number = 184;
const CLOSE_ALL_HINT_HEIGHT: number = 54;

/** Background ink only: cards paint above it, and every gesture passes through it. */
@Component
export struct BrowserTabsOverviewCloseAllHint {
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = '#5F6875';
  @Prop selectedSection: BrowserTabsOverviewSection = 'tabs';
  @Prop viewportWidth: number = 390;
  @Prop viewportHeight: number = 844;
  @Prop bottomChromeLiftVp: number = 0;
  @Prop surfaceOpacity: number = 1;
  private responsiveViewModel: BrowserBottomPanelResponsiveViewModel = new BrowserBottomPanelResponsiveViewModel();

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Text($r('app.string.tabs_overview_close_all_hint'))
        .width(Math.min(CLOSE_ALL_HINT_TEXT_WIDTH, this.resolveChromeWidth()))
        .height(20)
        .fontSize(12)
        .fontColor(this.resolveSecondaryColor())
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .position({ x: this.resolveCloseAllHintTextLeft(), y: 0 })

      Shape() {
        Path()
          .commands('M 2 2 C 27 2 29 15 18 27 M 17 19 L 18 27 L 26 25')
          .fillOpacity(0)
          .stroke(this.resolveSecondaryColor())
          .strokeWidth(1.25)
          .strokeLineCap(LineCapStyle.Round)
          .strokeLineJoin(LineJoinStyle.Round)
      }
      .viewPort({ x: 0, y: 0, width: 36, height: 30 })
      .width(36)
      .height(30)
      .position({ x: this.resolveCloseAllHintTargetCenter() - 18, y: 24 })
    }
    .width(this.resolveChromeWidth())
    .height(CLOSE_ALL_HINT_HEIGHT)
    .position({
      x: this.resolveChromeLeft(),
      y: this.resolveChromeTop() - CLOSE_ALL_HINT_HEIGHT - 8
    })
    .opacity(0.56 * this.surfaceOpacity)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no-hide-descendants')
  }

  private resolveCloseAllHintTargetCenter(): number {
    const inset = BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_SEGMENT_INSET;
    const segmentWidth = Math.max(1, (this.resolveSectionSwitcherWidth() - inset * 2) / 3);
    return BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_OUTER_SIZE +
      BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_BLOCK_GAP + inset +
      segmentWidth * (this.selectedSection === 'privacy' ? 0.5 : 1.5);
  }

  private resolveCloseAllHintTextLeft(): number {
    return Math.max(0, Math.min(
      this.resolveCloseAllHintTargetCenter() - CLOSE_ALL_HINT_TEXT_WIDTH / 2,
      this.resolveChromeWidth() - CLOSE_ALL_HINT_TEXT_WIDTH
    ));
  }

  private resolveChromeWidth(): number {
    return this.responsiveViewModel.buildState({
      viewportWidth: this.viewportWidth,
      viewportHeight: this.viewportHeight
    }).panelWidth;
  }

  private resolveChromeLeft(): number {
    return this.responsiveViewModel.buildState({
      viewportWidth: this.viewportWidth,
      viewportHeight: this.viewportHeight
    }).panelOffsetX;
  }

  private resolveChromeTop(): number {
    const lift = Number.isFinite(this.bottomChromeLiftVp) ? Math.max(0, this.bottomChromeLiftVp) : 0;
    return Math.max(0, this.viewportHeight - BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_BOTTOM_CLEARANCE -
      lift - BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT);
  }

  private resolveSectionSwitcherWidth(): number {
    return Math.max(1, this.resolveChromeWidth() -
      (BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_OUTER_SIZE + BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_BLOCK_GAP) * 2);
  }

  private resolveSecondaryColor(): ResourceColor {
    return this.storedSecondaryTextColor;
  }
}
