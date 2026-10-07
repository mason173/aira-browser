/**
 * Ownership rules for the in-flight `@ohos.net.http` handles a translation batch opens.
 *
 * Every `http.createHttp()` handle is driven by NetStack's `OS_NET_HttpWork` thread over a libcurl multi handle.
 * Destroying a handle while that thread is still inside `multi_runsingle` / `curl_multi_socket_action` for it is a
 * use-after-free inside the system library — the crash Aira sees when a busy translation is torn down during a
 * foreground/background or page switch. Two rules keep that from happening:
 *
 * - Cancelling a batch abandons our references to its requests; it never destroys a handle that may still be in
 *   flight. The handle is torn down later, by whoever waited on it, once the request has actually settled.
 * - A settled request is destroyed exactly once, so the settle path and any earlier cancellation cannot both fire
 *   `destroy()` on the same handle.
 *
 * A handle is a class rather than a bare function so this stays inside the ArkTS checker's rules: a class wraps the
 * destroy action and exposes it as a method, which the checker allows, while a function-typed interface member it
 * would not.
 */

/** One in-flight translation request, reduced to the single capability this registry needs: destroying it once. */
export class TranslationRequestHandle {
  private readonly destroyAction: () => void;
  private destroyed: boolean = false;

  constructor(destroyAction: () => void) {
    this.destroyAction = destroyAction;
  }

  /** Destroys the underlying request, at most once across the handle's lifetime. */
  destroyOnce(): void {
    if (this.destroyed) {
      return;
    }
    this.destroyed = true;
    this.destroyAction();
  }
}

export class TranslationActiveRequestRegistry {
  private active: TranslationRequestHandle[] = [];
  private abandoned: TranslationRequestHandle[] = [];

  /** Records a request that has just started. */
  track(handle: TranslationRequestHandle): void {
    this.active.push(handle);
  }

  /**
   * Cancels a batch by dropping our references to its in-flight requests without touching them.
   *
   * The handles stay alive until their own request settles; tearing them down here is what crashes the NetStack
   * thread. Results from an abandoned batch are discarded upstream by generation checks, so nothing needs them.
   */
  abandon(): void {
    for (const handle of this.active) {
      this.abandoned.push(handle);
    }
    this.active = [];
  }

  /**
   * The request has settled: destroy it, exactly once, whether or not the batch was abandoned in the meantime.
   *
   * Calls after the first are a no-op, so a request that was already destroyed cannot be destroyed twice.
   */
  settle(handle: TranslationRequestHandle): void {
    const activeIndex = this.active.indexOf(handle);
    if (activeIndex >= 0) {
      this.active.splice(activeIndex, 1);
      handle.destroyOnce();
      return;
    }
    const abandonedIndex = this.abandoned.indexOf(handle);
    if (abandonedIndex >= 0) {
      this.abandoned.splice(abandonedIndex, 1);
      handle.destroyOnce();
    }
  }
}
