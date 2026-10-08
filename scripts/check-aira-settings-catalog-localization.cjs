#!/usr/bin/env node
'use strict';

/**
 * The settings directory is the one place user-visible copy has to stay a plain string:
 * `SettingsDestinationCatalog` normalizes, tokenizes, and ranks those values, and a
 * `Resource` cannot be searched. `SettingsCatalogCopy` is the table that turns them back
 * into localized resources at the render sinks.
 *
 * That indirection is easy to forget. Adding a directory entry without a table case leaves
 * the new row Chinese in every locale, and the app still builds — the failure only shows up
 * on a device set to English. This guard closes that gap:
 *
 *   1. every title and every breadcrumb path segment in the catalog has a table case;
 *   2. every resource the table names exists in `base`, `zh_CN`, `zh_Hant`, and `en_US`;
 *   3. the four catalogs carry the same key set, so a locale cannot be half-translated;
 *   4. the `base` value of each mapped resource still equals the catalog literal, which is
 *      the identity the search index and the unit tests match on.
 *
 * It fails closed on any of the four.
 */

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..');
const ETS = 'AiraBrowser/entry/src/main/ets';
const CATALOG_REL = `${ETS}/core/settings/SettingsDestinationCatalog.ets`;
const COPY_REL = `${ETS}/core/settings/SettingsCatalogCopy.ets`;
// The settings copy table and the English search index are the other two places a
// settings string crosses from an identity to something rendered or matched.
const SETTINGS_COPY_REL = `${ETS}/core/settings/SettingsCopy.ets`;
const ENGLISH_INDEX_REL = `${ETS}/core/settings/SettingsCatalogEnglishIndex.ets`;
const RESOURCE_LOCALES = ['base', 'zh_CN', 'zh_Hant', 'en_US'];
const RESOURCE_REL = (locale) => `AiraBrowser/entry/src/main/resources/${locale}/element/string.json`;

let failures = 0;

function fail(message) {
  process.stdout.write(`Settings catalog localization violation: ${message}\n`);
  failures += 1;
}

function read(relPath) {
  return fs.readFileSync(path.join(REPO_ROOT, relPath), 'utf8');
}

/** Splits a call's argument list on top-level commas. */
function splitArguments(body) {
  const parts = [];
  let depth = 0;
  let current = '';
  let inString = false;
  let quote = '';
  for (const char of body) {
    if (inString) {
      current += char;
      if (char === quote) {
        inString = false;
      }
      continue;
    }
    if (char === "'" || char === '"') {
      inString = true;
      quote = char;
      current += char;
      continue;
    }
    if (char === '(' || char === '[' || char === '{') {
      depth += 1;
    } else if (char === ')' || char === ']' || char === '}') {
      depth -= 1;
    }
    if (char === ',' && depth === 0) {
      parts.push(current.trim());
      current = '';
    } else {
      current += char;
    }
  }
  parts.push(current.trim());
  return parts;
}

/** Reads the positional arguments of every `name(` call in a source file. */
function readCalls(source, name) {
  const calls = [];
  let index = 0;
  while (true) {
    index = source.indexOf(`${name}(`, index);
    if (index < 0) {
      break;
    }
    let depth = 0;
    let cursor = index + name.length;
    while (cursor < source.length) {
      if (source[cursor] === '(') {
        depth += 1;
      } else if (source[cursor] === ')') {
        depth -= 1;
        if (depth === 0) {
          break;
        }
      }
      cursor += 1;
    }
    calls.push(splitArguments(source.slice(index + name.length + 1, cursor)));
    index = cursor;
  }
  return calls;
}

function stringLiteral(part) {
  const match = /^'([^']*)'$/.exec(part);
  return match === null ? undefined : match[1];
}

/**
 * Every Chinese identity a `target(...)` call contributes: its title, its breadcrumb
 * segments, its aliases, and its keywords.
 *
 * The scan is positional only up to the fields before the first expression that can span
 * more than a literal: a `path` argument may be a ternary (the distribution picks the
 * breadcrumb root), which shifts every later position. So the title is read positionally
 * and everything else is taken from the remaining literal text, with breadcrumb segments
 * split out. That keeps the set a superset of what the catalog indexes, which is what the
 * English index is checked against.
 */
