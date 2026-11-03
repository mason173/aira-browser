import { buffer, util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  cloneInstalledUserScriptState,
  InstalledUserScriptState,
  UserScriptResourceRecord,
  UserScriptSettings
} from '../../features/userscripts/UserScriptMetadataModels';

interface UserScriptPackagePayload {
  schemaVersion: number;
  source: string;
  requireSources: string[];
  resources: UserScriptResourceRecord[];
}

interface UserScriptPackageEntry {
  metadata: InstalledUserScriptState;
  payloadFile: string;
}

interface UserScriptPackageIndex {
  schemaVersion: number;
  packages: UserScriptPackageEntry[];
  autoUpdateEnabled: boolean;
  updatedAt: number;
}

export interface UserScriptPreparedPackageIndex {
  index: UserScriptPackageIndex;
  settings: UserScriptSettings;
  serialized: string;
}

// Immutable payload files are durable before the small Preferences index references
// them. The index is the only commit point; orphan files are safe to reclaim after
// validating the complete index on the next open. No source is copied on a toggle.
export class UserScriptPackageStorage {
  private entries: UserScriptPackageEntry[] = [];
  private scripts: InstalledUserScriptState[] = [];
  private cleanupPromise: Promise<void> = Promise.resolve();
  private splitLayout: boolean = false;

  async read(raw: string): Promise<UserScriptSettings> {
    let index: UserScriptPackageIndex;
    try {
      index = JSON.parse(raw) as UserScriptPackageIndex;
    } catch (_error) {
      throw new Error('userscript-metadata-invalid-state: invalid-json');
    }
    if (index === undefined || index === null) {
      throw new Error('userscript-metadata-invalid-state: invalid-settings-shape');
    }
    if (index.schemaVersion === undefined) {
      // The repository still validates the legacy document before migration.
      return index as Object as UserScriptSettings;
    }
    if (index.schemaVersion !== 2 || !Array.isArray(index.packages)) {
      throw new Error('userscript-metadata-invalid-state: invalid-package-index');
    }
    const scripts: InstalledUserScriptState[] = [];
    const files: Set<string> = new Set<string>();
    for (const entry of index.packages) {
      if (entry === undefined || entry === null || entry.metadata === undefined || entry.metadata === null ||
        !this.isPayloadFile(entry.payloadFile) || files.has(entry.payloadFile)) {
        throw new Error('userscript-metadata-invalid-state: invalid-package-reference');
      }
      files.add(entry.payloadFile);
      const payload = JSON.parse(await this.readPayload(entry.payloadFile)) as UserScriptPackagePayload;
      if (payload === undefined || payload === null || payload.schemaVersion !== 1 ||
        typeof payload.source !== 'string' || !Array.isArray(payload.requireSources) || !Array.isArray(payload.resources)) {
        throw new Error('userscript-metadata-invalid-state: invalid-package-payload');
      }
      // Preserve the raw metadata for repository validation rather than normalizing
      // malformed fields while hydrating the large fields.
      entry.metadata.source = payload.source;
      entry.metadata.requireSources = payload.requireSources;
      entry.metadata.resources = payload.resources;
      scripts.push(entry.metadata);
    }
    this.entries = index.packages;
    this.splitLayout = true;
    return { scripts: scripts, autoUpdateEnabled: index.autoUpdateEnabled, updatedAt: index.updatedAt };
  }

  usesSplitLayout(): boolean {
    return this.splitLayout;
  }

  acceptLoaded(settings: UserScriptSettings): void {
    this.scripts = settings.scripts;
    if (this.splitLayout) {
      this.cleanupPromise = this.collectOrphans().catch((): void => {});
    }
  }

