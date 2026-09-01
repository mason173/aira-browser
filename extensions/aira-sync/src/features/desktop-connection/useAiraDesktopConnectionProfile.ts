import { useEffect, useState } from 'react';
import {
  readAiraDesktopConnectionProfile,
  type AiraDesktopConnectionProfile,
} from './desktopConnectionProfile';
import {
  AIRA_DESKTOP_CONNECTION_STORAGE_KEY,
} from './desktopConnectionRuntime';

export function useAiraDesktopConnectionProfile(): AiraDesktopConnectionProfile | null {
  const [profile, setProfile] = useState<AiraDesktopConnectionProfile | null>(null);

  useEffect(() => {
    let disposed = false;
    const refresh = () => {
      void readAiraDesktopConnectionProfile()
        .then((nextProfile) => {
          if (!disposed) setProfile(nextProfile);
        })
        .catch(() => {
          if (!disposed) setProfile(null);
        });
    };
    const handleStorageChanged = (
      changes: Record<string, chrome.storage.StorageChange>,
      areaName: string,
    ) => {
      if (areaName === 'local' && changes[AIRA_DESKTOP_CONNECTION_STORAGE_KEY]) {
        refresh();
      }
    };

    refresh();
    chrome.storage?.onChanged?.addListener?.(handleStorageChanged);
    return () => {
      disposed = true;
      chrome.storage?.onChanged?.removeListener?.(handleStorageChanged);
    };
  }, []);

  return profile;
}
