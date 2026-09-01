const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const {
  COMMUNITY_EXTENSION_ID,
  COMMUNITY_MANIFEST_KEY,
  FIREFOX_EXTENSION_ID,
  LOCAL_OFFICIAL_EXTENSION_ID,
  LOCAL_OFFICIAL_MANIFEST_KEY,
  RELEASE_EDITION,
  RELEASE_PACKAGE_BASENAME,
  computeExtensionIdFromManifestKey,
  detectReleaseEditionByManifest,
  getCommunityReleasePackageFilename,
  getLocalOfficialReleasePackageFilename,
  readReleaseMarkerFromZip,
} = require('./release-utils');

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf-8'));
}

function getExpectedManifest(root) {
  const manifestPath = path.join(root, 'public', 'manifest.final.json');
  if (!fs.existsSync(manifestPath)) {
    throw new Error(`Missing manifest template: ${manifestPath}`);
  }
  return readJson(manifestPath);
}

function readManifestFromZip(zipPath) {
  try {
    const text = execSync(`unzip -p "${zipPath}" manifest.json`, { encoding: 'utf-8' });
    return JSON.parse(text);
  } catch (error) {
    throw new Error(`Cannot read manifest.json from zip: ${zipPath}`);
  }
}

function readZipEntries(zipPath) {
  try {
    return new Set(execSync(`unzip -Z1 "${zipPath}"`, { encoding: 'utf-8' })
      .split(/\r?\n/)
      .map((entry) => entry.trim().replace(/^\.\//, ''))
      .filter(Boolean));
  } catch {
    throw new Error(`Cannot list release zip: ${zipPath}`);
  }
}

function detectPackageKind(zipPath, manifest) {
  const basename = path.basename(zipPath);
  if (
    basename === getLocalOfficialReleasePackageFilename(manifest.version)
    || manifest.key === LOCAL_OFFICIAL_MANIFEST_KEY
  ) {
    return 'local-official';
  }
  const name = basename.toLowerCase();
  if (name.includes('-firefox-') || manifest.browser_specific_settings?.gecko?.id === FIREFOX_EXTENSION_ID) {
    return 'firefox';
  }
  if (name === getCommunityReleasePackageFilename(manifest.version).toLowerCase()) return 'community';
  return 'store';
}

function readStringArray(value) {
  return Array.isArray(value) ? value.filter((item) => typeof item === 'string') : [];
}

function verifyZip({
  zipPath,
  expectedEdition,
  expectedVersion,
  expectedVersionName,
  expectedManifestKey,
  expectedLocalManifestKey,
}) {
  if (!fs.existsSync(zipPath)) {
    throw new Error(`Zip not found: ${zipPath}`);
  }
  const manifest = readManifestFromZip(zipPath);
  const packageKind = detectPackageKind(zipPath, manifest);
  const actualEdition = readReleaseMarkerFromZip(zipPath) || detectReleaseEditionByManifest(manifest);
  const actualVersion = String(manifest.version || '');
  const actualVersionName = String(manifest.version_name || '');
  const actualManifestKey = String(manifest.key || '');
  const actualExtensionId = actualManifestKey ? computeExtensionIdFromManifestKey(actualManifestKey) : '';
  const zipEntries = readZipEntries(zipPath);
  const permissions = readStringArray(manifest.permissions);

  for (const requiredEntry of ['background-sw.js', 'popup.html', 'history.html', 'history.js']) {
    if (!zipEntries.has(requiredEntry)) {
      throw new Error(`Package is missing ${requiredEntry} in ${path.basename(zipPath)}.`);
    }
  }
  if (permissions.includes('permissions')) {
    throw new Error(`Package must not include unsupported "permissions" manifest permission in ${path.basename(zipPath)}.`);
  }

  if ((packageKind === 'store' || packageKind === 'firefox') && Object.prototype.hasOwnProperty.call(manifest, 'key')) {
    throw new Error(
      [
        `Store package must not include manifest.key in ${path.basename(zipPath)}.`,
        'Remove the key field before packing the release zip.',
      ].join(' ')
    );
  }
  if (packageKind === 'firefox') {
    const gecko = manifest.browser_specific_settings?.gecko;
    if (gecko?.id !== FIREFOX_EXTENSION_ID) {
      throw new Error(
        [
          `Firefox package gecko.id mismatch in ${path.basename(zipPath)}.`,
          `Expected: ${FIREFOX_EXTENSION_ID}`,
          `Actual: ${gecko?.id || '(empty)'}`,
        ].join(' ')
      );
    }
    const requiredData = readStringArray(gecko?.data_collection_permissions?.required);
    for (const item of ['authenticationInfo', 'bookmarksInfo', 'browsingActivity']) {
      if (!requiredData.includes(item)) {
        throw new Error(
          `Firefox package must declare gecko.data_collection_permissions.required ${item} in ${path.basename(zipPath)}.`
        );
      }
    }
    const background = manifest.background || {};
    if (!Array.isArray(background.scripts) || !background.scripts.includes('background-sw.js')) {
      throw new Error(`Firefox package must include background.scripts fallback in ${path.basename(zipPath)}.`);
    }
    if (Object.prototype.hasOwnProperty.call(background, 'service_worker')) {
      throw new Error(`Firefox package must not include ignored background.service_worker in ${path.basename(zipPath)}.`);
    }
    if (!permissions.includes('history')) {
      throw new Error(`Firefox package must include required "history" permission in ${path.basename(zipPath)}.`);
    }
  }
  if (packageKind === 'community' && !actualManifestKey) {
    throw new Error(
      [
        `Community package must include manifest.key in ${path.basename(zipPath)}.`,
        'The key fixes the extension ID so manual updates keep user data.',
      ].join(' ')
    );
  }
  if (packageKind === 'local-official' && !actualManifestKey) {
    throw new Error(
      [
        `Official local package must include manifest.key in ${path.basename(zipPath)}.`,
        'The fixed key preserves the existing Chromium extension ID for manual updates.',
      ].join(' ')
    );
  }
  if (!permissions.includes('history')) {
    throw new Error(`Package must include required "history" permission in ${path.basename(zipPath)}.`);
  }
  if (packageKind === 'community' && expectedManifestKey && actualManifestKey !== expectedManifestKey) {
    throw new Error(
      [
        `Community manifest.key mismatch in ${path.basename(zipPath)}.`,
        'The community package must use the checked-in fixed extension key.',
      ].join(' ')
    );
  }
  if (packageKind === 'community' && actualExtensionId !== COMMUNITY_EXTENSION_ID) {
    throw new Error(
      [
        `Community extension ID mismatch in ${path.basename(zipPath)}.`,
        `Expected: ${COMMUNITY_EXTENSION_ID}`,
        `Actual: ${actualExtensionId || '(empty)'}`,
        'Do not rotate manifest.key or manual-update users will lose extension-scoped data.',
      ].join(' ')
    );
  }
  if (packageKind === 'local-official' && actualManifestKey !== expectedLocalManifestKey) {
    throw new Error(
      [
        `Official local manifest.key mismatch in ${path.basename(zipPath)}.`,
        'The local Official package must use the legacy fixed public key.',
      ].join(' ')
    );
  }
  if (packageKind === 'local-official' && actualExtensionId !== LOCAL_OFFICIAL_EXTENSION_ID) {
    throw new Error(
      [
        `Official local extension ID mismatch in ${path.basename(zipPath)}.`,
        `Expected: ${LOCAL_OFFICIAL_EXTENSION_ID}`,
        `Actual: ${actualExtensionId || '(empty)'}`,
      ].join(' ')
    );
  }
  if (actualEdition !== expectedEdition) {
    throw new Error(
      [
        `Release edition mismatch in ${path.basename(zipPath)}.`,
        `Expected: ${expectedEdition}`,
        `Actual: ${actualEdition}`,
        'Hint: run `npm run build` before packing.',
      ].join(' ')
    );
  }
  if (actualVersion !== expectedVersion) {
    throw new Error(
      [
        `Version mismatch in ${path.basename(zipPath)}.`,
        `Expected: ${expectedVersion}`,
        `Actual: ${actualVersion || '(empty)'}`,
      ].join(' ')
    );
  }
  if (String(expectedVersionName || '') !== actualVersionName) {
    throw new Error(
      [
        `Version name mismatch in ${path.basename(zipPath)}.`,
        `Expected: ${expectedVersionName || '(empty)'}`,
        `Actual: ${actualVersionName || '(empty)'}`,
      ].join(' ')
    );
  }

  console.log(
    `[verify] ${path.basename(zipPath)} OK (kind=${packageKind}, edition=${actualEdition}, version=${actualVersion}, version_name=${actualVersionName || '(empty)'}, key=${actualManifestKey ? 'present' : 'absent'}, extension_id=${actualExtensionId || '(none)'})`
  );
}

function main() {
  const root = path.resolve(__dirname, '..');
  const pkg = readJson(path.join(root, 'package.json'));
  const releaseVersion = String(pkg.version || '');
  if (!releaseVersion) {
    throw new Error('Missing package.json version.');
  }

  const expectedEdition = RELEASE_EDITION;
  const expectedManifest = getExpectedManifest(root);
  const expectedVersion = String(expectedManifest.version || '');
  const expectedVersionName = String(expectedManifest.version_name || '');
  const expectedManifestKey = COMMUNITY_MANIFEST_KEY;
  const expectedLocalManifestKey = LOCAL_OFFICIAL_MANIFEST_KEY;
  if (!expectedVersion) {
    throw new Error('Missing final manifest version.');
  }
  const args = process.argv.slice(2);
  const defaultZips = [
    path.join(root, `${RELEASE_PACKAGE_BASENAME}-${expectedEdition}-chrome-edge-store-v${releaseVersion}.zip`),
    path.join(root, getCommunityReleasePackageFilename(releaseVersion)),
    path.join(root, `${RELEASE_PACKAGE_BASENAME}-${expectedEdition}-firefox-store-v${releaseVersion}.zip`),
  ];
  const localOfficialZip = path.join(root, getLocalOfficialReleasePackageFilename(releaseVersion));
  if (fs.existsSync(localOfficialZip)) defaultZips.push(localOfficialZip);
  const zipPaths = args.length > 0 ? args.map((p) => path.resolve(root, p)) : defaultZips;

  console.log(
    `[verify] expected edition=${expectedEdition}, expected version=${expectedVersion}, expected version_name=${expectedVersionName || '(empty)'}, release tag version=${releaseVersion}`
  );
  zipPaths.forEach((zipPath) => {
    verifyZip({
      zipPath,
      expectedEdition,
      expectedVersion,
      expectedVersionName,
      expectedManifestKey,
      expectedLocalManifestKey,
    });
  });
  console.log('[verify] All release zip checks passed.');
}

try {
  main();
} catch (error) {
  console.error(`[verify] ${error.message}`);
  process.exit(1);
}
