import {
  BrowserBottomAddressPanelHeaderAction
} from './BrowserBottomAddressPanelViewModel';
import {
  BROWSER_BOTTOM_ADDRESS_PANEL_PHONE_HEADER_HORIZONTAL_PADDING,
  BROWSER_BOTTOM_CHROME_PHONE_OUTER_GAP,
  BROWSER_BOTTOM_CHROME_PHONE_OUTER_SIZE
} from './BrowserBottomAddressPanelMetrics';
import { HomeSearchPanelDetent } from './HomeSearchPanelDetentViewModel';
import { BrowserBottomChromeScrollPresentation } from './BrowserBottomChromeScrollCoordinator';
import {
  BROWSER_BOTTOM_PANEL_MIDDLE_SNAP_DURATION_MS,
  BROWSER_BOTTOM_PANEL_MOTION_DURATION_MS,
  resolveBrowserBottomPanelMiddleSnapCurve,
  resolveBrowserBottomPanelMotionCurve
} from './BrowserBottomPanelMotionTokens';
import {
  BrowserSearchEngineChromePresentation
} from './BrowserSearchEnginePresentationViewModel';
import { AiraRenderableIconId } from '../resources/GeneratedAiraIconCatalog';
import {
  BrowserToolbarSlotInteractionState,
  BrowserToolbarSlotActionState,
  BrowserToolbarSlotId
} from './BrowserToolbarCustomizationViewModel';
import { BrowserBottomPanelActionEnablementById } from './BrowserBottomPanelActionEnablement';
import {
  BrowserWebProtectionFeedbackPresentation,
  EMPTY_BROWSER_WEB_PROTECTION_FEEDBACK_PRESENTATION
} from './BrowserWebProtectionFeedbackSessionCoordinator';

export type BrowserBottomChromePresentationMode =
  'resting-three-block' |
  'center-active-tools' |
  'center-active-editing' |
  'scroll-compact' |
  'return-home-drag';

export type BrowserBottomChromePresentationScene = 'home' | 'web' | 'inactive';
export type BrowserBottomChromeHeaderPresentation = 'home' | 'address';
export type BrowserBottomChromeContentPresentation = 'home' | 'web';
export type BrowserBottomChromeCenterContentLayer = 'display' | 'editing' | 'return-home';
export type BrowserBottomAddressContextAction =
  'copy_link' |
  'paste_and_go' |
  'paste_authorization_failed';

export type BrowserBottomChromeGestureSource =
  'none' |
  'leading-outer' |
  'center-capsule' |
  'trailing-outer';

export type BrowserBottomChromeTapIntentKind =
  'none' |
  'activate-editing' |
  'open-search-engine-menu' |
  'dispatch-header-action' |
  'dispatch-panel-action' |
  'clear-input' |
  'restore-current-address';

export type BrowserBottomChromeMotionKind = 'immediate' | 'animated' | 'direct';

export interface BrowserBottomChromePresentationFacts {
  scene: BrowserBottomChromePresentationScene;
  addressFocused: boolean;
  addressEditable: boolean;
  currentDetent: HomeSearchPanelDetent;
  scrollPresentation: BrowserBottomChromeScrollPresentation;
  returnHomeDrag: boolean;
  returnHomeProgress: number;
  panelWidth: number;
  expandedChromeWidth?: number;
  floatingHeaderHorizontalPadding?: number;
  restingChromeOuterSize?: number;
  restingChromeOuterGap?: number;
  panelExpansionEnabled: boolean;
  addressInput: string;
  addressDisplayText: string;
  placeholder: string;
  searchEnginePresentation?: BrowserSearchEngineChromePresentation;
  toolbarSlotActions?: BrowserToolbarSlotActionState[];
  toolbarActionEnablement?: BrowserBottomPanelActionEnablementById;
  toolbarInteractionProfileActive?: boolean;
  customizationPreview?: boolean;
  gesturePromptText?: string;
  webProtectionFeedback?: BrowserWebProtectionFeedbackPresentation;
  leadingHeaderActions: BrowserBottomAddressPanelHeaderAction[];
  trailingHeaderActions: BrowserBottomAddressPanelHeaderAction[];
}

export interface BrowserBottomChromeReturnHomeGestureInput {
  source: BrowserBottomChromeGestureSource;
  offsetY: number;
  eligible: boolean;
  promptText?: string;
}

export interface BrowserBottomChromeReturnHomeGestureState {
  active: boolean;
  armed: boolean;
  progress: number;
  promptText: string;
}

interface BrowserBottomChromeFrameValues {
  leadingOuterWidth: number;
  leadingGap: number;
  centerWidth: number;
  trailingGap: number;
  trailingOuterWidth: number;
  centerHeight: number;
  centerRadius: number;
  centerTranslateY: number;
  centerDisplayScale: number;
  centerHorizontalPadding: number;
  centerVerticalPadding: number;
  centerLeadingWidth: number;
  centerPrimaryWidth: number;
  centerAccessoryGap: number;
  centerSecondaryWidth: number;
  centerViewportWidth: number;
  centerViewportHeight: number;
  outerOpacity: number;
  menuOpacity: number;
  refreshOpacity: number;
  copyOpacity: number;
  clearOpacity: number;
  editOpacity: number;
  displayOpacity: number;
  editingOpacity: number;
  returnHomeOpacity: number;
}

interface BrowserBottomChromeFrameOverrides {
  leadingOuterWidth?: number;
  leadingGap?: number;
  centerWidth?: number;
  trailingGap?: number;
  trailingOuterWidth?: number;
  centerHeight?: number;
  centerRadius?: number;
  centerTranslateY?: number;
  centerDisplayScale?: number;
  centerHorizontalPadding?: number;
  centerVerticalPadding?: number;
  centerLeadingWidth?: number;
  centerPrimaryWidth?: number;
  centerAccessoryGap?: number;
  centerSecondaryWidth?: number;
  centerViewportWidth?: number;
  centerViewportHeight?: number;
  outerOpacity?: number;
  menuOpacity?: number;
  refreshOpacity?: number;
  copyOpacity?: number;
  clearOpacity?: number;
  editOpacity?: number;
  displayOpacity?: number;
  editingOpacity?: number;
  returnHomeOpacity?: number;
}

