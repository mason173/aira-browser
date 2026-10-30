#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const cache = new Map();
function load(file) {
  const absolute = path.resolve(root, file);
  if (cache.has(absolute)) return cache.get(absolute);
  const module = { exports: {} };
  cache.set(absolute, module.exports);
  const source = fs.readFileSync(absolute, 'utf8');
  const compiled = ts.transpileModule(source, {compilerOptions: {module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020}});
  vm.runInNewContext(compiled.outputText, {module, exports: module.exports, require: ref =>
    ref.endsWith('BrowserModels') ? {} : load(path.relative(root, path.resolve(path.dirname(absolute), ref + '.ets'))),
    Set, Map, Date, Math, JSON});
  return module.exports;
}
const {HomeShortcutFolderService} = load('services/shortcuts/HomeShortcutFolderService.ets');
const {HomeShortcutGridPolicy} = load('features/newtab/HomeShortcutGridPolicy.ets');
const {HomeShortcutDragSession} = load('features/newtab/HomeShortcutDragSession.ets');
const folders = new HomeShortcutFolderService();
const record = (id, position, extra = {}) => ({id, position, title: id, url: `https://${id}.example`,
  folderName: '首页', scenarioId: 'default', ...extra});
const original = [record('a',0),record('b',1),record('c',2)];
const grouped = folders.apply(original,{operation:'merge',shortcutId:'a',targetId:'b',title:'Tools'},'f',100).shortcuts;
assert.equal(original[0].parentId, undefined, 'preview operations must not mutate live records');
assert.equal(folders.listContainer(grouped).length, 2);
assert.equal(folders.listContainer(grouped,'f').length, 2);
assert.equal(grouped.find(x=>x.id==='a').parentId,'f');
assert.equal(grouped.find(x=>x.id==='f').url,'');
assert.deepEqual(Array.from(folders.listContainer(grouped,'f'),x=>x.id),['b','a'],'the receiving link precedes the dropped link');
const moved = folders.apply(grouped,{operation:'move',shortcutId:'a',parentId:''},'',101).shortcuts;
assert.equal(moved.some(x=>x.kind==='folder'),false,'extracting the penultimate member dissolves the folder');
assert.equal(moved.find(x=>x.id==='b').parentId,undefined);
const extractedIntoNew=folders.apply(grouped,{operation:'extract',shortcutId:'a',dropOperation:'merge',targetId:'c',
  orderedIds:folders.listContainer(moved).map(x=>x.id)},'new-folder',106).shortcuts;
