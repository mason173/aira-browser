import { describe, expect, it } from '@ohos/hypium';
import { buffer } from '@kit.ArkTS';
import {
  UserScriptValueCommittedBytesAdapter,
  UserScriptValueStateLimits,
  UserScriptValueStateStore
} from '../main/ets/data/userscripts/UserScriptValueStateStore';
import {
  UserScriptValueStateDocument,
  UserScriptValueReadinessSnapshot,
  UserScriptValueStateError
} from '../main/ets/features/userscripts/UserScriptValueModels';

class InMemoryUserScriptValueCommittedBytesAdapter implements UserScriptValueCommittedBytesAdapter {
  committed?: Uint8Array;
  fallback?: Uint8Array;
  private fallbackReadActive: boolean = false;
  fallbackReadCount: number = 0;
  blockNextReplace: boolean = false;
  failNextReplace: boolean = false;
  pendingBytes?: Uint8Array;
  pendingResolve?: () => void;
  replaceCount: number = 0;

  readCommitted(): Promise<Uint8Array | undefined> {
    this.fallbackReadActive = false;
    return Promise.resolve(this.committed === undefined ? undefined : this.cloneBytes(this.committed));
  }

  readFallbackCommitted(): Promise<Uint8Array | undefined> {
    this.fallbackReadCount += 1;
    this.fallbackReadActive = true;
    return Promise.resolve(this.fallback === undefined ? undefined : this.cloneBytes(this.fallback));
  }

  replaceCommitted(bytes: Uint8Array): Promise<void> {
    this.replaceCount += 1;
    if (this.failNextReplace) {
      this.failNextReplace = false;
      return Promise.reject(new Error('injected-write-failure'));
    }
    if (this.blockNextReplace) {
      this.blockNextReplace = false;
      this.pendingBytes = this.cloneBytes(bytes);
      return new Promise<void>((resolve: () => void) => {
        this.pendingResolve = resolve;
      });
    }
    if (this.committed !== undefined && !this.fallbackReadActive) {
      this.fallback = this.cloneBytes(this.committed);
    }
    this.committed = this.cloneBytes(bytes);
    this.fallbackReadActive = false;
    return Promise.resolve();
  }

  releasePendingReplace(): void {
    if (this.pendingBytes !== undefined) {
      this.committed = this.pendingBytes;
    }
    this.pendingBytes = undefined;
    const resolve = this.pendingResolve;
    this.pendingResolve = undefined;
    resolve?.();
  }

