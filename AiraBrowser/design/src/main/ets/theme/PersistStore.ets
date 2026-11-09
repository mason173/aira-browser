import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { hilog } from '@kit.PerformanceAnalysisKit'

/**
 * 设置类数据的落盘帮手：preferences（`tasks` 库）`putSync + flushSync`，写完才返回，
 * 成功返回表示同步刷盘已完成；失败仅尽力恢复缓存，不保证任意存储故障下的物理回滚。
 *
 * 为什么不用 PersistentStorage：它的落盘是异步的，用户改完立刻杀进程会丢写入，
 * 下次启动回退成默认值，还会经云同步污染别的设备（2026-10 启动视图踩的坑，
 * 主题色历史上被推回默认也是它）。设置类数据一律走这里；PersistentStorage 只能当
 * 旧值的迁移源，不再往里写。日志标签 PineconePrefs。
 */

const STORE_NAME: string = 'tasks'
const TAG: string = 'PineconePrefs'

let appContext: common.Context | undefined = undefined

// 只在同一键成功 put + flush 后解除；换 context 或其他键刷盘不能解除。
// 这是当前模块生命周期内的读保护，不是可跨进程恢复的事务日志。
const failedKeys: Set<string> = new Set<string>()

/** 启动时调一次（themeInit / appearanceInit 里都会带 context 调它）。 */
export function setPersistContext(context: common.Context | undefined): void {
  appContext = context
}

function openStore(): preferences.Preferences | undefined {
  if (!appContext) {
    return undefined
  }
  try {
    return preferences.getPreferencesSync(appContext, { name: STORE_NAME })
  } catch (_err) {
    return undefined
  }
}

/** 读一个字符串。失败键、没有 context、库打不开或键不存在都返回空串。 */
export function readPersistText(key: string): string {
  if (failedKeys.has(key)) {
    return ''
  }
  const store = openStore()
  if (!store) {
    return ''
  }
  try {
    const value = store.getSync(key, '')
    return typeof value === 'string' ? value : ''
  } catch (_err) {
    return ''
  }
}

/** 写一个字符串（同步刷盘）。返回有没有写成功。 */
export function writePersistText(key: string, value: string): boolean {
  const store = openStore()
  if (!store) {
    hilog.warn(0x0000, TAG, 'write skipped (no store): %{public}s', key)
    return false
  }
  // 先完整取得快照，再允许修改。保留原始 ValueType，不把非字符串旧值变成空串。
  let existed: boolean
  let previous: preferences.ValueType
  try {
    existed = store.hasSync(key)
    previous = store.getSync(key, '')
  } catch (_err) {
    failedKeys.add(key)
    hilog.warn(0x0000, TAG, 'write snapshot failed: %{public}s', key)
    return false
  }
  try {
    store.putSync(key, value)
    store.flushSync()
    failedKeys.delete(key)
    return true
  } catch (_err) {
    // putSync 本身也可能修改缓存后抛错。先封锁读取，再尽力恢复写前缓存，
    // 避免其他键后续 flush 把本次失败的新值顺带持久化。不额外刷整库。
    failedKeys.add(key)
    try {
      if (existed) {
        store.putSync(key, previous)
      } else {
        store.deleteSync(key)
      }
    } catch (_rollbackErr) {
      hilog.warn(0x0000, TAG, 'write cache rollback failed: %{public}s', key)
    }
    // rollback 失败时缓存可能仍有新值，其他键刷盘也可能将它落盘；guard
    // 只能保证本模块继续 fail closed，无法保证磁盘回滚或进程重启后的读取。
    hilog.warn(0x0000, TAG, 'write failed: %{public}s', key)
    return false
  }
}
