#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const {
  assertGoogleSupportedDomainCatalogScale,
  buildGoogleSearchHostPolicyRules,
  parseGoogleSupportedDomains,
  renderGoogleSearchHostChunksArkTs
} = require('./lib/google-search-ua-domain-catalog');

const REPO_ROOT = path.resolve(__dirname, '..');
const SOURCE_PATH = path.join(REPO_ROOT, 'resources/policies/google-search-supported-domains.txt');
const ARKTS_OUTPUT_PATH = path.join(
  REPO_ROOT,
  'AiraBrowser/entry/src/main/ets/services/web/GeneratedGoogleSearchCompatibilityHosts.ets'
);
const VERIFIED_AT = '2026-08-29';

function main() {
  const checkOnly = process.argv.slice(2).includes('--check');
  const domains = parseGoogleSupportedDomains(fs.readFileSync(SOURCE_PATH, 'utf8'));
  assertGoogleSupportedDomainCatalogScale(domains);
  const generatedRules = buildGoogleSearchHostPolicyRules(domains, VERIFIED_AT);
  const outputs = [
    {
      path: ARKTS_OUTPUT_PATH,
      content: renderGoogleSearchHostChunksArkTs(domains)
    }
  ];
  const changedPaths = outputs
    .filter((output) => readExisting(output.path) !== output.content)
    .map((output) => path.relative(REPO_ROOT, output.path));
  if (checkOnly) {
    if (changedPaths.length > 0) {
      throw new Error(`Google Search UA catalog is stale: ${changedPaths.join(', ')}`);
    }
    console.log(`Checked ${domains.length} Google Search domains across ${generatedRules.length} rules.`);
    return;
  }
  outputs.forEach((output) => {
    fs.mkdirSync(path.dirname(output.path), { recursive: true });
    fs.writeFileSync(output.path, output.content, 'utf8');
  });
  console.log(`Generated ${domains.length} Google Search domains across ${generatedRules.length} rules.`);
}

function readExisting(filePath) {
  try {
    return fs.readFileSync(filePath, 'utf8');
  } catch (error) {
    if (error?.code === 'ENOENT') {
      return '';
    }
    throw error;
  }
}

main();
