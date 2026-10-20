/** Keep the completed snapshot opaque while the reattached Web surface settles underneath. */
export function resolveBrowserTabSurfaceHandoffDelayMs(reduceMotion: boolean = false): number {
  return reduceMotion ? 80 : 120;
}
