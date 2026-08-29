import { useCallback, useEffect, useRef, useState } from 'react';
import { listPhoneTabs } from './deviceTabsClient';
import type { CrossDeviceTabDevice } from './deviceTabsModels';

type DeviceTabsListState = {
  identityKey: string;
  devices: CrossDeviceTabDevice[];
  loading: boolean;
  error: unknown | null;
};

const EMPTY_DEVICE_TABS_STATE: DeviceTabsListState = {
  identityKey: '',
  devices: [],
  loading: false,
  error: null,
};

export function useDeviceTabsList({
  enabled,
  identityKey,
}: {
  enabled: boolean;
  identityKey: string;
}) {
  const requestIdRef = useRef(0);
  const [state, setState] = useState<DeviceTabsListState>(EMPTY_DEVICE_TABS_STATE);

  const refresh = useCallback(async () => {
    const requestId = requestIdRef.current + 1;
    requestIdRef.current = requestId;

    if (!enabled || !identityKey) {
      setState(EMPTY_DEVICE_TABS_STATE);
      return;
    }

    setState((current) => ({
      identityKey,
      devices: current.identityKey === identityKey ? current.devices : [],
      loading: true,
      error: null,
    }));
    try {
      const list = await listPhoneTabs();
      if (requestIdRef.current !== requestId) return;
      setState({
        identityKey,
        devices: list.devices,
        loading: false,
        error: null,
      });
    } catch (error) {
      if (requestIdRef.current !== requestId) return;
      setState({
        identityKey,
        devices: [],
        loading: false,
        error,
      });
    }
  }, [enabled, identityKey]);

  useEffect(() => {
    void refresh();
    return () => {
      requestIdRef.current += 1;
    };
  }, [refresh]);

  const isCurrentIdentity = enabled && state.identityKey === identityKey;
  const devices = isCurrentIdentity ? state.devices : [];
  let totalTabCount = 0;
  for (const device of devices) {
    totalTabCount += device.tabs.length;
  }

  return {
    devices,
    loading: enabled && Boolean(identityKey) && (!isCurrentIdentity || state.loading),
    error: isCurrentIdentity ? state.error : null,
    totalTabCount,
    refresh,
  };
}
