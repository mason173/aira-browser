import { describe, expect, it } from '@ohos/hypium';
import {
  ElementInspectionBoxModel,
  ElementInspectionComputedProperty,
  ElementInspectionOutlineNode,
  ElementInspectionRuntimeScriptService
} from '../main/ets/services/web/ElementInspectionRuntimeScriptService';

function inspectedSnapshot(): string {
  return JSON.stringify({
    ok: true,
    reason: '',
    protocolVersion: 4,
    sessionGeneration: 2,
    documentToken: '2:token',
    revision: 4,
    mode: 'inspected',
    node: {
      tagName: 'section',
      elementId: 'hero',
      classTokens: ['hero'],
      selector: 'section.hero',
      breadcrumb: ['html', 'body', 'section.hero'],
      attributes: [{ name: 'class', value: 'hero', redacted: false }],
      textPreview: '卡片',
      htmlPreview: '<section class="hero">卡片</section>',
      htmlLength: 32,
      rect: { left: 1, top: 2, width: 30, height: 40 },
      hasParent: true,
      hasFirstChild: false,
      hasPreviousSibling: false,
      hasNextSibling: false
    },
    outline: [
      {
        path: '',
        depth: 0,
        tagName: 'html',
        elementId: '',
        classTokens: [],
        textPreview: '',
        childCount: 2,
        selected: false
      },
      {
        path: '1/0',
        depth: 2,
        tagName: 'section',
        elementId: 'hero',
        classTokens: ['hero', 'card'],
        textPreview: '',
        childCount: 1,
        selected: true
      },
      {
        path: '../secret',
        depth: 1,
        tagName: 'script',
        elementId: '',
        classTokens: [],
        textPreview: '',
        childCount: 0,
        selected: false
      }
    ],
    box: {
      marginTop: 0,
      marginRight: 8,
      marginBottom: 12,
      marginLeft: 8,
      borderTop: 1,
      borderRight: 1,
      borderBottom: 1,
      borderLeft: 1,
      paddingTop: 22,
      paddingRight: 22,
      paddingBottom: 22,
      paddingLeft: 22,
      contentWidth: 640,
      contentHeight: 168
    },
    computed: [
      { name: 'display', value: 'block' },
      { name: 'background-color', value: 'rgb(244, 247, 255)' },
      { name: '', value: 'ignored' }
    ],
    logs: [
      { level: 'error', text: 'boom', time: 12 },
      { level: 'verbose', text: 'ignored-level', time: 13 }
    ],
    network: [
      { method: 'GET', url: 'https://example.test/app.js', status: 200, type: 'text/javascript', size: 32, durationMs: 8, startedAt: 20 }
    ],
    sources: [
      { id: 'document', kind: 'document', name: 'Example', url: 'https://example.test/' },
      { id: '../secret', kind: 'script', name: 'bad', url: 'https://example.test/bad.js' }
    ],
    listeners: [
      { type: 'click', capture: false, source: 'attribute' }
    ]
  });
}

