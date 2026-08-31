import { BrowserHostedWebHiddenSlot } from '../../../core/browser/BrowserHostedWebOwnershipCoordinator';
import { BrowserHostedWebParkingSlotGeometry } from '../../../core/browser/BrowserHostedWebLayerPresentationViewModel';
import { BrowserTabState } from '../../../core/tabs/TabManager';
import { HostedWebNodeController } from '../../../core/web/HostedWebNode';

@Component
export struct BrowserHostedWebFixedSlots {
  @Prop tabs: BrowserTabState[] = [];
  @Prop activeHostedTabId: string = '';
  @Prop hiddenSlots: BrowserHostedWebHiddenSlot[] = [];
  @Prop activeSurfaceVisible: boolean = true;
  @Prop surfaceRevision: string = '';

  resolveController: (tabId: string) => HostedWebNodeController | undefined =
    (_tabId: string): HostedWebNodeController | undefined => undefined;
  resolveControllerGeneration: (tabId: string) => number = (_tabId: string): number => 0;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.tabs, (tab: BrowserTabState) => {
        if (this.shouldMountFixedSlot(tab, this.surfaceRevision)) {
          NodeContainer(this.resolveController(tab.id) as HostedWebNodeController)
            .width('100%')
            .height('100%')
            .clip(true)
            .visibility(this.isActiveSlotVisible(tab.id) ? Visibility.Visible : Visibility.Hidden)
            .hitTestBehavior(this.isActiveSlotVisible(tab.id) ? HitTestMode.Default : HitTestMode.None)
        }
      }, (tab: BrowserTabState) => `${tab.id}:${this.resolveControllerGeneration(tab.id)}`)
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }

  private shouldMountFixedSlot(tab: BrowserTabState, _surfaceRevision: string): boolean {
    if (tab.isHome || this.resolveController(tab.id) === undefined) {
      return false;
    }
    return tab.id === this.activeHostedTabId || this.isBackgroundHot(tab.id);
  }

  private isActiveSlotVisible(tabId: string): boolean {
    return this.activeSurfaceVisible && tabId === this.activeHostedTabId;
  }

  private isBackgroundHot(tabId: string): boolean {
    return this.hiddenSlots.some((slot: BrowserHostedWebHiddenSlot) => {
      return slot.kind === 'background-hot' && slot.tabId === tabId;
    });
  }
}

@Component
export struct BrowserHostedWebParkingSlots {
  @Prop slots: BrowserHostedWebHiddenSlot[] = [];
  @Prop activeHostedTabId: string = '';

  resolveController: (tabId: string) => HostedWebNodeController | undefined =
    (_tabId: string): HostedWebNodeController | undefined => undefined;
  resolveGeometry: (slot: BrowserHostedWebHiddenSlot) => BrowserHostedWebParkingSlotGeometry =
    (_slot: BrowserHostedWebHiddenSlot): BrowserHostedWebParkingSlotGeometry => {
      return {
        width: 1,
        height: 1
      };
    };

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.slots, (slot: BrowserHostedWebHiddenSlot) => {
        if (this.shouldMountParkingSlot(slot)) {
          NodeContainer(this.resolveController(slot.tabId) as HostedWebNodeController)
            .width(this.resolveGeometry(slot).width)
            .height(this.resolveGeometry(slot).height)
            .clip(true)
            .opacity(0.01)
            .hitTestBehavior(HitTestMode.None)
            .position({ x: 0, y: 0 })
        }
      }, (slot: BrowserHostedWebHiddenSlot) => `${slot.tabId}:${slot.kind}`)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  private shouldMountParkingSlot(slot: BrowserHostedWebHiddenSlot): boolean {
    return slot.kind === 'desktop-web-entry-parked' &&
      slot.tabId !== this.activeHostedTabId &&
      this.resolveController(slot.tabId) !== undefined;
  }
}
