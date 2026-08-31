import { common } from '@kit.AbilityKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import buffer from '@ohos.buffer';
import zlib from '@ohos.zlib';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { CustomHomepageItem } from '../../common/models/CustomHomepageModels';
import {
  BrowserHomepageBackdropAppearanceEffectInput,
  BrowserHomepageBackdropAppearanceState
} from '../../common/models/BackdropAppearanceModels';
import { BackdropAppearanceSamplingService } from '../appearance/BackdropAppearanceSamplingService';
import { CustomHomepageHtmlValidationService } from './CustomHomepageHtmlValidationService';

const CUSTOM_HOMEPAGE_DIR_NAME: string = 'custom-homepage';
const CUSTOM_HOMEPAGE_PACKAGE_DIR_NAME: string = 'custom-homepage-packages';
const CUSTOM_HOMEPAGE_TMP_DIR_NAME: string = 'custom-homepage-tmp';
const CUSTOM_HOMEPAGE_PACKAGE_MANIFEST_NAME: string = 'aira-homepage.json';
const MAX_CUSTOM_HOMEPAGE_BYTES: number = 5 * 1024 * 1024;
const MAX_CUSTOM_HOMEPAGE_ZIP_BYTES: number = 20 * 1024 * 1024;
const MAX_CUSTOM_HOMEPAGE_EXTRACTED_BYTES: number = 50 * 1024 * 1024;
const MAX_CUSTOM_HOMEPAGE_PACKAGE_FILES: number = 300;
const MAX_CUSTOM_HOMEPAGE_PACKAGE_FILE_BYTES: number = 8 * 1024 * 1024;
const MAX_CUSTOM_HOMEPAGE_MANIFEST_BYTES: number = 128 * 1024;
const MAX_CUSTOM_HOMEPAGE_VERSION_LENGTH: number = 32;
const MAX_CUSTOM_HOMEPAGE_DESCRIPTION_LENGTH: number = 200;
const CUSTOM_HOMEPAGE_PREVIEW_APPEARANCE_SAMPLE_WIDTH: number = 96;
const CUSTOM_HOMEPAGE_PREVIEW_APPEARANCE_SAMPLE_HEIGHT: number = 144;
const CUSTOM_HOMEPAGE_VERSION_PATTERN: RegExp =
  /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/;

const CUSTOM_HOMEPAGE_ALLOWED_PACKAGE_SUFFIXES: string[] = [
  '.html', '.htm', '.css', '.js', '.mjs', '.json', '.txt', '.md',
  '.png', '.jpg', '.jpeg', '.webp', '.gif', '.svg', '.ico',
  '.woff', '.woff2', '.ttf', '.otf'
];

const CUSTOM_HOMEPAGE_BLOCKED_PACKAGE_SUFFIXES: string[] = [
  '.hap', '.app', '.apk', '.exe', '.msi', '.dmg', '.pkg', '.deb', '.rpm',
  '.sh', '.bat', '.cmd', '.ps1', '.command', '.so', '.dll', '.dylib',
  '.jar', '.class', '.zip', '.7z', '.rar', '.tar', '.gz', '.bz2', '.xz'
];

const CUSTOM_HOMEPAGE_BLOCKED_DIR_NAMES: string[] = [
  '__macosx', 'node_modules', '.git', '.svn', '.hg'
];

interface CustomHomepagePackageManifest {
  schemaVersion?: number;
  id?: string;
  name?: string;
  entry?: string;
  preview?: string;
  previewLight?: string;
  previewDark?: string;
  version?: string;
  author?: string;
  description?: string;
}

interface CustomHomepagePackagePreviewPaths {
  light: string;
  dark: string;
  hasLightAppearanceEvidence: boolean;
  hasDarkAppearanceEvidence: boolean;
}

interface CustomHomepagePackageScanResult {
  fileCount: number;
  totalBytes: number;
}

interface CustomHomepagePreviewAppearancePair {
  light?: BrowserHomepageBackdropAppearanceState;
  dark?: BrowserHomepageBackdropAppearanceState;
}

export interface CustomHomepagePreparedPackageImport {
  token: string;
  stagingRootPath: string;
  stagedPackageRootPath: string;
  finalPackageRootPath: string;
  previewLightRelativePath: string;
  previewDarkRelativePath: string;
  item: CustomHomepageItem;
}

export type CustomHomepagePackageImportErrorCode = 'missing_manifest' | 'invalid_zip';

export class CustomHomepagePackageImportError extends Error {
  readonly code: CustomHomepagePackageImportErrorCode;

  constructor(code: CustomHomepagePackageImportErrorCode, message: string) {
    super(message);
    this.name = 'CustomHomepagePackageImportError';
    this.code = code;
  }
}

export class CustomHomepageFileService {
  private htmlValidationService: CustomHomepageHtmlValidationService = new CustomHomepageHtmlValidationService();
  private appearanceSamplingService: BackdropAppearanceSamplingService = new BackdropAppearanceSamplingService();

  pickHomepageFileUri(context: common.UIAbilityContext): Promise<string | undefined> {
    const documentPicker = new picker.DocumentViewPicker(context);
    return documentPicker.select({
      maxSelectNumber: 1,
      fileSuffixFilters: ['.html', '.htm', '.zip']
    }).then((uris: Array<string>) => uris.length > 0 ? uris[0] : undefined);
  }

  async importHomepageFile(sourceUri: string): Promise<CustomHomepageItem> {
    const normalizedSourceUri = sourceUri.trim();
    if (this.isZipUri(normalizedSourceUri)) {
      return await this.importZipPackage(normalizedSourceUri);
    }
    return await this.importHtmlFile(normalizedSourceUri);
  }

