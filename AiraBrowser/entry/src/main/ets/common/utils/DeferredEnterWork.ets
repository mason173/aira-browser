const DEFAULT_PAGE_ENTER_CONTENT_DELAY_MS: number = 280;

export class DeferredEnterWork {
  private timer: number = -1;

  schedule(task: () => void, delayMs: number = DEFAULT_PAGE_ENTER_CONTENT_DELAY_MS): void {
    this.cancel();
    this.timer = setTimeout((): void => {
      this.timer = -1;
      task();
    }, Math.max(0, delayMs));
  }

  cancel(): void {
    if (this.timer < 0) {
      return;
    }
    clearTimeout(this.timer);
    this.timer = -1;
  }
}
