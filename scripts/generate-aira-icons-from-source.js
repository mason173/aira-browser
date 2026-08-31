#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const {
  canonicalLegacyResourceName,
  compileAiraIconCatalog,
  synchronizeAiraIconCatalogArtifacts
} = require('./lib/aira-icon-catalog');

const repoRoot = path.resolve(__dirname, '..');
const resourceRoot = path.join(repoRoot, 'AiraBrowser/entry/src/main/resources');
const baseMediaDir = path.join(resourceRoot, 'base/media');
const darkMediaDir = path.join(resourceRoot, 'dark/media');
const defaultSourceRoot = path.join(repoRoot, 'resources/icon-sources/aira');
const options = parseArgs(process.argv.slice(2));
const sourceRoot = options.sourceRoot ? path.resolve(options.sourceRoot) : defaultSourceRoot;
const catalog = compileAiraIconCatalog({ repoRoot, sourceRoot });

const COLORS = {
  chromeLight: '#383838',
  chromeDark: '#ECE8E9',
  brandLight: '#323232',
  brandDark: '#ECE8E9',
  widgetShortcutLight: '#323232',
  widgetShortcutDark: '#ECE8E9',
  widgetOutline: '#FFFFFF',
  iconOnAccent: '#FFFFFF',
  membershipDark: '#000000',
  membershipIvory: '#E8DDC5',
  restorePurchaseDark: '#171007'
};

function parseArgs(args) {
  const options = {
    check: false,
    sourceRoot: ''
  };

  args.forEach((arg) => {
    if (arg === '--check') {
      options.check = true;
      return;
    }
    if (arg === '--help' || arg === '-h') {
      printUsage();
      process.exit(0);
    }
    if (options.sourceRoot.length > 0) {
      throw new Error(`Unexpected extra argument: ${arg}`);
    }
    options.sourceRoot = arg;
  });

  return options;
}

function printUsage() {
  console.log([
    'Usage: node scripts/generate-aira-icons-from-source.js [--check] [source-root]',
    '',
    'Defaults:',
    `  source-root: ${path.relative(repoRoot, defaultSourceRoot)}`,
    '',
    'Examples:',
    '  node scripts/generate-aira-icons-from-source.js',
    '  node scripts/generate-aira-icons-from-source.js --check',
    '  node scripts/generate-aira-icons-from-source.js /path/to/export'
  ].join('\n'));
}

function listSvgFiles(dir) {
  return fs.readdirSync(dir)
    .filter((fileName) => fileName.endsWith('.svg'))
    .sort();
}

function isAccentIconName(name) {
  return name.startsWith('app_settings_') ||
    name.startsWith('app_site_permission_') ||
    name.startsWith('app_site_setting_') ||
    name.startsWith('app_video_assistant_');
}

function iconColor(fileName, dir) {
  const name = fileName.replace(/\.svg$/, '');

  if (name === 'aira_logo_brand') {
    return dir === darkMediaDir ? COLORS.brandDark : COLORS.brandLight;
  }
  if (name === 'app_search_suggestion_fill_arrow') {
    return COLORS.iconOnAccent;
  }
  if (name === 'app_widget_navigation_arrow') {
    return COLORS.widgetOutline;
  }
  if (name.startsWith('app_widget_')) {
    return dir === darkMediaDir ? COLORS.widgetShortcutDark : COLORS.widgetShortcutLight;
  }
  if (name.endsWith('_chrome_dark')) {
    return COLORS.chromeDark;
  }
  if (name.endsWith('_chrome_light')) {
    return COLORS.chromeLight;
  }
  if (name.endsWith('_white')) {
    return COLORS.iconOnAccent;
  }
  if (name.endsWith('_ivory')) {
    return COLORS.membershipIvory;
  }
  if (name.startsWith('app_membership_benefit_') && name.endsWith('_dark')) {
    return COLORS.membershipDark;
  }
  if (name === 'app_membership_restore_purchase_dark') {
    return COLORS.restorePurchaseDark;
  }
  if (name.startsWith('app_video_assistant_gesture_')) {
    return '#323232';
  }
  if (isAccentIconName(name)) {
    return COLORS.iconOnAccent;
  }

  return dir === darkMediaDir ? COLORS.chromeDark : COLORS.chromeLight;
}

function normalizeSvg(svg, color) {
  let output = svg.replace(/\r\n/g, '\n').trim();
  output = output.replace(/<!--[\s\S]*?-->/g, '');
  output = output.replace(/\s+stroke="(?!none")[^"]*"/g, ` stroke="${color}"`);
  output = output.replace(/\s+fill="(?!none")[^"]*"/g, ` fill="${color}"`);
  output = output.replace(/>\s+</g, '>\n<');
  output = output.replace(/\n{2,}/g, '\n').trim();
  return `${output}\n`;
}

function writeIfChanged(filePath, content, stats) {
  const previous = fs.existsSync(filePath) ? fs.readFileSync(filePath, 'utf8') : '';
  if (previous === content) {
    return;
  }
  if (options.check) {
    stats.changed += 1;
    stats.changedFiles.push(path.relative(repoRoot, filePath));
    return;
  }
  fs.writeFileSync(filePath, content);
  stats.changed += 1;
  stats.changedFiles.push(path.relative(repoRoot, filePath));
}

