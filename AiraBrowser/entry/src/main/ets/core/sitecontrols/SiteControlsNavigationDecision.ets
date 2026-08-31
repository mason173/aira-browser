import { SitePermissionKind } from '../../common/models/BrowserModels';
import { SiteCustomizationCapabilityFilterId } from '../../services/web/SiteCapabilityCatalogService';
import { SiteControlsFilterId } from './SiteControlsCoordinator';

export type SiteCustomizationFocusCapability = SiteCustomizationCapabilityFilterId;

export type SiteControlsSiteNavigationTargetKind =
  'site_permission' |
  'desktop_site' |
  'focused_site_customization' |
  'full_site_customization';

export interface SiteControlsSiteNavigationTarget {
  kind: SiteControlsSiteNavigationTargetKind;
  permissionKind?: SitePermissionKind;
  focusCapability?: SiteCustomizationFocusCapability;
}

export class SiteControlsNavigationDecision {
  resolveSiteTarget(
    filterId: SiteControlsFilterId,
    customizationFilterId: SiteCustomizationCapabilityFilterId | ''
  ): SiteControlsSiteNavigationTarget {
    if (customizationFilterId.length > 0) {
      return this.resolveCustomizationCapabilityTarget(customizationFilterId as SiteCustomizationCapabilityFilterId);
    }
    if (filterId === 'open_app') {
      return {
        kind: 'focused_site_customization',
        focusCapability: 'external_actions'
      };
    }
    if (this.isPermissionFilter(filterId)) {
      return {
        kind: 'site_permission',
        permissionKind: filterId as SitePermissionKind
      };
    }
    return {
      kind: 'full_site_customization'
    };
  }

  normalizeFocusCapability(value: string): SiteCustomizationFocusCapability | '' {
    if (
      value === 'external_actions' ||
        value === 'desktop_site' ||
        value === 'private_site' ||
        value === 'javascript'
    ) {
      return value;
    }
    return '';
  }

  private resolveCustomizationCapabilityTarget(
    capabilityId: SiteCustomizationCapabilityFilterId
  ): SiteControlsSiteNavigationTarget {
    if (capabilityId === 'desktop_site') {
      return {
        kind: 'desktop_site'
      };
    }
    return {
      kind: 'focused_site_customization',
      focusCapability: capabilityId
    };
  }

  private isPermissionFilter(filterId: SiteControlsFilterId): boolean {
    return filterId === 'camera' ||
      filterId === 'microphone' ||
      filterId === 'location' ||
      filterId === 'sensor' ||
      filterId === 'clipboard';
  }
}
