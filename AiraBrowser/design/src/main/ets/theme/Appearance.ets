import { common, ConfigurationConstant } from '@kit.AbilityKit'
import { readPersistText, writePersistText, setPersistContext } from './PersistStore'

/** 公共外观只管理浅色、深色和跟随系统；应用自己的设置由应用保存。 */
export const APPEARANCE_COLOR_MODE_KEY: string = 'appearanceColorMode'
export const APPEARANCE_COLOR_MODE_DEFAULT: number = -1
export const COLOR_MODE_DARK: number = 0
export const COLOR_MODE_LIGHT: number = 1
export const COLOR_MODE_SYSTEM: number = -1

// 保持已有应用的存储键，升级组件库不重置外观。
const APPEARANCE_PREF_KEY: string = 'appearance_settings'

function savedSettings(): Record<string, Object> {
  try {
    const record = JSON.parse(readPersistText(APPEARANCE_PREF_KEY)) as Record<string, Object>
    if (record !== null && typeof record === 'object' && !Array.isArray(record)) {
      return record
    }
  } catch (_error) {
  }
  return {}
}

/** 在 Ability 启动时调用，保留 PersistentStorage 旧值迁移。 */
export function appearanceInit(context: common.Context | undefined): void {
  setPersistContext(context)
  PersistentStorage.persistProp(APPEARANCE_COLOR_MODE_KEY, APPEARANCE_COLOR_MODE_DEFAULT)
  const record = savedSettings()
  const mode = record[APPEARANCE_COLOR_MODE_KEY]
  if (typeof mode === 'number') {
    AppStorage.setOrCreate(APPEARANCE_COLOR_MODE_KEY, mode)
  } else {
    persistMode(currentColorMode())
  }
  applyColorMode(context)
}

function persistMode(mode: number): void {
  // 保留旧版本记录里的其他字段，不因公共库精简而删除宿主历史设置。
  const record = savedSettings()
  record[APPEARANCE_COLOR_MODE_KEY] = mode
  writePersistText(APPEARANCE_PREF_KEY, JSON.stringify(record))
}

export function currentColorMode(): number {
  const value = AppStorage.get<number>(APPEARANCE_COLOR_MODE_KEY)
  return typeof value === 'number' ? value : APPEARANCE_COLOR_MODE_DEFAULT
}

/**
 * 切换外观。
 *
 * **顺序是有意的：先真正切，再通知订阅者。**
 * 订阅者收到通知后往往会立刻读一遍颜色（把色值读成数字来插值的组件必须这么做，
 * `$r` 资源会自己更新、数值快照不会）。先通知后切的话，它们读到的是**切换前**的色值，
 * 表现为"深浅色换了，但那一块颜色没变，重启应用才跟上"（2026-10-17 修的：
 * 列表卡片的倒计时环底色要重启才跟随）。
 */
export function setColorMode(context: common.Context | undefined, mode: number): void {
  applyMode(context, mode)
  persistMode(mode)
  AppStorage.setOrCreate(APPEARANCE_COLOR_MODE_KEY, mode)
}

export function applyColorMode(context: common.Context | undefined): void {
  applyMode(context, currentColorMode())
}

function applyMode(context: common.Context | undefined, mode: number): void {
  if (!context) {
    return
  }
  try {
    context.getApplicationContext().setColorMode(mode as ConfigurationConstant.ColorMode)
  } catch (_error) {
  }
}