  async prepare(settings: UserScriptSettings): Promise<UserScriptPreparedPackageIndex> {
    await this.cleanupPromise;
    const entries: UserScriptPackageEntry[] = [];
    for (const script of settings.scripts) {
      const existing = this.entries.find((entry: UserScriptPackageEntry): boolean => entry.metadata.id === script.id);
      const previous = this.scripts.find((candidate: InstalledUserScriptState): boolean => candidate.id === script.id);
      let payloadFile: string;
      if (existing !== undefined && previous !== undefined && this.samePayload(previous, script)) {
        payloadFile = existing.payloadFile;
      } else {
        payloadFile = `${util.generateRandomUUID()}.json`;
        const payload: UserScriptPackagePayload = { schemaVersion: 1, source: script.source,
          requireSources: script.requireSources, resources: script.resources };
        await this.writePayload(payloadFile, JSON.stringify(payload));
      }
      const metadata = cloneInstalledUserScriptState(script);
      metadata.source = '';
      metadata.requireSources = [];
      metadata.resources = [];
      entries.push({ metadata: metadata, payloadFile: payloadFile });
    }
    const index: UserScriptPackageIndex = { schemaVersion: 2, packages: entries,
      autoUpdateEnabled: settings.autoUpdateEnabled, updatedAt: settings.updatedAt };
    return { index: index, settings: settings, serialized: JSON.stringify(index) };
  }

  acceptCommitted(prepared: UserScriptPreparedPackageIndex): void {
    const retired = this.entries.filter((old: UserScriptPackageEntry): boolean =>
      !prepared.index.packages.some((entry: UserScriptPackageEntry): boolean => entry.payloadFile === old.payloadFile));
    this.entries = prepared.index.packages;
    this.scripts = prepared.settings.scripts;
    this.splitLayout = true;
    // Best-effort cleanup is outside the user-visible commit. Failed cleanup and
    // interrupted unpublished writes are retried by collectOrphans on next open.
    this.cleanupPromise = this.removeFiles(retired.map((entry: UserScriptPackageEntry): string => entry.payloadFile))
      .catch((): void => {});
  }

  private samePayload(left: InstalledUserScriptState, right: InstalledUserScriptState): boolean {
    return left.source === right.source && left.requireSources.length === right.requireSources.length &&
      left.requireSources.every((source: string, index: number): boolean => source === right.requireSources[index]) &&
      left.resources.length === right.resources.length && left.resources.every((resource: UserScriptResourceRecord, index: number): boolean => {
        const other = right.resources[index];
        return resource.name === other.name && resource.url === other.url && resource.text === other.text &&
          resource.mimeType === other.mimeType && resource.contentBase64 === other.contentBase64;
      });
  }

  private directory(): string {
    return `${AppRuntimeContext.getApplicationContext().filesDir}/userscript-packages`;
  }

  private isPayloadFile(name: string): boolean {
    return typeof name === 'string' && /^[0-9a-f-]{36}\.json$/.test(name);
  }

  private async writePayload(name: string, text: string): Promise<void> {
    const directory = this.directory();
    if (!await fileIo.access(directory)) {
      await fileIo.mkdir(directory);
    }
    const path = `${directory}/${name}`;
    if (await fileIo.access(path)) {
      throw new Error('userscript-package-name-collision');
    }
    const file = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE);
    try {
      const written = await fileIo.write(file.fd, text);
      if (written !== buffer.from(text, 'utf8').length) {
        throw new Error('userscript-package-short-write');
      }
      await fileIo.fsync(file.fd);
    } finally {
      await fileIo.close(file);
    }
    if (await this.readPayload(name) !== text) {
      throw new Error('userscript-package-write-verification-failed');
    }
  }

  private async readPayload(name: string): Promise<string> {
    const path = `${this.directory()}/${name}`;
    const size = (await fileIo.stat(path)).size;
    if (size <= 0 || size > 256 * 1024 * 1024) {
      throw new Error('userscript-metadata-invalid-state: invalid-package-size');
    }
    const bytes = new ArrayBuffer(size);
    const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    try {
      if (await fileIo.read(file.fd, bytes) !== size) {
        throw new Error('userscript-package-short-read');
      }
    } finally {
      await fileIo.close(file);
    }
    return buffer.from(bytes).toString('utf8');
  }

  private async collectOrphans(): Promise<void> {
    const directory = this.directory();
    if (!await fileIo.access(directory)) {
      return;
    }
    const files = await fileIo.listFile(directory);
    await this.removeFiles(files.filter((name: string): boolean => this.isPayloadFile(name) &&
      !this.entries.some((entry: UserScriptPackageEntry): boolean => entry.payloadFile === name)));
  }

  private async removeFiles(files: string[]): Promise<void> {
    for (const name of files) {
      const path = `${this.directory()}/${name}`;
      if (await fileIo.access(path)) {
        await fileIo.unlink(path);
      }
    }
  }
}