interface BrowserBottomChromePresentationValues {
  scene: BrowserBottomChromePresentationScene;
  mode: BrowserBottomChromePresentationMode;
  panelWidth: number;
  floatingSurfaceTranslateY: number;
  frame: BrowserBottomChromeFrame;
  leadingOuterTarget: BrowserBottomChromeTapTarget;
  centerBodyTarget: BrowserBottomChromeTapTarget;
  centerLeadingTarget: BrowserBottomChromeTapTarget;
  centerPrimaryTarget: BrowserBottomChromeTapTarget;
  centerSecondaryTarget: BrowserBottomChromeTapTarget;
  trailingOuterTarget: BrowserBottomChromeTapTarget;
  leadingOuterLongPressTarget: BrowserBottomChromeTapTarget;
  centerLeadingLongPressTarget: BrowserBottomChromeTapTarget;
  centerPrimaryLongPressTarget: BrowserBottomChromeTapTarget;
  trailingOuterLongPressTarget: BrowserBottomChromeTapTarget;
  toolbarInteractionProfileActive: boolean;
  leadingOuterVisualEnabled: boolean;
  centerLeadingVisualEnabled: boolean;
  centerPrimaryVisualEnabled: boolean;
  trailingOuterVisualEnabled: boolean;
  addressInput: string;
  placeholder: string;
  searchEnginePresentation: BrowserSearchEngineChromePresentation;
  centerContent: BrowserBottomChromeCenterContentPresentation;
  leadingOuterIconId: AiraRenderableIconId;
  centerLeadingIconId: AiraRenderableIconId;
  centerPrimaryIconId: AiraRenderableIconId;
  trailingOuterIconId: AiraRenderableIconId;
  leadingHeaderActions: BrowserBottomAddressPanelHeaderAction[];
  trailingHeaderActions: BrowserBottomAddressPanelHeaderAction[];
}

const BROWSER_BOTTOM_CHROME_MATERIAL_HEIGHT: number = 52;
const BROWSER_BOTTOM_CHROME_RESTING_HORIZONTAL_PADDING: number = 2;
const BROWSER_BOTTOM_CHROME_ACCESSORY_SIZE: number = 48;
const BROWSER_BOTTOM_CHROME_ACCESSORY_GAP: number = 2;
const BROWSER_BOTTOM_CHROME_COMPACT_WIDTH: number = 96;
const BROWSER_BOTTOM_CHROME_COMPACT_HEIGHT: number = 32;
const BROWSER_BOTTOM_CHROME_COMPACT_RADIUS: number = 16;
const BROWSER_BOTTOM_CHROME_COMPACT_TRANSLATE_Y: number = 20;
const BROWSER_BOTTOM_CHROME_COMPACT_FLOATING_SURFACE_TRANSLATE_Y: number = 20;
const BROWSER_BOTTOM_CHROME_COMPACT_DISPLAY_SCALE: number = 14 / 15;
const BROWSER_BOTTOM_CHROME_COMPACT_HORIZONTAL_PADDING: number = 10;
const BROWSER_BOTTOM_CHROME_COMPACT_VERTICAL_PADDING: number = 4;
const BROWSER_BOTTOM_CHROME_RETURN_HOME_ACTIVE_OFFSET_Y: number = 8;
const BROWSER_BOTTOM_CHROME_RETURN_HOME_RELEASE_OFFSET_Y: number = 44;
const BROWSER_BOTTOM_CHROME_DEFAULT_GESTURE_PROMPT: string = '松手打开主页';
const BROWSER_BOTTOM_CHROME_FOCUS_READY_PROGRESS: number = 0.35;
const BROWSER_BOTTOM_CHROME_FRAME_EPSILON: number = 0.001;
const EMPTY_SEARCH_ENGINE_CHROME_PRESENTATION: BrowserSearchEngineChromePresentation =
  new BrowserSearchEngineChromePresentation('bing', [], '搜索或输入网址');

export class BrowserBottomChromeTapIntent {
  kind: BrowserBottomChromeTapIntentKind;
  actionId: string;
  slotId: string;
  disabledMessage: string;

  constructor(
    kind: BrowserBottomChromeTapIntentKind,
    actionId: string = '',
    slotId: string = '',
    disabledMessage: string = ''
  ) {
    this.kind = kind;
    this.actionId = actionId;
    this.slotId = slotId;
    this.disabledMessage = disabledMessage;
  }
}

export class BrowserBottomChromeTapTarget {
  intent: BrowserBottomChromeTapIntent;
  enabled: boolean;
  accessibilityText: string;
  reliable: boolean;

  constructor(
    intent: BrowserBottomChromeTapIntent,
    enabled: boolean,
    accessibilityText: string,
    reliable: boolean = false
  ) {
    this.intent = intent;
    this.enabled = enabled;
    this.accessibilityText = accessibilityText;
    this.reliable = reliable;
  }
}

export class BrowserBottomChromeFrame {
  leadingOuterWidth: number;
  leadingGap: number;
  centerWidth: number;
  trailingGap: number;
  trailingOuterWidth: number;
  centerHeight: number;
  centerRadius: number;
  centerTranslateY: number;
  centerDisplayScale: number;
  centerHorizontalPadding: number;
  centerVerticalPadding: number;
  centerLeadingWidth: number;
  centerPrimaryWidth: number;
  centerAccessoryGap: number;
  centerSecondaryWidth: number;
  centerViewportWidth: number;
  centerViewportHeight: number;
  outerOpacity: number;
  menuOpacity: number;
  refreshOpacity: number;
  copyOpacity: number;
  clearOpacity: number;
  editOpacity: number;
  displayOpacity: number;
  editingOpacity: number;
  returnHomeOpacity: number;

  constructor(values: BrowserBottomChromeFrameValues) {
    this.leadingOuterWidth = sanitizeSize(values.leadingOuterWidth);
    this.leadingGap = sanitizeSize(values.leadingGap);
    this.centerWidth = sanitizeSize(values.centerWidth);
    this.trailingGap = sanitizeSize(values.trailingGap);
    this.trailingOuterWidth = sanitizeSize(values.trailingOuterWidth);
    this.centerHeight = sanitizeSize(values.centerHeight);
    this.centerRadius = sanitizeSize(values.centerRadius);
    this.centerTranslateY = sanitizeFinite(values.centerTranslateY);
    this.centerDisplayScale = Math.max(0.01, sanitizeFinite(values.centerDisplayScale));
    this.centerHorizontalPadding = sanitizeSize(values.centerHorizontalPadding);
    this.centerVerticalPadding = sanitizeSize(values.centerVerticalPadding);
    this.centerLeadingWidth = sanitizeSize(values.centerLeadingWidth);
    this.centerPrimaryWidth = sanitizeSize(values.centerPrimaryWidth);
    this.centerAccessoryGap = sanitizeSize(values.centerAccessoryGap);
    this.centerSecondaryWidth = sanitizeSize(values.centerSecondaryWidth);
    this.centerViewportWidth = sanitizeSize(values.centerViewportWidth);
    this.centerViewportHeight = sanitizeSize(values.centerViewportHeight);
    this.outerOpacity = clampUnit(values.outerOpacity);
    this.menuOpacity = clampUnit(values.menuOpacity);
    this.refreshOpacity = clampUnit(values.refreshOpacity);
    this.copyOpacity = clampUnit(values.copyOpacity);
    this.clearOpacity = clampUnit(values.clearOpacity);
    this.editOpacity = clampUnit(values.editOpacity);
    this.displayOpacity = clampUnit(values.displayOpacity);
    this.editingOpacity = clampUnit(values.editingOpacity);
    this.returnHomeOpacity = clampUnit(values.returnHomeOpacity);
  }

