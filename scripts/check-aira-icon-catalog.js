#!/usr/bin/env node

const path = require('path');
const {
  compileAiraIconCatalog,
  synchronizeAiraIconCatalogArtifacts
} = require('./lib/aira-icon-catalog');

const repoRoot = path.resolve(__dirname, '..');
const catalog = compileAiraIconCatalog({ repoRoot });
const artifacts = synchronizeAiraIconCatalogArtifacts(catalog, { check: true });

if (artifacts.changed > 0) {
  console.error('Canonical Aira Icon Catalog derived artifacts are out of date.');
  artifacts.changedFiles.forEach((fileName) => console.error(`- ${fileName}`));
  console.error('Run: node scripts/generate-aira-icons-from-source.js');
  process.exit(1);
}

console.log(
  `Checked Canonical Aira Icon Catalog: ${catalog.icons.length} Operational Icons, ` +
  `${catalog.sources.length} sources, ${catalog.groups.length} Operational groups; ` +
  `${catalog.imageManifest.assets.length} image-owned assets, ` +
  `${catalog.imageManifest.packagedSvgExceptionPaths.size} classified packaged SVG exceptions, ` +
  `${catalog.legacyOutputProjection.iconByResourcePath.size} deterministic legacy SVG outputs, ` +
  `${artifacts.checked} derived artifacts.`
);
