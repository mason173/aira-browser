// Runs from the vendored module; checks need no upstream checkout or network.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const ignored = new Set(['build', 'oh_modules', '.hvigor', '.DS_Store', 'oh-package-lock.json5', 'BuildProfile.ets']);
function inventory(folder) {
  const result = {};
  function visit(base, prefix = '') {
    for (const entry of fs.readdirSync(base, {withFileTypes:true})) {
      if (ignored.has(entry.name)) continue;
      if (entry.isSymbolicLink()) throw Error('Membership module cannot contain symlinks');
      const relative = prefix + entry.name;
      if (entry.isDirectory()) visit(path.join(base,entry.name),relative+'/');
      else result[relative]=crypto.createHash('sha256').update(fs.readFileSync(path.join(base,entry.name))).digest('hex');
    }
  }
  visit(folder);return result;
}
function same(a,b) { return !!b && Object.keys(a).length===Object.keys(b).length && Object.keys(a).every(key=>a[key]===b[key]); }
function checkSources(sources) {
  const ts = require(path.join(process.env.DEVECO_APP || '/Applications/DevEco-Studio.app', 'Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
  const errors=[];
  for (const [file,source] of sources) {
    if (/(?:MembershipSuite|SuiteCatalog)\.ets$/.test(file)) errors.push(file+': 全家桶只在共享 membership 模块维护，删除宿主副本。');
    const scanner=ts.createScanner(ts.ScriptTarget.Latest,true,ts.LanguageVariant.Standard,source), tokens=[];
    while(scanner.scan()!==ts.SyntaxKind.EndOfFileToken) tokens.push({kind:scanner.getToken(),text:scanner.getTokenText()});
    for(const token of tokens) {
      if(token.kind===ts.SyntaxKind.Identifier && ['JuMembershipPage','JuMembershipPanel','JuMembershipSuite','fixedKitappSuite','completeKitappAppOffer'].includes(token.text))
        errors.push(file+': 禁止绕过固定成品入口 '+token.text+'；使用 kitapp-membership 的 KitappMembershipPage。');
      if(token.kind===ts.SyntaxKind.StringLiteral && /kitapp-membership\//.test(token.text))
        errors.push(file+': 禁止深层导入会员模块内部实现。');
    }
    const entryProps={
      KitappMembershipPage:['app','asDestination','active','showSuite','suitePurchaseEnabled','suiteOwned','paymentBusy','contactEmail','appActions','onAppAction','onBack','onPurchase','onOpenSuite','onRestore','onUserAgreement','onPrivacy'],
      KitappSuitePage:['title','active','hasTabBar','accountAvatar','inlineAction','owned','agreementChecked','actionLabel','actionEnabled','onAccount','onPurchase','onAgreementChange','onAgreementTap','onUserAgreement','onPrivacy']};
    for(const name in entryProps) {
      for(let i=0;i<tokens.length;i++) {
        if(tokens[i].text!==name||tokens[i+1]?.text!=='('||tokens[i+2]?.text!=='{')continue;
        let depth=1;
        for(let j=i+3;j<tokens.length&&depth>0;j++) {
          const text=tokens[j].text;
          if(depth===1 && text==='...') errors.push(file+': 成品会员页禁止展开未知配置。');
          if(depth===1 && tokens[j].kind===ts.SyntaxKind.Identifier && tokens[j+1]?.text===':' && !entryProps[name].includes(text))
            errors.push(file+': 成品会员页不接受 '+text+'；全家桶内容不可覆盖。');
          if(['{','(','['].includes(text))depth++;
          if(['}',')',']'].includes(text))depth--;
        }
      }
    }
  }
  return errors;
}
function check(appRoot) {
  const folder=path.join(appRoot,'membership');
  const lock=JSON.parse(fs.readFileSync(path.join(appRoot,'kitapp-membership.lock.json'),'utf8'));
  const metadata=JSON.parse(fs.readFileSync(path.join(folder,'oh-package.json5'),'utf8'));
  if(lock.library!=='KitappMembership'||lock.version!==metadata.version||!same(inventory(folder),lock.files))
    throw Error('统一会员模块与锁定版本不一致，请回公共源维护并通过 vendor-membership.cjs 显式升级。');
  const sources=new Map();
  function visit(base) { for(const e of fs.readdirSync(base,{withFileTypes:true})) {const f=path.join(base,e.name);if(e.isDirectory())visit(f);else if(f.endsWith('.ets'))sources.set(path.relative(appRoot,f),fs.readFileSync(f,'utf8'));} }
  visit(path.join(appRoot,'entry/src/main/ets'));
  const errors=checkSources(sources);if(errors.length)throw Error(errors.join('\n'));
  console.log(`PASS: KitappMembership ${lock.version} 固定资料/资源校验与宿主接入约束。`);
}
if(require.main===module)check(path.resolve(process.argv[2] || path.join(__dirname,'../../..')));
module.exports={inventory,same,check,checkSources};