  isEquivalent(other: BrowserBottomChromeFrame): boolean {
    return approximatelyEqual(this.leadingOuterWidth, other.leadingOuterWidth) &&
      approximatelyEqual(this.leadingGap, other.leadingGap) &&
      approximatelyEqual(this.centerWidth, other.centerWidth) &&
      approximatelyEqual(this.trailingGap, other.trailingGap) &&
      approximatelyEqual(this.trailingOuterWidth, other.trailingOuterWidth) &&
      approximatelyEqual(this.centerHeight, other.centerHeight) &&
      approximatelyEqual(this.centerRadius, other.centerRadius) &&
      approximatelyEqual(this.centerTranslateY, other.centerTranslateY) &&
      approximatelyEqual(this.centerDisplayScale, other.centerDisplayScale) &&
      approximatelyEqual(this.centerHorizontalPadding, other.centerHorizontalPadding) &&
      approximatelyEqual(this.centerVerticalPadding, other.centerVerticalPadding) &&
      approximatelyEqual(this.centerLeadingWidth, other.centerLeadingWidth) &&
      approximatelyEqual(this.centerPrimaryWidth, other.centerPrimaryWidth) &&
      approximatelyEqual(this.centerAccessoryGap, other.centerAccessoryGap) &&
      approximatelyEqual(this.centerSecondaryWidth, other.centerSecondaryWidth) &&
      approximatelyEqual(this.centerViewportWidth, other.centerViewportWidth) &&
      approximatelyEqual(this.centerViewportHeight, other.centerViewportHeight) &&
      approximatelyEqual(this.outerOpacity, other.outerOpacity) &&
      approximatelyEqual(this.menuOpacity, other.menuOpacity) &&
      approximatelyEqual(this.refreshOpacity, other.refreshOpacity) &&
      approximatelyEqual(this.copyOpacity, other.copyOpacity) &&
      approximatelyEqual(this.clearOpacity, other.clearOpacity) &&
      approximatelyEqual(this.editOpacity, other.editOpacity) &&
      approximatelyEqual(this.displayOpacity, other.displayOpacity) &&
      approximatelyEqual(this.editingOpacity, other.editingOpacity) &&
      approximatelyEqual(this.returnHomeOpacity, other.returnHomeOpacity);
  }
}

export class BrowserBottomChromeMotionDirective {
  kind: BrowserBottomChromeMotionKind;
  durationMs: number;
  curve?: ICurve;
  focusReadyProgress: number;

  constructor(
    kind: BrowserBottomChromeMotionKind,
    durationMs: number,
    curve: ICurve | undefined,
    focusReadyProgress: number = -1
  ) {
    this.kind = kind;
    this.durationMs = Math.max(0, Math.floor(durationMs));
    this.curve = curve;
    this.focusReadyProgress = focusReadyProgress;
  }
}

export class BrowserBottomChromeCenterContentPresentation {
  activeLayer: BrowserBottomChromeCenterContentLayer;
  displayKey: string;
  displayText: string;
  displayUsesSecondaryTone: boolean;
  promptText: string;
  webProtectionFeedback: BrowserWebProtectionFeedbackPresentation;

  constructor(
    activeLayer: BrowserBottomChromeCenterContentLayer,
    displayKey: string,
    displayText: string,
    displayUsesSecondaryTone: boolean,
    promptText: string,
    webProtectionFeedback: BrowserWebProtectionFeedbackPresentation =
      EMPTY_BROWSER_WEB_PROTECTION_FEEDBACK_PRESENTATION
  ) {
    this.activeLayer = activeLayer;
    this.displayKey = displayKey;
    this.displayText = displayText;
    this.displayUsesSecondaryTone = displayUsesSecondaryTone;
    this.promptText = promptText;
    this.webProtectionFeedback = webProtectionFeedback;
  }
}

export class BrowserBottomChromePresentation {
  scene: BrowserBottomChromePresentationScene;
  headerPresentation: BrowserBottomChromeHeaderPresentation;
  contentPresentation: BrowserBottomChromeContentPresentation;
  effectiveHome: boolean;
  effectiveWeb: boolean;
  mode: BrowserBottomChromePresentationMode;
  panelWidth: number;
  floatingSurfaceTranslateY: number;
  frame: BrowserBottomChromeFrame;
  leadingOuterTarget: BrowserBottomChromeTapTarget;
  centerBodyTarget: BrowserBottomChromeTapTarget;
  centerLeadingTarget: BrowserBottomChromeTapTarget;
  centerPrimaryTarget: BrowserBottomChromeTapTarget;
  centerSecondaryTarget: BrowserBottomChromeTapTarget;
  trailingOuterTarget: BrowserBottomChromeTapTarget;
  leadingOuterLongPressTarget: BrowserBottomChromeTapTarget;
  centerLeadingLongPressTarget: BrowserBottomChromeTapTarget;
  centerPrimaryLongPressTarget: BrowserBottomChromeTapTarget;
  trailingOuterLongPressTarget: BrowserBottomChromeTapTarget;
  toolbarInteractionProfileActive: boolean;
  leadingOuterVisualEnabled: boolean;
  centerLeadingVisualEnabled: boolean;
  centerPrimaryVisualEnabled: boolean;
  trailingOuterVisualEnabled: boolean;
  addressInput: string;
  placeholder: string;
  searchEnginePresentation: BrowserSearchEngineChromePresentation;
  centerContent: BrowserBottomChromeCenterContentPresentation;
  leadingOuterIconId: AiraRenderableIconId;
  centerLeadingIconId: AiraRenderableIconId;
  centerPrimaryIconId: AiraRenderableIconId;
  trailingOuterIconId: AiraRenderableIconId;
  leadingHeaderActions: BrowserBottomAddressPanelHeaderAction[];
  trailingHeaderActions: BrowserBottomAddressPanelHeaderAction[];

