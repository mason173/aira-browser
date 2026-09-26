import { BrowserToolbarLayoutSettings } from '../../common/models/BrowserModels';
import {
  cloneBrowserToolbarLayoutSettings,
  normalizeSplitToolbarSettings
} from './BrowserSplitToolbarCustomizationPolicy';
import {
  DEFAULT_BROWSER_TOOLBAR_LAYOUT_SETTINGS
} from '../../data/preferences/PreferencesRepository';
import {
  BrowserBottomAddressPanelActionId
} from './BrowserBottomAddressPanelViewModel';
import { BrowserBottomPanelActionCatalog } from './BrowserBottomPanelActionCatalog';
import { AiraRenderableIconId } from '../resources/GeneratedAiraIconCatalog';

export interface BrowserToolbarCustomizationState {
  slotActions: BrowserToolbarSlotActionState[];
  canReset: boolean;
}

export type BrowserToolbarSlotId = 'leading' | 'menu' | 'refresh' | 'tabs';
export type BrowserToolbarInteractionKind = 'tap' | 'longPress' | 'swipeUp';
export type BrowserToolbarCoreActionId =
  'webBack' | 'webForward' | 'bottomChromeMenu' | 'webReload' | 'openTabs' | 'newTab';
export type BrowserToolbarInteractionActionId = BrowserBottomAddressPanelActionId |
  BrowserToolbarCoreActionId | 'none';
export type BrowserToolbarSlotDispatchKind = 'header' | 'panel' | 'none';

export interface BrowserToolbarInteractionActionState {
  id: BrowserToolbarInteractionActionId;
  title: string;
  subtitle: string;
  airaIconId: AiraRenderableIconId;
  dispatchKind: BrowserToolbarSlotDispatchKind;
  isNone: boolean;
}

export interface BrowserToolbarSlotInteractionState {
  kind: BrowserToolbarInteractionKind;
  title: string;
  action: BrowserToolbarInteractionActionState;
  allowsNone: boolean;
}

export interface BrowserToolbarSlotActionState {
  id: BrowserToolbarSlotId;
  slotTitle: string;
  defaultActionTitle: string;
  actionId: string;
  customActionId: string;
  title: string;
  airaIconId: AiraRenderableIconId;
  dispatchKind: BrowserToolbarSlotDispatchKind;
  isDefault: boolean;
  isProfileDefault: boolean;
  tap: BrowserToolbarSlotInteractionState;
  longPress: BrowserToolbarSlotInteractionState;
  swipeUp?: BrowserToolbarSlotInteractionState;
}

export type BrowserToolbarCenterCapsuleSwipeUpActionId = 'tools' | 'tabs';

export interface BrowserToolbarCenterCapsuleSwipeUpOptionState {
  actionId: BrowserToolbarCenterCapsuleSwipeUpActionId;
  title: string;
  isSelected: boolean;
}

const TOOLBAR_CORE_ACTION_IDS: BrowserToolbarCoreActionId[] = [
  'webBack',
  'webForward',
  'bottomChromeMenu',
  'webReload',
  'openTabs',
  'newTab'
];

/**
 * The middle bar's swipe-up opens one of two surfaces. Unlike the four configurable buttons it has
 * no slot and no action catalog of its own, so its two choices are declared here and nowhere else.
 */
const BROWSER_TOOLBAR_CENTER_CAPSULE_SWIPE_UP_OPTIONS: BrowserToolbarCenterCapsuleSwipeUpOptionState[] = [
  { actionId: 'tools', title: '打开工具面板', isSelected: false },
  { actionId: 'tabs', title: '打开标签管理页', isSelected: false }
];

export class BrowserToolbarCustomizationViewModel {
  /**
   * The one state the customization screens read.
   *
   * `primaryActions` used to be projected here and read by nobody, and the settings were normalised
   * once per projection — which for a slot list meant three normalisations per build, each copying the
   * whole toolbar layout. Nothing else consumes it, so it is gone and the settings are normalised once.
   */
  buildState(settings: BrowserToolbarLayoutSettings): BrowserToolbarCustomizationState {
    const normalizedSettings = this.normalizeSettings(settings);
    return {
      slotActions: this.buildSlotActionsForNormalized(normalizedSettings),
      canReset: !this.areListsEqual(
        normalizedSettings.primaryActionIds,
        DEFAULT_BROWSER_TOOLBAR_LAYOUT_SETTINGS.primaryActionIds
      ) || !this.areListsEqual(
        normalizedSettings.secondaryActionIds,
        DEFAULT_BROWSER_TOOLBAR_LAYOUT_SETTINGS.secondaryActionIds
      ) || this.hasNonDefaultSlotAction(normalizedSettings)
    };
  }

