'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {test}=require('node:test'),ts=require('./lib/deveco-typescript.cjs');
const root=path.resolve(__dirname,'../AiraBrowser/entry/src/main/ets/services/membership');
const tick=()=>new Promise(resolve=>setImmediate(resolve));
const suite={productId:'aira_suite_lifetime',productType:1,purchaseToken:'suite-token',purchaseOrderId:'suite-order'};
const receipt=order=>JSON.stringify({type:1,jwsPurchaseOrder:'e30.'+Buffer.from(JSON.stringify(order)).toString('base64url')+'.e30'});
function fixture(){
 let available=true,products=true,failure='',pendingStage='',release;const calls=[];
 const cache=new Map();
 async function step(name,value){calls.push(name);if(failure===name)throw {code:1001860005};if(pendingStage===name)await new Promise(resolve=>release=resolve);return value;}
 const iap={ProductType:{NONCONSUMABLE:1,AUTORENEWABLE:2},PurchaseQueryType:{CURRENT_ENTITLEMENT:2,UNFINISHED:1,ALL:0},
  queryEnvironmentStatus:()=>step('environment'),
  queryProducts:(_ctx,input)=>{assert.deepEqual(Array.from(input.productIds),['aira_suite_lifetime']);assert.equal(input.productType,1);return step('products',products?[{id:'aira_suite_lifetime'}]:[]);},
  createPurchase:(_ctx,input)=>{assert.equal(input.productId,'aira_suite_lifetime');assert.equal(input.productType,1);assert.equal(input.applicationUserName,'binding:u');return step('purchase',{purchaseData:receipt(suite)});},
  queryPurchases:(_ctx,input)=>step('restore:'+input.productType+':'+input.queryType,{purchaseDataList:[receipt(suite),receipt({productId:'aira_pro_lifetime',purchaseToken:'own',purchaseOrderId:'own',productType:1})]}),
  finishPurchase:(_ctx,input)=>{assert.equal(input.productType,1);assert.equal(input.purchaseToken,'suite-token');assert.equal(input.purchaseOrderId,'suite-order');return step('finish');}
 };
 function load(name){if(cache.has(name))return cache.get(name);const output={};cache.set(name,output);
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root,name+'.ets'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2021}}).outputText,{
   exports:output,$r:name=>name,canIUse:()=>true,
   require(request){
    if(request==='@kit.IAPKit')return{iap};
    if(request==='@kit.ArkTS')return{util:{Base64Helper:class{decodeSync(value){return Buffer.from(value,'base64');}},TextDecoder:{create:()=>({decodeToString:value=>Buffer.from(value).toString('utf8')})}}};
    if(request.includes('HuaweiIapAccountBindingService'))return{HuaweiIapAccountBindingService:class{buildApplicationUserName(uid){return'binding:'+uid;}}};
    if(request.includes('AiraDistributionCapabilityOwner'))return{AIRA_DISTRIBUTION_CAPABILITY_OWNER:{isAvailable:()=>available,resolveUnavailableReason:()=> 'disabled'}};
    if(request.includes('AppResourceText'))return{resolveAppResourceText:value=>value};
    return load(path.basename(request));
   }
  });return output;
 }
 const service=new (load('HuaweiIapPurchaseService').HuaweiIapPurchaseService)();
 return{service,calls,disable(){available=false;},empty(){products=false;},fail(name){failure=name;},hold(name){pendingStage=name;},release(){release();}};
}
test('suite checkout uses its own nonconsumable SKU and account binding after checking environment/products',async()=>{
 const f=fixture(),result=await f.service.startProPurchase({},'suite_lifetime','u');assert.equal(result.ok,true);assert.equal(result.action,'purchase_suite_lifetime');assert.deepEqual(f.calls,['environment','products','purchase']);
});
test('unavailable products, native errors and Community never open checkout',async()=>{
 for(const mode of ['empty','failure','community']){
  const f=fixture();if(mode==='empty')f.empty();else if(mode==='failure')f.fail('products');else f.disable();
  const result=await f.service.startProPurchase({},'suite_lifetime','u');assert.equal(result.ok,false);assert(!f.calls.includes('purchase'));
 }
});
test('leaving or switching accounts during environment/product queries never opens a late cashier',async()=>{
 for(const stage of ['environment','products']){
  const f=fixture();let current=true;f.hold(stage);const pending=f.service.startProPurchase({},'suite_lifetime','u',()=>current);
  await tick();current=false;f.release();const result=await pending;assert.equal(result.ok,false);assert.equal(result.silent,true);assert(!f.calls.includes('purchase'));
 }
});
test('suite restore deduplicates current/unfinished modern receipts and ignores the own-app SKU',async()=>{
 const f=fixture(),result=await f.service.restorePurchases({},true);assert.equal(result.ok,true);assert.equal(result.purchaseCount,1);assert.equal(result.purchaseDataList[0],receipt(suite));
 assert(f.calls.includes('restore:1:1'));assert(f.calls.includes('restore:1:2'));assert(!f.calls.includes('purchase'));
});
test('finish uses the modern signed order fields and rejects missing order credentials',async()=>{
 const f=fixture();await f.service.finishPurchase({},receipt(suite),'nonconsumable');assert.deepEqual(f.calls,['finish']);
 await assert.rejects(()=>f.service.finishPurchase({},receipt({productId:'aira_suite_lifetime'}),'nonconsumable'));assert.equal(f.calls.length,1);
});

function coordinatorFixture(mode){
 let current=true;const calls=[],output={};
 vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root,'../../core/membership/AiraProPurchaseCoordinator.ets'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2021}}).outputText,{
  exports:output,$r:name=>name,
  require(name){
   if(name.includes('HuaweiIapProductCatalog')){
    const exports={};new Function('exports',ts.transpileModule(fs.readFileSync(path.join(root,'HuaweiIapProductCatalog.ets'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2021}}).outputText)(exports);return exports;
   }
   if(name.includes('AppResourceText'))return{resolveAppResourceText:value=>value};
   return new Proxy({},{get:()=>class{}});
  }
 });
 const owner=Object.create(output.AiraProPurchaseCoordinator.prototype);
 Object.assign(owner,{purchaseConsentGeneration:0,showDiagnosticMessages:false,
  membershipFeature:{capturePurchaseSessionGuard:()=>()=>current},launchGate:{armCashierDetection(){},finish(){}},
  iapService:{async startProPurchase(){calls.push('purchase');owner.cancelPurchaseConsent();return{ok:true,title:'paid',message:'paid',action:'purchase_suite_lifetime',purchaseDataList:[receipt(suite)]};},async finishPurchase(){calls.push('finish');}},
  verificationService:{async submitPurchaseData(){calls.push('verify');if(mode==='stale')current=false;return{ok:mode!=='reject',productId:'aira_suite_lifetime',productType:'nonconsumable',expiresAt:0,code:mode==='reject'?'rejected':undefined,message:'denied'};}}
 });return{owner,calls};
}
test('cashier-induced inactivity does not discard a paid order from the same account',async()=>{
 const f=coordinatorFixture('success'),result=await f.owner.startProPurchase({},'suite_lifetime','u');
 assert.equal(result.ok,true);assert.deepEqual(f.calls,['purchase','verify','finish']);assert.equal(result.verifiedProductId,'aira_suite_lifetime');
});
test('rejected verification and an account change during verification never confirm delivery',async()=>{
 for(const mode of ['reject','stale']){const f=coordinatorFixture(mode),result=await f.owner.startProPurchase({},'suite_lifetime','u');assert.equal(result.ok,false);assert.deepEqual(f.calls,['purchase','verify']);}
});