export default function elementInspectionRuntimeScriptServiceTest(): void {
  describe('ElementInspectionRuntimeScriptService outline', () => {
    it('keeps a bounded outline, box model, and computed properties', 0, () => {
      const service = new ElementInspectionRuntimeScriptService();
      const snapshot = service.parseSnapshot(inspectedSnapshot());

      expect(snapshot.ok).assertTrue();
      expect(snapshot.mode).assertEqual('inspected');
      const outline: ElementInspectionOutlineNode[] = snapshot.outline !== undefined ? snapshot.outline : [];
      const computed: ElementInspectionComputedProperty[] = snapshot.computed !== undefined ? snapshot.computed : [];
      const box: ElementInspectionBoxModel | undefined = snapshot.box;
      expect(outline.length).assertEqual(2);
      expect(outline[0].path).assertEqual('');
      expect(outline[1].path).assertEqual('1/0');
      expect(outline[1].selected).assertTrue();
      expect(box !== undefined).assertTrue();
      if (box !== undefined) {
        expect(box.contentWidth).assertEqual(640);
        expect(box.paddingTop).assertEqual(22);
      }
      expect(computed.length).assertEqual(2);
      expect(computed[1].name).assertEqual('background-color');
      expect(snapshot.logs !== undefined && snapshot.logs.length === 2).assertTrue();
      expect(snapshot.logs !== undefined ? snapshot.logs[1].level : '').assertEqual('log');
      expect(snapshot.network !== undefined && snapshot.network.length === 1).assertTrue();
      expect(snapshot.sources !== undefined && snapshot.sources.length === 1).assertTrue();
      expect(snapshot.listeners !== undefined && snapshot.listeners[0].type === 'click').assertTrue();
    });

    it('rejects a snapshot from an older inspection protocol', 0, () => {
      const service = new ElementInspectionRuntimeScriptService();
      const snapshot = service.parseSnapshot(JSON.stringify({
        ok: true,
        protocolVersion: 2,
        sessionGeneration: 1,
        documentToken: '1:token',
        revision: 1,
        mode: 'selecting'
      }));

      expect(snapshot.ok).assertFalse();
    });

    it('evaluates console input only as an encoded page expression', 0, () => {
      const service = new ElementInspectionRuntimeScriptService();
      const script = service.buildEvaluateScript(2, '2:token', '1;alert(1)');
      const rejected = service.buildReadSourceScript(2, '2:token', 'script:1;alert(1)');

      expect(script.indexOf('runtime.evaluate(') >= 0).assertTrue();
      expect(script.indexOf('"1;alert(1)"') >= 0).assertTrue();
      expect(rejected.indexOf('runtime.readSource(') >= 0).assertFalse();
    });

    it('selects an outline path only when the path is a child index', 0, () => {
      const service = new ElementInspectionRuntimeScriptService();
      const selected = service.buildSelectOutlineScript(2, '2:token', '1/0');
      const rejected = service.buildSelectOutlineScript(2, '2:token', '1;alert(1)');

      expect(selected.indexOf('runtime.selectByPath(') >= 0).assertTrue();
      expect(selected.indexOf('"1/0"') >= 0).assertTrue();
      expect(rejected.indexOf('runtime.selectByPath(') >= 0).assertFalse();
      expect(rejected.indexOf('runtime.snapshot()') >= 0).assertTrue();
    });

    it('previews an outline path without selecting it', 0, () => {
      const service = new ElementInspectionRuntimeScriptService();
      const preview = service.buildPreviewOutlineScript(2, '2:token', '1/0');
      const rejected = service.buildPreviewOutlineScript(2, '2:token', '1;alert(1)');
      const install = service.buildInstallScript(2, '2:token', '#0A59F7');

      expect(preview.indexOf('runtime.previewByPath(') >= 0).assertTrue();
      expect(preview.indexOf('"1/0"') >= 0).assertTrue();
      expect(rejected.indexOf('runtime.previewByPath(') >= 0).assertFalse();
      expect(install.indexOf('可键盘聚焦') >= 0).assertTrue();
    });

    it('builds a path-scoped context action and rejects an unsafe command', 0, () => {
      const service = new ElementInspectionRuntimeScriptService();
      const script = service.buildOutlineCommandScript(2, '2:token', 'delete', '1/0', '');
      const rejectedKind = service.buildOutlineCommandScript(2, '2:token', 'delete;alert(1)', '1/0', '');
      const rejectedPath = service.buildOutlineCommandScript(2, '2:token', 'paste', '1/0', '<div>');
      const install = service.buildInstallScript(2, '2:token', '#0A59F7');
      const parsed = service.parseContextActionResult(JSON.stringify({
        ok: true,
        reason: '',
        protocolVersion: 4,
        sessionGeneration: 2,
        documentToken: '2:token',
        text: 'temp1',
        snapshot: JSON.parse(inspectedSnapshot())
      }));

      expect(script.indexOf('runtime.contextAction(') >= 0).assertTrue();
      expect(script.indexOf('"delete"') >= 0).assertTrue();
      expect(rejectedKind.indexOf('runtime.contextAction(') >= 0).assertFalse();
      expect(rejectedPath.indexOf('runtime.contextAction(') >= 0).assertFalse();
      expect(install.indexOf('runtime.contextAction') >= 0).assertTrue();
      expect(install.indexOf('aira-inspect-hidden') >= 0).assertTrue();
      expect(parsed.ok).assertTrue();
      expect(parsed.text).assertEqual('temp1');
      expect(parsed.snapshot.ok).assertTrue();
    });
  });
}