function writeBufferIfChanged(filePath, content, stats) {
  const previous = fs.existsSync(filePath) ? fs.readFileSync(filePath) : undefined;
  if (previous !== undefined && previous.equals(content)) {
    return;
  }
  if (options.check) {
    stats.changed += 1;
    stats.changedFiles.push(path.relative(repoRoot, filePath));
    return;
  }
  fs.writeFileSync(filePath, content);
  stats.changed += 1;
  stats.changedFiles.push(path.relative(repoRoot, filePath));
}

function buildSvgOutputSourceMap(catalog) {
  const sourceByResourcePath = new Map();
  catalog.legacyOutputProjection.iconByResourcePath.forEach((icon, resourcePath) => {
    const fileName = path.basename(resourcePath);
    const canonicalName = canonicalLegacyResourceName(fileName);
    sourceByResourcePath.set(resourcePath, catalog.resolveLegacySourcePath(canonicalName, fileName));
  });
  catalog.imageManifest.themedSourcePathByResourcePath.forEach((sourcePath, resourcePath) => {
    sourceByResourcePath.set(resourcePath, sourcePath);
  });
  return sourceByResourcePath;
}

function generateDirectory(dir, svgOutputSourceMap, stats) {
  const directoryPath = path.relative(resourceRoot, dir);
  const expectedPaths = Array.from(svgOutputSourceMap.keys())
    .filter((resourcePath) => path.dirname(resourcePath) === directoryPath)
    .sort();
  const expectedPathSet = new Set(expectedPaths);

  listSvgFiles(dir).forEach((fileName) => {
    const resourcePath = path.join(directoryPath, fileName);
    if (expectedPathSet.has(resourcePath)) {
      return;
    }
    const legacyResourceFamily = canonicalLegacyResourceName(fileName);
    if (catalog.fontResourceFamilies.has(legacyResourceFamily)) {
      const absolutePath = path.join(resourceRoot, resourcePath);
      stats.changed += 1;
      stats.changedFiles.push(path.relative(repoRoot, absolutePath));
      stats.retired += 1;
      if (!options.check) {
        fs.unlinkSync(absolutePath);
      }
      return;
    }
    if (!catalog.imageManifest.packagedSvgExceptionPaths.has(resourcePath)) {
      throw new Error(`Unclassified packaged SVG resource: ${resourcePath}`);
    }
    stats.skipped.push(resourcePath);
  });

  expectedPaths.forEach((resourcePath) => {
    const sourcePath = svgOutputSourceMap.get(resourcePath);
    const fileName = path.basename(resourcePath);
    const sourceSvg = fs.readFileSync(sourcePath, 'utf8');
    const output = normalizeSvg(sourceSvg, iconColor(fileName, dir));
    writeIfChanged(path.join(resourceRoot, resourcePath), output, stats);
    stats.generated += 1;
  });
}

function generateRasterResources(stats) {
  catalog.imageManifest.assets.filter((asset) => asset.kind === 'raster-copy').forEach((asset) => {
    const sourcePath = catalog.imageManifest.resolvedSourcePathById.get(asset.id);
    writeBufferIfChanged(
      path.join(baseMediaDir, asset.resourceFile),
      fs.readFileSync(sourcePath),
      stats
    );
    stats.generated += 1;
  });
  catalog.imageManifest.assets.filter((asset) => asset.kind === 'themed-raster').forEach((asset) => {
    const sourcePath = catalog.imageManifest.resolvedSourcePathById.get(asset.id);
    const content = fs.readFileSync(sourcePath);
    asset.resourcePaths.forEach((resourcePath) => {
      writeBufferIfChanged(path.join(resourceRoot, resourcePath), content, stats);
      stats.generated += 1;
    });
  });
}

function main() {
  const svgOutputSourceMap = buildSvgOutputSourceMap(catalog);
  const catalogArtifacts = synchronizeAiraIconCatalogArtifacts(catalog, { check: options.check });
  const stats = {
    generated: 0,
    changed: 0,
    changedFiles: [],
    skipped: [],
    retired: 0
  };

  stats.changed += catalogArtifacts.changed;
  stats.changedFiles.push(...catalogArtifacts.changedFiles);

  generateDirectory(baseMediaDir, svgOutputSourceMap, stats);
  generateDirectory(darkMediaDir, svgOutputSourceMap, stats);
  generateRasterResources(stats);

  const skippedResources = new Set(stats.skipped);
  catalog.imageManifest.packagedSvgExceptionPaths.forEach((resourcePath) => {
    if (!skippedResources.has(resourcePath)) {
      throw new Error(`Stale packaged SVG exception: ${resourcePath}`);
    }
  });

  console.log(
    `${options.check ? 'Checked' : 'Generated'} Canonical Aira Icon Catalog artifacts: ` +
    `${catalogArtifacts.checked}; changed: ${catalogArtifacts.changed}.`
  );
  console.log(`${options.check ? 'Checked' : 'Generated'} ${stats.generated} Aira icon resources from ${path.relative(repoRoot, sourceRoot) || sourceRoot}.`);
  console.log(`${options.check ? 'Checked' : 'Removed'} retired legacy SVG resources: ${stats.retired}.`);
  console.log(`${options.check ? 'Out-of-date files' : 'Changed files'}: ${stats.changed}`);
  stats.changedFiles.forEach((fileName) => console.log(`- ${fileName}`));
  console.log(`Checked classified image-owned SVG resources: ${stats.skipped.length}`);
  if (options.check && stats.changed > 0) {
    console.error('Aira icon resources are out of date. Run: node scripts/generate-aira-icons-from-source.js');
    process.exit(1);
  }
}

main();
