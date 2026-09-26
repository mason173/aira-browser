#!/usr/bin/env node
'use strict';

// One or two dialog actions sit side by side and share the row. Three or more stack,
// primary action first, and a stacked action must opt out of the Row width weight.
//
// Why this exists: BrowserSheetActionButton uses layoutWeight to split a Row's width,
// and that weight is the main axis. The same weight inside a Column stretches the
// button vertically. A later rule put 1–2 actions back in a Row and kept 3+ stacked.
// Both the stretch and a 3-across row are cheap to reintroduce, so they are scanned here.
//
// The scan is textual and conservative: it only inspects a container whose whole body is
// action buttons (or a single builder call that renders them), so two-column rows that
// are not actions (segmented controls, label/value pairs) are never matched.
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const BUTTON = 'BrowserSheetActionButton({';
const OTHER_COMPONENT = /\b(Text|Column|Row|Image|Stack|Toggle|Checkbox|ForEach|List|Grid)\s*\(/;
const BUTTON_CALL = /BrowserSheetActionButton\(\{[\s\S]*?\n\s*\}\)/g;
const BUILDER_CALL = /^(\s*)this\.(\w+)\(\);?\s*$/;

function listEtsFiles(dir) {
  const files = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...listEtsFiles(full));
    } else if (entry.name.endsWith('.ets')) {
      files.push(full);
    }
  }
  return files;
}

/** Collects `Component(...) { ... }` blocks by matching each closing brace at its own indent. */
function collectBlocks(lines, component) {
  const opener = new RegExp(`^(\\s*)${component}\\((?:\\{ space: \\d+ \\})?\\) \\{$`);
  const blocks = [];
  for (let index = 0; index < lines.length; index += 1) {
    const match = opener.exec(lines[index]);
    if (match === null) {
      continue;
    }
    const indent = match[1].length;
    const body = [];
    let cursor = index + 1;
    while (cursor < lines.length) {
      const line = lines[cursor];
      if (line.trim() === '}' && line.length - line.trimStart().length === indent) {
        break;
      }
      body.push(line);
      cursor += 1;
    }
    blocks.push({ line: index + 1, indent, body: body.join('\n'), lines: body });
  }
  return blocks;
}

