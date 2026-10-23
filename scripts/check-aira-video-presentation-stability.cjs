// Exercises the generated production page script. A layout that settles later
// must not cause repeated writes of already-applied CSS on the same live video.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
function load(relative) {
  const filename = path.join(root, relative);
  const module = { exports: {} };
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
  }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, $r: key => key,
    require(specifier) {
      if (specifier === '@kit.ArkWeb') return { webview: {} };
      if (specifier.endsWith('/AppResourceText')) return { resolveAppResourceText: key => key };
      if (specifier.endsWith('/WebVideoRuntimeProtocol')) return load('services/video/WebVideoRuntimeProtocol.ets');
      if (specifier.endsWith('/WebVideoFrameCommandTransport')) return load('services/video/WebVideoFrameCommandTransport.ets');
      throw Error(`Unexpected dependency: ${specifier}`);
    }
  });
  return module.exports;
}
const { WebVideoPresentationService } = load('services/video/WebVideoPresentationService.ets');
const service = new WebVideoPresentationService();
const generated = service.buildExecuteLiveCommandScript({ runtimeId: 'video', elementId: '', source: '' },
  { action: 'rate', value: 1 });
const methods = {};
const node = ts.createSourceFile('page.js', generated, ts.ScriptTarget.ES2020, true, ts.ScriptKind.JS);
function visit(n) {
  if (ts.isFunctionDeclaration(n) && n.name) methods[n.name.text] = n.getText(node);
  ts.forEachChild(n, visit);
}
visit(node);
let writes = 0;
function style(countWrites = true) {
  const values = new Map();
  return {
    getPropertyValue: key => values.get(key)?.value || '',
    getPropertyPriority: key => values.get(key)?.priority || '',
    setProperty(key, value, priority) {
      if (countWrites) writes++;
      if (/^(margin|padding|top|left)$/.test(key) && value === '0') value = '0px';
      if (key === 'background-color' && value === '#000') value = 'rgb(0, 0, 0)';
      values.set(key, { value, priority });
    }
  };
}
const context = vm.createContext({ document: { createElement: () => ({ style: style(false) }) },
  video: null, controlsHiddenMarkerAttribute: 'marker' });
vm.runInContext(`${methods.applyImportantStyles}\n${methods.enforceNativeControlsHidden}`, context);
const element = { style: style() };
context.applyImportantStyles(element, { position: 'fixed', margin: '0', 'background-color': '#000' });
const firstWrites = writes;
for (let frame = 0; frame < 300; frame++) {
  context.applyImportantStyles(element, { position: 'fixed', margin: '0', 'background-color': '#000' });
}
assert.equal(writes, firstWrites, 'unchanged CSS must not retrigger observers/native video layout every frame');
element.style.setProperty('position', 'absolute', 'important');
context.applyImportantStyles(element, { position: 'fixed' });
assert.equal(element.style.getPropertyValue('position'), 'fixed', 'real site changes still need repair');
element.style.setProperty('position', 'fixed', '');
context.applyImportantStyles(element, { position: 'fixed' });
assert.equal(element.style.getPropertyPriority('position'), 'important');
let controlsWrites = 0;
let controls = false;
const media = {
  get controls() { return controls; }, set controls(value) { controlsWrites++; controls = value; },
  hasAttribute: () => false,
  removeAttribute: () => controlsWrites++, getAttribute: () => 'true', setAttribute: () => controlsWrites++
};
for (let frame = 0; frame < 300; frame++) context.enforceNativeControlsHidden(media);
assert.equal(controlsWrites, 0, 'already-hidden controls must not be rewritten');
console.log('Video presentation stability passed (300 repeated repairs, CSS normalization, external changes).');
