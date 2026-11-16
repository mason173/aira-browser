import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { qrcodegen } from './vendor/QrCodeGenerator';

export interface WebPageQrCodeImage {
  png: ArrayBuffer;
  source: string;
}

const QR_IMAGE_SIZE_PX: number = 768;
const QR_QUIET_ZONE_MODULES: number = 4;
// Version 40-L capacity with the UTF-8 ECI and byte-mode headers.
const QR_MAX_UTF8_BYTES: number = 2952;

export class WebPageQrCodeService {
  async generate(url: string): Promise<WebPageQrCodeImage> {
    const pixelMap = await this.createQrPixelMap(url);
    let packer: image.ImagePacker | undefined;
    try {
      packer = image.createImagePacker();
      const png = await packer.packToData(pixelMap, { format: 'image/png', quality: 100 });
      const base64 = new util.Base64Helper().encodeToStringSync(new Uint8Array(png));
      return { png: png, source: `data:image/png;base64,${base64}` };
    } finally {
      await packer?.release().catch((_error: Error): void => {});
      await pixelMap.release().catch((_error: Error): void => {});
    }
  }

  private async createQrPixelMap(url: string): Promise<image.PixelMap> {
    if (url.length === 0 || url.length > QR_MAX_UTF8_BYTES) {
      throw new RangeError('qr-link-length');
    }
    const bytes = util.TextEncoder.create('utf-8').encodeInto(url);
    if (bytes.length > QR_MAX_UTF8_BYTES) {
      throw new RangeError('qr-link-length');
    }
    const qr = qrcodegen.QrCode.encodeSegments([
      qrcodegen.QrSegment.makeEci(26), // UTF-8
      qrcodegen.QrSegment.makeBytes(Array.from(bytes))
    ], qrcodegen.QrCode.Ecc.LOW);
    const moduleCount = qr.size + QR_QUIET_ZONE_MODULES * 2;
    const scale = Math.floor(QR_IMAGE_SIZE_PX / moduleCount);
    const size = moduleCount * scale;
    const pixels = new Uint8Array(size * size * 4);
    pixels.fill(255);

    for (let row = 0; row < qr.size; row++) {
      for (let column = 0; column < qr.size; column++) {
        if (!qr.getModule(column, row)) {
          continue;
        }
        const left = (column + QR_QUIET_ZONE_MODULES) * scale;
        const top = (row + QR_QUIET_ZONE_MODULES) * scale;
        for (let y = top; y < top + scale; y++) {
          let index = (y * size + left) * 4;
          for (let x = 0; x < scale; x++, index += 4) {
            pixels[index] = 0;
            pixels[index + 1] = 0;
            pixels[index + 2] = 0;
          }
        }
      }
    }
    return image.createPixelMapFromPixels(pixels.buffer as ArrayBuffer, {
      size: { width: size, height: size },
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: image.AlphaType.OPAQUE
    });
  }

  async saveToGallery(context: common.UIAbilityContext, qr: WebPageQrCodeImage): Promise<boolean> {
    const path = `${context.cacheDir}/aira-qr-${util.generateRandomUUID()}.png`;
    try {
      const source = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE |
        fileIo.OpenMode.TRUNC);
      try {
        let offset = 0;
        while (offset < qr.png.byteLength) {
          const written = await fileIo.write(source.fd, qr.png.slice(offset), { offset: offset });
          if (written <= 0) {
            throw new Error('qr-image-write-stalled');
          }
          offset += written;
        }
      } finally {
        await fileIo.close(source);
      }

      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const savedUris = await helper.showAssetsCreationDialog([fileUri.getUriFromPath(path)], [{
        title: 'Aira-QR',
        fileNameExtension: 'png',
        photoType: photoAccessHelper.PhotoType.IMAGE
      }]);
      if (savedUris.length === 0) {
        return false;
      }
      const destination = await fileIo.open(savedUris[0], fileIo.OpenMode.WRITE_ONLY);
      try {
        await fileIo.copyFile(path, destination.fd);
      } finally {
        await fileIo.close(destination);
      }
      return true;
    } finally {
      await fileIo.unlink(path).catch((_error: Error): void => {});
    }
  }
}
