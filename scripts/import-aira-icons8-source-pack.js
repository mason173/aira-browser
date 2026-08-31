#!/usr/bin/env node

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const vendorRoot = path.join(
  repoRoot,
  'resources/icon-sources/aira/vendor/icons8/ios-27-glyph'
);
const sourceOutputRoot = path.join(vendorRoot, 'svg');
const manifestPath = path.join(vendorRoot, 'source-manifest.json');

function fail(message) {
  throw new Error(`Icons8 source import: ${message}`);
}

function sha256(content) {
  return crypto.createHash('sha256').update(content).digest('hex');
}

function validateSvg(fileName, content) {
  const text = content.toString('utf8');
  if (!/^\s*<svg\b/.test(text)) {
    fail(`${fileName} is not an SVG document.`);
  }
  if (!/\bviewBox="0 0 30 30"/.test(text)) {
    fail(`${fileName} must use viewBox="0 0 30 30".`);
  }
  const outlineCount = (text.match(/<(?:path|polygon)\b/g) ?? []).length;
  if (outlineCount <= 0) {
    fail(`${fileName} must contain at least one path or polygon outline.`);
  }
  if (/<(?:script|image|use|foreignObject)\b/i.test(text) || /(?:href|xlink:href)=/i.test(text)) {
    fail(`${fileName} contains unsupported external or executable SVG content.`);
  }
}

function loadManifest() {
  if (!fs.existsSync(manifestPath)) {
    fail(`missing canonical source manifest: ${path.relative(repoRoot, manifestPath)}`);
  }
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  if (manifest.schemaVersion !== 1 || manifest.authority !== 'aira-icons8-ios-27-glyph-source-pack') {
    fail('unsupported source manifest schema or authority.');
  }
  if (!Array.isArray(manifest.glyphs) || manifest.glyphs.length <= 0) {
    fail('source manifest must declare at least one glyph.');
  }

  const glyphNames = new Set();
  const codePoints = new Set();
  const sourceFiles = new Set();
  manifest.glyphs.forEach((entry, index) => {
    if (typeof entry.glyph !== 'string' || entry.glyph.length <= 0) {
      fail(`glyph ${index} has no canonical glyph name.`);
    }
    if (!Number.isInteger(entry.codePoint) || entry.codePoint < 0 || entry.codePoint > 0xFFFF) {
      fail(`glyph ${entry.glyph} has an invalid BMP codePoint.`);
    }
    if (typeof entry.icons8Name !== 'string' || entry.icons8Name.length <= 0) {
      fail(`glyph ${entry.glyph} has no Icons8 name.`);
    }
    if (typeof entry.sourceFile !== 'string' || !entry.sourceFile.startsWith('svg/') ||
      path.basename(entry.sourceFile) !== entry.sourceFile.slice(4)) {
      fail(`glyph ${entry.glyph} has an invalid sourceFile: ${entry.sourceFile}`);
    }
    if (glyphNames.has(entry.glyph)) {
      fail(`duplicate glyph name: ${entry.glyph}`);
    }
    if (codePoints.has(entry.codePoint)) {
      fail(`duplicate codePoint: ${entry.codePoint}`);
    }
    if (sourceFiles.has(entry.sourceFile)) {
      fail(`duplicate sourceFile: ${entry.sourceFile}`);
    }
    glyphNames.add(entry.glyph);
    codePoints.add(entry.codePoint);
    sourceFiles.add(entry.sourceFile);
  });
  return manifest;
}

function listSvgFilesRecursive(root) {
  const result = [];
  const pending = [root];
  while (pending.length > 0) {
    const current = pending.pop();
    fs.readdirSync(current, { withFileTypes: true }).forEach((entry) => {
      const entryPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        pending.push(entryPath);
      } else if (entry.isFile() && entry.name.endsWith('.svg')) {
        result.push(entryPath);
      }
    });
  }
  return result;
}

function main() {
  const sourceRoot = process.argv[2] ? path.resolve(process.argv[2]) : '';
  if (!sourceRoot || !fs.statSync(sourceRoot, { throwIfNoEntry: false })?.isDirectory()) {
    fail('pass the licensed SVG directory as the only argument.');
  }

  const manifest = loadManifest();
  const suppliedPathsByName = new Map();
  listSvgFilesRecursive(sourceRoot).forEach((sourcePath) => {
    const sourceName = path.basename(sourcePath);
    const current = suppliedPathsByName.get(sourceName) ?? [];
    current.push(sourcePath);
    suppliedPathsByName.set(sourceName, current);
  });
  const expectedFiles = new Set(manifest.glyphs.map((entry) => path.basename(entry.sourceFile)));
  const missing = [...expectedFiles].filter((fileName) => !suppliedPathsByName.has(fileName));
  if (missing.length > 0) {
    fail(`missing SVG files: ${missing.join(', ')}`);
  }
  const ambiguous = [...expectedFiles].filter((fileName) => suppliedPathsByName.get(fileName).length !== 1);
  if (ambiguous.length > 0) {
    fail(`expected exactly one source path for: ${ambiguous.join(', ')}`);
  }

  fs.mkdirSync(sourceOutputRoot, { recursive: true });
  fs.readdirSync(sourceOutputRoot).forEach((fileName) => {
    if (fileName.endsWith('.svg') && !expectedFiles.has(fileName)) {
      fs.unlinkSync(path.join(sourceOutputRoot, fileName));
    }
  });
  manifest.glyphs.forEach((entry) => {
    const sourceName = path.basename(entry.sourceFile);
    const content = fs.readFileSync(suppliedPathsByName.get(sourceName)[0]);
    validateSvg(sourceName, content);
    fs.writeFileSync(path.join(sourceOutputRoot, sourceName), content);
    entry.sourceSha256 = sha256(content);
  });

  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(
    `Imported ${manifest.glyphs.length} licensed Icons8 SVGs into ${path.relative(repoRoot, vendorRoot)}.`
  );
}

main();