  private cloneBytes(bytes: Uint8Array): Uint8Array {
    return new Uint8Array(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
  }
}

function encodeUtf8(value: string): Uint8Array {
  const encoded = new Uint8Array(value.length);
  for (let index = 0; index < value.length; index += 1) {
    encoded[index] = value.charCodeAt(index);
  }
  return encoded;
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

export default function userScriptValueStateStoreTest(): void {
  describe('UserScriptValueStateStore', () => {
    it('creates schema version 1 revision 0 before becoming ready on first run', 0, async () => {
      const adapter = new InMemoryUserScriptValueCommittedBytesAdapter();
      const store = new UserScriptValueStateStore(adapter, 0, (): number => 1000);

      const readiness = await store.initialize();
      expect((adapter.committed ?? new Uint8Array()).byteLength).assertLarger(0);
      const committedText = buffer.from(adapter.committed ?? new Uint8Array()).toString('utf8');
      const committed = JSON.parse(committedText) as UserScriptValueStateDocument;

      expect(readiness.status).assertEqual('ready');
      expect(readiness.revision).assertEqual(0);
      expect(adapter.replaceCount).assertEqual(1);
      expect(committed.schemaVersion).assertEqual(1);
      expect(committed.revision).assertEqual(0);
    });

    it('advances revision once for a state-changing commit and not for a no-op', 0, async () => {
      const adapter = new InMemoryUserScriptValueCommittedBytesAdapter();
      const store = new UserScriptValueStateStore(adapter, 0, (): number => 2000);
      try {
        await store.initialize();
      } catch (_error) {
        const projection = store.readManagementProjection();
        throw new Error(`${projection.readiness.failureStage}:${projection.readiness.failureCode}`);
      }

      const committed = await store.commitMutations('script-a', [{
        operation: 'set',
        key: 'rules',
        valueJson: '{"count":3824}'
      }]);
      const noOp = await store.commitMutations('script-a', [{
        operation: 'set',
        key: 'rules',
        valueJson: '{"count":3824}'
      }]);

      expect(committed.revision).assertEqual(1);
      expect(committed.changed).assertTrue();
      expect(committed.transitions.length).assertEqual(1);
      expect(committed.transitions[0].hasOldValue).assertFalse();
      expect(committed.transitions[0].newValueJson).assertEqual('{"count":3824}');
      expect(store.readCommittedValueJson('script-a', 'rules')).assertEqual('{"count":3824}');
      expect(noOp.revision).assertEqual(1);
      expect(noOp.changed).assertFalse();
      expect(adapter.replaceCount).assertEqual(2);
    });

    it('coalesces same-key requests in one physical batch to the final committed value', 0, async () => {
      const adapter = new InMemoryUserScriptValueCommittedBytesAdapter();
      const store = new UserScriptValueStateStore(adapter, 0, (): number => 3000);
      await store.initialize();
      await store.commitMutations('script-a', [{
        operation: 'set',
        key: 'counter',
        valueJson: '0'
      }]);

      const first = store.commitMutations('script-a', [{
        operation: 'set',
        key: 'counter',
        valueJson: '1'
      }]);
      const second = store.commitMutations('script-a', [{
        operation: 'set',
        key: 'counter',
        valueJson: '2'
      }]);
      const results = await Promise.all([first, second]);

      expect(results[0].revision).assertEqual(2);
      expect(results[1].revision).assertEqual(2);
      expect(results[0].transitions.length).assertEqual(1);
      expect(results[0].transitions[0].oldValueJson).assertEqual('0');
      expect(results[0].transitions[0].newValueJson).assertEqual('2');
      expect(store.readCommittedValueJson('script-a', 'counter')).assertEqual('2');
      expect(adapter.replaceCount).assertEqual(3);
    });

    it('retains the last committed revision across an incident and recovers on a later commit', 0, async () => {
      const adapter = new InMemoryUserScriptValueCommittedBytesAdapter();
      const store = new UserScriptValueStateStore(adapter, 0, (): number => 4000);
      await store.initialize();
      await store.commitMutations('script-a', [{
        operation: 'set',
        key: 'rules',
        valueJson: '1'
      }]);

      adapter.failNextReplace = true;
      let firstError: UserScriptValueStateError | undefined = undefined;
      try {
        await store.commitMutations('script-a', [{
          operation: 'set',
          key: 'rules',
          valueJson: '2'
        }]);
      } catch (error) {
        if (error instanceof UserScriptValueStateError) {
          firstError = error;
        }
      }
      const firstIncident = store.readManagementProjection().incident;

      adapter.failNextReplace = true;
      let secondError: UserScriptValueStateError | undefined = undefined;
      try {
        await store.commitMutations('script-a', [{
          operation: 'set',
          key: 'rules',
          valueJson: '3'
        }]);
      } catch (error) {
        if (error instanceof UserScriptValueStateError) {
          secondError = error;
        }
      }

      expect(firstError !== undefined).assertTrue();
      expect(firstError?.incidentStarted ?? false).assertTrue();
      expect(secondError?.incidentStarted ?? true).assertFalse();
      expect(secondError?.incidentId ?? 0).assertEqual(firstIncident.id);
      expect(store.readCommittedValueJson('script-a', 'rules')).assertEqual('1');
      expect(store.readCommittedRuntimeView('script-a').revision).assertEqual(1);
      expect(store.readManagementProjection().incident.active).assertTrue();

      const recovered = await store.commitMutations('script-a', [{
        operation: 'set',
        key: 'rules',
        valueJson: '4'
      }]);
      expect(recovered.revision).assertEqual(2);
      expect(recovered.incidentRecovered).assertTrue();
      expect(store.readCommittedValueJson('script-a', 'rules')).assertEqual('4');
      expect(store.readManagementProjection().incident.active).assertFalse();
    });

    it('recovers an unsupported current snapshot from a valid previous snapshot', 0, async () => {
      const adapter = new InMemoryUserScriptValueCommittedBytesAdapter();
      adapter.committed = encodeUtf8('{"values":[],"updatedAt":0}');
      const previous = encodeUtf8('{"schemaVersion":1,"revision":4,"values":[],"updatedAt":5000}');
      adapter.fallback = previous;
      const store = new UserScriptValueStateStore(adapter, 0, (): number => 5000);

      let readiness: UserScriptValueReadinessSnapshot;
      try {
        readiness = await store.initialize();
      } catch (_error) {
        const projection = store.readManagementProjection();
        throw new Error(
          `${projection.readiness.failureStage}:${projection.readiness.failureCode}:fallback=${adapter.fallbackReadCount}:bytes=${adapter.fallback?.byteLength ?? -1}`
        );
      }

      expect(readiness.status).assertEqual('ready');
      expect(readiness.revision).assertEqual(4);
      expect(store.readManagementProjection().incident.active).assertFalse();
      expect(adapter.replaceCount).assertEqual(1);
      expect(bytesEqual(adapter.committed, previous)).assertTrue();
    });

    it('blocks only user-script readiness when both startup snapshots are invalid', 0, async () => {
      const adapter = new InMemoryUserScriptValueCommittedBytesAdapter();
      const current = encodeUtf8('{"values":[],"updatedAt":0}');
      const previous = encodeUtf8('{"schemaVersion":2,"revision":1,"values":[],"updatedAt":1}');
      adapter.committed = current;
      adapter.fallback = previous;
      const store = new UserScriptValueStateStore(adapter, 0, (): number => 5500);
      let blocked = false;
      try {
        await store.initialize();
      } catch (error) {
        blocked = error instanceof UserScriptValueStateError;
      }

      expect(blocked).assertTrue();
      expect(store.readReadiness().status).assertEqual('blocked');
      expect(store.readManagementProjection().incident.active).assertTrue();
      expect(store.readManagementProjection().incident.kind).assertEqual('startup');
      expect(adapter.replaceCount).assertEqual(0);
      expect(bytesEqual(adapter.committed, current)).assertTrue();
      expect(bytesEqual(adapter.fallback, previous)).assertTrue();
    });

    it('rejects invalid mutations before batching without opening an incident', 0, async () => {
      const adapter = new InMemoryUserScriptValueCommittedBytesAdapter();
      const store = new UserScriptValueStateStore(adapter, 0, (): number => 6000);
      await store.initialize();

      let rejection: UserScriptValueStateError | undefined = undefined;
      try {
        await store.commitMutations('script-a', [{
          operation: 'set',
          key: 'broken',
          valueJson: '{'
        }]);
      } catch (error) {
        if (error instanceof UserScriptValueStateError) {
          rejection = error;
        }
      }

      expect(rejection?.failureKind ?? '').assertEqual('validation');
      expect(store.readManagementProjection().incident.active).assertFalse();
      expect(store.readCommittedRuntimeView('script-a').revision).assertEqual(0);
      expect(adapter.replaceCount).assertEqual(1);
    });

    it('rejects only the request that would exceed aggregate capacity before batching', 0, async () => {
      const adapter = new InMemoryUserScriptValueCommittedBytesAdapter();
      const limits = new UserScriptValueStateLimits(100, 250);
      const store = new UserScriptValueStateStore(adapter, 20, (): number => 6500, limits);
      await store.initialize();

      const first = store.commitMutations('script-a', [{
        operation: 'set',
        key: 'first',
        valueJson: JSON.stringify('x'.repeat(50))
      }]);
      let secondError: UserScriptValueStateError | undefined = undefined;
      try {
        await store.commitMutations('script-b', [{
          operation: 'set',
          key: 'second',
          valueJson: JSON.stringify('y'.repeat(50))
        }]);
      } catch (error) {
        if (error instanceof UserScriptValueStateError) {
          secondError = error;
        }
      }
      const firstResult = await first;

      expect(firstResult.changed).assertTrue();
      expect(secondError?.publicCode ?? '').assertEqual('userscript-value-rejected:state-too-large');
      expect(store.readCommittedValueJson('script-a', 'first') !== undefined).assertTrue();
      expect(store.readCommittedValueJson('script-b', 'second') === undefined).assertTrue();
      expect(store.readManagementProjection().incident.active).assertFalse();
      expect(adapter.replaceCount).assertEqual(2);
    });

    it('publishes committed state only after the durable replacement completes', 0, async () => {
      const adapter = new InMemoryUserScriptValueCommittedBytesAdapter();
      const store = new UserScriptValueStateStore(adapter, 0, (): number => 7000);
      await store.initialize();
      adapter.blockNextReplace = true;

      const pendingCommit = store.commitMutations('script-a', [{
        operation: 'set',
        key: 'rules',
        valueJson: '3824'
      }]);
      await new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, 20);
      });

      expect(adapter.pendingBytes !== undefined).assertTrue();
      expect(store.readCommittedValueJson('script-a', 'rules') === undefined).assertTrue();
      expect(store.readCommittedRuntimeView('script-a').revision).assertEqual(0);

      adapter.releasePendingReplace();
      const result = await pendingCommit;
      expect(result.revision).assertEqual(1);
      expect(store.readCommittedValueJson('script-a', 'rules')).assertEqual('3824');
    });
  });
}
