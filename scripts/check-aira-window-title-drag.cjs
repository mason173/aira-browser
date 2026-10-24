#!/usr/bin/env node
'use strict';

// Replay the production title-bar callbacks and Window service. The native stub
// models a maximized window restoring as soon as startMoving is requested.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const sourceRoot = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const TouchType = { Down: 0, Up: 1, Move: 2, Cancel: 3 };

function evaluate(source, globals = {}) {
  const exports = {};
  const code = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText;
  vm.runInNewContext(code, { exports, TouchType, require: () => ({}), ...globals });
  return exports;
}

const { BrowserLargeScreenWindowChromeService } = evaluate(fs.readFileSync(
  path.join(sourceRoot, 'services/browser/BrowserLargeScreenWindowChromeService.ets'), 'utf8'));

function callback(service, surface) {
  const source = fs.readFileSync(path.join(sourceRoot,
    `app/components/browser/BrowserLargeScreen${surface}.ets`), 'utf8');
  let match;
  if (surface === 'NavigationToolbarSurface') {
    const dragArea = source.slice(source.indexOf('.width(BROWSER_LARGE_SCREEN_TITLE_BAR_MIN_DRAG_WIDTH_VP)'));
    match = dragArea.match(/\.onTouch\(\(event: TouchEvent\): void => \{([\s\S]*?)\n            \}\)/);
  } else {
    match = source.match(/private handleWindowMoveTouch\(event: TouchEvent\): void \{([\s\S]*?)\n  \}/);
  }
  assert.ok(match, `${surface} must retain a title-bar touch callback`);
  return evaluate(`export function handle(event: TouchEvent): void {${match[1]}\n}`, {
    sharedBrowserLargeScreenWindowChromeService: service
  }).handle;
}

function fixture(surface = 'TabStripSurface', service = new BrowserLargeScreenWindowChromeService(), id = 'main') {
  const native = {
    status: 'MAXIMIZE', moves: 0,
    setWindowDecorVisible() {},
    startMoving() { this.moves += 1; this.status = 'FLOATING'; return Promise.resolve(); }
  };
  service.registerWindow(id, native);
  const lease = service.activate(id);
  const ui = { windowChromeLeaseId: lease, windowMoveEnabled: true, presentation: { windowMoveEnabled: true } };
  const handle = callback(service, surface);
  return { service, native, lease, ui,
    send(type, x = 100, y = 20, pointerId = 1, extraTouches = []) {
      const point = { id: pointerId, windowX: x, windowY: y };
      handle.call(ui, { type, changedTouches: [point], touches: [point, ...extraTouches] });
    }
  };
}

for (const surface of ['TabStripSurface', 'VerticalTabsSidebar', 'NavigationToolbarSurface']) {
  test(`${surface}: clicking a maximized title bar preserves its size`, () => {
    const f = fixture(surface);
    f.send(TouchType.Down);
    assert.equal(f.native.status, 'MAXIMIZE', 'a press must not restore the window');
    f.send(TouchType.Up);
    assert.equal(f.native.moves, 0);
  });

  test(`${surface}: jitter is ignored and an intentional drag starts exactly once`, () => {
    const f = fixture(surface);
    f.send(TouchType.Move, 150);
    assert.equal(f.native.moves, 0, 'movement without a press must not drag');
    f.send(TouchType.Down);
    f.send(TouchType.Move, 102, 22);
    assert.equal(f.native.moves, 0, 'small pointer jitter must preserve maximization');
    f.send(TouchType.Move, 108);
    f.send(TouchType.Move, 120);
    assert.equal(f.native.moves, 1);
    f.send(TouchType.Up, 120);
    f.send(TouchType.Down, 120);
    f.send(TouchType.Move, 120, 30);
    assert.equal(f.native.moves, 2, 'the next gesture can drag vertically');
  });

  for (const end of [TouchType.Up, TouchType.Cancel]) {
    test(`${surface}: ${end === TouchType.Up ? 'release' : 'cancel'} clears the pending drag`, () => {
      const f = fixture(surface);
      f.send(TouchType.Down);
      f.send(end);
      f.send(TouchType.Move, 120);
      assert.equal(f.native.moves, 0);
    });
  }
}

test('a different pointer or a multi-touch gesture cannot start the pending drag', () => {
  const f = fixture();
  f.send(TouchType.Down);
  f.send(TouchType.Move, 140, 20, 2);
  assert.equal(f.native.moves, 0);
  f.send(TouchType.Down);
  f.send(TouchType.Down, 100, 20, 2, [{ id: 1, windowX: 100, windowY: 20 }]);
  f.send(TouchType.Move, 140);
  assert.equal(f.native.moves, 0);
});

test('each native window owns its pending gesture', () => {
  const first = fixture();
  const second = fixture('TabStripSurface', first.service, 'second');
  first.send(TouchType.Down);
  second.send(TouchType.Move, 140);
  assert.equal(second.native.moves, 0);
  first.send(TouchType.Move, 140);
  assert.equal(first.native.moves, 1);
});

test('restoring system chrome or rebinding a window invalidates its pending gesture', () => {
  const f = fixture();
  f.send(TouchType.Down);
  f.service.restoreLease(f.lease);
  f.service.activate('main');
  f.send(TouchType.Move, 140);
  assert.equal(f.native.moves, 0);
  f.send(TouchType.Down);
  f.service.rebindWindow('main', 'renamed', f.native);
  f.send(TouchType.Move, 140);
  assert.equal(f.native.moves, 0);
});

test('disabled movement and empty touch data discard a pending gesture', () => {
  const f = fixture();
  f.send(TouchType.Down);
  f.ui.presentation.windowMoveEnabled = false;
  f.send(TouchType.Move, 140);
  f.ui.presentation.windowMoveEnabled = true;
  f.send(TouchType.Move, 150);
  assert.equal(f.native.moves, 0);
  f.send(TouchType.Down);
  callback(f.service, 'TabStripSurface').call(f.ui, { type: TouchType.Move, touches: [], changedTouches: [] });
  f.send(TouchType.Move, 150);
  assert.equal(f.native.moves, 0);
});
