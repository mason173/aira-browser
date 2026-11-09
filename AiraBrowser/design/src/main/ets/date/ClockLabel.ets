/** 时间一律写成 24 小时制两位数：00:23、09:30、12:23、23:59。 */
export function clockLabel(hour: number, minute: number): string {
  let h = hour
  if (h < 0) {
    h = 0
  }
  if (h > 23) {
    h = 23
  }
  let m = minute
  if (m < 0) {
    m = 0
  }
  if (m > 59) {
    m = 59
  }
  const hh = h < 10 ? `0${h}` : `${h}`
  const mm = m < 10 ? `0${m}` : `${m}`
  return `${hh}:${mm}`
}
