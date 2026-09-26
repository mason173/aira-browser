import { BrowserToolbarLayoutSettings } from '../../common/models/BrowserModels';

/** Which split bottom bar a slot belongs to. */
export type BrowserSplitToolbarScene = 'home' | 'web';

/**
 * Slots of the split bottom bar.
 *
 * Home is bookmarks, history, tabs, menu. Web is back, forward, home, tabs, menu.
 * Tabs, menu, back and forward keep a fixed tap. The other three taps can be replaced.
 */
export type BrowserSplitToolbarSlotId =
  'homeLeading' |
  'homeSecondary' |
  'homeTabs' |
  'homeMenu' |
  'webBack' |
  'webForward' |
  'webHome' |
  'webTabs' |
  'webMenu';

export type BrowserSplitToolbarInteractionKind = 'tap' | 'longPress';

export interface BrowserSplitToolbarSlotDefinition {
  id: BrowserSplitToolbarSlotId;
  scene: BrowserSplitToolbarScene;
  defaultTapActionId: string;
  tapLocked: boolean;
  usesTabBadge: boolean;
}

const SPLIT_TOOLBAR_SLOTS: BrowserSplitToolbarSlotDefinition[] = [
  { id: 'homeLeading', scene: 'home', defaultTapActionId: 'openBookmarks', tapLocked: false, usesTabBadge: false },
  { id: 'homeSecondary', scene: 'home', defaultTapActionId: 'history', tapLocked: false, usesTabBadge: false },
  { id: 'homeTabs', scene: 'home', defaultTapActionId: 'openTabs', tapLocked: true, usesTabBadge: true },
  { id: 'homeMenu', scene: 'home', defaultTapActionId: 'bottomChromeMenu', tapLocked: true, usesTabBadge: false },
  { id: 'webBack', scene: 'web', defaultTapActionId: 'webBack', tapLocked: true, usesTabBadge: false },
  { id: 'webForward', scene: 'web', defaultTapActionId: 'webForward', tapLocked: true, usesTabBadge: false },
  { id: 'webHome', scene: 'web', defaultTapActionId: 'home', tapLocked: false, usesTabBadge: false },
  { id: 'webTabs', scene: 'web', defaultTapActionId: 'openTabs', tapLocked: true, usesTabBadge: true },
  { id: 'webMenu', scene: 'web', defaultTapActionId: 'bottomChromeMenu', tapLocked: true, usesTabBadge: false }
];

export function splitToolbarSlotDefinitions(): BrowserSplitToolbarSlotDefinition[] {
  return SPLIT_TOOLBAR_SLOTS.slice();
}

export function splitToolbarSlotsForScene(scene: BrowserSplitToolbarScene): BrowserSplitToolbarSlotDefinition[] {
  return SPLIT_TOOLBAR_SLOTS.filter((slot: BrowserSplitToolbarSlotDefinition): boolean => slot.scene === scene);
}

export function findSplitToolbarSlot(slotId: string): BrowserSplitToolbarSlotDefinition | undefined {
  return SPLIT_TOOLBAR_SLOTS.find((slot: BrowserSplitToolbarSlotDefinition): boolean => slot.id === slotId);
}

export function isSplitToolbarSlotId(slotId: string): boolean {
  return findSplitToolbarSlot(slotId) !== undefined;
}

export function splitToolbarActionEnabled(
  actionId: string,
  canGoBack: boolean,
  canGoForward: boolean
): boolean {
  if (actionId === 'webBack') {
    return canGoBack;
  }
  if (actionId === 'webForward') {
    return canGoForward;
  }
  return true;
}

/**
 * A full copy of toolbar layout settings.
 *
 * Split-slot writes go through this so a floating-slot edit cannot drop the split bar, and a split
 * edit cannot drop the floating slots. Every field of {@link BrowserToolbarLayoutSettings} has to
 * be named here; the toolbar contract checks that.
 */
