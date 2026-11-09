'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const {test}=require('node:test'),ts=require('./lib/deveco-typescript.cjs');
const root=path.resolve(__dirname,'../AiraBrowser/entry/src/main/ets');
const tick=()=>new Promise(resolve=>setImmediate(resolve));
function fixture(){
 let current=true,decision,dialogs=0,purchases=0,launched=0,restores=0,lastOptions,revision=0,suiteOwned=false,linked=true,links=0;const documents=[];const cache=new Map();
 const noTypes=new Proxy({},{get:()=>class{}});
 function load(file){if(cache.has(file))return cache.get(file);const exports={};cache.set(file,exports);
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2021,module:ts.ModuleKind.CommonJS}}).outputText,{
   exports,Date,$r:name=>name,
   require(name){
    if(name==='kitapp-membership')return{KitappPurchaseConsentRequest:class{constructor(_ui,options){dialogs++;lastOptions=options;this.result=new Promise(resolve=>{decision=resolve});}cancel(){decision?.({accepted:false});}}};
    if(name==='@kit.ArkUI')return{window:{async getLastWindow(){return{getUIContext:()=>({})};}}};
    if(name.includes('AiraLegalDocuments'))return{resolveAiraLegalDocumentLink:id=>({url:id})};
    if(name.includes('HuaweiIapProductCatalog')||name.includes('AiraProStorePricePolicy'))return load(path.resolve(path.dirname(file),name)+'.ets');
    return noTypes;
   }
  });return exports;
 }
 const api=load(path.join(root,'core/membership/AiraProPurchaseCoordinator.ets'));
 const owner=Object.create(api.AiraProPurchaseCoordinator.prototype);
 const member={refreshState:async()=>{revision++;return{plan:'guest',userId:'u'};},capturePurchaseSessionGuard:()=>()=>current,getAppSuiteState:()=>({owned:suiteOwned,checked:true,revision})};
 Object.assign(owner,{membershipFeature:member,purchaseLaunchInFlight:false,purchaseConsentGeneration:0,
  accountUnionLinkService:{async linkUnionId(){links++;return linked;}},
  purchasePolicyService:{resolveOneTimePlanAction:()=> 'purchase',resolveSubscriptionPlanAction:()=> 'purchase'},
  launchGate:{hasTimedOut:()=>false},isEffectAllowed:()=>current,
  beginHuaweiPaymentLaunch(){launched++;},endHuaweiPaymentLaunch(){},resolveAccountUid:uid=>uid,
  async startProPurchase(){purchases++;return{ok:false,silent:true};},async restorePurchase(){restores++;return{ok:false,silent:true};},showOperationResult(){}});
 const host={onMembershipStateChanged(){},onLoginRequired(){},showMessage(){}};
 const context={async openLink(url){documents.push(url)}};
 const boundary={dataScope:'profile_persistent',privacyMode:'regular'};
 return{owner,member,host,context,boundary,get dialogs(){return dialogs},get purchases(){return purchases},get launched(){return launched},get restores(){return restores},get links(){return links},setOwned(){suiteOwned=true;},linkFails(){linked=false;},get options(){return lastOptions},documents,
  run(plan='one_time',uid='u'){return owner.startPurchaseFlow(context,plan,uid,host,boundary)},answer(result){decision(result)},stale(){current=false}};
}
test('every Aira plan waits for confirmation before native payment or launch UI',async()=>{
 for(const plan of ['one_time','monthly','yearly']){
  const f=fixture(),pending=f.run(plan);await tick();assert.equal(f.dialogs,1);assert.equal(f.purchases,0);assert.equal(f.launched,0);
  assert.equal(f.options.recurring,plan!=='one_time');f.answer({accepted:true});await pending;assert.equal(f.purchases,1);assert.equal(f.launched,1);
 }
});
test('decline, links, stale account and repeated taps never create an extra purchase',async()=>{
 for(const mode of ['decline','terms','stale']){
  const f=fixture(),pending=f.run();await tick();await f.run();assert.equal(f.dialogs,1);
  if(mode==='stale')f.stale();f.answer(mode==='terms'?{accepted:false,link:'privacy'}:{accepted:mode==='stale'});await pending;
  assert.equal(f.purchases,0);assert.equal(f.documents.length,mode==='terms'?1:0);
 }
});
test('page cancellation before membership refresh completes cannot show a late dialog',async()=>{
 const f=fixture();let finish;f.member.refreshState=()=>new Promise(resolve=>{finish=resolve});const pending=f.run();f.owner.cancelPurchaseConsent();finish({plan:'guest'});await pending;assert.equal(f.dialogs,0);assert.equal(f.purchases,0);
});
test('restoring an existing purchase does not request new-purchase consent',async()=>{
 const f=fixture();await f.owner.restorePurchaseFlow(f.context,'u','one_time',f.host,f.boundary);assert.equal(f.dialogs,0);assert.equal(f.restores,1);
});

