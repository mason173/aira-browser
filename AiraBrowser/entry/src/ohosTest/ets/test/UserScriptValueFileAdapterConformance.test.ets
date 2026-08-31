import { buffer } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { afterAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { UserScriptValueFileAdapter } from '../../../main/ets/data/userscripts/UserScriptValueFileAdapter';

const TEST_DIR_NAME: string = 'userscript-value-file-adapter-conformance';
const TEST_FILE_NAME: string = 'values.json';
const LARGE_PAYLOAD_BYTES: number = 8 * 1024 * 1024;

function resolveTestRoot(): string {
  return `${abilityDelegatorRegistry.getAbilityDelegator().getAppContext().filesDir}/${TEST_DIR_NAME}`;
}

function resolveTestFilePath(): string {
  return `${resolveTestRoot()}/${TEST_FILE_NAME}`;
}

function resolveTestPreviousFilePath(): string {
  return `${resolveTestFilePath()}.previous`;
}

function encodeUtf8(value: string): Uint8Array {
  const encoded = buffer.from(value, 'utf8');
  return new Uint8Array(encoded.buffer.slice(encoded.byteOffset, encoded.byteOffset + encoded.length));
}

function createLargePayload(): Uint8Array {
  const payload = new Uint8Array(LARGE_PAYLOAD_BYTES);
  for (let index = 0; index < payload.byteLength; index += 1) {
    payload[index] = index % 251;
  }
  return payload;
}

function bytesEqual(actual: Uint8Array | undefined, expected: Uint8Array): boolean {
  if (actual === undefined || actual.byteLength !== expected.byteLength) {
    return false;
  }
  for (let index = 0; index < expected.byteLength; index += 1) {
    if (actual[index] !== expected[index]) {
      return false;
    }
  }
  return true;
}

async function removeTestFile(): Promise<void> {
  const path = resolveTestFilePath();
  if (await fileIo.access(path)) {
    await fileIo.unlink(path);
  }
  const previousPath = resolveTestPreviousFilePath();
  if (await fileIo.access(previousPath)) {
    await fileIo.unlink(previousPath);
  }
}

export default function userScriptValueFileAdapterConformanceTest(): void {
  describe('UserScriptValueFileAdapter device conformance', () => {
    beforeEach(async () => {
      await removeTestFile();
    });

    afterAll(async () => {
      await removeTestFile();
      const root = resolveTestRoot();
      if (await fileIo.access(root)) {
        await fileIo.rmdir(root);
      }
    });

    it('persists small and large replacements, overwrites, empty snapshots, and reopens', 0, async () => {
      const path = resolveTestFilePath();
      const adapter = new UserScriptValueFileAdapter(path);
      const small = encodeUtf8('{"schemaVersion":1,"revision":1,"values":[],"updatedAt":1}');
      await adapter.replaceCommitted(small);
      expect(bytesEqual(await new UserScriptValueFileAdapter(path).readCommitted(), small)).assertTrue();

      const large = createLargePayload();
      await adapter.replaceCommitted(large);
      expect(bytesEqual(await new UserScriptValueFileAdapter(path).readFallbackCommitted(), small)).assertTrue();
      expect(bytesEqual(await new UserScriptValueFileAdapter(path).readCommitted(), large)).assertTrue();

      const overwrite = encodeUtf8('{"schemaVersion":1,"revision":2,"values":[],"updatedAt":2}');
      await adapter.replaceCommitted(overwrite);
      expect(bytesEqual(await new UserScriptValueFileAdapter(path).readCommitted(), overwrite)).assertTrue();

      const empty = encodeUtf8('{"schemaVersion":1,"revision":0,"values":[],"updatedAt":0}');
      await adapter.replaceCommitted(empty);
      expect(bytesEqual(await new UserScriptValueFileAdapter(path).readCommitted(), empty)).assertTrue();
    });
  });
}
