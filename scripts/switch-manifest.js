const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const publicDir = path.join(root, 'public');
const sourcePath = path.join(publicDir, 'manifest.final.json');
const targetPath = path.join(publicDir, 'manifest.json');

if (!fs.existsSync(sourcePath)) {
  console.error(`Manifest template not found: ${sourcePath}`);
  process.exit(1);
}

fs.copyFileSync(sourcePath, targetPath);
console.log(`[manifest] using ${path.basename(sourcePath)} -> public/manifest.json`);
