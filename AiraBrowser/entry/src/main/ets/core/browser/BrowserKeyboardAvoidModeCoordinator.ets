import { KeyboardAvoidMode, UIContext } from '@kit.ArkUI';

export interface BrowserKeyboardAvoidModeRequest {
  ownerId: string;
  mode: KeyboardAvoidMode;
  priority: number;
  sequence: number;
}

export class BrowserKeyboardAvoidModeCoordinator {
  private requests: BrowserKeyboardAvoidModeRequest[] = [];
  private previousModeCaptured: boolean = false;
  private previousMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET;
  private nextSequence: number = 1;

  requestMode(uiContext: UIContext, ownerId: string, mode: KeyboardAvoidMode, priority: number): void {
    const normalizedOwnerId = ownerId.trim();
    if (normalizedOwnerId.length <= 0) {
      return;
    }
    this.capturePreviousModeIfNeeded(uiContext);
    this.upsertRequest(normalizedOwnerId, mode, priority);
    this.applyResolvedMode(uiContext);
  }

  releaseOwner(uiContext: UIContext, ownerId: string): void {
    const normalizedOwnerId = ownerId.trim();
    if (normalizedOwnerId.length <= 0) {
      return;
    }
    const index = this.findRequestIndex(normalizedOwnerId);
    if (index < 0) {
      return;
    }
    this.requests.splice(index, 1);
    this.applyResolvedMode(uiContext);
  }

  releaseAll(uiContext: UIContext): void {
    if (this.requests.length <= 0 && !this.previousModeCaptured) {
      return;
    }
    this.requests = [];
    this.applyResolvedMode(uiContext);
  }

  private capturePreviousModeIfNeeded(uiContext: UIContext): void {
    if (this.previousModeCaptured) {
      return;
    }
    try {
      this.previousMode = uiContext.getKeyboardAvoidMode();
    } catch (_error) {
    }
    this.previousModeCaptured = true;
  }

  private upsertRequest(ownerId: string, mode: KeyboardAvoidMode, priority: number): void {
    const normalizedPriority = Number.isFinite(priority) ? priority : 0;
    const index = this.findRequestIndex(ownerId);
    if (index >= 0) {
      const existing = this.requests[index];
      existing.mode = mode;
      existing.priority = normalizedPriority;
      return;
    }
    this.requests.push({
      ownerId,
      mode,
      priority: normalizedPriority,
      sequence: this.nextSequence
    });
    this.nextSequence += 1;
  }

  private findRequestIndex(ownerId: string): number {
    for (let index = 0; index < this.requests.length; index += 1) {
      if (this.requests[index].ownerId === ownerId) {
        return index;
      }
    }
    return -1;
  }

  private applyResolvedMode(uiContext: UIContext): void {
    const resolvedRequest = this.resolveActiveRequest();
    if (resolvedRequest !== undefined) {
      this.applyMode(uiContext, resolvedRequest.mode);
      return;
    }
    if (!this.previousModeCaptured) {
      return;
    }
    const previousMode = this.previousMode;
    this.previousModeCaptured = false;
    this.applyMode(uiContext, previousMode);
  }

  private resolveActiveRequest(): BrowserKeyboardAvoidModeRequest | undefined {
    if (this.requests.length <= 0) {
      return undefined;
    }
    let candidate = this.requests[0];
    for (let index = 1; index < this.requests.length; index += 1) {
      const request = this.requests[index];
      if (request.priority > candidate.priority ||
        (request.priority === candidate.priority && request.sequence > candidate.sequence)) {
        candidate = request;
      }
    }
    return candidate;
  }

  private applyMode(uiContext: UIContext, mode: KeyboardAvoidMode): void {
    try {
      if (uiContext.getKeyboardAvoidMode() !== mode) {
        uiContext.setKeyboardAvoidMode(mode);
      }
    } catch (_error) {
    }
  }
}
