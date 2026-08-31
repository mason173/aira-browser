#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const iconSourceRoot = path.join(repoRoot, 'resources/icon-sources/aira');
const defaultOutputRoot = path.join(process.env.HOME || '/tmp', 'Downloads/aira-icon-groups');
const options = parseArgs(process.argv.slice(2));

function parseArgs(args) {
  const options = {
    groupId: '',
    outputRoot: defaultOutputRoot
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--help' || arg === '-h') {
      printUsage();
      process.exit(0);
    }
    if (arg === '--output' || arg === '-o') {
      index += 1;
      if (index >= args.length) {
        throw new Error('Missing value for --output');
      }
      options.outputRoot = args[index];
      continue;
    }
    if (options.groupId.length > 0) {
      throw new Error(`Unexpected extra argument: ${arg}`);
    }
    options.groupId = arg;
  }

  if (options.groupId.length <= 0) {
    throw new Error('Missing icon group id.');
  }
  return options;
}

function printUsage() {
  console.log([
    'Usage: node scripts/export-aira-icon-group.js <group-id> [--output <dir>]',
    '',
    'Examples:',
    '  node scripts/export-aira-icon-group.js bottom-toolbar-customizable',
    '  node scripts/export-aira-icon-group.js settings --output /tmp/settings-icons'
  ].join('\n'));
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function csvEscape(value) {
  return `"${String(value ?? '').replace(/"/g, '""')}"`;
}

function buildFamilyMap(iconMap) {
  const familyMap = new Map();
  iconMap.forEach((entry) => {
    (entry.resourceFamilies ?? []).forEach((family) => {
      familyMap.set(family, entry);
    });
  });
  return familyMap;
}

function resolveGroup(iconGroups, groupId) {
  const group = (iconGroups.groups ?? []).find((candidate) => candidate.id === groupId);
  if (!group) {
    const knownGroups = (iconGroups.groups ?? []).map((candidate) => candidate.id).join(', ');
    throw new Error(`Unknown icon group: ${groupId}. Known groups: ${knownGroups}`);
  }
  return group;
}

function resolveOutputDir(outputRoot, groupId) {
  const resolved = path.resolve(outputRoot);
  if (path.basename(resolved) === groupId) {
    return resolved;
  }
  return path.join(resolved, groupId);
}

function main() {
  const iconMap = readJson(path.join(iconSourceRoot, 'icon-map.json'));
  const iconGroups = readJson(path.join(iconSourceRoot, 'icon-groups.json'));
  const familyMap = buildFamilyMap(iconMap);
  const group = resolveGroup(iconGroups, options.groupId);
  const outDir = resolveOutputDir(options.outputRoot, group.id);
  const iconsDir = path.join(outDir, 'icons');
  const rows = [];
  const copiedFiles = new Set();

  fs.rmSync(outDir, { recursive: true, force: true });
  fs.mkdirSync(iconsDir, { recursive: true });

  (group.entries ?? []).forEach((entry, index) => {
    const iconMapEntry = familyMap.get(entry.resourceFamily);
    if (!iconMapEntry) {
      throw new Error(`No source icon maps to resourceFamily ${entry.resourceFamily}`);
    }
    const sourceFile = path.basename(iconMapEntry.exportedFile);
    if (!copiedFiles.has(sourceFile)) {
      fs.copyFileSync(
        path.join(iconSourceRoot, iconMapEntry.exportedFile),
        path.join(iconsDir, sourceFile)
      );
      copiedFiles.add(sourceFile);
    }
    rows.push({
      order: index + 1,
      actionId: entry.actionId ?? '',
      title: entry.title ?? '',
      resourceFamily: entry.resourceFamily,
      sourceFile,
      primaryResourceFamily: iconMapEntry.primaryResourceFamily,
      allResourceFamiliesFromSameSource: iconMapEntry.resourceFamilies,
      originalDesignSource: iconMapEntry.originalSource
    });
  });

  const headers = [
    'order',
    'actionId',
    'title',
    'resourceFamily',
    'sourceFile',
    'primaryResourceFamily',
    'allResourceFamiliesFromSameSource',
    'originalDesignSource'
  ];
  const csv = [headers.map(csvEscape).join(',')]
    .concat(rows.map((row) => headers.map((header) => {
      const value = header === 'allResourceFamiliesFromSameSource' ?
        row[header].join(';') :
        row[header];
      return csvEscape(value);
    }).join(',')))
    .join('\n') + '\n';

  fs.writeFileSync(path.join(outDir, 'icon-group-map.csv'), csv);
  fs.writeFileSync(path.join(outDir, 'icon-group-map.json'), JSON.stringify({
    groupId: group.id,
    title: group.title,
    description: group.description ?? '',
    renderContext: group.renderContext ?? '',
    foregroundColor: group.foregroundColor ?? '',
    backgroundOwner: group.backgroundOwner ?? '',
    entryCount: rows.length,
    uniqueSourceSvgCount: copiedFiles.size,
    entries: rows
  }, null, 2) + '\n');
  const readmeLines = [
    `# ${group.title}`,
    '',
    group.description ?? '',
    '',
    `- Entries: ${rows.length}`,
    `- Unique source SVG files: ${copiedFiles.size}`,
  ];
  if (group.foregroundColor) {
    readmeLines.push(`- Foreground color: ${group.foregroundColor}`);
  }
  if (group.backgroundOwner) {
    readmeLines.push(`- Background owner: ${group.backgroundOwner}`);
  }
  if (group.renderContext) {
    readmeLines.push(`- Render context: ${group.renderContext}`);
  }
  readmeLines.push(
    '',
    'Edit SVGs in `icons/`. Keep the filename prefix before `__` unchanged so the files can be mapped back.',
    'Use `icon-group-map.csv` or `icon-group-map.json` for the action/resource mapping.'
  );
  fs.writeFileSync(path.join(outDir, 'README.md'), readmeLines.join('\n') + '\n');

  console.log(`Exported ${copiedFiles.size} source SVGs for ${rows.length} ${group.id} entries.`);
  console.log(outDir);
}

main();
