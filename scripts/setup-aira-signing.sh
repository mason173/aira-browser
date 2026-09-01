#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_DIR="${REPO_ROOT}/AiraBrowser"
BUILD_PROFILE_LOCAL="${PROJECT_DIR}/build-profile.local.json5"
BUILD_PROFILE_TEMPLATE="${PROJECT_DIR}/build-profile.json5"
PRODUCTION_BUNDLE_NAME="com.aira.browser"
COMMUNITY_BUNDLE_NAME="org.aira.browser"

DISTRIBUTION="${AIRA_DISTRIBUTION:-official}"
case "${DISTRIBUTION}" in
  official)
    EXPECTED_BUNDLE_NAME="${PRODUCTION_BUNDLE_NAME}"
    ;;
  community)
    EXPECTED_BUNDLE_NAME="${COMMUNITY_BUNDLE_NAME}"
    ;;
  *)
    echo "Unsupported AIRA_DISTRIBUTION=${DISTRIBUTION}. Use community or official." >&2
    exit 1
    ;;
esac

DEVECO_APP="/Applications/DevEco-Studio.app"
NODE_BIN="${DEVECO_APP}/Contents/tools/node/bin/node"
JAVA_BIN="${DEVECO_APP}/Contents/jbr/Contents/Home/bin/java"
KEYTOOL_BIN="${DEVECO_APP}/Contents/jbr/Contents/Home/bin/keytool"
SIGN_TOOL_JAR="${DEVECO_APP}/Contents/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar"

SIGNING_DIR="${AIRA_SIGNING_DIR:-${HOME}/AiraSigning}"
DEBUG_SIGNING_DIR="${AIRA_DEBUG_SIGNING_DIR:-${SIGNING_DIR}/debug}"
RELEASE_SIGNING_DIR="${AIRA_RELEASE_SIGNING_DIR:-${SIGNING_DIR}/release}"
resolve_first_file() {
  local candidate
  for candidate in "$@"; do
    if [ -f "${candidate}" ]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  printf '%s' "$1"
}
resolve_first_dir() {
  local candidate
  for candidate in "$@"; do
    if [ -d "${candidate}" ]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  printf '%s' "$1"
}
DEBUG_CERT="${AIRA_DEBUG_CERT:-$(resolve_first_file "${DEBUG_SIGNING_DIR}/aira-debug-certificate.cer")}"
DEBUG_STORE="${AIRA_DEBUG_STORE:-$(resolve_first_file "${DEBUG_SIGNING_DIR}/aira-debug-keystore.p12")}"
if [ -n "${AIRA_DEBUG_PROFILE:-}" ]; then
  DEBUG_PROFILE="${AIRA_DEBUG_PROFILE}"
else
  DEBUG_PROFILE="$(resolve_first_file "${DEBUG_SIGNING_DIR}/aira-debug-profile.p7b")"
fi
DEBUG_MATERIAL_DIR="${AIRA_DEBUG_MATERIAL_DIR:-$(resolve_first_dir "${DEBUG_SIGNING_DIR}/material")}"
DEBUG_KEY_ALIAS="${AIRA_DEBUG_KEY_ALIAS:-}"
RELEASE_CERT="${AIRA_RELEASE_CERT:-$(resolve_first_file "${RELEASE_SIGNING_DIR}/aira-release-certificate.cer" "${SIGNING_DIR}/aira.cer")}"
RELEASE_STORE="${AIRA_RELEASE_STORE:-$(resolve_first_file "${RELEASE_SIGNING_DIR}/aira-release-keystore.p12" "${SIGNING_DIR}/aira.p12")}"
RELEASE_PROFILE="${AIRA_RELEASE_PROFILE:-$(resolve_first_file "${RELEASE_SIGNING_DIR}/aira-release-profile.p7b" "${SIGNING_DIR}/Aira_Release_ProfileRelease.p7b")}"
RELEASE_MATERIAL_DIR="${AIRA_RELEASE_MATERIAL_DIR:-$(resolve_first_dir "${RELEASE_SIGNING_DIR}/material" "${SIGNING_DIR}/material")}"
RELEASE_KEY_ALIAS="${AIRA_RELEASE_KEY_ALIAS:-}"
COMMON_STORE_PASSWORD="${AIRA_SIGNING_STORE_PASSWORD:-}"