assert.equal(extractedIntoNew.find(x=>x.id==='a').parentId,'new-folder');
assert.equal(extractedIntoNew.find(x=>x.id==='c').parentId,'new-folder');
assert.equal(extractedIntoNew.find(x=>x.id==='b').parentId,undefined);
assert.equal(extractedIntoNew.some(x=>x.id==='f'),false);
const orphan = [record('x',0,{parentId:'missing'}),record('y',1)];
assert.equal(folders.listContainer(orphan).length,2,'orphaned members stay reachable without rewriting membership');
assert.equal(orphan[0].parentId,'missing');
assert.equal(folders.apply(grouped,{operation:'merge',shortcutId:'a',targetId:'b'},'nested',102).changed,false);
const renamed = folders.apply(grouped,{operation:'rename',shortcutId:'f',title:'Work'},'',103).shortcuts;
assert.equal(renamed.find(x=>x.id==='f').title,'Work');
const spec={columns:4,width:320,columnGap:0,rowGap:0,rowHeight:80,centerPartialRows:false};
const policy=new HomeShortcutGridPolicy();
assert.equal(policy.footprint([record('big',0,{kind:'folder',folderDisplayMode:'large'})]),4);
const rootOrder=folders.listContainer(moved).map(x=>x.id).reverse();
const extracted=folders.apply(grouped,{operation:'move',shortcutId:'a',parentId:'',orderedIds:rootOrder},'',104);
assert.deepEqual(Array.from(folders.listContainer(extracted.shortcuts), x=>x.id),rootOrder,'extraction and root ordering commit atomically');
assert.equal(folders.apply(grouped,{operation:'move',shortcutId:'a',parentId:'',orderedIds:['a']},'',105).changed,false);
const {HomeShortcutDragGeometry}=load('features/newtab/HomeShortcutDragGeometry.ets');
const geometry=new HomeShortcutDragGeometry();
const viewport={x:20,y:100,width:320,height:400};
assert.equal(geometry.scrollStep(300,viewport),0);
assert.ok(geometry.scrollStep(110,viewport)<0);
assert.ok(geometry.scrollStep(490,viewport)>0);
assert.equal(geometry.scrollStep(520,viewport),0);
assert.equal(geometry.outside(100,80,viewport),false);
assert.equal(geometry.outside(100,70,viewport),true);
const mixed=[record('large',0,{kind:'folder',folderDisplayMode:'large'}),...original];
const layout=policy.layout(mixed,spec,true);
assert.equal(layout.slots[0].span,2);
for(let i=0;i<layout.slots.length;i++) for(let j=i+1;j<layout.slots.length;j++){
  const a=layout.slots[i],b=layout.slots[j];
  assert.ok(a.x+a.width<=b.x||b.x+b.width<=a.x||a.y+a.height<=b.y||b.y+b.height<=a.y,'mixed spans cannot overlap');
}
const reorder=policy.reorder(mixed,'c','a');
assert.equal(reorder[0].id,'large','dragging a small icon preserves large-folder slots');
const drag=new HomeShortcutDragSession();
drag.begin('a',original,spec,'');
drag.update({x:80,y:0},0);
assert.equal(drag.release(),undefined,'a displayed candidate alone cannot commit a merge');
drag.update({x:80,y:0},101);
assert.equal(drag.release().operation,'merge');
drag.cancel();
assert.equal(drag.release(),undefined,'cancel clears every pending commit');
drag.begin('a',original,spec,'');
drag.update({x:55,y:0},0);
drag.update({x:55,y:0},201);
const projected=drag.snapshot().orderedIds.join(',');
assert.notEqual(projected,'a,b,c');
// The current displayed target 'b' has moved to the first slot. Enter its core.
drag.update({x:0,y:0},202);
assert.equal(drag.snapshot().orderedIds.join(','),projected,'center feedback preserves the confirmed projection');
drag.update({x:0,y:0},303);
assert.equal(drag.release().operation,'merge');
const tail=Array.from({length:5},(_,index)=>record(`t${index}`,index));
const tailSpec={...spec,iconSize:54,centerPartialRows:true};
drag.begin('t4',tail,tailSpec,'',true);
drag.update({x:-80,y:-80},0);
assert.equal(drag.snapshot().targetId,'t0','centered tail hit testing includes the add slot');
drag.update({x:-80,y:-80},101);
assert.equal(drag.release().operation,'merge');
drag.begin('a',original,{...spec,iconSize:54},'');
drag.update({x:80,y:30},0);
assert.equal(drag.snapshot().center,false,'the label area does not count as the icon merge core');
// Exercise production persistence normalization: an unrelated order change must not
// acquire a new content revision and overwrite another device's newer membership.
const repositorySource=fs.readFileSync(path.join(root,'data/repositories/BrowserRepositories.ets'),'utf8');
const names=['equalShortcutContent','normalizeShortcutTreeForLocalReplace','normalizeShortcutForLocalReplace','flattenShortcutList','cloneShortcutWithIcon','rebaseShortcutReplacement','rebaseShortcutContent','isAiraOwnedShortcut','markShortcutDeleted','resolveShortcutRecordModifiedAt'];
const functions=names.map(name=>{
  const match=repositorySource.match(new RegExp(`function ${name}\\([^]*?\\n}`));
  assert.ok(match, name); return match[0];
}).join('\n');
const moduleForNormalization={exports:{}};
vm.runInNewContext(ts.transpileModule(functions+'\nexport {normalizeShortcutTreeForLocalReplace,rebaseShortcutReplacement,markShortcutDeleted};',{
  compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}
}).outputText,{module:moduleForNormalization,exports:moduleForNormalization.exports,Date,
  DEFAULT_DEVICE_ID:'device',Math,JSON});