  constructor(values: BrowserBottomChromePresentationValues) {
    this.scene = values.scene;
    this.headerPresentation = values.scene === 'home' ? 'home' : 'address';
    this.contentPresentation = values.scene === 'home' ? 'home' : 'web';
    this.effectiveHome = values.scene === 'home';
    this.effectiveWeb = values.scene === 'web';
    this.mode = values.mode;
    this.panelWidth = Math.max(1, values.panelWidth);
    this.floatingSurfaceTranslateY = sanitizeFinite(values.floatingSurfaceTranslateY);
    this.frame = values.frame;
    this.leadingOuterTarget = values.leadingOuterTarget;
    this.centerBodyTarget = values.centerBodyTarget;
    this.centerLeadingTarget = values.centerLeadingTarget;
    this.centerPrimaryTarget = values.centerPrimaryTarget;
    this.centerSecondaryTarget = values.centerSecondaryTarget;
    this.trailingOuterTarget = values.trailingOuterTarget;
    this.leadingOuterLongPressTarget = values.leadingOuterLongPressTarget;
    this.centerLeadingLongPressTarget = values.centerLeadingLongPressTarget;
    this.centerPrimaryLongPressTarget = values.centerPrimaryLongPressTarget;
    this.trailingOuterLongPressTarget = values.trailingOuterLongPressTarget;
    this.toolbarInteractionProfileActive = values.toolbarInteractionProfileActive;
    this.leadingOuterVisualEnabled = values.leadingOuterVisualEnabled;
    this.centerLeadingVisualEnabled = values.centerLeadingVisualEnabled;
    this.centerPrimaryVisualEnabled = values.centerPrimaryVisualEnabled;
    this.trailingOuterVisualEnabled = values.trailingOuterVisualEnabled;
    this.addressInput = values.addressInput;
    this.placeholder = values.placeholder;
    this.searchEnginePresentation = values.searchEnginePresentation;
    this.centerContent = values.centerContent;
    this.leadingOuterIconId = values.leadingOuterIconId;
    this.centerLeadingIconId = values.centerLeadingIconId;
    this.centerPrimaryIconId = values.centerPrimaryIconId;
    this.trailingOuterIconId = values.trailingOuterIconId;
    this.leadingHeaderActions = values.leadingHeaderActions;
    this.trailingHeaderActions = values.trailingHeaderActions;
  }

  resolveGestureSource(localX: number): BrowserBottomChromeGestureSource {
    if (!Number.isFinite(localX)) {
      return 'none';
    }
    const totalWidth = this.frame.leadingOuterWidth + this.frame.leadingGap + this.frame.centerWidth +
      this.frame.trailingGap + this.frame.trailingOuterWidth;
    const contentLeft = Math.max(0, (this.panelWidth - totalWidth) / 2);
    const leadingRight = contentLeft + this.frame.leadingOuterWidth;
    if (this.frame.leadingOuterWidth > 0 && localX >= contentLeft && localX <= leadingRight) {
      return 'leading-outer';
    }
    const centerLeft = leadingRight + this.frame.leadingGap;
    const centerRight = centerLeft + this.frame.centerWidth;
    if (localX >= centerLeft && localX <= centerRight) {
      return 'center-capsule';
    }
    const trailingLeft = centerRight + this.frame.trailingGap;
    const trailingRight = trailingLeft + this.frame.trailingOuterWidth;
    if (this.frame.trailingOuterWidth > 0 && localX >= trailingLeft && localX <= trailingRight) {
      return 'trailing-outer';
    }
    return 'none';
  }

  resolveMotionFrom(previous?: BrowserBottomChromePresentation): BrowserBottomChromeMotionDirective {
    if (previous === undefined) {
      return new BrowserBottomChromeMotionDirective(
        'immediate',
        0,
        undefined,
        this.mode === 'center-active-editing' ? 0 : -1
      );
    }
    if (this.mode === 'return-home-drag') {
      return new BrowserBottomChromeMotionDirective('direct', 0, undefined);
    }
    const wideTransition = isWideMode(this.mode) || isWideMode(previous.mode);
    const focusReadyProgress = this.resolveFocusReadyProgress(previous);
    if (wideTransition) {
      return new BrowserBottomChromeMotionDirective(
        'animated',
        BROWSER_BOTTOM_PANEL_MIDDLE_SNAP_DURATION_MS,
        resolveBrowserBottomPanelMiddleSnapCurve(),
        focusReadyProgress
      );
    }
    return new BrowserBottomChromeMotionDirective(
      'animated',
      BROWSER_BOTTOM_PANEL_MOTION_DURATION_MS,
      resolveBrowserBottomPanelMotionCurve(),
      focusReadyProgress
    );
  }

  private resolveFocusReadyProgress(previous: BrowserBottomChromePresentation): number {
    if (this.mode !== 'center-active-editing' || previous.mode === 'center-active-editing') {
      return -1;
    }
    return previous.mode === 'center-active-tools' ? 0 : BROWSER_BOTTOM_CHROME_FOCUS_READY_PROGRESS;
  }
}

const EMPTY_TAP_TARGET: BrowserBottomChromeTapTarget = new BrowserBottomChromeTapTarget(
  new BrowserBottomChromeTapIntent('none'),
  false,
  ''
);

