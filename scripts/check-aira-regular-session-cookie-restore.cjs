const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');

// ArkWeb keeps session cookies (no Expires/Max-Age) in memory, so a site whose sign-in lives in one, such as
// GitHub's `_gh_sess`, is signed out as soon as the process is gone. The regular-profile snapshot copies those
// cookies to preferences on the way out and writes them back before the first page loads.
//
// The restore used to run before `initializeBrowserAppLaunchReadiness` published the application context, and
// the snapshot store resolves its preferences through `AppRuntimeContext`. A cold start therefore threw inside
// the restore, the catch swallowed the error into one warn line, and nothing came back — on device this read as
// `Failed to restore regular session cookies: {}` right after `Ability onCreate`, while a warm process restored
// normally. Reordering `AppRuntimeContext.setApplicationContext` ahead of the restore is what this file keeps
// from regressing, together with the scope rules a written-back cookie must obey to be accepted at all.
const repoRoot = path.resolve(__dirname, '..');
const etsRoot = path.join(repoRoot, 'AiraBrowser/entry/src/main/ets');
const ability = fs.readFileSync(path.join(etsRoot, 'app/abilities/EntryAbility.ets'), 'utf8');
const repository = fs.readFileSync(
  path.join(etsRoot, 'data/browser/RegularSessionCookieSnapshotRepository.ets'), 'utf8');
const service = fs.readFileSync(path.join(etsRoot, 'services/web/SiteDataControlService.ets'), 'utf8');

function fnBody(source, signature) {
  const start = source.indexOf(signature);
  assert.ok(start >= 0, `Missing declaration: ${signature}`);
  const paramsEnd = source.indexOf('):', start);
  assert.ok(paramsEnd > start, `Missing parameter list end: ${signature}`);
  const openBrace = source.indexOf('{', paramsEnd);
  assert.ok(openBrace > paramsEnd, `Missing body: ${signature}`);
  let depth = 0;
  for (let index = openBrace; index < source.length; index += 1) {
    const character = source[index];
    if (character === '{') {
      depth += 1;
    } else if (character === '}') {
      depth -= 1;
      if (depth === 0) {
        return source.slice(start, index + 1);
      }
    }
  }
  assert.fail(`Unbalanced body: ${signature}`);
}

test('a cold start publishes the application context before it restores session cookies', () => {
  const onCreate = fnBody(ability, 'onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {');
  const publish = onCreate.indexOf('AppRuntimeContext.setApplicationContext(');
  const restore = onCreate.indexOf('this.regularSessionCookieRestore = this.restoreRegularSessionCookies()');
  assert.ok(publish >= 0, 'onCreate must publish the application context the snapshot store resolves preferences with');
  assert.ok(restore >= 0, 'onCreate must still stage the regular session cookie restore');
  assert.ok(
    publish < restore,
    'the application context must be published before the regular session cookie restore starts, or a cold ' +
    'start restores nothing while a warm process restores fine'
  );
});

test('the first page load still waits for the restore', () => {
  const prepare = fnBody(ability, 'private prepareWindowStage(windowStage: window.WindowStage, source:');
  assert.ok(
    prepare.includes('return this.regularSessionCookieRestore'),
    'the window stage must keep waiting for the restore before it loads content, so the first page receives ' +
    'the cookies it was signed in with'
  );
});

test('the snapshot store refuses to run before the application context exists', () => {
  const getStore = fnBody(repository, 'private async getStore(): Promise<preferences.Preferences> {');
  assert.ok(
    getStore.includes('AppRuntimeContext.hasApplicationContext()'),
    'the store must name the application-context contract instead of failing with a bare not-initialized error'
  );
});

test('a written-back cookie keeps the scope and prefix rules the engine accepts', () => {
  const build = fnBody(service, 'private buildSetCookieValue(cookie: PrivateModeCookieSnapshotRecord): string {');
  assert.ok(
    !build.includes('if (domain.length > 0)'),
    'a host-only cookie must not be widened into a domain cookie by a Domain attribute'
  );
  assert.ok(build.includes("domain.startsWith('.')"), 'only a domain cookie keeps its Domain attribute');
  assert.ok(
    build.includes("cookie.name.startsWith('__Host-')"),
    'a __Host- prefixed cookie must drop Domain and keep Path=/ with Secure, or the engine rejects it outright'
  );
  assert.ok(
    build.includes("cookie.name.startsWith('__Secure-')"),
    'a __Secure- prefixed cookie must be written back as Secure'
  );
});

test('one cookie the engine rejects does not abort the rest of the restore', () => {
  const restore = fnBody(service, 'async restoreRegularSessionCookies(): Promise<number> {');
  assert.ok(
    /try \{[\s\S]*configCookieSync[\s\S]*\} catch/.test(restore),
    'each cookie must be written inside its own guard, so one rejected value cannot drop every cookie behind it'
  );
  assert.ok(restore.includes('saveCookieSync()'), 'the restored cookies must still be flushed to disk');
});

test('an empty cookie jar does not overwrite the snapshot the next cold start needs', () => {
  const preserve = fnBody(service, 'async preserveRegularSessionCookies(): Promise<number> {');
  const emptyCheck = preserve.indexOf('cookies.length <= 0');
  assert.ok(emptyCheck >= 0, 'an unreadable jar at teardown must be recognized');
  assert.ok(
    emptyCheck < preserve.indexOf('saveSnapshot('),
    'the empty-jar check must run before the snapshot is written'
  );
});
