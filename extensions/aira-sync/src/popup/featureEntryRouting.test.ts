import { describe, expect, test } from 'vitest';
import { resolveCloudFeatureEntryView } from './featureEntryRouting';

describe('cloud feature entry routing', () => {
  test('uses sync method setup when the desktop session exists without a selected provider', () => {
    expect(resolveCloudFeatureEntryView({
      hasAiraDesktopSession: true,
      airaCloudAvailable: true,
    })).toBe('sync-method');
  });

  test('opens QR login only when there is no desktop session', () => {
    expect(resolveCloudFeatureEntryView({
      hasAiraDesktopSession: false,
      airaCloudAvailable: true,
    })).toBe('login');
  });
});
