import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { DesktopShortcutIconPreparationService } from '../shortcuts/DesktopShortcutIconPreparationService';

const WEB_APP_INSTALL_ICON_DRAFT_DIR: string = 'webapp-install-icon-drafts';

export interface WebAppInstallIconSelection {
  filePath: string;
  previewUri: string;
}

export class WebAppInstallIconSelectionService {
  private draftSequence: number = 0;
  private iconPreparationService: DesktopShortcutIconPreparationService;

  constructor(iconPreparationService: DesktopShortcutIconPreparationService =
    new DesktopShortcutIconPreparationService()) {
    this.iconPreparationService = iconPreparationService;
  }

  async pickAndPrepare(context: common.UIAbilityContext): Promise<WebAppInstallIconSelection | undefined> {
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    const picker = new photoAccessHelper.PhotoViewPicker();
    const result = await picker.select(options);
    if (result.photoUris.length === 0) {
      return undefined;
    }
    return await this.prepareSelectedImage(context, result.photoUris[0]);
  }

  async discard(selection: WebAppInstallIconSelection | undefined): Promise<void> {
    if (selection === undefined || selection.filePath.trim().length === 0) {
      return;
    }
    await this.deleteIfExists(selection.filePath);
  }

  private async prepareSelectedImage(
    context: common.UIAbilityContext,
    sourceUri: string
  ): Promise<WebAppInstallIconSelection> {
    const normalizedSourceUri = sourceUri.trim();
    if (normalizedSourceUri.length === 0) {
      throw new Error('未选择应用图标。');
    }
    const directory = `${context.cacheDir}/${WEB_APP_INSTALL_ICON_DRAFT_DIR}`;
    await this.ensureDirectory(directory);
    this.draftSequence += 1;
    const targetPath = `${directory}/icon-${Date.now()}-${this.draftSequence}.png`;
    await this.iconPreparationService.prepare(normalizedSourceUri, targetPath);
    return {
      filePath: targetPath,
      previewUri: fileUri.getUriFromPath(targetPath)
    };
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
}
