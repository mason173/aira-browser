#!/usr/bin/env node
'use strict';

// Replay selection callbacks and batch orchestration from the production ETS sources.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const resources = new Map(JSON.parse(fs.readFileSync(path.join(root,
  '../resources/base/element/string.json'), 'utf8')).string.map(item => [item.name, item.value]));
const resourceText = key => resources.get(key.replace('app.string.', '')) || key;

function evaluate(source, globals = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021, experimentalDecorators: true }
  }).outputText, {
    exports, Observed: target => target, $r: key => key,
    require: id => {
      if (id.endsWith('/AppResourceText')) return { resolveAppResourceText: resourceText };
      if (id.endsWith('/DownloadSelectionViewModel')) return selection;
      return {};
    }, ...globals
  });
  return exports;
}
const selection = evaluate(read('core/download/DownloadSelectionViewModel.ets'));
const { DownloadBatchActionCoordinator } = evaluate(read('core/download/DownloadBatchActionCoordinator.ets'));
const { DownloadManagerViewModel } = evaluate(read('core/download/DownloadManagerViewModel.ets'));
const boundary = { windowId: 'private-window', profileId: 'profile-main',
  privacyMode: 'private', dataScope: 'session_ephemeral' };
const task = (guid, status, actions, extra = {}) => ({ guid, status, actions, ...extra });

function fixture(tasks, control = async () => true) {
  const calls = [];
  const runtime = {
    listTasksSnapshot(scope) {
      assert.equal(scope, boundary, 'every snapshot keeps the captured privacy/window boundary');
      return tasks.filter(item => !item.outsideBoundary);
    },
    listAllowedActionsForTask: item => item.actions
  };
  for (const [method, action] of [['pauseTaskForBoundary', 'pause'], ['resumeTaskForBoundary', 'resume'],
    ['retryTaskForBoundary', 'retry'], ['cancelAndRemoveTaskForBoundary', 'cancel']]) {
    runtime[method] = async (guid, scope) => {
      assert.equal(scope, boundary);
      calls.push([guid, action]);
      return control(guid, action);
    };
  }
  return { coordinator: new DownloadBatchActionCoordinator(runtime), calls };
}

test('active and completed menus lead with multi-select, including optimistic pause/resume', () => {
  const model = new DownloadManagerViewModel();
  for (const status of ['created', 'awaiting_confirmation', 'queued', 'running', 'paused', 'failed', 'completed']) {
    assert.equal(selection.canSelectDownloadTask(status), true);
    assert.equal(model.buildRowMenuActions(['pause', 'cancel'], status, 'pause')[0].action, 'enter_selection');
  }
  for (const status of ['canceled', 'removed']) assert.equal(selection.canSelectDownloadTask(status), false);
  for (const status of ['running', 'paused']) {
    assert.equal(model.buildOptimisticMenuActions(status)[0].action, 'enter_selection');
  }
  const completed = model.buildRowMenuActions(['save_to_system', 'open_file', 'open_location', 'remove_record'],
    'completed', 'open_file');
  assert.equal(completed.map(item => item.action).join(','),
    'enter_selection,save_to_system,open_location,remove_record,delete_task_and_file,copy_link');
});

test('pause touches only selected, currently supported downloads', async () => {
  const f = fixture([task('running', 'running', ['pause', 'cancel']), task('paused', 'paused', ['resume']),
    task('queued', 'queued', ['cancel']), task('unselected', 'running', ['pause'])]);
  const result = await f.coordinator.execute('pause', ['running', 'paused', 'queued', 'running'], boundary);
  assert.deepEqual(f.calls, [['running', 'pause']]);
  assert.equal(result.succeededGuids.join(','), 'running');
  assert.equal(result.skippedGuids.join(','), 'paused,queued');
});

test('continue respects live resume, retry-only recovery, and unsupported failures', async () => {
  const f = fixture([task('paused', 'paused', ['resume']), task('failed-live', 'failed', ['resume']),
    task('retry-only', 'failed', ['retry']), task('lost-context', 'failed', ['remove_record']),
    task('running', 'running', ['pause'])]);
  const result = await f.coordinator.execute('resume',
    ['paused', 'failed-live', 'retry-only', 'lost-context', 'running'], boundary);
  assert.deepEqual(f.calls, [['paused', 'resume'], ['failed-live', 'resume'], ['retry-only', 'retry']]);
  assert.equal(result.skippedGuids.join(','), 'lost-context,running');
});