export class BrowserBottomChromePresentationViewModel {
  buildPresentation(facts: BrowserBottomChromePresentationFacts): BrowserBottomChromePresentation {
    const mode = this.resolveMode(facts);
    const frame = this.buildFrame(facts, mode);
    const searchEnginePresentation = facts.searchEnginePresentation ?? EMPTY_SEARCH_ENGINE_CHROME_PRESENTATION;
    const leadingAction = findHeaderAction(facts.leadingHeaderActions, 0);
    const refreshAction = findHeaderAction(facts.trailingHeaderActions, 0);
    const tabsAction = findHeaderAction(facts.trailingHeaderActions, 1);
    const leadingSlot = findToolbarSlotAction(facts.toolbarSlotActions, 'leading');
    const menuSlot = findToolbarSlotAction(facts.toolbarSlotActions, 'menu');
    const refreshSlot = findToolbarSlotAction(facts.toolbarSlotActions, 'refresh');
    const tabsSlot = findToolbarSlotAction(facts.toolbarSlotActions, 'tabs');
    const leadingOuterTarget = this.buildLeadingOuterTarget(facts, mode, leadingSlot, leadingAction);
    const trailingOuterTarget = this.buildTrailingOuterTarget(facts, mode, tabsSlot, tabsAction);
    const centerLeadingTarget = this.buildCenterLeadingTarget(facts, mode, menuSlot);
    const centerPrimaryTarget = this.buildCenterPrimaryTarget(facts, mode, refreshSlot, refreshAction);
    return new BrowserBottomChromePresentation({
      scene: facts.scene,
      mode,
      panelWidth: facts.panelWidth,
      floatingSurfaceTranslateY: mode === 'scroll-compact' ?
        BROWSER_BOTTOM_CHROME_COMPACT_FLOATING_SURFACE_TRANSLATE_Y : 0,
      frame,
      leadingOuterTarget,
      centerBodyTarget: this.buildCenterBodyTarget(facts, mode),
      centerLeadingTarget,
      centerPrimaryTarget,
      centerSecondaryTarget: this.buildCenterSecondaryTarget(facts, mode),
      trailingOuterTarget,
      leadingOuterLongPressTarget: this.buildLongPressTarget(facts, mode, leadingSlot),
      centerLeadingLongPressTarget: this.buildLongPressTarget(facts, mode, menuSlot),
      centerPrimaryLongPressTarget: this.buildLongPressTarget(facts, mode, refreshSlot),
      trailingOuterLongPressTarget: this.buildLongPressTarget(facts, mode, tabsSlot),
      toolbarInteractionProfileActive: facts.toolbarInteractionProfileActive === true,
      leadingOuterVisualEnabled: leadingOuterTarget.enabled,
      centerLeadingVisualEnabled: centerLeadingTarget.enabled,
      centerPrimaryVisualEnabled: centerPrimaryTarget.enabled,
      trailingOuterVisualEnabled: trailingOuterTarget.enabled,
      addressInput: facts.addressInput,
      placeholder: facts.placeholder,
      searchEnginePresentation,
      centerContent: this.buildCenterContent(facts, mode),
      leadingOuterIconId: leadingSlot?.airaIconId ?? 'browser.toolbar.back',
      centerLeadingIconId: menuSlot?.airaIconId ?? 'browser.toolbar.menu',
      centerPrimaryIconId: refreshSlot?.airaIconId ?? 'browser.toolbar.refresh',
      trailingOuterIconId: tabsSlot?.airaIconId ?? 'browser.toolbar.tabs',
      leadingHeaderActions: facts.leadingHeaderActions,
      trailingHeaderActions: facts.trailingHeaderActions
    });
  }

  isOuterGestureSource(source: BrowserBottomChromeGestureSource): boolean {
    return source === 'leading-outer' || source === 'trailing-outer';
  }

  resolveReturnHomeGesture(
    input: BrowserBottomChromeReturnHomeGestureInput
  ): BrowserBottomChromeReturnHomeGestureState {
    const outerEligible = input.eligible && this.isOuterGestureSource(input.source) && Number.isFinite(input.offsetY);
    const distance = outerEligible ? Math.max(0, -input.offsetY) : 0;
    const progress = clampUnit(
      (distance - BROWSER_BOTTOM_CHROME_RETURN_HOME_ACTIVE_OFFSET_Y) /
      (BROWSER_BOTTOM_CHROME_RETURN_HOME_RELEASE_OFFSET_Y - BROWSER_BOTTOM_CHROME_RETURN_HOME_ACTIVE_OFFSET_Y)
    );
    const active = outerEligible && distance >= BROWSER_BOTTOM_CHROME_RETURN_HOME_ACTIVE_OFFSET_Y;
    const armed = outerEligible && distance >= BROWSER_BOTTOM_CHROME_RETURN_HOME_RELEASE_OFFSET_Y;
    return {
      active,
      armed,
      progress,
      promptText: active ? (input.promptText ?? BROWSER_BOTTOM_CHROME_DEFAULT_GESTURE_PROMPT) : ''
    };
  }

  private resolveMode(facts: BrowserBottomChromePresentationFacts): BrowserBottomChromePresentationMode {
    if (facts.returnHomeDrag) {
      return 'return-home-drag';
    }
    if (facts.addressFocused) {
      return 'center-active-editing';
    }
    if (facts.currentDetent === 'middle') {
      return 'center-active-tools';
    }
    if ((facts.scene === 'home' || facts.scene === 'web') && facts.scrollPresentation === 'compact') {
      return 'scroll-compact';
    }
    return 'resting-three-block';
  }

  private buildFrame(
    facts: BrowserBottomChromePresentationFacts,
    mode: BrowserBottomChromePresentationMode
  ): BrowserBottomChromeFrame {
    const floatingHeaderHorizontalPadding = sanitizeSize(
      facts.floatingHeaderHorizontalPadding ?? BROWSER_BOTTOM_ADDRESS_PANEL_PHONE_HEADER_HORIZONTAL_PADDING
    );
    const restingChromeOuterSize = sanitizeSize(
      facts.restingChromeOuterSize ?? BROWSER_BOTTOM_CHROME_PHONE_OUTER_SIZE
    );
    const restingChromeOuterGap = sanitizeSize(
      facts.restingChromeOuterGap ?? BROWSER_BOTTOM_CHROME_PHONE_OUTER_GAP
    );
    const availableWidth = Math.max(1,
      facts.panelWidth - floatingHeaderHorizontalPadding * 2);
    const restingCenterWidth = Math.max(1,
      availableWidth - restingChromeOuterSize * 2 - restingChromeOuterGap * 2);
    const requestedWideCenterWidth = sanitizeSize(facts.expandedChromeWidth ?? availableWidth);
    const wideCenterWidth = Math.max(1, Math.min(
      availableWidth,
      requestedWideCenterWidth > 0 ? requestedWideCenterWidth : availableWidth
    ));
    const compactCenterWidth = Math.max(1, Math.min(BROWSER_BOTTOM_CHROME_COMPACT_WIDTH, availableWidth));
    if (mode === 'scroll-compact') {
      return this.buildFrameValues({
        centerWidth: compactCenterWidth,
        centerHeight: BROWSER_BOTTOM_CHROME_COMPACT_HEIGHT,
        centerRadius: BROWSER_BOTTOM_CHROME_COMPACT_RADIUS,
        centerTranslateY: BROWSER_BOTTOM_CHROME_COMPACT_TRANSLATE_Y,
        centerDisplayScale: BROWSER_BOTTOM_CHROME_COMPACT_DISPLAY_SCALE,
        centerHorizontalPadding: BROWSER_BOTTOM_CHROME_COMPACT_HORIZONTAL_PADDING,
        centerVerticalPadding: BROWSER_BOTTOM_CHROME_COMPACT_VERTICAL_PADDING,
        displayOpacity: 1
      });
    }
    if (mode === 'center-active-editing') {
      const webEditing = facts.scene === 'web';
      const homeEditing = facts.scene === 'home';
      const homeClearVisible = facts.scene === 'home' && facts.addressInput.trim().length > 0;
      return this.buildFrameValues({
        centerWidth: wideCenterWidth,
        centerLeadingWidth: webEditing || homeEditing ? BROWSER_BOTTOM_CHROME_ACCESSORY_SIZE : 0,
        centerPrimaryWidth: webEditing || homeClearVisible ? BROWSER_BOTTOM_CHROME_ACCESSORY_SIZE : 0,
        centerAccessoryGap: webEditing ? BROWSER_BOTTOM_CHROME_ACCESSORY_GAP : 0,
        centerSecondaryWidth: webEditing ? BROWSER_BOTTOM_CHROME_ACCESSORY_SIZE : 0,
        copyOpacity: webEditing ? 1 : 0,
        clearOpacity: homeClearVisible ? 1 : 0,
        editOpacity: webEditing ? 1 : 0,
        editingOpacity: 1
      });
    }
    if (mode === 'center-active-tools') {
      return this.buildRestingOrToolsFrame(
        facts,
        restingCenterWidth,
        1,
        0,
        restingChromeOuterSize,
        restingChromeOuterGap
      );
    }
    if (mode === 'return-home-drag') {
      const progress = clampUnit(facts.returnHomeProgress);
      return this.buildRestingOrToolsFrame(
        facts,
        restingCenterWidth,
        1 - progress,
        progress,
        restingChromeOuterSize,
        restingChromeOuterGap
      );
    }
    return this.buildRestingOrToolsFrame(
      facts,
      restingCenterWidth,
      1,
      0,
      restingChromeOuterSize,
      restingChromeOuterGap
    );
  }