fail() {
  echo "$1" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  AIRA_SIGNING_STORE_PASSWORD='...' ./scripts/setup-aira-signing.sh

  Or pass debug/release passwords separately:
  AIRA_DEBUG_STORE_PASSWORD='...' AIRA_RELEASE_STORE_PASSWORD='...' ./scripts/setup-aira-signing.sh

Optional overrides:
  AIRA_SIGNING_STORE_PASSWORD='...'       Default store password for both debug and release p12 files.
  AIRA_DEBUG_STORE_PASSWORD='...'         Defaults to AIRA_SIGNING_STORE_PASSWORD.
  AIRA_DEBUG_KEY_PASSWORD='...'           Defaults to AIRA_DEBUG_STORE_PASSWORD.
  AIRA_DEBUG_SIGNING_DIR=/abs/debug/dir   Defaults to AIRA_SIGNING_DIR/debug.
  AIRA_DEBUG_CERT=/abs/aira-debug-certificate.cer
  AIRA_DEBUG_STORE=/abs/aira-debug-keystore.p12
  AIRA_DEBUG_PROFILE=/abs/aira-debug-profile.p7b
  AIRA_DEBUG_MATERIAL_DIR=/abs/debug/material
  AIRA_DEBUG_KEY_ALIAS=debugKey           Auto-detected from the p12 when omitted.
  AIRA_RELEASE_STORE_PASSWORD='...'       Defaults to AIRA_SIGNING_STORE_PASSWORD.
  AIRA_RELEASE_KEY_PASSWORD='...'        Defaults to AIRA_RELEASE_STORE_PASSWORD.
  AIRA_SIGNING_DIR=/abs/signing/dir      Defaults to ~/AiraSigning.
  AIRA_RELEASE_SIGNING_DIR=/abs/release/dir Defaults to AIRA_SIGNING_DIR/release.
  AIRA_RELEASE_CERT=/abs/aira-release-certificate.cer
  AIRA_RELEASE_STORE=/abs/aira-release-keystore.p12
  AIRA_RELEASE_PROFILE=/abs/aira-release-profile.p7b
  AIRA_RELEASE_MATERIAL_DIR=/abs/release/material
  AIRA_RELEASE_KEY_ALIAS=airakey         Auto-detected from the p12 when omitted.

The script writes AiraBrowser/build-profile.local.json5. That file is gitignored and is the only place where machine-local
encrypted signing passwords and absolute signing material paths should live.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

[ -x "${NODE_BIN}" ] || fail "DevEco Node not found: ${NODE_BIN}"
[ -x "${JAVA_BIN}" ] || fail "DevEco Java not found: ${JAVA_BIN}"
[ -x "${KEYTOOL_BIN}" ] || fail "DevEco keytool not found: ${KEYTOOL_BIN}"
[ -f "${SIGN_TOOL_JAR}" ] || fail "hap-sign-tool not found: ${SIGN_TOOL_JAR}"
[ -f "${BUILD_PROFILE_TEMPLATE}" ] || fail "Build profile template not found: ${BUILD_PROFILE_TEMPLATE}"
[ -f "${DEBUG_CERT}" ] || fail "Debug certificate not found: ${DEBUG_CERT}"
[ -f "${DEBUG_STORE}" ] || fail "Debug p12 not found: ${DEBUG_STORE}"
[ -f "${DEBUG_PROFILE}" ] || fail "Debug Profile not found: ${DEBUG_PROFILE}"
[ -d "${DEBUG_MATERIAL_DIR}" ] || fail "Debug material directory not found: ${DEBUG_MATERIAL_DIR}"
[ -f "${RELEASE_CERT}" ] || fail "Release certificate not found: ${RELEASE_CERT}"
[ -f "${RELEASE_STORE}" ] || fail "Release p12 not found: ${RELEASE_STORE}"
[ -f "${RELEASE_PROFILE}" ] || fail "Release Profile not found: ${RELEASE_PROFILE}"
[ -d "${RELEASE_MATERIAL_DIR}" ] || fail "Release material directory not found: ${RELEASE_MATERIAL_DIR}"
[ -n "${COMMON_STORE_PASSWORD}${AIRA_DEBUG_STORE_PASSWORD:-}${AIRA_RELEASE_STORE_PASSWORD:-}" ] \
  || fail "AIRA_SIGNING_STORE_PASSWORD is required, or pass AIRA_DEBUG_STORE_PASSWORD and AIRA_RELEASE_STORE_PASSWORD separately. Passwords are used only to generate local encrypted fields."

DEBUG_STORE_PASSWORD="${AIRA_DEBUG_STORE_PASSWORD:-${COMMON_STORE_PASSWORD}}"
RELEASE_STORE_PASSWORD="${AIRA_RELEASE_STORE_PASSWORD:-${COMMON_STORE_PASSWORD}}"
DEBUG_KEY_PASSWORD="${AIRA_DEBUG_KEY_PASSWORD:-${DEBUG_STORE_PASSWORD}}"
[ -n "${DEBUG_STORE_PASSWORD}" ] || fail "AIRA_DEBUG_STORE_PASSWORD is required when AIRA_SIGNING_STORE_PASSWORD is not set."
[ -n "${RELEASE_STORE_PASSWORD}" ] || fail "AIRA_RELEASE_STORE_PASSWORD is required when AIRA_SIGNING_STORE_PASSWORD is not set."
RELEASE_KEY_PASSWORD="${AIRA_RELEASE_KEY_PASSWORD:-${RELEASE_STORE_PASSWORD}}"

verify_profile_for_config() {
  local label="$1"
  local profile_path="$2"
  local expected_type="$3"
  local profile_verify_output
  local profile_bundle_name
  local profile_type
  local profile_issuer

  profile_verify_output="$("${JAVA_BIN}" -jar "${SIGN_TOOL_JAR}" verify-profile -inFile "${profile_path}" 2>&1)"
  if ! printf '%s\n' "${profile_verify_output}" | grep -q '"verifiedPassed": true'; then
    printf '%s\n' "${profile_verify_output}" >&2
    fail "${label} Profile verification failed: ${profile_path}"
  fi

  profile_bundle_name="$(printf '%s\n' "${profile_verify_output}" | sed -n 's|.*"bundle-name": "\(.*\)",$|\1|p' | head -n 1)"
  [ "${profile_bundle_name}" = "${EXPECTED_BUNDLE_NAME}" ] \
    || fail "${label} Profile bundle-name is ${profile_bundle_name}, expected ${EXPECTED_BUNDLE_NAME}: ${profile_path}"

  profile_type="$(printf '%s\n' "${profile_verify_output}" | sed -n 's|.*"type": "\(.*\)",$|\1|p' | head -n 1)"
  [ "${profile_type}" = "${expected_type}" ] || fail "${label} Profile type is ${profile_type}, expected ${expected_type}: ${profile_path}"

  profile_issuer="$(printf '%s\n' "${profile_verify_output}" | sed -n 's|.*"issuer": "\(.*\)".*|\1|p' | head -n 1)"
  [ "${profile_issuer}" = "app_gallery" ] || fail "${label} Profile issuer is ${profile_issuer}, expected app_gallery: ${profile_path}"
}

detect_key_alias() {
  local label="$1"
  local store_file="$2"
  local store_password="$3"

  "${NODE_BIN}" - "${KEYTOOL_BIN}" "${store_file}" "${store_password}" "${label}" <<'NODE'
const cp = require('child_process');
const [keytool, storeFile, password, label] = process.argv.slice(2);
const result = cp.spawnSync(keytool, [
  '-list',
  '-keystore', storeFile,
  '-storetype', 'PKCS12',
  '-storepass', password
], { encoding: 'utf8' });
const output = `${result.stdout || ''}${result.stderr || ''}`;
if (result.status !== 0) {
  process.stderr.write(output);
  process.exit(result.status || 1);
}
const aliasLine = output.split(/\r?\n/).find((line) => line.includes(','));
if (!aliasLine) {
  process.stderr.write(`Could not resolve ${label} key alias.\n`);
  process.stderr.write(output);
  process.exit(1);
}
process.stdout.write(aliasLine.replace(/,.*/, '').trim());
NODE
}

verify_profile_for_config "Debug" "${DEBUG_PROFILE}" "debug"
verify_profile_for_config "Release" "${RELEASE_PROFILE}" "release"

if [ -z "${DEBUG_KEY_ALIAS}" ]; then
  DEBUG_KEY_ALIAS="$(detect_key_alias "debug" "${DEBUG_STORE}" "${DEBUG_STORE_PASSWORD}")"
fi

if [ -z "${RELEASE_KEY_ALIAS}" ]; then
  RELEASE_KEY_ALIAS="$(detect_key_alias "release" "${RELEASE_STORE}" "${RELEASE_STORE_PASSWORD}")"
fi

[ -n "${DEBUG_KEY_ALIAS}" ] || fail "Failed to resolve debug key alias."
[ -n "${RELEASE_KEY_ALIAS}" ] || fail "Failed to resolve release key alias."

"${NODE_BIN}" - \
  "${BUILD_PROFILE_TEMPLATE}" \
  "${BUILD_PROFILE_LOCAL}" \
  "${DEBUG_CERT}" \
  "${DEBUG_STORE}" \
  "${DEBUG_PROFILE}" \
  "${DEBUG_MATERIAL_DIR}" \
  "${DEBUG_KEY_ALIAS}" \
  "${DEBUG_STORE_PASSWORD}" \
  "${DEBUG_KEY_PASSWORD}" \
  "${RELEASE_CERT}" \
  "${RELEASE_STORE}" \
  "${RELEASE_PROFILE}" \
  "${RELEASE_MATERIAL_DIR}" \
  "${RELEASE_KEY_ALIAS}" \
  "${RELEASE_STORE_PASSWORD}" \
  "${RELEASE_KEY_PASSWORD}" <<'NODE'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const cp = require('child_process');

const [
  templatePath,
  outputPath,
  debugCert,
  debugStore,
  debugProfile,
  debugMaterialDir,
  debugKeyAlias,
  debugStorePassword,
  debugKeyPassword,
  releaseCert,
  releaseStore,
  releaseProfile,
  releaseMaterialDir,
  releaseKeyAlias,
  releaseStorePassword,
  releaseKeyPassword,
] = process.argv.slice(2);

const component = new Int8Array([49, 243, 9, 115, 214, 175, 91, 184, 211, 190, 177, 88, 101, 131, 192, 119]);

function readJson5(filePath) {
  return new Function(`return (${fs.readFileSync(filePath, 'utf8')});`)();
}

function readOnlyFile(dir) {
  const entries = fs.readdirSync(dir).filter((entry) => entry !== '.DS_Store');
  if (entries.length !== 1) {
    throw new Error(`Invalid signing material directory: ${dir}`);
  }
  return new Int8Array(fs.readFileSync(path.join(dir, entries[0])));
}

function xor(left, right) {
  if (left.byteLength !== right.byteLength) {
    throw new Error('Signing material length mismatch.');
  }
  const output = new Int8Array(left.byteLength);
  for (let index = 0; index < left.byteLength; index++) {
    output[index] = left[index] ^ right[index];
  }
  return output;
}

function decryptBytes(key, bytes) {
  const payloadLength = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  const ivLength = bytes.length - 4 - payloadLength;
  const iv = bytes.slice(4, 4 + ivLength);
  const decipher = crypto.createDecipheriv('aes-128-gcm', key, iv);
  decipher.setAuthTag(bytes.slice(bytes.length - 16));
  return Buffer.concat([decipher.update(bytes.subarray(4 + ivLength, bytes.length - 16)), decipher.final()]);
}

function encryptBytes(key, text) {
  const iv = new Int8Array(crypto.randomBytes(12));
  const cipher = crypto.createCipheriv('aes-128-gcm', key, iv);
  const encrypted = Buffer.concat([cipher.update(new Int8Array(Buffer.from(text))), cipher.final()]);
  const authTag = new Int8Array(cipher.getAuthTag());
  const payloadLength = encrypted.length + authTag.length;
  const output = new Int8Array(4 + iv.length + encrypted.length + authTag.length);
  output[0] = (payloadLength >> 24) & 255;
  output[1] = (payloadLength >> 16) & 255;
  output[2] = (payloadLength >> 8) & 255;
  output[3] = payloadLength & 255;
  output.set(iv, 4);
  output.set(new Int8Array(encrypted), 4 + iv.length);
  output.set(authTag, 4 + iv.length + encrypted.length);
  return Buffer.from(output).toString('hex').toUpperCase();
}

function deriveSigningKey(materialDir) {
  const components = ['0', '1', '2'].map((name) => readOnlyFile(path.join(materialDir, 'fd', name)));
  const salt = readOnlyFile(path.join(materialDir, 'ac'));
  let mixed = xor(components[0], components[1]);
  mixed = xor(mixed, components[2]);
  mixed = xor(mixed, component);
  const rootKey = new Int8Array(crypto.pbkdf2Sync(Buffer.from(mixed).toString(), salt, 10000, 16, 'sha256'));
  return new Int8Array(decryptBytes(rootKey, readOnlyFile(path.join(materialDir, 'ce'))));
}

function decryptPassword(encryptedPassword, materialDir) {
  const key = deriveSigningKey(materialDir);
  return decryptBytes(key, new Int8Array(Buffer.from(encryptedPassword, 'hex'))).toString('utf8');
}

function p12Opens(storeFile, password) {
  const result = cp.spawnSync('openssl', [
    'pkcs12',
    '-info',
    '-in', storeFile,
    '-nokeys',
    '-passin', `pass:${password}`,
  ], { encoding: 'utf8' });
  const output = `${result.stdout || ''}${result.stderr || ''}`;
  return result.status === 0 && !output.includes('Mac verify error');
}

if (!p12Opens(debugStore, debugStorePassword)) {
  throw new Error('AIRA_DEBUG_STORE_PASSWORD does not open the debug p12.');
}

if (!p12Opens(releaseStore, releaseStorePassword)) {
  throw new Error('AIRA_RELEASE_STORE_PASSWORD does not open the release p12.');
}

const result = readJson5(templatePath);

function buildSigningConfig(name, certpath, storeFile, profile, materialDir, keyAlias, storePassword, keyPassword) {
  const key = deriveSigningKey(materialDir);
  const encryptedStorePassword = encryptBytes(key, storePassword);
  const encryptedKeyPassword = encryptBytes(key, keyPassword);
  if (decryptPassword(encryptedStorePassword, materialDir) !== storePassword ||
      decryptPassword(encryptedKeyPassword, materialDir) !== keyPassword) {
    throw new Error(`Generated encrypted ${name} passwords failed local verification.`);
  }
  return {
    name,
    type: 'HarmonyOS',
    material: {
      certpath,
      keyAlias,
      keyPassword: encryptedKeyPassword,
      profile,
      signAlg: 'SHA256withECDSA',
      storeFile,
      storePassword: encryptedStorePassword,
    },
  };
}

result.app.signingConfigs = [
  buildSigningConfig('debug', debugCert, debugStore, debugProfile, debugMaterialDir, debugKeyAlias, debugStorePassword, debugKeyPassword),
  buildSigningConfig('release', releaseCert, releaseStore, releaseProfile, releaseMaterialDir, releaseKeyAlias, releaseStorePassword, releaseKeyPassword),
];
for (const product of result.app.products || []) {
  if (product.name === 'default') {
    product.signingConfig = 'debug';
  }
}

fs.writeFileSync(outputPath, `${JSON.stringify(result, null, 2)}\n`);
NODE

echo "Wrote local signing profile: ${BUILD_PROFILE_LOCAL}"
echo "Debug signing material:"
echo "  cert: ${DEBUG_CERT}"
echo "  p12: ${DEBUG_STORE}"
echo "  profile: ${DEBUG_PROFILE}"
echo "  material: ${DEBUG_MATERIAL_DIR}"
echo "  key alias: ${DEBUG_KEY_ALIAS}"
echo
echo "Release signing material:"
echo "  cert: ${RELEASE_CERT}"
echo "  p12: ${RELEASE_STORE}"
echo "  profile: ${RELEASE_PROFILE}"
echo "  material: ${RELEASE_MATERIAL_DIR}"
echo "  key alias: ${RELEASE_KEY_ALIAS}"
echo
echo "Next debug install command:"
echo "  ./scripts/install-aira-browser.sh"
echo
echo "Next release package command:"
echo "  AIRA_BUILD_VARIANT=release AIRA_BUILD_PACKAGE_FORMAT=app SKIP_INSTALL=1 ./scripts/build-aira-browser.sh"
