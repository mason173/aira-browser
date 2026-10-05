import { describe, expect, it } from '@ohos/hypium';
import {
  BROWSER_WEB_TOOLBAR_CLEARANCE_VP,
  resolveWebToolbarClearanceVp
} from '../main/ets/core/browser/BrowserWebToolbarClearancePolicy';
import { BrowserWebToolbarClearanceCoordinator } from '../main/ets/core/browser/BrowserWebToolbarClearanceCoordinator';
import { WebToolbarClearanceScriptService } from '../main/ets/services/web/WebToolbarClearanceScriptService';

export default function browserWebToolbarClearancePolicyTest(): void {
  describe('BrowserWebToolbarClearancePolicy', () => {
    it('extends the scroll range by the resting capsule overlap while the toolbar overlays the page', 0, () => {
      expect(resolveWebToolbarClearanceVp({
        overlayActive: true,
        viewportReserved: false,
        bottomLiftVp: 0
      })).assertEqual(BROWSER_WEB_TOOLBAR_CLEARANCE_VP);
    });

    it('adds the cockpit lift without resizing when the capsule only compacts or hides on scroll', 0, () => {
      expect(resolveWebToolbarClearanceVp({
        overlayActive: true,
        viewportReserved: false,
        bottomLiftVp: 12
      })).assertEqual(BROWSER_WEB_TOOLBAR_CLEARANCE_VP + 12);
    });

    it('drops the clearance when the toolbar is not an overlay or the viewport is already shortened', 0, () => {
      expect(resolveWebToolbarClearanceVp({
        overlayActive: false,
        viewportReserved: false,
        bottomLiftVp: 8
      })).assertEqual(0);
      expect(resolveWebToolbarClearanceVp({
        overlayActive: true,
        viewportReserved: true,
        bottomLiftVp: 8
      })).assertEqual(0);
      expect(resolveWebToolbarClearanceVp({
        overlayActive: true,
        viewportReserved: false,
        bottomLiftVp: Number.NaN
      })).assertEqual(BROWSER_WEB_TOOLBAR_CLEARANCE_VP);
    });

    it('builds a trailing spacer script and a removal script without touching fixed bars', 0, () => {
      const applyScript = WebToolbarClearanceScriptService.buildApplyScript(93.6);
      expect(applyScript.indexOf('aira-toolbar-clearance') >= 0).assertTrue();
      expect(applyScript.indexOf('var px = 94') >= 0).assertTrue();
      expect(applyScript.indexOf('position:fixed') >= 0).assertFalse();
      expect(applyScript.indexOf('runtime.clear') >= 0).assertTrue();
      const removeScript = WebToolbarClearanceScriptService.buildApplyScript(0);
      expect(removeScript.indexOf('var px = 0') >= 0).assertTrue();
    });

    it('skips the spacer when the container lays its children out sideways', 0, () => {
      const applyScript = WebToolbarClearanceScriptService.buildApplyScript(94);
      // The spacer is a full-width sibling. In a row flex or grid container it would push the real
      // content off screen instead of adding scroll room, so the script must refuse to insert it.
      expect(applyScript.indexOf('runtime.extendsFlow') >= 0).assertTrue();
      expect(applyScript.indexOf("display === 'grid' || display === 'inline-grid'") >= 0).assertTrue();
      expect(applyScript.indexOf("flexDirection === 'column' || style.flexDirection === 'column-reverse'"))
        .assertTrue();
      // Both the initial ensure() and the mutation observer's repair path must consult the guard.
      const guardCalls = applyScript.split('runtime.extendsFlow(document.body)').length - 1;
      expect(guardCalls).assertEqual(2);
    });

    it('applies once until the document is replaced or the clearance changes', 0, () => {
      const scripts: string[] = [];
      let overlayActive = true;
      const coordinator = new BrowserWebToolbarClearanceCoordinator({
        readFacts: () => ({
          tabId: 'tab-1',
          overlayActive: overlayActive,
          viewportReserved: false,
          bottomLiftVp: 0
        }),
        runScript: (_tabId: string, script: string): void => {
          scripts.push(script);
        }
      });

      coordinator.apply('tab-1');
      coordinator.apply('tab-1');
      expect(scripts.length).assertEqual(1);

      coordinator.handleDocumentBegin('tab-1');
      coordinator.apply('tab-1');
      expect(scripts.length).assertEqual(2);

      overlayActive = false;
      coordinator.apply('tab-1');
      expect(scripts.length).assertEqual(3);
      expect(scripts[2].indexOf('var px = 0') >= 0).assertTrue();

      coordinator.apply('tab-2');
      expect(scripts.length).assertEqual(3);
    });
  });
}
