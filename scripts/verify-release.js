const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const {
  COMMUNITY_EXTENSION_ID,
  FIREFOX_EXTENSION_ID,
  RELEASE_EDITION,
  computeExtensionIdFromManifestKey,
  detectReleaseEditionByManifest,
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

function detectPackageKind(zipPath) {
  const name = path.basename(zipPath).toLowerCase();
  if (name.includes('-firefox-')) return 'firefox';
  if (name.includes('-community-')) return 'community';
  return 'store';
}

function readStringArray(value) {
  return Array.isArray(value) ? value.filter((item) => typeof item === 'string') : [];
}

function verifyZip({ zipPath, expectedEdition, expectedVersion, expectedVersionName, expectedManifestKey }) {
  if (!fs.existsSync(zipPath)) {
    throw new Error(`Zip not found: ${zipPath}`);
  }
  const packageKind = detectPackageKind(zipPath);
  const manifest = readManifestFromZip(zipPath);
  const actualEdition = readReleaseMarkerFromZip(zipPath) || detectReleaseEditionByManifest(manifest);
  const actualVersion = String(manifest.version || '');
  const actualVersionName = String(manifest.version_name || '');
  const actualManifestKey = String(manifest.key || '');
  const actualExtensionId = actualManifestKey ? computeExtensionIdFromManifestKey(actualManifestKey) : '';

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
    for (const item of ['authenticationInfo', 'bookmarksInfo']) {
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
    const permissions = readStringArray(manifest.permissions);
    if (permissions.includes('permissions')) {
      throw new Error(`Firefox package must not include unsupported "permissions" manifest permission in ${path.basename(zipPath)}.`);
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
  const expectedManifestKey = String(expectedManifest.key || '');
  if (!expectedVersion) {
    throw new Error('Missing final manifest version.');
  }
  const args = process.argv.slice(2);
  const defaultZips = [
    path.join(root, `airatab-${expectedEdition}-chrome-edge-store-v${releaseVersion}.zip`),
    path.join(root, `airatab-${expectedEdition}-chrome-edge-community-v${releaseVersion}.zip`),
    path.join(root, `airatab-${expectedEdition}-firefox-store-v${releaseVersion}.zip`),
  ];
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