  private buildRestingOrToolsFrame(
    facts: BrowserBottomChromePresentationFacts,
    centerWidth: number,
    contentOpacity: number,
    promptOpacity: number,
    restingChromeOuterSize: number,
    restingChromeOuterGap: number,
    outerVisible: boolean = true
  ): BrowserBottomChromeFrame {
    const menuVisible = this.isToolbarSlotVisible(
      facts,
      findToolbarSlotAction(facts.toolbarSlotActions, 'menu'),
      facts.panelExpansionEnabled
    );
    const refreshVisible = this.isToolbarSlotVisible(
      facts,
      findToolbarSlotAction(facts.toolbarSlotActions, 'refresh'),
      findHeaderAction(facts.trailingHeaderActions, 0) !== undefined
    );
    return this.buildFrameValues({
      leadingOuterWidth: outerVisible ? restingChromeOuterSize : 0,
      leadingGap: outerVisible ? restingChromeOuterGap : 0,
      centerWidth,
      trailingGap: outerVisible ? restingChromeOuterGap : 0,
      trailingOuterWidth: outerVisible ? restingChromeOuterSize : 0,
      outerOpacity: outerVisible ? 1 : 0,
      centerLeadingWidth: menuVisible ? BROWSER_BOTTOM_CHROME_ACCESSORY_SIZE : 0,
      centerPrimaryWidth: refreshVisible ? BROWSER_BOTTOM_CHROME_ACCESSORY_SIZE : 0,
      menuOpacity: menuVisible ? contentOpacity : 0,
      refreshOpacity: refreshVisible ? contentOpacity : 0,
      displayOpacity: contentOpacity,
      returnHomeOpacity: promptOpacity
    });
  }

  private buildFrameValues(overrides: BrowserBottomChromeFrameOverrides): BrowserBottomChromeFrame {
    const centerWidth = overrides.centerWidth ?? 1;
    const centerHeight = overrides.centerHeight ?? BROWSER_BOTTOM_CHROME_MATERIAL_HEIGHT;
    const horizontalPadding = overrides.centerHorizontalPadding ?? BROWSER_BOTTOM_CHROME_RESTING_HORIZONTAL_PADDING;
    const verticalPadding = overrides.centerVerticalPadding ?? 0;
    const leadingWidth = overrides.centerLeadingWidth ?? 0;
    const primaryWidth = overrides.centerPrimaryWidth ?? 0;
    const accessoryGap = overrides.centerAccessoryGap ?? 0;
    const secondaryWidth = overrides.centerSecondaryWidth ?? 0;
    const viewportWidth = Math.max(1,
      centerWidth - horizontalPadding * 2 - leadingWidth - primaryWidth - accessoryGap - secondaryWidth);
    const viewportHeight = Math.max(1, centerHeight - verticalPadding * 2);
    return new BrowserBottomChromeFrame({
      leadingOuterWidth: overrides.leadingOuterWidth ?? 0,
      leadingGap: overrides.leadingGap ?? 0,
      centerWidth,
      trailingGap: overrides.trailingGap ?? 0,
      trailingOuterWidth: overrides.trailingOuterWidth ?? 0,
      centerHeight,
      centerRadius: overrides.centerRadius ?? BROWSER_BOTTOM_CHROME_MATERIAL_HEIGHT / 2,
      centerTranslateY: overrides.centerTranslateY ?? 0,
      centerDisplayScale: overrides.centerDisplayScale ?? 1,
      centerHorizontalPadding: horizontalPadding,
      centerVerticalPadding: verticalPadding,
      centerLeadingWidth: leadingWidth,
      centerPrimaryWidth: primaryWidth,
      centerAccessoryGap: accessoryGap,
      centerSecondaryWidth: secondaryWidth,
      centerViewportWidth: overrides.centerViewportWidth ?? viewportWidth,
      centerViewportHeight: overrides.centerViewportHeight ?? viewportHeight,
      outerOpacity: overrides.outerOpacity ?? 0,
      menuOpacity: overrides.menuOpacity ?? 0,
      refreshOpacity: overrides.refreshOpacity ?? 0,
      copyOpacity: overrides.copyOpacity ?? 0,
      clearOpacity: overrides.clearOpacity ?? 0,
      editOpacity: overrides.editOpacity ?? 0,
      displayOpacity: overrides.displayOpacity ?? 0,
      editingOpacity: overrides.editingOpacity ?? 0,
      returnHomeOpacity: overrides.returnHomeOpacity ?? 0
    });
  }

  private buildCenterContent(
    facts: BrowserBottomChromePresentationFacts,
    mode: BrowserBottomChromePresentationMode
  ): BrowserBottomChromeCenterContentPresentation {
    const displayText = this.resolveDisplayText(facts);
    const displayUsesSecondaryTone = facts.addressDisplayText.trim().length === 0 &&
      facts.addressInput.trim().length === 0;
    const activeLayer: BrowserBottomChromeCenterContentLayer = mode === 'center-active-editing' ? 'editing' :
      (mode === 'return-home-drag' ? 'return-home' : 'display');
    return new BrowserBottomChromeCenterContentPresentation(
      activeLayer,
      this.resolveDisplayKey(displayText, displayUsesSecondaryTone),
      displayText,
      displayUsesSecondaryTone,
      facts.gesturePromptText ?? BROWSER_BOTTOM_CHROME_DEFAULT_GESTURE_PROMPT,
      facts.webProtectionFeedback ?? EMPTY_BROWSER_WEB_PROTECTION_FEEDBACK_PRESENTATION
    );
  }

