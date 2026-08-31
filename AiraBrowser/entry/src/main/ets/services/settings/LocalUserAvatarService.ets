import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

const LOCAL_USER_AVATAR_DIR_NAME: string = 'local-user-avatar';
const LOCAL_USER_AVATAR_FILE_PREFIX: string = 'avatar-';
const LOCAL_USER_AVATAR_MAX_BYTES: number = 10 * 1024 * 1024;

export class LocalUserAvatarService {
  pickAvatarImageUri(context: common.UIAbilityContext): Promise<string | undefined> {
    const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    photoSelectOptions.maxSelectNumber = 1;
    const photoPicker = new photoAccessHelper.PhotoViewPicker();
    return photoPicker.select(photoSelectOptions)
      .then((result: photoAccessHelper.PhotoSelectResult) => {
        return result.photoUris.length > 0 ? result.photoUris[0] : undefined;
      });
  }

  async pickAndSaveAvatarImage(context: common.UIAbilityContext): Promise<string> {
    const uri = await this.pickAvatarImageUri(context);
    return uri === undefined ? '' : await this.saveAvatarImage(uri);
  }

  async saveAvatarImage(sourceUri: string): Promise<string> {
    const normalizedSourceUri = sourceUri.trim();
    if (normalizedSourceUri.length === 0) {
      throw new Error('未选择头像图片。');
    }

    await this.ensureDirectory(this.getAvatarDir());
    const extension = this.resolveImageExtension(normalizedSourceUri);
    const targetPath = `${this.getAvatarDir()}/${LOCAL_USER_AVATAR_FILE_PREFIX}${Date.now()}.${extension}`;
    const tempPath = `${targetPath}.tmp`;
    await this.deleteIfExists(tempPath);
    await fileIo.copy(normalizedSourceUri, fileUri.getUriFromPath(tempPath));
    try {
      await this.ensureUsableAvatarImage(tempPath);
      await this.deleteExistingAvatarImages();
      await this.moveFile(tempPath, targetPath);
      return fileUri.getUriFromPath(targetPath);
    } catch (error) {
      await this.deleteIfExists(tempPath);
      throw new Error(this.stringifyError(error));
    }
  }

  async getAvatarImageUri(): Promise<string> {
    const path = await this.findLatestAvatarImagePath();
    return path.length > 0 ? fileUri.getUriFromPath(path) : '';
  }

  private async ensureUsableAvatarImage(path: string): Promise<void> {
    const stat = await fileIo.stat(path);
    if (stat.isDirectory() || stat.size <= 0) {
      throw new Error('头像图片不可用。');
    }
    if (stat.size > LOCAL_USER_AVATAR_MAX_BYTES) {
      throw new Error('头像图片超过 10 MB。');
    }
    const sample = await this.readFileSample(path);
    if (!this.isLikelyImagePayload(sample)) {
      throw new Error('请选择 PNG、JPG 或 WebP 图片。');
    }
  }

  private async readFileSample(path: string): Promise<ArrayBuffer> {
    const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    try {
      const buffer = new ArrayBuffer(512);
      const readLength = await fileIo.read(file.fd, buffer);
      return readLength > 0 ? buffer.slice(0, readLength) : new ArrayBuffer(0);
    } finally {
      await fileIo.close(file);
    }
  }

  private isLikelyImagePayload(data: ArrayBuffer): boolean {
    const bytes = new Uint8Array(data);
    if (bytes.length < 4) {
      return false;
    }
    if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) {
      return true;
    }
    if (bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) {
      return true;
    }
    return bytes.length >= 12 &&
      bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
      bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50;
  }

  private async findLatestAvatarImagePath(): Promise<string> {
    const dir = this.getAvatarDir();
    if (!await this.exists(dir)) {
      return '';
    }
    const files = await fileIo.listFile(dir);
    const candidates = files
      .filter((name: string) => this.isAvatarImageFileName(name))
      .sort()
      .reverse();
    return candidates.length > 0 ? `${dir}/${candidates[0]}` : '';
  }

  private async deleteExistingAvatarImages(): Promise<void> {
    const dir = this.getAvatarDir();
    if (!await this.exists(dir)) {
      return;
    }
    const files = await fileIo.listFile(dir);
    for (let index = 0; index < files.length; index += 1) {
      const fileName = files[index];
      if (this.isAvatarImageFileName(fileName)) {
        await this.deleteIfExists(`${dir}/${fileName}`);
      }
    }
  }

  private isAvatarImageFileName(fileName: string): boolean {
    return fileName.startsWith(LOCAL_USER_AVATAR_FILE_PREFIX) &&
      (fileName.endsWith('.png') || fileName.endsWith('.jpg') || fileName.endsWith('.webp'));
  }

  private async moveFile(sourcePath: string, targetPath: string): Promise<void> {
    try {
      await fileIo.rename(sourcePath, targetPath);
    } catch (_renameError) {
      await fileIo.copyFile(sourcePath, targetPath);
      await fileIo.unlink(sourcePath);
    }
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

  private getAvatarDir(): string {
    return `${AppRuntimeContext.getApplicationContext().filesDir}/${LOCAL_USER_AVATAR_DIR_NAME}`;
  }

  private resolveImageExtension(uri: string): string {
    const normalized = uri.toLowerCase().split('?')[0].split('#')[0];
    if (normalized.endsWith('.webp')) {
      return 'webp';
    }
    if (normalized.endsWith('.jpg') || normalized.endsWith('.jpeg')) {
      return 'jpg';
    }
    return 'png';
  }

  private stringifyError(error: Object | undefined): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return JSON.stringify(error);
  }
}