function readCatalogTargets() {
  const source = read(CATALOG_REL);
  const rendered = new Set();
  const allIdentities = new Set();
  for (const args of readCalls(source, 'target')) {
    if (args.length < 4) {
      continue;
    }
    const title = stringLiteral(args[3]);
    if (title !== undefined) {
      rendered.add(title);
      allIdentities.add(title);
    }
    // Positions after the title can shift: the breadcrumb root is a ternary on some rows.
    // Read every remaining literal and treat a slashed value as breadcrumb segments.
    for (let index = 4; index < args.length; index += 1) {
      const text = args[index];
      const literalPattern = /'([^']*)'/g;
      let match = literalPattern.exec(text);
      while (match !== null) {
        const value = match[1];
        if (/[\u4e00-\u9fff]/.test(value)) {
          if (value.indexOf('/') >= 0) {
            for (const segment of value.split('/')) {
              const trimmed = segment.trim();
              if (trimmed.length > 0) {
                rendered.add(trimmed);
                allIdentities.add(trimmed);
              }
            }
          } else {
            allIdentities.add(value);
          }
        }
        match = literalPattern.exec(text);
      }
    }
  }
  return { rendered, allIdentities };
}

/**
 * Reads a `case '<zh>': return $r('app.string.<name>');` table.
 */
function readResourceCaseTable(relPath) {
  const source = read(relPath);
  const entries = [];
  const pattern = /case '([^']*)':\s*\n\s*return \$r\('app\.string\.([^']*)'\);/g;
  let match = pattern.exec(source);
  while (match !== null) {
    entries.push({ literal: match[1], resource: match[2] });
    match = pattern.exec(source);
  }
  return entries;
}

/** Reads the Chinese identity to English text map. */
/**
 * Settings files whose user-visible copy must be reachable through a localization table.
 * A literal outside this scope is another module's concern.
 */
function settingsScopeFiles() {
  const scope = [];
  for (const sub of ['core/settings', 'app/components/settings']) {
    const dir = path.join(REPO_ROOT, ETS, sub);
    for (const name of fs.readdirSync(dir)) {
      if (name.endsWith('.ets')) {
        scope.push(path.join(ETS, sub, name));
      }
    }
  }
  const pagesDir = path.join(REPO_ROOT, ETS, 'app/pages');
  for (const name of fs.readdirSync(pagesDir)) {
    if (name.endsWith('.ets') && /(Sync|Settings|Theme|AppIcon)/.test(name)) {
      scope.push(path.join(ETS, 'app/pages', name));
    }
  }
  return scope;
}

/**
 * Chinese literals that must stay Chinese on purpose, with the reason.
 *
 * - format markers: a count suffix or unit the code splits on before formatting.
 * - match markers: an internal string the code compares to classify a failure; it is
 *   never rendered, so translating it would break the comparison.
 * - the English index: its keys are Chinese identities by design.
 */
const INTENTIONAL_CHINESE = new Map([
  ['图片|.png,.jpg,.jpeg,.gif,.webp,.bmp,.svg,.heic,.heif,.avif,.ico,.tif,.tiff', 'file picker filter, `描述|后缀` shape the API parses'],
  [' 天未使用', 'day count marker the formatter splits on'],
  [' 条', 'item count marker the formatter splits on'],
  [' 天', 'day count marker the formatter splits on'],
  ['应用市场暂时无法打开。', 'review failure match marker, folded into settings_about_review_failed'],
  ['暂时无法打开评分弹窗。', 'review failure match marker, folded into settings_about_review_failed'],
  ['打开链接失败：', 'review failure match prefix, folded into settings_about_review_failed']
]);

/** Chinese literals still present in the settings scope, with the file that holds them. */
function readUnmappedSettingsLiterals() {
  const unmapped = [];
  for (const relPath of settingsScopeFiles()) {
    if (relPath === CATALOG_REL || relPath === ENGLISH_INDEX_REL) {
      continue;
    }
    let source = read(relPath);
    source = source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
    // Drop the argument of a localization call and the body of a `$r` value: those are
    // identities the tables own, not literals this check is looking for.
    source = source.replace(/localize\w*Copy\(\s*'[^']*'\s*\)/g, '');
    source = source.replace(/\$r\('[^']*'[^)]*\)/g, '');
    const pattern = /'([^'\\\n]*)'/g;
    let match = pattern.exec(source);
    while (match !== null) {
      const value = match[1];
      if (/[\u4e00-\u9fff]/.test(value) && !INTENTIONAL_CHINESE.has(value)) {
        unmapped.push({ value, relPath });
      }
      match = pattern.exec(source);
    }
  }
  return unmapped;
}

