import { describe, expect, test, vi } from 'vitest';
import {
  AiraDesktopConnectionModule,
  AiraDesktopConnectionRemoteError,
  type AiraDesktopConnectionRecord,
  type AiraDesktopConnectionRemote,
  type AiraDesktopConnectionStorage,
} from './AiraDesktopConnectionModule';

type MembershipRefreshResponse = Awaited<ReturnType<AiraDesktopConnectionRemote['refreshMembership']>>;

const NOW = Date.parse('2026-08-20T00:00:00.000Z');

function createRecord(overrides: Partial<AiraDesktopConnectionRecord> = {}): AiraDesktopConnectionRecord {
  return {
    version: 1,
    status: 'connected',
    deviceId: 'desktop-1',
    deviceName: 'Chrome',
    account: {
      uid: 'account-1',
      uidSuffix: 'unt-1',
      displayName: 'Aira User',
      avatarUri: '',
    },
    membership: {
      plan: 'pro',
      status: 'active',
      expiresAt: 0,
      checkedAt: new Date(NOW - 60_000).toISOString(),
    },
    credential: 'desktop-credential-1',
    lastError: null,
    ...overrides,
  };
}

function createHarness(
  remote: Partial<AiraDesktopConnectionRemote>,
  initial = createRecord(),
  now: () => number = () => NOW,
) {
  let record: AiraDesktopConnectionRecord | null = initial;
  const storage: AiraDesktopConnectionStorage = {
    read: vi.fn(async () => record && structuredClone(record)),
    write: vi.fn(async (next) => {
      record = structuredClone(next);
    }),
    clear: vi.fn(async () => {
      record = null;
    }),
  };
  const module = new AiraDesktopConnectionModule({
    storage,
    remote: {
      createPairing: vi.fn(),
      pollPairing: vi.fn(),
      revoke: vi.fn(),
      refreshMembership: vi.fn(),
      ...remote,
    } as AiraDesktopConnectionRemote,
    now,
  });
  return { module, storage, getRecord: () => record };
}

describe('AiraDesktopConnectionModule membership refresh', () => {
  test('keeps the credential and avoids repeated requests during temporary failure backoff', async () => {
    const refreshMembership = vi.fn(async () => {
      throw new AiraDesktopConnectionRemoteError('http_error', 'Too many requests', 429);
    });
    const { module, getRecord } = createHarness({ refreshMembership });

    const first = await module.refreshMembership({ force: true });
    const second = await module.refreshMembership({ force: true });

    expect(refreshMembership).toHaveBeenCalledTimes(1);
    expect(first.status).toBe('degraded');
    expect(second.hasCredential).toBe(true);
    expect(second.membership?.plan).toBe('pro');
    expect(getRecord()?.credential).toBe('desktop-credential-1');
  });

  test('allows a retry after backoff and clears the temporary error on success', async () => {
    let shouldFail = true;
    let currentNow = NOW;
    const refreshMembership = vi.fn(async () => {
      if (shouldFail) {
        throw new AiraDesktopConnectionRemoteError('network_unavailable', 'offline');
      }
      return {
        account: { uid: 'account-1' },
        membership: {
          plan: 'pro',
          status: 'active',
          expiresAt: 0,
          checkedAt: new Date(NOW).toISOString(),
        },
      };
    });
    const { module, getRecord } = createHarness({ refreshMembership }, createRecord(), () => currentNow);

    await module.refreshMembership({ force: true });
    const blocked = await module.refreshMembership({ force: true });
    expect(refreshMembership).toHaveBeenCalledTimes(1);
    expect(blocked.status).toBe('degraded');

    const retryAt = Number(getRecord()?.membershipRefreshRetryAt || 0);
    currentNow = retryAt;
    shouldFail = false;

    const recovered = await module.refreshMembership({ force: true });
    expect(refreshMembership).toHaveBeenCalledTimes(2);
    expect(recovered.status).toBe('connected');
    expect(recovered.lastError).toBeNull();
    expect(getRecord()?.membershipRefreshRetryAt).toBe(0);
  });

  test('only explicit credential rejection enters reauth-required', async () => {
    const refreshMembership = vi.fn(async () => {
      throw new AiraDesktopConnectionRemoteError('invalid_desktop_push_token', 'revoked', 401);
    });
    const { module, getRecord } = createHarness({ refreshMembership });

    const snapshot = await module.refreshMembership({ force: true });

    expect(snapshot.status).toBe('reauth-required');
    expect(snapshot.hasCredential).toBe(false);
    expect(getRecord()?.credential).toBe('');
  });

  test('merges concurrent refreshes for the same desktop credential', async () => {
    let resolveRefresh: (value: MembershipRefreshResponse) => void = () => undefined;
    const refreshMembership = vi.fn((): Promise<MembershipRefreshResponse> => new Promise((resolve) => {
      resolveRefresh = resolve;
    }));
    const { module } = createHarness({ refreshMembership });

    const first = module.refreshMembership({ force: true });
    const second = module.refreshMembership({ force: true });
    await Promise.resolve();
    expect(refreshMembership).toHaveBeenCalledTimes(1);

    resolveRefresh({
      account: { uid: 'account-1' },
      membership: {
        plan: 'pro',
        status: 'active',
        expiresAt: 0,
        checkedAt: new Date(NOW).toISOString(),
      },
    });
    const [firstSnapshot, secondSnapshot] = await Promise.all([first, second]);
    expect(secondSnapshot).toEqual(firstSnapshot);
    expect(secondSnapshot.status).toBe('connected');
  });
});