export function cloneBrowserToolbarLayoutSettings(
  settings: BrowserToolbarLayoutSettings
): BrowserToolbarLayoutSettings {
  return {
    primaryActionIds: settings.primaryActionIds.slice(),
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
    centerCapsuleSwipeUpActionId: settings.centerCapsuleSwipeUpActionId,
    tabsSlotSwipeUpActionId: settings.tabsSlotSwipeUpActionId,
    splitHomeLeadingTapActionId: settings.splitHomeLeadingTapActionId,
    splitHomeLeadingLongPressActionId: settings.splitHomeLeadingLongPressActionId,
    splitHomeSecondaryTapActionId: settings.splitHomeSecondaryTapActionId,
    splitHomeSecondaryLongPressActionId: settings.splitHomeSecondaryLongPressActionId,
    splitHomeTabsLongPressActionId: settings.splitHomeTabsLongPressActionId,
    splitHomeMenuLongPressActionId: settings.splitHomeMenuLongPressActionId,
    splitWebHomeTapActionId: settings.splitWebHomeTapActionId,
    splitWebHomeLongPressActionId: settings.splitWebHomeLongPressActionId,
    splitWebBackLongPressActionId: settings.splitWebBackLongPressActionId,
    splitWebForwardLongPressActionId: settings.splitWebForwardLongPressActionId,
    splitWebTabsLongPressActionId: settings.splitWebTabsLongPressActionId,
    splitWebMenuLongPressActionId: settings.splitWebMenuLongPressActionId,
    updatedAt: settings.updatedAt
  };
}

export function resolveSplitToolbarTapActionId(
  settings: BrowserToolbarLayoutSettings,
  slotId: BrowserSplitToolbarSlotId,
  isKnownAction: (actionId: string) => boolean
): string {
  const resolved = resolveSceneTapActionIds(settings, sceneOf(slotId), isKnownAction);
  const index = splitToolbarSlotsForScene(sceneOf(slotId))
    .findIndex((slot: BrowserSplitToolbarSlotDefinition): boolean => slot.id === slotId);
  return index >= 0 ? resolved[index] : '';
}

export function resolveSplitToolbarLongPressActionId(
  settings: BrowserToolbarLayoutSettings,
  slotId: BrowserSplitToolbarSlotId,
  isKnownAction: (actionId: string) => boolean
): string {
  const stored = readLongPress(settings, slotId).trim();
  if (stored === 'none') {
    return 'none';
  }
  return isKnownAction(stored) ? stored : 'none';
}

export function replaceSplitToolbarInteraction(
  settings: BrowserToolbarLayoutSettings,
  slotId: BrowserSplitToolbarSlotId,
  kind: BrowserSplitToolbarInteractionKind,
  actionId: string,
  isKnownAction: (actionId: string) => boolean
): BrowserToolbarLayoutSettings {
  const normalized = normalizeSplitToolbarSettings(settings, isKnownAction);
  const definition = findSplitToolbarSlot(slotId);
  if (definition === undefined) {
    return normalized;
  }
  const trimmed = actionId.trim();
  if (kind === 'tap') {
    if (definition.tapLocked || trimmed.length === 0 || trimmed === 'none' || !isKnownAction(trimmed)) {
      return normalized;
    }
    if (resolveSplitToolbarTapActionId(normalized, slotId, isKnownAction) === trimmed) {
      return normalized;
    }
    if (otherSceneTapActionIds(normalized, definition, isKnownAction).includes(trimmed)) {
      return normalized;
    }
    const next = cloneBrowserToolbarLayoutSettings(normalized);
    writeTap(next, slotId, trimmed === definition.defaultTapActionId ? '' : trimmed);
    return next;
  }
  if (trimmed !== 'none' && !isKnownAction(trimmed)) {
    return normalized;
  }
  const stored = trimmed === 'none' ? 'none' : trimmed;
  if (resolveSplitToolbarLongPressActionId(normalized, slotId, isKnownAction) === stored) {
    return normalized;
  }
  const next = cloneBrowserToolbarLayoutSettings(normalized);
  writeLongPress(next, slotId, stored);
  return next;
}

export function resetSplitToolbarSlot(
  settings: BrowserToolbarLayoutSettings,
  slotId: BrowserSplitToolbarSlotId,
  isKnownAction: (actionId: string) => boolean
): BrowserToolbarLayoutSettings {
  const normalized = normalizeSplitToolbarSettings(settings, isKnownAction);
  if (findSplitToolbarSlot(slotId) === undefined) {
    return normalized;
  }
  const next = cloneBrowserToolbarLayoutSettings(normalized);
  writeTap(next, slotId, '');
  writeLongPress(next, slotId, 'none');
  return next;
}

export function resetAllSplitToolbarSlots(
  settings: BrowserToolbarLayoutSettings
): BrowserToolbarLayoutSettings {
  const next = cloneBrowserToolbarLayoutSettings(settings);
  writeTap(next, 'homeLeading', '');
  writeTap(next, 'homeSecondary', '');
  writeTap(next, 'webHome', '');
  writeLongPress(next, 'homeLeading', 'none');
  writeLongPress(next, 'homeSecondary', 'none');
  writeLongPress(next, 'homeTabs', 'none');
  writeLongPress(next, 'homeMenu', 'none');
  writeLongPress(next, 'webBack', 'none');
  writeLongPress(next, 'webForward', 'none');
  writeLongPress(next, 'webHome', 'none');
  writeLongPress(next, 'webTabs', 'none');
  writeLongPress(next, 'webMenu', 'none');
  return next;
}

