#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const args = process.argv.slice(2);
const check = args[0] === '--check';
const targets = args.slice(check ? 1 : 0).map(dir => path.resolve(dir));
if (targets.length === 0) {
  console.error('Usage: node scripts/sync-app-recommendations.cjs [--check] <HarmonyOS entry module> [...]');
  process.exit(1);
}

const sourceProject = path.resolve(__dirname, '../AiraBrowser');
const sourceMain = path.join(sourceProject, 'entry/src/main');
const sourceResources = path.join(sourceMain, 'resources');
const templates = path.join(__dirname, 'app-recommendations');
const banner = '// Synced from Aira with scripts/sync-app-recommendations.cjs.\n';
const files = new Map();
const componentDir = 'ets/components/apprecommendations';

const catalogSource = fs.readFileSync(path.join(
  sourceMain, 'ets/app/components/onboarding/AppRecommendationContent.ets'), 'utf8');
const colors = catalogSource.replaceAll('app.color.app_recommendation_feature_', 'app.color.sidebar_icon_');
const catalog = colors.replace(/app\.media\.(\w+)/g, (_, name) =>
  `app.media.${name.startsWith('app_recommendation_') ? name : `app_recommendation_${name}`}`);
const component = fs.readFileSync(path.join(templates, 'RecommendationContent.ets'), 'utf8');
files.set(`${componentDir}/RecommendationCatalog.ets`, banner + catalog);
files.set(`${componentDir}/RecommendationContent.ets`, banner + component);
files.set(`${componentDir}/RecommendationStore.ets`,
  banner + fs.readFileSync(path.join(templates, 'RecommendationStore.ets'), 'utf8'));

const mediaSources = [
  path.join(sourceResources, 'base/media'),
  path.join(sourceProject, 'design/src/main/resources/base/media'),
];
const names = new Set([...colors.matchAll(/app\.media\.(\w+)/g)].map(match => match[1]));
for (const name of names) {
  const media = mediaSources.flatMap(directory =>
    fs.readdirSync(directory).filter(file => path.parse(file).name === name).map(file => path.join(directory, file)))[0];
  if (media === undefined) {
    throw new Error(`Missing recommendation artwork: ${name}`);
  }
  const filename = path.basename(media);
  const packaged = name.startsWith('app_recommendation_') ? filename : `app_recommendation_${filename}`;
  files.set(`resources/base/media/${packaged}`, fs.readFileSync(media));
}

const localMarketErrors = {
  base: '暂时无法打开应用市场',
  zh_CN: '暂时无法打开应用市场',
  zh_Hant: '暫時無法開啟應用程式市場',
  en_US: 'Could not open AppGallery',
};
const usedStrings = new Set([...(catalog + component).matchAll(/app\.string\.(\w+)/g)].map(match => match[1]));
for (const [locale, marketError] of Object.entries(localMarketErrors)) {
  const elements = path.join(sourceResources, locale, 'element/string.json');
  const strings = JSON.parse(fs.readFileSync(elements, 'utf8')).string.filter(item => usedStrings.has(item.name));
  strings.push({ name: 'app_recommendation_market_error', value: marketError });
  if (strings.length !== usedStrings.size || new Set(strings.map(item => item.name)).size !== usedStrings.size) {
    throw new Error(`Missing or duplicate recommendation strings in ${locale}`);
  }
  files.set(`resources/${locale}/element/app_recommendation_strings.json`,
    JSON.stringify({ string: strings }, null, 2) + '\n');
}
files.set('resources/base/element/app_recommendation_float.json', JSON.stringify({
  float: [{ name: 'app_recommendation_review_card_width', value: '248vp' }],
}, null, 2) + '\n');

let needsSync = false;
for (const target of targets) {
  const main = path.join(target, 'src/main');
  if (!fs.existsSync(path.join(main, 'module.json5'))) {
    throw new Error(`Expected a HarmonyOS entry module: ${target}`);
  }
  for (const [relative, content] of files) {
    const dest = path.join(main, relative);
    const bytes = Buffer.isBuffer(content) ? content : Buffer.from(content);
    if (fs.existsSync(dest) && fs.readFileSync(dest).equals(bytes)) {
      continue;
    }
    if (check) {
      needsSync = true;
      console.error(`Out of date: ${dest}`);
      continue;
    }
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, bytes);
  }
  if (!check) {
    console.log(`Synced recommendations to ${target}`);
  }
}
process.exitCode = needsSync ? 1 : 0;