  buildSlotActions(settings: BrowserToolbarLayoutSettings): BrowserToolbarSlotActionState[] {
    return this.buildSlotActionsForNormalized(this.normalizeSettings(settings));
  }

  private buildSlotActionsForNormalized(
    normalizedSettings: BrowserToolbarLayoutSettings
  ): BrowserToolbarSlotActionState[] {
    return [
      this.buildSlotActionState('leading', normalizedSettings),
      this.buildSlotActionState('menu', normalizedSettings),
      this.buildSlotActionState('refresh', normalizedSettings),
      this.buildSlotActionState('tabs', normalizedSettings)
    ];
  }

  buildInteractionActionCatalog(
    settings: BrowserToolbarLayoutSettings,
    slotId: BrowserToolbarSlotId,
    kind: BrowserToolbarInteractionKind
  ): BrowserToolbarInteractionActionState[] {
    const normalizedSettings = this.normalizeSettings(settings);
    const result: BrowserToolbarInteractionActionState[] = [];
    if (this.interactionAllowsNone(slotId, kind)) {
      result.push(this.buildInteractionActionState('none'));
    }
    TOOLBAR_CORE_ACTION_IDS.forEach((actionId: BrowserToolbarCoreActionId) => {
      result.push(this.buildInteractionActionState(actionId));
    });
    normalizedSettings.primaryActionIds.forEach((actionId: string) => {
      result.push(this.buildInteractionActionState(actionId as BrowserBottomAddressPanelActionId));
    });
    return result;
  }

  replaceSlotAction(
    settings: BrowserToolbarLayoutSettings,
    slotId: BrowserToolbarSlotId,
    actionId: BrowserBottomAddressPanelActionId
  ): BrowserToolbarLayoutSettings {
    return this.replaceSlotInteraction(settings, slotId, 'tap', actionId);
  }

  replaceSlotInteraction(
    settings: BrowserToolbarLayoutSettings,
    slotId: BrowserToolbarSlotId,
    kind: BrowserToolbarInteractionKind,
    actionId: BrowserToolbarInteractionActionId
  ): BrowserToolbarLayoutSettings {
    const normalizedSettings = this.normalizeSettings(settings);
    const normalizedActionId = this.normalizeSelectedInteractionActionId(slotId, kind, actionId);
    return this.normalizeSettings(this.buildSettingsWithSlotInteraction(
      normalizedSettings,
      slotId,
      kind,
      normalizedActionId
    ));
  }

  resetSlotAction(
    settings: BrowserToolbarLayoutSettings,
    slotId: BrowserToolbarSlotId
  ): BrowserToolbarLayoutSettings {
    let nextSettings = this.normalizeSettings(settings);
    nextSettings = this.buildSettingsWithSlotInteraction(nextSettings, slotId, 'tap', '');
    nextSettings = this.buildSettingsWithSlotInteraction(nextSettings, slotId, 'longPress', 'none');
    if (this.slotSupportsSwipeUp(slotId)) {
      nextSettings = this.buildSettingsWithSlotInteraction(nextSettings, slotId, 'swipeUp', 'home');
    }
    return this.normalizeSettings(nextSettings);
  }

  resetAllSlotActions(settings: BrowserToolbarLayoutSettings): BrowserToolbarLayoutSettings {
    const normalizedSettings = this.normalizeSettings(settings);
    const reset = cloneBrowserToolbarLayoutSettings(normalizedSettings);
    reset.leadingSlotActionId = '';
    reset.menuSlotActionId = '';
    reset.refreshSlotActionId = '';
    reset.tabsSlotActionId = '';
    reset.leadingSlotLongPressActionId = 'none';
    reset.menuSlotLongPressActionId = 'none';
    reset.refreshSlotLongPressActionId = 'none';
    reset.tabsSlotLongPressActionId = 'none';
    reset.leadingSlotSwipeUpActionId = 'home';
    reset.tabsSlotSwipeUpActionId = 'home';
    reset.centerCapsuleSwipeUpActionId = 'tools';
    return this.normalizeSettings(reset);
  }

