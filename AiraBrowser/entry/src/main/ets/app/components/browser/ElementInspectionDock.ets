import {
  ElementInspectionAction,
  ElementInspectionOutlineCommand,
  ElementInspectionPresentation
} from '../../../core/browser/ElementInspectionSessionCoordinator';
import {
  ElementInspectionOutlineContextMenu,
  ElementInspectionOutlineMenuEntry
} from './ElementInspectionOutlineContextMenu';
import {
  ElementInspectionBoxModel,
  ElementInspectionComputedProperty,
  ElementInspectionConsoleEntry,
  ElementInspectionListenerEntry,
  ElementInspectionNetworkEntry,
  ElementInspectionOutlineNode,
  ElementInspectionSourceEntry
} from '../../../services/web/ElementInspectionRuntimeScriptService';
import { AiraIcon } from '../common/AiraIcon';
import { pointer } from '@kit.InputKit';

const ELEMENT_INSPECTION_DOCK_DEFAULT_WIDTH_VP: number = 440;
const ELEMENT_INSPECTION_DOCK_MIN_WIDTH_VP: number = 240;
const ELEMENT_INSPECTION_DOCK_MAX_WIDTH_VP: number = 1100;
const ELEMENT_INSPECTION_DOCK_SPLITTER_HIT_VP: number = 12;
const ELEMENT_INSPECTION_DOCK_ROW_HEIGHT_VP: number = 22;
const ELEMENT_INSPECTION_DOCK_BACKGROUND_COLOR: string = '#202124';
const ELEMENT_INSPECTION_DOCK_BAR_COLOR: string = '#292a2d';
const ELEMENT_INSPECTION_DOCK_LINE_COLOR: string = '#3c4043';
const ELEMENT_INSPECTION_DOCK_TEXT_COLOR: string = '#e8eaed';
const ELEMENT_INSPECTION_DOCK_DIM_COLOR: string = '#9aa0a6';
const ELEMENT_INSPECTION_DOCK_BLUE_COLOR: string = '#8ab4f8';
const ELEMENT_INSPECTION_DOCK_SELECT_COLOR: string = '#1a73e8';
const ELEMENT_INSPECTION_DOCK_TAG_COLOR: string = '#f08c6a';
const ELEMENT_INSPECTION_DOCK_ATTR_COLOR: string = '#e8c07a';
const ELEMENT_INSPECTION_DOCK_STRING_COLOR: string = '#b4a7ff';

type ElementInspectionDockTab = 'elements' | 'console' | 'sources' | 'network';
type ElementInspectionDockSubtab = 'styles' | 'computed' | 'layout' | 'listeners';

@Component
export struct ElementInspectionDock {
  @Prop @Watch('handlePresentationChanged') presentation: ElementInspectionPresentation;
  @Prop maxWidthVp: number = 1200;
  @State private panelWidthVp: number = ELEMENT_INSPECTION_DOCK_DEFAULT_WIDTH_VP;
  @State private tab: string = 'elements';
  @State private subtab: string = 'computed';
  @State private filterText: string = '';
  @State private splitterActive: boolean = false;
  @State private splitterDragging: boolean = false;
  @State private consoleFilter: string = 'all';
  @State private consoleInput: string = '';
  @State private selectedSourceId: string = '';
  @State private hoveredOutlinePath: string = '';
  @State private editorVisible: boolean = false;
  @State private editorKind: string = '';
  @State private editorTitle: string = '';
  @State private editorPath: string = '';
  @State private editorText: string = '';
  @State private editorName: string = '';
  @State private editorBusy: boolean = false;
  @State private outlineMenuVisible: boolean = false;
  @State private outlineMenuEntries: ElementInspectionOutlineMenuEntry[] = [];
  @State private outlineMenuAnchorXVp: number = 0;
  @State private outlineMenuAnchorYVp: number = 0;
  @State private outlineMenuHostWidthVp: number = 0;
  @State private outlineMenuHostHeightVp: number = 0;
  private outlineMenuHostGlobalXVp: number = 0;
  private outlineMenuHostGlobalYVp: number = 0;
  private outlineMenuPath: string = '';
  private editorRequestId: number = 0;
  private appliedEditorRequestId: number = -1;
  private panStartWidthVp: number = ELEMENT_INSPECTION_DOCK_DEFAULT_WIDTH_VP;
  private panResizeActive: boolean = false;
  private mouseDragStartWindowXPx: number = 0;
  private mouseDragStartWidthVp: number = ELEMENT_INSPECTION_DOCK_DEFAULT_WIDTH_VP;
  private treeScroller: Scroller = new Scroller();
  onAction: (action: ElementInspectionAction) => void = (_action: ElementInspectionAction) => {};
  onSelectOutline: (path: string) => void = (_path: string) => {};
  onPreviewOutline: (path: string) => void = (_path: string) => {};
  onClearOutlinePreview: () => void = () => {};
  onPickerArmedChange: (armed: boolean) => void = (_armed: boolean) => {};
  onEvaluateConsole: (expression: string) => void = (_expression: string) => {};
  onClearConsole: () => void = () => {};
  onReadSource: (sourceId: string) => void = (_sourceId: string) => {};
  onOutlineCommand: (command: ElementInspectionOutlineCommand) => void =
    (_command: ElementInspectionOutlineCommand) => {};

