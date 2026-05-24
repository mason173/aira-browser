import { SCENARIO_MODES_KEY, SCENARIO_SELECTED_KEY } from '@/scenario/scenario';
import type { ScenarioMode } from '@/scenario/scenario';
import type { ScenarioShortcuts, SyncablePreferences } from '@/types';
import { normalizeSyncablePreferences, readSyncablePreferencesFromStorage } from '@/utils/syncablePreferences';

export const LOCAL_SHORTCUTS_KEY = 'local_shortcuts_v3';
export const LEGACY_SHORTCUTS_KEY = 'local_shortcuts';
export const LOCAL_PROFILE_SNAPSHOT_KEY = 'leaf_tab_local_profile_v1';

export type LocalProfileSnapshot = {
  scenarioModes: ScenarioMode[];
  selectedScenarioId: string;
  scenarioShortcuts: ScenarioShortcuts;
  preferences?: SyncablePreferences;
};

const isObject = (value: unknown): value is Record<string, unknown> => {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
};

const parseJson = <T>(raw: string | null): T | null => {
  if (!raw) return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
};

export const readLocalProfileSnapshot = (): LocalProfileSnapshot | null => {
  const snapshot = parseJson<LocalProfileSnapshot>(localStorage.getItem(LOCAL_PROFILE_SNAPSHOT_KEY));
  if (snapshot && Array.isArray(snapshot.scenarioModes) && typeof snapshot.selectedScenarioId === 'string' && isObject(snapshot.scenarioShortcuts)) {
    return {
      ...snapshot,
      preferences: normalizeSyncablePreferences(snapshot.preferences || readSyncablePreferencesFromStorage()),
    };
  }

  const scenarioModes = parseJson<ScenarioMode[]>(localStorage.getItem(SCENARIO_MODES_KEY));
  const selectedScenarioId = localStorage.getItem(SCENARIO_SELECTED_KEY);
  const scenarioShortcuts = parseJson<ScenarioShortcuts>(localStorage.getItem(LOCAL_SHORTCUTS_KEY));
  if (!Array.isArray(scenarioModes) || !selectedScenarioId || !isObject(scenarioShortcuts)) return null;

  return {
    scenarioModes,
    selectedScenarioId,
    scenarioShortcuts,
    preferences: readSyncablePreferencesFromStorage(),
  };
};

export const persistLocalProfileSnapshot = (snapshot: LocalProfileSnapshot) => {
  const existing = readLocalProfileSnapshot();
  const nextSnapshot: LocalProfileSnapshot = {
    scenarioModes: snapshot.scenarioModes,
    selectedScenarioId: snapshot.selectedScenarioId,
    scenarioShortcuts: snapshot.scenarioShortcuts,
    preferences: normalizeSyncablePreferences(
      snapshot.preferences
      || existing?.preferences
      || readSyncablePreferencesFromStorage(),
    ),
  };
  const serialized = JSON.stringify(nextSnapshot);
  localStorage.setItem(LOCAL_PROFILE_SNAPSHOT_KEY, serialized);
  localStorage.setItem(SCENARIO_MODES_KEY, JSON.stringify(nextSnapshot.scenarioModes));
  localStorage.setItem(SCENARIO_SELECTED_KEY, nextSnapshot.selectedScenarioId);
  localStorage.setItem(LOCAL_SHORTCUTS_KEY, JSON.stringify(nextSnapshot.scenarioShortcuts));
  localStorage.removeItem(LEGACY_SHORTCUTS_KEY);
  localStorage.setItem('local_shortcuts_updated_at', new Date().toISOString());
};

export const clearLocalProfileSnapshot = () => {
  localStorage.removeItem(LOCAL_PROFILE_SNAPSHOT_KEY);
  localStorage.removeItem(LOCAL_SHORTCUTS_KEY);
  localStorage.removeItem(LEGACY_SHORTCUTS_KEY);
  localStorage.removeItem(SCENARIO_MODES_KEY);
  localStorage.removeItem(SCENARIO_SELECTED_KEY);
  localStorage.removeItem('local_shortcuts_updated_at');
};

export const persistLocalProfilePreferences = (preferences: SyncablePreferences) => {
  const current = readLocalProfileSnapshot();
  if (!current) return;
  persistLocalProfileSnapshot({
    ...current,
    preferences: normalizeSyncablePreferences(preferences),
  });
};
