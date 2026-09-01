const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const CATALOG_SCHEMA_VERSION = 1;
const CATALOG_AUTHORITY = 'canonical-aira-icon-catalog';
const IMAGE_MANIFEST_AUTHORITY = 'aira-image-asset-manifest';
const FONT_SOURCE_MANIFEST_AUTHORITY = 'aira-lucide-operational-source-pack';
const SEMANTIC_ICON_ID_PATTERN = /^[a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*)+$/;
const SOURCE_ID_PATTERN = /^source\.[a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*)+$/;
const ALLOWED_REPRESENTATION_KINDS = new Set(['legacy-svg', 'font']);
const ALLOWED_IMAGE_ASSET_KINDS = new Set(['themed-svg', 'themed-raster', 'raster-copy']);
const ALLOWED_LEGACY_VARIANTS = new Set(['chrome']);

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function sha256File(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
}

function requireCondition(condition, message) {
  if (!condition) {
    throw new Error(`Aira icon catalog: ${message}`);
  }
}

function requireString(value, label) {
  requireCondition(typeof value === 'string' && value.length > 0, `${label} must be a non-empty string.`);
}

function requireArray(value, label) {
  requireCondition(Array.isArray(value), `${label} must be an array.`);
}

function requireUnique(values, label) {
  const seen = new Set();
  values.forEach((value) => {
    requireCondition(!seen.has(value), `Duplicate ${label}: ${value}`);
    seen.add(value);
  });
}

