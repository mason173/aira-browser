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
  ElementInspectionRuntimeAttribute,
  ElementInspectionSecuritySummary,
  ElementInspectionSourceEntry,
  ElementInspectionStorageEntry
} from '../../../services/web/ElementInspectionRuntimeScriptService';
import { AiraIcon } from '../common/AiraIcon';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { KeyCode, pointer } from '@kit.InputKit';

const ELEMENT_INSPECTION_DOCK_DEFAULT_WIDTH_VP: number = 440;
const ELEMENT_INSPECTION_DOCK_MIN_WIDTH_VP: number = 240;
const ELEMENT_INSPECTION_DOCK_MAX_WIDTH_VP: number = 1100;
const ELEMENT_INSPECTION_DOCK_SPLITTER_HIT_VP: number = 12;
const ELEMENT_INSPECTION_DOCK_ROW_HEIGHT_VP: number = 22;
const ELEMENT_INSPECTION_TREE_FOCUS_ID: string = 'aira-element-inspection-tree';
const ELEMENT_INSPECTION_INLINE_EDIT_ID: string = 'aira-element-inspection-inline-edit';
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

type ElementInspectionDockTab = 'elements' | 'console' | 'sources' | 'network' | 'application' | 'security';

interface ElementInspectionDismissRegion {
  x: number | string;
  y: number | string;
  width: number | string;
  height: number | string;
}
type ElementInspectionDockSubtab = 'styles' | 'computed' | 'layout' | 'listeners';

@Component
export struct ElementInspectionDock {
  @Prop @Watch('handlePresentationChanged') presentation: ElementInspectionPresentation;
  @Prop @Watch('handleOutlineMenuDismissSerial') outlineMenuDismissSerial: number = 0;
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
  @State private hoveredTwistyPath: string = '';
  @State private selectedOutlineRowKey: string = '';
  @State private outlineTreeWidthVp: number = 0;
  @State private outlineTreeHeightVp: number = 0;
  private pendingOutlinePath: string = '';
  private outlineClickAtMs: number = 0;
  private outlineClickKey: string = '';
  private inlineEditCancel: boolean = false;
  private inlineEditCtrl: boolean = false;
  private inlineEditArmed: boolean = false;
  @State private editorVisible: boolean = false;
  @State private editorKind: string = '';
  @State private editorTitle: string = '';
  @State private editorPath: string = '';
  @State private editorText: string = '';
  @State private editorName: string = '';
  @State private editorBusy: boolean = false;
  @State private editorAttributes: ElementInspectionRuntimeAttribute[] = [];
  @State private editorSelectedAttribute: string = '';
  @State private outlineMenuVisible: boolean = false;
  @State private outlineMenuEntries: ElementInspectionOutlineMenuEntry[] = [];
  @State private outlineMenuAnchorXVp: number = 0;
  @State private outlineMenuAnchorYVp: number = 0;
  @State private outlineMenuHostWidthVp: number = 0;
  @State private outlineMenuHostHeightVp: number = 0;
  private outlineMenuHostGlobalXVp: number = 0;
  private outlineMenuHostGlobalYVp: number = 0;
  private outlineMenuPath: string = '';
  private outlineMenuOpenedAtMs: number = 0;
  private editorRequestId: number = 0;
  private appliedEditorRequestId: number = -1;
  private panStartWidthVp: number = ELEMENT_INSPECTION_DOCK_DEFAULT_WIDTH_VP;
  private panResizeActive: boolean = false;
  private mouseDragStartWindowXPx: number = 0;
  private mouseDragStartWidthVp: number = ELEMENT_INSPECTION_DOCK_DEFAULT_WIDTH_VP;
  private splitterHovered: boolean = false;
  private pointerWindowId: number = -1;
  private pointerWindowResolving: boolean = false;
  private splitterCursorTimer: number = -1;
  private treeScroller: Scroller = new Scroller();
  private scrolledOutlinePath: string = '';
  private outlineToggleAtMs: number = 0;
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
  onOutlineMenuVisibleChange: (visible: boolean) => void = (_visible: boolean): void => {};

  aboutToAppear(): void {
    this.rememberPointerWindowId();
  }