const normalize=moduleForNormalization.exports.normalizeShortcutTreeForLocalReplace;
const old=original.map(x=>({...x,createdAt:10,updatedAt:20,sync:{source:'local',state:'synced',lastModifiedAt:20}}));
old[1].scenarioId='other';
const {rebaseShortcutReplacement:rebase,markShortcutDeleted:tombstone}=moduleForNormalization.exports;
const newer=old.map(x=>({...x}));
newer[0]={...old[0],parentId:'remote-folder',sync:{...old[0].sync,lastModifiedAt:900}};
newer.push(record('remote-added',3));
const rebased=rebase({scenarioId:'default',preserveScenarios:true,baseShortcuts:old,shortcuts:[old[2],old[1],old[0]]},newer);
assert.equal(rebased.find(x=>x.id==='a').parentId,'remote-folder','a stale reorder cannot erase newer membership');
assert.ok(rebased.some(x=>x.id==='remote-added'),'a stale replacement preserves concurrent additions');
const renamedLocal=old.map(x=>({...x,title:x.id==='a'?'Local title':x.title}));
const bothEdits=rebase({scenarioId:'default',preserveScenarios:true,baseShortcuts:old,shortcuts:renamedLocal},newer);
assert.equal(bothEdits.find(x=>x.id==='a').title,'Local title');
assert.equal(bothEdits.find(x=>x.id==='a').parentId,'remote-folder','field edits merge independently');
assert.ok(tombstone({...old[0],sync:{...old[0].sync,lastModifiedAt:Date.now()+10000}}).sync.deletedAt>Date.now()+9999);
const normalized=normalize('default',[old[2],old[1],old[0]],old,true);
assert.equal(normalized[0].sync.lastModifiedAt,20);
assert.equal(normalized[1].scenarioId,'other','aggregate ordering must not migrate legacy scenarios');
const changed=normalize('default',[{...old[0],parentId:'f'},old[1],old[2]],old,true);
assert.ok(changed[0].sync.lastModifiedAt>20);
assert.equal(changed[1].sync.lastModifiedAt,20);
const validatorSource=fs.readFileSync(path.join(root,'services/sync/PersonalizationSyncSnapshotValidationService.ets'),'utf8');
const validatorModule={exports:{}};
const sectionIds=['home_shortcuts','core_preferences','activity_heatmap','search'];
vm.runInNewContext(ts.transpileModule(validatorSource,{
  compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}
}).outputText,{module:validatorModule,exports:validatorModule.exports,
  require:()=>({PERSONALIZATION_SYNC_SCHEMA_VERSION:3,PERSONALIZATION_SYNC_ITEM_IDS:sectionIds}),Set,Math});
const validator=new validatorModule.exports.PersonalizationSyncSnapshotValidationService();
const metadata={state:'synced',source:'local',lastModifiedAt:100,lastModifiedBy:'device',deviceId:'device'};
const sections=Object.fromEntries(sectionIds.map(id=>[id,{enabled:false,updatedAt:100,payload:{}}]));
sections.home_shortcuts={enabled:true,updatedAt:100,payload:{scenarios:[],
  shortcuts:grouped.map(x=>({...x,sync:{...metadata}})),orders:[]}};
const snapshot={meta:{version:3,deviceId:'device',generatedAt:'2026-10-30'},sections};
assert.equal(validator.validate(snapshot,'test'),snapshot);
assert.equal(validator.validate({...snapshot,meta:{...snapshot.meta,version:2}},'legacy').meta.version,2);
assert.throws(()=>validator.validate({...snapshot,meta:{...snapshot.meta,version:4}},'future'));
const invalid=JSON.parse(JSON.stringify(snapshot));
invalid.sections.home_shortcuts.payload.shortcuts[0].parentId=123;
assert.throws(()=>validator.validate(invalid,'invalid-parent'));
console.log('Home folders: membership, orphan reachability, dissolution, mixed spans and two-intent drag arbitration passed.');

function extractClass(file, className, names, globals={}) {
  const source=fs.readFileSync(path.join(root,file),'utf8');
  const methods=names.map(name=>{
    const match=source.match(new RegExp(`  (?:private )?(?:async )?${name}(?:<[^>]*>)?\\([^]*?\\n  }`));
    assert.ok(match,name);return match[0];
  }).join('\n');
  const module={exports:{}};
  vm.runInNewContext(ts.transpileModule(`export class ${className} { ${methods} }`,{
    compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}
  }).outputText,{module,exports:module.exports,Set,Map,Date,Math,JSON,...globals});
  return module.exports[className];
}
const Backup=extractClass('services/backup/LocalBackupService.ets','Backup',
  ['buildPortableHomeShortcutsPayload','buildImportedHomeShortcutsPayload','buildImportedSyncMetadata']);
