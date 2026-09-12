const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const {
  COMMUNITY_EXTENSION_ID,
  COMMUNITY_MANIFEST_KEY,
  computeExtensionIdFromManifestKey,
  writeReleaseMarkerToDir,
} = require('./release-utils');
const { isLocalTestMode, parseEndpoint } = require(path.join(__dirname, '..', '..', '..', 'scripts', 'distribution-endpoint-policy.js'));

const root = path.resolve(__dirname, '..');
const distribution = String(process.argv[2] || '').trim().toLowerCase();
const localTestMode = isLocalTestMode(process.env.AIRA_LOCAL_TEST_MODE);
const routeNames = [
  'bookmarkSync',
  'historySync',
  'desktopPairingCreate',
  'desktopPairingStatus',
  'desktopMembershipState',
  'desktopSessionRevoke',
  'pagePushPoll',
  'pagePushAck',
  'deviceTabsPublish',
  'deviceTabsList',
  'deviceTabsClear',
];

if (distribution !== 'community' && distribution !== 'official') {
  throw new Error('Usage: node scripts/build-distribution.js <community|official>');
}

const outDir = path.join('build', distribution);
const buildDir = path.join(root, outDir);
const officialRoutes = distribution === 'official'
  ? validateOfficialRoutes(process.env.AIRA_SYNC_OFFICIAL_API_ROUTES || '', localTestMode)
  : '';
const env = {
  ...process.env,
  VITE_AIRATAB_DISTRIBUTION: distribution,
  VITE_AIRATAB_OFFICIAL_API_ROUTES: officialRoutes,
  VITE_AIRATAB_LOCAL_TEST_MODE: localTestMode ? '1' : '0',
  VITE_BUILD_OUT_DIR: outDir,
};
const switchManifestScript = path.join(root, 'scripts', 'switch-manifest.js');
const manifestTemplateFiles = ['manifest.final.json'];
const localeMessages = distribution === 'community'
  ? {
      en: {
        appTitle: { message: 'Aira-sync', description: 'The title of the application' },
        appDescription: {
          message: 'Self-hosted bookmark, history, page push, and cross-device tab integration for Aira Browser.',
          description: 'The description of the application',
        },
        commandOpenHistory: {
          message: 'Open Aira history',
          description: "Keyboard shortcut that opens Aira's merged history page",
        },
      },
      zh_CN: {
        appTitle: { message: 'Aira-sync', description: 'The title of the application' },
        appDescription: {
          message: '通过个人服务器连接 Aira 浏览器，同步书签、历史记录、网页推送和跨设备标签页。',
          description: 'The description of the application',
        },
        commandOpenHistory: {
          message: '打开 Aira 历史记录',
          description: "Keyboard shortcut that opens Aira's merged history page",
        },
      },
    }
  : {
      en: {
        appTitle: { message: 'Aira-sync', description: 'The title of the application' },
        appDescription: {
          message: 'Connect Aira Browser on HarmonyOS to sync bookmarks and browsing history on desktop, and receive pages sent from your phone.',
          description: 'The description of the application',
        },
        commandOpenHistory: {
          message: 'Open Aira history',
          description: "Keyboard shortcut that opens Aira's merged history page",
        },
      },
      zh_CN: {
        appTitle: { message: 'Aira-sync', description: 'The title of the application' },
        appDescription: {
          message: '连接鸿蒙手机上的 Aira 浏览器，在电脑浏览器同步书签和历史记录，并接收手机推送的当前网页。',
          description: 'The description of the application',
        },
        commandOpenHistory: {
          message: '打开 Aira 历史记录',
          description: "Keyboard shortcut that opens Aira's merged history page",
        },
      },
    };

function validateOfficialRoutes(raw, allowHttp) {
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error('Official build requires AIRA_SYNC_OFFICIAL_API_ROUTES as a JSON object.');
  }
  for (const routeName of routeNames) {
    const value = String(parsed?.[routeName] || '').trim();
    let endpoint;
    try {
      endpoint = parseEndpoint(value, {
        allowHttp,
        label: `Official API route ${routeName}`,
      });
    } catch (error) {
      throw new Error(error.message);
    }
    parsed[routeName] = endpoint;
  }
  return JSON.stringify(parsed);
}

function runNode(file) {
  execFileSync(process.execPath, [file], { cwd: root, stdio: 'inherit', env });
}

function runVite() {
  const viteBin = path.join(root, 'node_modules', 'vite', 'bin', 'vite.js');
  execFileSync(process.execPath, [viteBin, 'build'], { cwd: root, stdio: 'inherit', env });
}

function readFileIfExists(filePath) {
  return fs.existsSync(filePath) ? fs.readFileSync(filePath, 'utf8') : null;
}

function applyLocaleMessages() {
  const backups = new Map();
  for (const [locale, content] of Object.entries(localeMessages)) {
    const filePath = path.join(root, 'public', '_locales', locale, 'messages.json');
    backups.set(filePath, readFileIfExists(filePath));
    fs.writeFileSync(filePath, `${JSON.stringify(content, null, 2)}\n`);
  }
  return () => {
    for (const [filePath, content] of backups.entries()) {
      if (content === null) fs.rmSync(filePath, { force: true });
      else fs.writeFileSync(filePath, content);
    }
  };
}

function removeManifestTemplates() {
  for (const fileName of manifestTemplateFiles) {
    fs.rmSync(path.join(buildDir, fileName), { force: true });
  }
}

function applyDistributionManifestIdentity() {
  const manifestPath = path.join(buildDir, 'manifest.json');
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  if (distribution === 'community') {
    manifest.key = COMMUNITY_MANIFEST_KEY;
    const extensionId = computeExtensionIdFromManifestKey(manifest.key);
    if (extensionId !== COMMUNITY_EXTENSION_ID) {
      throw new Error(`Community extension ID mismatch: expected ${COMMUNITY_EXTENSION_ID}, got ${extensionId || '(empty)'}.`);
    }
  } else {
    delete manifest.key;
  }
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

console.log(`[build] Aira-sync distribution: ${distribution}`);
fs.rmSync(path.join(buildDir, '.aira-sync-local-test-mode'), { force: true });
const restoreLocales = applyLocaleMessages();
try {
  runNode(switchManifestScript);
  runVite();
  applyDistributionManifestIdentity();
  removeManifestTemplates();
  writeReleaseMarkerToDir(buildDir);
  fs.writeFileSync(path.join(buildDir, '.aira-sync-distribution'), `${distribution}\n`);
  const localTestMarker = path.join(buildDir, '.aira-sync-local-test-mode');
  if (localTestMode) fs.writeFileSync(localTestMarker, '1\n');
  else fs.rmSync(localTestMarker, { force: true });
} finally {
  restoreLocales();
  runNode(switchManifestScript);
}
