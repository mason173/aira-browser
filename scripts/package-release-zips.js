const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const {
  COMMUNITY_EXTENSION_ID,
  FIREFOX_EXTENSION_ID,
  RELEASE_EDITION,
  computeExtensionIdFromManifestKey,
  detectReleaseEditionByManifest,
  readReleaseMarkerFromDir,
} = require('./release-utils');

const root = path.resolve(__dirname, '..');
const buildDir = path.join(root, 'build');

const verifyScript = path.join(root, 'scripts', 'verify-release.js');
const packWorkDir = path.join(root, '.tmp-release-pack');
const packageJsonPath = path.join(root, 'package.json');
const packageLockPath = path.join(root, 'package-lock.json');
const manifestFinalPath = path.join(root, 'public', 'manifest.final.json');
const manifestPath = path.join(root, 'public', 'manifest.json');

function run(cmd) {
  execSync(cmd, { cwd: root, stdio: 'inherit' });
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf-8'));
}

function writeJson(filePath, data, spaces = 2) {
  fs.writeFileSync(filePath, `${JSON.stringify(data, null, spaces)}\n`);
}

function bumpPatchVersion(version) {
  const match = String(version || '').match(/^(\d+)\.(\d+)\.(\d+)$/);
  if (!match) {
    throw new Error(`Release version must be x.y.z before packaging. Actual: ${version || '(empty)'}`);
  }
  return `${match[1]}.${match[2]}.${Number(match[3]) + 1}`;
}

function updatePackageLockVersion(nextVersion) {
  if (!fs.existsSync(packageLockPath)) return;
  const lock = readJson(packageLockPath);
  lock.version = nextVersion;
  if (lock.packages && lock.packages['']) {
    lock.packages[''].version = nextVersion;
  }
  writeJson(packageLockPath, lock, 6);
}

function updateManifestVersion(filePath, nextVersion) {
  const manifest = readJson(filePath);
  manifest.version = nextVersion;
  manifest.version_name = nextVersion;
  writeJson(filePath, manifest, 2);
  return manifest;
}

function shouldBumpReleaseVersion() {
  return process.argv.includes('--bump')
    || process.env.AIRATAB_BUMP_RELEASE_VERSION === '1';
}

function assertReleaseVersionLocked() {
  const pkg = readJson(packageJsonPath);
  const finalManifest = readJson(manifestFinalPath);
  const currentVersion = String(pkg.version || '');
  const manifestVersion = String(finalManifest.version || '');
  const manifestVersionName = String(finalManifest.version_name || '');
  if (!currentVersion || currentVersion !== manifestVersion || currentVersion !== manifestVersionName) {
    throw new Error(
      [
        'Release version files are out of sync.',
        `package.json=${currentVersion || '(empty)'}`,
        `manifest.version=${manifestVersion || '(empty)'}`,
        `manifest.version_name=${manifestVersionName || '(empty)'}`,
      ].join(' ')
    );
  }
  const extensionId = computeExtensionIdFromManifestKey(finalManifest.key);
  if (extensionId !== COMMUNITY_EXTENSION_ID) {
    throw new Error(
      [
        `Community extension ID changed unexpectedly.`,
        `Expected: ${COMMUNITY_EXTENSION_ID}`,
        `Actual: ${extensionId || '(empty)'}`,
        'Do not rotate manifest.key or community users will lose extension-scoped data.',
      ].join(' ')
    );
  }
  console.log(`[pack] Packaging existing release version: ${currentVersion}`);
  console.log(`[pack] Community extension ID locked: ${COMMUNITY_EXTENSION_ID}`);
  return currentVersion;
}

function bumpReleaseVersion() {
  const pkg = readJson(packageJsonPath);
  const currentVersion = String(pkg.version || '');
  const nextVersion = bumpPatchVersion(currentVersion);

  pkg.version = nextVersion;
  writeJson(packageJsonPath, pkg, 6);
  updatePackageLockVersion(nextVersion);
  const finalManifest = updateManifestVersion(manifestFinalPath, nextVersion);
  updateManifestVersion(manifestPath, nextVersion);

  const extensionId = computeExtensionIdFromManifestKey(finalManifest.key);
  if (extensionId !== COMMUNITY_EXTENSION_ID) {
    throw new Error(
      [
        `Community extension ID changed unexpectedly.`,
        `Expected: ${COMMUNITY_EXTENSION_ID}`,
        `Actual: ${extensionId || '(empty)'}`,
        'Do not rotate manifest.key or community users will lose extension-scoped data.',
      ].join(' ')
    );
  }

  console.log(`[pack] Bumped release version: ${currentVersion} -> ${nextVersion}`);
  console.log(`[pack] Community extension ID locked: ${COMMUNITY_EXTENSION_ID}`);
  return nextVersion;
}

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

function prepareFirefoxStoreManifest(dir) {
  const manifestPath = path.join(dir, 'manifest.json');
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf-8'));
  delete manifest.key;
  manifest.permissions = Array.isArray(manifest.permissions)
    ? manifest.permissions.filter((permission) => permission !== 'permissions')
    : manifest.permissions;
  manifest.background = {
    scripts: ['background-sw.js'],
    type: 'module',
  };
  manifest.browser_specific_settings = {
    gecko: {
      id: FIREFOX_EXTENSION_ID,
      data_collection_permissions: {
        required: [
          'authenticationInfo',
          'bookmarksInfo',
        ],
      },
      strict_min_version: '142.0',
    },
  };
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

const version = shouldBumpReleaseVersion()
  ? bumpReleaseVersion()
  : assertReleaseVersionLocked();
console.log('[pack] Building final release before packaging...');
run('npm run build');
assertBuild(buildDir, 'Chrome/Edge');

const builtEdition = detectReleaseEditionFromBuild(buildDir);
if (builtEdition !== RELEASE_EDITION) {
  console.error(`[pack] Expected final build but output is "${builtEdition || '(unknown)'}".`);
  console.error('[pack] Please run npm run build first.');
  process.exit(1);
}

const packageLabel = RELEASE_EDITION;
const storeZip = path.join(root, `airatab-${packageLabel}-chrome-edge-store-v${version}.zip`);
const communityZip = path.join(root, `airatab-${packageLabel}-chrome-edge-community-v${version}.zip`);
const firefoxZip = path.join(root, `airatab-${packageLabel}-firefox-store-v${version}.zip`);

console.log('[pack] Creating release zip files...');
copyDir(buildDir, packWorkDir);
removeStoreForbiddenManifestFields(packWorkDir);
packZip(packWorkDir, storeZip);
fs.rmSync(packWorkDir, { recursive: true, force: true });

copyDir(buildDir, packWorkDir);
packZip(packWorkDir, communityZip);
fs.rmSync(packWorkDir, { recursive: true, force: true });

copyDir(buildDir, packWorkDir);
prepareFirefoxStoreManifest(packWorkDir);
packZip(packWorkDir, firefoxZip);
fs.rmSync(packWorkDir, { recursive: true, force: true });

console.log('[pack] Verifying release zip...');
execSync(`node "${verifyScript}" "${storeZip}" "${communityZip}" "${firefoxZip}"`, { cwd: root, stdio: 'inherit' });
console.log(`[pack] Done:
- ${path.basename(storeZip)}
- ${path.basename(communityZip)}
- ${path.basename(firefoxZip)}`);
