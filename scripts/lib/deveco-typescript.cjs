/*
 * Shared TypeScript runtime resolver for the static contract checks under scripts/.
 *
 * Those checks transpile .ets sources with ts.transpileModule and evaluate them in a vm. The compiler
 * originally came only from DevEco Studio's bundled hvigor toolchain, which does not exist on the Linux
 * machines that run Client CI, so every check failed to load before it could inspect anything.
 *
 * Resolution order:
 *   1. DEVECO_TYPESCRIPT_PATH, for an explicit override.
 *   2. The `typescript` devDependency in this repository (root package.json). This is the pinned
 *      compiler, so local runs and CI agree on it.
 *   3. DevEco Studio's bundled hvigor TypeScript, so a HarmonyOS machine works with no npm install.
 *
 * If none resolve, fail loudly: silently skipping would disable these contracts everywhere.
 */

const fs = require('node:fs');
const path = require('node:path');

const DEVECO_TYPESCRIPT_RELATIVE =
  path.join('tools', 'hvigor', 'hvigor', 'node_modules', 'typescript', 'lib', 'typescript.js');

const REPO_ROOT = path.resolve(__dirname, '..', '..');

// DevEco Studio keeps its bundled toolchain under a per-platform install root.
const DEVECO_INSTALL_ROOTS = [
  process.env.DEVECO_STUDIO_HOME,
  process.env.DEVECO_STUDIO_PATH,
  process.env.DEVECO_HOME,
  '/Applications/DevEco-Studio.app/Contents',
  '/Applications/DevEco-Studio.app',
  path.join(process.env.HOME || '', 'Applications', 'DevEco-Studio.app', 'Contents'),
  'C:\\Program Files\\Huawei\\DevEco Studio',
  'C:\\Program Files\\DevEco Studio',
  '/opt/deveco-studio',
  '/usr/local/deveco-studio',
  '/usr/local/DevEco-Studio'
];

function loadFromPath(candidatePath) {
  if (!candidatePath || !fs.existsSync(candidatePath)) {
    return null;
  }
  return require(candidatePath);
}

function loadFromRepoDependency() {
  try {
    return require(require.resolve('typescript', { paths: [REPO_ROOT] }));
  } catch {
    return null;
  }
}

function loadFromDevEco() {
  for (const root of DEVECO_INSTALL_ROOTS) {
    if (!root) continue;
    const resolved = loadFromPath(path.join(root, DEVECO_TYPESCRIPT_RELATIVE));
    if (resolved) return resolved;
  }
  return null;
}

function resolveTypeScript() {
  const overridePath = process.env.DEVECO_TYPESCRIPT_PATH;
  if (overridePath) {
    const overridden = loadFromPath(path.resolve(overridePath));
    if (!overridden) {
      throw new Error(`DEVECO_TYPESCRIPT_PATH does not point at a TypeScript runtime: ${overridePath}`);
    }
    return overridden;
  }

  const resolved = loadFromRepoDependency() || loadFromDevEco();
  if (!resolved) {
    throw new Error(
      [
        'No TypeScript runtime available for the static contract checks.',
        'Run `npm ci` at the repository root to install the pinned compiler,',
        'or set DEVECO_TYPESCRIPT_PATH to a typescript/lib/typescript.js file.'
      ].join(' ')
    );
  }
  return resolved;
}

module.exports = resolveTypeScript();