  private resolveDisplayText(facts: BrowserBottomChromePresentationFacts): string {
    if (facts.addressDisplayText.trim().length > 0) {
      return facts.addressDisplayText;
    }
    if (facts.addressInput.trim().length > 0) {
      return facts.addressInput;
    }
    return facts.placeholder;
  }

  private resolveDisplayKey(displayText: string, displayUsesSecondaryTone: boolean): string {
    return displayText + (displayUsesSecondaryTone ? '|secondary' : '|primary');
  }

  private buildLeadingOuterTarget(
    facts: BrowserBottomChromePresentationFacts,
    mode: BrowserBottomChromePresentationMode,
    slot: BrowserToolbarSlotActionState | undefined,
    action?: BrowserBottomAddressPanelHeaderAction
  ): BrowserBottomChromeTapTarget {
    if (mode !== 'resting-three-block' && mode !== 'center-active-tools') {
      return EMPTY_TAP_TARGET;
    }
    const configuredTarget = this.buildConfiguredSlotTarget(facts, slot);
    if (configuredTarget !== undefined) {
      return configuredTarget;
    }
    if (action === undefined) {
      return EMPTY_TAP_TARGET;
    }
    return buildHeaderActionTarget(action);
  }

  private buildTrailingOuterTarget(
    facts: BrowserBottomChromePresentationFacts,
    mode: BrowserBottomChromePresentationMode,
    slot: BrowserToolbarSlotActionState | undefined,
    action?: BrowserBottomAddressPanelHeaderAction
  ): BrowserBottomChromeTapTarget {
    if (mode !== 'resting-three-block' && mode !== 'center-active-tools') {
      return EMPTY_TAP_TARGET;
    }
    const configuredTarget = this.buildConfiguredSlotTarget(facts, slot);
    if (configuredTarget !== undefined) {
      return configuredTarget;
    }
    if (action === undefined) {
      return EMPTY_TAP_TARGET;
    }
    return buildHeaderActionTarget(action);
  }

  private buildCenterBodyTarget(
    facts: BrowserBottomChromePresentationFacts,
    mode: BrowserBottomChromePresentationMode
  ): BrowserBottomChromeTapTarget {
    if (mode === 'scroll-compact') {
      return new BrowserBottomChromeTapTarget(
        new BrowserBottomChromeTapIntent('dispatch-header-action', 'bottomChromeRestore'),
        true,
        '恢复工具栏'
      );
    }
    if (mode === 'return-home-drag' || mode === 'center-active-editing') {
      return EMPTY_TAP_TARGET;
    }
    if (facts.addressEditable) {
      return new BrowserBottomChromeTapTarget(
        new BrowserBottomChromeTapIntent('activate-editing'),
        true,
        facts.scene === 'home' ? '搜索或输入网址' : '编辑当前网址'
      );
    }
    if (facts.panelExpansionEnabled) {
      return new BrowserBottomChromeTapTarget(
        new BrowserBottomChromeTapIntent('dispatch-header-action', 'bottomChromeMenu'),
        true,
        mode === 'center-active-tools' ? '收起工具栏' : '展开工具栏'
      );
    }
    return EMPTY_TAP_TARGET;
  }

  private buildCenterLeadingTarget(
    facts: BrowserBottomChromePresentationFacts,
    mode: BrowserBottomChromePresentationMode,
    slot: BrowserToolbarSlotActionState | undefined
  ): BrowserBottomChromeTapTarget {
    if (mode === 'center-active-editing' && (facts.scene === 'home' || facts.scene === 'web')) {
      return new BrowserBottomChromeTapTarget(
        new BrowserBottomChromeTapIntent('open-search-engine-menu'),
        (facts.searchEnginePresentation?.searchEngines.length ?? 0) > 0,
        '选择搜索引擎'
      );
    }
    if (mode === 'resting-three-block' || mode === 'center-active-tools') {
      const configuredTarget = this.buildConfiguredSlotTarget(facts, slot);
      if (configuredTarget !== undefined) {
        return configuredTarget;
      }
    }
    if ((mode === 'resting-three-block' || mode === 'center-active-tools') && facts.panelExpansionEnabled) {
      return new BrowserBottomChromeTapTarget(
        new BrowserBottomChromeTapIntent('dispatch-header-action', 'bottomChromeMenu'),
        true,
        mode === 'center-active-tools' ? '收起工具栏' : '展开工具栏'
      );
    }
    return EMPTY_TAP_TARGET;
  }

  private buildCenterPrimaryTarget(
    facts: BrowserBottomChromePresentationFacts,
    mode: BrowserBottomChromePresentationMode,
    slot: BrowserToolbarSlotActionState | undefined,
    refreshAction?: BrowserBottomAddressPanelHeaderAction
  ): BrowserBottomChromeTapTarget {
    if (mode === 'center-active-editing' && facts.scene === 'web') {
      return new BrowserBottomChromeTapTarget(
        new BrowserBottomChromeTapIntent('dispatch-header-action', 'copyLink'),
        true,
        '复制当前网址'
      );
    }
    if (mode === 'center-active-editing' && facts.scene === 'home' && facts.addressInput.trim().length > 0) {
      return new BrowserBottomChromeTapTarget(
        new BrowserBottomChromeTapIntent('clear-input'),
        true,
        '清除输入'
      );
    }
    if (mode === 'resting-three-block' || mode === 'center-active-tools') {
      const configuredTarget = this.buildConfiguredSlotTarget(facts, slot);
      if (configuredTarget !== undefined) {
        return configuredTarget;
      }
    }
    if ((mode === 'resting-three-block' || mode === 'center-active-tools') && refreshAction !== undefined) {
      return buildHeaderActionTarget(refreshAction);
    }
    return EMPTY_TAP_TARGET;
  }

  private buildCenterSecondaryTarget(
    facts: BrowserBottomChromePresentationFacts,
    mode: BrowserBottomChromePresentationMode
  ): BrowserBottomChromeTapTarget {
    if (mode === 'center-active-editing' && facts.scene === 'web') {
      return new BrowserBottomChromeTapTarget(
        new BrowserBottomChromeTapIntent('restore-current-address'),
        true,
        '编辑当前网址'
      );
    }
    return EMPTY_TAP_TARGET;
  }