  findSlotAction(
    state: BrowserToolbarCustomizationState,
    slotId: BrowserToolbarSlotId
  ): BrowserToolbarSlotActionState | undefined {
    return state.slotActions.find((slot: BrowserToolbarSlotActionState) => slot.id === slotId);
  }

  findSlotInteraction(
    state: BrowserToolbarCustomizationState,
    slotId: BrowserToolbarSlotId,
    kind: BrowserToolbarInteractionKind
  ): BrowserToolbarSlotInteractionState | undefined {
    const slot = this.findSlotAction(state, slotId);
    if (kind === 'tap') {
      return slot?.tap;
    }
    if (kind === 'longPress') {
      return slot?.longPress;
    }
    return slot?.swipeUp;
  }

  movePrimaryToIndex(
    settings: BrowserToolbarLayoutSettings,
    actionId: BrowserBottomAddressPanelActionId,
    targetIndex: number
  ): BrowserToolbarLayoutSettings {
    const normalizedSettings = this.normalizeSettings(settings);
    const nextPrimaryActionIds = this.moveActionToIndex(
      this.toActionIds(normalizedSettings.primaryActionIds),
      actionId,
      targetIndex
    );
    return this.normalizeSettings(this.copySettings(normalizedSettings, nextPrimaryActionIds, Date.now()));
  }

  movePrimary(
    settings: BrowserToolbarLayoutSettings,
    actionId: BrowserBottomAddressPanelActionId,
    direction: 'up' | 'down'
  ): BrowserToolbarLayoutSettings {
    const normalizedSettings = this.normalizeSettings(settings);
    return this.normalizeSettings(this.copySettings(
      normalizedSettings,
      this.moveAction(this.toActionIds(normalizedSettings.primaryActionIds), actionId, direction),
      Date.now()
    ));
  }

  buildDefaultSettings(): BrowserToolbarLayoutSettings {
    const settings = cloneBrowserToolbarLayoutSettings(DEFAULT_BROWSER_TOOLBAR_LAYOUT_SETTINGS);
    settings.primaryActionIds = DEFAULT_BROWSER_TOOLBAR_LAYOUT_SETTINGS.primaryActionIds.slice();
    settings.secondaryActionIds = [];
    settings.updatedAt = Date.now();
    return settings;
  }

  /** Action ids a toolbar button may be set to, not including `none`. */
  listSelectableInteractionActionIds(): BrowserToolbarInteractionActionId[] {
    const ids: BrowserToolbarInteractionActionId[] = [];
    TOOLBAR_CORE_ACTION_IDS.forEach((actionId: BrowserToolbarCoreActionId): void => {
      ids.push(actionId);
    });
    this.getCatalogActionIds().forEach((actionId: BrowserBottomAddressPanelActionId): void => {
      ids.push(actionId);
    });
    return ids;
  }

  presentInteractionAction(actionId: BrowserToolbarInteractionActionId): BrowserToolbarInteractionActionState {
    return this.buildInteractionActionState(actionId);
  }

  isSelectableInteractionAction(actionId: string): boolean {
    return this.isInteractionActionId(actionId);
  }

  normalizeSettings(settings: BrowserToolbarLayoutSettings): BrowserToolbarLayoutSettings {
    const normalizedActionIds = this.toActionIds(
      this.toActionIds(settings.primaryActionIds).concat(this.toActionIds(settings.secondaryActionIds))
    );
    const missingActionIds = this.getCatalogActionIds().filter((actionId: BrowserBottomAddressPanelActionId) => {
      return !normalizedActionIds.includes(actionId);
    });
    const normalized = cloneBrowserToolbarLayoutSettings(settings);
    normalized.primaryActionIds = normalizedActionIds.concat(missingActionIds);
    normalized.secondaryActionIds = [];
    normalized.leadingSlotActionId = this.normalizeTapActionId('leading', settings.leadingSlotActionId);
    normalized.menuSlotActionId = this.normalizeTapActionId('menu', settings.menuSlotActionId);
    normalized.refreshSlotActionId = this.normalizeTapActionId('refresh', settings.refreshSlotActionId);
    normalized.tabsSlotActionId = this.normalizeTapActionId('tabs', settings.tabsSlotActionId);
    normalized.leadingSlotLongPressActionId = this.normalizeGestureActionId(settings.leadingSlotLongPressActionId, 'none');
    normalized.menuSlotLongPressActionId = this.normalizeGestureActionId(settings.menuSlotLongPressActionId, 'none');
    normalized.refreshSlotLongPressActionId = this.normalizeGestureActionId(settings.refreshSlotLongPressActionId, 'none');
    normalized.tabsSlotLongPressActionId = this.normalizeGestureActionId(settings.tabsSlotLongPressActionId, 'none');
    normalized.leadingSlotSwipeUpActionId = this.normalizeGestureActionId(settings.leadingSlotSwipeUpActionId, 'home');
    normalized.tabsSlotSwipeUpActionId = this.normalizeGestureActionId(settings.tabsSlotSwipeUpActionId, 'home');
    normalized.centerCapsuleSwipeUpActionId = this.normalizeCenterCapsuleSwipeUpActionId(
      settings.centerCapsuleSwipeUpActionId);
    normalized.updatedAt = Number(settings.updatedAt) > 0 ? Math.floor(Number(settings.updatedAt)) : 0;
    return normalizeSplitToolbarSettings(normalized, (actionId: string): boolean => {
      return this.isInteractionActionId(actionId);
    });
  }

