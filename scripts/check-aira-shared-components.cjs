const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

function checkVendoredDesign(root) {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'judesign.lock.json'), 'utf8'));
  const folder = path.join(root, 'design');
  const ignored = new Set(['build', 'oh_modules', '.hvigor', '.DS_Store', 'oh-package-lock.json5']);
  // 新版发布清单不收录构建生成文件；旧版清单仍按原记录校验。
  if (!manifest.files?.['BuildProfile.ets']) ignored.add('BuildProfile.ets');
  const files = {};
  function visit(base, prefix = '') {
    for (const entry of fs.readdirSync(base, { withFileTypes: true })) {
      if (ignored.has(entry.name)) continue;
      if (entry.isSymbolicLink()) throw new Error('JuDesign 副本不能包含符号链接。');
      const key = prefix + entry.name;
      if (entry.isDirectory()) visit(path.join(base, entry.name), key + '/');
      else files[key] = crypto.createHash('sha256').update(fs.readFileSync(path.join(base, entry.name))).digest('hex');
    }
  }
  visit(folder);
  const differences = [...new Set([...Object.keys(files), ...Object.keys(manifest.files || {})])]
    .filter(key => files[key] !== manifest.files?.[key]);
  if (manifest.library !== 'JuDesign' || !manifest.files || differences.length) {
    throw new Error(`JuDesign 固定副本与锁定版本不一致：${differences.join(', ')}。请在公共 JuDesign 工程修改并通过版本接入脚本升级。`);
  }
  const metadata = JSON.parse(fs.readFileSync(path.join(folder, 'oh-package.json5'), 'utf8'));
  if (metadata.version !== manifest.version) throw new Error('JuDesign 模块版本与锁文件不一致。');
  console.log(`PASS: JuDesign ${manifest.version} 固定副本校验（${Object.keys(files).length} 个文件）。`);
}
if (require.main === module) {
  const project = path.resolve(__dirname, '../AiraBrowser');
  checkVendoredDesign(project);
  require(path.join(project, 'membership/tools/check-integration.cjs')).check(project);
}
module.exports = { checkVendoredDesign };