export function normalizeSplitToolbarSettings(
  settings: BrowserToolbarLayoutSettings,
  isKnownAction: (actionId: string) => boolean
): BrowserToolbarLayoutSettings {
  const next = cloneBrowserToolbarLayoutSettings(settings);
  sanitizeStoredTaps(next, isKnownAction);
  sanitizeStoredLongPress(next, isKnownAction);
  clearConflictingStoredTaps(next, 'home', isKnownAction);
  clearConflictingStoredTaps(next, 'web', isKnownAction);
  return next;
}

export function hasSplitToolbarCustomizations(settings: BrowserToolbarLayoutSettings): boolean {
  return readTap(settings, 'homeLeading').trim().length > 0 ||
    readTap(settings, 'homeSecondary').trim().length > 0 ||
    readTap(settings, 'webHome').trim().length > 0 ||
    isCustomLongPress(settings, 'homeLeading') ||
    isCustomLongPress(settings, 'homeSecondary') ||
    isCustomLongPress(settings, 'homeTabs') ||
    isCustomLongPress(settings, 'homeMenu') ||
    isCustomLongPress(settings, 'webBack') ||
    isCustomLongPress(settings, 'webForward') ||
    isCustomLongPress(settings, 'webHome') ||
    isCustomLongPress(settings, 'webTabs') ||
    isCustomLongPress(settings, 'webMenu');
}

function sceneOf(slotId: BrowserSplitToolbarSlotId): BrowserSplitToolbarScene {
  return findSplitToolbarSlot(slotId)?.scene ?? 'home';
}

function resolveSceneTapActionIds(
  settings: BrowserToolbarLayoutSettings,
  scene: BrowserSplitToolbarScene,
  isKnownAction: (actionId: string) => boolean
): string[] {
  const used: string[] = [];
  const resolved: string[] = [];
  splitToolbarSlotsForScene(scene).forEach((slot: BrowserSplitToolbarSlotDefinition): void => {
    const actionId = resolveCandidateTap(settings, slot, isKnownAction, used);
    used.push(actionId);
    resolved.push(actionId);
  });
  return resolved;
}

function resolveCandidateTap(
  settings: BrowserToolbarLayoutSettings,
  slot: BrowserSplitToolbarSlotDefinition,
  isKnownAction: (actionId: string) => boolean,
  used: string[]
): string {
  if (slot.tapLocked) {
    return slot.defaultTapActionId;
  }
  const stored = readTap(settings, slot.id).trim();
  if (stored.length > 0 && isKnownAction(stored) && !used.includes(stored)) {
    return stored;
  }
  return slot.defaultTapActionId;
}

function otherSceneTapActionIds(
  settings: BrowserToolbarLayoutSettings,
  slot: BrowserSplitToolbarSlotDefinition,
  isKnownAction: (actionId: string) => boolean
): string[] {
  const resolved = resolveSceneTapActionIds(settings, slot.scene, isKnownAction);
  const slots = splitToolbarSlotsForScene(slot.scene);
  const others: string[] = [];
  slots.forEach((candidate: BrowserSplitToolbarSlotDefinition, index: number): void => {
    if (candidate.id !== slot.id) {
      others.push(resolved[index]);
    }
  });
  return others;
}

function sanitizeStoredTaps(
  settings: BrowserToolbarLayoutSettings,
  isKnownAction: (actionId: string) => boolean
): void {
  writeTap(settings, 'homeLeading', sanitizeTap(readTap(settings, 'homeLeading'), isKnownAction));
  writeTap(settings, 'homeSecondary', sanitizeTap(readTap(settings, 'homeSecondary'), isKnownAction));
  writeTap(settings, 'webHome', sanitizeTap(readTap(settings, 'webHome'), isKnownAction));
}

function sanitizeTap(actionId: string, isKnownAction: (actionId: string) => boolean): string {
  const trimmed = actionId.trim();
  if (trimmed.length === 0 || trimmed === 'none' || !isKnownAction(trimmed)) {
    return '';
  }
  return trimmed;
}