  private buildConfiguredSlotTarget(
    facts: BrowserBottomChromePresentationFacts,
    slot: BrowserToolbarSlotActionState | undefined
  ): BrowserBottomChromeTapTarget | undefined {
    if (slot === undefined) {
      return undefined;
    }
    if (facts.customizationPreview === true) {
      return new BrowserBottomChromeTapTarget(
        new BrowserBottomChromeTapIntent('dispatch-header-action', 'toolbarCustomization', slot.id),
        true,
        `设置${slot.slotTitle}`
      );
    }
    if (slot.tap.action.isNone) {
      return EMPTY_TAP_TARGET;
    }
    return this.buildInteractionTarget(facts, slot.id, slot.tap);
  }

  private buildLongPressTarget(
    facts: BrowserBottomChromePresentationFacts,
    mode: BrowserBottomChromePresentationMode,
    slot: BrowserToolbarSlotActionState | undefined
  ): BrowserBottomChromeTapTarget {
    if (facts.customizationPreview === true || slot === undefined || slot.longPress.action.isNone ||
      (mode !== 'resting-three-block' && mode !== 'center-active-tools')) {
      return EMPTY_TAP_TARGET;
    }
    return this.buildInteractionTarget(facts, slot.id, slot.longPress);
  }

  private buildInteractionTarget(
    facts: BrowserBottomChromePresentationFacts,
    slotId: BrowserToolbarSlotId,
    interaction: BrowserToolbarSlotInteractionState
  ): BrowserBottomChromeTapTarget {
    const action = interaction.action;
    if (action.dispatchKind === 'panel') {
      const enablement = facts.toolbarActionEnablement?.[action.id];
      const enabled = enablement?.enabled ?? true;
      const disabledMessage = enabled ? '' :
        (enablement?.disabledMessage ?? `当前页面无法${action.title}。`);
      return new BrowserBottomChromeTapTarget(
        new BrowserBottomChromeTapIntent('dispatch-panel-action', action.id, slotId, disabledMessage),
        enabled,
        action.title
      );
    }
    if (action.dispatchKind === 'none') {
      return EMPTY_TAP_TARGET;
    }
    if (action.id === 'bottomChromeMenu') {
      const enabled = facts.panelExpansionEnabled;
      return new BrowserBottomChromeTapTarget(
        new BrowserBottomChromeTapIntent(
          'dispatch-header-action',
          action.id,
          slotId,
          enabled ? '' : '当前页面无法展开工具栏。'
        ),
        enabled,
        action.title
      );
    }
    if (action.id === 'newTab') {
      return new BrowserBottomChromeTapTarget(
        new BrowserBottomChromeTapIntent('dispatch-header-action', action.id, slotId),
        true,
        action.title
      );
    }
    const headerAction = findHeaderActionById(
      facts.leadingHeaderActions.concat(facts.trailingHeaderActions),
      action.id
    );
    if (headerAction !== undefined) {
      return buildHeaderActionTarget(
        headerAction,
        slotId,
        facts.scene === 'web'
      );
    }
    return new BrowserBottomChromeTapTarget(
      new BrowserBottomChromeTapIntent(
        'dispatch-header-action',
        action.id,
        slotId,
        `当前页面无法${action.title}。`
      ),
      false,
      action.title
    );
  }

  private isToolbarSlotVisible(
    facts: BrowserBottomChromePresentationFacts,
    slot: BrowserToolbarSlotActionState | undefined,
    fallbackVisible: boolean
  ): boolean {
    if (facts.customizationPreview === true) {
      return true;
    }
    if (slot?.tap.action.isNone === true) {
      return false;
    }
    return slot !== undefined || fallbackVisible;
  }
}

function buildHeaderActionTarget(
  action: BrowserBottomAddressPanelHeaderAction,
  slotId: string = '',
  allowReliableWebHistory: boolean = false
): BrowserBottomChromeTapTarget {
  const reliableWebHistoryAction = allowReliableWebHistory &&
    action.triggerPolicy === 'reliableTrigger' &&
    (action.id === 'webBack' || action.id === 'webForward');
  const enabled = reliableWebHistoryAction || action.enabled;
  const actionDisabledMessage = action.disabledMessage ?? '';
  const disabledMessage = actionDisabledMessage.trim().length > 0 ?
    actionDisabledMessage : `当前页面无法${action.title}。`;
  return new BrowserBottomChromeTapTarget(
    new BrowserBottomChromeTapIntent(
      'dispatch-header-action',
      action.id,
      slotId,
      enabled ? '' : disabledMessage
    ),
    enabled,
    action.title,
    action.triggerPolicy === 'reliableTrigger'
  );
}

function findHeaderActionById(
  actions: BrowserBottomAddressPanelHeaderAction[],
  actionId: string
): BrowserBottomAddressPanelHeaderAction | undefined {
  return actions.find((action: BrowserBottomAddressPanelHeaderAction): boolean => action.id === actionId);
}

function findHeaderAction(
  actions: BrowserBottomAddressPanelHeaderAction[],
  index: number
): BrowserBottomAddressPanelHeaderAction | undefined {
  return index >= 0 && index < actions.length ? actions[index] : undefined;
}

function findToolbarSlotAction(
  slots: BrowserToolbarSlotActionState[] | undefined,
  slotId: BrowserToolbarSlotId
): BrowserToolbarSlotActionState | undefined {
  return slots?.find((slot: BrowserToolbarSlotActionState) => slot.id === slotId);
}

function isWideMode(mode: BrowserBottomChromePresentationMode): boolean {
  return mode === 'center-active-tools' || mode === 'center-active-editing';
}

function sanitizeFinite(value: number): number {
  return Number.isFinite(value) ? value : 0;
}

function sanitizeSize(value: number): number {
  return Math.max(0, sanitizeFinite(value));
}

function clampUnit(value: number): number {
  return Math.max(0, Math.min(1, sanitizeFinite(value)));
}

function approximatelyEqual(left: number, right: number): boolean {
  return Math.abs(left - right) <= BROWSER_BOTTOM_CHROME_FRAME_EPSILON;
}

const DEFAULT_PRESENTATION_VIEW_MODEL: BrowserBottomChromePresentationViewModel =
  new BrowserBottomChromePresentationViewModel();

export const DEFAULT_BROWSER_BOTTOM_CHROME_PRESENTATION: BrowserBottomChromePresentation =
  DEFAULT_PRESENTATION_VIEW_MODEL.buildPresentation({
    scene: 'inactive',
    addressFocused: false,
    addressEditable: false,
    currentDetent: 'low',
    scrollPresentation: 'resting',
    returnHomeDrag: false,
    returnHomeProgress: 0,
    panelWidth: 360,
    panelExpansionEnabled: false,
    addressInput: '',
    addressDisplayText: '',
    placeholder: '',
    searchEnginePresentation: EMPTY_SEARCH_ENGINE_CHROME_PRESENTATION,
    leadingHeaderActions: [],
    trailingHeaderActions: []
  });