  async exportHomepageFile(context: common.UIAbilityContext, item: CustomHomepageItem): Promise<boolean> {
    const targetUri = await this.pickHomepageExportUri(context, item);
    if (targetUri === undefined) {
      return false;
    }
    if (item.kind === 'zip_package') {
      await this.exportZipPackage(item, targetUri);
      return true;
    }
    if (item.kind === 'remote_url') {
      await this.exportRemoteUrlHomepage(item, targetUri);
      return true;
    }
    await this.exportSingleHtmlHomepage(item, targetUri);
    return true;
  }

  async importHtmlFile(sourceUri: string): Promise<CustomHomepageItem> {
    const normalizedSourceUri = sourceUri.trim();
    if (normalizedSourceUri.length === 0) {
      throw new Error('未选择 HTML 文件。');
    }

    await this.ensureDirectory(this.getRootDir());
    const now = Date.now();
    const displayFileName = this.resolveDisplayFileName(normalizedSourceUri);
    const itemId = this.buildItemId(now);
    const identityKey = this.buildSingleHtmlIdentityKey(itemId);
    const finalPath = `${this.getRootDir()}/${itemId}-${this.sanitizeFileName(displayFileName)}`;
    const tempPath = `${finalPath}.tmp`;
    await this.deleteIfExists(tempPath);
    await fileIo.copy(normalizedSourceUri, fileUri.getUriFromPath(tempPath));
    try {
      const byteSize = await this.ensureUsableHtmlFile(tempPath);
      await this.deleteIfExists(finalPath);
      await this.moveFile(tempPath, finalPath);
      return {
        id: itemId,
        identityKey: identityKey,
        kind: 'single_html',
        fileName: displayFileName,
        filePath: finalPath,
        fileUri: fileUri.getUriFromPath(finalPath),
        rootPath: finalPath,
        packageRootPath: '',
        entryPath: '',
        manifestPath: '',
        packageName: '',
        version: '',
        author: '',
        description: '',
        previewPath: '',
        previewUri: '',
        previewLightUri: '',
        previewDarkUri: '',
        remoteUrl: '',
        siteIconUri: '',
        packageSize: byteSize,
        extractedSize: byteSize,
        byteSize: byteSize,
        importedAt: now,
        updatedAt: now
      };
    } catch (error) {
      await this.deleteIfExists(tempPath);
      throw new Error(this.stringifyError(error));
    }
  }

  async importZipPackage(sourceUri: string): Promise<CustomHomepageItem> {
    const prepared = await this.prepareZipPackage(sourceUri);
    try {
      return await this.commitPreparedZipPackage(prepared);
    } catch (error) {
      await this.discardPreparedZipPackage(prepared);
      throw this.normalizePackageImportError(error);
    }
  }

  async prepareZipPackage(sourceUri: string): Promise<CustomHomepagePreparedPackageImport> {
    const normalizedSourceUri = sourceUri.trim();
    if (normalizedSourceUri.length === 0) {
      throw new Error('未选择主页包。');
    }

    await this.ensureDirectory(this.getPackageRootDir());
    await this.ensureDirectory(this.getTmpRootDir());
    const now = Date.now();
    const itemId = this.buildItemId(now);
    const displayFileName = this.resolveDisplayFileName(normalizedSourceUri);
    const finalPackageRootPath = `${this.getPackageRootDir()}/${itemId}`;
    const stagingRootPath = `${this.getTmpRootDir()}/${itemId}`;
    const stagedPackageRootPath = `${stagingRootPath}/package`;
    const copiedZipPath = `${stagingRootPath}/${this.sanitizeFileName(displayFileName)}`;
    await this.removeDirectoryTree(stagingRootPath);
    await this.ensureDirectory(stagedPackageRootPath);
    try {
      await fileIo.copy(normalizedSourceUri, fileUri.getUriFromPath(copiedZipPath));
      const zipStat = await this.ensureUsableZipFile(copiedZipPath);
      await this.ensureUsableZipOriginalSize(copiedZipPath);
      await zlib.decompressFile(copiedZipPath, stagedPackageRootPath);
      const manifest = await this.readPackageManifest(stagedPackageRootPath);
      const scan = await this.validatePackageTree(stagedPackageRootPath);
      const packageName = this.normalizeManifestText(manifest.name, this.stripFileExtension(displayFileName));
      const version = this.normalizeManifestVersion(manifest.version);
      const description = this.normalizeManifestDescription(manifest.description);
      const identityKey = this.buildZipPackageIdentityKey(manifest, itemId);
      const entryPath = this.normalizePackageRelativePath(manifest.entry ?? '');
      if (entryPath.length === 0) {
        throw new Error('主页包缺少入口文件。');
      }
      const previewPaths = this.resolvePackagePreviewPaths(manifest);
      this.ensureHtmlFileName(entryPath, '入口文件必须是 HTML。');
      this.ensurePreviewFileName(previewPaths.light);
      this.ensurePreviewFileName(previewPaths.dark);
      const entryFullPath = this.resolvePackagePath(stagedPackageRootPath, entryPath);
      const previewLightFullPath = this.resolvePackagePath(stagedPackageRootPath, previewPaths.light);
      const previewDarkFullPath = this.resolvePackagePath(stagedPackageRootPath, previewPaths.dark);
      await this.ensurePackageHtmlEntry(entryFullPath);
      await this.ensurePackagePreviewImage(previewLightFullPath);
      if (previewDarkFullPath !== previewLightFullPath) {
        await this.ensurePackagePreviewImage(previewDarkFullPath);
      }
      const previewLightUri = fileUri.getUriFromPath(previewLightFullPath);
      const previewDarkUri = fileUri.getUriFromPath(previewDarkFullPath);
      const appearancePair = await this.resolvePreviewAppearancePair(
        previewLightFullPath,
        previewDarkFullPath,
        previewPaths.hasLightAppearanceEvidence,
        previewPaths.hasDarkAppearanceEvidence,
        itemId,
        now
      );
      const item: CustomHomepageItem = {
        id: itemId,
        identityKey: identityKey,
        kind: 'zip_package',
        fileName: displayFileName,
        filePath: entryFullPath,
        fileUri: fileUri.getUriFromPath(entryFullPath),
        rootPath: stagedPackageRootPath,
        packageRootPath: stagedPackageRootPath,
        entryPath: entryPath,
        manifestPath: `${stagedPackageRootPath}/${CUSTOM_HOMEPAGE_PACKAGE_MANIFEST_NAME}`,
        packageName: packageName,
        version: version,
        author: this.normalizeManifestText(manifest.author, ''),
        description: description,
        previewPath: previewLightFullPath,
        previewUri: previewLightUri,
        previewLightUri: previewLightUri,
        previewDarkUri: previewDarkUri,
        hasLightAppearanceEvidence: previewPaths.hasLightAppearanceEvidence,
        hasDarkAppearanceEvidence: previewPaths.hasDarkAppearanceEvidence,
        appearanceLight: appearancePair.light,
        appearanceDark: appearancePair.dark,
        remoteUrl: '',
        siteIconUri: '',
        packageSize: Math.floor(zipStat.size),
        extractedSize: scan.totalBytes,
        byteSize: Math.floor(zipStat.size),
        importedAt: now,
        updatedAt: now
      };
      return {
        token: itemId,
        stagingRootPath: stagingRootPath,
        stagedPackageRootPath: stagedPackageRootPath,
        finalPackageRootPath: finalPackageRootPath,
        previewLightRelativePath: previewPaths.light,
        previewDarkRelativePath: previewPaths.dark,
        item: item
      };
    } catch (error) {
      const packageError = this.normalizePackageImportError(error);
      try {
        await this.removeDirectoryTree(stagingRootPath);
      } catch (cleanupError) {
        throw this.buildCleanupFailureError(packageError, cleanupError, '隔离目录');
      }
      throw packageError;
    } finally {
      await this.deleteIfExists(copiedZipPath);
    }
  }