test('cancel rechecks completion between commands and cannot reach another private window', async () => {
  const tasks = [task('first', 'running', ['cancel']), task('finishes', 'running', ['cancel']),
    task('other-window', 'running', ['cancel'], { outsideBoundary: true }), task('removed', 'removed', ['cancel'])];
  const f = fixture(tasks, async () => { tasks[1].status = 'completed'; return true; });
  const result = await f.coordinator.execute('cancel', ['first', 'finishes', 'other-window', 'removed'], boundary);
  assert.deepEqual(f.calls, [['first', 'cancel']]);
  assert.equal(result.skippedGuids.join(','), 'finishes,other-window,removed');
});

test('a failed or throwing command does not prevent the remaining downloads from being controlled', async () => {
  const f = fixture(['false', 'throws', 'success'].map(id => task(id, 'running', ['pause'])), async id => {
    if (id === 'throws') throw Error('platform unavailable');
    return id === 'success';
  });
  const result = await f.coordinator.execute('pause', ['false', 'throws', 'success'], boundary);
  assert.equal(result.failedGuids.join(','), 'false,throws');
  assert.equal(result.succeededGuids.join(','), 'success');
});

function method(source, name) {
  const match = source.match(new RegExp(`^  (?:private )?(?:async )?${name}\\([\\s\\S]*?^  \\}`, 'm'));
  assert.ok(match, `missing production method ${name}`);
  return match[0];
}
const screenSource = read('app/components/browser/BrowserDownloadManagementScreen.ets');
const screenMethods = ['collectSelectableRows', 'canEnterSelectionMode', 'enterSelectionMode', 'exitSelectionMode',
  'isRowSelected', 'setRowSelected', 'toggleRowSelection', 'selectAllVisibleRows', 'pruneSelectionToVisibleRows',
  'getRowsForGroup', 'resolveDesktopRows', 'selectGroup', 'syncSelectedGroupFromIndex', 'canControlSelectedRows',
  'buildActiveSelectionToolbarActions', 'requestSelectedTaskAction'].map(name => method(screenSource, name)).join('\n');
let dialog;
const { Screen } = evaluate(`export class Screen { ${screenMethods} }`, {
  ...selection, resolveAppResourceText: resourceText, showCenteredAlertDialog: value => { dialog = value; },
  $r: key => key
});
function screen() {
  return Object.assign(new Screen(), {
    presentationMode: 'page', selectedGroup: 'in_progress', desktopQuery: '', selectedGuids: [], isSelectionMode: false,
    downloadListState: { groups: [
      { group: 'in_progress', rows: [task('active-a', 'running'), task('active-b', 'paused')] },
      { group: 'completed', rows: [task('done', 'completed')] }
    ] },
    showToast() {}, markInteractionQuiet() {}, logDownloadManagementLifecycle() {},
    syncSwiperToSelectedGroup() {}, scheduleDeferredRefresh() {},
    getAvailableGroups() { return this.downloadListState.groups; }
  });
}

test('select all is confined to the visible tab and completion removes a selected active task', () => {
  const ui = screen();
  ui.enterSelectionMode('active-a');
  assert.equal(ui.selectedGuids.join(','), 'active-a');
  ui.selectAllVisibleRows();
  assert.equal(ui.selectedGuids.join(','), 'active-a,active-b');
  ui.downloadListState.groups[0].rows.shift();
  ui.pruneSelectionToVisibleRows();
  assert.equal(ui.selectedGuids.join(','), 'active-b');
  ui.downloadListState.groups[0].rows = [];
  ui.pruneSelectionToVisibleRows();
  assert.equal(ui.isSelectionMode, false);
});

test('desktop select all and refresh respect the current filename search', () => {
  const ui = screen();
  ui.presentationMode = 'native_tab';
  ui.downloadListState.groups[0].rows.forEach(item => { item.fileName = item.guid; });
  ui.desktopQuery = 'active-a';
  ui.enterSelectionMode(); ui.selectAllVisibleRows();
  assert.equal(ui.selectedGuids.join(','), 'active-a');
  ui.desktopQuery = 'active-b'; ui.pruneSelectionToVisibleRows();
  assert.equal(ui.selectedGuids.length, 0);
  assert.equal(ui.isSelectionMode, true);
});

test('both tab selection and swiping exit selection; completed select all stays isolated', () => {
  for (const change of [ui => ui.selectGroup('completed'), ui => ui.syncSelectedGroupFromIndex(1)]) {
    const ui = screen(); ui.enterSelectionMode('active-a'); change(ui);
    assert.equal(ui.isSelectionMode, false);
    assert.equal(ui.selectedGuids.length, 0);
    ui.enterSelectionMode(); ui.selectAllVisibleRows();
    assert.equal(ui.selectedGuids.join(','), 'done');
  }
});

