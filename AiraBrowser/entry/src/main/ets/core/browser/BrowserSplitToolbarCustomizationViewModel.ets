import { BrowserToolbarLayoutSettings } from '../../common/models/BrowserModels';
import { AiraRenderableIconId } from '../resources/GeneratedAiraIconCatalog';
import {
  BrowserSplitToolbarInteractionKind,
  BrowserSplitToolbarScene,
  BrowserSplitToolbarSlotDefinition,
  BrowserSplitToolbarSlotId,
  findSplitToolbarSlot,
  hasSplitToolbarCustomizations,
  replaceSplitToolbarInteraction,
  resetAllSplitToolbarSlots,
  resetSplitToolbarSlot,
  resolveSplitToolbarLongPressActionId,
  resolveSplitToolbarTapActionId,
  splitToolbarActionEnabled,
  splitToolbarSlotsForScene
} from './BrowserSplitToolbarCustomizationPolicy';
import {
  BrowserToolbarCustomizationViewModel,
  BrowserToolbarInteractionActionId,
  BrowserToolbarInteractionActionState,
  BrowserToolbarSlotInteractionState
} from './BrowserToolbarCustomizationViewModel';
import { bottomPanelInteractionTitle } from './BrowserBottomPanelText';
import { resolveAppResourceText } from '../resources/AppResourceText';

export interface BrowserSplitToolbarButtonPresentation {
  slotId: BrowserSplitToolbarSlotId;
  actionId: string;
  title: ResourceStr;
  iconId: AiraRenderableIconId;
  usesTabBadge: boolean;
  enabled: boolean;
}

export interface BrowserSplitToolbarSlotDetail {
  slotId: BrowserSplitToolbarSlotId;
  scene: BrowserSplitToolbarScene;
  sheetTitle: string;
  tapLocked: boolean;
  isProfileDefault: boolean;
  tap: BrowserToolbarSlotInteractionState;
  longPress: BrowserToolbarSlotInteractionState;
}

export interface BrowserSplitToolbarDispatchAction {
  id: string;
  dispatchKind: 'header' | 'panel' | 'none';
}

/**
 * The `dock` style paints one bottom row: back, forward, menu, tabs, home. The slots are the split
 * web slots, so the dock reuses the split web bar's icons, tab badge, dispatch, and customization
 * sheets; only the painted order differs.
 */
const DOCK_TOOLBAR_SLOT_ORDER: BrowserSplitToolbarSlotId[] =
  ['webBack', 'webForward', 'webMenu', 'webTabs', 'webHome'];

/**
 * Presentation of the split bottom bar.
 *
 * The policy owns which taps are fixed and which actions may repeat. This view model only turns
 * that into titles, icons and the sheet rows the settings page already knows how to draw.
 */
export class BrowserSplitToolbarCustomizationViewModel {
  private actions: BrowserToolbarCustomizationViewModel = new BrowserToolbarCustomizationViewModel();

  buildPresentations(
    settings: BrowserToolbarLayoutSettings,
    scene: BrowserSplitToolbarScene,
    canGoBack: boolean,
    canGoForward: boolean
  ): BrowserSplitToolbarButtonPresentation[] {
    return splitToolbarSlotsForScene(scene).map((slot: BrowserSplitToolbarSlotDefinition):
      BrowserSplitToolbarButtonPresentation => {
      const actionId = resolveSplitToolbarTapActionId(settings, slot.id, (id: string): boolean => {
        return this.isKnown(id);
      });
      const action = this.actions.presentInteractionAction(actionId as BrowserToolbarInteractionActionId);
      return {
        slotId: slot.id,
        actionId,
        title: action.title,
        iconId: this.resolveIcon(slot, actionId, action.airaIconId),
        usesTabBadge: slot.usesTabBadge,
        enabled: splitToolbarActionEnabled(actionId, canGoBack, canGoForward)
      };
    });
  }

  /**
   * Presentation of the `dock` style's bottom row. The dock shares the split web bar's slots and
   * settings, so a tap or long press resolves exactly like the split web bar; only the painted
   * order is the dock's.
   */
  buildDockPresentations(
    settings: BrowserToolbarLayoutSettings,
    canGoBack: boolean,
    canGoForward: boolean
  ): BrowserSplitToolbarButtonPresentation[] {
    const bySlot: Map<string, BrowserSplitToolbarButtonPresentation> = new Map();
    this.buildPresentations(settings, 'web', canGoBack, canGoForward).forEach(
      (presentation: BrowserSplitToolbarButtonPresentation): void => {
        bySlot.set(presentation.slotId, presentation);
      });
    const result: BrowserSplitToolbarButtonPresentation[] = [];
    DOCK_TOOLBAR_SLOT_ORDER.forEach((slotId: BrowserSplitToolbarSlotId): void => {
      const presentation = bySlot.get(slotId);
      if (presentation !== undefined) {
        result.push(presentation);
      }
    });
    return result;
  }