  async commitPreparedZipPackage(prepared: CustomHomepagePreparedPackageImport): Promise<CustomHomepageItem> {
    this.ensurePreparedPackageImport(prepared);
    await this.ensureDirectory(this.getPackageRootDir());
    if (await this.exists(prepared.finalPackageRootPath)) {
      throw new Error('主页包安装目录冲突，请重试。');
    }
    try {
      await this.moveFile(prepared.stagedPackageRootPath, prepared.finalPackageRootPath);
      await this.removeDirectoryTree(prepared.stagingRootPath);
      return this.remapPreparedItem(prepared);
    } catch (error) {
      const packageError = error instanceof Error ? error : new Error('主页包安装未完成。');
      try {
        await this.removeDirectoryTree(prepared.finalPackageRootPath);
      } catch (cleanupError) {
        throw this.buildCleanupFailureError(packageError, cleanupError, '安装目录');
      }
      throw new Error(packageError.message);
    }
  }

  async discardPreparedZipPackage(prepared: CustomHomepagePreparedPackageImport): Promise<void> {
    this.ensurePreparedPackageImport(prepared);
    await this.removeDirectoryTree(prepared.stagingRootPath);
  }

  async removeImportedFile(item: CustomHomepageItem): Promise<void> {
    if (item.kind === 'remote_url') {
      return;
    }
    if (item.kind === 'zip_package') {
      const rootPath = item.packageRootPath.trim().length > 0 ? item.packageRootPath.trim() : item.rootPath.trim();
      if (rootPath.length > 0) {
        await this.removeDirectoryTree(rootPath);
      }
      return;
    }
    const normalizedPath = item.filePath.trim();
    if (normalizedPath.length > 0) {
      await this.deleteIfExists(normalizedPath);
    }
  }

  private async pickHomepageExportUri(
    context: common.UIAbilityContext,
    item: CustomHomepageItem
  ): Promise<string | undefined> {
    const documentPicker = new picker.DocumentViewPicker(context);
    const uris = await documentPicker.save({
      newFileNames: [this.buildHomepageExportFileName(item)],
      fileSuffixChoices: [item.kind === 'zip_package' ? 'Aira 主页包|.zip' : 'HTML 主页|.html']
    });
    return uris.length > 0 && uris[0].trim().length > 0 ? uris[0] : undefined;
  }

  private async exportSingleHtmlHomepage(item: CustomHomepageItem, targetUri: string): Promise<void> {
    const sourcePath = item.filePath.trim();
    await this.ensureExportFileExists(sourcePath, '自定义主页文件不存在。');
    await fileIo.copy(fileUri.getUriFromPath(sourcePath), targetUri);
  }

  private async exportZipPackage(item: CustomHomepageItem, targetUri: string): Promise<void> {
    const rootPath = item.packageRootPath.trim().length > 0 ? item.packageRootPath.trim() : item.rootPath.trim();
    await this.ensureExportDirectoryExists(rootPath, '自定义主页包不存在。');
    await this.ensureDirectory(this.getTmpRootDir());
    const tempZipPath = `${this.getTmpRootDir()}/export-${item.id}-${Date.now()}.zip`;
    await this.deleteIfExists(tempZipPath);
    try {
      const options: zlib.Options = {
        level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION,
        memLevel: zlib.MemLevel.MEM_LEVEL_DEFAULT,
        strategy: zlib.CompressStrategy.COMPRESS_STRATEGY_DEFAULT_STRATEGY
      };
      await zlib.compressFile(rootPath, tempZipPath, options);
      await fileIo.copy(fileUri.getUriFromPath(tempZipPath), targetUri);
    } finally {
      await this.deleteIfExists(tempZipPath);
    }
  }

