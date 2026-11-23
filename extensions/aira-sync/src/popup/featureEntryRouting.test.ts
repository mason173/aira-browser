import { describe, expect, test } from 'vitest';
import {
  resolveCloudFeatureEntryView,
  resolveOfficialPopupOpenView,
  shouldOfferCloudSyncChoice,
} from './featureEntryRouting';

describe('cloud feature entry routing', () => {
  test('uses sync method setup when the desktop session exists without a selected provider', () => {
    expect(resolveCloudFeatureEntryView({
      hasAiraDesktopSession: true,
      airaCloudAvailable: true,
    })).toBe('sync-method');
  });

  test('offers a cloud sync choice after login or before the first selection', () => {
    expect(shouldOfferCloudSyncChoice({
      airaCloudAvailable: true,
      loggedIn: true,
      selectedSource: 'webdav',
      loginJustCompleted: true,
    })).toBe(true);
    expect(shouldOfferCloudSyncChoice({
      airaCloudAvailable: true,
      loggedIn: true,
      selectedSource: null,
      loginJustCompleted: false,
    })).toBe(true);
    expect(shouldOfferCloudSyncChoice({
      airaCloudAvailable: true,
      loggedIn: true,
      selectedSource: 'personal-server',
      loginJustCompleted: false,
    })).toBe(false);
    expect(shouldOfferCloudSyncChoice({
      airaCloudAvailable: true,
      loggedIn: false,
      selectedSource: null,
      loginJustCompleted: true,
    })).toBe(false);
  });

  test('opens QR login only when there is no desktop session', () => {
    expect(resolveCloudFeatureEntryView({
      hasAiraDesktopSession: false,
      airaCloudAvailable: true,
    })).toBe('login');
  });

  test('opens the official popup on QR login until a desktop session or another provider exists', () => {
    expect(resolveOfficialPopupOpenView({
      airaCloudAvailable: true,
      loggedIn: false,
      selectedSource: null,
    })).toBe('login');
    expect(resolveOfficialPopupOpenView({
      airaCloudAvailable: true,
      loggedIn: false,
      selectedSource: 'aira-cloud',
    })).toBe('login');
    expect(resolveOfficialPopupOpenView({
      airaCloudAvailable: true,
      loggedIn: true,
      selectedSource: 'aira-cloud',
    })).toBe('home');
    expect(resolveOfficialPopupOpenView({
      airaCloudAvailable: true,
      loggedIn: false,
      selectedSource: 'personal-server',
    })).toBe('home');
    expect(resolveOfficialPopupOpenView({
      airaCloudAvailable: false,
      loggedIn: false,
      selectedSource: null,
    })).toBe('home');
  });
});