  getCatalogActionIds(): BrowserBottomAddressPanelActionId[] {
    return BrowserBottomPanelActionCatalog.customizableActionIds();
  }

  private buildSlotActionState(
    slotId: BrowserToolbarSlotId,
    settings: BrowserToolbarLayoutSettings
  ): BrowserToolbarSlotActionState {
    const tapStoredActionId = this.resolveStoredInteractionActionId(settings, slotId, 'tap');
    const tapActionId = tapStoredActionId.length > 0 ? tapStoredActionId : this.resolveDefaultSlotActionId(slotId);
    const tapAction = this.buildInteractionActionState(tapActionId as BrowserToolbarInteractionActionId);
    const longPressAction = this.buildInteractionActionState(
      this.resolveStoredInteractionActionId(settings, slotId, 'longPress') as BrowserToolbarInteractionActionId
    );
    const swipeUpAction = this.slotSupportsSwipeUp(slotId) ? this.buildInteractionActionState(
      this.resolveStoredInteractionActionId(settings, slotId, 'swipeUp') as BrowserToolbarInteractionActionId
    ) : undefined;
    const tap = this.buildSlotInteractionState(slotId, 'tap', tapAction);
    const longPress = this.buildSlotInteractionState(slotId, 'longPress', longPressAction);
    const swipeUp = swipeUpAction === undefined ? undefined :
      this.buildSlotInteractionState(slotId, 'swipeUp', swipeUpAction);
    const tapIsDefault = tapAction.id === this.resolveDefaultSlotActionId(slotId);
    const gesturesAreDefault = longPressAction.id === 'none' &&
      (swipeUp === undefined || swipeUp.action.id === 'home');
    return {
      id: slotId,
      slotTitle: this.resolveSlotTitle(slotId),
      defaultActionTitle: this.resolveCoreActionTitle(this.resolveDefaultSlotActionId(slotId)),
      actionId: tapAction.id,
      customActionId: tapStoredActionId,
      title: tapAction.title,
      airaIconId: tapAction.airaIconId,
      dispatchKind: tapAction.dispatchKind,
      isDefault: tapIsDefault,
      isProfileDefault: tapIsDefault && gesturesAreDefault,
      tap,
      longPress,
      swipeUp
    };
  }

  private buildSlotInteractionState(
    slotId: BrowserToolbarSlotId,
    kind: BrowserToolbarInteractionKind,
    action: BrowserToolbarInteractionActionState
  ): BrowserToolbarSlotInteractionState {
    return {
      kind,
      title: this.resolveInteractionTitle(kind),
      action,
      allowsNone: this.interactionAllowsNone(slotId, kind)
    };
  }