const backup=new Backup();
const payload={scenarios:[{id:'default',name:'Home',color:'',icon:'',position:0,archived:false,createdAt:1,updatedAt:2,sync:metadata}],
  shortcuts:grouped.map(x=>({...x,folderDisplayMode:x.kind==='folder'?'large':x.folderDisplayMode})),
  orders:[{scenarioId:'default',shortcutIds:grouped.map(x=>x.id),updatedAt:100}]};
const restored=backup.buildImportedHomeShortcutsPayload(backup.buildPortableHomeShortcutsPayload(payload));
assert.equal(restored.shortcuts.find(x=>x.id==='a').parentId,'f');
assert.equal(restored.shortcuts.find(x=>x.id==='f').folderDisplayMode,'large');
assert.equal(restored.shortcuts.length,grouped.length);
const Database=extractClass('data/database/BrowserDatabase.ets','Database',
  ['ensureSchema','ensureOptionalShortcutColumns','mapShortcutRows','toShortcutValues'],{
    SHORTCUTS_TABLE:'shortcuts',CURRENT_BROWSER_DATABASE_SCHEMA_VERSION:8,INITIAL_BROWSER_DATABASE_SCHEMA_VERSION:1,
    hilog:{error(){},warn(){}},DOMAIN:0,TAG:'test'
  });
const database=new Database();
for (const shortcut of restored.shortcuts) {
  const row=database.toShortcutValues(shortcut);
  let visited=false,closed=false;
  const rows=database.mapShortcutRows({getColumnIndex:name=>name,
    goToNextRow:()=>visited?false:(visited=true),isColumnNull:key=>row[key]==null,
    getString:key=>row[key],getLong:key=>row[key],close(){closed=true;}});
  assert.equal(rows.length,1);
  assert.equal(rows[0].parentId,shortcut.parentId);
  assert.equal(rows[0].folderDisplayMode,shortcut.folderDisplayMode);
  assert.equal(rows[0].kind,shortcut.kind);
  assert.ok(closed);
}
(async()=>{
  let version=7;
  const columns=new Set(['children','folder_display_mode']);
  const store={async executeSql(sql){
    const column=sql.match(/ADD COLUMN (\w+)/)?.[1];
    if(columns.has(column))throw new Error('duplicate column');
    columns.add(column);
  },async querySql(){
    assert.ok(columns.has('parent_id'));
    assert.ok(columns.has('folder_display_mode'));
    return {close(){}};
  }};
  database.ensureSchemaStateTable=async()=>{};
  database.readSchemaVersion=async()=>version;
  database.writeSchemaVersion=async(_store,value)=>{version=value;};
  await database.ensureSchema(store);
  assert.equal(version,8,'v7 migration commits schema8 only after folder columns are readable');
  version=7;
  await assert.rejects(database.ensureSchema({async executeSql(){throw new Error('disk full');},async querySql(){throw new Error('missing parent_id');}}));
  assert.equal(version,7,'a failed column migration cannot be recorded as schema8');
  console.log('Home folders: portable backup, database mappings and v7→v8 migration passed.');
})().catch(error=>{console.error(error);process.exitCode=1;});

(async()=>{
  const Toggle=extractClass('services/shortcuts/HomeShortcutToggleService.ets','Toggle',['toggleNow'],{HomeShortcutFolderService});
  const toggle=new Toggle();
  let stored=grouped;
  toggle.refresh=async()=>stored;
  toggle.findMatchingShortcutsForTarget=()=>[stored.find(x=>x.id==='a')];
  toggle.repository={listAll:()=>stored,async replaceScenarioShortcuts(command){stored=command.shortcuts;return stored;}};
  const result=await toggle.toggleNow({title:'a',url:'https://a.example',scenarioId:'default'});
  assert.ok(result.removed);
  assert.equal(stored.some(x=>x.id==='a'||x.id==='f'),false,'bookmark remove-from-home also dissolves the penultimate-member folder');
  assert.equal(stored.find(x=>x.id==='b').parentId,undefined);
  console.log('Home folders: bookmark toggle uses the same source-folder dissolution rules.');
})().catch(error=>{console.error(error);process.exitCode=1;});