function sanitizeStoredLongPress(
  settings: BrowserToolbarLayoutSettings,
  isKnownAction: (actionId: string) => boolean
): void {
  SPLIT_TOOLBAR_SLOTS.forEach((slot: BrowserSplitToolbarSlotDefinition): void => {
    writeLongPress(settings, slot.id, sanitizeLongPress(readLongPress(settings, slot.id), isKnownAction));
  });
}

function sanitizeLongPress(actionId: string, isKnownAction: (actionId: string) => boolean): string {
  const trimmed = actionId.trim();
  if (trimmed === 'none' || isKnownAction(trimmed)) {
    return trimmed.length > 0 ? trimmed : 'none';
  }
  return 'none';
}

function clearConflictingStoredTaps(
  settings: BrowserToolbarLayoutSettings,
  scene: BrowserSplitToolbarScene,
  isKnownAction: (actionId: string) => boolean
): void {
  const resolved = resolveSceneTapActionIds(settings, scene, isKnownAction);
  splitToolbarSlotsForScene(scene).forEach((slot: BrowserSplitToolbarSlotDefinition, index: number): void => {
    if (slot.tapLocked) {
      return;
    }
    const stored = readTap(settings, slot.id).trim();
    if (stored.length > 0 && stored !== resolved[index]) {
      writeTap(settings, slot.id, '');
    }
  });
}

function isCustomLongPress(settings: BrowserToolbarLayoutSettings, slotId: BrowserSplitToolbarSlotId): boolean {
  const stored = readLongPress(settings, slotId).trim();
  return stored.length > 0 && stored !== 'none';
}

function readTap(settings: BrowserToolbarLayoutSettings, slotId: BrowserSplitToolbarSlotId): string {
  if (slotId === 'homeLeading') {
    return settings.splitHomeLeadingTapActionId ?? '';
  }
  if (slotId === 'homeSecondary') {
    return settings.splitHomeSecondaryTapActionId ?? '';
  }
  if (slotId === 'webHome') {
    return settings.splitWebHomeTapActionId ?? '';
  }
  return '';
}

function writeTap(
  settings: BrowserToolbarLayoutSettings,
  slotId: BrowserSplitToolbarSlotId,
  actionId: string
): void {
  if (slotId === 'homeLeading') {
    settings.splitHomeLeadingTapActionId = actionId;
    return;
  }
  if (slotId === 'homeSecondary') {
    settings.splitHomeSecondaryTapActionId = actionId;
    return;
  }
  if (slotId === 'webHome') {
    settings.splitWebHomeTapActionId = actionId;
  }
}

function readLongPress(settings: BrowserToolbarLayoutSettings, slotId: BrowserSplitToolbarSlotId): string {
  if (slotId === 'homeLeading') return settings.splitHomeLeadingLongPressActionId ?? 'none';
  if (slotId === 'homeSecondary') return settings.splitHomeSecondaryLongPressActionId ?? 'none';
  if (slotId === 'homeTabs') return settings.splitHomeTabsLongPressActionId ?? 'none';
  if (slotId === 'homeMenu') return settings.splitHomeMenuLongPressActionId ?? 'none';
  if (slotId === 'webBack') return settings.splitWebBackLongPressActionId ?? 'none';
  if (slotId === 'webForward') return settings.splitWebForwardLongPressActionId ?? 'none';
  if (slotId === 'webHome') return settings.splitWebHomeLongPressActionId ?? 'none';
  if (slotId === 'webTabs') return settings.splitWebTabsLongPressActionId ?? 'none';
  return settings.splitWebMenuLongPressActionId ?? 'none';
}

function writeLongPress(
  settings: BrowserToolbarLayoutSettings,
  slotId: BrowserSplitToolbarSlotId,
  actionId: string
): void {
  if (slotId === 'homeLeading') settings.splitHomeLeadingLongPressActionId = actionId;
  if (slotId === 'homeSecondary') settings.splitHomeSecondaryLongPressActionId = actionId;
  if (slotId === 'homeTabs') settings.splitHomeTabsLongPressActionId = actionId;
  if (slotId === 'homeMenu') settings.splitHomeMenuLongPressActionId = actionId;
  if (slotId === 'webBack') settings.splitWebBackLongPressActionId = actionId;
  if (slotId === 'webForward') settings.splitWebForwardLongPressActionId = actionId;
  if (slotId === 'webHome') settings.splitWebHomeLongPressActionId = actionId;
  if (slotId === 'webTabs') settings.splitWebTabsLongPressActionId = actionId;
  if (slotId === 'webMenu') settings.splitWebMenuLongPressActionId = actionId;
}