  private buildInteractionActionState(
    actionId: BrowserToolbarInteractionActionId
  ): BrowserToolbarInteractionActionState {
    if (actionId === 'none') {
      return {
        id: actionId,
        title: '无动作',
        subtitle: '不响应此操作',
        airaIconId: 'browser.toolbar.emptySlot',
        dispatchKind: 'none',
        isNone: true
      };
    }
    if (this.isCoreActionId(actionId)) {
      const coreActionId = actionId as BrowserToolbarCoreActionId;
      return {
        id: actionId,
        title: this.resolveCoreActionTitle(coreActionId),
        subtitle: this.resolveCoreActionSubtitle(coreActionId),
        airaIconId: this.resolveCoreActionIconId(coreActionId),
        dispatchKind: 'header',
        isNone: false
      };
    }
    const panelActionId = actionId as BrowserBottomAddressPanelActionId;
    return {
      id: actionId,
      title: BrowserBottomPanelActionCatalog.title(panelActionId),
      subtitle: BrowserBottomPanelActionCatalog.subtitle(panelActionId),
      airaIconId: BrowserBottomPanelActionCatalog.iconId(panelActionId),
      dispatchKind: 'panel',
      isNone: false
    };
  }

  private buildSettingsWithSlotInteraction(
    settings: BrowserToolbarLayoutSettings,
    slotId: BrowserToolbarSlotId,
    kind: BrowserToolbarInteractionKind,
    actionId: string
  ): BrowserToolbarLayoutSettings {
    const result = this.copySettings(settings, settings.primaryActionIds, settings.updatedAt);
    if (kind === 'tap') {
      if (slotId === 'leading') result.leadingSlotActionId = actionId;
      if (slotId === 'menu') result.menuSlotActionId = actionId;
      if (slotId === 'refresh') result.refreshSlotActionId = actionId;
      if (slotId === 'tabs') result.tabsSlotActionId = actionId;
    } else if (kind === 'longPress') {
      if (slotId === 'leading') result.leadingSlotLongPressActionId = actionId;
      if (slotId === 'menu') result.menuSlotLongPressActionId = actionId;
      if (slotId === 'refresh') result.refreshSlotLongPressActionId = actionId;
      if (slotId === 'tabs') result.tabsSlotLongPressActionId = actionId;
    } else {
      if (slotId === 'leading') result.leadingSlotSwipeUpActionId = actionId;
      if (slotId === 'tabs') result.tabsSlotSwipeUpActionId = actionId;
    }
    return result;
  }

  private copySettings(
    settings: BrowserToolbarLayoutSettings,
    primaryActionIds: string[],
    updatedAt: number
  ): BrowserToolbarLayoutSettings {
    const copied = cloneBrowserToolbarLayoutSettings(settings);
    copied.primaryActionIds = primaryActionIds.slice();
    copied.secondaryActionIds = settings.secondaryActionIds.slice();
    copied.updatedAt = updatedAt;
    return copied;
  }

  private resolveStoredInteractionActionId(
    settings: BrowserToolbarLayoutSettings,
    slotId: BrowserToolbarSlotId,
    kind: BrowserToolbarInteractionKind
  ): string {
    if (kind === 'tap') {
      if (slotId === 'leading') return this.normalizeTapActionId(slotId, settings.leadingSlotActionId);
      if (slotId === 'menu') return this.normalizeTapActionId(slotId, settings.menuSlotActionId);
      if (slotId === 'refresh') return this.normalizeTapActionId(slotId, settings.refreshSlotActionId);
      return this.normalizeTapActionId(slotId, settings.tabsSlotActionId);
    }
    if (kind === 'longPress') {
      if (slotId === 'leading') return this.normalizeGestureActionId(settings.leadingSlotLongPressActionId, 'none');
      if (slotId === 'menu') return this.normalizeGestureActionId(settings.menuSlotLongPressActionId, 'none');
      if (slotId === 'refresh') return this.normalizeGestureActionId(settings.refreshSlotLongPressActionId, 'none');
      return this.normalizeGestureActionId(settings.tabsSlotLongPressActionId, 'none');
    }
    if (slotId === 'leading') return this.normalizeGestureActionId(settings.leadingSlotSwipeUpActionId, 'home');
    return this.normalizeGestureActionId(settings.tabsSlotSwipeUpActionId, 'home');
  }

  private normalizeSelectedInteractionActionId(
    slotId: BrowserToolbarSlotId,
    kind: BrowserToolbarInteractionKind,
    actionId: BrowserToolbarInteractionActionId
  ): string {
    const normalizedActionId = String(actionId ?? '').trim();
    if (normalizedActionId === 'none') {
      return this.interactionAllowsNone(slotId, kind) ? 'none' : this.resolveDefaultInteractionActionId(slotId, kind);
    }
    return this.isInteractionActionId(normalizedActionId) ? normalizedActionId :
      this.resolveDefaultInteractionActionId(slotId, kind);
  }

