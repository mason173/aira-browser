// Check computed styles in a local headless fixture, without taking screenshots
// or visiting a user page. Exercise the production SVG factory against page CSS.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const cp = require('node:child_process');
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
const generated = new WebVideoPresentationService().buildExecuteLiveCommandScript(
  { runtimeId: 'video', elementId: '', source: '' }, { action: 'install_action_toolbar' });
const tree = ts.createSourceFile('page.js', generated, ts.ScriptTarget.ES2020, true, ts.ScriptKind.JS);
const declarations = new Map();
let applyImportantStyles = '';
function visit(node) {
  if (ts.isVariableDeclaration(node) && node.name && node.initializer) {
    declarations.set(node.name.getText(tree), node.initializer.getText(tree));
  }
  if (ts.isFunctionDeclaration(node) && node.name?.text === 'applyImportantStyles') {
    applyImportantStyles = node.getText(tree);
  }
  ts.forEachChild(node, visit);
}
visit(tree);
const definitions = ['svgNamespace', 'castIconPaths', 'pictureInPictureIconPaths', 'fullscreenIconPaths', 'createIcon']
  .map(name => {
    assert.ok(declarations.has(name), `missing production ${name}`);
    return `var ${name} = ${declarations.get(name)};`;
  }).join('\n');
const fixture = `<!doctype html><meta charset="utf-8"><style>
  /* A video site's global SVG rules override presentation attributes, including
     descendant paths that do not inherit the root's stroke/fill settings. */
  .site-player svg { width: 80px !important; height: 80px !important; fill: red !important;
    stroke: red !important; stroke-width: 9px !important; transform: scale(2) !important;
    visibility: visible !important; }
  .site-player svg path { fill: currentColor !important; stroke: red !important;
    color: red !important; stroke-width: 8px !important; stroke-linecap: butt !important;
    stroke-dasharray: 1 2 !important; transform: scale(2) !important; visibility: visible !important; }
</style><div class="site-player" id="host"></div><pre id="result"></pre><script>
var ownerDocument = document;
${applyImportantStyles}
${definitions}
var output = [];
['rgb(22, 24, 29)', 'rgb(255, 255, 255)'].forEach(function (color) {
  [castIconPaths, pictureInPictureIconPaths, fullscreenIconPaths].forEach(function (paths) {
    var button = document.createElement('button');
    button.style.color = color;
    var icon = createIcon(paths);
    button.appendChild(icon);
    document.getElementById('host').appendChild(button);
    var rootStyle = getComputedStyle(icon);
    output.push({ color: color, width: rootStyle.width, height: rootStyle.height,
      fill: rootStyle.fill, stroke: rootStyle.stroke, transform: rootStyle.transform,
      viewBox: icon.getAttribute('viewBox'), paths: Array.from(icon.children).map(function (p) {
        var s = getComputedStyle(p);
        return { fill: s.fill, stroke: s.stroke, width: s.strokeWidth, cap: s.strokeLinecap,
          dash: s.strokeDasharray, transform: s.transform, d: p.getAttribute('d') };
      }), expectedPaths: paths });
    var nextColor = color === 'rgb(22, 24, 29)' ? 'rgb(255, 255, 255)' : 'rgb(22, 24, 29)';
    button.style.color = nextColor;
    output[output.length - 1].nextColor = nextColor;
    output[output.length - 1].nextStroke = getComputedStyle(icon).stroke;
    output[output.length - 1].nextPaths = Array.from(icon.children).map(function (p) {
      return getComputedStyle(p).stroke;
    });
    button.style.visibility = 'hidden';
    output[output.length - 1].hiddenVisibility = getComputedStyle(icon).visibility;
    output[output.length - 1].hiddenPaths = Array.from(icon.children).map(function (p) {
      return getComputedStyle(p).visibility;
    });
  });
});
document.getElementById('result').textContent = JSON.stringify(output);
</script>`;
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'aira-video-icons-'));
try {
  const html = path.join(directory, 'fixture.html');
  fs.writeFileSync(html, fixture);
  const chrome = process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  const result = cp.spawnSync(chrome, ['--headless', '--no-sandbox', '--disable-gpu', '--no-first-run',
    '--disable-background-networking', '--disable-extensions', `--user-data-dir=${directory}/profile`,
    '--dump-dom', `file://${html}`], { encoding: 'utf8', timeout: 25000, maxBuffer: 2 * 1024 * 1024 });
  assert.equal(result.status, 0, `headless style check failed: ${result.error || result.stderr.slice(-1000)}`);
  const match = result.stdout.match(/<pre id="result">([^<]+)<\/pre>/);
  assert.ok(match, 'fixture did not produce computed styles');
  const values = JSON.parse(match[1].replace(/&quot;/g, '"').replace(/&amp;/g, '&'));
  assert.equal(values.length, 6);
  for (const icon of values) {
    assert.equal(icon.width, '24px', 'page CSS distorted toolbar icon size');
    assert.equal(icon.height, '24px');
    assert.equal(icon.viewBox, '0 0 30 30');
    assert.equal(icon.fill, 'none', 'page CSS filled a line icon');
    assert.equal(icon.stroke, icon.color);
    assert.equal(icon.transform, 'none');
    assert.equal(icon.nextStroke, icon.nextColor, 'existing icons must follow a theme/busy color change');
    assert.ok(icon.nextPaths.every(value => value === icon.nextColor));
    assert.equal(icon.hiddenVisibility, 'hidden', 'icon must follow toolbar visibility during takeover');
    assert.ok(icon.hiddenPaths.every(value => value === 'hidden'));
    assert.deepEqual(icon.paths.map(p => p.d), icon.expectedPaths, 'original icon paths must be preserved');
    for (const p of icon.paths) {
      assert.equal(p.fill, 'none');
      assert.equal(p.stroke, icon.color, 'path selectors must not override the theme color');
      assert.equal(p.width, '2.3px');
      assert.equal(p.cap, 'round');
      assert.equal(p.dash, 'none');
      assert.equal(p.transform, 'none');
    }
  }
  console.log('Video toolbar icons passed (3 original icons, light/dark colors, hostile SVG/path CSS).');
} finally {
  fs.rmSync(directory, { recursive: true, force: true });
}
