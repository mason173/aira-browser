import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import deviceInfo from '@ohos.deviceInfo';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { APP_PREVIEW_VERSION_NAME } from '../../common/constants/AppVersionInfo';
import { CrossDeviceTabPresenceLocalDevice } from '../../core/deviceTabs/CrossDeviceTabPresenceModels';

const PREFERENCES_NAME: string = 'aira_cross_device_tab_presence';
const DEVICE_ID_KEY: string = 'installation_device_id_v1';
const ENABLED_ACCOUNTS_KEY: string = 'enabled_accounts_v1';

export class CrossDeviceTabPresencePreferencesRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;

  async isEnabled(uid: string): Promise<boolean> {
    return await this.readEnabledPreference(uid) === true;
  }

  async readEnabledPreference(uid: string): Promise<boolean | undefined> {
    const normalizedUid = uid.trim();
    if (normalizedUid.length === 0) {
      return undefined;
    }
    const store = await this.getStore();
    return this.readEnabledAccounts(store)[normalizedUid];
  }

  async setEnabled(uid: string, enabled: boolean): Promise<void> {
    const normalizedUid = uid.trim();
    if (normalizedUid.length === 0) {
      return;
    }
    const store = await this.getStore();
    const accounts = this.readEnabledAccounts(store);
    accounts[normalizedUid] = enabled;
    store.putSync(ENABLED_ACCOUNTS_KEY, JSON.stringify(accounts));
    await store.flush();
  }

  async readLocalDevice(): Promise<CrossDeviceTabPresenceLocalDevice> {
    const store = await this.getStore();
    const model = this.resolveDeviceModel();
    const defaultName = model.length > 0 ? model : 'HarmonyOS 手机';
    let deviceId = String(store.getSync(DEVICE_ID_KEY, '')).trim();
    if (deviceId.length === 0) {
      deviceId = `phone-${util.generateRandomUUID().split('-').join('')}`;
      store.putSync(DEVICE_ID_KEY, deviceId);
      await store.flush();
    }
    return {
      deviceId: deviceId,
      deviceName: defaultName,
      platform: 'HarmonyOS',
      model: model,
      browserName: 'Aira',
      browserVersion: APP_PREVIEW_VERSION_NAME
    };
  }

  private readEnabledAccounts(store: preferences.Preferences): Record<string, boolean | undefined> {
    const accounts: Record<string, boolean | undefined> = {};
    const raw = String(store.getSync(ENABLED_ACCOUNTS_KEY, '{}')).trim();
    if (raw.length === 0) {
      return accounts;
    }
    try {
      const parsed = JSON.parse(raw) as Record<string, Object | boolean | undefined>;
      Object.keys(parsed).forEach((uid: string): void => {
        const enabled = parsed[uid];
        if (enabled === true) {
          accounts[uid] = true;
        } else if (enabled === false) {
          accounts[uid] = false;
        }
      });
    } catch (_error) {
    }
    return accounts;
  }

  private resolveDeviceModel(): string {
    try {
      const marketName = `${deviceInfo.marketName ?? ''}`.trim();
      const productModel = `${deviceInfo.productModel ?? ''}`.trim();
      return (marketName.length > 0 ? marketName : productModel).slice(0, 120);
    } catch (_error) {
      return '';
    }
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(AppRuntimeContext.getApplicationContext(), PREFERENCES_NAME)
        .then((store: preferences.Preferences): preferences.Preferences => {
          this.store = store;
          return store;
        });
    }
    return this.storePromise;
  }
}

export const sharedCrossDeviceTabPresencePreferencesRepository: CrossDeviceTabPresencePreferencesRepository =
  new CrossDeviceTabPresencePreferencesRepository();