  private normalizeTapActionId(slotId: BrowserToolbarSlotId, actionId: string | undefined): string {
    const normalizedActionId = String(actionId ?? '').trim();
    if (normalizedActionId.length <= 0) {
      return '';
    }
    if (normalizedActionId === 'none') {
      return this.interactionAllowsNone(slotId, 'tap') ? normalizedActionId : '';
    }
    return this.isInteractionActionId(normalizedActionId) ? normalizedActionId : '';
  }

  private normalizeGestureActionId(actionId: string | undefined, fallbackActionId: string): string {
    const normalizedActionId = String(actionId ?? '').trim();
    if (normalizedActionId === 'none' || this.isInteractionActionId(normalizedActionId)) {
      return normalizedActionId;
    }
    return fallbackActionId;
  }

  private isInteractionActionId(actionId: string): boolean {
    return TOOLBAR_CORE_ACTION_IDS.includes(actionId as BrowserToolbarCoreActionId) ||
      this.getCatalogActionIds().includes(actionId as BrowserBottomAddressPanelActionId);
  }

  private isCoreActionId(actionId: BrowserToolbarInteractionActionId): boolean {
    return TOOLBAR_CORE_ACTION_IDS.includes(actionId as BrowserToolbarCoreActionId);
  }

  private hasNonDefaultSlotAction(settings: BrowserToolbarLayoutSettings): boolean {
    return this.buildSlotActions(settings).some((slot: BrowserToolbarSlotActionState): boolean => {
      return !slot.isProfileDefault;
    });
  }

  private interactionAllowsNone(slotId: BrowserToolbarSlotId, kind: BrowserToolbarInteractionKind): boolean {
    if (kind === 'tap') {
      return slotId === 'menu' || slotId === 'refresh';
    }
    return true;
  }

  private slotSupportsSwipeUp(slotId: BrowserToolbarSlotId): boolean {
    return slotId === 'leading' || slotId === 'tabs';
  }

  /**
   * The middle bar's two swipe-up choices with the current one marked, in presentation order.
   */
  buildCenterCapsuleSwipeUpOptions(
    settings: BrowserToolbarLayoutSettings
  ): BrowserToolbarCenterCapsuleSwipeUpOptionState[] {
    const selected = this.normalizeCenterCapsuleSwipeUpActionId(settings.centerCapsuleSwipeUpActionId);
    return BROWSER_TOOLBAR_CENTER_CAPSULE_SWIPE_UP_OPTIONS.map((
      option: BrowserToolbarCenterCapsuleSwipeUpOptionState
    ): BrowserToolbarCenterCapsuleSwipeUpOptionState => {
      return {
        actionId: option.actionId,
        title: option.title,
        isSelected: option.actionId === selected
      };
    });
  }

  /**
   * The same settings with the middle bar's swipe-up behaviour replaced.
   *
   * The middle of the bottom bar is not one of the four configurable buttons, so it has no slot to go
   * through; this is the one place that writes its choice.
   */
  withCenterCapsuleSwipeUpActionId(
    settings: BrowserToolbarLayoutSettings,
    actionId: string
  ): BrowserToolbarLayoutSettings {
    const next = this.normalizeSettings(settings);
    next.centerCapsuleSwipeUpActionId = this.normalizeCenterCapsuleSwipeUpActionId(actionId);
    return next;
  }

  private normalizeCenterCapsuleSwipeUpActionId(
    actionId: string | undefined
  ): BrowserToolbarCenterCapsuleSwipeUpActionId {
    return actionId === 'tabs' ? 'tabs' : 'tools';
  }

  private resolveDefaultInteractionActionId(
    slotId: BrowserToolbarSlotId,
    kind: BrowserToolbarInteractionKind
  ): string {
    if (kind === 'tap') {
      return this.resolveDefaultSlotActionId(slotId);
    }
    return kind === 'longPress' ? 'none' : 'home';
  }

  private resolveSlotTitle(slotId: BrowserToolbarSlotId): string {
    switch (slotId) {
      case 'leading':
        return '最左侧按钮';
      case 'menu':
        return '输入框左侧按钮';
      case 'refresh':
        return '输入框右侧按钮';
      case 'tabs':
        return '最右侧按钮';
    }
  }

  private resolveInteractionTitle(kind: BrowserToolbarInteractionKind): string {
    if (kind === 'tap') return '单击';
    if (kind === 'longPress') return '长按';
    return '上滑';
  }

