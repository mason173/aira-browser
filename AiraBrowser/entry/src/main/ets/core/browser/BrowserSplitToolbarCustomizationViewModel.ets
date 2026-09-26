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

export interface BrowserSplitToolbarButtonPresentation {
  slotId: BrowserSplitToolbarSlotId;
  actionId: string;
  title: string;
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
    const sceneTitle = slot.scene === 'home' ? '主页' : '网页';
    return {
      slotId,
      scene: slot.scene,
      sheetTitle: `${sceneTitle} · ${tapAction.title}`,
      tapLocked: slot.tapLocked,
      isProfileDefault: this.isSlotDefault(settings, slot, tapActionId, longPressActionId),
      tap: {
        kind: 'tap',
        title: '单击',
        action: tapAction,
        allowsNone: false
      },
      longPress: {
        kind: 'longPress',
        title: '长按',
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