const Merge=extractClass('services/sync/PersonalizationSyncSnapshotService.ets','Merge',
  ['mergeHomeShortcutRecords','stripDeviceLocalIconFromShortcut','isDeviceLocalIconPath','cloneObject',
   'resolveShortcutModifiedAt','normalizeTimestamp','compareHomeShortcutRecordOrder','compareStableString','resolveSnapshotSchemaVersion'],
  {PERSONALIZATION_SYNC_SCHEMA_VERSION:3});
const merge=new Merge();
assert.equal(merge.resolveSnapshotSchemaVersion({home_shortcuts:{enabled:true,payload:{shortcuts:original}}}),2,'ordinary homes keep the deployed v2 wire format');
assert.equal(merge.resolveSnapshotSchemaVersion({home_shortcuts:{enabled:true,payload:{shortcuts:grouped}}}),3,'folder snapshots require a reader that understands membership');
assert.equal(merge.resolveSnapshotSchemaVersion({home_shortcuts:{enabled:false,payload:{}}}),2);
assert.equal(merge.resolveSnapshotSchemaVersion({home_shortcuts:{enabled:false,payload:{shortcuts:grouped}}}),3,'preserved disabled folder payloads cannot be downgraded');
merge.homeShortcutLogicService={convergeDuplicateDestinations:shortcuts=>({shortcuts})};
const localMember={...old[0],position:5};
const remoteMember={...old[0],parentId:'remote-folder',sync:{...metadata,lastModifiedAt:900}};
const mergedMember=merge.mergeHomeShortcutRecords({shortcuts:[localMember]},{shortcuts:[remoteMember]},'ordinary');
assert.equal(mergedMember[0].parentId,'remote-folder');
const alive={...grouped.find(x=>x.id==='f'),sync:{...metadata,lastModifiedAt:100}};
const dead={...alive,sync:{...metadata,lastModifiedAt:200,deletedAt:200}};
assert.equal(merge.mergeHomeShortcutRecords({shortcuts:[alive]},{shortcuts:[dead]},'ordinary')[0].sync.deletedAt,200);
for(const [left,right] of [[alive,dead],[dead,alive]]) {
  const kept=merge.mergeHomeShortcutRecords({shortcuts:[left]},{shortcuts:[right]},'provider-switch')[0];
  assert.equal(kept.sync.deletedAt,undefined,'provider switches preserve a live folder against the opposing tombstone');
}
console.log('Home folders: ordinary record deletion and provider-switch preservation passed.');

(async()=>{
  const Sync=extractClass('services/sync/PersonalizationSyncService.ets','Sync',
    ['mergeSnapshots','buildActiveProviderSnapshot'],{PERSONALIZATION_SYNC_ITEM_IDS:['home_shortcuts']});
  const sync=new Sync();
  sync.snapshotService={resolveSnapshotSchemaVersion:merge.resolveSnapshotSchemaVersion.bind(merge),
    sanitizeSectionForProvider:(_id,section)=>section,
    mergeConcurrentSection:(_id,_local,remote)=>remote,areSnapshotContentsEqual:()=>false};
  sync.hasNonPortableRemoteContent=()=>false;
  sync.isItemSelected=()=>true;
  sync.activatePortableSection=(_id,section)=>section;
  const local={meta:{version:2,deviceId:'local',generatedAt:'2026-10-30'},sections:{home_shortcuts:{enabled:true,updatedAt:1,payload:{shortcuts:original}}}};
  const remote={...local,meta:{...local.meta,version:3},sections:{home_shortcuts:{enabled:true,updatedAt:2,payload:{shortcuts:grouped}}}};
  const merged=await sync.mergeSnapshots(local,remote,{});
  assert.equal(merged.snapshot.meta.version,3,'merging a remote folder into an ordinary local home uploads schema3');
  assert.ok(merged.shouldUpload);
  assert.equal(merged.snapshot.sections.home_shortcuts.payload.shortcuts.find(x=>x.id==='a').parentId,'f');
  assert.equal(sync.buildActiveProviderSnapshot(local).meta.version,2);
  console.log('Home folders: final provider snapshot and merged remote folders retain the required wire version.');
})().catch(error=>{console.error(error);process.exitCode=1;});