  private resolveDefaultSlotActionId(slotId: BrowserToolbarSlotId): BrowserToolbarCoreActionId {
    switch (slotId) {
      case 'leading':
        return 'webBack';
      case 'menu':
        return 'bottomChromeMenu';
      case 'refresh':
        return 'webReload';
      case 'tabs':
        return 'openTabs';
    }
  }

  private resolveCoreActionTitle(actionId: BrowserToolbarCoreActionId): string {
    if (actionId === 'webBack') return '返回';
    if (actionId === 'webForward') return '前进';
    if (actionId === 'bottomChromeMenu') return '菜单';
    if (actionId === 'webReload') return '刷新';
    if (actionId === 'openTabs') return '标签页';
    return '新建标签页';
  }

  private resolveCoreActionSubtitle(actionId: BrowserToolbarCoreActionId): string {
    if (actionId === 'webBack') return '返回上一页';
    if (actionId === 'webForward') return '前往下一页';
    if (actionId === 'bottomChromeMenu') return '展开或收起工具栏';
    if (actionId === 'webReload') return '重新载入当前页面';
    if (actionId === 'openTabs') return '查看打开的标签页';
    return '打开新的标签页';
  }

  private resolveCoreActionIconId(actionId: BrowserToolbarCoreActionId): AiraRenderableIconId {
    if (actionId === 'webBack') return 'browser.toolbar.back';
    if (actionId === 'webForward') return 'browser.toolbar.forward';
    if (actionId === 'bottomChromeMenu') return 'browser.toolbar.menu';
    if (actionId === 'webReload') return 'browser.toolbar.refresh';
    if (actionId === 'openTabs') return 'browser.toolbar.tabs';
    return 'browser.tabs.overviewAdd';
  }

  private normalizeActionIds(actionIds: string[], maxCount: number): BrowserBottomAddressPanelActionId[] {
    const normalized: BrowserBottomAddressPanelActionId[] = [];
    if (!Array.isArray(actionIds)) {
      return normalized;
    }
    actionIds.forEach((rawActionId: string) => {
      const actionId = String(rawActionId ?? '').trim() as BrowserBottomAddressPanelActionId;
      if (!this.getCatalogActionIds().includes(actionId) || normalized.includes(actionId)) {
        return;
      }
      if (normalized.length >= maxCount) {
        return;
      }
      normalized.push(actionId);
    });
    return normalized;
  }

  private toActionIds(actionIds: string[]): BrowserBottomAddressPanelActionId[] {
    return this.normalizeActionIds(actionIds, this.getCatalogActionIds().length);
  }

  private moveAction(
    actionIds: BrowserBottomAddressPanelActionId[],
    actionId: BrowserBottomAddressPanelActionId,
    direction: 'up' | 'down'
  ): BrowserBottomAddressPanelActionId[] {
    const nextActionIds = actionIds.slice();
    const index = nextActionIds.indexOf(actionId);
    if (index < 0) {
      return nextActionIds;
    }
    const targetIndex = direction === 'up' ? index - 1 : index + 1;
    if (targetIndex < 0 || targetIndex >= nextActionIds.length) {
      return nextActionIds;
    }
    const current = nextActionIds[index];
    nextActionIds[index] = nextActionIds[targetIndex];
    nextActionIds[targetIndex] = current;
    return nextActionIds;
  }

  private moveActionToIndex(
    actionIds: BrowserBottomAddressPanelActionId[],
    actionId: BrowserBottomAddressPanelActionId,
    targetIndex: number
  ): BrowserBottomAddressPanelActionId[] {
    const nextActionIds = actionIds.slice();
    const currentIndex = nextActionIds.indexOf(actionId);
    if (currentIndex < 0) {
      return nextActionIds;
    }
    const normalizedTargetIndex = Math.max(0, Math.min(nextActionIds.length - 1, Math.floor(targetIndex)));
    if (currentIndex === normalizedTargetIndex) {
      return nextActionIds;
    }
    nextActionIds.splice(currentIndex, 1);
    nextActionIds.splice(normalizedTargetIndex, 0, actionId);
    return nextActionIds;
  }

  private areListsEqual(first: string[], second: string[]): boolean {
    if (first.length !== second.length) {
      return false;
    }
    for (let index = 0; index < first.length; index++) {
      if (first[index] !== second[index]) {
        return false;
      }
    }
    return true;
  }
}
