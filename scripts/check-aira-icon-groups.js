#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const iconSourceRoot = path.join(repoRoot, 'resources/icon-sources/aira');
const iconMapPath = path.join(iconSourceRoot, 'icon-map.json');
const iconGroupsPath = path.join(iconSourceRoot, 'icon-groups.json');
const actionCatalogPath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserBottomPanelActionCatalog.ets'
);
const preferencesRepositoryPath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/data/preferences/PreferencesRepository.ets'
);

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function fail(message) {
  console.error(message);
  process.exitCode = 1;
}

function requireUnique(values, label) {
  const seen = new Set();
  values.forEach((value) => {
    if (seen.has(value)) {
      fail(`Duplicate ${label}: ${value}`);
    }
    seen.add(value);
  });
}

function parseCustomizableActionIds() {
  const source = fs.readFileSync(actionCatalogPath, 'utf8');
  const ids = [];
  source.split('\n').forEach((line) => {
    const match = line.match(/\{\s*id:\s*'([^']+)'[\s\S]*customizable:\s*true[\s\S]*\}/);
    if (match) {
      ids.push(match[1]);
    }
  });
  return ids;
}

function compareOrderedLists(expected, actual, label) {
  const expectedJoined = expected.join(',');
  const actualJoined = actual.join(',');
  if (expectedJoined === actualJoined) {
    return;
  }

  fail(`${label} is out of sync.`);
  const expectedSet = new Set(expected);
  const actualSet = new Set(actual);
  expected.filter((item) => !actualSet.has(item)).forEach((item) => {
    console.error(`- Missing from app catalog: ${item}`);
  });
  actual.filter((item) => !expectedSet.has(item)).forEach((item) => {
    console.error(`- Missing from icon group: ${item}`);
  });
  if (expected.length === actual.length && expected.every((item) => actualSet.has(item))) {
    console.error('- Same action ids, but order differs.');
  }
}

function compareSets(expected, actual, label) {
  const expectedSet = new Set(expected);
  const actualSet = new Set(actual);
  const missingFromActual = expected.filter((item) => !actualSet.has(item));
  const missingFromExpected = actual.filter((item) => !expectedSet.has(item));
  if (missingFromActual.length <= 0 && missingFromExpected.length <= 0) {
    return;
  }

  fail(`${label} is out of sync.`);
  missingFromActual.forEach((item) => {
    console.error(`- Missing from app catalog: ${item}`);
  });
  missingFromExpected.forEach((item) => {
    console.error(`- Missing from icon group: ${item}`);
  });
}

function parseDefaultToolbarActionIds() {
  const source = fs.readFileSync(preferencesRepositoryPath, 'utf8');
  const match = source.match(/DEFAULT_BROWSER_TOOLBAR_LAYOUT_SETTINGS[\s\S]*?primaryActionIds:\s*\[([\s\S]*?)\]/);
  if (!match) {
    fail('Unable to parse DEFAULT_BROWSER_TOOLBAR_LAYOUT_SETTINGS.primaryActionIds.');
    return [];
  }
  const ids = [];
  const idPattern = /'([^']+)'/g;
  let idMatch = idPattern.exec(match[1]);
  while (idMatch !== null) {
    ids.push(idMatch[1]);
    idMatch = idPattern.exec(match[1]);
  }
  return ids;
}

function main() {
  const iconMap = readJson(iconMapPath);
  const iconGroups = readJson(iconGroupsPath);
  const familyToSource = new Map();

  iconMap.forEach((entry) => {
    (entry.resourceFamilies ?? []).forEach((family) => {
      if (familyToSource.has(family)) {
        fail(`Resource family ${family} appears in multiple icon-map entries.`);
        return;
      }
      familyToSource.set(family, entry.exportedFile);
    });
  });

  const groups = iconGroups.groups ?? [];
  requireUnique(groups.map((group) => group.id), 'icon group id');

  groups.forEach((group) => {
    const entries = group.entries ?? [];
    if (entries.length <= 0) {
      fail(`Icon group ${group.id} has no entries.`);
      return;
    }
    requireUnique(entries.map((entry) => entry.actionId).filter(Boolean), `${group.id} actionId`);
    entries.forEach((entry) => {
      if (!entry.resourceFamily || !familyToSource.has(entry.resourceFamily)) {
        fail(`Icon group ${group.id} maps ${entry.actionId ?? entry.title ?? 'entry'} to unknown resourceFamily ${entry.resourceFamily}`);
      }
    });
  });

  const bottomToolbarGroup = groups.find((group) => group.id === 'bottom-toolbar-customizable');
  if (!bottomToolbarGroup) {
    fail('Missing icon group: bottom-toolbar-customizable');
  } else {
    const groupedActionIds = (bottomToolbarGroup.entries ?? []).map((entry) => entry.actionId).filter(Boolean);
    const appCatalogActionIds = parseCustomizableActionIds();
    const defaultToolbarActionIds = parseDefaultToolbarActionIds();
    compareSets(groupedActionIds, appCatalogActionIds, 'bottom-toolbar-customizable action set');
    compareOrderedLists(groupedActionIds, defaultToolbarActionIds, 'bottom-toolbar-customizable default order');
  }

  if (process.exitCode && process.exitCode !== 0) {
    return;
  }
  console.log(`Checked ${groups.length} Aira icon groups.`);
}

main();
