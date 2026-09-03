/**
 * Owns the distribution boundary shared by Official and Community artifacts.
 *
 * The build script temporarily changes AIRA_DISTRIBUTION for an Official
 * build. Community is the safe source-tree default and never inherits Aira's
 * Huawei project, cloud, or payment approvals.
 */
export type AiraDistribution = 'community' | 'official';

export type AiraDistributionCapability =
  'huawei_account' |
  'huawei_space' |
  'huawei_iap' |
  'aira_cloud' |
  'personal_server';

export interface AiraDistributionCapabilityState {
  distribution: AiraDistribution;
  capability: AiraDistributionCapability;
  available: boolean;
  reason: string;
}

export const AIRA_DISTRIBUTION: AiraDistribution = 'official';
export const AIRA_HOSTED_API_BASE_URL: string = 'https://api.aira.cool';

export class AiraDistributionCapabilityOwner {
  getDistribution(): AiraDistribution {
    return AIRA_DISTRIBUTION;
  }

  isOfficial(): boolean {
    return this.getDistribution() === 'official';
  }

  isCommunity(): boolean {
    return !this.isOfficial();
  }

  isAvailable(capability: AiraDistributionCapability): boolean {
    if (capability === 'personal_server') {
      return true;
    }
    return this.isOfficial();
  }

  resolveUnavailableReason(capability: AiraDistributionCapability): string {
    if (this.isAvailable(capability)) {
      return '';
    }
    if (capability === 'aira_cloud') {
      return 'Aira 云服务仅包含在 Official 发行版中。Community 版本可使用本地功能、WebDAV 或未来接入的个人服务器。';
    }
    if (capability === 'personal_server') {
      return '';
    }
    return '此 Huawei 能力需要构建者自己的 Huawei 项目、审批和签名，Community 版本不会携带 Aira 的官方配置。';
  }

  resolveState(capability: AiraDistributionCapability): AiraDistributionCapabilityState {
    return {
      distribution: this.getDistribution(),
      capability: capability,
      available: this.isAvailable(capability),
      reason: this.resolveUnavailableReason(capability)
    };
  }
}

export const AIRA_DISTRIBUTION_CAPABILITY_OWNER: AiraDistributionCapabilityOwner =
  new AiraDistributionCapabilityOwner();