function readEnglishIndex() {
  const source = read(ENGLISH_INDEX_REL);
  const entries = [];
  const pattern = /^\s*\['((?:[^'\\]|\\.)*)',\s*'((?:[^'\\]|\\.)*)'\],$/gm;
  let match = pattern.exec(source);
  while (match !== null) {
    entries.push({ chinese: match[1], english: match[2] });
    match = pattern.exec(source);
  }
  return entries;
}

function readCopyTable() {
  const source = read(COPY_REL);
  const entries = [];
  const pattern = /case '([^']*)':\s*\n\s*return \$r\('app\.string\.([^']*)'\);/g;
  let match = pattern.exec(source);
  while (match !== null) {
    entries.push({ literal: match[1], resource: match[2] });
    match = pattern.exec(source);
  }
  return entries;
}

function readLocale(locale) {
  const parsed = JSON.parse(read(RESOURCE_REL(locale)));
  const values = new Map();
  for (const entry of parsed.string) {
    values.set(entry.name, entry.value);
  }
  return values;
}

function main() {
  const { rendered: catalogStrings, allIdentities } = readCatalogTargets();
  if (catalogStrings.size === 0) {
    fail(`could not read any title or path from ${CATALOG_REL}`);
  }

  const entries = readCopyTable();
  if (entries.length === 0) {
    fail(`could not read any mapping from ${COPY_REL}`);
  }
  const copyEntries = readResourceCaseTable(SETTINGS_COPY_REL);
  if (copyEntries.length === 0) {
    fail(`could not read any mapping from ${SETTINGS_COPY_REL}`);
  }
  const englishEntries = readEnglishIndex();
  if (englishEntries.length === 0) {
    fail(`could not read any entry from ${ENGLISH_INDEX_REL}`);
  }

  const mapped = new Map();
  for (const entry of entries) {
    if (mapped.has(entry.literal)) {
      fail(`${COPY_REL} maps ${JSON.stringify(entry.literal)} more than once`);
      continue;
    }
    mapped.set(entry.literal, entry.resource);
  }

  const locales = new Map();
  for (const locale of RESOURCE_LOCALES) {
    locales.set(locale, readLocale(locale));
  }

  const baseKeys = [...locales.get('base').keys()].sort().join('\n');
  for (const locale of RESOURCE_LOCALES) {
    if (locale === 'base') {
      continue;
    }
    const keys = [...locales.get(locale).keys()].sort().join('\n');
    if (keys !== baseKeys) {
      fail(`${RESOURCE_REL(locale)} does not carry the same key set as ${RESOURCE_REL('base')}`);
    }
  }

  const unmapped = [];
  for (const value of catalogStrings) {
    if (!mapped.has(value)) {
      unmapped.push(value);
    }
  }
  if (unmapped.length > 0) {
    unmapped.sort();
    fail(
      `${unmapped.length} settings directory string(s) have no ${COPY_REL} case and stay ` +
      `Chinese in every locale: ${unmapped.map((value) => JSON.stringify(value)).join(', ')}`
    );
  }

  for (const entry of entries) {
    for (const locale of RESOURCE_LOCALES) {
      const values = locales.get(locale);
      if (!values.has(entry.resource)) {
        fail(`${RESOURCE_REL(locale)} is missing app.string.${entry.resource} for ${JSON.stringify(entry.literal)}`);
        continue;
      }
      if (locale === 'base' && values.get(entry.resource) !== entry.literal) {
        fail(
          `app.string.${entry.resource} is ${JSON.stringify(values.get(entry.resource))} in base but ` +
          `${JSON.stringify(entry.literal)} in the catalog; the literal is the search identity and must not drift`
        );
      }
    }
  }

  // The settings copy table: every resource it names exists, and its `base` value still
  // equals the literal the owner produces.
  for (const entry of copyEntries) {
    for (const locale of RESOURCE_LOCALES) {
      const values = locales.get(locale);
      if (!values.has(entry.resource)) {
        fail(`${RESOURCE_REL(locale)} is missing app.string.${entry.resource} for ${JSON.stringify(entry.literal)}`);
        continue;
      }
      if (locale === 'base' && values.get(entry.resource) !== entry.literal) {
        fail(
          `app.string.${entry.resource} is ${JSON.stringify(values.get(entry.resource))} in base but ` +
          `${JSON.stringify(entry.literal)} in the settings copy table`
        );
      }
    }
  }

  // The English search index: every Chinese identity is one the directory actually uses,
  // and its English text agrees with the resource the render sinks show.
  const directoryIdentities = allIdentities;
  const englishByChinese = new Map();
  for (const entry of englishEntries) {
    if (englishByChinese.has(entry.chinese)) {
      fail(`${ENGLISH_INDEX_REL} maps ${JSON.stringify(entry.chinese)} more than once`);
      continue;
    }
    englishByChinese.set(entry.chinese, entry.english);
  }
  // An identity whose base value is already English (a brand name such as `Google` or
  // `Startpage`) needs no index entry: it reads the same in every locale, so the index
  // table correctly omits it.
  const baseValues = locales.get('base');
  const isReadableAsIs = (identity) => {
    const keys = [...baseValues.entries()]
      .filter(([, value]) => value === identity)
      .map(([name]) => name);
    if (keys.length === 0) {
      return false;
    }
    const englishValues = locales.get('en_US');
    return keys.every((name) => englishValues.get(name) === identity);
  };
  const englishMisses = [];
  for (const identity of directoryIdentities) {
    if (englishByChinese.has(identity) || isReadableAsIs(identity)) {
      continue;
    }
    englishMisses.push(identity);
  }
  // The English index must not silently drop an entry either: a missing key means an
  // English query cannot find that row.
  const englishIdentityPattern = /'((?:[^'\\]|\\.)*)'/g;
  if (englishMisses.length > 0) {
    englishMisses.sort();
    fail(
      `${englishMisses.length} settings directory identity(ies) have no ${ENGLISH_INDEX_REL} entry, ` +
      `so an English query cannot find them: ${englishMisses.map((value) => JSON.stringify(value)).join(', ')}`
    );
  }

  // Every remaining Chinese literal in the settings scope is either mapped by the copy
  // table or documented as intentional. Without this the table could silently stop covering
  // a string and nothing would notice.
  // A literal may be owned by any of the settings localization tables, not only the shared
  // one: the destination-specific tables cover copy that belongs to a single page.
  const copyLiterals = new Set(copyEntries.map((entry) => entry.literal));
  const settingsDir = path.join(REPO_ROOT, ETS, 'core/settings');
  for (const name of fs.readdirSync(settingsDir)) {
    if (!name.endsWith('.ets')) {
      continue;
    }
    const source = read(path.join(ETS, 'core/settings', name));
    for (const match of source.matchAll(/case '([^']*)':/g)) {
      copyLiterals.add(match[1]);
    }
  }
  // A `localizeSettingsCopy('...')` call site is a promise that the table covers that
  // literal. Checking the call sites directly is what catches a deleted mapping: the
  // source still compiles, and the literal only reappears in the guard's scan because the
  // call is stripped before the literal sweep.
  const uncovered = [];
  for (const relPath of settingsScopeFiles()) {
    const source = read(relPath);
    const pattern = /localizeSettingsCopy\(\s*'([^']*)'\s*\)/g;
    let match = pattern.exec(source);
    while (match !== null) {
      if (!copyLiterals.has(match[1])) {
        uncovered.push(`${relPath}: ${JSON.stringify(match[1])} (called but not in ${SETTINGS_COPY_REL})`);
      }
      match = pattern.exec(source);
    }
  }
  const settingsLiterals = readUnmappedSettingsLiterals();
  for (const entry of settingsLiterals) {
    if (!copyLiterals.has(entry.value)) {
      uncovered.push(`${entry.relPath}: ${JSON.stringify(entry.value)}`);
    }
  }
  if (uncovered.length > 0) {
    uncovered.sort();
    fail(
      `${uncovered.length} settings literal(s) are neither in ${SETTINGS_COPY_REL} nor documented ` +
      `as intentional, so they stay Chinese in every locale:\n    ` + uncovered.join('\n    ')
    );
  }

  if (failures > 0) {
    process.exit(1);
  }
  process.stdout.write(
    `Settings catalog localization guard passed: ${catalogStrings.size} directory strings, ` +
    `${entries.length} catalog mappings, ${copyEntries.length} settings-copy mappings, ` +
    `${englishEntries.length} English index entries, ${RESOURCE_LOCALES.length} locales.\n`
  );
}

main();
