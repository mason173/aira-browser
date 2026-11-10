'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('./lib/deveco-typescript.cjs');

const MIN_SUPPORTED_API_VERSION = 26;

function parseApiVersion(value) {
  const text = String(value ?? '').trim();
  const match = text.match(/\((\d+)\)$/) || text.match(/^(\d+)(?:\.\d+){0,2}$/);
  return match ? Number(match[1]) : NaN;
}

function checkAiraApiBaseline(profilePath = path.resolve(__dirname, '../AiraBrowser/build-profile.json5')) {
  const result = ts.parseConfigFileTextToJson(profilePath, fs.readFileSync(profilePath, 'utf8'));
  assert(!result.error, 'Cannot parse the Aira build profile');
  const products = result.config?.app?.products;
  assert(Array.isArray(products) && products.length > 0, 'Aira build profile must declare products');
  for (const product of products) {
    const compatible = parseApiVersion(product.compatibleSdkVersion);
    const target = parseApiVersion(product.targetSdkVersion);
    assert(compatible >= MIN_SUPPORTED_API_VERSION,
      `${product.name}: compatibleSdkVersion must be API 26 or newer; membership activation requires API 26`);
    assert(target >= compatible,
      `${product.name}: targetSdkVersion must be at least compatibleSdkVersion (API 26 or newer)`);
  }
}

if (require.main === module) {
  checkAiraApiBaseline(process.argv[2]);
  if (process.argv[3]) {
    const sdk = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
    assert(Number(sdk.data?.apiVersion) >= MIN_SUPPORTED_API_VERSION,
      'The installed HarmonyOS SDK must be API 26 or newer');
  }
  console.log('PASS Aira API baseline: minimum and target API 26 or newer.');
}

module.exports = { checkAiraApiBaseline };
