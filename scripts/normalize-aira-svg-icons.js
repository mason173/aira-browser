#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const resourceRoot = path.join(repoRoot, 'AiraBrowser/entry/src/main/resources');
const baseMediaDir = path.join(resourceRoot, 'base/media');
const darkMediaDir = path.join(resourceRoot, 'dark/media');

const config = {
  chromePrefixes: [
    'app_toolbar_',
    'app_shortcut_',
    'app_tabs_'
  ],
  strokeWidth: '2',
  colors: {
    chromeLight: '#383838',
    chromeDark: '#ECE8E9',
    iconOnAccent: '#FFFFFF'
  }
};

const desktopShortcutSourceIcons = new Set([
  'app_shortcut_bookmarks.svg',
  'app_shortcut_downloads.svg',
  'app_shortcut_history.svg',
  'app_shortcut_scan_qr.svg'
]);

function isAppSvg(fileName) {
  return fileName.startsWith('app_') && fileName.endsWith('.svg');
}

function isDesktopShortcutSourceIcon(fileName) {
  return desktopShortcutSourceIcons.has(fileName);
}

function isChromeIcon(fileName) {
  return !isDesktopShortcutSourceIcon(fileName) &&
    config.chromePrefixes.some((prefix) => fileName.startsWith(prefix));
}

function listSvgFiles(dir) {
  return fs.readdirSync(dir)
    .filter(isAppSvg)
    .sort();
}

function normalizeSvg(svg, options) {
  let output = svg.replace(/\r\n/g, '\n').trim();

  output = output.replace(/<!--[\s\S]*?-->/g, '');
  output = removeEmptyGroups(output);
  output = removeInvisibleShapeElements(output);

  output = output.replace(/\s+stroke="(?:#[0-9A-Fa-f]{6}|currentColor)"/g, ` stroke="${options.strokeColor}"`);
  output = output.replace(/\s+stroke-width="[^"]+"/g, ` stroke-width="${options.strokeWidth}"`);
  output = output.replace(/>\s+</g, '>\n<');
  output = output.replace(/\n{2,}/g, '\n').trim();

  return `${output}\n`;
}

function removeEmptyGroups(svg) {
  let previous = '';
  let next = svg;
  while (previous !== next) {
    previous = next;
    next = next.replace(/<g\b[^>]*>\s*<\/g>/g, '');
  }
  return next;
}

function removeInvisibleShapeElements(svg) {
  return svg.replace(
    /<(path|rect|circle|ellipse|line|polyline|polygon)\b(?=[^>]*\bfill="none")(?!(?=[^>]*\bstroke=))[^>]*\/?>/g,
    ''
  );
}

function writeIfChanged(filePath, content, stats) {
  const previous = fs.existsSync(filePath) ? fs.readFileSync(filePath, 'utf8') : '';
  if (previous === content) {
    return;
  }
  fs.writeFileSync(filePath, content);
  stats.changed += 1;
  stats.changedFiles.push(path.relative(repoRoot, filePath));
}

function normalizeDirectory(dir, tone, stats) {
  const files = listSvgFiles(dir)
    .filter((fileName) => !fileName.includes('_chrome_light.svg') && !fileName.includes('_chrome_dark.svg'))
    .filter((fileName) => !isDesktopShortcutSourceIcon(fileName));

  files.forEach((fileName) => {
    const filePath = path.join(dir, fileName);
    const strokeColor = isChromeIcon(fileName)
      ? (tone === 'dark' ? config.colors.chromeDark : config.colors.chromeLight)
      : config.colors.iconOnAccent;
    const normalized = normalizeSvg(fs.readFileSync(filePath, 'utf8'), {
      strokeColor,
      strokeWidth: config.strokeWidth
    });
    writeIfChanged(filePath, normalized, stats);
  });
}

function buildVariantName(fileName, variant) {
  return fileName.replace(/\.svg$/, `_chrome_${variant}.svg`);
}

function generateChromeVariants(stats) {
  listSvgFiles(baseMediaDir)
    .filter((fileName) => isChromeIcon(fileName))
    .filter((fileName) => !fileName.includes('_chrome_light.svg') && !fileName.includes('_chrome_dark.svg'))
    .forEach((fileName) => {
      const source = fs.readFileSync(path.join(baseMediaDir, fileName), 'utf8');
      const light = normalizeSvg(source, {
        strokeColor: config.colors.chromeLight,
        strokeWidth: config.strokeWidth
      });
      const dark = normalizeSvg(source, {
        strokeColor: config.colors.chromeDark,
        strokeWidth: config.strokeWidth
      });

      writeIfChanged(path.join(baseMediaDir, buildVariantName(fileName, 'light')), light, stats);
      writeIfChanged(path.join(baseMediaDir, buildVariantName(fileName, 'dark')), dark, stats);
    });
}

function main() {
  const stats = {
    changed: 0,
    changedFiles: []
  };

  normalizeDirectory(baseMediaDir, 'light', stats);
  normalizeDirectory(darkMediaDir, 'dark', stats);
  generateChromeVariants(stats);

  console.log(`Normalized Aira SVG icons. Changed files: ${stats.changed}`);
  stats.changedFiles.forEach((fileName) => {
    console.log(`- ${fileName}`);
  });
}

main();