  aboutToDisappear(): void {
    this.splitterHovered = false;
    this.splitterDragging = false;
    this.releaseSplitterCursor();
    this.onOutlineMenuVisibleChange(false);
  }

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
          } else if (this.tab === 'application') {
            this.buildApplicationPane()
          } else if (this.tab === 'security') {
            this.buildSecurityPane()
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

        if (this.editorVisible && this.editorKind !== 'html') {
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
    .responseRegion(this.outlineMenuDismissRegion())
    .onMouse((event: MouseEvent) => {
      if (!this.outlineMenuVisible || event.action !== MouseAction.Press) {
        return;
      }
      event.stopPropagation();
      this.dismissOutlineMenuFromPointer();
    })
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
    .backgroundColor(this.splitterActive ? '#1a73e822' : '#01000000')
    .hitTestBehavior(HitTestMode.Default)
    .responseRegion({ x: -8, y: 0, width: 28, height: '100%' })
    .accessibilityText('拖动调整网页和审查元素窗口的宽度')
    .onHover((isHover: boolean) => {
      this.splitterHovered = isHover;
      if (this.splitterDragging) {
        this.setSplitterCursor(true);
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

      Scroll() {
        Row() {
          this.buildTabButton('元素', 'elements')
          this.buildTabButton('控制台', 'console')
          this.buildTabButton('源代码', 'sources')
          this.buildTabButton('网络', 'network')
          this.buildTabButton('应用', 'application')
          this.buildTabButton('安全', 'security')
        }
        .height(40)
        .alignItems(VerticalAlign.Center)
      }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .height(40)
        .align(Alignment.Start)

      Blank().width(4)

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
        }, (node: ElementInspectionOutlineNode) =>
          `${this.outlineRowKey(node)}:${this.isOutlineRowHighlighted(node) ? '1' : '0'}:${node.expanded === true ? '1' : '0'}:${Math.round(this.outlineTreeWidthVp)}:${this.isInlineHtmlEditing(node) ? 'edit' : 'view'}`)
        if (this.presentation.node === undefined && this.presentation.outline.length > 0) {
          Text(this.presentation.helperText)
            .width('100%')
            .fontSize(12)
            .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        }
      }
      .width('100%')
      .constraintSize({ minWidth: '100%' })
      .alignItems(HorizontalAlign.Start)
    }
    .id(ELEMENT_INSPECTION_TREE_FOCUS_ID)
    .focusable(true)
    .layoutWeight(1.15)
    .width('100%')
    .align(Alignment.TopStart)
    .scrollBar(BarState.Auto)
    .onAreaChange((_oldArea: Area, area: Area) => {
      const widthVp = Number(area.width);
      const heightVp = Number(area.height);
      if (Number.isFinite(widthVp) && widthVp > 0 && Math.abs(widthVp - this.outlineTreeWidthVp) >= 1) {
        this.outlineTreeWidthVp = widthVp;
      }
      if (Number.isFinite(heightVp) && heightVp > 0 && Math.abs(heightVp - this.outlineTreeHeightVp) >= 1) {
        this.outlineTreeHeightVp = heightVp;
      }
    })
    .onKeyEvent((event: KeyEvent): boolean => this.handleOutlineKey(event))

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
      if (this.outlineRowKind(node) === 'element' && node.childCount > 0) {
        Text(node.expanded === true ? '▾' : '▸')
          .width(22)
          .height(ELEMENT_INSPECTION_DOCK_ROW_HEIGHT_VP)
          .fontSize(10)
          .textAlign(TextAlign.Center)
          .fontColor(this.outlineInk(node, ELEMENT_INSPECTION_DOCK_DIM_COLOR))
          .backgroundColor(this.hoveredTwistyPath === node.path ? '#3c4043' : Color.Transparent)
          .borderRadius(2)
          .onHover((isHover: boolean) => {
            this.hoveredTwistyPath = isHover ? node.path : '';
          })
          .onClick(() => {
            this.focusOutlineTree();
            this.toggleOutlineNode(node);
          })
      } else {
        Text('')
          .width(22)
          .height(ELEMENT_INSPECTION_DOCK_ROW_HEIGHT_VP)
      }
      if (this.isInlineHtmlEditing(node)) {
        this.buildInlineHtmlEditor()
      } else {
        this.buildOutlineMarkup(node)
      }
    }
    .width(this.outlineTreeWidthVp > 0 ? this.outlineTreeWidthVp : '100%')
    .constraintSize({ minWidth: '100%' })
    .height(this.isInlineHtmlEditing(node) ? 112 : ELEMENT_INSPECTION_DOCK_ROW_HEIGHT_VP)
    .padding({ left: 2 + node.depth * 14, right: 8 })
    .backgroundColor(this.isOutlineRowHighlighted(node) ? ELEMENT_INSPECTION_DOCK_SELECT_COLOR :
      (this.hoveredOutlinePath === this.outlineRowKey(node) ? '#35363a' : Color.Transparent))
    .alignItems(VerticalAlign.Center)
    .onHover((isHover: boolean) => {
      if (isHover) {
        this.hoveredOutlinePath = this.outlineRowKey(node);
        if (this.outlineRowKind(node) !== 'more') {
          this.onPreviewOutline(node.path);
        }
        return;
      }
      if (this.hoveredOutlinePath === this.outlineRowKey(node)) {
        this.hoveredOutlinePath = '';
      }
      this.onClearOutlinePreview();
    })
    .onClick(() => {
      const rowKey = this.outlineRowKey(node);
      const now = Date.now();
      const doubleClick = rowKey === this.outlineClickKey && now - this.outlineClickAtMs < 350;
      this.outlineClickKey = rowKey;
      this.outlineClickAtMs = now;
      this.keepTreeOffset();
      this.focusOutlineTree();
      this.activateOutlineRow(node);
      if (doubleClick && this.outlineRowKind(node) === 'element' &&
        Date.now() - this.outlineToggleAtMs >= 400) {
        this.beginInlineHtmlEdit(node);
      }
    })
    .onMouse((event: MouseEvent) => {
      if (event.button !== MouseButton.Right || event.action !== MouseAction.Press ||
        this.outlineRowKind(node) === 'more') {
        return;
      }
      event.stopPropagation();
      this.openOutlineMenu(node, event);
    })
  }

  @Builder
  private buildInlineHtmlEditor() {
    Column() {
      if (this.editorBusy) {
        Text('正在读取代码…')
          .width('100%')
          .fontSize(12)
          .fontColor('#FFFFFF')
      }
      TextArea({
        text: this.editorText,
        placeholder: '编辑这段 HTML'
      })
        .id(ELEMENT_INSPECTION_INLINE_EDIT_ID)
        .visibility(this.editorBusy ? Visibility.None : Visibility.Visible)
        .width('100%')
        .height(72)
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor(ELEMENT_INSPECTION_DOCK_TEXT_COLOR)
        .backgroundColor(ELEMENT_INSPECTION_DOCK_BAR_COLOR)
        .enabled(!this.editorBusy)
        .onChange((value: string) => {
          if (!this.editorBusy) {
            this.editorText = value;
          }
        })
        .onBlur(() => {
          this.commitInlineHtmlEdit(true);
        })
        .onKeyEvent((event: KeyEvent): boolean => {
          if (event.keyCode === KeyCode.KEYCODE_CTRL_LEFT || event.keyCode === KeyCode.KEYCODE_CTRL_RIGHT) {
            this.inlineEditCtrl = event.type === KeyType.Down;
            return false;
          }
          if (event.type !== KeyType.Down) {
            return false;
          }
          if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
            this.cancelInlineHtmlEdit();
            return true;
          }
          if ((event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_NUMPAD_ENTER) &&
            (this.inlineEditCtrl || event.metaKey === 1)) {
            this.commitInlineHtmlEdit(false);
            return true;
          }
          return false;
        })
      Text('点外面或按 Ctrl+Enter 应用，Esc 取消。只改当前页面。')
        .width('100%')
        .fontSize(10)
        .fontColor('#FFFFFF')
        .opacity(0.8)
        .maxLines(1)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildOutlineMarkup(node: ElementInspectionOutlineNode) {
    if (this.outlineRowKind(node) === 'more') {
      Text(node.moreDirection === 'before' ? `↑ 还有 ${node.moreCount ?? 0} 个` : `↓ 还有 ${node.moreCount ?? 0} 个`)
        .layoutWeight(1)
        .fontFamily('monospace')
        .fontSize(12)
        .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    } else if (this.outlineRowKind(node) === 'close') {
      Text(`</${node.tagName}>`)
        .layoutWeight(1)
        .fontFamily('monospace')
        .fontSize(12)
        .fontColor(this.outlineInk(node, ELEMENT_INSPECTION_DOCK_TAG_COLOR))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    } else {
      Text() {
        Span('<')
          .fontColor(this.outlineInk(node, ELEMENT_INSPECTION_DOCK_TAG_COLOR))
        Span(node.tagName)
          .fontColor(this.outlineInk(node, ELEMENT_INSPECTION_DOCK_TAG_COLOR))
        if (node.elementId.length > 0) {
          Span(' id=')
            .fontColor(this.outlineInk(node, ELEMENT_INSPECTION_DOCK_ATTR_COLOR))
          Span(`"${node.elementId}"`)
            .fontColor(this.outlineInk(node, ELEMENT_INSPECTION_DOCK_STRING_COLOR))
        }
        if (node.classTokens.length > 0) {
          Span(' class=')
            .fontColor(this.outlineInk(node, ELEMENT_INSPECTION_DOCK_ATTR_COLOR))
          Span(`"${node.classTokens.join(' ')}"`)
            .fontColor(this.outlineInk(node, ELEMENT_INSPECTION_DOCK_STRING_COLOR))
        }
        Span('>')
          .fontColor(this.outlineInk(node, ELEMENT_INSPECTION_DOCK_TAG_COLOR))
        if (node.childCount > 0 && node.expanded !== true) {
          Span('…')
            .fontColor(this.outlineInk(node, ELEMENT_INSPECTION_DOCK_DIM_COLOR))
          Span(`</${node.tagName}>`)
            .fontColor(this.outlineInk(node, ELEMENT_INSPECTION_DOCK_TAG_COLOR))
        } else if (node.childCount === 0 && node.textPreview.length > 0) {
          Span(` ${node.textPreview}`)
            .fontColor(this.outlineInk(node, ELEMENT_INSPECTION_DOCK_DIM_COLOR))
          if (!this.isVoidOutlineTag(node.tagName)) {
            Span(`</${node.tagName}>`)
              .fontColor(this.outlineInk(node, ELEMENT_INSPECTION_DOCK_TAG_COLOR))
          }
        } else if (node.childCount === 0 && !this.isVoidOutlineTag(node.tagName)) {
          Span(`</${node.tagName}>`)
            .fontColor(this.outlineInk(node, ELEMENT_INSPECTION_DOCK_TAG_COLOR))
        }
      }
      .fontFamily('monospace')
      .fontSize(12)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .copyOption(CopyOptions.None)
      .layoutWeight(1)
    }
  }

  @Builder
  private buildOutlineMenuOverlay() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => {
          this.dismissOutlineMenu();
        })
        .onMouse((event: MouseEvent) => {
          event.stopPropagation();
          if (event.action === MouseAction.Press) {
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
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  private buildOutlineEditor() {
    Column() {
      Text(this.editorTitle)
        .width('100%')
        .fontSize(14)
        .fontColor(ELEMENT_INSPECTION_DOCK_TEXT_COLOR)
        .margin({ bottom: 8 })
      Text(this.resolveEditorHint())
        .width('100%')
        .fontSize(12)
        .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
        .margin({ bottom: 10 })
      if (this.editorKind === 'attribute_edit' && !this.editorBusy) {
        this.buildAttributeChoices()
      }
      if (this.editorKind === 'attribute' || this.editorKind === 'attribute_edit') {
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
        Text(this.editorKind === 'attribute_edit' ? '正在读取属性…' : '正在读取 HTML…')
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
  private buildAttributeChoices() {
    Column() {
      if (this.editorAttributes.length === 0) {
        Text('这个元素没有可编辑的属性。')
          .width('100%')
          .fontSize(12)
          .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
      } else {
        Scroll() {
          Column() {
            ForEach(this.editorAttributes, (attribute: ElementInspectionRuntimeAttribute, index: number) => {
              this.buildAttributeChoice(attribute)
            }, (attribute: ElementInspectionRuntimeAttribute, index: number) => `${index}:${attribute.name}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height(120)
        .scrollBar(BarState.Auto)
        .align(Alignment.TopStart)
      }
    }
    .width('100%')
    .margin({ bottom: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildAttributeChoice(attribute: ElementInspectionRuntimeAttribute) {
    Row() {
      Text(attribute.name)
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor(attribute.redacted ? ELEMENT_INSPECTION_DOCK_DIM_COLOR : ELEMENT_INSPECTION_DOCK_ATTR_COLOR)
        .maxLines(1)
      Text(attribute.redacted ? '已隐藏' : attribute.value)
        .layoutWeight(1)
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor(ELEMENT_INSPECTION_DOCK_STRING_COLOR)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 8 })
    }
    .width('100%')
    .height(28)
    .padding({ left: 8, right: 8 })
    .backgroundColor(this.editorSelectedAttribute === attribute.name && !attribute.redacted ?
      ELEMENT_INSPECTION_DOCK_SELECT_COLOR : Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (attribute.redacted) {
        return;
      }
      this.editorSelectedAttribute = attribute.name;
      this.editorName = attribute.name;
      this.editorText = attribute.value;
    })
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
          .width(32)
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
              .width(28)
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
                .width(80)
                .height(28)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .textAlign(TextAlign.Center)
              Text(this.formatBox(this.presentation.box?.paddingBottom))
                .fontSize(10)
                .fontColor('#e7f3c4')
                .height(16)
            }
            .width(96)
            .backgroundColor('#4d5c32')
            .border({ width: 1, color: '#d5e08a', style: BorderStyle.Dashed })
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .flexShrink(0)
            .alignItems(HorizontalAlign.Center)
            Text(this.formatBox(this.presentation.box?.borderRight))
              .fontSize(10)
              .fontColor('#f3ddc0')
              .width(28)
              .height(36)
              .textAlign(TextAlign.Center)
              .flexShrink(0)
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          Text(this.formatBox(this.presentation.box?.borderBottom))
            .fontSize(10)
            .fontColor('#f3ddc0')
            .height(16)
        }
        .width(168)
        .clip(true)
        .flexShrink(0)
        .backgroundColor('#8a6234')
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .alignItems(HorizontalAlign.Center)
        Text(this.formatBox(this.presentation.box?.marginRight))
          .fontSize(11)
          .fontColor('#f6e3c4')
          .width(32)
          .textAlign(TextAlign.Center)
          .flexShrink(0)
      }
      .width(232)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      Text(this.formatBox(this.presentation.box?.marginBottom))
        .fontSize(11)
        .fontColor('#f6e3c4')
        .height(16)
    }
    .width(248)
    .clip(true)
    .flexShrink(0)
    .alignSelf(ItemAlign.Center)
    .backgroundColor('#6b4a28')
    .border({ width: 1, color: '#e0b07a', style: BorderStyle.Dashed })
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .margin({ top: 8, bottom: 4 })
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
    if (!this.presentation.active || this.presentation.phase === 'starting' ||
      this.presentation.phase === 'closing') {
      this.pendingOutlinePath = '';
      this.selectedOutlineRowKey = '';
      this.dismissOutlineMenu();
      this.closeOutlineEditor();
    } else {
      this.syncOutlineSelectionFromPresentation();
    }
    this.applyOutlineDraft();
    let selectedPath = '';
    let selectedIndex = -1;
    for (let index = 0; index < this.presentation.outline.length; index += 1) {
      const node = this.presentation.outline[index];
      if (node.selected && this.outlineRowKind(node) === 'element') {
        selectedPath = node.path;
        selectedIndex = index;
        break;
      }
    }
    this.revealOutlineSelection(selectedIndex, selectedPath);
  }

  private revealOutlineSelection(selectedIndex: number, selectedPath: string): void {
    if (selectedIndex < 0 || selectedPath === this.scrolledOutlinePath) {
      return;
    }
    this.scrolledOutlinePath = selectedPath;
    const rowHeight = ELEMENT_INSPECTION_DOCK_ROW_HEIGHT_VP;
    const rowTop = selectedIndex * rowHeight;
    const rowBottom = rowTop + rowHeight;
    const viewHeight = this.outlineTreeHeightVp;
    if (viewHeight <= 0) {
      return;
    }
    let offsetY = 0;
    try {
      offsetY = this.treeScroller.currentOffset().yOffset;
    } catch (_error) {
      return;
    }
    const margin = 8;
    if (rowTop >= offsetY + margin && rowBottom <= offsetY + viewHeight - margin) {
      return;
    }
    let target = offsetY;
    if (rowTop < offsetY + margin) {
      target = Math.max(0, rowTop - margin);
    } else if (rowBottom > offsetY + viewHeight - margin) {
      target = Math.max(0, rowBottom - viewHeight + margin);
    }
    if (Math.abs(target - offsetY) < 1) {
      return;
    }
    try {
      this.treeScroller.scrollTo({ xOffset: 0, yOffset: target, animation: false });
    } catch (_error) {
    }
  }

  private outlineRowKind(node: ElementInspectionOutlineNode): string {
    return node.rowKind === 'close' || node.rowKind === 'more' ? node.rowKind : 'element';
  }

  private outlineRowKey(node: ElementInspectionOutlineNode): string {
    const direction = node.moreDirection === 'before' ? 'before' : 'after';
    return `${this.outlineRowKind(node)}:${direction}:${node.path}`;
  }

  private isOutlineRowHighlighted(node: ElementInspectionOutlineNode): boolean {
    return this.outlineRowKind(node) === 'element' && this.outlineRowKey(node) === this.selectedOutlineRowKey;
  }

  private outlineInk(node: ElementInspectionOutlineNode, color: string): string {
    return this.isOutlineRowHighlighted(node) ? '#FFFFFF' : color;
  }

  private rememberOutlineSelection(node: ElementInspectionOutlineNode): void {
    if (this.outlineRowKind(node) === 'more') {
      return;
    }
    this.pendingOutlinePath = node.path;
    for (let index = 0; index < this.presentation.outline.length; index += 1) {
      const candidate = this.presentation.outline[index];
      if (candidate.path === node.path && this.outlineRowKind(candidate) === 'element') {
        this.selectedOutlineRowKey = this.outlineRowKey(candidate);
        return;
      }
    }
    this.selectedOutlineRowKey = this.outlineRowKey(node);
  }

  private syncOutlineSelectionFromPresentation(): void {
    let selectedKey = '';
    for (let index = 0; index < this.presentation.outline.length; index += 1) {
      const node = this.presentation.outline[index];
      if (node.selected && this.outlineRowKind(node) === 'element') {
        selectedKey = this.outlineRowKey(node);
        break;
      }
    }
    if (this.pendingOutlinePath.length > 0) {
      if (selectedKey.length > 0) {
        const selectedPath = selectedKey.substring(selectedKey.lastIndexOf(':') + 1);
        if (selectedPath === this.pendingOutlinePath) {
          this.pendingOutlinePath = '';
          this.selectedOutlineRowKey = selectedKey;
        }
      }
      return;
    }
    if (selectedKey.length > 0) {
      this.selectedOutlineRowKey = selectedKey;
    }
  }

  private isVoidOutlineTag(tagName: string): boolean {
    return tagName === 'area' || tagName === 'base' || tagName === 'br' || tagName === 'col' ||
      tagName === 'embed' || tagName === 'hr' || tagName === 'img' || tagName === 'input' ||
      tagName === 'link' || tagName === 'meta' || tagName === 'param' || tagName === 'source' ||
      tagName === 'track' || tagName === 'wbr';
  }

  private keepTreeOffset(): void {
    let offsetY = 0;
    try {
      offsetY = this.treeScroller.currentOffset().yOffset;
    } catch (_error) {
      return;
    }
    const restore = (): void => {
      try {
        const current = this.treeScroller.currentOffset().yOffset;
        if (Math.abs(current - offsetY) >= 1) {
          this.treeScroller.scrollTo({ xOffset: 0, yOffset: offsetY, animation: false });
        }
      } catch (_error) {
      }
    };
    restore();
    setTimeout(restore, 0);
    setTimeout(restore, 48);
  }

  private focusOutlineTree(): void {
    try {
      focusControl.requestFocus(ELEMENT_INSPECTION_TREE_FOCUS_ID);
    } catch (_error) {
    }
  }

  private activateOutlineRow(node: ElementInspectionOutlineNode): void {
    if (Date.now() - this.outlineToggleAtMs < 80) {
      return;
    }
    this.dismissOutlineMenu();
    if (this.presentation.busy) {
      return;
    }
    if (this.outlineRowKind(node) === 'more') {
      this.emitOutlineCommand('outline_more', node.path, '', String(node.moreStart !== undefined ? node.moreStart : 0));
      return;
    }
    this.rememberOutlineSelection(node);
    this.onSelectOutline(node.path);
  }

  private toggleOutlineNode(node: ElementInspectionOutlineNode): void {
    if (this.presentation.busy || node.childCount <= 0 || this.outlineRowKind(node) !== 'element') {
      return;
    }
    this.outlineToggleAtMs = Date.now();
    this.dismissOutlineMenu();
    this.emitOutlineCommand('toggle_outline', node.path, '', node.expanded === true ? '0' : '1');
  }

  private handleOutlineKey(event: KeyEvent): boolean {
    if (event.keyCode === KeyCode.KEYCODE_CTRL_LEFT || event.keyCode === KeyCode.KEYCODE_CTRL_RIGHT) {
      this.inlineEditCtrl = event.type === KeyType.Down;
      return false;
    }
    if (this.tab !== 'elements' || event.type !== KeyType.Down || this.outlineMenuVisible) {
      return false;
    }
    if (this.editorVisible && this.editorKind === 'html') {
      if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
        this.cancelInlineHtmlEdit();
        return true;
      }
      return false;
    }
    if (this.editorVisible) {
      return false;
    }
    if (event.keyCode === KeyCode.KEYCODE_DEL || event.keyCode === KeyCode.KEYCODE_FORWARD_DEL) {
      this.deleteSelectedOutlineNode();
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_NUMPAD_ENTER) {
      this.beginInlineHtmlEdit();
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_DPAD_LEFT) {
      this.collapseOrSelectParent();
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_DPAD_RIGHT) {
      this.expandOrSelectChild();
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_DPAD_UP) {
      this.moveOutlineSelection(-1);
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
      this.moveOutlineSelection(1);
      return true;
    }
    return false;
  }

  private selectedElementIndex(): number {
    if (this.selectedOutlineRowKey.length > 0) {
      for (let index = 0; index < this.presentation.outline.length; index += 1) {
        const node = this.presentation.outline[index];
        if (this.outlineRowKind(node) === 'element' && this.outlineRowKey(node) === this.selectedOutlineRowKey) {
          return index;
        }
      }
    }
    for (let index = 0; index < this.presentation.outline.length; index += 1) {
      const node = this.presentation.outline[index];
      if (node.selected && this.outlineRowKind(node) === 'element') {
        return index;
      }
    }
    return -1;
  }

  private collapseOrSelectParent(): void {
    const index = this.selectedElementIndex();
    if (index < 0 || this.presentation.busy) {
      return;
    }
    const node = this.presentation.outline[index];
    if (node.childCount > 0 && node.expanded === true) {
      this.toggleOutlineNode(node);
      return;
    }
    if (node.path.length === 0) {
      return;
    }
    const slash = node.path.lastIndexOf('/');
    const parentPath = slash < 0 ? '' : node.path.substring(0, slash);
    this.pendingOutlinePath = parentPath;
    this.selectedOutlineRowKey = `element:after:${parentPath}`;
    this.onSelectOutline(parentPath);
  }

  private expandOrSelectChild(): void {
    const index = this.selectedElementIndex();
    if (index < 0 || this.presentation.busy) {
      return;
    }
    const node = this.presentation.outline[index];
    if (node.childCount > 0 && node.expanded !== true) {
      this.toggleOutlineNode(node);
      return;
    }
    for (let childIndex = index + 1; childIndex < this.presentation.outline.length; childIndex += 1) {
      const child = this.presentation.outline[childIndex];
      if (child.depth <= node.depth) {
        return;
      }
      if (this.outlineRowKind(child) === 'element') {
        this.rememberOutlineSelection(child);
        this.onSelectOutline(child.path);
        return;
      }
    }
  }

  private moveOutlineSelection(delta: number): void {
    if (this.presentation.busy || delta === 0) {
      return;
    }
    const current = this.selectedElementIndex();
    let next = current;
    const step = delta > 0 ? 1 : -1;
    for (let index = current + step; index >= 0 && index < this.presentation.outline.length; index += step) {
      if (this.outlineRowKind(this.presentation.outline[index]) === 'element') {
        next = index;
        break;
      }
    }
    if (next === current || next < 0) {
      return;
    }
    this.rememberOutlineSelection(this.presentation.outline[next]);
    this.onSelectOutline(this.presentation.outline[next].path);
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
    this.rememberOutlineSelection(node);
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
    this.outlineMenuOpenedAtMs = Date.now();
    this.outlineMenuVisible = true;
    this.onOutlineMenuVisibleChange(true);
  }

  private dismissOutlineMenu(): void {
    if (!this.outlineMenuVisible) {
      return;
    }
    this.outlineMenuVisible = false;
    this.outlineMenuPath = '';
    this.onOutlineMenuVisibleChange(false);
  }

  private handleOutlineMenuDismissSerial(): void {
    this.dismissOutlineMenu();
  }

  private dismissOutlineMenuFromPointer(): void {
    if (!this.outlineMenuVisible || Date.now() - this.outlineMenuOpenedAtMs < 80) {
      return;
    }
    this.dismissOutlineMenu();
  }

  private outlineMenuDismissRegion(): ElementInspectionDismissRegion {
    if (!this.outlineMenuVisible) {
      return { x: 0, y: 0, width: '100%', height: '100%' };
    }
    const left = Math.max(0, this.outlineMenuHostGlobalXVp) + 480;
    const top = Math.max(0, this.outlineMenuHostGlobalYVp) + 480;
    return {
      x: -left,
      y: -top,
      width: left + 4800,
      height: top + 4800
    };
  }

  private handleOutlineMenuSelect(key: string): void {
    const path = this.outlineMenuPath;
    this.dismissOutlineMenu();
    if (path.length === 0 || this.presentation.busy) {
      return;
    }
    if (key === 'add_attribute') {
      this.openAddAttributeEditor(path);
      return;
    }
    if (key === 'edit_attribute') {
      this.openAttributeEditor(path);
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
    entries.push({ key: 'duplicate', label: '创建副本', enabled: !busy && !protectedNode, group: 0 });
    entries.push({ key: 'delete', label: '删除元素', enabled: !busy && !protectedNode, group: 0 });
    entries.push({ key: 'cut', label: '剪切', enabled: !busy && !protectedNode, group: 1 });
    entries.push({ key: 'copy_selector', label: '复制选择器', enabled: !busy, group: 1 });
    entries.push({ key: 'copy_js_path', label: '复制 JS 路径', enabled: !busy, group: 1 });
    entries.push({ key: 'copy_xpath', label: '复制 XPath', enabled: !busy, group: 1 });
    entries.push({ key: 'copy_html', label: '复制 outerHTML', enabled: !busy, group: 1 });
    entries.push({ key: 'copy_styles', label: '复制样式', enabled: !busy, group: 1 });
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

  private emitOutlineCommand(
    kind: string,
    path: string,
    name: string,
    value: string,
    previousName: string = ''
  ): void {
    const command: ElementInspectionOutlineCommand = {
      kind: kind,
      path: path,
      name: name,
      value: value,
      requestId: 0,
      previousName: previousName
    };
    this.onOutlineCommand(command);
  }

  private openAttributeEditor(path: string): void {
    this.editorRequestId += 1;
    this.editorKind = 'attribute_edit';
    this.editorTitle = '编辑属性';
    this.editorPath = path;
    this.editorName = '';
    this.editorText = '';
    this.editorAttributes = [];
    this.editorSelectedAttribute = '';
    this.editorBusy = true;
    this.editorVisible = true;
    const command: ElementInspectionOutlineCommand = {
      kind: 'read_attributes',
      path: path,
      name: '',
      value: '',
      requestId: this.editorRequestId
    };
    this.onOutlineCommand(command);
  }

  private openAddAttributeEditor(path: string): void {
    this.editorKind = 'attribute';
    this.editorTitle = '添加属性';
    this.editorPath = path;
    this.editorName = '';
    this.editorText = '';
    this.editorAttributes = [];
    this.editorSelectedAttribute = '';
    this.editorBusy = false;
    this.editorVisible = true;
  }

  private isInlineHtmlEditing(node: ElementInspectionOutlineNode): boolean {
    return this.editorVisible && this.editorKind === 'html' && this.editorPath === node.path &&
      this.outlineRowKind(node) === 'element';
  }

  private beginInlineHtmlEdit(node?: ElementInspectionOutlineNode): void {
    let target = node;
    if (target === undefined) {
      const index = this.selectedElementIndex();
      if (index < 0) {
        return;
      }
      target = this.presentation.outline[index];
    }
    if (this.presentation.busy || target.tagName === 'html' || this.outlineRowKind(target) !== 'element') {
      return;
    }
    if (this.editorVisible && this.editorKind === 'html' && this.editorPath === target.path) {
      return;
    }
    this.keepTreeOffset();
    this.openHtmlEditor(target.path);
  }

  private deleteSelectedOutlineNode(): void {
    const index = this.selectedElementIndex();
    if (index < 0 || this.presentation.busy) {
      return;
    }
    const node = this.presentation.outline[index];
    if (this.isProtectedOutlineNode(node)) {
      return;
    }
    this.emitOutlineCommand('delete', node.path, '', '');
  }

  private cancelInlineHtmlEdit(): void {
    this.inlineEditCancel = true;
    this.closeOutlineEditor();
    this.focusOutlineTree();
  }

  private commitInlineHtmlEdit(fromBlur: boolean = false): void {
    if (fromBlur && !this.inlineEditArmed) {
      return;
    }
    if (this.inlineEditCancel || !this.editorVisible || this.editorKind !== 'html' || this.editorBusy) {
      return;
    }
    this.inlineEditCancel = true;
    this.applyOutlineEditor();
    this.focusOutlineTree();
  }

  private focusInlineHtmlEditor(): void {
    try {
      focusControl.requestFocus(ELEMENT_INSPECTION_INLINE_EDIT_ID);
    } catch (_error) {
    }
  }

  private openHtmlEditor(path: string): void {
    this.inlineEditCancel = false;
    this.inlineEditArmed = false;
    this.editorRequestId += 1;
    this.editorKind = 'html';
    this.editorTitle = '编辑为 HTML';
    this.editorPath = path;
    this.editorName = '';
    this.editorText = '';
    this.editorAttributes = [];
    this.editorSelectedAttribute = '';
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
    this.editorAttributes = [];
    this.editorSelectedAttribute = '';
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
      const nextName = this.editorName.trim();
      const previousName = this.editorKind === 'attribute_edit' && this.editorSelectedAttribute.length > 0 &&
        this.editorSelectedAttribute !== nextName ? this.editorSelectedAttribute : '';
      this.emitOutlineCommand('set_attribute', this.editorPath, nextName, this.editorText, previousName);
    }
    this.closeOutlineEditor();
  }

  private applyOutlineDraft(): void {
    const draft = this.presentation.outlineDraft;
    if (draft === undefined || !this.editorVisible ||
      draft.requestId !== this.editorRequestId || draft.requestId === this.appliedEditorRequestId) {
      return;
    }
    if (this.editorKind === 'html' && draft.kind === 'html') {
      this.appliedEditorRequestId = draft.requestId;
      this.editorBusy = false;
      if (!draft.ready) {
        this.closeOutlineEditor();
        return;
      }
      this.editorText = draft.text;
      setTimeout((): void => {
        this.focusInlineHtmlEditor();
        setTimeout((): void => {
          if (this.editorVisible && this.editorKind === 'html' && !this.inlineEditCancel) {
            this.inlineEditArmed = true;
          }
        }, 80);
      }, 0);
      return;
    }
    if (this.editorKind !== 'attribute_edit' || draft.kind !== 'attributes') {
      return;
    }
    this.appliedEditorRequestId = draft.requestId;
    this.editorBusy = false;
    if (!draft.ready) {
      this.closeOutlineEditor();
      return;
    }
    this.editorAttributes = this.parseAttributeDraft(draft.text);
    this.prefillFirstEditableAttribute();
  }

  private resolveEditorHint(): string {
    if (this.editorKind === 'html') {
      return '需要保留一个根元素。';
    }
    if (this.editorKind === 'attribute_edit') {
      return '点选已有属性再修改。改名会删掉旧属性，值为空时会删除该属性。';
    }
    return '属性值为空时会删除该属性。';
  }

  private parseAttributeDraft(text: string): ElementInspectionRuntimeAttribute[] {
    const result: ElementInspectionRuntimeAttribute[] = [];
    let parsed: ElementInspectionRuntimeAttribute[] = [];
    try {
      parsed = JSON.parse(text) as ElementInspectionRuntimeAttribute[];
    } catch (_error) {
      return result;
    }
    if (!Array.isArray(parsed)) {
      return result;
    }
    for (let index = 0; index < parsed.length && result.length < 40; index += 1) {
      const record = parsed[index];
      const name = record.name !== undefined ? String(record.name).trim() : '';
      if (name.length === 0) {
        continue;
      }
      result.push({
        name: name,
        value: record.value !== undefined ? String(record.value) : '',
        redacted: record.redacted === true
      });
    }
    return result;
  }

  private prefillFirstEditableAttribute(): void {
    for (let index = 0; index < this.editorAttributes.length; index += 1) {
      const attribute = this.editorAttributes[index];
      if (attribute.redacted) {
        continue;
      }
      this.editorSelectedAttribute = attribute.name;
      this.editorName = attribute.name;
      this.editorText = attribute.value;
      return;
    }
    this.editorSelectedAttribute = '';
    this.editorName = '';
    this.editorText = '';
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
          .height(36)
          .padding({ left: 10, right: 10, top: 0, bottom: 0 })
          .fontSize(13)
          .fontColor(ELEMENT_INSPECTION_DOCK_TEXT_COLOR)
          .backgroundColor(ELEMENT_INSPECTION_DOCK_BAR_COLOR)
          .placeholderColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
          .borderRadius(4)
          .onChange((value: string) => {
            this.consoleInput = value;
          })
        Button('执行')
          .type(ButtonType.Normal)
          .width(52)
          .height(36)
          .fontSize(12)
          .fontColor('#FFFFFF')
          .backgroundColor(ELEMENT_INSPECTION_DOCK_SELECT_COLOR)
          .margin({ left: 8 })
          .onClick(() => {
            this.submitConsole();
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8, top: 8, bottom: 12 })
      .alignItems(VerticalAlign.Center)
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
        Text('时间来自页面资源计时。蓝色是等待，绿色是下载。状态只在脚本请求里能看到。请求头和响应体看不到。')
          .width('100%')
          .fontSize(12)
          .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
          .padding({ left: 12, right: 12, top: 10, bottom: 8 })
        if (this.presentation.network.length === 0) {
          Text(this.presentation.phase === 'starting' ?
            '网页正在刷新，审查还开着，资源会在页面准备好后出现。' :
            '还没有看到资源。打开审查之后的新请求，以及页面已经加载的资源，会出现在这里。')
            .width('100%')
            .fontSize(12)
            .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
            .padding({ left: 12, right: 12, bottom: 12 })
        }
        ForEach(this.presentation.network, (entry: ElementInspectionNetworkEntry) => {
          this.buildNetworkRow(entry)
        }, (entry: ElementInspectionNetworkEntry, index: number) =>
          `${index}:${entry.url}:${entry.status}:${entry.durationMs}:${entry.offsetMs}`)
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
  private buildNetworkRow(entry: ElementInspectionNetworkEntry) {
    Column() {
      Row() {
        Text(this.networkMethodText(entry))
          .fontSize(11)
          .fontColor(ELEMENT_INSPECTION_DOCK_BLUE_COLOR)
          .constraintSize({ minWidth: 36, maxWidth: 72 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.networkStatusText(entry))
          .fontSize(11)
          .fontColor(this.networkStatusColor(entry))
          .width(42)
          .margin({ left: 8 })
        Text(this.networkTimingText(entry))
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
        .margin({ top: 2 })
      if (entry.type.length > 0 && entry.method.length > 0) {
        Text(entry.type)
          .fontSize(11)
          .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
          .margin({ top: 2 })
      }
      this.buildNetworkWaterfall(entry)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .border({ width: { bottom: 1 }, color: ELEMENT_INSPECTION_DOCK_LINE_COLOR })
  }

  @Builder
  private buildNetworkWaterfall(entry: ElementInspectionNetworkEntry) {
    if (entry.timed && this.networkBarTotal() > 0 && this.networkBarSpan(entry) > 0) {
      Row() {
        if (entry.offsetMs > 0) {
          Column()
            .width(this.percentWidth(entry.offsetMs))
            .height(4)
        }
        if (this.networkWaitWidth(entry) > 0) {
          Column()
            .width(this.percentWidth(this.networkWaitWidth(entry)))
            .height(4)
            .backgroundColor(ELEMENT_INSPECTION_DOCK_BLUE_COLOR)
        }
        if (entry.downloadMs > 0) {
          Column()
            .width(this.percentWidth(entry.downloadMs))
            .height(4)
            .backgroundColor('#81c995')
        }
      }
      .width('100%')
      .height(6)
      .margin({ top: 4 })
      .backgroundColor(ELEMENT_INSPECTION_DOCK_LINE_COLOR)
      .borderRadius(2)
      .clip(true)
    }
  }

  @Builder
  private buildApplicationPane() {
    Scroll() {
      Column() {
        Text('只能看当前网站。HttpOnly Cookie 看不到，密码和令牌这类名称已隐藏。')
          .width('100%')
          .fontSize(12)
          .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
          .padding({ left: 12, right: 12, top: 10, bottom: 8 })
        this.buildStorageSection('本地存储', this.localStorageEntries(), '当前网站没有本地存储。')
        this.buildStorageSection('会话存储', this.sessionStorageEntries(), '当前网站没有会话存储。')
        this.buildStorageSection('Cookie', this.cookieEntries(), '页面读不到 Cookie。')
        this.buildDatabaseSection()
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
  private buildStorageSection(title: string, entries: ElementInspectionStorageEntry[], emptyText: string) {
    Column() {
      Text(title)
        .width('100%')
        .fontSize(12)
        .fontColor(ELEMENT_INSPECTION_DOCK_BLUE_COLOR)
        .padding({ left: 12, right: 12, top: 8, bottom: 4 })
      if (entries.length === 0) {
        Text(emptyText)
          .width('100%')
          .fontSize(12)
          .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
          .padding({ left: 12, right: 12, bottom: 8 })
      }
      ForEach(entries, (entry: ElementInspectionStorageEntry) => {
        Column() {
          Text(entry.name)
            .width('100%')
            .fontSize(12)
            .fontColor(ELEMENT_INSPECTION_DOCK_ATTR_COLOR)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.storageValueText(entry))
            .width('100%')
            .fontSize(12)
            .fontColor(entry.redacted ? ELEMENT_INSPECTION_DOCK_DIM_COLOR : ELEMENT_INSPECTION_DOCK_STRING_COLOR)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 12, right: 12, top: 4, bottom: 6 })
      }, (entry: ElementInspectionStorageEntry, index: number) => `${title}:${index}:${entry.name}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .border({ width: { bottom: 1 }, color: ELEMENT_INSPECTION_DOCK_LINE_COLOR })
  }

  @Builder
  private buildDatabaseSection() {
    Column() {
      Text('IndexedDB')
        .width('100%')
        .fontSize(12)
        .fontColor(ELEMENT_INSPECTION_DOCK_BLUE_COLOR)
        .padding({ left: 12, right: 12, top: 8, bottom: 4 })
      if (this.databaseNames().length === 0) {
        Text('没有看到数据库。只显示库名，不读取里面的数据。')
          .width('100%')
          .fontSize(12)
          .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
          .padding({ left: 12, right: 12, bottom: 8 })
      }
      ForEach(this.databaseNames(), (name: string) => {
        Text(name)
          .width('100%')
          .fontSize(12)
          .fontColor(ELEMENT_INSPECTION_DOCK_TEXT_COLOR)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      }, (name: string, index: number) => `${index}:${name}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildSecurityPane() {
    Scroll() {
      Column() {
        if (this.presentation.security === undefined) {
          Text('正在读取页面安全信息。')
            .width('100%')
            .fontSize(12)
            .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
            .padding(12)
        } else {
          this.buildSecurityRow('连接', this.securityConnectionText())
          this.buildSecurityRow('协议', this.securityProtocolText())
          this.buildSecurityRow('来源', this.securityOriginText())
          this.buildSecurityRow('证书', this.securityCertificateText())
          Text(this.securityMixedTitle())
            .width('100%')
            .fontSize(12)
            .fontColor(ELEMENT_INSPECTION_DOCK_BLUE_COLOR)
            .padding({ left: 12, right: 12, top: 10, bottom: 4 })
          if (this.securityMixedUrls().length === 0) {
            Text(this.securityMixedEmptyText())
              .width('100%')
              .fontSize(12)
              .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
              .padding({ left: 12, right: 12, bottom: 8 })
          }
          ForEach(this.securityMixedUrls(), (url: string) => {
            Text(url)
              .width('100%')
              .fontSize(12)
              .fontColor('#f28b82')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 12, right: 12, top: 2, bottom: 4 })
          }, (url: string, index: number) => `${index}:${url}`)
          Text('证书链、有效期和请求头看不到。')
            .width('100%')
            .fontSize(12)
            .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
            .padding({ left: 12, right: 12, top: 8, bottom: 12 })
        }
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
  private buildSecurityRow(label: string, value: string) {
    Column() {
      Text(label)
        .width('100%')
        .fontSize(11)
        .fontColor(ELEMENT_INSPECTION_DOCK_DIM_COLOR)
      Text(value)
        .width('100%')
        .fontSize(13)
        .fontColor(ELEMENT_INSPECTION_DOCK_TEXT_COLOR)
        .margin({ top: 2 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .border({ width: { bottom: 1 }, color: ELEMENT_INSPECTION_DOCK_LINE_COLOR })
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

  private networkMethodText(entry: ElementInspectionNetworkEntry): string {
    if (entry.method.length > 0) {
      return entry.method;
    }
    if (entry.type.length > 0) {
      return entry.type;
    }
    return '资源';
  }

  private networkStatusText(entry: ElementInspectionNetworkEntry): string {
    if (entry.status > 0) {
      return String(entry.status);
    }
    if (entry.timed || entry.durationMs > 0) {
      return '—';
    }
    return '失败';
  }

  private networkStatusColor(entry: ElementInspectionNetworkEntry): string {
    if (entry.status >= 400 || (entry.status === 0 && !entry.timed && entry.durationMs === 0)) {
      return '#f28b82';
    }
    if (entry.status === 0) {
      return ELEMENT_INSPECTION_DOCK_DIM_COLOR;
    }
    return '#81c995';
  }

  private networkTimingText(entry: ElementInspectionNetworkEntry): string {
    if (entry.durationMs > 0) {
      return `${entry.durationMs} ms`;
    }
    if (entry.timed) {
      return '时间不可用';
    }
    return '—';
  }

  private networkBarTotal(): number {
    let total = 0;
    this.presentation.network.forEach((entry: ElementInspectionNetworkEntry): void => {
      if (!entry.timed) {
        return;
      }
      const end = entry.offsetMs + this.networkBarSpan(entry);
      if (end > total) {
        total = end;
      }
    });
    return total;
  }

  private networkBarSpan(entry: ElementInspectionNetworkEntry): number {
    return Math.max(entry.durationMs, entry.waitMs + entry.downloadMs);
  }

  private networkWaitWidth(entry: ElementInspectionNetworkEntry): number {
    if (entry.waitMs > 0) {
      return entry.waitMs;
    }
    if (entry.downloadMs > 0) {
      return 0;
    }
    return entry.durationMs;
  }

  private percentWidth(value: number): string {
    const total = this.networkBarTotal();
    if (total <= 0 || value <= 0) {
      return '0%';
    }
    const percent = Math.min(100, Math.round((value / total) * 1000) / 10);
    return `${percent}%`;
  }

  private storageValueText(entry: ElementInspectionStorageEntry): string {
    if (entry.redacted) {
      return '已隐藏';
    }
    return entry.value.length > 0 ? entry.value : '空';
  }

  private localStorageEntries(): ElementInspectionStorageEntry[] {
    return this.presentation.storage !== undefined ? this.presentation.storage.local : [];
  }

  private sessionStorageEntries(): ElementInspectionStorageEntry[] {
    return this.presentation.storage !== undefined ? this.presentation.storage.session : [];
  }

  private cookieEntries(): ElementInspectionStorageEntry[] {
    return this.presentation.storage !== undefined ? this.presentation.storage.cookies : [];
  }

  private databaseNames(): string[] {
    return this.presentation.storage !== undefined ? this.presentation.storage.databases : [];
  }

  private securitySummary(): ElementInspectionSecuritySummary | undefined {
    return this.presentation.security;
  }

  private securityConnectionText(): string {
    const summary = this.securitySummary();
    if (summary === undefined) {
      return '未知';
    }
    return summary.secure ? '安全上下文' : '不是安全上下文';
  }

  private securityProtocolText(): string {
    const summary = this.securitySummary();
    if (summary === undefined || summary.protocol.length === 0) {
      return '未知';
    }
    if (summary.protocol === 'https') {
      return 'HTTPS';
    }
    if (summary.protocol === 'http') {
      return 'HTTP';
    }
    return summary.protocol;
  }

  private securityOriginText(): string {
    const summary = this.securitySummary();
    if (summary === undefined || summary.origin.length === 0) {
      return '未知';
    }
    return summary.origin;
  }

  private securityCertificateText(): string {
    const summary = this.securitySummary();
    if (summary !== undefined && summary.certificateError) {
      return '这个网站的主框架证书校验失败过。';
    }
    return '这次没有看到证书错误。';
  }

  private securityMixedTitle(): string {
    return '混合内容';
  }

  private securityMixedEmptyText(): string {
    const summary = this.securitySummary();
    if (summary !== undefined && summary.protocol !== 'https') {
      return '只在 HTTPS 页面检查混合内容。';
    }
    return '没有看到 HTTP 资源。';
  }

  private securityMixedUrls(): string[] {
    const summary = this.securitySummary();
    return summary !== undefined ? summary.mixedUrls : [];
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
    this.splitterActive = this.splitterHovered;
    this.panResizeActive = false;
    this.setSplitterCursor(this.splitterHovered);
  }

  private handleSplitterMouse(event: MouseEvent, fromCapture: boolean): void {
    if (event.action === MouseAction.Press && event.button === MouseButton.Left) {
      this.mouseDragStartWindowXPx = event.windowX;
      this.panResizeActive = false;
      this.beginSplitterDrag(this.panelWidthVp);
      return;
    }
    if (event.action === MouseAction.Hover && !this.splitterDragging) {
      this.splitterHovered = true;
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
    if (event.action === MouseAction.Move) {
      this.setSplitterCursor(true);
      if (this.splitterDragging && !this.panResizeActive) {
        const deltaVp = this.getUIContext().px2vp(event.windowX - this.mouseDragStartWindowXPx);
        this.panelWidthVp = this.clampWidth(this.mouseDragStartWidthVp - deltaVp);
      }
    }
  }

  private setSplitterCursor(resize: boolean): void {
    this.applySplitterCursor(resize);
    if (resize) {
      this.ensureSplitterCursorTimer();
      return;
    }
    this.clearSplitterCursorTimer();
  }

  private releaseSplitterCursor(): void {
    this.clearSplitterCursorTimer();
    this.applySplitterCursor(false);
  }

  private ensureSplitterCursorTimer(): void {
    if (this.splitterCursorTimer >= 0) {
      return;
    }
    this.splitterCursorTimer = setInterval((): void => {
      if (!this.splitterHovered && !this.splitterDragging) {
        this.releaseSplitterCursor();
        return;
      }
      this.applySplitterCursor(true);
    }, 32);
  }

  private clearSplitterCursorTimer(): void {
    if (this.splitterCursorTimer < 0) {
      return;
    }
    clearInterval(this.splitterCursorTimer);
    this.splitterCursorTimer = -1;
  }

  private applySplitterCursor(resize: boolean): void {
    const style = resize ? pointer.PointerStyle.RESIZE_LEFT_RIGHT : pointer.PointerStyle.DEFAULT;
    try {
      cursorControl.setCursor(style);
    } catch (_error) {
    }
    try {
      const cursor = this.getUIContext().getCursorController();
      if (resize) {
        cursor.setCursor(style);
      } else {
        cursor.restoreDefault();
      }
    } catch (_error) {
    }
    this.applyWindowPointerStyle(style);
  }

  private applyWindowPointerStyle(style: pointer.PointerStyle): void {
    if (this.pointerWindowId < 0) {
      this.rememberPointerWindowId();
      return;
    }
    try {
      pointer.setPointerStyleSync(this.pointerWindowId, style);
    } catch (_error) {
    }
  }

  private rememberPointerWindowId(): void {
    if (this.pointerWindowId >= 0 || this.pointerWindowResolving) {
      return;
    }
    let hostContext: common.UIAbilityContext | undefined = undefined;
    try {
      hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    } catch (_error) {
      return;
    }
    if (hostContext === undefined) {
      return;
    }
    this.pointerWindowResolving = true;
    window.getLastWindow(hostContext).then((mainWindow: window.Window) => {
      this.pointerWindowResolving = false;
      const windowId = mainWindow.getWindowProperties().id;
      if (windowId < 0) {
        return;
      }
      this.pointerWindowId = windowId;
      if (this.splitterHovered || this.splitterDragging) {
        this.applySplitterCursor(true);
      }
    }).catch((_error: BusinessError) => {
      this.pointerWindowResolving = false;
    });
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
