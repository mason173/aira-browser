import { BrowserToolbarLayoutSettings } from '../../common/models/BrowserModels';
import {
  DEFAULT_BROWSER_TOOLBAR_LAYOUT_SETTINGS
} from '../../data/preferences/PreferencesRepository';
import {
  BrowserBottomAddressPanelActionId
} from './BrowserBottomAddressPanelViewModel';
import { BrowserBottomPanelActionCatalog } from './BrowserBottomPanelActionCatalog';
import { AiraRenderableIconId } from '../resources/GeneratedAiraIconCatalog';

export interface BrowserToolbarCustomizationActionState {
  id: BrowserBottomAddressPanelActionId;
  title: string;
  subtitle: string;
  airaIconId: AiraRenderableIconId;
  isPrimary: boolean;
  canAddToPrimary: boolean;
  canRemoveFromPrimary: boolean;
  canMoveUp: boolean;
  canMoveDown: boolean;
}

export interface BrowserToolbarCustomizationState {
  primaryActions: BrowserToolbarCustomizationActionState[];
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

const TOOLBAR_CORE_ACTION_IDS: BrowserToolbarCoreActionId[] = [
  'webBack',
  'webForward',
  'bottomChromeMenu',
  'webReload',
  'openTabs',
  'newTab'
];

export class BrowserToolbarCustomizationViewModel {
  buildState(settings: BrowserToolbarLayoutSettings): BrowserToolbarCustomizationState {
    const normalizedSettings = this.normalizeSettings(settings);
    return {
      primaryActions: normalizedSettings.primaryActionIds.map((
        actionId: string,
        index: number
      ): BrowserToolbarCustomizationActionState => {
        return this.buildActionState(actionId as BrowserBottomAddressPanelActionId, true, index,
          normalizedSettings.primaryActionIds.length);
      }),
      slotActions: this.buildSlotActions(normalizedSettings),
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
    const normalizedSettings = this.normalizeSettings(settings);
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
    return this.normalizeSettings({
      primaryActionIds: normalizedSettings.primaryActionIds,
      secondaryActionIds: normalizedSettings.secondaryActionIds,
      leadingSlotActionId: '',
      menuSlotActionId: '',
      refreshSlotActionId: '',
      tabsSlotActionId: '',
      leadingSlotLongPressActionId: 'none',
      menuSlotLongPressActionId: 'none',
      refreshSlotLongPressActionId: 'none',
      tabsSlotLongPressActionId: 'none',
      leadingSlotSwipeUpActionId: 'home',
      tabsSlotSwipeUpActionId: 'home',
      updatedAt: normalizedSettings.updatedAt
    });
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
    return {
      primaryActionIds: DEFAULT_BROWSER_TOOLBAR_LAYOUT_SETTINGS.primaryActionIds.slice(),
      secondaryActionIds: [],
      leadingSlotActionId: '',
      menuSlotActionId: '',
      refreshSlotActionId: '',
      tabsSlotActionId: '',
      leadingSlotLongPressActionId: 'none',
      menuSlotLongPressActionId: 'none',
      refreshSlotLongPressActionId: 'none',
      tabsSlotLongPressActionId: 'none',
      leadingSlotSwipeUpActionId: 'home',
      tabsSlotSwipeUpActionId: 'home',
      updatedAt: Date.now()
    };
  }

  normalizeSettings(settings: BrowserToolbarLayoutSettings): BrowserToolbarLayoutSettings {
    const normalizedActionIds = this.toActionIds(
      this.toActionIds(settings.primaryActionIds).concat(this.toActionIds(settings.secondaryActionIds))
    );
    const missingActionIds = this.getCatalogActionIds().filter((actionId: BrowserBottomAddressPanelActionId) => {
      return !normalizedActionIds.includes(actionId);
    });
    return {
      primaryActionIds: normalizedActionIds.concat(missingActionIds),
      secondaryActionIds: [],
      leadingSlotActionId: this.normalizeTapActionId('leading', settings.leadingSlotActionId),
      menuSlotActionId: this.normalizeTapActionId('menu', settings.menuSlotActionId),
      refreshSlotActionId: this.normalizeTapActionId('refresh', settings.refreshSlotActionId),
      tabsSlotActionId: this.normalizeTapActionId('tabs', settings.tabsSlotActionId),
      leadingSlotLongPressActionId: this.normalizeGestureActionId(settings.leadingSlotLongPressActionId, 'none'),
      menuSlotLongPressActionId: this.normalizeGestureActionId(settings.menuSlotLongPressActionId, 'none'),
      refreshSlotLongPressActionId: this.normalizeGestureActionId(settings.refreshSlotLongPressActionId, 'none'),
      tabsSlotLongPressActionId: this.normalizeGestureActionId(settings.tabsSlotLongPressActionId, 'none'),
      leadingSlotSwipeUpActionId: this.normalizeGestureActionId(settings.leadingSlotSwipeUpActionId, 'home'),
      tabsSlotSwipeUpActionId: this.normalizeGestureActionId(settings.tabsSlotSwipeUpActionId, 'home'),
      updatedAt: Number(settings.updatedAt) > 0 ? Math.floor(Number(settings.updatedAt)) : 0
    };
  }

  getCatalogActionIds(): BrowserBottomAddressPanelActionId[] {
    return BrowserBottomPanelActionCatalog.customizableActionIds();
  }

  private buildActionState(
    actionId: BrowserBottomAddressPanelActionId,
    isPrimary: boolean,
    index: number,
    count: number
  ): BrowserToolbarCustomizationActionState {
    return {
      id: actionId,
      title: BrowserBottomPanelActionCatalog.title(actionId),
      subtitle: BrowserBottomPanelActionCatalog.subtitle(actionId),
      airaIconId: BrowserBottomPanelActionCatalog.iconId(actionId),
      isPrimary,
      canAddToPrimary: !isPrimary,
      canRemoveFromPrimary: isPrimary,
      canMoveUp: index > 0,
      canMoveDown: index < count - 1
    };
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
    return {
      primaryActionIds: primaryActionIds.slice(),
      secondaryActionIds: settings.secondaryActionIds.slice(),
      leadingSlotActionId: settings.leadingSlotActionId,
      menuSlotActionId: settings.menuSlotActionId,
      refreshSlotActionId: settings.refreshSlotActionId,
      tabsSlotActionId: settings.tabsSlotActionId,
      leadingSlotLongPressActionId: settings.leadingSlotLongPressActionId,
      menuSlotLongPressActionId: settings.menuSlotLongPressActionId,
      refreshSlotLongPressActionId: settings.refreshSlotLongPressActionId,
      tabsSlotLongPressActionId: settings.tabsSlotLongPressActionId,
      leadingSlotSwipeUpActionId: settings.leadingSlotSwipeUpActionId,
      tabsSlotSwipeUpActionId: settings.tabsSlotSwipeUpActionId,
      updatedAt
    };
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
