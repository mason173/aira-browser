import {
  BrowserSystemMemoryPressureLevel,
  BrowserSystemMemoryPressureSnapshot
} from './BrowserTabBackgroundTypes';

export const BROWSER_SYSTEM_MEMORY_PRESSURE_REVISION_KEY: string =
  'aira.browser.systemMemoryPressure.revision';
const BROWSER_SYSTEM_MEMORY_PRESSURE_LEVEL_KEY: string =
  'aira.browser.systemMemoryPressure.level';
const BROWSER_SYSTEM_MEMORY_PRESSURE_UPDATED_AT_KEY: string =
  'aira.browser.systemMemoryPressure.updatedAt';
const BROWSER_SYSTEM_MEMORY_PRESSURE_SOURCE_KEY: string =
  'aira.browser.systemMemoryPressure.source';
const BROWSER_SYSTEM_MEMORY_PRESSURE_RAW_LEVEL_KEY: string =
  'aira.browser.systemMemoryPressure.rawLevel';

export class BrowserSystemMemoryPressureSignal {
  static record(
    level: BrowserSystemMemoryPressureLevel,
    source: string,
    rawLevel: number
  ): number {
    const nextRevision = (AppStorage.get<number>(BROWSER_SYSTEM_MEMORY_PRESSURE_REVISION_KEY) ?? 0) + 1;
    AppStorage.setOrCreate(BROWSER_SYSTEM_MEMORY_PRESSURE_LEVEL_KEY, level);
    AppStorage.setOrCreate(BROWSER_SYSTEM_MEMORY_PRESSURE_UPDATED_AT_KEY, Date.now());
    AppStorage.setOrCreate(BROWSER_SYSTEM_MEMORY_PRESSURE_SOURCE_KEY, source);
    AppStorage.setOrCreate(BROWSER_SYSTEM_MEMORY_PRESSURE_RAW_LEVEL_KEY, rawLevel);
    AppStorage.setOrCreate(BROWSER_SYSTEM_MEMORY_PRESSURE_REVISION_KEY, nextRevision);
    return nextRevision;
  }

  static getSnapshot(): BrowserSystemMemoryPressureSnapshot {
    return {
      level: BrowserSystemMemoryPressureSignal.normalizeLevel(
        AppStorage.get<string>(BROWSER_SYSTEM_MEMORY_PRESSURE_LEVEL_KEY) ?? 'normal'
      ),
      revision: AppStorage.get<number>(BROWSER_SYSTEM_MEMORY_PRESSURE_REVISION_KEY) ?? 0,
      updatedAt: AppStorage.get<number>(BROWSER_SYSTEM_MEMORY_PRESSURE_UPDATED_AT_KEY) ?? 0,
      source: AppStorage.get<string>(BROWSER_SYSTEM_MEMORY_PRESSURE_SOURCE_KEY) ?? '',
      rawLevel: AppStorage.get<number>(BROWSER_SYSTEM_MEMORY_PRESSURE_RAW_LEVEL_KEY) ?? -1
    };
  }

  static buildInitialSnapshot(): BrowserSystemMemoryPressureSnapshot {
    return {
      level: 'normal',
      revision: 0,
      updatedAt: 0,
      source: '',
      rawLevel: -1
    };
  }

  private static normalizeLevel(value: string): BrowserSystemMemoryPressureLevel {
    if (value === 'moderate' || value === 'low' || value === 'critical') {
      return value;
    }
    return 'normal';
  }
}
