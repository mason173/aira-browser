/**
 * Lets a settings scroll body hand its Scroller to the title bar without every
 * page passing `scrollers` by hand. Unbound title bars must not show the
 * scroll-effect blur, so the scaffold only enables it after a scroller arrives.
 */
export class SettingsHeaderScrollRegistry {
  scrollers: Scroller[] = [];
  private listener: (() => void) | undefined = undefined;

  setListener(listener: () => void): void {
    this.listener = listener;
    if (this.scrollers.length > 0) {
      listener();
    }
  }

  bind(scroller: Scroller): void {
    if (this.scrollers.indexOf(scroller) >= 0) {
      return;
    }
    this.scrollers.push(scroller);
    if (this.listener !== undefined) {
      this.listener();
    }
  }
}
