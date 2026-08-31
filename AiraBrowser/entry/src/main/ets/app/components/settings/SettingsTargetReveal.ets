const SETTINGS_TARGET_REVEAL_SCROLL_TOP_SPACE: number = 12;
const SETTINGS_TARGET_REVEAL_SCROLL_DURATION_MS: number = 240;
const SETTINGS_TARGET_REVEAL_HIGHLIGHT_DURATION_MS: number = 1600;
const SETTINGS_TARGET_REVEAL_HIGHLIGHT_OPACITY: number = 0.72;

class SettingsTargetRevealArea {
  targetId: string;
  globalTop: number;

  constructor(targetId: string, globalTop: number) {
    this.targetId = targetId;
    this.globalTop = globalTop;
  }
}

export type SettingsTargetRevealHighlightHandler = (targetId: string) => void;

export class SettingsTargetRevealController {
  private scroller: Scroller | undefined = undefined;
  private areas: SettingsTargetRevealArea[] = [];
  private contentGlobalTop: number = 0;
  private hasContentGlobalTop: boolean = false;
  private requestedTargetId: string = '';
  private requestedRevision: number = 0;
  private consumedRevision: number = 0;
  private highlightTimer: number = -1;
  private onHighlightChanged: SettingsTargetRevealHighlightHandler;

  constructor(onHighlightChanged: SettingsTargetRevealHighlightHandler) {
    this.onHighlightChanged = onHighlightChanged;
  }

  bindScroller(scroller: Scroller | undefined): void {
    this.scroller = scroller;
    this.tryReveal();
  }

  request(targetId: string, revision: number): void {
    this.requestedTargetId = targetId.trim();
    this.requestedRevision = revision;
    this.tryReveal();
  }

  rememberContentArea(area: Area): void {
    this.contentGlobalTop = this.parseAreaPosition(area.globalPosition.y);
    this.hasContentGlobalTop = true;
    this.tryReveal();
  }

  rememberTargetArea(targetId: string, area: Area): void {
    const globalTop = this.parseAreaPosition(area.globalPosition.y);
    for (let index = 0; index < this.areas.length; index += 1) {
      if (this.areas[index].targetId === targetId) {
        this.areas[index].globalTop = globalTop;
        this.tryReveal();
        return;
      }
    }
    this.areas.push(new SettingsTargetRevealArea(targetId, globalTop));
    this.tryReveal();
  }

  dispose(): void {
    this.clearHighlightTimer();
  }

  private tryReveal(): void {
    if (this.requestedTargetId.length === 0 || this.requestedRevision <= this.consumedRevision ||
      !this.hasContentGlobalTop || this.scroller === undefined) {
      return;
    }
    const targetArea = this.findArea(this.requestedTargetId);
    if (targetArea === undefined) {
      return;
    }
    const targetOffset = Math.max(
      0,
      targetArea.globalTop - this.contentGlobalTop - SETTINGS_TARGET_REVEAL_SCROLL_TOP_SPACE
    );
    try {
      this.scroller.scrollTo({
        xOffset: 0,
        yOffset: targetOffset,
        animation: {
          duration: SETTINGS_TARGET_REVEAL_SCROLL_DURATION_MS,
          curve: Curve.EaseOut
        }
      });
    } catch (_error) {
      return;
    }
    this.consumedRevision = this.requestedRevision;
    this.onHighlightChanged(this.requestedTargetId);
    this.clearHighlightTimer();
    this.highlightTimer = setTimeout(() => {
      this.onHighlightChanged('');
      this.highlightTimer = -1;
    }, SETTINGS_TARGET_REVEAL_HIGHLIGHT_DURATION_MS);
  }

  private findArea(targetId: string): SettingsTargetRevealArea | undefined {
    for (let index = 0; index < this.areas.length; index += 1) {
      if (this.areas[index].targetId === targetId) {
        return this.areas[index];
      }
    }
    return undefined;
  }

  private clearHighlightTimer(): void {
    if (this.highlightTimer < 0) {
      return;
    }
    clearTimeout(this.highlightTimer);
    this.highlightTimer = -1;
  }

  private parseAreaPosition(value?: Length): number {
    if (value === undefined) {
      return 0;
    }
    const parsed = Number.parseFloat(`${value}`.replace('vp', '').replace('px', ''));
    return Number.isFinite(parsed) ? parsed : 0;
  }
}

@Component
export struct SettingsTargetRevealRegion {
  @Prop targetId: string = '';
  @Prop highlightedTargetId: string = '';
  @Prop accentColor: ResourceColor = '';
  @Prop regionLayoutWeight: number = 0;
  onAreaChanged: (targetId: string, area: Area) => void = (_targetId: string, _area: Area) => {};
  @BuilderParam content: () => void = this.emptyContent;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row()
        .width(3)
        .height(24)
        .backgroundColor(this.accentColor)
        .borderRadius(2)
        .opacity(this.highlightedTargetId === this.targetId ? SETTINGS_TARGET_REVEAL_HIGHLIGHT_OPACITY : 0)
        .animation({
          duration: SETTINGS_TARGET_REVEAL_SCROLL_DURATION_MS,
          curve: Curve.EaseOut
        })
        .hitTestBehavior(HitTestMode.None)
      this.content()
    }
    .width('100%')
    .layoutWeight(this.regionLayoutWeight)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.onAreaChanged(this.targetId, newArea);
    })
  }

  @Builder
  private emptyContent() {
  }
}