  private async exportRemoteUrlHomepage(item: CustomHomepageItem, targetUri: string): Promise<void> {
    const url = item.remoteUrl.trim();
    if (url.length <= 0) {
      throw new Error('网址主页地址不存在。');
    }
    await this.ensureDirectory(this.getTmpRootDir());
    const tempHtmlPath = `${this.getTmpRootDir()}/export-${item.id}-${Date.now()}.html`;
    await this.deleteIfExists(tempHtmlPath);
    try {
      await this.writeTextFile(tempHtmlPath, this.buildRemoteUrlExportHtml(item, url));
      await fileIo.copy(fileUri.getUriFromPath(tempHtmlPath), targetUri);
    } finally {
      await this.deleteIfExists(tempHtmlPath);
    }
  }

  private buildRemoteUrlExportHtml(item: CustomHomepageItem, url: string): string {
    const title = item.packageName.trim().length > 0 ? item.packageName.trim() : url;
    const escapedTitle = this.escapeHtml(title);
    const escapedUrl = this.escapeHtml(url);
    return [
      '<!doctype html>',
      '<html lang="zh-CN">',
      '<head>',
      '  <meta charset="utf-8">',
      '  <meta name="viewport" content="width=device-width, initial-scale=1">',
      `  <title>${escapedTitle}</title>`,
      '  <style>',
      '    :root { color-scheme: light dark; font-family: sans-serif; }',
      '    body { margin: 0; min-height: 100vh; display: grid; place-items: center; }',
      '    main { width: min(34rem, calc(100% - 3rem)); text-align: center; }',
      '    a { display: inline-block; margin-top: 1rem; padding: 0.8rem 1.2rem; border-radius: 999px; }',
      '    .url { margin-top: 1rem; overflow-wrap: anywhere; opacity: 0.72; }',
      '  </style>',
      '</head>',
      '<body>',
      '  <main>',
      `    <h1>${escapedTitle}</h1>`,
      '    <p>此文件保存了 Aira 网址主页的地址。</p>',
      `    <a href="${escapedUrl}">打开主页</a>`,
      `    <p class="url">${escapedUrl}</p>`,
      '  </main>',
      '</body>',
      '</html>',
      ''
    ].join('\n');
  }

  private buildHomepageExportFileName(item: CustomHomepageItem): string {
    const fallbackName = item.kind === 'zip_package' ? 'aira-homepage-package' : 'aira-homepage';
    const sourceName = item.packageName.trim().length > 0 ? item.packageName.trim() : item.fileName.trim();
    const baseName = this.sanitizeFileName(this.stripFileExtension(sourceName.length > 0 ? sourceName : fallbackName));
    const extension = item.kind === 'zip_package' ? '.zip' : '.html';
    return `${baseName.substring(0, 72)}${extension}`;
  }

  private async writeTextFile(path: string, payload: string): Promise<void> {
    const file = await fileIo.open(
      path,
      fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    );
    try {
      await fileIo.write(file.fd, payload);
    } finally {
      await fileIo.close(file);
    }
  }

  private async ensureExportFileExists(path: string, message: string): Promise<void> {
    if (path.length <= 0) {
      throw new Error(message);
    }
    try {
      const stat = await fileIo.stat(path);
      if (stat.isDirectory() || stat.size <= 0) {
        throw new Error(message);
      }
    } catch (_error) {
      throw new Error(message);
    }
  }

  private async ensureExportDirectoryExists(path: string, message: string): Promise<void> {
    if (path.length <= 0) {
      throw new Error(message);
    }
    try {
      const stat = await fileIo.stat(path);
      if (!stat.isDirectory()) {
        throw new Error(message);
      }
      const names = await fileIo.listFile(path);
      if (names.length <= 0) {
        throw new Error(message);
      }
    } catch (_error) {
      throw new Error(message);
    }
  }

