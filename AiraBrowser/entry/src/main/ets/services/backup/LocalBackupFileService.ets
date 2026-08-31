import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import buffer from '@ohos.buffer';

const LOCAL_BACKUP_MAX_BYTES: number = 128 * 1024 * 1024;

export class LocalBackupFileService {
  async pickImportUri(context: common.UIAbilityContext): Promise<string | undefined> {
    const documentPicker = new picker.DocumentViewPicker(context);
    const uris = await documentPicker.select({
      maxSelectNumber: 1,
      fileSuffixFilters: ['.aira-backup', '.json']
    });
    return uris.length > 0 && uris[0].length > 0 ? uris[0] : undefined;
  }

  async pickExportUri(context: common.UIAbilityContext): Promise<string | undefined> {
    const documentPicker = new picker.DocumentViewPicker(context);
    const uris = await documentPicker.save({
      newFileNames: [`aira-backup-${this.resolveFileTimestamp()}.aira-backup`],
      fileSuffixChoices: ['Aira 备份|.aira-backup']
    });
    return uris.length > 0 && uris[0].length > 0 ? uris[0] : undefined;
  }

  async readPayload(uri: string): Promise<string> {
    const stat = await fileIo.stat(uri);
    if (stat.isDirectory() || stat.size <= 0) {
      throw new Error('备份文件为空或不可用。');
    }
    if (stat.size > LOCAL_BACKUP_MAX_BYTES) {
      throw new Error('备份文件超过 128 MB，无法导入。');
    }
    const expectedBytes = Math.floor(stat.size);
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const data = new ArrayBuffer(expectedBytes);
      const bytesRead = await fileIo.read(file.fd, data, { offset: 0, length: expectedBytes });
      if (bytesRead !== expectedBytes) {
        throw new Error('备份文件读取不完整，请重新选择。');
      }
      return buffer.from(data).toString('utf8');
    } finally {
      await fileIo.close(file);
    }
  }

  async writePayload(uri: string, payload: string): Promise<void> {
    if (buffer.from(payload).length > LOCAL_BACKUP_MAX_BYTES) {
      throw new Error('备份内容超过 128 MB，无法导出。');
    }
    const file = await fileIo.open(uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, payload);
    } finally {
      await fileIo.close(file);
    }
  }

  private resolveFileTimestamp(): string {
    return new Date().toISOString()
      .replace(/[:.]/g, '-')
      .replace('T', '_')
      .replace('Z', '');
  }
}
