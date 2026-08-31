import { fileIo } from '@kit.CoreFileKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

export interface WebStateSnapshotRecord {
  path: string;
  updatedAt: number;
  size: number;
}

const SNAPSHOT_DIR_NAME = 'web-tab-snapshots';
const SNAPSHOT_CHUNK_SIZE = 64 * 1024;

export class WebStateSnapshotStore {
  async saveSnapshot(tabId: string, payload: Uint8Array): Promise<WebStateSnapshotRecord | undefined> {
    if (tabId.trim().length === 0 || payload.byteLength === 0) {
      return undefined;
    }

    const path = this.buildSnapshotPath(tabId);
    await this.ensureSnapshotDir();
    const file = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      const content = payload.byteOffset === 0 && payload.byteLength === payload.buffer.byteLength
        ? payload.buffer
        : payload.buffer.slice(payload.byteOffset, payload.byteOffset + payload.byteLength);
      await fileIo.write(file.fd, content);
    } finally {
      await fileIo.close(file);
    }

    return {
      path: path,
      updatedAt: Date.now(),
      size: payload.byteLength
    };
  }

  async loadSnapshot(path: string): Promise<Uint8Array | undefined> {
    if (path.trim().length === 0 || !await this.exists(path)) {
      return undefined;
    }

    const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    const chunks: Uint8Array[] = [];
    let totalSize = 0;
    try {
      let bytesRead = 0;
      do {
        const data = new ArrayBuffer(SNAPSHOT_CHUNK_SIZE);
        bytesRead = await fileIo.read(file.fd, data);
        if (bytesRead > 0) {
          const source = new Uint8Array(data, 0, bytesRead);
          const bytes = new Uint8Array(bytesRead);
          bytes.set(source);
          chunks.push(bytes);
          totalSize += bytesRead;
        }
      } while (bytesRead === SNAPSHOT_CHUNK_SIZE);
    } finally {
      await fileIo.close(file);
    }

    if (totalSize === 0) {
      return undefined;
    }

    const merged = new Uint8Array(totalSize);
    let offset = 0;
    chunks.forEach((chunk: Uint8Array) => {
      merged.set(chunk, offset);
      offset += chunk.byteLength;
    });
    return merged;
  }

  async deleteSnapshot(path: string): Promise<void> {
    await this.deleteSnapshotIfExists(path);
  }

  async deleteSnapshotIfExists(path: string): Promise<boolean> {
    if (path.trim().length === 0 || !await this.exists(path)) {
      return false;
    }

    try {
      await fileIo.unlink(path);
      return true;
    } catch (_error) {
      return false;
    }
  }

  private async ensureSnapshotDir(): Promise<void> {
    const dir = this.getSnapshotDir();
    if (await this.exists(dir)) {
      return;
    }

    try {
      await fileIo.mkdir(dir, true);
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

  private buildSnapshotPath(tabId: string): string {
    return `${this.getSnapshotDir()}/${this.sanitizeTabId(tabId)}.bin`;
  }

  private getSnapshotDir(): string {
    return `${AppRuntimeContext.getApplicationContext().cacheDir}/${SNAPSHOT_DIR_NAME}`;
  }

  private sanitizeTabId(tabId: string): string {
    return tabId.trim().replace(/[^a-zA-Z0-9._-]/g, '_');
  }
}