  private escapeHtml(value: string): string {
    return value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  private async ensureUsableZipFile(path: string): Promise<fileIo.Stat> {
    const stat = await fileIo.stat(path);
    if (stat.isDirectory() || stat.size <= 0) {
      throw new Error('主页包不可用。');
    }
    if (stat.size > MAX_CUSTOM_HOMEPAGE_ZIP_BYTES) {
      throw new Error('主页包超过 20 MB。');
    }
    const sample = await this.readFileBytes(path, 4);
    if (sample.length < 4 || sample[0] !== 0x50 || sample[1] !== 0x4B) {
      throw new CustomHomepagePackageImportError('invalid_zip', '请选择有效的 ZIP 主页包。');
    }
    return stat;
  }

  private async ensureUsableZipOriginalSize(path: string): Promise<void> {
    let originalSize: number;
    try {
      originalSize = await zlib.getOriginalSize(path);
    } catch (_error) {
      throw new CustomHomepagePackageImportError('invalid_zip', '请选择有效的 ZIP 主页包。');
    }
    if (!Number.isFinite(originalSize) || originalSize < 0) {
      throw new CustomHomepagePackageImportError('invalid_zip', '请选择有效的 ZIP 主页包。');
    }
    if (originalSize > MAX_CUSTOM_HOMEPAGE_EXTRACTED_BYTES) {
      throw new Error('主页包解压后超过 50 MB。');
    }
  }

  private async ensureUsableHtmlFile(path: string): Promise<number> {
    const stat = await fileIo.stat(path);
    if (stat.isDirectory() || stat.size <= 0) {
      throw new Error('HTML 文件不可用。');
    }
    if (stat.size > MAX_CUSTOM_HOMEPAGE_BYTES) {
      throw new Error('HTML 文件超过 5 MB。');
    }
    const sample = await this.readFileSample(path);
    if (!this.htmlValidationService.looksLikeHtml(sample)) {
      throw new Error('请选择有效的 HTML 文件。');
    }
    this.htmlValidationService.validateForImport({
      html: await this.readTextFile(path, MAX_CUSTOM_HOMEPAGE_BYTES),
      sourceLabel: 'HTML 文件'
    });
    return Math.floor(stat.size);
  }

  private async readFileSample(path: string): Promise<string> {
    const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    try {
      const data = new ArrayBuffer(2048);
      const readLength = await fileIo.read(file.fd, data);
      return readLength > 0 ? buffer.from(data, 0, readLength).toString('utf8').trim().toLowerCase() : '';
    } finally {
      await fileIo.close(file);
    }
  }

  private async validatePackageTree(rootPath: string): Promise<CustomHomepagePackageScanResult> {
    const result: CustomHomepagePackageScanResult = {
      fileCount: 0,
      totalBytes: 0
    };
    await this.scanPackageDirectory(rootPath, rootPath, result);
    if (result.fileCount <= 0) {
      throw new Error('主页包为空。');
    }
    return result;
  }

  private async scanPackageDirectory(
    rootPath: string,
    dir: string,
    result: CustomHomepagePackageScanResult
  ): Promise<void> {
    const names = await fileIo.listFile(dir);
    for (let index = 0; index < names.length; index += 1) {
      const name = names[index];
      this.ensureSafePackageSegment(name);
      const path = `${dir}/${name}`;
      this.ensurePathInsideRoot(rootPath, path);
      const stat = await fileIo.stat(path);
      if (stat.isDirectory()) {
        this.ensureAllowedPackageDirectoryName(name);
        await this.scanPackageDirectory(rootPath, path, result);
      } else {
        result.fileCount += 1;
        if (result.fileCount > MAX_CUSTOM_HOMEPAGE_PACKAGE_FILES) {
          throw new Error('主页包文件数量超过 300 个。');
        }
        if (stat.size > MAX_CUSTOM_HOMEPAGE_PACKAGE_FILE_BYTES) {
          throw new Error(`主页包内文件过大：${name}`);
        }
        result.totalBytes += Math.max(0, Math.floor(stat.size));
        if (result.totalBytes > MAX_CUSTOM_HOMEPAGE_EXTRACTED_BYTES) {
          throw new Error('主页包解压后超过 50 MB。');
        }
        const relativePath = path.substring(rootPath.length + 1);
        this.ensureAllowedPackageFileName(relativePath);
        await this.validatePackageAssetContent(path, relativePath);
      }
    }
  }

  private async validatePackageAssetContent(path: string, relativePath: string): Promise<void> {
    const lower = relativePath.toLowerCase();
    if (!lower.endsWith('.js') && !lower.endsWith('.mjs')) {
      return;
    }
    try {
      this.htmlValidationService.validateScriptAssetForImport(
        await this.readTextFile(path, MAX_CUSTOM_HOMEPAGE_PACKAGE_FILE_BYTES)
      );
    } catch (error) {
      throw new Error(`主页包脚本不安全：${this.stringifyError(error)}`);
    }
  }

  private async readPackageManifest(rootPath: string): Promise<CustomHomepagePackageManifest> {
    const manifestPath = `${rootPath}/${CUSTOM_HOMEPAGE_PACKAGE_MANIFEST_NAME}`;
    try {
      await this.ensurePackageFileExists(manifestPath, '主页包缺少 aira-homepage.json。');
    } catch (_error) {
      throw new CustomHomepagePackageImportError(
        'missing_manifest',
        '主页包缺少 aira-homepage.json。'
      );
    }
    const text = await this.readTextFile(manifestPath, MAX_CUSTOM_HOMEPAGE_MANIFEST_BYTES);
    try {
      const manifest = JSON.parse(text) as CustomHomepagePackageManifest;
      if (manifest.schemaVersion !== 1) {
        throw new Error('schemaVersion 必须为 1。');
      }
      return manifest;
    } catch (error) {
      throw new Error(`主页包清单无效：${this.stringifyError(error)}`);
    }
  }

  private resolvePackagePreviewPaths(manifest: CustomHomepagePackageManifest): CustomHomepagePackagePreviewPaths {
    const fallback = this.normalizeOptionalManifestPreviewPath(manifest.preview, 'preview');
    const explicitLight = this.normalizeOptionalManifestPreviewPath(manifest.previewLight, 'previewLight');
    const explicitDark = this.normalizeOptionalManifestPreviewPath(manifest.previewDark, 'previewDark');
    if (fallback.length === 0 && explicitLight.length === 0 && explicitDark.length === 0) {
      throw new Error('主页包缺少预览图。请配置 preview、previewLight 或 previewDark 中至少一个字段。');
    }
    const light = explicitLight.length > 0 ? explicitLight : (fallback.length > 0 ? fallback : explicitDark);
    const dark = explicitDark.length > 0 ? explicitDark : (fallback.length > 0 ? fallback : explicitLight);
    return {
      light: light,
      dark: dark,
      hasLightAppearanceEvidence: explicitLight.length > 0 || fallback.length > 0,
      hasDarkAppearanceEvidence: explicitDark.length > 0
    };
  }

  private normalizeOptionalManifestPreviewPath(value: string | undefined, fieldName: string): string {
    const rawValue = value?.trim() ?? '';
    if (rawValue.length === 0) {
      return '';
    }
    const normalized = this.normalizePackageRelativePath(rawValue);
    if (normalized.length === 0) {
      throw new Error(`主页包清单字段 ${fieldName} 的路径无效。`);
    }
    return normalized;
  }

  private async ensurePackageHtmlEntry(path: string): Promise<void> {
    await this.ensurePackageFileExists(path, '入口 HTML 文件不存在。');
    const stat = await fileIo.stat(path);
    if (stat.size > MAX_CUSTOM_HOMEPAGE_BYTES) {
      throw new Error('入口 HTML 文件超过 5 MB。');
    }
    const sample = await this.readFileSample(path);
    if (!this.htmlValidationService.looksLikeHtml(sample)) {
      throw new Error('入口文件不是有效的 HTML。');
    }
    this.htmlValidationService.validateForImport({
      html: await this.readTextFile(path, MAX_CUSTOM_HOMEPAGE_BYTES),
      sourceLabel: '入口 HTML'
    });
  }

  private async ensurePackagePreviewImage(path: string): Promise<void> {
    await this.ensurePackageFileExists(path, '主页包预览图不存在。');
    const stat = await fileIo.stat(path);
    if (stat.size > MAX_CUSTOM_HOMEPAGE_PACKAGE_FILE_BYTES) {
      throw new Error('主页包预览图超过 8 MB。');
    }
    const sample = await this.readFileBytes(path, 12);
    if (!this.looksLikePreviewImage(sample)) {
      throw new Error('主页包预览图必须是 PNG、JPEG 或 WebP 图片。');
    }
  }

  private async resolvePreviewAppearancePair(
    previewLightPath: string,
    previewDarkPath: string,
    hasLightAppearanceEvidence: boolean,
    hasDarkAppearanceEvidence: boolean,
    itemId: string,
    nowMs: number
  ): Promise<CustomHomepagePreviewAppearancePair> {
    const light = hasLightAppearanceEvidence ?
      await this.resolvePreviewAppearance(previewLightPath, itemId, nowMs, 'light') : undefined;
    const dark = hasDarkAppearanceEvidence ?
      await this.resolvePreviewAppearance(previewDarkPath, itemId, nowMs, 'dark') : undefined;
    return {
      light: light,
      dark: dark
    };
  }

  private async resolvePreviewAppearance(
    previewPath: string,
    itemId: string,
    nowMs: number,
    mode: 'light' | 'dark'
  ): Promise<BrowserHomepageBackdropAppearanceState | undefined> {
    let imageSource: image.ImageSource | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      const payload = await this.readFilePayload(previewPath, MAX_CUSTOM_HOMEPAGE_PACKAGE_FILE_BYTES);
      imageSource = image.createImageSource(payload);
      pixelMap = await imageSource.createPixelMap({
        editable: false,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredSize: {
          width: CUSTOM_HOMEPAGE_PREVIEW_APPEARANCE_SAMPLE_WIDTH,
          height: CUSTOM_HOMEPAGE_PREVIEW_APPEARANCE_SAMPLE_HEIGHT
        }
      });
      return await this.appearanceSamplingService.sample({
        pixelMap: pixelMap,
        sourceKey: `customImportedPreview:${itemId}:${mode}:${nowMs}`,
        effect: this.buildPreviewAppearanceEffect(mode),
        volatileOnly: false,
        nowMs: nowMs
      });
    } catch (_error) {
      return undefined;
    } finally {
      if (pixelMap !== undefined) {
        await pixelMap.release().catch((_error: Error) => {});
      }
      if (imageSource !== undefined) {
        await imageSource.release().catch((_error: Error) => {});
      }
    }
  }