  build() {
    Row() {
      this.buildSplitter()

      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          this.buildTabBar()
          if (this.tab === 'elements') {
            this.buildElementsPane()
          } else if (this.tab === 'console') {
            this.buildConsolePane()
          } else if (this.tab === 'network') {
            this.buildNetworkPane()
          } else if (this.tab === 'sources') {
            this.buildSourcesPane()
          } else {
            Text('这个页签没有内容。')
              .width('100%')
              .layoutWeight(1)
              .fontSize(13)
              .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
              .textAlign(TextAlign.Center)
              .padding(24)
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(ELEMENT_INSPECTION_DOCK_BACKGROUND_COLOR)

        if (this.editorVisible) {
          this.buildOutlineEditor()
        }

        if (this.outlineMenuVisible) {
          this.buildOutlineMenuOverlay()
        }
      }
      .layoutWeight(1)
      .height('100%')
      .clip(true)
      .onAreaChange((_oldArea: Area, area: Area) => {
        this.updateOutlineMenuHost(area);
      })

      if (this.splitterDragging) {
        Column()
          .width(2800)
          .height('100%')
          .position({ x: -2600, y: 0 })
          .zIndex(40)
          .hitTestBehavior(HitTestMode.Block)
          .backgroundColor(Color.Transparent)
          .onMouse((event: MouseEvent) => {
            this.handleSplitterMouse(event, true);
          })
      }

    }
    .width(this.panelWidthVp)
    .height('100%')
    .clip(false)
    .zIndex(3)
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  private buildSplitter() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width(this.splitterActive ? 3 : 1)
        .height('100%')
        .backgroundColor(this.splitterActive ?
          ELEMENT_INSPECTION_DOCK_BLUE_COLOR : ELEMENT_INSPECTION_DOCK_LINE_COLOR)
    }
    .width(ELEMENT_INSPECTION_DOCK_SPLITTER_HIT_VP)
    .height('100%')
    .backgroundColor(this.splitterActive ? '#1a73e822' : Color.Transparent)
    .hitTestBehavior(HitTestMode.Default)
    .responseRegion({ x: -8, y: 0, width: 28, height: '100%' })
    .accessibilityText('拖动调整网页和审查元素窗口的宽度')
    .onHover((isHover: boolean) => {
      if (this.splitterDragging) {
        return;
      }
      this.splitterActive = isHover;
      this.setSplitterCursor(isHover);
    })
    .onMouse((event: MouseEvent) => {
      this.handleSplitterMouse(event, false);
    })
    .priorityGesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 1 })
        .onActionStart(() => {
          this.beginSplitterDrag(this.panelWidthVp);
          this.panResizeActive = true;
        })
        .onActionUpdate((event: GestureEvent) => {
          this.panResizeActive = true;
          this.panelWidthVp = this.clampWidth(this.panStartWidthVp - event.offsetX);
        })
        .onActionEnd(() => {
          this.endSplitterDrag();
        })
        .onActionCancel(() => {
          this.endSplitterDrag();
        })
    )
  }

  @Builder
  private buildTabBar() {
    Row() {
      Button({ type: ButtonType.Normal }) {
        AiraIcon({
          airaIconId: 'browser.elementInspection.picker',
          iconSize: 18,
          iconColor: this.presentation.pickerArmed ?
            ELEMENT_INSPECTION_DOCK_BLUE_COLOR : ELEMENT_INSPECTION_DOCK_DIM_COLOR
        })
      }
        .width(32)
        .height(32)
        .backgroundColor(Color.Transparent)
        .margin({ left: 4, right: 2 })
        .accessibilityText(this.presentation.pickerArmed ? '停止在页面上选择' : '在页面上选择元素')
        .onClick(() => {
          this.onPickerArmedChange(!this.presentation.pickerArmed);
        })

      this.buildTabButton('元素', 'elements')
      this.buildTabButton('控制台', 'console')
      this.buildTabButton('源代码', 'sources')
      this.buildTabButton('网络', 'network')

      Blank()

      Button({ type: ButtonType.Normal }) {
        AiraIcon({
          airaIconId: 'browser.tabs.delete',
          iconSize: 16,
          iconColor: ELEMENT_INSPECTION_DOCK_DIM_COLOR
        })
      }
        .width(32)
        .height(32)
        .backgroundColor(Color.Transparent)
        .accessibilityText('关闭审查元素')
        .onClick(() => {
          this.onAction('cancel');
        })
    }
    .width('100%')
    .height(40)
    .backgroundColor(ELEMENT_INSPECTION_DOCK_BAR_COLOR)
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: 1 }, color: ELEMENT_INSPECTION_DOCK_LINE_COLOR })
  }

  @Builder
  private buildTabButton(label: string, tab: ElementInspectionDockTab) {
    Button(label)
      .type(ButtonType.Normal)
      .height(40)
      .fontSize(13)
      .fontColor(this.tab === tab ? '#FFFFFF' : ELEMENT_INSPECTION_DOCK_DIM_COLOR)
      .backgroundColor(Color.Transparent)
      .padding({ left: 10, right: 10 })
      .border({
        width: { bottom: 2 },
        color: this.tab === tab ? ELEMENT_INSPECTION_DOCK_BLUE_COLOR : Color.Transparent
      })
      .onClick(() => {
        this.tab = tab;
      })
  }

  @Builder
  private buildElementsPane() {
    Scroll(this.treeScroller) {
      Column() {
        if (this.presentation.outline.length === 0) {
          Text(this.presentation.phase === 'starting' || this.presentation.busy ?
            '正在准备元素审查…' : '当前页面没有可显示的元素')
            .width('100%')
            .fontSize(12)
            .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
            .padding(12)
        }
        ForEach(this.presentation.outline, (node: ElementInspectionOutlineNode) => {
          this.buildOutlineRow(node)
        }, (node: ElementInspectionOutlineNode) => node.path.length > 0 ? node.path : 'root')
        if (this.presentation.node === undefined && this.presentation.outline.length > 0) {
          Text(this.presentation.helperText)
            .width('100%')
            .fontSize(12)
            .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1.15)
    .align(Alignment.TopStart)
    .scrollBar(BarState.Auto)

    this.buildCrumb()

    Column() {
      this.buildSubtabs()
      if (this.subtab === 'computed') {
        this.buildComputedPane()
      } else if (this.subtab === 'styles') {
        this.buildStylesPane()
      } else if (this.subtab === 'listeners') {
        this.buildListenersPane()
      } else {
        Text('布局这次先留空。')
          .width('100%')
          .layoutWeight(1)
          .fontSize(12)
          .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
          .textAlign(TextAlign.Center)
          .padding(16)
      }
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: 280 })
    .width('100%')
  }

  @Builder
  private buildOutlineRow(node: ElementInspectionOutlineNode) {
    Row() {
      Text(node.childCount > 0 ? '▾' : '')
        .width(14)
        .fontSize(10)
        .fontColor(node.selected ? '#FFFFFF' : ELEMENT_INSPECTION_DOCK_DIM_COLOR)
      Text() {
        Span('<')
          .fontColor(node.selected ? '#FFFFFF' : ELEMENT_INSPECTION_DOCK_TAG_COLOR)
        Span(node.tagName)
          .fontColor(node.selected ? '#FFFFFF' : ELEMENT_INSPECTION_DOCK_TAG_COLOR)
        if (node.elementId.length > 0) {
          Span(' id=')
            .fontColor(node.selected ? '#FFFFFF' : ELEMENT_INSPECTION_DOCK_ATTR_COLOR)
          Span(`"${node.elementId}"`)
            .fontColor(node.selected ? '#FFFFFF' : ELEMENT_INSPECTION_DOCK_STRING_COLOR)
        }
        if (node.classTokens.length > 0) {
          Span(' class=')
            .fontColor(node.selected ? '#FFFFFF' : ELEMENT_INSPECTION_DOCK_ATTR_COLOR)
          Span(`"${node.classTokens.join(' ')}"`)
            .fontColor(node.selected ? '#FFFFFF' : ELEMENT_INSPECTION_DOCK_STRING_COLOR)
        }
        Span('>')
          .fontColor(node.selected ? '#FFFFFF' : ELEMENT_INSPECTION_DOCK_TAG_COLOR)
        if (node.textPreview.length > 0) {
          Span(` ${node.textPreview}`)
            .fontColor(node.selected ? '#FFFFFF' : ELEMENT_INSPECTION_DOCK_DIM_COLOR)
        }
      }
      .fontFamily('monospace')
      .fontSize(12)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .copyOption(CopyOptions.None)
    }
    .width('100%')
    .height(ELEMENT_INSPECTION_DOCK_ROW_HEIGHT_VP)
    .padding({ left: 8 + node.depth * 12, right: 8 })
    .backgroundColor(node.selected ? ELEMENT_INSPECTION_DOCK_SELECT_COLOR :
      (this.hoveredOutlinePath === node.path ? '#35363a' : Color.Transparent))
    .alignItems(VerticalAlign.Center)
    .onHover((isHover: boolean) => {
      if (isHover) {
        this.hoveredOutlinePath = node.path;
        this.onPreviewOutline(node.path);
        return;
      }
      if (this.hoveredOutlinePath === node.path) {
        this.hoveredOutlinePath = '';
      }
      this.onClearOutlinePreview();
    })
    .onClick(() => {
      this.dismissOutlineMenu();
      if (!this.presentation.busy) {
        this.onSelectOutline(node.path);
      }
    })
    .onMouse((event: MouseEvent) => {
      if (event.button !== MouseButton.Right || event.action !== MouseAction.Press) {
        return;
      }
      event.stopPropagation();
      this.openOutlineMenu(node, event);
    })
  }

  @Builder
  private buildOutlineMenuOverlay() {
    Stack() {
      Column()
        .width(8000)
        .height('100%')
        .position({ x: -4000, y: 0 })
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => {
          this.dismissOutlineMenu();
        })
        .onMouse((event: MouseEvent) => {
          if (event.button === MouseButton.Right && event.action === MouseAction.Press) {
            this.dismissOutlineMenu();
          }
        })
        .keyboardShortcut(FunctionKey.ESC, [], () => {
          this.dismissOutlineMenu();
        })

      ElementInspectionOutlineContextMenu({
        entries: this.outlineMenuEntries,
        anchorXVp: this.outlineMenuAnchorXVp,
        anchorYVp: this.outlineMenuAnchorYVp,
        hostWidthVp: this.outlineMenuHostWidthVp,
        hostHeightVp: this.outlineMenuHostHeightVp,
        onSelect: (key: string): void => {
          this.handleOutlineMenuSelect(key);
        }
      })
    }
    .width('100%')
    .height('100%')
    .zIndex(80)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private buildOutlineEditor() {
    Column() {
      Text(this.editorTitle)
        .width('100%')
        .fontSize(14)
        .fontColor(ELEMENT_INSPECTION_DOCK_TEXT_COLOR)
        .margin({ bottom: 8 })
      Text(this.editorKind === 'html' ?
        '需要保留一个根元素。' : '属性值为空时会删除该属性。')
        .width('100%')
        .fontSize(12)
        .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
        .margin({ bottom: 10 })
      if (this.editorKind === 'attribute') {
        TextInput({ text: this.editorName, placeholder: '属性名' })
          .width('100%')
          .height(36)
          .fontSize(13)
          .fontColor(ELEMENT_INSPECTION_DOCK_TEXT_COLOR)
          .placeholderColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
          .backgroundColor(ELEMENT_INSPECTION_DOCK_BAR_COLOR)
          .margin({ bottom: 8 })
          .enabled(!this.editorBusy)
          .onChange((value: string) => {
            this.editorName = value;
          })
      }
      if (this.editorBusy) {
        Text('正在读取 HTML…')
          .width('100%')
          .layoutWeight(1)
          .fontSize(12)
          .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
      }
      TextArea({
        text: this.editorText,
        placeholder: this.editorKind === 'html' ? '' : '属性值'
      })
        .visibility(this.editorBusy ? Visibility.None : Visibility.Visible)
        .width('100%')
        .layoutWeight(1)
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor(ELEMENT_INSPECTION_DOCK_TEXT_COLOR)
        .placeholderColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
        .backgroundColor(ELEMENT_INSPECTION_DOCK_BAR_COLOR)
        .enabled(!this.editorBusy)
        .onChange((value: string) => {
          if (!this.editorBusy) {
            this.editorText = value;
          }
        })
      Row({ space: 8 }) {
        Button('取消')
          .layoutWeight(1)
          .height(34)
          .fontSize(13)
          .fontColor(ELEMENT_INSPECTION_DOCK_TEXT_COLOR)
          .backgroundColor(ELEMENT_INSPECTION_DOCK_LINE_COLOR)
          .onClick(() => {
            this.closeOutlineEditor();
          })
        Button(this.editorKind === 'html' ? '应用' : '确定')
          .layoutWeight(1)
          .height(34)
          .fontSize(13)
          .fontColor('#FFFFFF')
          .backgroundColor(ELEMENT_INSPECTION_DOCK_SELECT_COLOR)
          .enabled(this.canApplyOutlineEditor())
          .onClick(() => {
            this.applyOutlineEditor();
          })
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor(ELEMENT_INSPECTION_DOCK_BACKGROUND_COLOR)
    .zIndex(20)
    .hitTestBehavior(HitTestMode.Block)
  }

  @Builder
  private buildCrumb() {
    Row() {
      Text(this.resolveCrumbPrefix())
        .layoutWeight(1)
        .fontSize(11)
        .fontFamily('monospace')
        .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.resolveCrumbCurrent().length > 0) {
        Text(this.resolveCrumbCurrent())
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor('#FFFFFF')
          .backgroundColor(ELEMENT_INSPECTION_DOCK_SELECT_COLOR)
          .borderRadius(4)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .maxLines(1)
      }
    }
    .width('100%')
    .height(28)
    .padding({ left: 8, right: 8 })
    .backgroundColor(ELEMENT_INSPECTION_DOCK_BAR_COLOR)
    .alignItems(VerticalAlign.Center)
    .border({ width: { top: 1 }, color: ELEMENT_INSPECTION_DOCK_LINE_COLOR })
  }

  @Builder
  private buildSubtabs() {
    Row() {
      this.buildSubtabButton('样式', 'styles')
      this.buildSubtabButton('计算后', 'computed')
      this.buildSubtabButton('布局', 'layout')
      this.buildSubtabButton('事件', 'listeners')
    }
    .width('100%')
    .height(32)
    .backgroundColor(ELEMENT_INSPECTION_DOCK_BAR_COLOR)
    .border({ width: { bottom: 1 }, color: ELEMENT_INSPECTION_DOCK_LINE_COLOR })
  }

  @Builder
  private buildSubtabButton(label: string, subtab: ElementInspectionDockSubtab) {
    Button(label)
      .type(ButtonType.Normal)
      .height(32)
      .fontSize(12)
      .fontColor(this.subtab === subtab ? '#FFFFFF' : ELEMENT_INSPECTION_DOCK_DIM_COLOR)
      .backgroundColor(Color.Transparent)
      .padding({ left: 10, right: 10 })
      .border({
        width: { bottom: 2 },
        color: this.subtab === subtab ? ELEMENT_INSPECTION_DOCK_BLUE_COLOR : Color.Transparent
      })
      .onClick(() => {
        this.subtab = subtab;
      })
  }

  @Builder
  private buildComputedPane() {
    Column() {
      this.buildBoxModel()
      Scroll() {
        Column() {
        TextInput({ placeholder: '过滤', text: this.filterText })
          .width('100%')
          .height(28)
          .margin({ left: 10, right: 10, top: 8, bottom: 6 })
          .fontSize(12)
          .fontColor(ELEMENT_INSPECTION_DOCK_TEXT_COLOR)
          .placeholderColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
          .backgroundColor(ELEMENT_INSPECTION_DOCK_BACKGROUND_COLOR)
          .onChange((value: string) => {
            this.filterText = value;
          })
        if (this.presentation.node === undefined) {
          Text('还没有选中元素。点击页面，或点击上面的树。')
            .width('100%')
            .fontSize(12)
            .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
            .padding(12)
        }
        ForEach(this.resolveVisibleComputed(), (property: ElementInspectionComputedProperty) => {
          this.buildComputedRow(property)
        }, (property: ElementInspectionComputedProperty) => `${property.name}:${property.value}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private buildStylesPane() {
    Scroll() {
      Column() {
        Text('只读。这次不能改样式。')
          .width('100%')
          .fontSize(12)
          .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
          .padding({ left: 12, right: 12, top: 12, bottom: 4 })
        ForEach(this.presentation.computed, (property: ElementInspectionComputedProperty) => {
          Text() {
            Span(property.name)
              .fontColor(ELEMENT_INSPECTION_DOCK_BLUE_COLOR)
            Span(': ')
              .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
            Span(property.value)
              .fontColor('#ce9178')
            Span(';')
              .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
          }
          .width('100%')
          .fontFamily('monospace')
          .fontSize(12)
          .padding({ left: 12, right: 12, top: 2, bottom: 2 })
        }, (property: ElementInspectionComputedProperty) => `style:${property.name}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .align(Alignment.TopStart)
    .scrollBar(BarState.Off)
  }

  @Builder
  private buildBoxModel() {
    Column() {
      Text('margin')
        .fontSize(11)
        .fontColor('#f6e3c4')
        .height(16)
      Text(this.formatBox(this.presentation.box?.marginTop))
        .fontSize(11)
        .fontColor('#f6e3c4')
        .height(16)
      Row() {
        Text(this.formatBox(this.presentation.box?.marginLeft))
          .fontSize(11)
          .fontColor('#f6e3c4')
          .width(40)
          .textAlign(TextAlign.Center)
          .flexShrink(0)
        Column() {
          Text('border')
            .fontSize(11)
            .fontColor('#f3ddc0')
            .height(16)
          Text(this.formatBox(this.presentation.box?.borderTop))
            .fontSize(10)
            .fontColor('#f3ddc0')
            .height(16)
          Row() {
            Text(this.formatBox(this.presentation.box?.borderLeft))
              .fontSize(10)
              .fontColor('#f3ddc0')
              .width(32)
              .height(36)
              .textAlign(TextAlign.Center)
              .flexShrink(0)
            Column() {
              Text('padding')
                .fontSize(11)
                .fontColor('#e7f3c4')
                .height(16)
              Text(this.formatBox(this.presentation.box?.paddingTop))
                .fontSize(10)
                .fontColor('#e7f3c4')
                .height(16)
              Text(this.resolveContentSize())
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
                .backgroundColor('#5b8def')
                .borderRadius(2)
                .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                .constraintSize({ minWidth: 88, minHeight: 28 })
                .textAlign(TextAlign.Center)
              Text(this.formatBox(this.presentation.box?.paddingBottom))
                .fontSize(10)
                .fontColor('#e7f3c4')
                .height(16)
            }
            .backgroundColor('#4d5c32')
            .border({ width: 1, color: '#d5e08a', style: BorderStyle.Dashed })
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .constraintSize({ minHeight: 88 })
            .flexShrink(0)
            .alignItems(HorizontalAlign.Center)
            Text(this.formatBox(this.presentation.box?.borderRight))
              .fontSize(10)
              .fontColor('#f3ddc0')
              .width(32)
              .height(36)
              .textAlign(TextAlign.Center)
              .flexShrink(0)
          }
          .constraintSize({ minHeight: 96 })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          Text(this.formatBox(this.presentation.box?.borderBottom))
            .fontSize(10)
            .fontColor('#f3ddc0')
            .height(16)
        }
        .layoutWeight(1)
        .constraintSize({ minHeight: 148 })
        .flexShrink(0)
        .backgroundColor('#8a6234')
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .alignItems(HorizontalAlign.Center)
        Text(this.formatBox(this.presentation.box?.marginRight))
          .fontSize(11)
          .fontColor('#f6e3c4')
          .width(40)
          .textAlign(TextAlign.Center)
          .flexShrink(0)
      }
      .width('100%')
      .constraintSize({ minHeight: 156 })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      Text(this.formatBox(this.presentation.box?.marginBottom))
        .fontSize(11)
        .fontColor('#f6e3c4')
        .height(16)
    }
    .width('100%')
    .flexShrink(0)
    .constraintSize({ minHeight: 196 })
    .backgroundColor('#6b4a28')
    .border({ width: 1, color: '#e0b07a', style: BorderStyle.Dashed })
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .margin({ left: 8, right: 8, top: 8 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildComputedRow(property: ElementInspectionComputedProperty) {
    Row() {
      Column()
        .width(12)
        .height(12)
        .borderRadius(2)
        .backgroundColor(this.resolveSwatch(property.value))
        .border({ width: 1, color: '#5f6368' })
        .margin({ right: 8 })
      Text(property.name)
        .layoutWeight(1)
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor(ELEMENT_INSPECTION_DOCK_BLUE_COLOR)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(property.value)
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor(ELEMENT_INSPECTION_DOCK_TEXT_COLOR)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '46%' })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 2, bottom: 2 })
    .alignItems(VerticalAlign.Center)
  }

  private handlePresentationChanged(): void {
    this.applyOutlineDraft();
    let selectedIndex = -1;
    for (let index = 0; index < this.presentation.outline.length; index += 1) {
      if (this.presentation.outline[index].selected) {
        selectedIndex = index;
        break;
      }
    }
    if (selectedIndex < 0) {
      return;
    }
    try {
      this.treeScroller.scrollTo({
        xOffset: 0,
        yOffset: Math.max(0, selectedIndex * ELEMENT_INSPECTION_DOCK_ROW_HEIGHT_VP - 48),
        animation: false
      });
    } catch (_error) {
    }
  }

  private updateOutlineMenuHost(area: Area): void {
    const widthVp = Number(area.width);
    const heightVp = Number(area.height);
    const globalXVp = Number(area.globalPosition.x);
    const globalYVp = Number(area.globalPosition.y);
    if (Number.isFinite(widthVp) && widthVp > 0) {
      this.outlineMenuHostWidthVp = widthVp;
    }
    if (Number.isFinite(heightVp) && heightVp > 0) {
      this.outlineMenuHostHeightVp = heightVp;
    }
    if (Number.isFinite(globalXVp)) {
      this.outlineMenuHostGlobalXVp = globalXVp;
    }
    if (Number.isFinite(globalYVp)) {
      this.outlineMenuHostGlobalYVp = globalYVp;
    }
  }

  private openOutlineMenu(node: ElementInspectionOutlineNode, event: MouseEvent): void {
    if (this.presentation.busy) {
      return;
    }
    this.onSelectOutline(node.path);
    this.outlineMenuPath = node.path;
    this.outlineMenuEntries = this.buildOutlineMenuEntries(node);
    if (this.outlineMenuHostWidthVp <= 0) {
      this.outlineMenuHostWidthVp = Math.max(1, this.panelWidthVp);
    }
    if (this.outlineMenuHostHeightVp <= 0) {
      this.outlineMenuHostHeightVp = 640;
    }
    this.outlineMenuAnchorXVp = event.windowX - this.outlineMenuHostGlobalXVp;
    this.outlineMenuAnchorYVp = event.windowY - this.outlineMenuHostGlobalYVp;
    this.outlineMenuVisible = true;
  }

  private dismissOutlineMenu(): void {
    this.outlineMenuVisible = false;
    this.outlineMenuPath = '';
  }

  private handleOutlineMenuSelect(key: string): void {
    const path = this.outlineMenuPath;
    this.dismissOutlineMenu();
    if (path.length === 0 || this.presentation.busy) {
      return;
    }
    if (key === 'add_attribute') {
      this.openAttributeEditor(path, '添加属性');
      return;
    }
    if (key === 'edit_attribute') {
      this.openAttributeEditor(path, '编辑属性');
      return;
    }
    if (key === 'edit_html') {
      this.openHtmlEditor(path);
      return;
    }
    this.emitOutlineCommand(key, path, '', '');
  }

  private buildOutlineMenuEntries(node: ElementInspectionOutlineNode): ElementInspectionOutlineMenuEntry[] {
    const busy = this.presentation.busy;
    const protectedNode = this.isProtectedOutlineNode(node);
    const htmlRoot = node.tagName === 'html';
    const entries: ElementInspectionOutlineMenuEntry[] = [];
    entries.push({ key: 'add_attribute', label: '添加属性', enabled: !busy, group: 0 });
    entries.push({ key: 'edit_attribute', label: '编辑属性', enabled: !busy, group: 0 });
    entries.push({ key: 'edit_html', label: '编辑为 HTML', enabled: !busy && !htmlRoot, group: 0 });
    entries.push({ key: 'duplicate', label: '复制元素', enabled: !busy && !protectedNode, group: 0 });
    entries.push({ key: 'delete', label: '删除元素', enabled: !busy && !protectedNode, group: 0 });
    entries.push({ key: 'cut', label: '剪切', enabled: !busy && !protectedNode, group: 1 });
    entries.push({ key: 'copy_selector', label: '复制选择器', enabled: !busy, group: 1 });
    entries.push({ key: 'copy_js_path', label: '复制 JS 路径', enabled: !busy, group: 1 });
    entries.push({ key: 'copy_xpath', label: '复制 XPath', enabled: !busy, group: 1 });
    entries.push({ key: 'copy_html', label: '复制 outerHTML', enabled: !busy, group: 1 });
    entries.push({ key: 'paste', label: '粘贴', enabled: !busy && !htmlRoot, group: 1 });
    entries.push({
      key: 'hide',
      label: node.hidden === true ? '显示元素' : '隐藏元素',
      enabled: !busy && !protectedNode,
      group: 2
    });
    entries.push({ key: 'scroll_into_view', label: '滚动到可视区域', enabled: !busy, group: 2 });
    entries.push({ key: 'focus', label: '聚焦', enabled: !busy, group: 2 });
    entries.push({ key: 'store_global', label: '存为全局变量', enabled: !busy, group: 2 });
    return entries;
  }

  private isProtectedOutlineNode(node: ElementInspectionOutlineNode): boolean {
    return node.tagName === 'html' || node.tagName === 'head' || node.tagName === 'body';
  }

  private emitOutlineCommand(kind: string, path: string, name: string, value: string): void {
    const command: ElementInspectionOutlineCommand = {
      kind: kind,
      path: path,
      name: name,
      value: value,
      requestId: 0
    };
    this.onOutlineCommand(command);
  }

  private openAttributeEditor(path: string, title: string): void {
    this.editorKind = 'attribute';
    this.editorTitle = title;
    this.editorPath = path;
    this.editorName = '';
    this.editorText = '';
    this.editorBusy = false;
    this.editorVisible = true;
  }

  private openHtmlEditor(path: string): void {
    this.editorRequestId += 1;
    this.editorKind = 'html';
    this.editorTitle = '编辑为 HTML';
    this.editorPath = path;
    this.editorName = '';
    this.editorText = '';
    this.editorBusy = true;
    this.editorVisible = true;
    const command: ElementInspectionOutlineCommand = {
      kind: 'read_html',
      path: path,
      name: '',
      value: '',
      requestId: this.editorRequestId
    };
    this.onOutlineCommand(command);
  }

  private closeOutlineEditor(): void {
    this.editorVisible = false;
    this.editorBusy = false;
    this.editorText = '';
    this.editorName = '';
  }

  private canApplyOutlineEditor(): boolean {
    if (!this.editorVisible || this.editorBusy) {
      return false;
    }
    if (this.editorKind === 'html') {
      return this.editorText.trim().length > 0;
    }
    return this.editorName.trim().length > 0;
  }

  private applyOutlineEditor(): void {
    if (!this.canApplyOutlineEditor()) {
      return;
    }
    if (this.editorKind === 'html') {
      this.emitOutlineCommand('replace_html', this.editorPath, '', this.editorText);
    } else {
      this.emitOutlineCommand('set_attribute', this.editorPath, this.editorName.trim(), this.editorText);
    }
    this.closeOutlineEditor();
  }

  private applyOutlineDraft(): void {
    const draft = this.presentation.outlineDraft;
    if (draft === undefined || !this.editorVisible || this.editorKind !== 'html' ||
      draft.requestId !== this.editorRequestId || draft.requestId === this.appliedEditorRequestId) {
      return;
    }
    this.appliedEditorRequestId = draft.requestId;
    this.editorBusy = false;
    if (!draft.ready) {
      this.closeOutlineEditor();
      return;
    }
    this.editorText = draft.text;
  }

  @Builder
  private buildConsolePane() {
    Column() {
      Row() {
        this.buildFilterButton('全部', 'all')
        this.buildFilterButton('信息', 'info')
        this.buildFilterButton('警告', 'warn')
        this.buildFilterButton('错误', 'error')
        Blank()
        Button('清空')
          .type(ButtonType.Normal)
          .height(24)
          .fontSize(11)
          .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.onClearConsole();
          })
      }
      .width('100%')
      .height(32)
      .padding({ left: 8, right: 8 })

      Scroll() {
        Column() {
          if (this.filteredLogs().length === 0) {
            Text('还没有日志。页面里的 console 输出和未捕获错误会出现在这里。')
              .width('100%')
              .fontSize(12)
              .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
              .padding(12)
          }
          ForEach(this.filteredLogs(), (entry: ElementInspectionConsoleEntry) => {
            Text(entry.text)
              .width('100%')
              .fontSize(12)
              .fontColor(this.consoleColor(entry.level))
              .padding({ left: 12, right: 12, top: 3, bottom: 3 })
          }, (entry: ElementInspectionConsoleEntry, index: number) => `${entry.time}:${index}:${entry.text}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)

      Row() {
        TextInput({ text: this.consoleInput, placeholder: '执行 JavaScript' })
          .layoutWeight(1)
          .height(28)
          .fontSize(12)
          .fontColor(ELEMENT_INSPECTION_DOCK_TEXT_COLOR)
          .backgroundColor(ELEMENT_INSPECTION_DOCK_BAR_COLOR)
          .placeholderColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
          .onChange((value: string) => {
            this.consoleInput = value;
          })
        Button('执行')
          .type(ButtonType.Normal)
          .width(52)
          .height(28)
          .fontSize(12)
          .fontColor('#FFFFFF')
          .backgroundColor(ELEMENT_INSPECTION_DOCK_SELECT_COLOR)
          .margin({ left: 8 })
          .onClick(() => {
            this.submitConsole();
          })
      }
      .width('100%')
      .padding(8)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private buildFilterButton(label: string, filter: string) {
    Button(label)
      .type(ButtonType.Normal)
      .height(22)
      .fontSize(11)
      .fontColor(this.consoleFilter === filter ? '#FFFFFF' : ELEMENT_INSPECTION_DOCK_DIM_COLOR)
      .backgroundColor(this.consoleFilter === filter ?
        ELEMENT_INSPECTION_DOCK_SELECT_COLOR : Color.Transparent)
      .margin({ right: 4 })
      .onClick(() => {
        this.consoleFilter = filter;
      })
  }

  @Builder
  private buildNetworkPane() {
    Scroll() {
      Column() {
        if (this.presentation.network.length === 0) {
          Text('打开审查之后的新请求会出现在这里。')
            .width('100%')
            .fontSize(12)
            .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
            .padding(12)
        }
        ForEach(this.presentation.network, (entry: ElementInspectionNetworkEntry) => {
          Column() {
            Row() {
              Text(entry.method)
                .fontSize(11)
                .fontColor(ELEMENT_INSPECTION_DOCK_BLUE_COLOR)
                .width(42)
              Text(entry.status > 0 ? String(entry.status) : '失败')
                .fontSize(11)
                .fontColor(entry.status >= 400 || entry.status === 0 ? '#f28b82' : '#81c995')
                .width(42)
              Text(entry.durationMs > 0 ? `${entry.durationMs} ms` : '')
                .fontSize(11)
                .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
                .layoutWeight(1)
              if (entry.size > 0) {
                Text(this.formatBytes(entry.size))
                  .fontSize(11)
                  .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
              }
            }
            .width('100%')
            Text(entry.url)
              .width('100%')
              .fontSize(12)
              .fontColor(ELEMENT_INSPECTION_DOCK_TEXT_COLOR)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (entry.type.length > 0) {
              Text(entry.type)
                .fontSize(11)
                .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .border({ width: { bottom: 1 }, color: ELEMENT_INSPECTION_DOCK_LINE_COLOR })
        }, (entry: ElementInspectionNetworkEntry, index: number) =>
          `${entry.startedAt}:${index}:${entry.url}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .align(Alignment.TopStart)
    .scrollBar(BarState.Auto)
  }

  @Builder
  private buildSourcesPane() {
    Column() {
      Text(this.pageInfoText())
        .width('100%')
        .fontSize(11)
        .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
        .padding({ left: 12, right: 12, top: 8, bottom: 4 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Scroll() {
        Column() {
          if (this.presentation.sources.length === 0) {
            Text('还没有可显示的源代码。')
              .width('100%')
              .fontSize(12)
              .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
              .padding(12)
          }
          ForEach(this.presentation.sources, (entry: ElementInspectionSourceEntry) => {
            Text(entry.name)
              .width('100%')
              .fontSize(12)
              .fontColor(this.selectedSourceId === entry.id ?
                ELEMENT_INSPECTION_DOCK_BLUE_COLOR : ELEMENT_INSPECTION_DOCK_TEXT_COLOR)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .onClick(() => {
                this.selectedSourceId = entry.id;
                this.onReadSource(entry.id);
              })
          }, (entry: ElementInspectionSourceEntry) => entry.id)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(0.7)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)

      Scroll() {
        Text(this.sourcePreviewText())
          .width('100%')
          .fontSize(11)
          .fontColor(ELEMENT_INSPECTION_DOCK_TEXT_COLOR)
          .padding(12)
      }
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
      .border({ width: { top: 1 }, color: ELEMENT_INSPECTION_DOCK_LINE_COLOR })
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private buildListenersPane() {
    Scroll() {
      Column() {
        if (this.presentation.listeners.length === 0) {
          Text('没有读到内联事件。审查开始之后新绑定的监听会出现在这里。')
            .width('100%')
            .fontSize(12)
            .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
            .padding(12)
        }
        ForEach(this.presentation.listeners, (entry: ElementInspectionListenerEntry) => {
          Text(`${entry.type}${entry.capture ? ' · capture' : ''} · ${entry.source === 'attribute' ? '属性' : '监听'}`)
            .width('100%')
            .fontSize(12)
            .fontColor(ELEMENT_INSPECTION_DOCK_TEXT_COLOR)
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        }, (entry: ElementInspectionListenerEntry, index: number) => `${entry.type}:${entry.source}:${index}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .align(Alignment.TopStart)
  }

  private submitConsole(): void {
    const expression = this.consoleInput.trim();
    if (expression.length === 0) {
      return;
    }
    this.onEvaluateConsole(expression);
    this.consoleInput = '';
  }

  private filteredLogs(): ElementInspectionConsoleEntry[] {
    const result: ElementInspectionConsoleEntry[] = [];
    this.presentation.logs.forEach((entry: ElementInspectionConsoleEntry): void => {
      if (this.consoleFilter === 'all' ||
        (this.consoleFilter === 'info' && (entry.level === 'log' || entry.level === 'info' || entry.level === 'debug')) ||
        entry.level === this.consoleFilter) {
        result.push(entry);
      }
    });
    return result;
  }

  private consoleColor(level: string): string {
    if (level === 'error') {
      return '#f28b82';
    }
    if (level === 'warn') {
      return '#fdd663';
    }
    if (level === 'info') {
      return ELEMENT_INSPECTION_DOCK_BLUE_COLOR;
    }
    return ELEMENT_INSPECTION_DOCK_TEXT_COLOR;
  }

  private formatBytes(size: number): string {
    if (size < 1024) {
      return `${size} B`;
    }
    const kilobytes = Math.round(size / 102.4) / 10;
    return `${kilobytes} KB`;
  }

  private pageInfoText(): string {
    const info = this.presentation.pageInfo;
    if (info === undefined) {
      return '';
    }
    const title = info.title.length > 0 ? info.title : info.url;
    return `${title}  ·  ${info.viewportWidth} × ${info.viewportHeight}  ·  ${info.devicePixelRatio}x`;
  }

  private sourcePreviewText(): string {
    const preview = this.presentation.sourcePreview;
    if (preview === undefined || preview.id !== this.selectedSourceId) {
      return '选择一项查看源代码。跨域脚本和样式只能显示地址。';
    }
    if (preview.reason === 'external_script' || preview.reason === 'external_style') {
      return `受跨域限制，只显示地址：\n${preview.text}`;
    }
    if (preview.text.length === 0) {
      return '无法读取这段源代码。';
    }
    return preview.text;
  }

  private resolveCrumbPrefix(): string {
    const breadcrumb = this.presentation.node?.breadcrumb ?? [];
    if (breadcrumb.length <= 1) {
      return breadcrumb.length === 0 ? '未选择' : '';
    }
    return breadcrumb.slice(0, breadcrumb.length - 1).join(' › ');
  }

  private resolveCrumbCurrent(): string {
    const breadcrumb = this.presentation.node?.breadcrumb ?? [];
    if (breadcrumb.length === 0) {
      return '';
    }
    return breadcrumb[breadcrumb.length - 1];
  }

  private resolveContentSize(): string {
    const box: ElementInspectionBoxModel | undefined = this.presentation.box;
    if (box === undefined) {
      return '—';
    }
    return `${this.formatBox(box.contentWidth)} × ${this.formatBox(box.contentHeight)}`;
  }

  private resolveVisibleComputed(): ElementInspectionComputedProperty[] {
    const query = this.filterText.trim().toLowerCase();
    const result: ElementInspectionComputedProperty[] = [];
    this.presentation.computed.forEach((property: ElementInspectionComputedProperty): void => {
      if (query.length === 0 || property.name.toLowerCase().indexOf(query) >= 0 ||
        property.value.toLowerCase().indexOf(query) >= 0) {
        result.push(property);
      }
    });
    return result;
  }

  private resolveSwatch(value: string): string {
    const normalized = value.trim().toLowerCase();
    if (normalized.indexOf('#') === 0 || normalized.indexOf('rgb') === 0 || normalized.indexOf('hsl') === 0) {
      return value;
    }
    return 'transparent';
  }

  private formatBox(value: number | undefined): string {
    if (value === undefined || !Number.isFinite(value)) {
      return '0';
    }
    const rounded = Math.round(value * 10) / 10;
    return Number.isInteger(rounded) ? String(Math.trunc(rounded)) : rounded.toFixed(1);
  }

  private beginSplitterDrag(startWidthVp: number): void {
    this.panStartWidthVp = startWidthVp;
    this.mouseDragStartWidthVp = startWidthVp;
    this.splitterDragging = true;
    this.splitterActive = true;
    this.setSplitterCursor(true);
  }

  private endSplitterDrag(): void {
    this.splitterDragging = false;
    this.splitterActive = false;
    this.panResizeActive = false;
    this.setSplitterCursor(false);
  }

  private handleSplitterMouse(event: MouseEvent, fromCapture: boolean): void {
    if (event.action === MouseAction.Press && event.button === MouseButton.Left) {
      this.mouseDragStartWindowXPx = event.windowX;
      this.panResizeActive = false;
      this.beginSplitterDrag(this.panelWidthVp);
      return;
    }
    if (event.action === MouseAction.Hover && !this.splitterDragging) {
      this.splitterActive = true;
      this.setSplitterCursor(true);
      return;
    }
    if (event.action === MouseAction.Release || event.action === MouseAction.CANCEL) {
      if (this.splitterDragging && (event.button === MouseButton.Left || fromCapture)) {
        this.endSplitterDrag();
      }
      return;
    }
    if (event.action === MouseAction.Move && this.splitterDragging && !this.panResizeActive) {
      const deltaVp = this.getUIContext().px2vp(event.windowX - this.mouseDragStartWindowXPx);
      this.panelWidthVp = this.clampWidth(this.mouseDragStartWidthVp - deltaVp);
    }
  }

  private setSplitterCursor(resize: boolean): void {
    try {
      cursorControl.setCursor(resize ?
        pointer.PointerStyle.RESIZE_LEFT_RIGHT : pointer.PointerStyle.DEFAULT);
    } catch (_error) {
    }
  }

  private clampWidth(width: number): number {
    const available = Number.isFinite(this.maxWidthVp) && this.maxWidthVp > 0 ? this.maxWidthVp : 1200;
    const max = Math.max(
      ELEMENT_INSPECTION_DOCK_MIN_WIDTH_VP,
      Math.min(ELEMENT_INSPECTION_DOCK_MAX_WIDTH_VP, Math.round(available * 0.75))
    );
    return Math.min(max, Math.max(ELEMENT_INSPECTION_DOCK_MIN_WIDTH_VP, Math.round(width)));
  }
}
