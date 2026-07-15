const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const crypto = require('crypto');

const RELEASE_EDITION = 'final';
const RELEASE_MARKER_FILE = '.release-edition';
const RELEASE_PACKAGE_BASENAME = 'aira-sync-assistant';
const COMMUNITY_RELEASE_PACKAGE_BASENAME = 'Aira-Sync';
const COMMUNITY_EXTENSION_ID = 'plnjjlkaaonbccmjpfljbbbbaahfklem';
const FIREFOX_EXTENSION_ID = 'airatab@cc';

function detectReleaseEditionByManifest(manifest) {
  void manifest;
  return RELEASE_EDITION;
}

function readReleaseMarkerText(raw) {
  const normalized = String(raw || '').trim().toLowerCase();
  return normalized === RELEASE_EDITION ? RELEASE_EDITION : '';
}

function readReleaseMarkerFromDir(dirPath) {
  const markerPath = path.join(dirPath, RELEASE_MARKER_FILE);
  if (!fs.existsSync(markerPath)) return '';
  try {
    return readReleaseMarkerText(fs.readFileSync(markerPath, 'utf-8'));
  } catch {
    return '';
  }
}

function writeReleaseMarkerToDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
  fs.writeFileSync(path.join(dirPath, RELEASE_MARKER_FILE), `${RELEASE_EDITION}\n`);
}

function getCommunityReleasePackageFilename(version) {
  return `${COMMUNITY_RELEASE_PACKAGE_BASENAME}-v${version}.zip`;
}

function readReleaseMarkerFromZip(zipPath) {
  try {
    const output = execSync(`unzip -p "${zipPath}" ${RELEASE_MARKER_FILE}`, { encoding: 'utf-8' });
    return readReleaseMarkerText(output);
  } catch {
    return '';
  }
}

function computeExtensionIdFromManifestKey(manifestKey) {
  const compactKey = String(manifestKey || '').replace(/\s+/g, '');
  if (!compactKey) return '';
  const pem = [
    '-----BEGIN PUBLIC KEY-----',
    compactKey.match(/.{1,64}/g).join('\n'),
    '-----END PUBLIC KEY-----',
    '',
  ].join('\n');
  const der = crypto.createPublicKey(pem).export({ type: 'spki', format: 'der' });
  const hash = crypto.createHash('sha256').update(der).digest();
  return Array.from(hash.subarray(0, 16), (byte) => (
    String.fromCharCode(97 + (byte >> 4)) + String.fromCharCode(97 + (byte & 15))
  )).join('');
}

module.exports = {
  COMMUNITY_EXTENSION_ID,
  FIREFOX_EXTENSION_ID,
  RELEASE_EDITION,
  RELEASE_MARKER_FILE,
  RELEASE_PACKAGE_BASENAME,
  computeExtensionIdFromManifestKey,
  detectReleaseEditionByManifest,
  getCommunityReleasePackageFilename,
  readReleaseMarkerFromDir,
  readReleaseMarkerFromZip,
  writeReleaseMarkerToDir,
};