  private buildPreviewAppearanceEffect(mode: 'light' | 'dark'): BrowserHomepageBackdropAppearanceEffectInput {
    return {
      resolvedThemeMode: mode,
      tintColor: '#000000',
      tintOpacity: 0,
      effectSignature: `custom-imported-preview:v1:${mode}`
    };
  }

  private async ensurePackageFileExists(path: string, message: string): Promise<void> {
    try {
      const stat = await fileIo.stat(path);
      if (stat.isDirectory() || stat.size <= 0) {
        throw new Error(message);
      }
    } catch (_error) {
      throw new Error(message);
    }
  }

  private async readTextFile(path: string, maxBytes: number): Promise<string> {
    const stat = await fileIo.stat(path);
    if (stat.size > maxBytes) {
      throw new Error('文件过大。');
    }
    const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    try {
      const data = new ArrayBuffer(Math.max(1, Math.floor(stat.size)));
      const readLength = await fileIo.read(file.fd, data);
      return readLength > 0 ? buffer.from(data, 0, readLength).toString('utf8') : '';
    } finally {
      await fileIo.close(file);
    }
  }

  private async readFileBytes(path: string, maxBytes: number): Promise<number[]> {
    const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    try {
      const data = new ArrayBuffer(maxBytes);
      const readLength = await fileIo.read(file.fd, data);
      if (readLength <= 0) {
        return [];
      }
      const view = new Uint8Array(data);
      const bytes: number[] = [];
      for (let index = 0; index < readLength; index += 1) {
        bytes.push(view[index]);
      }
      return bytes;
    } finally {
      await fileIo.close(file);
    }
  }

  private async readFilePayload(path: string, maxBytes: number): Promise<ArrayBuffer> {
    const stat = await fileIo.stat(path);
    if (stat.isDirectory() || stat.size <= 0 || stat.size > maxBytes) {
      throw new Error('文件过大。');
    }
    const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    try {
      const data = new ArrayBuffer(Math.max(1, Math.floor(stat.size)));
      const readLength = await fileIo.read(file.fd, data);
      if (readLength <= 0) {
        throw new Error('文件读取失败。');
      }
      return data;
    } finally {
      await fileIo.close(file);
    }
  }

  private async moveFile(sourcePath: string, targetPath: string): Promise<void> {
    try {
      await fileIo.rename(sourcePath, targetPath);
    } catch (_renameError) {
      await fileIo.copyFile(sourcePath, targetPath);
      await fileIo.unlink(sourcePath);
    }
  }

  private async removeDirectoryTree(dir: string): Promise<void> {
    try {
      await this.removeDirectoryTreeOnce(dir);
      return;
    } catch (_firstError) {}
    try {
      await this.removeDirectoryTreeOnce(dir);
    } catch (error) {
      throw new Error(`目录清理失败：${this.stringifyError(error)}`);
    }
  }

  private async removeDirectoryTreeOnce(dir: string): Promise<void> {
    if (!await this.exists(dir)) {
      return;
    }
    const names = await fileIo.listFile(dir);
    for (let index = 0; index < names.length; index += 1) {
      const path = `${dir}/${names[index]}`;
      const stat = await fileIo.stat(path);
      if (stat.isDirectory()) {
        await this.removeDirectoryTreeOnce(path);
      } else {
        await fileIo.unlink(path);
      }
    }
    await fileIo.rmdir(dir);
  }

