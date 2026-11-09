import { common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { readPersistText, writePersistText, setPersistContext } from './PersistStore'

/**
 * 运行时换主题色。
 *
 * 为什么需要这一层：`$r('app.color.x')` 在编译期就定死了，运行时换不了。所以「用户换主题色」
 * 的本质是——凡是**跟着主题变**的颜色，使用点不再读 `$r`，改读这里算出来的运行时值。
 * 不跟主题的语义色（危险红、成功绿、长休紫、提醒橙等）继续读 `$r`，不受影响。
 *
 * 主题色用 `palette_*` 那 20 个下标表示：`-1` = 默认（就是现在的品牌蓝，直接用原 `$r` token，
 * 保证默认外观和以前一模一样），`0..19` = 对应 `palette_*`，其余角色由基色派生。
 *
 * 全局状态：本项目此前靠 `Home` 下传 `@Prop version` 计数来刷新，没有全局响应式状态。
 * 主题是一个要跨整棵树生效的全局值，用 `AppStorage` 的 `themeHue` 键最低成本：
 * 组件用 `@StorageProp(THEME_HUE_KEY) themeHue` 订阅，值一变自动重渲染。
 * 落盘走 preferences + flushSync（见 `PersistStore`），不用 PersistentStorage——它异步
 * 落盘，快速杀进程会丢写入。
 */

/** AppStorage / 持久化里存主题色下标的键。 */
export const THEME_HUE_KEY: string = 'themeHue'
/** preferences 里存主题色的键（权威存储，见 PersistStore）。 */
const THEME_HUE_PREF_KEY: string = 'theme_hue'
/** 默认值：-1 表示用原来的品牌蓝 token。 */
export const THEME_HUE_DEFAULT: number = -1

/** 主题可选的色板个数（`palette_*`）。 */
export function themeHueCount(): number {
  return 20
}

/** 写主题色：AppStorage（界面即时刷新）+ preferences 同步刷盘（杀进程不丢）。 */
export function setThemeHue(hue: number): void {
  AppStorage.setOrCreate(THEME_HUE_KEY, hue)
  writePersistText(THEME_HUE_PREF_KEY, `${hue}`)
}

/** 读当前主题色下标。 */
export function currentThemeHue(): number {
  const value = AppStorage.get<number>(THEME_HUE_KEY)
  return typeof value === 'number' ? value : THEME_HUE_DEFAULT
}

let appContext: common.Context | undefined = undefined

/**
 * 应用启动时调一次，把 context 存下来。之后连没有 UIContext 的自由函数（如
 * `TaskItem.priorityColor`）也能通过 `currentRoles()` 取色，不必到处传 host。
 * 同时接主题色的落盘：PersistentStorage 只做旧值迁移，preferences 里的值权威。
 */
export function themeInit(context: common.Context | undefined): void {
  appContext = context
  setPersistContext(context)
  PersistentStorage.persistProp(THEME_HUE_KEY, THEME_HUE_DEFAULT)
  const persistentHue = currentThemeHue()
  const raw = readPersistText(THEME_HUE_PREF_KEY)
  const diskHue = Number(raw)
  if (raw.length > 0 && Number.isFinite(diskHue)) {
    if (diskHue !== persistentHue) {
      AppStorage.setOrCreate(THEME_HUE_KEY, diskHue)
    }
  } else if (persistentHue !== THEME_HUE_DEFAULT) {
    // 第一版存在 PersistentStorage 里的值，迁进 preferences。之后只认 preferences。
    writePersistText(THEME_HUE_PREF_KEY, `${persistentHue}`)
  }
  hilog.info(0x0000, 'PineconePrefs',
    'theme init: persistent=%{public}d prefs=%{public}s -> %{public}d',
    persistentHue, raw.length > 0 ? raw : '(empty)', currentThemeHue())
}

/**
 * 一组「跟着主题变」的颜色角色。默认时每个字段直接指向原 `$r` token。
 */
export class ThemeRoles {
  primary: ResourceColor = $r('app.color.primary')
  onPrimary: ResourceColor = $r('app.color.primary_foreground')
  disabled: ResourceColor = $r('app.color.primary_disabled')
  switchOn: ResourceColor = $r('app.color.switch_on')
  checkboxOn: ResourceColor = $r('app.color.checkbox_on')
  quadrantUrgent: ResourceColor = $r('app.color.quadrant_urgent')
  fabTaskBadge: ResourceColor = $r('app.color.fab_menu_task_badge')
  ringTail: ResourceColor = $r('app.color.focus_ring_tail')
  ringStart: ResourceColor = $r('app.color.focus_ring_start')
  ringEnd: ResourceColor = $r('app.color.focus_ring_end')
  heat1: ResourceColor = $r('app.color.focus_heat_1')
  heat2: ResourceColor = $r('app.color.focus_heat_2')
  heat3: ResourceColor = $r('app.color.focus_heat_3')
  heat4: ResourceColor = $r('app.color.focus_heat_4')
  iconBlue: ResourceColor = $r('app.color.sidebar_icon_blue')
  iconGreen: ResourceColor = $r('app.color.sidebar_icon_green')
  iconOrange: ResourceColor = $r('app.color.sidebar_icon_orange')
  iconPurple: ResourceColor = $r('app.color.sidebar_icon_purple')
  iconTeal: ResourceColor = $r('app.color.sidebar_icon_teal')
  iconRed: ResourceColor = $r('app.color.sidebar_icon_red')
}

/** `palette_*` 资源名，顺序 P。和 `ListColors.ets` 的调色板顺序一致，不要动。 */
const PALETTE_NAMES: string[] = [
  'palette_rose', 'palette_pink', 'palette_magenta', 'palette_violet', 'palette_indigo',
  'palette_blue', 'palette_azure', 'palette_sky', 'palette_teal', 'palette_emerald',
  'palette_green', 'palette_lime', 'palette_amber', 'palette_orange', 'palette_tangerine',
  'palette_red', 'palette_sand', 'palette_tan', 'palette_navy', 'palette_ink'
]

/** 侧栏六个图标徽章相对主题色相的偏移（度）。 */
const ICON_HUE_OFFSETS: number[] = [0, 60, 120, 180, 240, 300]

let cachedKey: string = ''
let cachedRoles: ThemeRoles | undefined = undefined

/** 取当前主题色下的角色组。默认色相直接返回原 token，保证不退化。 */
export function themeRoles(hue: number, host: common.Context | undefined): ThemeRoles {
  if (hue < 0 || hue >= themeHueCount() || host === undefined) {
    return new ThemeRoles()
  }
  const dark = isDark(host)
  const key = `${hue}-${dark ? 1 : 0}`
  if (cachedRoles !== undefined && cachedKey === key) {
    return cachedRoles
  }
  const base = paletteHex(host, hue)
  const roles = deriveRoles(hue, base, dark)
  cachedKey = key
  cachedRoles = roles
  return roles
}

/** 给没有 UIContext 的自由函数用：读当前主题色 + 启动时存的 context。 */
export function currentRoles(): ThemeRoles {
  return themeRoles(currentThemeHue(), appContext)
}

/** 用基色派生全部角色。 */
function deriveRoles(hue: number, base: string, dark: boolean): ThemeRoles {
  const roles = new ThemeRoles()
  const surface = dark ? '#161616' : '#ffffff'

  roles.primary = base
  roles.onPrimary = luminance(base) > 0.62 ? '#202020' : '#ffffff'
  // 主色 20% 叠在底色上（浅色叠白、深色叠卡片底）。
  roles.disabled = mix(surface, base, 0.2)
  roles.switchOn = base
  roles.checkboxOn = base
  roles.quadrantUrgent = base
  roles.fabTaskBadge = base

  // 进度环：尾端全透明，前半亮、后半深。深色下整体更亮一点。
  roles.ringTail = `#00${strip(base)}`
  roles.ringStart = dark ? lighten(base, 0.35) : lighten(base, 0.28)
  roles.ringEnd = dark ? base : darken(base, 0.18)

  // 热力图四档：浅色往白混（越深档越接近基色再压暗）；深色往底混再提亮。
  if (dark) {
    roles.heat1 = mix('#020002', base, 0.28)
    roles.heat2 = mix('#020002', base, 0.5)
    roles.heat3 = mix('#020002', base, 0.72)
    roles.heat4 = lighten(base, 0.22)
  } else {
    roles.heat1 = mix('#ffffff', base, 0.22)
    roles.heat2 = mix('#ffffff', base, 0.5)
    roles.heat3 = mix('#ffffff', base, 0.78)
    roles.heat4 = darken(base, 0.18)
  }

  // 侧栏六色：主题色相按固定偏移转出六个协调但仍分得开的色相。
  const hsl = rgbToHsl(hexToRgb(base))
  const icons: ResourceColor[] = []
  for (let i = 0; i < ICON_HUE_OFFSETS.length; i++) {
    const rotated = (hsl.h + ICON_HUE_OFFSETS[i]) % 360
    icons.push(hslToHex(rotated, clamp(hsl.s, 0.55, 0.85), clamp(hsl.l, 0.5, 0.6)))
  }
  roles.iconBlue = icons[0]
  roles.iconGreen = icons[1]
  roles.iconOrange = icons[2]
  roles.iconPurple = icons[3]
  roles.iconTeal = icons[4]
  roles.iconRed = icons[5]
  return roles
}

/** 从 `palette_*` 资源读基色 hex。读不到就退回蓝，不至于崩。 */
function paletteHex(host: common.Context, hue: number): string {
  const name = PALETTE_NAMES[hue]
  try {
    const value = host.resourceManager.getColorByNameSync(name)
    if (value >= 0) {
      return argbToHex(value)
    }
  } catch (_err) {
    // 读不到就走下面的兜底。
  }
  return '#00b3ff'
}

/** 当前是不是深色：拿不到配置就当浅色。 */
function isDark(host: common.Context): boolean {
  try {
    const value = host.resourceManager.getColorByNameSync('background')
    return value >= 0 && luminance(argbToHex(value)) < 0.35
  } catch (_err) {
    return false
  }
}

// ---------- 颜色数学 ----------

function clamp(value: number, min: number, max: number): number {
  return value < min ? min : (value > max ? max : value)
}

function strip(hex: string): string {
  return hex.startsWith('#') ? hex.substring(1) : hex
}

function argbToHex(value: number): string {
  const rgb = value & 0x00ffffff
  const raw = rgb.toString(16)
  return `#${'000000'.substring(raw.length)}${raw}`
}

class Rgb {
  r: number = 0
  g: number = 0
  b: number = 0
}

function hexToRgb(hex: string): Rgb {
  const raw = strip(hex)
  const value = Number.parseInt(raw.length > 6 ? raw.substring(raw.length - 6) : raw, 16)
  const out = new Rgb()
  if (Number.isNaN(value)) {
    return out
  }
  out.r = (value >> 16) & 0xff
  out.g = (value >> 8) & 0xff
  out.b = value & 0xff
  return out
}

function channel(value: number): string {
  const v = clamp(Math.round(value), 0, 255)
  const raw = v.toString(16)
  return raw.length < 2 ? `0${raw}` : raw
}

function rgbToHex(rgb: Rgb): string {
  return `#${channel(rgb.r)}${channel(rgb.g)}${channel(rgb.b)}`
}

function mix(from: string, to: string, t: number): string {
  const a = hexToRgb(from)
  const b = hexToRgb(to)
  const out = new Rgb()
  out.r = a.r + (b.r - a.r) * t
  out.g = a.g + (b.g - a.g) * t
  out.b = a.b + (b.b - a.b) * t
  return rgbToHex(out)
}

function lighten(hex: string, t: number): string {
  return mix(hex, '#ffffff', t)
}

function darken(hex: string, t: number): string {
  return mix(hex, '#000000', t)
}

/** 感知亮度 0–1。 */
function luminance(hex: string): number {
  const rgb = hexToRgb(hex)
  return (0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b) / 255
}

class Hsl {
  h: number = 0
  s: number = 0
  l: number = 0
}

function rgbToHsl(rgb: Rgb): Hsl {
  const r = rgb.r / 255
  const g = rgb.g / 255
  const b = rgb.b / 255
  const max = Math.max(r, Math.max(g, b))
  const min = Math.min(r, Math.min(g, b))
  const out = new Hsl()
  out.l = (max + min) / 2
  if (max === min) {
    return out
  }
  const d = max - min
  out.s = out.l > 0.5 ? d / (2 - max - min) : d / (max + min)
  if (max === r) {
    out.h = (g - b) / d + (g < b ? 6 : 0)
  } else if (max === g) {
    out.h = (b - r) / d + 2
  } else {
    out.h = (r - g) / d + 4
  }
  out.h = out.h * 60
  return out
}

function hueToChannel(p: number, q: number, tIn: number): number {
  let t = tIn
  if (t < 0) {
    t += 1
  }
  if (t > 1) {
    t -= 1
  }
  if (t < 1 / 6) {
    return p + (q - p) * 6 * t
  }
  if (t < 1 / 2) {
    return q
  }
  if (t < 2 / 3) {
    return p + (q - p) * (2 / 3 - t) * 6
  }
  return p
}

function hslToHex(hue: number, s: number, l: number): string {
  if (s <= 0) {
    const gray = new Rgb()
    gray.r = Math.round(l * 255)
    gray.g = gray.r
    gray.b = gray.r
    return rgbToHex(gray)
  }
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s
  const p = 2 * l - q
  const h = (hue % 360) / 360
  const out = new Rgb()
  out.r = hueToChannel(p, q, h + 1 / 3) * 255
  out.g = hueToChannel(p, q, h) * 255
  out.b = hueToChannel(p, q, h - 1 / 3) * 255
  return rgbToHex(out)
}
