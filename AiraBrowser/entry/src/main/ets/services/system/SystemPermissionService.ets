import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { SitePermissionKind } from '../../common/models/BrowserModels';
import { SiteCapabilityCatalogService } from '../web/SiteCapabilityCatalogService';

export interface SystemPermissionGrantResult {
  granted: boolean;
  systemDialogShown: boolean;
  settingsRequired: boolean;
  locationServiceEnabled: boolean;
  message: string;
}

export class SystemPermissionService {
  private capabilityCatalog: SiteCapabilityCatalogService = new SiteCapabilityCatalogService();

  async requestAppPermissionsForKinds(
    context: common.UIAbilityContext,
    kinds: SitePermissionKind[]
  ): Promise<SystemPermissionGrantResult> {
    const permissions = this.resolveAppPermissions(kinds);
    if (permissions.length === 0) {
      return {
        granted: true,
        systemDialogShown: false,
        settingsRequired: false,
        locationServiceEnabled: true,
        message: '无需额外系统权限。'
      };
    }
    if (this.hasRequiredGrantStatuses(kinds, permissions, this.getCurrentGrantStatuses(context, permissions))) {
      const locationServiceEnabled = this.isRequiredLocationServiceEnabled(kinds);
      return {
        granted: locationServiceEnabled,
        systemDialogShown: false,
        settingsRequired: !locationServiceEnabled,
        locationServiceEnabled: locationServiceEnabled,
        message: locationServiceEnabled ? '系统权限已授予。' : '系统位置信息开关未开启。'
      };
    }
    const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, permissions);
    const appPermissionsGranted = this.hasRequiredAppPermissions(kinds, result.permissions, result.authResults);
    const locationServiceEnabled = this.isRequiredLocationServiceEnabled(kinds);
    const systemDialogShown = (result.dialogShownResults ?? []).some((shown: boolean) => shown);
    const deniedWithoutSystemDialog = this.hasDeniedRequiredPermissionWithoutDialog(
      kinds,
      result.permissions,
      result.authResults,
      result.dialogShownResults ?? []
    );
    const granted = appPermissionsGranted && locationServiceEnabled;
    return {
      granted: granted,
      systemDialogShown: systemDialogShown,
      settingsRequired: !granted && (deniedWithoutSystemDialog || !locationServiceEnabled),
      locationServiceEnabled: locationServiceEnabled,
      message: granted ? '系统权限已授予。' :
        (locationServiceEnabled ? '系统权限未完全开启。' : '系统位置信息开关未开启。')
    };
  }

  async requestAppPermissionSettingsForKinds(
    context: common.UIAbilityContext,
    kinds: SitePermissionKind[]
  ): Promise<SystemPermissionGrantResult> {
    const permissions = this.resolveAppPermissions(kinds);
    if (permissions.length === 0) {
      return {
        granted: true,
        systemDialogShown: false,
        settingsRequired: false,
        locationServiceEnabled: true,
        message: '无需额外系统权限。'
      };
    }
    if (this.hasRequiredGrantStatuses(kinds, permissions, this.getCurrentGrantStatuses(context, permissions))) {
      const locationServiceEnabled = this.isRequiredLocationServiceEnabled(kinds);
      return {
        granted: locationServiceEnabled,
        systemDialogShown: false,
        settingsRequired: !locationServiceEnabled,
        locationServiceEnabled: locationServiceEnabled,
        message: locationServiceEnabled ? '系统权限已开启，请重新发起网页请求。' : '系统位置信息开关未开启。'
      };
    }
    const grantStatuses = await this.requestPermissionsOnSettingOneByOne(context, permissions);
    const appPermissionsGranted = this.hasRequiredGrantStatuses(kinds, permissions, grantStatuses) ||
      this.hasRequiredGrantStatuses(kinds, permissions, this.getCurrentGrantStatuses(context, permissions));
    const locationServiceEnabled = this.isRequiredLocationServiceEnabled(kinds);
    const granted = appPermissionsGranted && locationServiceEnabled;
    return {
      granted: granted,
      systemDialogShown: false,
      settingsRequired: !granted,
      locationServiceEnabled: locationServiceEnabled,
      message: granted ? '系统权限已开启，请重新发起网页请求。' :
        (locationServiceEnabled ? '系统权限仍未完全开启。' : '系统位置信息开关未开启。')
    };
  }

  resolveAppPermissions(kinds: SitePermissionKind[]): Permissions[] {
    return this.capabilityCatalog.resolveSystemPermissions(kinds);
  }

  private async requestPermissionsOnSettingOneByOne(
    context: common.UIAbilityContext,
    permissions: Permissions[]
  ): Promise<abilityAccessCtrl.GrantStatus[]> {
    const grantStatuses = this.getCurrentGrantStatuses(context, permissions);
    for (let index = 0; index < permissions.length; index += 1) {
      if (grantStatuses[index] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        continue;
      }
      const result = await abilityAccessCtrl.createAtManager().requestPermissionOnSetting(context, [permissions[index]]);
      if (result.length > 0) {
        grantStatuses[index] = result[0];
      }
    }
    return grantStatuses;
  }

  private getCurrentGrantStatuses(
    context: common.UIAbilityContext,
    permissions: Permissions[]
  ): abilityAccessCtrl.GrantStatus[] {
    const tokenId = context.applicationInfo.accessTokenId;
    return permissions.map((permission: Permissions) => {
      return abilityAccessCtrl.createAtManager().checkAccessTokenSync(tokenId, permission);
    });
  }

  private hasRequiredAppPermissions(
    kinds: SitePermissionKind[],
    permissions: string[],
    authResults: number[]
  ): boolean {
    if (kinds.includes('camera') && !this.isAppPermissionGranted(permissions, authResults, 'ohos.permission.CAMERA')) {
      return false;
    }
    if (kinds.includes('microphone') &&
      !this.isAppPermissionGranted(permissions, authResults, 'ohos.permission.MICROPHONE')) {
      return false;
    }
    if (kinds.includes('location') &&
      !this.isAppPermissionGranted(permissions, authResults, 'ohos.permission.APPROXIMATELY_LOCATION') &&
      !this.isAppPermissionGranted(permissions, authResults, 'ohos.permission.LOCATION')) {
      return false;
    }
    if (kinds.includes('sensor') &&
      !this.isAppPermissionGranted(permissions, authResults, 'ohos.permission.ACCELEROMETER')) {
      return false;
    }
    if (kinds.includes('clipboard') &&
      !this.isAppPermissionGranted(permissions, authResults, 'ohos.permission.READ_PASTEBOARD')) {
      return false;
    }
    return true;
  }

  private hasRequiredGrantStatuses(
    kinds: SitePermissionKind[],
    permissions: Permissions[],
    grantStatuses: abilityAccessCtrl.GrantStatus[]
  ): boolean {
    if (kinds.includes('camera') && !this.isGrantStatusGranted(permissions, grantStatuses, 'ohos.permission.CAMERA')) {
      return false;
    }
    if (kinds.includes('microphone') &&
      !this.isGrantStatusGranted(permissions, grantStatuses, 'ohos.permission.MICROPHONE')) {
      return false;
    }
    if (kinds.includes('location') &&
      !this.isGrantStatusGranted(permissions, grantStatuses, 'ohos.permission.APPROXIMATELY_LOCATION') &&
      !this.isGrantStatusGranted(permissions, grantStatuses, 'ohos.permission.LOCATION')) {
      return false;
    }
    if (kinds.includes('sensor') &&
      !this.isGrantStatusGranted(permissions, grantStatuses, 'ohos.permission.ACCELEROMETER')) {
      return false;
    }
    if (kinds.includes('clipboard') &&
      !this.isGrantStatusGranted(permissions, grantStatuses, 'ohos.permission.READ_PASTEBOARD')) {
      return false;
    }
    return true;
  }

  private isAppPermissionGranted(permissions: string[], authResults: number[], permission: string): boolean {
    const index = permissions.indexOf(permission);
    return index >= 0 && authResults[index] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }

  private hasDeniedRequiredPermissionWithoutDialog(
    kinds: SitePermissionKind[],
    permissions: string[],
    authResults: number[],
    dialogShownResults: boolean[]
  ): boolean {
    if (kinds.includes('camera') &&
      !this.isAppPermissionGranted(permissions, authResults, 'ohos.permission.CAMERA') &&
      !this.wasAppPermissionDialogShown(permissions, dialogShownResults, 'ohos.permission.CAMERA')) {
      return true;
    }
    if (kinds.includes('microphone') &&
      !this.isAppPermissionGranted(permissions, authResults, 'ohos.permission.MICROPHONE') &&
      !this.wasAppPermissionDialogShown(permissions, dialogShownResults, 'ohos.permission.MICROPHONE')) {
      return true;
    }
    if (kinds.includes('location') &&
      !this.isAppPermissionGranted(permissions, authResults, 'ohos.permission.APPROXIMATELY_LOCATION') &&
      !this.isAppPermissionGranted(permissions, authResults, 'ohos.permission.LOCATION') &&
      !this.wasAppPermissionDialogShown(permissions, dialogShownResults, 'ohos.permission.APPROXIMATELY_LOCATION') &&
      !this.wasAppPermissionDialogShown(permissions, dialogShownResults, 'ohos.permission.LOCATION')) {
      return true;
    }
    if (kinds.includes('sensor') &&
      !this.isAppPermissionGranted(permissions, authResults, 'ohos.permission.ACCELEROMETER') &&
      !this.wasAppPermissionDialogShown(permissions, dialogShownResults, 'ohos.permission.ACCELEROMETER')) {
      return true;
    }
    return kinds.includes('clipboard') &&
      !this.isAppPermissionGranted(permissions, authResults, 'ohos.permission.READ_PASTEBOARD') &&
      !this.wasAppPermissionDialogShown(permissions, dialogShownResults, 'ohos.permission.READ_PASTEBOARD');
  }

  private wasAppPermissionDialogShown(
    permissions: string[],
    dialogShownResults: boolean[],
    permission: string
  ): boolean {
    const index = permissions.indexOf(permission);
    return index >= 0 && dialogShownResults[index] === true;
  }

  private isGrantStatusGranted(
    permissions: Permissions[],
    grantStatuses: abilityAccessCtrl.GrantStatus[],
    permission: Permissions
  ): boolean {
    const index = permissions.indexOf(permission);
    return index >= 0 && grantStatuses[index] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }

  private isRequiredLocationServiceEnabled(kinds: SitePermissionKind[]): boolean {
    if (!kinds.includes('location')) {
      return true;
    }
    try {
      return geoLocationManager.isLocationEnabled();
    } catch (_error) {
      return false;
    }
  }
}