function csvValue(value) {
  const text = String(value ?? '');
  if (!/[",\n]/.test(text)) {
    return text;
  }
  return `"${text.replace(/"/g, '""')}"`;
}

function arkTSStringLiteral(value) {
  return JSON.stringify(value);
}

function arkTSGlyphLiteral(codePoint) {
  requireCondition(codePoint >= 0 && codePoint <= 0xFFFF,
    `Generated ArkTS glyph code point is outside the BMP: ${codePoint}`);
  return `'\\u${codePoint.toString(16).toUpperCase().padStart(4, '0')}'`;
}

function canonicalLegacyResourceName(fileName) {
  const name = fileName.replace(/\.svg$/, '');

  if (name.endsWith('_chrome_light') || name.endsWith('_chrome_dark')) {
    return name.replace(/_chrome_(light|dark)$/, '');
  }
  if (name === 'app_toolbar_tabs_white' ||
    name === 'app_tabs_add_white' ||
    name === 'app_tabs_delete_white' ||
    name === 'app_tabs_privacy_mode_white') {
    return name.replace(/_white$/, '');
  }
  if (name.startsWith('app_membership_benefit_')) {
    return name.replace(/_(dark|ivory|white)$/, '');
  }
  if (name.startsWith('app_membership_restore_purchase_')) {
    return 'app_membership_restore_purchase';
  }
  if (name === 'app_membership_gift_ivory' || name === 'app_membership_gift_white') {
    return 'app_membership_gift';
  }
  if (name === 'app_membership_invite_record_clock_white') {
    return 'app_membership_invite_record_clock';
  }

  return name;
}

function resolveCatalogSourcePath(catalogRoot, sourceRoot, source) {
  const canonicalPath = path.join(catalogRoot, source.exportedFile);
  const directOverridePath = path.join(sourceRoot, source.exportedFile);
  const directBasenameOverridePath = path.join(sourceRoot, path.basename(source.exportedFile));
  if (path.resolve(sourceRoot) === path.resolve(catalogRoot) && fs.existsSync(canonicalPath)) {
    return canonicalPath;
  }
  if (fs.existsSync(directOverridePath)) {
    return directOverridePath;
  }
  if (fs.existsSync(directBasenameOverridePath)) {
    return directBasenameOverridePath;
  }

  return canonicalPath;
}

function validateOperationalFont(catalogRoot, font) {
  requireCondition(font && typeof font === 'object', 'font metadata is required.');
  requireString(font.familyName, 'font.familyName');
  requireString(font.fontFile, 'font.fontFile');
  requireString(font.packagedRawfile, 'font.packagedRawfile');
  requireString(font.fontSha256, 'font.fontSha256');
  requireString(font.selectionFile, 'font.selectionFile');
  requireString(font.selectionSha256, 'font.selectionSha256');
  requireString(font.sourceManifestFile, 'font.sourceManifestFile');
  requireString(font.sourceManifestSha256, 'font.sourceManifestSha256');
  requireCondition(
    font.packagedRawfile.startsWith('fonts/aira/') &&
      font.packagedRawfile.endsWith('.ttf') &&
      !font.packagedRawfile.includes('..'),
    `Operational font packagedRawfile must stay inside rawfile/fonts/aira: ${font.packagedRawfile}`
  );

  const fontPath = path.join(catalogRoot, font.fontFile);
  const selectionPath = path.join(catalogRoot, font.selectionFile);
  const sourceManifestPath = path.join(catalogRoot, font.sourceManifestFile);
  requireCondition(fs.existsSync(fontPath), `Missing Operational font: ${font.fontFile}`);
  requireCondition(fs.existsSync(selectionPath), `Missing Operational font selection: ${font.selectionFile}`);
  requireCondition(fs.existsSync(sourceManifestPath),
    `Missing Operational font source manifest: ${font.sourceManifestFile}`);
  requireCondition(sha256File(fontPath) === font.fontSha256,
    `Operational font checksum mismatch: ${font.fontFile}`);
  requireCondition(sha256File(selectionPath) === font.selectionSha256,
    `Operational font selection checksum mismatch: ${font.selectionFile}`);
  requireCondition(sha256File(sourceManifestPath) === font.sourceManifestSha256,
    `Operational font source manifest checksum mismatch: ${font.sourceManifestFile}`);

  const selection = readJson(selectionPath);
  const declaredFamily = selection.preferences?.fontPref?.metadata?.fontFamily;
  requireCondition(declaredFamily === font.familyName,
    `Operational font family mismatch: expected ${font.familyName}, received ${declaredFamily ?? 'missing'}`);
  requireArray(selection.icons, 'Operational font selection icons');
  const glyphs = new Map();
  const selectionCodes = [];
  selection.icons.forEach((icon, index) => {
    const glyphName = icon?.properties?.name;
    const glyphCode = icon?.properties?.code;
    requireString(glyphName, `Operational font glyph ${index} name`);
    requireCondition(Number.isInteger(glyphCode),
      `Operational font glyph ${glyphName} code must be an integer.`);
    requireCondition(glyphCode >= 0 && glyphCode <= 0xFFFF,
      `Operational font glyph ${glyphName} must use a BMP codepoint.`);
    requireCondition(!glyphs.has(glyphName), `Duplicate Operational font glyph: ${glyphName}`);
    glyphs.set(glyphName, glyphCode);
    selectionCodes.push(glyphCode);
  });
  requireUnique(selectionCodes, 'Operational font codepoint');

  const sourceManifest = readJson(sourceManifestPath);
  requireCondition(sourceManifest.schemaVersion === CATALOG_SCHEMA_VERSION,
    `Unsupported Operational font source manifest schemaVersion: ${font.sourceManifestFile}`);
  requireCondition(sourceManifest.authority === FONT_SOURCE_MANIFEST_AUTHORITY,
    `Invalid Operational font source manifest authority: ${sourceManifest.authority}`);
  requireArray(sourceManifest.glyphs, 'Operational font source glyphs');
  requireUnique(sourceManifest.glyphs.map((entry) => entry.glyph), 'Operational font source glyph');
  requireUnique(sourceManifest.glyphs.map((entry) => entry.codePoint), 'Operational font source codepoint');
  requireUnique(sourceManifest.glyphs.map((entry) => entry.sourceFile), 'Operational font source file');
  const sourcePathByGlyph = new Map();
  const manifestGlyphs = new Map();
  sourceManifest.glyphs.forEach((entry, index) => {
    requireString(entry.glyph, `Operational font source glyph ${index}`);
    requireCondition(Number.isInteger(entry.codePoint) && entry.codePoint >= 0 && entry.codePoint <= 0xFFFF,
      `Operational font source ${entry.glyph} has an invalid BMP codepoint.`);
    requireString(entry.lucideSlug, `Operational font Lucide slug ${index}`);
    requireString(entry.sourceFile, `Operational font source file ${index}`);
    requireString(entry.sourceSha256, `Operational font source checksum ${index}`);
    requireCondition(entry.sourceFile.startsWith('svg/') && !entry.sourceFile.includes('..'),
      `Operational font source must stay inside its vendor SVG directory: ${entry.sourceFile}`);
    const sourcePath = path.join(path.dirname(sourceManifestPath), entry.sourceFile);
    requireCondition(fs.existsSync(sourcePath), `Missing Operational font SVG source: ${entry.sourceFile}`);
    requireCondition(sha256File(sourcePath) === entry.sourceSha256,
      `Operational font SVG checksum mismatch: ${entry.sourceFile}`);
    sourcePathByGlyph.set(entry.glyph, sourcePath);
    manifestGlyphs.set(entry.glyph, entry.codePoint);
  });
  requireCondition(JSON.stringify([...manifestGlyphs.keys()].sort()) === JSON.stringify([...glyphs.keys()].sort()),
    'Operational font source manifest and selection glyphs differ.');
  manifestGlyphs.forEach((codePoint, glyphName) => {
    requireCondition(glyphs.get(glyphName) === codePoint,
      `Operational font codepoint mismatch for ${glyphName}.`);
  });

  return { glyphs, sourceManifest, sourcePathByGlyph };
}

function compileImageAssetManifest(repoRoot, catalogRoot, sourceRoot, operationalGroupIds) {
  const manifestPath = path.join(catalogRoot, 'image-assets.json');
  requireCondition(fs.existsSync(manifestPath), 'Missing image-owned asset manifest: image-assets.json');
  const raw = readJson(manifestPath);
  requireCondition(raw.schemaVersion === CATALOG_SCHEMA_VERSION, 'Unsupported image asset manifest schemaVersion.');
  requireCondition(raw.authority === IMAGE_MANIFEST_AUTHORITY, `Invalid image asset authority: ${raw.authority}`);
  requireArray(raw.assets, 'imageAssets.assets');
  requireArray(raw.groups, 'imageAssets.groups');
  requireArray(raw.packagedSvgExceptionGroups, 'imageAssets.packagedSvgExceptionGroups');
  requireUnique(raw.assets.map((asset) => asset.id), 'image asset id');
  requireUnique(raw.assets.map((asset) => asset.exportedFile), 'image asset source file');
  requireUnique(raw.assets.map((asset) => asset.resourceFile), 'image asset resource file');
  requireUnique(raw.assets.map((asset) => asset.resourceFamily), 'image asset resource family');
  requireUnique(raw.groups.map((group) => group.id), 'image asset group id');
  requireUnique(raw.packagedSvgExceptionGroups.map((group) => group.owner), 'packaged SVG exception owner');

  const assetByResourceFamily = new Map();
  const resolvedSourcePathById = new Map();
  const themedSourcePathByResourcePath = new Map();
  const themedRasterSourcePathByResourcePath = new Map();
  raw.assets.forEach((asset, index) => {
    requireString(asset.id, `imageAssets.assets[${index}].id`);
    requireCondition(ALLOWED_IMAGE_ASSET_KINDS.has(asset.kind), `Unsupported image asset kind: ${asset.kind}`);
    requireString(asset.exportedFile, `imageAssets.assets[${index}].exportedFile`);
    requireString(asset.originalSource, `imageAssets.assets[${index}].originalSource`);
    requireString(asset.resourceFile, `imageAssets.assets[${index}].resourceFile`);
    requireString(asset.resourceFamily, `imageAssets.assets[${index}].resourceFamily`);
    requireString(asset.note, `imageAssets.assets[${index}].note`);
    requireCondition(
      asset.resourceFamily.startsWith('app_') ||
        asset.resourceFamily === 'aira_logo_brand' ||
        asset.resourceFamily === 'start_window_brand_lockup',
      `Invalid image asset resource family: ${asset.resourceFamily}`);
    if (asset.kind === 'themed-svg') {
      requireCondition(asset.exportedFile.endsWith('.svg'), `Themed image source must be SVG: ${asset.exportedFile}`);
      requireCondition(asset.resourceFile.endsWith('.svg'), `Themed image resource must be SVG: ${asset.resourceFile}`);
      requireArray(asset.resourcePaths, `imageAssets.assets[${index}].resourcePaths`);
      requireCondition(asset.resourcePaths.length > 0, `Themed image asset must declare resourcePaths: ${asset.id}`);
    } else if (asset.kind === 'themed-raster') {
      requireCondition(asset.exportedFile.endsWith('.png'), `Themed raster source must be PNG: ${asset.exportedFile}`);
      requireCondition(asset.resourceFile.endsWith('.png'), `Themed raster resource must be PNG: ${asset.resourceFile}`);
      requireArray(asset.resourcePaths, `imageAssets.assets[${index}].resourcePaths`);
      requireCondition(asset.resourcePaths.length > 0, `Themed raster asset must declare resourcePaths: ${asset.id}`);
    } else {
      requireCondition(asset.exportedFile.endsWith('.png'), `Raster image source must be PNG: ${asset.exportedFile}`);
      requireCondition(asset.resourceFile.endsWith('.png'), `Raster image resource must be PNG: ${asset.resourceFile}`);
      requireCondition(asset.resourcePaths === undefined, `Raster image asset must not declare resourcePaths: ${asset.id}`);
    }
    const resolvedPath = resolveCatalogSourcePath(catalogRoot, sourceRoot, asset);
    requireCondition(fs.existsSync(resolvedPath), `Missing image-owned source: ${asset.exportedFile}`);
    assetByResourceFamily.set(asset.resourceFamily, asset);
    resolvedSourcePathById.set(asset.id, resolvedPath);
    if (asset.kind === 'themed-svg' || asset.kind === 'themed-raster') {
      const outputMap = asset.kind === 'themed-svg' ?
        themedSourcePathByResourcePath : themedRasterSourcePathByResourcePath;
      asset.resourcePaths.forEach((resourcePath) => {
        requireString(resourcePath, `Themed image resource path for ${asset.id}`);
        requireCondition(
          (resourcePath.startsWith('base/media/') || resourcePath.startsWith('dark/media/')) && !resourcePath.includes('..'),
          `Themed image resource must stay inside base/media or dark/media: ${resourcePath}`
        );
        requireCondition(path.basename(resourcePath) === asset.resourceFile,
          `Themed image resource path must end with ${asset.resourceFile}: ${resourcePath}`);
        requireCondition(!outputMap.has(resourcePath),
          `Duplicate themed image resource path: ${resourcePath}`);
        outputMap.set(resourcePath, resolvedPath);
      });
    }
  });

  raw.groups.forEach((group, groupIndex) => {
    requireString(group.id, `imageAssets.groups[${groupIndex}].id`);
    requireCondition(!operationalGroupIds.has(group.id), `Image asset group overlaps an Operational group: ${group.id}`);
    requireString(group.afterGroupId, `imageAssets.groups[${groupIndex}].afterGroupId`);
    requireCondition(operationalGroupIds.has(group.afterGroupId),
      `Image asset group ${group.id} has unknown afterGroupId ${group.afterGroupId}`);
    requireString(group.title, `imageAssets.groups[${groupIndex}].title`);
    requireArray(group.entries, `imageAssets.groups[${groupIndex}].entries`);
    requireCondition(group.entries.length > 0, `Image asset group ${group.id} must not be empty.`);
    requireUnique(group.entries.map((entry) => entry.resourceFamily), `${group.id} resourceFamily`);
    group.entries.forEach((entry, entryIndex) => {
      requireString(entry.resourceFamily, `imageAssets.groups[${groupIndex}].entries[${entryIndex}].resourceFamily`);
      requireCondition(assetByResourceFamily.has(entry.resourceFamily),
        `Image asset group ${group.id} references unknown resourceFamily ${entry.resourceFamily}`);
    });
  });

  const packagedSvgExceptionPaths = new Set();
  raw.packagedSvgExceptionGroups.forEach((group, groupIndex) => {
    requireString(group.owner, `imageAssets.packagedSvgExceptionGroups[${groupIndex}].owner`);
    requireString(group.reason, `imageAssets.packagedSvgExceptionGroups[${groupIndex}].reason`);
    requireArray(group.resourcePaths, `imageAssets.packagedSvgExceptionGroups[${groupIndex}].resourcePaths`);
    requireCondition(group.resourcePaths.length > 0, `Packaged SVG exception group ${group.owner} must not be empty.`);
    group.resourcePaths.forEach((resourcePath, resourceIndex) => {
      requireString(resourcePath,
        `imageAssets.packagedSvgExceptionGroups[${groupIndex}].resourcePaths[${resourceIndex}]`);
      requireCondition(resourcePath.endsWith('.svg'), `Packaged image exception must be SVG: ${resourcePath}`);
      requireCondition(
        (resourcePath.startsWith('base/media/') || resourcePath.startsWith('dark/media/')) && !resourcePath.includes('..'),
        `Packaged SVG exception must stay inside base/media or dark/media: ${resourcePath}`
      );
      requireCondition(!packagedSvgExceptionPaths.has(resourcePath), `Duplicate packaged SVG exception: ${resourcePath}`);
      const absolutePath = path.join(repoRoot, 'AiraBrowser/entry/src/main/resources', resourcePath);
      requireCondition(fs.existsSync(absolutePath), `Missing packaged SVG exception resource: ${resourcePath}`);
      packagedSvgExceptionPaths.add(resourcePath);
    });
  });

  return {
    assets: raw.assets,
    groups: raw.groups,
    assetByResourceFamily,
    resolvedSourcePathById,
    themedSourcePathByResourcePath,
    themedRasterSourcePathByResourcePath,
    packagedSvgExceptionPaths
  };
}

function validateCanonicalSourceCoverage(catalogRoot, sources) {
  const iconsDir = path.join(catalogRoot, 'icons');
  const catalogFiles = new Set(sources.map((source) => source.exportedFile));
  const missingFromCatalog = fs.readdirSync(iconsDir)
    .filter((fileName) => fileName.endsWith('.svg'))
    .filter((fileName) => !fileName.startsWith('aira_logo_brand__'))
    .filter((fileName) => !fileName.startsWith('unmapped__'))
    .map((fileName) => `icons/${fileName}`)
    .filter((fileName) => !catalogFiles.has(fileName));
  requireCondition(
    missingFromCatalog.length === 0,
    `Canonical Operational Icon sources missing from catalog: ${missingFromCatalog.join(', ')}`
  );
}

function deriveOperationalIconMap(font, fontValidation, sources, icons) {
  const iconsByPrimarySource = new Map();
  icons.filter((icon) => icon.representation.kind === 'legacy-svg').forEach((icon) => {
    const current = iconsByPrimarySource.get(icon.sourceId) ?? [];
    current.push(icon);
    iconsByPrimarySource.set(icon.sourceId, current);
  });

  const legacyEntries = sources
    .filter((source) => iconsByPrimarySource.has(source.id))
    .map((source) => {
      const sourceIcons = iconsByPrimarySource.get(source.id);
      const resourceFamilies = sourceIcons.map((icon) => icon.legacyResourceFamily);
      const entry = {
        exportedFile: source.exportedFile,
        originalSource: source.originalSource,
        primaryResourceFamily: resourceFamilies[0],
        resourceFamilies
      };
      if (source.note) {
        entry.note = source.note;
      } else if (resourceFamilies.length > 1) {
        entry.note = 'one source generates multiple app resource families';
      }
      return entry;
    });

  const fontIconsByGlyph = new Map();
  icons.filter((icon) => icon.representation.kind === 'font').forEach((icon) => {
    const current = fontIconsByGlyph.get(icon.representation.glyph) ?? [];
    current.push(icon);
    fontIconsByGlyph.set(icon.representation.glyph, current);
  });
  const sourceManifestDir = path.dirname(font.sourceManifestFile);
  const fontEntries = fontValidation.sourceManifest.glyphs
    .filter((entry) => fontIconsByGlyph.has(entry.glyph))
    .map((entry) => {
      const sourceIcons = fontIconsByGlyph.get(entry.glyph);
      const resourceFamilies = sourceIcons.map((icon) => icon.legacyResourceFamily);
      return {
        exportedFile: path.join(sourceManifestDir, entry.sourceFile),
        originalSource: `Lucide 1.38.0 / ${entry.lucideSlug}`,
        primaryResourceFamily: resourceFamilies[0],
        resourceFamilies,
        note: resourceFamilies.length > 1 ? 'one font glyph serves multiple app resource families' :
          'Lucide Operational font source'
      };
    });

  return [...fontEntries, ...legacyEntries];
}

function deriveImageLegacyIconMap(imageAssets) {
  return imageAssets.map((asset) => ({
    exportedFile: asset.exportedFile,
    originalSource: asset.originalSource,
    primaryResourceFamily: asset.resourceFamily,
    resourceFamilies: [asset.resourceFamily],
    note: asset.note
  }));
}

function deriveLegacyIconMapCsv(iconMap) {
  const headers = [
    'exportedFile',
    'originalSource',
    'primaryResourceFamily',
    'resourceFamilies',
    'note'
  ];
  return [headers.join(',')]
    .concat(iconMap.map((entry) => [
      entry.exportedFile,
      entry.originalSource,
      entry.primaryResourceFamily,
      entry.resourceFamilies.join(';'),
      entry.note ?? ''
    ].map(csvValue).join(',')))
    .join('\n') + '\n';
}

function deriveLegacyIconGroups(rawGroups, iconById, imageGroups) {
  const groupsAfter = new Map();
  imageGroups.forEach((group) => {
    const current = groupsAfter.get(group.afterGroupId) ?? [];
    const derived = { ...group };
    delete derived.afterGroupId;
    current.push(derived);
    groupsAfter.set(group.afterGroupId, current);
  });

  const groups = [];
  rawGroups.forEach((group) => {
    const derived = { ...group };
    derived.entries = group.entries.map((entry) => {
      const icon = iconById.get(entry.iconId);
      const result = { ...entry, resourceFamily: icon.legacyResourceFamily };
      delete result.iconId;
      return result;
    });
    groups.push(derived, ...(groupsAfter.get(group.id) ?? []));
  });
  return { schemaVersion: CATALOG_SCHEMA_VERSION, groups };
}

function deriveGeneratedAiraIconCatalog(font, icons, glyphs, legacyOutputProjection) {
  const fontIcons = icons.filter((icon) => icon.representation.kind === 'font');
  const legacyIcons = icons.filter((icon) =>
    icon.representation.kind === 'legacy-svg' &&
      legacyOutputProjection.iconByResourcePath.has(`base/media/${icon.legacyResourceFamily}.svg`)
  );
  const idType = icons
    .map((icon) => `  | ${arkTSStringLiteral(icon.id)}`)
    .join('\n');
  const renderableIconIds = new Set(
    fontIcons.concat(legacyIcons).map((icon) => icon.id)
  );
  const renderableIdType = icons
    .filter((icon) => renderableIconIds.has(icon.id))
    .map((icon) => `  | ${arkTSStringLiteral(icon.id)}`)
    .join('\n');
  const fontCases = fontIcons
    .map((icon) => `      case ${arkTSStringLiteral(icon.id)}:`)
    .join('\n');
  const glyphCases = fontIcons.map((icon) => {
    const codePoint = glyphs.get(icon.representation.glyph);
    return [
      `      case ${arkTSStringLiteral(icon.id)}:`,
      `        return ${arkTSGlyphLiteral(codePoint)};`
    ].join('\n');
  }).join('\n');
  const legacyCases = legacyIcons.map((icon) => [
    `      case ${arkTSStringLiteral(icon.id)}:`,
    `        return $r(${arkTSStringLiteral(`app.media.${icon.legacyResourceFamily}`)});`
  ].join('\n')).join('\n');
  const legacyPresenceCases = legacyIcons
    .map((icon) => `      case ${arkTSStringLiteral(icon.id)}:`)
    .join('\n');

  return [
    '// Generated by scripts/generate-aira-icons-from-source.js. Do not edit by hand.',
    '',
    'export type AiraIconId =',
    `${idType};`,
    '',
    'export type AiraRenderableIconId =',
    `${renderableIdType};`,
    '',
    `export const AIRA_ICON_FONT_FAMILY: string = ${arkTSStringLiteral(font.familyName)};`,
    `export const AIRA_ICON_FONT_RAWFILE_PATH: string = ${arkTSStringLiteral(font.packagedRawfile)};`,
    '',
    'export function airaIconFontResource(): Resource {',
    `  return $rawfile(${arkTSStringLiteral(font.packagedRawfile)});`,
    '}',
    '',
    'export class GeneratedAiraIconCatalog {',
    '  static isFontBacked(iconId: AiraRenderableIconId): boolean {',
    '    switch (iconId) {',
    fontCases,
    '        return true;',
    '      default:',
    '        return false;',
    '    }',
    '  }',
    '',
    '  static resolveFontGlyph(iconId: AiraRenderableIconId): string {',
    '    switch (iconId) {',
    glyphCases,
    '      default:',
    "        return '';",
    '    }',
    '  }',
    '',
    '  static hasLegacyResource(iconId: AiraRenderableIconId): boolean {',
    '    switch (iconId) {',
    legacyPresenceCases,
    '        return true;',
    '      default:',
    '        return false;',
    '    }',
    '  }',
    '',
    '  static resolveLegacyResource(iconId: AiraRenderableIconId): Resource | undefined {',
    '    switch (iconId) {',
    legacyCases,
    '      default:',
    '        return undefined;',
    '    }',
    '  }',
    '}',
    ''
  ].join('\n');
}

function compileLegacyOutputProjection(rawProfiles, iconById, legacyCompatibilityIconIds) {
  requireArray(rawProfiles, 'legacyOutputProfiles');
  requireCondition(rawProfiles.length > 0, 'legacyOutputProfiles must not be empty.');
  requireUnique(rawProfiles.map((profile) => profile.id), 'legacy output profile id');
  const profileByIconId = new Map();
  const iconByResourcePath = new Map();

  rawProfiles.forEach((profile, profileIndex) => {
    requireString(profile.id, `legacyOutputProfiles[${profileIndex}].id`);
    requireArray(profile.pathTemplates, `legacyOutputProfiles[${profileIndex}].pathTemplates`);
    requireArray(profile.iconIds, `legacyOutputProfiles[${profileIndex}].iconIds`);
    requireCondition(profile.pathTemplates.length > 0, `Legacy output profile ${profile.id} has no path templates.`);
    requireCondition(profile.iconIds.length > 0, `Legacy output profile ${profile.id} has no icon IDs.`);
    requireUnique(profile.pathTemplates, `${profile.id} path template`);
    requireUnique(profile.iconIds, `${profile.id} icon id`);

    profile.pathTemplates.forEach((template) => {
      requireString(template, `Legacy output path template for ${profile.id}`);
      requireCondition(template.includes('{family}'),
        `Legacy output path template must include {family}: ${template}`);
      requireCondition(
        (template.startsWith('base/media/') || template.startsWith('dark/media/')) &&
          template.endsWith('.svg') && !template.includes('..'),
        `Legacy output path template must stay inside base/media or dark/media: ${template}`
      );
    });

    profile.iconIds.forEach((iconId) => {
      requireCondition(iconById.has(iconId), `Legacy output profile ${profile.id} references unknown icon ${iconId}`);
      requireCondition(!profileByIconId.has(iconId), `Operational Icon has multiple legacy output profiles: ${iconId}`);
      const icon = iconById.get(iconId);
      requireCondition(
        icon.representation.kind === 'legacy-svg' || legacyCompatibilityIconIds.has(iconId),
        `Only legacy-svg or declared compatibility icons may retain legacy outputs: ${iconId}`
      );
      profileByIconId.set(iconId, profile.id);
      profile.pathTemplates.forEach((template) => {
        const resourcePath = template.replaceAll('{family}', icon.legacyResourceFamily);
        requireCondition(canonicalLegacyResourceName(path.basename(resourcePath)) === icon.legacyResourceFamily,
          `Legacy output path does not resolve to ${icon.legacyResourceFamily}: ${resourcePath}`);
        requireCondition(!iconByResourcePath.has(resourcePath), `Duplicate legacy output resource path: ${resourcePath}`);
        iconByResourcePath.set(resourcePath, icon);
      });
    });
  });

  iconById.forEach((icon, iconId) => {
    if (icon.representation.kind === 'legacy-svg') {
      requireCondition(profileByIconId.has(iconId), `Legacy SVG icon has no output profile: ${iconId}`);
    } else if (legacyCompatibilityIconIds.has(iconId)) {
      requireCondition(profileByIconId.has(iconId), `Compatibility icon has no legacy output profile: ${iconId}`);
    } else {
      requireCondition(!profileByIconId.has(iconId), `Font icon must not retain legacy outputs: ${iconId}`);
    }
  });

  return { iconByResourcePath };
}

function compileAiraIconCatalog(options = {}) {
  const repoRoot = options.repoRoot ?? path.resolve(__dirname, '../..');
  const catalogRoot = options.catalogRoot ?? path.join(repoRoot, 'resources/icon-sources/aira');
  const sourceRoot = options.sourceRoot ? path.resolve(options.sourceRoot) : catalogRoot;
  const catalogPath = path.join(catalogRoot, 'icon-catalog.json');
  requireCondition(fs.existsSync(catalogPath), `Missing catalog file: ${path.relative(repoRoot, catalogPath)}`);

  const raw = readJson(catalogPath);
  requireCondition(raw.schemaVersion === CATALOG_SCHEMA_VERSION, `Unsupported schemaVersion: ${raw.schemaVersion}`);
  requireCondition(raw.authority === CATALOG_AUTHORITY, `Invalid authority: ${raw.authority}`);
  const fontValidation = validateOperationalFont(catalogRoot, raw.font);

  requireArray(raw.sources, 'sources');
  requireArray(raw.icons, 'icons');
  requireArray(raw.groups, 'groups');
  requireCondition(raw.sources.length > 0, 'sources must not be empty.');
  requireCondition(raw.icons.length > 0, 'icons must not be empty.');
  requireUnique(raw.sources.map((source) => source.id), 'source id');
  requireUnique(raw.sources.map((source) => source.exportedFile), 'source file');
  requireUnique(raw.icons.map((icon) => icon.id), 'semantic icon id');
  requireUnique(raw.icons.map((icon) => icon.legacyResourceFamily), 'legacy resource family');
  requireUnique(raw.groups.map((group) => group.id), 'icon group id');
  const imageManifest = compileImageAssetManifest(
    repoRoot,
    catalogRoot,
    sourceRoot,
    new Set(raw.groups.map((group) => group.id))
  );

  const sourceById = new Map();
  const resolvedSourcePathById = new Map();
  raw.sources.forEach((source, index) => {
    requireString(source.id, `sources[${index}].id`);
    requireCondition(SOURCE_ID_PATTERN.test(source.id), `Invalid source id: ${source.id}`);
    requireString(source.exportedFile, `sources[${index}].exportedFile`);
    requireCondition(source.exportedFile.endsWith('.svg'), `Source must be SVG: ${source.exportedFile}`);
    requireString(source.originalSource, `sources[${index}].originalSource`);
    const resolvedPath = resolveCatalogSourcePath(catalogRoot, sourceRoot, source);
    requireCondition(fs.existsSync(resolvedPath), `Missing canonical source: ${source.exportedFile}`);
    sourceById.set(source.id, source);
    resolvedSourcePathById.set(source.id, resolvedPath);
  });

  if (path.resolve(sourceRoot) === path.resolve(catalogRoot)) {
    validateCanonicalSourceCoverage(catalogRoot, raw.sources);
  }

  const iconById = new Map();
  const iconByLegacyResourceFamily = new Map();
  raw.icons.forEach((icon, index) => {
    requireString(icon.id, `icons[${index}].id`);
    requireCondition(SEMANTIC_ICON_ID_PATTERN.test(icon.id), `Invalid semantic icon id: ${icon.id}`);
    requireString(icon.legacyResourceFamily, `icons[${index}].legacyResourceFamily`);
    requireCondition(icon.legacyResourceFamily.startsWith('app_'), `Invalid legacy resource family: ${icon.legacyResourceFamily}`);
    requireCondition(icon.representation && typeof icon.representation === 'object', `Missing representation for ${icon.id}`);
    requireCondition(
      ALLOWED_REPRESENTATION_KINDS.has(icon.representation.kind),
      `Unsupported representation kind for ${icon.id}: ${icon.representation.kind}`
    );
    requireString(icon.representation.reason, `icons[${index}].representation.reason`);

    if (icon.representation.kind === 'legacy-svg') {
      requireString(icon.sourceId, `Legacy SVG sourceId for ${icon.id}`);
      requireCondition(sourceById.has(icon.sourceId), `Unknown sourceId ${icon.sourceId} for ${icon.id}`);
    } else {
      requireCondition(icon.sourceId === undefined, `Font icon must not retain sourceId: ${icon.id}`);
    }

    if (icon.legacyVariantSources !== undefined) {
      requireCondition(icon.representation.kind === 'legacy-svg',
        `Only legacy-svg icons may declare legacyVariantSources: ${icon.id}`);
      requireCondition(
        icon.legacyVariantSources && typeof icon.legacyVariantSources === 'object' && !Array.isArray(icon.legacyVariantSources),
        `legacyVariantSources must be an object for ${icon.id}`
      );
      requireCondition(Object.keys(icon.legacyVariantSources).length > 0,
        `legacyVariantSources must not be empty for ${icon.id}`);
      Object.entries(icon.legacyVariantSources).forEach(([variant, sourceId]) => {
        requireString(variant, `legacy variant for ${icon.id}`);
        requireCondition(ALLOWED_LEGACY_VARIANTS.has(variant), `Unsupported legacy variant ${variant} for ${icon.id}`);
        requireString(sourceId, `legacy variant source for ${icon.id}`);
        requireCondition(sourceById.has(sourceId), `Unknown variant sourceId ${sourceId} for ${icon.id}`);
      });
    }

    if (icon.representation.kind === 'font') {
      requireString(icon.representation.glyph, `Operational font glyph for ${icon.id}`);
      requireCondition(fontValidation.glyphs.has(icon.representation.glyph),
        `Unknown Operational font glyph for ${icon.id}: ${icon.representation.glyph}`);
      requireCondition(icon.representation.regularGlyph === undefined &&
        icon.representation.selectedGlyph === undefined && icon.representation.style === undefined,
      `Font representation for ${icon.id} must use glyph only.`);
    }

    iconById.set(icon.id, icon);
    iconByLegacyResourceFamily.set(icon.legacyResourceFamily, icon);
  });

  const referencedSourceIds = new Set();
  raw.icons.filter((icon) => icon.representation.kind === 'legacy-svg').forEach((icon) => {
    referencedSourceIds.add(icon.sourceId);
    Object.values(icon.legacyVariantSources ?? {}).forEach((sourceId) => referencedSourceIds.add(sourceId));
  });
  raw.sources.forEach((source) => {
    requireCondition(referencedSourceIds.has(source.id), `Canonical source is not referenced by an icon: ${source.id}`);
  });

  requireArray(raw.font.fontQuarantinedIconIds, 'font.fontQuarantinedIconIds');
  requireArray(raw.font.legacyCompatibilityIconIds, 'font.legacyCompatibilityIconIds');
  requireUnique(raw.font.fontQuarantinedIconIds, 'font-quarantined icon id');
  requireUnique(raw.font.legacyCompatibilityIconIds, 'legacy compatibility icon id');
  const fontQuarantinedIconIds = new Set(raw.font.fontQuarantinedIconIds);
  const legacyCompatibilityIconIds = new Set(raw.font.legacyCompatibilityIconIds);
  fontQuarantinedIconIds.forEach((iconId) => {
    requireCondition(iconById.has(iconId), `Unknown font-quarantined icon id: ${iconId}`);
    requireCondition(iconById.get(iconId).representation.kind === 'legacy-svg',
      `Font-quarantined icon must retain legacy-svg representation: ${iconId}`);
  });
  legacyCompatibilityIconIds.forEach((iconId) => {
    requireCondition(iconById.has(iconId), `Unknown legacy compatibility icon id: ${iconId}`);
    requireCondition(!fontQuarantinedIconIds.has(iconId),
      `Font-quarantined icon cannot be a legacy compatibility icon: ${iconId}`);
    requireCondition(iconById.get(iconId).representation.kind === 'font',
      `Legacy compatibility icon must use the Operational font: ${iconId}`);
  });
  iconById.forEach((_icon, iconId) => {
    if (iconId.startsWith('desktopCard.')) {
      requireCondition(fontQuarantinedIconIds.has(iconId),
        `Desktop-card Operational Icon must be font-quarantined: ${iconId}`);
    }
  });
  const referencedGlyphs = new Set(
    raw.icons.filter((icon) => icon.representation.kind === 'font')
      .map((icon) => icon.representation.glyph)
  );
  requireCondition(
    JSON.stringify([...referencedGlyphs].sort()) === JSON.stringify([...fontValidation.glyphs.keys()].sort()),
    'Operational font contains glyphs that are not referenced by the Canonical Icon Catalog.'
  );

  imageManifest.assets.forEach((asset) => {
    requireCondition(!iconByLegacyResourceFamily.has(asset.resourceFamily),
      `Image-owned resource family overlaps an Operational Icon: ${asset.resourceFamily}`);
  });

  raw.groups.forEach((group, groupIndex) => {
    requireString(group.id, `groups[${groupIndex}].id`);
    requireString(group.title, `groups[${groupIndex}].title`);
    requireArray(group.entries, `groups[${groupIndex}].entries`);
    requireCondition(group.entries.length > 0, `Icon group ${group.id} must not be empty.`);
    requireUnique(group.entries.map((entry) => entry.actionId).filter(Boolean), `${group.id} actionId`);
    group.entries.forEach((entry, entryIndex) => {
      requireString(entry.iconId, `groups[${groupIndex}].entries[${entryIndex}].iconId`);
      requireCondition(iconById.has(entry.iconId), `Icon group ${group.id} references unknown iconId ${entry.iconId}`);
      requireCondition(entry.resourceFamily === undefined, `Catalog group ${group.id} must reference iconId, not resourceFamily.`);
    });
  });

  const legacyOutputProjection = compileLegacyOutputProjection(
    raw.legacyOutputProfiles,
    iconById,
    legacyCompatibilityIconIds
  );
  legacyOutputProjection.iconByResourcePath.forEach((_icon, resourcePath) => {
    requireCondition(!imageManifest.themedSourcePathByResourcePath.has(resourcePath),
      `Operational and image-owned outputs overlap: ${resourcePath}`);
    requireCondition(!imageManifest.packagedSvgExceptionPaths.has(resourcePath),
      `Operational output is also classified as an image exception: ${resourcePath}`);
  });
  imageManifest.themedSourcePathByResourcePath.forEach((_sourcePath, resourcePath) => {
    requireCondition(!imageManifest.packagedSvgExceptionPaths.has(resourcePath),
      `Generated image output is also classified as an exception: ${resourcePath}`);
  });
  imageManifest.themedRasterSourcePathByResourcePath.forEach((_sourcePath, resourcePath) => {
    requireCondition(!legacyOutputProjection.iconByResourcePath.has(resourcePath),
      `Operational and image-owned outputs overlap: ${resourcePath}`);
    requireCondition(!imageManifest.themedSourcePathByResourcePath.has(resourcePath),
      `Themed SVG and raster outputs overlap: ${resourcePath}`);
    requireCondition(!imageManifest.packagedSvgExceptionPaths.has(resourcePath),
      `Generated image output is also classified as an exception: ${resourcePath}`);
  });

  const operationalLegacyIconMap = deriveOperationalIconMap(raw.font, fontValidation, raw.sources, raw.icons);
  const imageLegacyIconMap = deriveImageLegacyIconMap(imageManifest.assets);
  const themedImageMap = imageLegacyIconMap.filter((entry) =>
    imageManifest.assetByResourceFamily.get(entry.primaryResourceFamily).kind.startsWith('themed-'));
  const rasterImageMap = imageLegacyIconMap.filter((entry) =>
    imageManifest.assetByResourceFamily.get(entry.primaryResourceFamily).kind === 'raster-copy');
  const legacyIconMap = [...themedImageMap, ...operationalLegacyIconMap, ...rasterImageMap];
  const legacyIconGroups = deriveLegacyIconGroups(raw.groups, iconById, imageManifest.groups);
  const generatedArkTS = deriveGeneratedAiraIconCatalog(
    raw.font,
    raw.icons,
    fontValidation.glyphs,
    legacyOutputProjection
  );
  const generatedArkTSPath = path.join(
    repoRoot,
    'AiraBrowser/entry/src/main/ets/core/resources/GeneratedAiraIconCatalog.ets'
  );
  const rawfileRoot = path.join(repoRoot, 'AiraBrowser/entry/src/main/resources/rawfile');
  const derivedArtifacts = new Map([
    [path.join(catalogRoot, 'icon-map.json'), JSON.stringify(legacyIconMap, null, 2) + '\n'],
    [path.join(catalogRoot, 'icon-map.csv'), deriveLegacyIconMapCsv(legacyIconMap)],
    [path.join(catalogRoot, 'icon-groups.json'), JSON.stringify(legacyIconGroups, null, 2) + '\n'],
    [generatedArkTSPath, generatedArkTS],
    [path.join(rawfileRoot, raw.font.packagedRawfile),
      fs.readFileSync(path.join(catalogRoot, raw.font.fontFile))]
  ]);
  const fontResourceFamilies = new Set(
    raw.icons
      .filter((icon) => icon.representation.kind === 'font')
      .map((icon) => icon.legacyResourceFamily)
  );

  function resolveLegacySourcePath(resourceFamily, outputFileName = '') {
    const icon = iconByLegacyResourceFamily.get(resourceFamily);
    if (!icon) {
      return undefined;
    }
    if (icon.representation.kind === 'font') {
      return fontValidation.sourcePathByGlyph.get(icon.representation.glyph);
    }
    const variant = /_chrome_(light|dark)\.svg$/.test(outputFileName) ? 'chrome' : 'default';
    const sourceId = icon.legacyVariantSources?.[variant] ?? icon.sourceId;
    return resolvedSourcePathById.get(sourceId);
  }

  return {
    repoRoot,
    sources: raw.sources,
    icons: raw.icons,
    groups: raw.groups,
    imageManifest,
    legacyOutputProjection,
    legacyCompatibilityIconIds,
    fontResourceFamilies,
    derivedArtifacts,
    resolveLegacySourcePath
  };
}

function synchronizeAiraIconCatalogArtifacts(compiled, options = {}) {
  const check = options.check === true;
  const changedFiles = [];
  compiled.derivedArtifacts.forEach((content, filePath) => {
    const previous = fs.existsSync(filePath) ? fs.readFileSync(filePath) : undefined;
    const next = Buffer.isBuffer(content) ? content : Buffer.from(content, 'utf8');
    if (previous !== undefined && previous.equals(next)) {
      return;
    }
    changedFiles.push(path.relative(compiled.repoRoot, filePath));
    if (!check) {
      fs.mkdirSync(path.dirname(filePath), { recursive: true });
      fs.writeFileSync(filePath, next);
    }
  });
  return {
    checked: compiled.derivedArtifacts.size,
    changed: changedFiles.length,
    changedFiles
  };
}

module.exports = {
  canonicalLegacyResourceName,
  compileAiraIconCatalog,
  synchronizeAiraIconCatalogArtifacts
};
