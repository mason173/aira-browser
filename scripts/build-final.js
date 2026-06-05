const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const {
  RELEASE_EDITION,
  writeReleaseMarkerToDir,
} = require('./release-utils');

const root = path.resolve(__dirname, '..');
const outDir = 'build';
const env = {
  ...process.env,
  VITE_BUILD_OUT_DIR: outDir,
};
const switchManifestScript = path.join(root, 'scripts', 'switch-manifest.js');
const buildDir = path.join(root, outDir);
const finalLocaleMessages = {
  en: {
    appTitle: {
      message: 'Aira - Focused WebDAV New Tab',
      description: 'The title of the application',
    },
    appDescription: {
      message: 'Focused new tab with shortcuts, browser bookmark search, WebDAV bookmark sync, wallpapers, and a clean keyboard-first layout.',
      description: 'The description of the application',
    },
  },
  zh_CN: {
    appTitle: {
      message: 'Aira 新标签页 - 简洁高效的 WebDAV 书签同步',
      description: 'The title of the application',
    },
    appDescription: {
      message: '简洁高效的新标签页，支持快捷方式、浏览器书签搜索、WebDAV 书签同步、壁纸与键盘优先操作。',
      description: 'The description of the application',
    },
  },
};
const localeFiles = Object.entries(finalLocaleMessages).map(([locale]) => path.join(root, 'public', '_locales', locale, 'messages.json'));
const BUILD_MANIFEST_TEMPLATE_FILES = [
  'manifest.final.json',
];

function run(cmd) {
  execSync(cmd, { cwd: root, stdio: 'inherit', env });
}

function removeBuildManifestTemplates(dirPath) {
  for (const fileName of BUILD_MANIFEST_TEMPLATE_FILES) {
    const filePath = path.join(dirPath, fileName);
    if (fs.existsSync(filePath)) {
      fs.rmSync(filePath, { force: true });
    }
  }
}

function readFileIfExists(filePath) {
  if (!fs.existsSync(filePath)) return null;
  return fs.readFileSync(filePath, 'utf-8');
}

function applyFinalLocaleMessages() {
  const backups = new Map();
  for (const filePath of localeFiles) {
    backups.set(filePath, readFileIfExists(filePath));
  }
  for (const [locale, content] of Object.entries(finalLocaleMessages)) {
    const filePath = path.join(root, 'public', '_locales', locale, 'messages.json');
    fs.writeFileSync(filePath, `${JSON.stringify(content, null, 2)}\n`);
  }
  return () => {
    for (const [filePath, originalContent] of backups.entries()) {
      if (originalContent == null) {
        fs.rmSync(filePath, { force: true });
      } else {
        fs.writeFileSync(filePath, originalContent);
      }
    }
  };
}

console.log(`[build] edition: ${RELEASE_EDITION}`);
const restoreLocales = applyFinalLocaleMessages();
try {
  run(`node "${switchManifestScript}"`);
  run('npx vite build');
  if (fs.existsSync(buildDir)) {
    removeBuildManifestTemplates(buildDir);
    writeReleaseMarkerToDir(buildDir);
  }
} finally {
  restoreLocales();
  run(`node "${switchManifestScript}"`);
}
