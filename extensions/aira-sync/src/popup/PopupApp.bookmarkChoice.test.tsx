import type { PropsWithChildren } from 'react';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';
import { afterEach, expect, test, vi } from 'vitest';
import { LEAFTAB_SELECTED_SYNC_SOURCE_KEY } from '@/features/sync/app/leafTabSyncStorageKeys';
import { PopupApp } from './PopupApp';

const actions = vi.hoisted(() => ({
  handleSelectSyncSource: vi.fn(async () => false),
  prepareBookmarkOverwrite: vi.fn(async () => ({ provider: 'aira-cloud', selectedSource: null, sourceIdentity: 'cloud:account', label: 'account' })),
  overwriteBookmarks: vi.fn(async () => false),
}));
vi.mock('@/config/AiratabDistribution', async (original) => ({
  ...await original<typeof import('@/config/AiratabDistribution')>(),
  AIRATAB_CAPABILITIES: { airaCloud: true },
}));
vi.mock('@/features/sync/bookmarks/useBookmarkSyncRuntimeController', () => ({
  useBookmarkSyncRuntimeController: () => ({ actions, state: {
    syncStorageReady: true, leafTabCloudLoggedIn: true, leafTabSelectedSyncSource: null,
    leafTabSyncProgress: { open: false, inProgress: false, progress: 0 },
  } }),
}));
vi.mock('@/features/device-tabs/useDeviceTabsList', () => ({ useDeviceTabsList: () => ({ totalTabCount: 0 }) }));
vi.mock('@/features/desktop-connection/useAiraDesktopConnectionProfile', () => ({ useAiraDesktopConnectionProfile: () => null }));
vi.mock('@/features/personal-server/PersonalServerConnection', async (original) => ({
  ...await original<typeof import('@/features/personal-server/PersonalServerConnection')>(), readPersonalServerConnection: async () => null,
}));
vi.mock('react-i18next', () => ({ useTranslation: () => ({ t: (key: string) => key }) }));
vi.mock('@/components/ui/dialog', () => {
  const content = ({ children }: PropsWithChildren) => <>{children}</>;
  return { Dialog: ({ open, children }: PropsWithChildren<{ open: boolean }>) => open ? children : null,
    DialogContent: content, DialogHeader: content, DialogTitle: content, DialogDescription: content };
});

let renderer: ReactTestRenderer;
afterEach(async () => {
  if (renderer) await act(async () => renderer.unmount());
  vi.unstubAllGlobals();
  vi.clearAllMocks();
});

test.each([
  ['pushBookmarks', 'computer-to-remote'], ['pullBookmarks', 'remote-to-computer'], ['mergeBookmarks', 'merge'],
])('first pairing waits for an explicit %s choice', async (button, direction) => {
  vi.stubGlobal('window', new EventTarget());
  vi.stubGlobal('localStorage', {
    getItem: (key: string) => key === LEAFTAB_SELECTED_SYNC_SOURCE_KEY ? 'webdav' : null,
  });
  await act(async () => { renderer = create(<PopupApp />); });
  const click = async (label: string) => {
    const target = renderer.root.findAllByType('button').find(node => node.children.includes('popup.advanced.' + label));
    expect(target).toBeDefined();
    await act(async () => { await target!.props.onClick(); });
  };
  expect(actions.handleSelectSyncSource).not.toHaveBeenCalled();
  expect(actions.prepareBookmarkOverwrite).not.toHaveBeenCalled();
  await click(button);
  if (direction === 'merge') {
    expect(actions.handleSelectSyncSource).toHaveBeenCalledWith('aira-cloud');
    expect(actions.overwriteBookmarks).not.toHaveBeenCalled();
  } else {
    expect(actions.handleSelectSyncSource).not.toHaveBeenCalled();
    expect(actions.overwriteBookmarks).not.toHaveBeenCalled();
    await click('confirmOverwrite');
    expect(actions.overwriteBookmarks).toHaveBeenCalledWith(expect.objectContaining({ sourceIdentity: 'cloud:account' }), direction);
  }
});