  buildSlotDetail(
    settings: BrowserToolbarLayoutSettings,
    slotId: BrowserSplitToolbarSlotId
  ): BrowserSplitToolbarSlotDetail | undefined {
    const slot = findSplitToolbarSlot(slotId);
    if (slot === undefined) {
      return undefined;
    }
    const tapActionId = resolveSplitToolbarTapActionId(settings, slotId, (id: string): boolean => this.isKnown(id));
    const tapAction = this.actions.presentInteractionAction(tapActionId as BrowserToolbarInteractionActionId);
    const longPressActionId = resolveSplitToolbarLongPressActionId(settings, slotId, (id: string): boolean => {
      return this.isKnown(id);
    });
    const longPressAction = this.actions.presentInteractionAction(
      longPressActionId as BrowserToolbarInteractionActionId
    );
    const sceneTitle = slot.scene === 'home' ?
      $r('app.string.bottom_panel_scene_home') : $r('app.string.bottom_panel_scene_web');
    return {
      slotId,
      scene: slot.scene,
      sheetTitle: resolveAppResourceText($r('app.string.bottom_panel_split_sheet_title',
        resolveAppResourceText(sceneTitle), resolveAppResourceText(tapAction.title))),
      tapLocked: slot.tapLocked,
      isProfileDefault: this.isSlotDefault(settings, slot, tapActionId, longPressActionId),
      tap: {
        kind: 'tap',
        title: bottomPanelInteractionTitle('tap'),
        action: tapAction,
        allowsNone: false
      },
      longPress: {
        kind: 'longPress',
        title: bottomPanelInteractionTitle('longPress'),
        action: longPressAction,
        allowsNone: true
      }
    };
  }

  buildActionCatalog(
    settings: BrowserToolbarLayoutSettings,
    slotId: BrowserSplitToolbarSlotId,
    kind: BrowserSplitToolbarInteractionKind
  ): BrowserToolbarInteractionActionState[] {
    const slot = findSplitToolbarSlot(slotId);
    if (slot === undefined || (kind === 'tap' && slot.tapLocked)) {
      return [];
    }
    const currentTap = resolveSplitToolbarTapActionId(settings, slotId, (id: string): boolean => this.isKnown(id));
    const taken = this.otherTapActionIds(settings, slot);
    const result: BrowserToolbarInteractionActionState[] = [];
    if (kind === 'longPress') {
      result.push(this.actions.presentInteractionAction('none'));
    }
    this.actions.listSelectableInteractionActionIds().forEach((actionId: BrowserToolbarInteractionActionId): void => {
      if (kind === 'tap' && taken.includes(actionId) && actionId !== currentTap) {
        return;
      }
      result.push(this.actions.presentInteractionAction(actionId));
    });
    return result;
  }

  replaceInteraction(
    settings: BrowserToolbarLayoutSettings,
    slotId: BrowserSplitToolbarSlotId,
    kind: BrowserSplitToolbarInteractionKind,
    actionId: BrowserToolbarInteractionActionId
  ): BrowserToolbarLayoutSettings {
    return replaceSplitToolbarInteraction(settings, slotId, kind, actionId, (id: string): boolean => this.isKnown(id));
  }

  resetSlot(
    settings: BrowserToolbarLayoutSettings,
    slotId: BrowserSplitToolbarSlotId
  ): BrowserToolbarLayoutSettings {
    return resetSplitToolbarSlot(settings, slotId, (id: string): boolean => this.isKnown(id));
  }

  resetAll(settings: BrowserToolbarLayoutSettings): BrowserToolbarLayoutSettings {
    return resetAllSplitToolbarSlots(settings);
  }

  hasCustomizations(settings: BrowserToolbarLayoutSettings): boolean {
    return hasSplitToolbarCustomizations(settings);
  }

  resolveActionId(
    settings: BrowserToolbarLayoutSettings,
    slotId: BrowserSplitToolbarSlotId,
    kind: BrowserSplitToolbarInteractionKind
  ): string {
    if (kind === 'longPress') {
      return resolveSplitToolbarLongPressActionId(settings, slotId, (id: string): boolean => this.isKnown(id));
    }
    return resolveSplitToolbarTapActionId(settings, slotId, (id: string): boolean => this.isKnown(id));
  }

  resolveDispatchAction(
    settings: BrowserToolbarLayoutSettings,
    slotId: string,
    kind: BrowserSplitToolbarInteractionKind
  ): BrowserSplitToolbarDispatchAction | undefined {
    if (findSplitToolbarSlot(slotId) === undefined) {
      return undefined;
    }
    const actionId = this.resolveActionId(settings, slotId as BrowserSplitToolbarSlotId, kind);
    const action = this.actions.presentInteractionAction(actionId as BrowserToolbarInteractionActionId);
    if (action.isNone) {
      return undefined;
    }
    return {
      id: action.id,
      dispatchKind: action.dispatchKind
    };
  }

  private otherTapActionIds(
    settings: BrowserToolbarLayoutSettings,
    slot: BrowserSplitToolbarSlotDefinition
  ): string[] {
    const taken: string[] = [];
    splitToolbarSlotsForScene(slot.scene).forEach((candidate: BrowserSplitToolbarSlotDefinition): void => {
      if (candidate.id === slot.id) {
        return;
      }
      taken.push(resolveSplitToolbarTapActionId(settings, candidate.id, (id: string): boolean => this.isKnown(id)));
    });
    return taken;
  }

  private isSlotDefault(
    settings: BrowserToolbarLayoutSettings,
    slot: BrowserSplitToolbarSlotDefinition,
    tapActionId: string,
    longPressActionId: string
  ): boolean {
    const storedTap = slot.id === 'homeLeading' ? (settings.splitHomeLeadingTapActionId ?? '') :
      slot.id === 'homeSecondary' ? (settings.splitHomeSecondaryTapActionId ?? '') :
        slot.id === 'webHome' ? (settings.splitWebHomeTapActionId ?? '') : '';
    return (slot.tapLocked || storedTap.trim().length === 0) &&
      tapActionId === slot.defaultTapActionId &&
      longPressActionId === 'none';
  }

  private resolveIcon(
    slot: BrowserSplitToolbarSlotDefinition,
    actionId: string,
    catalogIconId: AiraRenderableIconId
  ): AiraRenderableIconId {
    if (slot.id === 'webHome' && actionId === 'home') {
      return 'browser.toolbar.home';
    }
    return catalogIconId;
  }

  private isKnown(actionId: string): boolean {
    return this.actions.isSelectableInteractionAction(actionId);
  }
}
