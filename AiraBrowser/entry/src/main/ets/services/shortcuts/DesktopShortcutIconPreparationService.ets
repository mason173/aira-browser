import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';

const DESKTOP_SHORTCUT_ICON_MAX_BYTES: number = 100 * 1024;
const DESKTOP_SHORTCUT_ICON_EDGE_LENGTHS: number[] = [512, 384, 256, 192, 128];

export class DesktopShortcutIconPreparationService {
  async prepare(sourceUri: string, targetPath: string): Promise<string> {
    const normalizedSourceUri = sourceUri.trim();
    const normalizedTargetPath = targetPath.trim();
    if (normalizedSourceUri.length === 0 || normalizedTargetPath.length === 0) {
      throw new Error('未提供可用的桌面图标。');
    }
    if (this.toFilePath(normalizedSourceUri) === normalizedTargetPath) {
      throw new Error('桌面图标来源与输出路径不能相同。');
    }

    let sourceFile: fileIo.File | undefined = undefined;
    let imageSource: image.ImageSource | undefined = undefined;
    const imagePacker = image.createImagePacker();
    let completed = false;
    try {
      sourceFile = await fileIo.open(normalizedSourceUri, fileIo.OpenMode.READ_ONLY);
      imageSource = image.createImageSource(sourceFile.fd);
      const imageInfo = await imageSource.getImageInfo();
      const sourceWidth = Math.floor(imageInfo.size.width);
      const sourceHeight = Math.floor(imageInfo.size.height);
      if (sourceWidth <= 0 || sourceHeight <= 0) {
        throw new Error('这张图片的尺寸不可用。');
      }
      const cropSize = Math.min(sourceWidth, sourceHeight);
      const cropRegion: image.Region = {
        x: Math.floor((sourceWidth - cropSize) / 2),
        y: Math.floor((sourceHeight - cropSize) / 2),
        size: {
          width: cropSize,
          height: cropSize
        }
      };
      for (let index = 0; index < DESKTOP_SHORTCUT_ICON_EDGE_LENGTHS.length; index += 1) {
        const edgeLength = DESKTOP_SHORTCUT_ICON_EDGE_LENGTHS[index];
        const pixelMap = await imageSource.createPixelMap({
          index: 0,
          desiredRegion: cropRegion,
          desiredSize: {
            width: edgeLength,
            height: edgeLength
          },
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
          cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST
        });
        try {
          await this.packPixelMap(normalizedTargetPath, pixelMap, imagePacker);
        } finally {
          await this.releasePixelMap(pixelMap);
        }
        if (await this.isValidPreparedFile(normalizedTargetPath)) {
          completed = true;
          return normalizedTargetPath;
        }
      }
      throw new Error('这张图片无法压缩到鸿蒙桌面图标要求，请换一张再试。');
    } catch (error) {
      if (error instanceof Error && error.message.trim().length > 0) {
        throw error;
      }
      throw new Error('无法处理这张图片，请换一张再试。');
    } finally {
      try {
        await imagePacker.release();
      } catch (_error) {
      }
      if (imageSource !== undefined) {
        try {
          await imageSource.release();
        } catch (_error) {
        }
      }
      if (sourceFile !== undefined) {
        try {
          await fileIo.close(sourceFile);
        } catch (_error) {
        }
      }
      if (!completed) {
        await this.deleteIfExists(normalizedTargetPath);
      }
    }
  }

  private async isValidPreparedFile(path: string): Promise<boolean> {
    try {
      const stat = await fileIo.stat(path);
      return !stat.isDirectory() && stat.size > 0 && stat.size <= DESKTOP_SHORTCUT_ICON_MAX_BYTES;
    } catch (_error) {
      return false;
    }
  }

  private async packPixelMap(
    targetPath: string,
    pixelMap: image.PixelMap,
    packer: image.ImagePacker
  ): Promise<void> {
    const outputFile = await fileIo.open(
      targetPath,
      fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    );
    try {
      await packer.packToFile(pixelMap, outputFile.fd, {
        format: 'image/png',
        quality: 100
      });
    } finally {
      await fileIo.close(outputFile);
    }
  }

  private async releasePixelMap(pixelMap: image.PixelMap): Promise<void> {
    try {
      await pixelMap.release();
    } catch (_error) {
    }
  }

  private async deleteIfExists(path: string): Promise<void> {
    try {
      if (await fileIo.access(path)) {
        await fileIo.unlink(path);
      }
    } catch (_error) {
    }
  }

  private toFilePath(uri: string): string {
    const normalized = uri.trim();
    return normalized.startsWith('file://') ? normalized.substring(7) : normalized;
  }
}
