const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const RELEASE_EDITION = 'final';
const RELEASE_MARKER_FILE = '.release-edition';

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

function readReleaseMarkerFromZip(zipPath) {
  try {
    const output = execSync(`unzip -p "${zipPath}" ${RELEASE_MARKER_FILE}`, { encoding: 'utf-8' });
    return readReleaseMarkerText(output);
  } catch {
    return '';
  }
}

module.exports = {
  RELEASE_EDITION,
  RELEASE_MARKER_FILE,
  detectReleaseEditionByManifest,
  readReleaseMarkerFromDir,
  readReleaseMarkerFromZip,
  writeReleaseMarkerToDir,
};
