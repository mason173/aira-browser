import { BrowserTabletInterfaceMode } from '../../common/models/BrowserDevicePresentationModels';

export type BrowserTabletInterfaceModeTransitionConsumer =
  'phone_native_settings_handoff' |
  'standalone_settings_route';

interface BrowserTabletInterfaceModeTransition {
  transitionId: number;
  targetMode: BrowserTabletInterfaceMode;
  consumer: BrowserTabletInterfaceModeTransitionConsumer;
}

/**
 * Owns the one-shot navigation postcondition for a manual interface-mode save.
 * Physical fold/input changes never arm this owner and therefore never navigate.
 */
export class BrowserTabletInterfaceModeTransitionOwner {
  private transitionSerial: number = 0;
  private pendingTransition?: BrowserTabletInterfaceModeTransition;

  begin(
    targetMode: BrowserTabletInterfaceMode,
    consumer: BrowserTabletInterfaceModeTransitionConsumer
  ): number {
    const transitionId = this.transitionSerial + 1;
    this.transitionSerial = transitionId;
    this.pendingTransition = {
      transitionId: transitionId,
      targetMode: targetMode,
      consumer: consumer
    };
    return transitionId;
  }

  cancel(transitionId: number): void {
    if (this.pendingTransition?.transitionId !== transitionId) {
      return;
    }
    this.pendingTransition = undefined;
  }

  consumeCommitted(
    targetMode: BrowserTabletInterfaceMode,
    consumer: BrowserTabletInterfaceModeTransitionConsumer
  ): boolean {
    const transition = this.pendingTransition;
    if (transition === undefined || transition.targetMode !== targetMode || transition.consumer !== consumer) {
      return false;
    }
    this.pendingTransition = undefined;
    return true;
  }
}

export const sharedBrowserTabletInterfaceModeTransitionOwner: BrowserTabletInterfaceModeTransitionOwner =
  new BrowserTabletInterfaceModeTransitionOwner();