  private async ensureDirectory(path: string): Promise<void> {
    if (await this.exists(path)) {
      return;
    }
    await fileIo.mkdir(path, true);
  }

  private async deleteIfExists(path: string): Promise<void> {
    try {
      if (await fileIo.access(path)) {
        await fileIo.unlink(path);
      }
    } catch (_error) {
    }
  }

  private async exists(path: string): Promise<boolean> {
    try {
      return await fileIo.access(path);
    } catch (_error) {
      return false;
    }
  }

  private getRootDir(): string {
    return `${AppRuntimeContext.getApplicationContext().filesDir}/${CUSTOM_HOMEPAGE_DIR_NAME}`;
  }

  private getPackageRootDir(): string {
    return `${AppRuntimeContext.getApplicationContext().filesDir}/${CUSTOM_HOMEPAGE_PACKAGE_DIR_NAME}`;
  }

  private getTmpRootDir(): string {
    return `${AppRuntimeContext.getApplicationContext().filesDir}/${CUSTOM_HOMEPAGE_TMP_DIR_NAME}`;
  }

  private resolveDisplayFileName(uri: string): string {
    const normalized = uri.split('?')[0].split('#')[0];
    const segments = normalized.split('/');
    const fileName = segments.length > 0 ? segments[segments.length - 1] : '';
    return fileName.trim().length > 0 ? decodeURIComponent(fileName.trim()) : 'homepage.html';
  }

