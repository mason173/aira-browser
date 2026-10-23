// Run the production overlay's timeline handlers with the live-stream shape
// observed on-device: duration=0 (Web duration=Infinity), position ~= 6700s.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const filename = path.resolve(__dirname,
  '../AiraBrowser/entry/src/main/ets/app/components/browser/BrowserVideoAssistantPlayerOverlay.ets');
const source = fs.readFileSync(filename, 'utf8');
function method(name) {
  const match = source.match(new RegExp(`  private ${name}\\([^]*?\\n  }`));
  assert.ok(match, `production handler ${name} must exist`);
  return match[0];
}
const methods = ['resolveDisplayPositionSeconds', 'resolveDurationSeconds', 'resolveTimelineValue',
  'clampSeconds', 'handleTimelineChange', 'commitSeek'].map(method).join('\n');
const code = ts.transpileModule(`class Timeline {
  playerState = { positionSeconds: 6700, durationSeconds: 0 };
  scrubberActive = false;
  scrubberPositionSeconds = 0;
  controlsVisible = false;
  commands = [];
  clearControlsHideTimer() {}
  showControlsTemporarily() {}
  dispatchWebLiveCommand(command) { this.commands.push(command); }
  ${methods}
}
module.exports = Timeline;`, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText;
const moduleObject = { exports: {} };
const modes = { Begin: 0, Moving: 1, End: 2, Click: 3 };
vm.runInNewContext(code, { module: moduleObject, SliderChangeMode: modes });
const Timeline = moduleObject.exports;
const live = new Timeline();
// ArkUI clamps an out-of-range Slider value and can report its value change.
// Replaying that callback must never turn playback-position updates into seeks.
for (let frame = 0; frame < 300; frame++) {
  live.playerState.positionSeconds += 1 / 30;
  const value = live.resolveTimelineValue();
  assert.ok(value >= 0 && value <= 1, 'live timeline value exceeds its Slider max=1');
  live.handleTimelineChange(1, modes.Click);
  live.handleTimelineChange(1, modes.End);
}
assert.equal(live.commands.length, 0, 'live position updates must not create a seek/toast feedback loop');
assert.equal(live.controlsVisible, false, 'live slider callbacks must not keep controls flashing');
live.commitSeek(10);
assert.equal(live.commands.length, 0, 'non-seekable live playback also rejects seek buttons');
for (const duration of [NaN, Infinity, -1]) {
  live.playerState.durationSeconds = duration;
  assert.equal(live.resolveDurationSeconds(), 0);
  assert.equal(live.resolveTimelineValue(), 0);
  live.handleTimelineChange(1, modes.Click);
}
assert.equal(live.commands.length, 0);

const vod = new Timeline();
vod.playerState = { positionSeconds: 35, durationSeconds: 120 };
assert.equal(vod.resolveTimelineValue(), 35);
vod.handleTimelineChange(50, modes.Begin);
vod.handleTimelineChange(60, modes.Moving);
assert.equal(vod.commands.length, 0);
vod.handleTimelineChange(60, modes.End);
assert.equal(vod.commands.length, 1);
assert.equal(vod.commands[0].value, 60);
vod.handleTimelineChange(200, modes.Click);
assert.equal(vod.commands.at(-1).value, 120);
vod.commitSeek(-10);
assert.equal(vod.commands.at(-1).value, 0);
assert.match(source, /\.enabled\(this\.resolveDurationSeconds\(\) > 0\)/,
  'the native live Slider must be disabled as well as guarded');
console.log('Live timeline contract passed (300 live frames, no-duration callbacks, VOD seeking).');
