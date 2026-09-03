import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import buffer from '@ohos.buffer';
import { BookmarkManagementFeature } from '../../features/bookmarks/BookmarkManagementFeature';

export interface BookmarkHtmlTransferApplicationResult {
  completed: boolean;
  cancelled: boolean;
  title: string;
  message: string;
}

/** Platform boundary for bookmark HTML picker and file IO. */
export class BookmarkHtmlTransferApplicationService {
  private readonly bookmarkManagementFeature: BookmarkManagementFeature;

  constructor(bookmarkManagementFeature: BookmarkManagementFeature) {
    this.bookmarkManagementFeature = bookmarkManagementFeature;
  }

  async importHtml(context: common.UIAbilityContext): Promise<BookmarkHtmlTransferApplicationResult> {
    try {
      const uri = await this.pickOpenUri(context);
      if (uri.length <= 0) {
        return this.cancelledResult('已取消导入');
      }
      const payload = await this.readTextFromUri(uri);
      const result = await this.bookmarkManagementFeature.applyHtmlImport(payload);
      return {
        completed: true,
        cancelled: false,
        title: '导入成功',
        message: result.summary
      };
    } catch (error) {
      return this.failureResult('导入失败', error as Error);
    }
  }

  async exportHtml(context: common.UIAbilityContext): Promise<BookmarkHtmlTransferApplicationResult> {
    try {
      const uri = await this.pickSaveUri(context, `aira-bookmarks-${this.resolveFileTimestamp()}.html`);
      if (uri.length <= 0) {
        return this.cancelledResult('已取消导出');
      }
      await this.bookmarkManagementFeature.refresh();
      const payload = this.bookmarkManagementFeature.buildHtmlExport();
      await this.writeTextToUri(uri, payload);
      return {
        completed: true,
        cancelled: false,
        title: '导出成功',
        message: '书签已导出为浏览器通用 HTML 文件。'
      };
    } catch (error) {
      return this.failureResult('导出失败', error as Error);
    }
  }

  private async pickOpenUri(context: common.UIAbilityContext): Promise<string> {
    const documentPicker = new picker.DocumentViewPicker(context);
    const uris = await documentPicker.select({
      maxSelectNumber: 1,
      fileSuffixFilters: ['.html', '.htm']
    });
    return uris.length > 0 ? uris[0] : '';
  }

  private async pickSaveUri(context: common.UIAbilityContext, fileName: string): Promise<string> {
    const documentPicker = new picker.DocumentViewPicker(context);
    const uris = await documentPicker.save({
      newFileNames: [fileName],
      fileSuffixChoices: ['HTML|.html']
    });
    return uris.length > 0 ? uris[0] : '';
  }

  private async readTextFromUri(uri: string): Promise<string> {
    return readBookmarkTextFromUri(uri);
  }

  private async writeTextToUri(uri: string, payload: string): Promise<void> {
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

  private cancelledResult(message: string): BookmarkHtmlTransferApplicationResult {
    return {
      completed: false,
      cancelled: true,
      title: '',
      message: message
    };
  }

  private failureResult(title: string, error: Error): BookmarkHtmlTransferApplicationResult {
    return {
      completed: false,
      cancelled: false,
      title: title,
      message: error.message.length > 0 ? error.message : '未知错误'
    };
  }
}

/** Read the complete UTF-8 byte stream before decoding so chunk boundaries cannot corrupt text. */
export async function readBookmarkTextFromUri(uri: string): Promise<string> {
  const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  const chunkSize = 64 * 1024;
  try {
    let bytesRead = 0;
    do {
      const data = new ArrayBuffer(chunkSize);
      bytesRead = await fileIo.read(file.fd, data);
      if (bytesRead > 0) {
        const chunk = new Uint8Array(bytesRead);
        chunk.set(new Uint8Array(data, 0, bytesRead));
        chunks.push(chunk);
        totalBytes += bytesRead;
      }
    } while (bytesRead > 0);
  } finally {
    await fileIo.close(file);
  }
  if (totalBytes === 0) {
    return '';
  }
  const merged = new Uint8Array(totalBytes);
  let offset = 0;
  chunks.forEach((chunk: Uint8Array): void => {
    merged.set(chunk, offset);
    offset += chunk.byteLength;
  });
  return buffer.from(merged.buffer, merged.byteOffset, merged.byteLength).toString('utf8');
}