  private sanitizeFileName(fileName: string): string {
    const normalized = fileName.trim().replace(/[\\/:*?"<>|]/g, '_');
    return normalized.length > 0 ? normalized : 'homepage.html';
  }

  private stripFileExtension(fileName: string): string {
    const normalized = fileName.trim();
    const index = normalized.lastIndexOf('.');
    return index > 0 ? normalized.substring(0, index) : normalized;
  }

  private isZipUri(uri: string): boolean {
    return uri.split('?')[0].split('#')[0].toLowerCase().endsWith('.zip');
  }

  private normalizeManifestText(value: string | undefined, fallback: string): string {
    const normalized = typeof value === 'string' ? value.trim() : '';
    return normalized.length > 0 ? normalized.substring(0, 80) : fallback;
  }

  private normalizeManifestVersion(value: string | undefined): string {
    if (value !== undefined && typeof value !== 'string') {
      throw new Error('主页包 version 必须是字符串。');
    }
    const normalized = typeof value === 'string' ? value.trim() : '';
    if (normalized.length === 0) {
      return '';
    }
    if (normalized.length > MAX_CUSTOM_HOMEPAGE_VERSION_LENGTH) {
      throw new Error(`主页包 version 不能超过 ${MAX_CUSTOM_HOMEPAGE_VERSION_LENGTH} 个字符。`);
    }
    if (!CUSTOM_HOMEPAGE_VERSION_PATTERN.test(normalized)) {
      throw new Error('主页包 version 必须使用 SemVer 格式，例如 1.0.0 或 1.2.0-beta.1。');
    }
    return normalized;
  }

  private normalizeManifestDescription(value: string | undefined): string {
    if (value !== undefined && typeof value !== 'string') {
      throw new Error('主页包 description 必须是字符串。');
    }
    const normalized = typeof value === 'string' ? value.trim() : '';
    if (normalized.length > MAX_CUSTOM_HOMEPAGE_DESCRIPTION_LENGTH) {
      throw new Error(`主页包 description 不能超过 ${MAX_CUSTOM_HOMEPAGE_DESCRIPTION_LENGTH} 个字符。`);
    }
    return normalized;
  }

  private buildSingleHtmlIdentityKey(itemId: string): string {
    return `single_html:install:${this.normalizeIdentityPart(itemId)}`;
  }

  private buildZipPackageIdentityKey(
    manifest: CustomHomepagePackageManifest,
    itemId: string
  ): string {
    const manifestId = this.normalizeManifestId(manifest.id);
    if (manifestId.length > 0) {
      return `zip_package:id:${this.normalizeIdentityPart(manifestId)}`;
    }
    return `zip_package:install:${this.normalizeIdentityPart(itemId)}`;
  }

  private normalizeManifestId(value: string | undefined): string {
    if (value !== undefined && typeof value !== 'string') {
      throw new Error('主页包 id 必须是字符串。');
    }
    const normalized = typeof value === 'string' ? value.trim() : '';
    if (normalized.length > 128) {
      throw new Error('主页包 id 不能超过 128 个字符。');
    }
    return normalized;
  }

  private normalizeIdentityPart(value: string): string {
    return value.trim().toLowerCase();
  }

  private ensurePreparedPackageImport(prepared: CustomHomepagePreparedPackageImport): void {
    const stagingRoot = prepared.stagingRootPath.trim();
    const stagedPackageRoot = prepared.stagedPackageRootPath.trim();
    const finalPackageRoot = prepared.finalPackageRootPath.trim();
    const tmpRoot = this.getTmpRootDir();
    const packageRoot = this.getPackageRootDir();
    if (prepared.token.trim().length === 0 ||
      !stagingRoot.startsWith(`${tmpRoot}/`) ||
      stagedPackageRoot !== `${stagingRoot}/package` ||
      !finalPackageRoot.startsWith(`${packageRoot}/`)) {
      throw new Error('主页包预检状态无效。');
    }
  }

  private remapPreparedItem(prepared: CustomHomepagePreparedPackageImport): CustomHomepageItem {
    const item = prepared.item;
    const targetRoot = prepared.finalPackageRootPath;
    const entryPath = this.resolvePackagePath(targetRoot, item.entryPath);
    const previewLightPath = this.resolvePackagePath(targetRoot, prepared.previewLightRelativePath);
    const previewDarkPath = this.resolvePackagePath(targetRoot, prepared.previewDarkRelativePath);
    const previewUri = fileUri.getUriFromPath(previewLightPath);
    return {
      id: item.id,
      identityKey: item.identityKey,
      kind: item.kind,
      fileName: item.fileName,
      filePath: entryPath,
      fileUri: fileUri.getUriFromPath(entryPath),
      rootPath: targetRoot,
      packageRootPath: targetRoot,
      entryPath: item.entryPath,
      manifestPath: `${targetRoot}/${CUSTOM_HOMEPAGE_PACKAGE_MANIFEST_NAME}`,
      packageName: item.packageName,
      version: item.version,
      author: item.author,
      description: item.description,
      previewPath: previewLightPath,
      previewUri: previewUri,
      previewLightUri: previewUri,
      previewDarkUri: fileUri.getUriFromPath(previewDarkPath),
      hasLightAppearanceEvidence: item.hasLightAppearanceEvidence,
      hasDarkAppearanceEvidence: item.hasDarkAppearanceEvidence,
      appearanceLight: item.appearanceLight,
      appearanceDark: item.appearanceDark,
      remoteUrl: item.remoteUrl,
      siteIconUri: item.siteIconUri,
      packageSize: item.packageSize,
      extractedSize: item.extractedSize,
      byteSize: item.byteSize,
      importedAt: item.importedAt,
      updatedAt: item.updatedAt
    };
  }

  private normalizePackageRelativePath(value: string): string {
    const normalized = value.trim().replace(/\\/g, '/');
    if (normalized.length === 0 ||
      normalized.startsWith('/') ||
      normalized.includes('\u0000') ||
      normalized.split('/').some((segment: string): boolean => segment.length === 0 || segment === '.' || segment === '..')) {
      return '';
    }
    return normalized;
  }

  private resolvePackagePath(rootPath: string, relativePath: string): string {
    const normalizedRelativePath = this.normalizePackageRelativePath(relativePath);
    if (normalizedRelativePath.length === 0) {
      throw new Error('主页包路径无效。');
    }
    const path = `${rootPath}/${normalizedRelativePath}`;
    this.ensurePathInsideRoot(rootPath, path);
    return path;
  }

  private ensurePathInsideRoot(rootPath: string, path: string): void {
    if (path !== rootPath && !path.startsWith(`${rootPath}/`)) {
      throw new Error('主页包包含非法路径。');
    }
  }

  private ensureSafePackageSegment(segment: string): void {
    if (segment.length === 0 || segment === '.' || segment === '..' ||
      segment.includes('/') || segment.includes('\\') || segment.includes('\u0000')) {
      throw new Error('主页包包含非法路径。');
    }
    if (segment.startsWith('.')) {
      throw new Error('主页包不能包含隐藏文件或隐藏目录。');
    }
  }

  private ensureAllowedPackageDirectoryName(name: string): void {
    const lower = name.trim().toLowerCase();
    if (CUSTOM_HOMEPAGE_BLOCKED_DIR_NAMES.indexOf(lower) >= 0) {
      throw new Error(`主页包不能包含目录：${name}`);
    }
  }

  private ensureAllowedPackageFileName(relativePath: string): void {
    const lower = relativePath.toLowerCase();
    const segments = lower.split('/');
    for (let index = 0; index < segments.length; index += 1) {
      const segment = segments[index];
      if (segment.startsWith('.') || CUSTOM_HOMEPAGE_BLOCKED_DIR_NAMES.indexOf(segment) >= 0) {
        throw new Error('主页包包含不支持的路径。');
      }
    }
    if (CUSTOM_HOMEPAGE_BLOCKED_PACKAGE_SUFFIXES.some((suffix: string): boolean => lower.endsWith(suffix))) {
      throw new Error('主页包包含不支持的文件类型。');
    }
    if (!CUSTOM_HOMEPAGE_ALLOWED_PACKAGE_SUFFIXES.some((suffix: string): boolean => lower.endsWith(suffix))) {
      throw new Error(`主页包包含不支持的文件：${relativePath}`);
    }
  }

  private ensureHtmlFileName(relativePath: string, message: string): void {
    const lower = relativePath.toLowerCase();
    if (!lower.endsWith('.html') && !lower.endsWith('.htm')) {
      throw new Error(message);
    }
  }

  private ensurePreviewFileName(relativePath: string): void {
    const lower = relativePath.toLowerCase();
    if (!lower.endsWith('.png') && !lower.endsWith('.jpg') && !lower.endsWith('.jpeg') && !lower.endsWith('.webp')) {
      throw new Error('主页包预览图必须是 PNG、JPEG 或 WebP 图片。');
    }
  }

  private looksLikePreviewImage(bytes: number[]): boolean {
    if (bytes.length >= 8 &&
      bytes[0] === 0x89 &&
      bytes[1] === 0x50 &&
      bytes[2] === 0x4E &&
      bytes[3] === 0x47) {
      return true;
    }
    if (bytes.length >= 3 && bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) {
      return true;
    }
    return bytes.length >= 12 &&
      bytes[0] === 0x52 &&
      bytes[1] === 0x49 &&
      bytes[2] === 0x46 &&
      bytes[3] === 0x46 &&
      bytes[8] === 0x57 &&
      bytes[9] === 0x45 &&
      bytes[10] === 0x42 &&
      bytes[11] === 0x50;
  }

  private buildItemId(now: number): string {
    return `home_${now}_${Math.floor(Math.random() * 1000000)}`;
  }

  private stringifyError(error: Object | undefined): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return JSON.stringify(error);
  }

  private normalizePackageImportError(error: Object | undefined): Error {
    if (error instanceof CustomHomepagePackageImportError) {
      return error;
    }
    return new Error(this.stringifyError(error));
  }

  private buildCleanupFailureError(
    operationError: Error,
    cleanupError: Object | undefined,
    targetLabel: string
  ): Error {
    return new Error(
      `${operationError.message} ${targetLabel}清理失败：${this.stringifyError(cleanupError)}`
    );
  }
}