function buttonCount(text) {
  return (text.match(/BrowserSheetActionButton\(\{/g) ?? []).length;
}

function isPureActionBody(body) {
  if (buttonCount(body) < 2) {
    return false;
  }
  return !OTHER_COMPONENT.test(body.replace(BUTTON_CALL, ''));
}

/** The single `this.buildX()` a block wraps, when that builder is the whole body. */
function wrappedBuilder(bodyLines) {
  const meaningful = bodyLines.filter((line) => line.trim().length > 0);
  if (meaningful.length !== 1) {
    return undefined;
  }
  return BUILDER_CALL.exec(meaningful[0])?.[2];
}

function readBuilders(source) {
  const builders = new Map();
  const lines = source.split('\n');
  for (let index = 0; index < lines.length; index += 1) {
    const match = /^(\s*)private\s+(\w+)\([^)]*\)\s*\{$/.exec(lines[index]);
    if (match === null) {
      continue;
    }
    const indent = match[1].length;
    const body = [];
    let cursor = index + 1;
    while (cursor < lines.length) {
      const line = lines[cursor];
      if (line.trim() === '}' && line.length - line.trimStart().length === indent) {
        break;
      }
      body.push(line);
      cursor += 1;
    }
    builders.set(match[2], body.join('\n'));
  }
  return builders;
}

function firstButtonIndexWithPrimary(body) {
  const starts = [];
  let at = body.indexOf(BUTTON);
  while (at >= 0) {
    starts.push(at);
    at = body.indexOf(BUTTON, at + 1);
  }
  for (let index = 0; index < starts.length; index += 1) {
    const slice = body.slice(starts[index], starts[index + 1] ?? body.length);
    if (/emphasis: 'primary'/.test(slice)) {
      return index;
    }
  }
  return -1;
}

function stackedMissing(body) {
  const starts = [];
  let at = body.indexOf(BUTTON);
  while (at >= 0) {
    starts.push(at);
    at = body.indexOf(BUTTON, at + 1);
  }
  for (let index = 0; index < starts.length; index += 1) {
    const slice = body.slice(starts[index], starts[index + 1] ?? body.length);
    if (!/stacked: true/.test(slice)) {
      return true;
    }
  }
  return false;
}

const sideBySide = [];
const builderSideBySide = [];
const notStacked = [];
const wrongOrder = [];

for (const file of listEtsFiles(ROOT)) {
  const source = fs.readFileSync(file, 'utf8');
  const lines = source.split('\n');
  const relative = path.relative(path.resolve(__dirname, '..'), file);
  const builders = readBuilders(source);

  for (const block of collectBlocks(lines, 'Row')) {
    if (isPureActionBody(block.body) && buttonCount(block.body) >= 3) {
      sideBySide.push(`${relative}:${block.line}`);
      continue;
    }
    if (isPureActionBody(block.body) && /stacked: true/.test(block.body)) {
      notStacked.push(`${relative}:${block.line} a side-by-side pair must not pass stacked: true`);
      continue;
    }
    const builder = wrappedBuilder(block.lines);
    const builderBody = builder === undefined ? '' : (builders.get(builder) ?? '');
    if (builder !== undefined && buttonCount(builderBody) >= 3) {
      builderSideBySide.push(`${relative}:${block.line} this.${builder}()`);
    }
  }

  // A builder that only renders action buttons must stack them itself: a caller may host
  // it in a Row footer, and two stacked (width 100%) actions there overflow the sheet.
  for (const [name, body] of builders) {
    if (!isPureActionBody(body) || /^\s*(Column|Row)\(/m.test(body.split('\n').find((line) => line.trim().length > 0) ?? '')) {
      continue;
    }
    notStacked.push(`${relative} ${name}() must wrap its actions in a Column`);
  }

  for (const block of collectBlocks(lines, 'Column')) {
    if (isPureActionBody(block.body) && buttonCount(block.body) === 2) {
      sideBySide.push(`${relative}:${block.line} two actions must sit side by side`);
      continue;
    }
    if (isPureActionBody(block.body)) {
      if (stackedMissing(block.body)) {
        notStacked.push(`${relative}:${block.line}`);
      }
      if (firstButtonIndexWithPrimary(block.body) > 0) {
        wrongOrder.push(`${relative}:${block.line}`);
      }
      continue;
    }
    const builder = wrappedBuilder(block.lines);
    const builderBody = builder === undefined ? '' : (builders.get(builder) ?? '');
    if (buttonCount(builderBody) >= 2 && !/stacked: true/.test(builderBody)) {
      notStacked.push(`${relative}:${block.line} this.${builder}()`);
    }
  }
}

// The clear-browsing-data picker is a tall bottom sheet on the phone shell; only the PC
// pane keeps the centered dialog. Pinned here because the shared content component makes
// it easy to hand the wrong presentation to one of the two callers.
const phoneSettingsPage = path.join(ROOT, 'app/pages/SettingsDetailPage.ets');
const phoneSettingsSource = fs.readFileSync(phoneSettingsPage, 'utf8');
const presentationViolations = [];
if (!phoneSettingsSource.includes('ClearBrowsingDataContent')) {
  presentationViolations.push('SettingsDetailPage must host the shared clear-data content');
}
if (phoneSettingsSource.includes('builder: ClearBrowsingDataDialog(')) {
  presentationViolations.push('SettingsDetailPage must not present clear-data as a centered dialog');
}
if (!/bindSheet\(\$\$this\.clearBrowsingDataSheetVisible/.test(phoneSettingsSource)) {
  presentationViolations.push('SettingsDetailPage must present clear-data in a bottom sheet');
}
const clearContent = fs.readFileSync(
  path.join(ROOT, 'app/components/settings/ClearBrowsingDataDialog.ets'), 'utf8');
// The phone sheet uses the shared half-modal header. The close button is the layout overlay,
// aligned with the title, not a second button drawn inside the title row or by the platform.
if (!clearContent.includes('BrowserImmersiveSheetLayout')) {
  presentationViolations.push('the clear-data sheet must keep the immersive sheet layout');
}
if (!clearContent.includes('BrowserFeatureSheetHeader')) {
  presentationViolations.push('the clear-data sheet must use the shared half-modal title');
}
if (!/BrowserImmersiveSheetLayout\(\{[\s\S]*?closeVisible: true/.test(clearContent)) {
  presentationViolations.push('the clear-data sheet must use the shared half-modal close button');
}
const inlinePanelPath = path.join(ROOT, 'app/components/settings/SettingsInlineDetailPanel.ets');
const inlinePanelSource = fs.readFileSync(inlinePanelPath, 'utf8');
for (const [source, label] of [[phoneSettingsSource, 'SettingsDetailPage'], [inlinePanelSource, 'SettingsInlineDetailPanel']]) {
  const sheet = /bindSheet\(\$\$this\.clearBrowsingDataSheetVisible[\s\S]{0,700}?\)\)/.exec(source)?.[0] ?? '';
  if (!/showClose: false/.test(sheet)) {
    presentationViolations.push(`${label} must let the sheet content own the close button`);
  }
  if (/title: \{ title: this\.clearBrowsingDataDialogState\.title \}/.test(sheet)) {
    presentationViolations.push(`${label} must not add a platform title over the in-content header`);
  }
  // The layoutMode lives in the sheet builder, not in the bindSheet options.
  if (!/buildClearBrowsingDataSheet\(\)[\s\S]*?layoutMode: 'sheet'/.test(source)) {
    presentationViolations.push(`${label} must host the clear-data sheet in its sheet layout`);
  }
}

// A lambda passed to a named @BuilderParam must call a @Builder, not construct a component
// inline. The inline form compiles and then crashes at render with
// "class constructor cannot called without 'new'".
const builderParamViolations = [];
for (const file of listEtsFiles(ROOT)) {
  const source = fs.readFileSync(file, 'utf8');
  const relative = path.relative(path.resolve(__dirname, '..'), file);
  const entries = source.matchAll(
    /\b(scrollContent|header|footer|content|trailing|customLeading|contentBuilder)\s*:\s*\(\)\s*=>\s*\{\s*\n\s*([A-Z]\w+)\(\)?\s*\{/g);
  for (const entry of entries) {
    const line = source.slice(0, entry.index).split('\n').length;
    builderParamViolations.push(
      `${relative}:${line} ${entry[1]} constructs ${entry[2]} inline; call an @Builder method instead`);
  }
}

function report(header, entries) {
  if (entries.length === 0) {
    return;
  }
  console.error(header);
  for (const entry of entries) {
    console.error(`  ${entry}`);
  }
}

report('Dialog action rows must be one or two buttons, and a pair must not stay stacked:', sideBySide);
report('A builder that renders three or more actions must not sit in a Row:', builderSideBySide);
report('A stacked action must pass stacked: true so it keeps its height:', notStacked);
report('A stacked action group must put the primary action first:', wrongOrder);
report('The phone shell must present the clear-data picker as a sheet:', presentationViolations);
report('A named @BuilderParam must receive a @Builder call, not an inline component:', builderParamViolations);
if (sideBySide.length + builderSideBySide.length + notStacked.length + wrongOrder.length +
  presentationViolations.length + builderParamViolations.length > 0) {
  process.exitCode = 1;
} else {
  console.log('Dialog action layout passed: one or two actions sit side by side; three or more stack.');
}