test('real membership session guards reject anonymous subjects and A→B→A reuse',()=>{
 const exports={};vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root,'features/membership/MembershipFeature.ets'),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2021,module:ts.ModuleKind.CommonJS}}).outputText,{exports,require:()=>new Proxy({},{get:()=>class{}})});
 let uid='A';const feature=Object.create(exports.MembershipFeature.prototype);Object.assign(feature,{accountScopeUid:'A',accountScopeGeneration:1,getHuaweiUid:()=>uid});
 const guard=feature.capturePurchaseSessionGuard('A');assert.equal(guard(),true);
 uid='B';feature.accountScopeUid='B';feature.accountScopeGeneration++;assert.equal(guard(),false);
 uid='A';feature.accountScopeUid='A';feature.accountScopeGeneration++;assert.equal(guard(),false);
 uid='';assert.equal(feature.capturePurchaseSessionGuard('')(),false);
});


test('Aira suite requires fixed-suite consent and trusted account linking before native payment',async()=>{
 const f=fixture(),pending=f.run('suite_lifetime');await tick();assert.equal(f.dialogs,1);assert.equal(f.options.suite,true);assert.equal(f.options.recurring,false);assert.equal(f.links,1);
 f.answer({accepted:true});await pending;assert.equal(f.links,1);assert.equal(f.purchases,1);
 const blocked=fixture();blocked.linkFails();await blocked.run('suite_lifetime');assert.equal(blocked.dialogs,0);assert.equal(blocked.purchases,0);
});
test('suite checkout rejects owned or unconfirmed server rights and canceled confirmation',async()=>{
 const owned=fixture();owned.setOwned();await owned.run('suite_lifetime');assert.equal(owned.dialogs,0);assert.equal(owned.purchases,0);
 const cached=fixture();cached.member.refreshState=async()=>({plan:'guest',userId:'u'});await cached.run('suite_lifetime');assert.equal(cached.dialogs,0);assert.equal(cached.purchases,0);
 const no=fixture(),pending=no.run('suite_lifetime');await tick();no.answer({accepted:false});await pending;assert.equal(no.links,1);assert.equal(no.purchases,0);
});
test('suite restoration links the account and refreshes server rights even with empty native recovery',async()=>{
 const f=fixture();await f.owner.restorePurchaseFlow(f.context,'u','suite_lifetime',f.host,f.boundary);
 assert.equal(f.links,1);assert.equal(f.restores,1);assert.equal(f.dialogs,0);assert(f.member.getAppSuiteState().revision>0);
});


test('leaving the page while cross-app linking is pending cannot launch payment later',async()=>{
 const f=fixture();let finishLink;f.owner.accountUnionLinkService.linkUnionId=()=>new Promise(resolve=>finishLink=resolve);
 const pending=f.run('suite_lifetime');await tick();assert(finishLink);
 f.owner.cancelPurchaseConsent();finishLink(true);await pending;assert.equal(f.launched,0);assert.equal(f.purchases,0);
});


test('a suite discovered after account linking blocks a duplicate cross-app purchase',async()=>{
 const f=fixture();f.owner.accountUnionLinkService.linkUnionId=async()=>{f.setOwned();return true;};
 await f.run('suite_lifetime');assert.equal(f.dialogs,0);assert.equal(f.purchases,0);
});
test('a temporary re-link failure does not prevent restoring already linked server rights',async()=>{
 const f=fixture();f.linkFails();await f.owner.restorePurchaseFlow(f.context,'u','suite_lifetime',f.host,f.boundary);
 assert.equal(f.restores,1);assert(f.member.getAppSuiteState().revision>0);
});


test('suite confirmation opens the actual Kitapp One agreement without initiating purchase',async()=>{
 const f=fixture(),pending=f.run('suite_lifetime');await tick();assert.equal(f.options.membershipTitle,'《Kitapp One 会员服务协议》');
 f.answer({accepted:false,link:'membership'});await pending;assert.deepEqual(f.documents,['suite_membership_service_agreement']);assert.equal(f.purchases,0);
});
