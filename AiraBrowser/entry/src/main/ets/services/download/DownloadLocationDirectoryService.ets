import { common } from '@kit.AbilityKit';
import { fileIo, fileShare, fileUri, picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { BrowserDownloadSettings } from '../../common/models/BrowserModels';
import { resolveAppResourceText } from '../../core/resources/AppResourceText';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

const DOWNLOAD_DIRECTORY_DOMAIN = 0x0000;
const DOWNLOAD_DIRECTORY_TAG = 'DownloadLocationDirectory';

// PolicyInfo permits CREATE_MODE only for temporary grants. A persisted parent
// directory's WRITE_MODE already covers creating children; keep this same
// read/write policy for persistence, activation and revocation.
const DOWNLOAD_DIRECTORY_OPERATION_MODE: number =
  fileShare.OperationMode.READ_MODE |
  fileShare.OperationMode.WRITE_MODE;
const DOWNLOAD_DIRECTORY_URI_MAX_LENGTH: number = 2048;
const DOWNLOAD_DIRECTORY_LABEL_MAX_LENGTH: number = 80;
const DOWNLOAD_DIRECTORY_LOCATION_TAIL_SEGMENTS: number = 2;
const DOWNLOAD_DIRECTORY_PROBE_FILE_PREFIX: string = '.aira-write-probe-';
const DOWNLOAD_DIRECTORY_PROBE_PAYLOAD: string = 'aira-probe';

export interface DownloadLocationDirectorySelection {
  uri: string;
  label: string;
}

/**
 * The picker can end in three genuinely different states, and the caller has to
 * tell them apart: nothing chosen, a folder we can write to, or a folder the
 * platform handed back but we cannot use. Collapsing the last one into
 * "undefined" used to make an unusable selection look like a cancel.
 */
export type DownloadLocationSelectionStatus =
  'selected' |
  'cancelled' |
  'unusable_folder';

export interface DownloadLocationSelectionResult {
  status: DownloadLocationSelectionStatus;
  selection?: DownloadLocationDirectorySelection;
  /** True when the platform will still honour this folder after a restart. */
  isPersisted: boolean;
  diagnosticMessage: string;
}

export interface DownloadDirectoryActivationResult {
  /** Whether the folder can be written to right now. */
  usable: boolean;
  /** Whether the grant survives an app restart. */
  isPersisted: boolean;
  /** True when the platform has no folder-authorization capability at all. */
  capabilityMissing: boolean;
  diagnosticMessage: string;
}

export interface DownloadCustomDirectory {
  uri: string;
  /** Ambiguity-free tail of the folder path, e.g. `Download/Aira`. */
  label: string;
}



/**
 * The full picker URI is far too long for a settings row, so this keeps the
 * tail of the path. A bare folder name is ambiguous (`Download` exists under
 * several roots), and the tail is what lets a user tell two folders apart.
 */
export function buildDownloadDirectoryLocationLabel(uri: string): string {
  const segments = resolveDecodedDirectorySegments(uri);
  if (segments.length === 0) {
    return resolveAppResourceText($r('app.string.download_custom_location'));
  }
  return segments.slice(-DOWNLOAD_DIRECTORY_LOCATION_TAIL_SEGMENTS).join('/');
}

function resolveDecodedDirectorySegments(uri: string): string[] {
  let normalized = uri.trim();
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  if (normalized.length === 0) {
    return [];
  }
  const segments: string[] = [];
  const rawSegments = normalized.split('/');
  for (let index = 0; index < rawSegments.length; index += 1) {
    const rawSegment = rawSegments[index];
    if (rawSegment.length === 0) {
      continue;
    }
    let decodedSegment = rawSegment;
    try {
      decodedSegment = decodeURIComponent(rawSegment);
    } catch (_error) {
      decodedSegment = rawSegment;
    }
    const trimmedSegment = decodedSegment.trim();
    // Scheme segments such as `file:` carry no location value; only keep real path parts.
    if (trimmedSegment.length === 0 || trimmedSegment.includes(':')) {
      continue;
    }
    segments.push(trimmedSegment);
  }
  return segments;
}

export function resolveCustomDownloadDirectory(
  settings: BrowserDownloadSettings
): DownloadCustomDirectory | undefined {
  if (settings.defaultLocation !== 'custom') {
    return undefined;
  }
  const uri = settings.customLocationUri.trim();
  if (uri.length === 0 || uri.length > DOWNLOAD_DIRECTORY_URI_MAX_LENGTH || uri.indexOf('://') <= 0) {
    return undefined;
  }
  const storedLabel = settings.customLocationLabel.trim();
  return {
    uri: uri,
    label: storedLabel.length > 0
      ? storedLabel.slice(0, DOWNLOAD_DIRECTORY_LABEL_MAX_LENGTH)
      : buildDownloadDirectoryLocationLabel(uri)
  };
}

export class DownloadLocationDirectoryService {
  /**
   * Picks a folder through the system file picker.
   *
   * This deliberately uses `select()` with `DocumentSelectMode.FOLDER`, NOT
   * `save()` with `DocumentPickerMode.DOWNLOAD`. Per the official guide
   * (harmonyos-guides/save-user-file) DOWNLOAD mode "skips the file selection
   * screen and saves directly" into `Download/<bundle>/` — it never shows a
   * folder picker, so asking a user to choose a location with it was a no-op.
   */
  async selectDirectory(
    context: common.UIAbilityContext
  ): Promise<DownloadLocationSelectionResult> {
    const uris = await this.pickFolderUri(context);
    if (uris === undefined) {
      return {
        status: 'cancelled',
        isPersisted: false,
        diagnosticMessage: 'picker returned no folder'
      };
    }
    const uri = this.normalizeDirectoryUri(uris);
    if (!this.isAcceptableDirectoryUri(uri)) {
      hilog.warn(
        DOWNLOAD_DIRECTORY_DOMAIN,
        DOWNLOAD_DIRECTORY_TAG,
        'picker returned an unusable folder uri=%{public}s',
        uri
      );
      return {
        status: 'unusable_folder',
        isPersisted: false,
        diagnosticMessage: `unusable folder uri=${uri}`
      };
    }
    const isPersisted = await this.persistDirectory(uri);
    return {
      status: 'selected',
      selection: {
        uri: uri,
        // Store the ambiguity-free tail, not the bare folder name: `Download`
        // alone cannot be told apart from another `Download` elsewhere.
        label: this.buildDirectoryLocationLabel(uri)
      },
      isPersisted: isPersisted,
      diagnosticMessage: isPersisted
        ? 'folder persisted'
        : 'folder selected but permission could not be persisted'
    };
  }

  /**
   * `DocumentSelectMode.FOLDER` only gained phone support in API 26.0.0 and
   * reports itself through the FolderSelection system capability, so both have
   * to be checked before promising the user a folder picker. When it is absent
   * the caller should fall back to the save picker instead of opening a picker
   * that cannot select folders.
   */
  isFolderSelectionSupported(): boolean {
    return canIUse('SystemCapability.FileManagement.UserFileService.FolderSelection');
  }

  private async pickFolderUri(context: common.UIAbilityContext): Promise<string | undefined> {
    const selectOptions = new picker.DocumentSelectOptions();
    selectOptions.selectMode = picker.DocumentSelectMode.FOLDER;
    selectOptions.maxSelectNumber = 1;
    const documentPicker = new picker.DocumentViewPicker(context);
    const uris = await documentPicker.select(selectOptions);
    if (uris.length <= 0) {
      return undefined;
    }
    return uris[0];
  }

  /**
   * Activation is a best-effort refresh of a persisted grant. A failure here
   * does not mean the folder is unwritable: the picker grant is still live for
   * this session, and on devices without the folder-authorization capability
   * there is nothing to activate at all. Callers must not treat a false
   * `usable` as "give up" — they should try the write and let that decide.
   */
  async activateDirectory(uri: string): Promise<DownloadDirectoryActivationResult> {
    if (!this.isAcceptableDirectoryUri(uri)) {
      return {
        usable: false,
        isPersisted: false,
        capabilityMissing: false,
        diagnosticMessage: `unacceptable folder uri=${uri}`
      };
    }
    if (!this.isFolderAuthorizationSupported()) {
      return {
        usable: true,
        isPersisted: false,
        capabilityMissing: true,
        diagnosticMessage: 'folder authorization capability is absent on this device'
      };
    }
    try {
      await fileShare.activatePermission([this.buildPolicy(uri)]);
      return {
        usable: true,
        isPersisted: true,
        capabilityMissing: false,
        diagnosticMessage: 'folder permission activated'
      };
    } catch (error) {
      const diagnosticMessage = this.stringifyError(error);
      hilog.warn(
        DOWNLOAD_DIRECTORY_DOMAIN,
        DOWNLOAD_DIRECTORY_TAG,
        'activate folder permission failed uri=%{public}s error=%{public}s',
        uri,
        diagnosticMessage
      );
      return {
        usable: false,
        isPersisted: false,
        capabilityMissing: false,
        diagnosticMessage: `activate failed: ${diagnosticMessage}`
      };
    }
  }

  async releaseDirectory(uri: string): Promise<void> {
    if (!this.isAcceptableDirectoryUri(uri) || !this.isFolderAuthorizationSupported()) {
      return;
    }
    try {
      await fileShare.revokePermission([this.buildPolicy(uri)]);
    } catch (error) {
      hilog.warn(
        DOWNLOAD_DIRECTORY_DOMAIN,
        DOWNLOAD_DIRECTORY_TAG,
        'revoke folder permission failed uri=%{public}s error=%{public}s',
        uri,
        this.stringifyError(error)
      );
    }
  }

  /**
   * The full picker URI is far too long for a settings row, so this keeps the
   * tail of the path. A bare folder name is ambiguous (`Download` exists under
   * several roots), and the tail is what lets a user tell two folders apart.
   */
  buildDirectoryLocationLabel(uri: string): string {
    return buildDownloadDirectoryLocationLabel(uri);
  }

  private async persistDirectory(uri: string): Promise<boolean> {
    if (!this.isFolderAuthorizationSupported()) {
      return false;
    }
    try {
      await fileShare.persistPermission([this.buildPolicy(uri)]);
      return true;
    } catch (error) {
      hilog.warn(
        DOWNLOAD_DIRECTORY_DOMAIN,
        DOWNLOAD_DIRECTORY_TAG,
        'persist folder permission failed uri=%{public}s error=%{public}s',
        uri,
        this.stringifyError(error)
      );
      return false;
    }
  }

  private stringifyError(error: Object | Error | undefined | null): string {
    if (error === undefined || error === null) {
      return 'unknown';
    }
    const businessError = error as BusinessError<fileShare.PolicyErrorResult[]>;
    if (businessError.code !== undefined && businessError.message !== undefined) {
      const policyFailures = businessError.data;
      const detail = policyFailures !== undefined && policyFailures.length > 0
        ? policyFailures.map((failure: fileShare.PolicyErrorResult): string =>
          `${failure.code}:${failure.message}`).join('; ')
        : '';
      return `code=${businessError.code} message=${businessError.message}` +
        (detail.length > 0 ? ` policies=${detail}` : '');
    }
    if (error instanceof Error) {
      return error.message;
    }
    try {
      return JSON.stringify(error);
    } catch (_jsonError) {
      return String(error);
    }
  }

  private normalizeDirectoryUri(uri: string): string {
    let normalized = uri.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  private buildPolicy(uri: string): fileShare.PolicyInfo {
    return {
      uri: uri,
      operationMode: DOWNLOAD_DIRECTORY_OPERATION_MODE
    };
  }

  private isFolderAuthorizationSupported(): boolean {
    return canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization');
  }

  private isAcceptableDirectoryUri(uri: string): boolean {
    const trimmed = uri.trim();
    return trimmed.length > 0 &&
      trimmed.length <= DOWNLOAD_DIRECTORY_URI_MAX_LENGTH &&
      trimmed.indexOf('://') > 0 &&
      trimmed.indexOf('\n') < 0 &&
      trimmed.indexOf('\r') < 0;
  }

  /**
   * Checks current write access, independently of whether the grant is durable.
   * Selection callers keep the user's choice and explain a failed probe; the
   * exporter requires a successful probe before creating the download's name.
   *
   * Both probe transports use URI access to the public folder with real bytes.
   * ENOENT from opening a new child URI is inconclusive: the actual export's
   * URI-copy operation can still create it. Never retry public writes by path
   * after a permission error, since that can leave empty file-manager entries.
   * Keep the selected directory URI untouched and the child name plain ASCII;
   * provider-specific URI failures can still occur and must remain diagnostic.
   */
  async verifyDirectoryWritable(uri: string): Promise<boolean> {
    if (!this.isAcceptableDirectoryUri(uri)) {
      return false;
    }
    // Settings checks and multiple finishing downloads can overlap. Sharing a
    // probe name lets the first cleanup remove the second caller's live probe.
    const probeUri = `${uri}/${DOWNLOAD_DIRECTORY_PROBE_FILE_PREFIX}${util.generateRandomUUID()}`;
    let probeOpened = false;
    let probeFile: fileIo.File | undefined = undefined;
    try {
      const file = await fileIo.open(
        probeUri,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC
      );
      probeFile = file;
      probeOpened = true;
      await fileIo.write(file.fd, DOWNLOAD_DIRECTORY_PROBE_PAYLOAD);
      await fileIo.close(file);
      probeFile = undefined;
      const stat = await fileIo.stat(probeUri);
      if (stat.size !== DOWNLOAD_DIRECTORY_PROBE_PAYLOAD.length) {
        hilog.warn(
          DOWNLOAD_DIRECTORY_DOMAIN,
          DOWNLOAD_DIRECTORY_TAG,
          'write probe size mismatch uri=%{public}s expected=%{public}d actual=%{public}d',
          uri,
          DOWNLOAD_DIRECTORY_PROBE_PAYLOAD.length,
          stat.size
        );
        return false;
      }
      return true;
    } catch (error) {
      const businessError = error as BusinessError;
      if (!probeOpened && businessError.code === 13900002) {
        return await this.verifyDirectoryCopyWritable(uri, probeUri);
      }
      hilog.warn(
        DOWNLOAD_DIRECTORY_DOMAIN,
        DOWNLOAD_DIRECTORY_TAG,
        'folder is not writable uri=%{public}s error=%{public}s',
        uri,
        this.stringifyError(error)
      );
      return false;
    } finally {
      if (probeFile !== undefined) {
        try {
          await fileIo.close(probeFile);
        } catch (_closeError) {
        }
      }
      if (probeOpened) {
        await this.deleteDirectoryProbeFile(probeUri);
      }
    }
  }

  private async verifyDirectoryCopyWritable(directoryUri: string, probeUri: string): Promise<boolean> {
    let sourcePath = '';
    let sourceFile: fileIo.File | undefined = undefined;
    let sourceCreated = false;
    let copyAttempted = false;
    let stage = 'source_open';
    try {
      // Create source bytes inside our sandbox. The destination is checked by
      // the same URI-copy API used to export the real downloaded file.
      const probeName = probeUri.substring(probeUri.lastIndexOf('/') + 1);
      sourcePath = `${AppRuntimeContext.getApplicationContext().cacheDir}/${probeName}`;
      sourceFile = await fileIo.open(sourcePath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      sourceCreated = true;
      stage = 'source_write';
      await fileIo.write(sourceFile.fd, DOWNLOAD_DIRECTORY_PROBE_PAYLOAD);
      await fileIo.close(sourceFile);
      sourceFile = undefined;
      stage = 'uri_copy';
      copyAttempted = true;
      await fileIo.copy(fileUri.getUriFromPath(sourcePath), probeUri);
      stage = 'destination_stat';
      const stat = await fileIo.stat(probeUri);
      const verified = stat.size === DOWNLOAD_DIRECTORY_PROBE_PAYLOAD.length;
      hilog.info(DOWNLOAD_DIRECTORY_DOMAIN, DOWNLOAD_DIRECTORY_TAG,
        'directory copy probe verified=%{public}s size=%{public}d uri=%{public}s',
        String(verified), stat.size, directoryUri);
      return verified;
    } catch (error) {
      hilog.warn(DOWNLOAD_DIRECTORY_DOMAIN, DOWNLOAD_DIRECTORY_TAG,
        'directory copy probe failed stage=%{public}s uri=%{public}s error=%{public}s',
        stage, directoryUri, this.stringifyError(error));
      return false;
    } finally {
      if (sourceFile !== undefined) {
        try {
          await fileIo.close(sourceFile);
        } catch (_closeError) {
        }
      }
      if (copyAttempted) {
        await this.deleteDirectoryProbeFile(probeUri);
      }
      if (sourceCreated) {
        try {
          await fileIo.unlink(sourcePath);
        } catch (error) {
          hilog.warn(DOWNLOAD_DIRECTORY_DOMAIN, DOWNLOAD_DIRECTORY_TAG,
            'local directory probe cleanup failed error=%{public}s', this.stringifyError(error));
        }
      }
    }
  }

  private async deleteDirectoryProbeFile(probeUri: string): Promise<void> {
    try {
      await fileIo.unlink(probeUri);
    } catch (_uriError) {
      try {
        await fileIo.unlink(new fileUri.FileUri(probeUri).path);
      } catch (error) {
        hilog.warn(DOWNLOAD_DIRECTORY_DOMAIN, DOWNLOAD_DIRECTORY_TAG,
          'write probe cleanup failed uri=%{public}s error=%{public}s', probeUri, this.stringifyError(error));
      }
    }
  }
}