test('cancel waits for confirmation and retains the reviewed selection and boundary', () => {
  const ui = screen();
  const row = ui.downloadListState.groups[0].rows[0];
  row.primaryAction = 'pause'; row.menuActions = [{ action: 'cancel' }];
  ui.enterSelectionMode('active-a');
  ui.getCurrentDownloadBoundary = () => boundary;
  const calls = [];
  ui.performSelectedTaskAction = (...args) => { calls.push(args); };
  ui.requestSelectedTaskAction('cancel');
  assert.equal(calls.length, 0);
  dialog.buttons[0].action();
  assert.equal(calls.length, 0);
  ui.selectedGuids = ['active-b'];
  dialog.buttons[1].action();
  assert.equal(calls[0][0], 'cancel');
  assert.equal(calls[0][1].join(','), 'active-a');
  assert.equal(calls[0][2], boundary);
  ui.batchActionBusy = true;
  assert.equal(ui.canControlSelectedRows('pause'), false);
});

test('toolbar availability follows selection, task state changes, and the batch busy state', () => {
  const ui = screen();
  const [active, paused] = ui.downloadListState.groups[0].rows;
  active.primaryAction = 'pause'; active.menuActions = [{ action: 'cancel' }];
  paused.primaryAction = 'resume'; paused.menuActions = [{ action: 'cancel' }];
  const enabled = () => ui.buildActiveSelectionToolbarActions().map(item => item.enabled).join(',');
  ui.enterSelectionMode('active-a');
  assert.equal(enabled(), 'true,false,true');
  ui.toggleRowSelection('active-a'); ui.toggleRowSelection('active-b');
  assert.equal(enabled(), 'false,true,true');
  paused.status = 'running'; paused.primaryAction = 'pause';
  assert.equal(enabled(), 'true,false,true');
  ui.batchActionBusy = true;
  assert.equal(enabled(), 'false,false,false');
  const toolbar = read('app/components/common/FloatingSelectionToolbar.ets');
  assert.match(toolbar, /@Prop actions:/, 'the mounted toolbar must receive updated action descriptors');
  assert.match(toolbar, /`selection-\$\{index\}:\$\{item\.enabled/,
    'a retained ForEach item must not keep an obsolete enabled flag');
});

test('a mounted toolbar refreshes formatted counts and select-all labels while actions stay enabled', () => {
  const toolbar = read('app/components/common/FloatingSelectionToolbar.ets');
  const keyExpression = toolbar.match(
    /\}, \(item: FloatingSelectionToolbarAction, index: number\) =>\s*(`[^`]+`)\)/
  );
  assert.ok(keyExpression, 'use the production ForEach key generator');
  const text = title => typeof title === 'string' ? title : `Download (${title.params[0]})`;
  const { actionKey } = evaluate(`export const actionKey = (item, index) => ${keyExpression[1]};`, {
    resolveAppResourceText: text
  });
  // Model ArkUI retaining a child when its key has not changed.
  let mounted = new Map();
  const render = actions => {
    const next = new Map();
    const rows = actions.map((action, index) => {
      const key = actionKey(action, index);
      const row = mounted.get(key) || { label: text(action.title), enabled: action.enabled };
      next.set(key, row);
      return row;
    });
    mounted = next;
    return rows;
  };
  for (const count of [1, 2, 12, 192, 2, 0, 1]) {
    const selectAllLabel = count === 192 ? 'Deselect all' : 'Select all';
    const rows = render([
      { title: selectAllLabel, enabled: true },
      { title: 'Copy links', enabled: count > 0 },
      { title: { id: 77, params: [count] }, enabled: count > 0 }
    ]);
    assert.equal(rows[0].label, selectAllLabel);
    assert.equal(rows[2].label, `Download (${count})`);
    assert.equal(rows[2].enabled, count > 0);
  }
});

const { Service } = evaluate(`export class Service {
  ${method(read('services/downloadv2/DownloadV2Service.ets'), 'cancelAndRemoveTask')}
}`);
test('completion winning during native cancellation keeps the completed record and file', async () => {
  const service = new Service();
  let current = task('racing', 'running', ['cancel']);
  let cleanupCount = 0;
  service.engine = { findTask: () => current, removeTaskRecord: () => { throw Error('must keep completed record'); } };
  service.cancelTask = async () => { current = { ...current, status: 'completed' }; return false; };
  service.cleanupLocalTempFile = async () => { cleanupCount++; };
  service.canRemoveTaskLocally = () => true;
  assert.equal(await service.cancelAndRemoveTask('racing'), false);
  assert.equal(cleanupCount, 0);
});
