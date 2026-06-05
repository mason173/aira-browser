const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const {
  RELEASE_EDITION,
  detectReleaseEditionByManifest,
  readReleaseMarkerFromDir,
} = require('./release-utils');

const root = path.resolve(__dirname, '..');
const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf-8'));
const version = String(pkg.version || '0.0.0');

const buildDir = path.join(root, 'build');

const verifyScript = path.join(root, 'scripts', 'verify-release.js');
const packWorkDir = path.join(root, '.tmp-release-pack');

function assertBuild(dir, label) {
  const manifestPath = path.join(dir, 'manifest.json');
  if (!fs.existsSync(dir) || !fs.existsSync(manifestPath)) {
    console.error(`[pack] Missing ${label} build. Please run a build first.`);
    console.error(`[pack] Expected: ${manifestPath}`);
    process.exit(1);
  }
}

function readManifest(dir) {
  const manifestPath = path.join(dir, 'manifest.json');
  return JSON.parse(fs.readFileSync(manifestPath, 'utf-8'));
}

function detectReleaseEditionFromBuild(dir) {
  const markedEdition = readReleaseMarkerFromDir(dir);
  if (markedEdition) return markedEdition;
  return detectReleaseEditionByManifest(readManifest(dir));
}

function packZip(cwd, outFile) {
  if (fs.existsSync(outFile)) fs.rmSync(outFile, { force: true });
  execSync(`zip -qr "${outFile}" .`, { cwd, stdio: 'inherit' });
}

function copyDir(source, target) {
  if (fs.existsSync(target)) fs.rmSync(target, { recursive: true, force: true });
  fs.cpSync(source, target, { recursive: true });
}

function removeStoreForbiddenManifestFields(dir) {
  const manifestPath = path.join(dir, 'manifest.json');
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf-8'));
  delete manifest.key;
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

assertBuild(buildDir, 'Chrome/Edge');

const builtEdition = detectReleaseEditionFromBuild(buildDir);
if (builtEdition !== RELEASE_EDITION) {
  console.error(`[pack] Expected final build but output is "${builtEdition || '(unknown)'}".`);
  console.error('[pack] Please run npm run build first.');
  process.exit(1);
}

const packageLabel = RELEASE_EDITION;
const chromeZip = path.join(root, `airatab-${packageLabel}-chrome-edge-v${version}.zip`);

console.log('[pack] Creating release zip files...');
copyDir(buildDir, packWorkDir);
removeStoreForbiddenManifestFields(packWorkDir);
packZip(packWorkDir, chromeZip);
fs.rmSync(packWorkDir, { recursive: true, force: true });
console.log('[pack] Verifying release zip...');
execSync(`node "${verifyScript}" "${chromeZip}"`, { cwd: root, stdio: 'inherit' });
console.log(`[pack] Done:
- ${path.basename(chromeZip)}`);
