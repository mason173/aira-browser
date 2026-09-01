const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const {
  LOCAL_OFFICIAL_EXTENSION_ID,
  LOCAL_OFFICIAL_MANIFEST_KEY,
  RELEASE_EDITION,
  computeExtensionIdFromManifestKey,
  getLocalOfficialReleasePackageFilename,
  readReleaseMarkerFromDir,
} = require('./release-utils');

const root = path.resolve(__dirname, '..');
const buildDir = path.join(root, 'build', 'official');
const packageJsonPath = path.join(root, 'package.json');
const manifestFinalPath = path.join(root, 'public', 'manifest.final.json');
const packWorkDir = path.join(root, '.tmp-local-official-pack');
const verifyScript = path.join(root, 'scripts', 'verify-release.js');

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function assertReleaseVersionLocked() {
  const packageVersion = String(readJson(packageJsonPath).version || '');
  const manifest = readJson(manifestFinalPath);
  const manifestVersion = String(manifest.version || '');
  const manifestVersionName = String(manifest.version_name || '');
  if (!packageVersion || packageVersion !== manifestVersion || packageVersion !== manifestVersionName) {
    throw new Error(
      `Release version files are out of sync. package.json=${packageVersion || '(empty)'} `
      + `manifest.version=${manifestVersion || '(empty)'} `
      + `manifest.version_name=${manifestVersionName || '(empty)'}`
    );
  }
  return packageVersion;
}

function assertOfficialBuild(expectedVersion) {
  const manifestPath = path.join(buildDir, 'manifest.json');
  for (const requiredPath of [manifestPath, path.join(buildDir, 'history.html'), path.join(buildDir, 'history.js')]) {
    if (!fs.existsSync(requiredPath)) {
      throw new Error(`Missing Official build output: ${requiredPath}. Run npm run build:official first.`);
    }
  }
  const distributionPath = path.join(buildDir, '.aira-sync-distribution');
  const distribution = fs.existsSync(distributionPath)
    ? fs.readFileSync(distributionPath, 'utf8').trim().toLowerCase()
    : '';
  if (distribution !== 'official') {
    throw new Error(`Expected build/official, but distribution marker is "${distribution || '(missing)'}".`);
  }
  const edition = readReleaseMarkerFromDir(buildDir);
  if (edition !== RELEASE_EDITION) {
    throw new Error(`Expected final Official build, but release edition is "${edition || '(unknown)'}".`);
  }
  const manifest = readJson(manifestPath);
  if (String(manifest.version || '') !== expectedVersion) {
    throw new Error(
      `Official build version mismatch. Expected ${expectedVersion}, got ${manifest.version || '(empty)'}. `
      + 'Run npm run build:official again.'
    );
  }
  if (Object.prototype.hasOwnProperty.call(manifest, 'key')) {
    throw new Error('Official build must omit manifest.key; the local package adds it in a staging copy.');
  }
}

function copyDir(source, target) {
  if (fs.existsSync(target)) fs.rmSync(target, { recursive: true, force: true });
  fs.cpSync(source, target, { recursive: true });
}

function packZip(cwd, outputPath) {
  if (fs.existsSync(outputPath)) fs.rmSync(outputPath, { force: true });
  execFileSync('zip', ['-qr', outputPath, '.'], { cwd, stdio: 'inherit' });
}

const version = assertReleaseVersionLocked();
const expectedId = computeExtensionIdFromManifestKey(LOCAL_OFFICIAL_MANIFEST_KEY);
if (expectedId !== LOCAL_OFFICIAL_EXTENSION_ID) {
  throw new Error(
    `Official local extension identity mismatch: expected ${LOCAL_OFFICIAL_EXTENSION_ID}, got ${expectedId || '(empty)'}.`
  );
}
assertOfficialBuild(version);

const outputPath = path.join(root, getLocalOfficialReleasePackageFilename(version));
console.log(`[pack] Official local package identity locked: ${LOCAL_OFFICIAL_EXTENSION_ID}`);
console.log(`[pack] Creating ${path.basename(outputPath)}...`);

try {
  copyDir(buildDir, packWorkDir);
  const stagedManifestPath = path.join(packWorkDir, 'manifest.json');
  const stagedManifest = readJson(stagedManifestPath);
  stagedManifest.key = LOCAL_OFFICIAL_MANIFEST_KEY;
  fs.writeFileSync(stagedManifestPath, `${JSON.stringify(stagedManifest, null, 2)}\n`);
  packZip(packWorkDir, outputPath);
} finally {
  fs.rmSync(packWorkDir, { recursive: true, force: true });
}

console.log('[pack] Verifying Official local package...');
execFileSync(process.execPath, [verifyScript, outputPath], { cwd: root, stdio: 'inherit' });
console.log(`[pack] Done: ${path.basename(outputPath)}`);
