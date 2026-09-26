import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import { applyDesktopDialogSheetChrome } from '../common/DesktopDialogSheetChrome';
import { AiraIcon } from '../common/AiraIcon';
import { AiraLegalWebDocumentContent } from '../legal/AiraLegalWebDocumentContent';
import { resolveAiraLegalDocumentLink } from '../../../services/legal/AiraLegalDocuments';
import { BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import {
  FEATURE_INTRO_GATE_KNOB_INSET_VP,
  FEATURE_INTRO_GATE_KNOB_VP,
  FEATURE_INTRO_GATE_TRACK_HEIGHT_VP,
  FEATURE_INTRO_GATE_TRACK_MAX_WIDTH_VP,
  clampFeatureIntroGateDrag,
  featureIntroGateBackdropColor,
  isFeatureIntroGateUnlocked,
  resolveFeatureIntroGateLabelOpacity,
  resolveFeatureIntroGateLogoSize,
  resolveFeatureIntroGateLogoTop,
  resolveFeatureIntroGateTravel
} from '../../../core/onboarding/FeatureIntroGatePolicy';

@Component
export struct FeatureIntroGate {
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedMode: string = 'light';
  @Prop topInsetVp: number = 0;
  @Prop bottomInsetVp: number = 0;
  label: string = '';
  skipLabel: string = '';
  onUnlocked: () => void = (): void => undefined;
  onSkip: () => void = (): void => undefined;
  @State private skipReady: boolean = false;
  @State private windowWidthVp: number = 360;
  @State private windowHeightVp: number = 780;
  @State private trackWidthVp: number = 0;
  @State private knobOffsetVp: number = 0;
  @State private videoOpacity: number = 0;
  @State private logoOpacity: number = 0;
  @State private logoShiftVp: number = 16;
  @State private sliderOpacity: number = 0;
  @State private sliderShiftVp: number = 16;
  @State private sliderReady: boolean = false;
  @State private legalSheetVisible: boolean = false;
  @State private legalDocumentTitle: string = '';
  @State private legalDocumentUrl: string = '';
  private entrancePlayed: boolean = false;
  private unlockCompleted: boolean = false;
  private readonly videoController: VideoController = new VideoController();

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(featureIntroGateBackdropColor(this.storedResolvedMode))

      Video({
        src: $rawfile('feature_intro_gate.mp4'),
        controller: this.videoController
      })
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .muted(true)
        .controls(false)
        .loop(true)
        .autoPlay(false)
        .opacity(this.videoOpacity)
        .onPrepared((): void => {
          this.videoController.start();
        })
        .onFinish((): void => {
          this.videoController.start();
        })

      Column() {
        Image($rawfile('feature_intro_logo.png'))
          .width(this.resolveLogoSize())
          .height(this.resolveLogoSize())
          .objectFit(ImageFit.Contain)
        Text('Aira')
          .fontSize(36)
          .lineHeight(42)
          .fontWeight(FontWeight.Bold)
          .fontColor('#17191F')
          .textAlign(TextAlign.Center)
          .margin({ top: 14 })
        Text('做最纯粹的鸿蒙浏览器')
          .fontSize(17)
          .lineHeight(24)
          .fontWeight(FontWeight.Lighter)
          .fontColor('#5C616B')
          .textAlign(TextAlign.Center)
          .margin({ top: 4 })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: this.resolveLogoTop() })
      .opacity(this.logoOpacity)
      .translate({ y: this.logoShiftVp })
      .hitTestBehavior(HitTestMode.None)

      Column() {
        this.buildTrack()
        this.buildLegalConsent()
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(HorizontalAlign.Center)
      .padding({
        left: 28,
        right: 28,
        bottom: Math.max(12, this.bottomInsetVp + 8)
      })
      .opacity(this.sliderOpacity)
      .translate({ y: this.sliderShiftVp })
      .hitTestBehavior(this.sliderReady ? HitTestMode.Default : HitTestMode.None)

      Row() {
        Text(this.skipLabel)
          .fontSize(14)
          .fontWeight(FontWeight.Regular)
          .fontColor('#3C4046')
          .padding({ left: 16, right: 20, top: 8, bottom: 8 })
          .onClick((): void => {
            this.confirmSkip();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .align(Alignment.TopEnd)
      .margin({ top: this.topInsetVp + 4, right: 8 })
      .opacity(this.logoOpacity)
      .hitTestBehavior(this.skipReady ? HitTestMode.Default : HitTestMode.None)
    }
    .bindSheet($$this.legalSheetVisible, this.buildLegalSheet(), applyDesktopDialogSheetChrome({
      preferType: SheetType.BOTTOM,
      height: SheetSize.LARGE,
      dragBar: true,
      showClose: true,
      backgroundColor: '#FFFFFF',
      onDisappear: (): void => {
        this.legalSheetVisible = false;
      }
    }, 'l'))
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAppear((): void => {
      this.playEntrance();
    })
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.updateWindowSize(newArea);
    })
  }

  @Builder
  private buildLegalConsent() {
    Flex({
      direction: FlexDirection.Row,
      wrap: FlexWrap.Wrap,
      justifyContent: FlexAlign.Center,
      alignItems: ItemAlign.Center
    }) {
      Text('继续操作即表示您同意')
        .fontSize(11)
        .lineHeight(16)
        .fontColor('#8A8F98')
      Text('用户服务协议')
        .fontSize(11)
        .lineHeight(16)
        .fontColor('#17191F')
        .decoration({ type: TextDecorationType.Underline, color: '#17191F' })
        .padding({ left: 2, right: 2, top: 4, bottom: 4 })
        .onClick((): void => {
          this.openLegalDocument('user_service_agreement');
        })
      Text('和')
        .fontSize(11)
        .lineHeight(16)
        .fontColor('#8A8F98')
      Text('隐私政策')
        .fontSize(11)
        .lineHeight(16)
        .fontColor('#17191F')
        .decoration({ type: TextDecorationType.Underline, color: '#17191F' })
        .padding({ left: 2, right: 2, top: 4, bottom: 4 })
        .onClick((): void => {
          this.openLegalDocument('privacy_statement');
        })
    }
    .width('100%')
    .margin({ top: 18 })
  }

  @Builder
  private buildLegalSheet() {
    Column() {
      Text(this.legalDocumentTitle)
        .width('100%')
        .fontSize(16)
        .lineHeight(22)
        .fontWeight(FontWeight.Medium)
        .fontColor('#17191F')
        .textAlign(TextAlign.Center)
        .padding({ top: 4, bottom: 12, left: 24, right: 24 })
      AiraLegalWebDocumentContent({
        documentUrl: this.legalDocumentUrl,
        styleId: 'aira-feature-intro-legal'
      })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  @Builder
  private buildTrack() {
    Stack({ alignContent: Alignment.Start }) {
      Text(this.label)
        .width('100%')
        .height('100%')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .opacity(this.resolveLabelOpacity())

      Stack({ alignContent: Alignment.Center }) {
        AiraIcon({
          airaIconId: 'browser.toolbar.forward',
          iconSize: 34,
          iconColor: '#17191F'
        })
      }
      .width(FEATURE_INTRO_GATE_KNOB_VP)
      .height(FEATURE_INTRO_GATE_KNOB_VP)
      .margin({ left: FEATURE_INTRO_GATE_KNOB_INSET_VP })
      .borderRadius(FEATURE_INTRO_GATE_KNOB_VP / 2)
      .backgroundColor('#FFFFFF')
      .translate({ x: this.knobOffsetVp })
      .gesture(
        PanGesture({ direction: PanDirection.Horizontal, distance: 1 })
          .onActionUpdate((event: GestureEvent): void => {
            this.updateDrag(event.offsetX);
          })
          .onActionEnd((): void => {
            this.finishDrag();
          })
          .onActionCancel((): void => {
            this.finishDrag();
          })
      )
    }
    .width('100%')
    .constraintSize({ maxWidth: FEATURE_INTRO_GATE_TRACK_MAX_WIDTH_VP })
    .height(FEATURE_INTRO_GATE_TRACK_HEIGHT_VP)
    .borderRadius(FEATURE_INTRO_GATE_TRACK_HEIGHT_VP / 2)
    .clip(true)
    .backgroundColor(Color.Transparent)
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK, {
      colorMode: ThemeColorMode.DARK,
      adaptiveColor: AdaptiveColor.DEFAULT,
      scale: 1
    })
    .border({ width: 1, color: '#33FFFFFF' })
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.trackWidthVp = this.parseAreaVp(newArea.width);
    })
  }

  private openLegalDocument(id: string): void {
    const link = resolveAiraLegalDocumentLink(id);
    this.legalDocumentTitle = link.title;
    this.legalDocumentUrl = link.url;
    this.legalSheetVisible = true;
  }

  private confirmSkip(): void {
    if (!this.skipReady || this.unlockCompleted) {
      return;
    }
    showCenteredAlertDialog({
      title: '跳过介绍',
      message: '跳过后将直接进入主页，不再显示这些介绍。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: (): void => undefined
      },
      secondaryButton: {
        value: '进入主页',
        action: (): void => {
          this.onSkip();
        }
      }
    });
  }

  private playEntrance(): void {
    if (this.entrancePlayed) {
      return;
    }
    this.entrancePlayed = true;
    animateTo({ duration: 900, curve: Curve.EaseOut }, (): void => {
      this.videoOpacity = 1;
    });
    animateTo({ duration: 700, delay: 280, curve: Curve.EaseOut, onFinish: (): void => {
      this.skipReady = true;
    } }, (): void => {
      this.logoOpacity = 1;
      this.logoShiftVp = 0;
    });
    animateTo({ duration: 700, delay: 560, curve: Curve.EaseOut, onFinish: (): void => {
      this.sliderReady = true;
    } }, (): void => {
      this.sliderOpacity = 1;
      this.sliderShiftVp = 0;
    });
  }

  private updateDrag(offsetVp: number): void {
    if (this.unlockCompleted || !this.sliderReady) {
      return;
    }
    this.knobOffsetVp = clampFeatureIntroGateDrag(offsetVp, resolveFeatureIntroGateTravel(this.trackWidthVp));
  }

  private finishDrag(): void {
    if (this.unlockCompleted || !this.sliderReady) {
      return;
    }
    const travel = resolveFeatureIntroGateTravel(this.trackWidthVp);
    if (isFeatureIntroGateUnlocked(this.knobOffsetVp, travel)) {
      this.unlockCompleted = true;
      animateTo({ duration: 160, curve: Curve.EaseOut, onFinish: (): void => {
        this.onUnlocked();
      } }, (): void => {
        this.knobOffsetVp = travel;
      });
      return;
    }
    animateTo({ duration: 260, curve: Curve.EaseOut }, (): void => {
      this.knobOffsetVp = 0;
    });
  }

  private resolveLabelOpacity(): number {
    return resolveFeatureIntroGateLabelOpacity(this.knobOffsetVp, resolveFeatureIntroGateTravel(this.trackWidthVp));
  }

  private resolveLogoSize(): number {
    return resolveFeatureIntroGateLogoSize(this.windowWidthVp);
  }

  private resolveLogoTop(): number {
    return resolveFeatureIntroGateLogoTop(this.windowHeightVp, this.topInsetVp, this.resolveLogoSize());
  }

  private updateWindowSize(area: Area): void {
    const width = this.parseAreaVp(area.width);
    const height = this.parseAreaVp(area.height);
    if (width > 0) {
      this.windowWidthVp = width;
    }
    if (height > 0) {
      this.windowHeightVp = height;
    }
  }

  private parseAreaVp(value: Length): number {
    const parsed = Number(`${value}`.replace('vp', '').replace('px', ''));
    return Number.isFinite(parsed) ? parsed : 0;
  }
}
