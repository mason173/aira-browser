import { AiraFeatureKey } from '../../common/constants/MembershipFeatureKeys';
import {
  EntitlementDecision,
  EntitlementPrimaryAction
} from '../../common/models/MembershipModels';
import { MembershipFeature } from '../../features/membership/MembershipFeature';
import { EntitlementContext } from '../../services/membership/EntitlementService';
import { BrowserShellRouteCoordinator } from '../browser/BrowserShellRouteCoordinator';
import { BrowserTransientSurfaceCoordinator } from '../browser/BrowserTransientSurfaceCoordinator';

export type FeatureGateAction = EntitlementPrimaryAction | 'dismiss';

export interface FeatureGateSnapshot {
  visible: boolean;
  title: string;
  message: string;
  primaryActionTitle: string;
  secondaryActionTitle: string;
  primaryAction: FeatureGateAction;
  secondaryAction: FeatureGateAction;
}

export function createHiddenFeatureGateSnapshot(): FeatureGateSnapshot {
  return {
    visible: false,
    title: '',
    message: '',
    primaryActionTitle: '',
    secondaryActionTitle: '',
    primaryAction: 'none',
    secondaryAction: 'none'
  };
}

export class FeatureGateCoordinator {
  private readonly membershipFeature: MembershipFeature;
  private readonly transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator;
  private readonly routeCoordinator: BrowserShellRouteCoordinator;
  private readonly publishSnapshotToShell: (snapshot: FeatureGateSnapshot) => void;
  private readonly revealDelayMs: number;
  private readonly dismissDurationMs: number;
  private snapshot: FeatureGateSnapshot = createHiddenFeatureGateSnapshot();
  private presentationGeneration: number = 0;

  constructor(
    membershipFeature: MembershipFeature,
    transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator,
    routeCoordinator: BrowserShellRouteCoordinator,
    publishSnapshotToShell: (snapshot: FeatureGateSnapshot) => void,
    revealDelayMs: number,
    dismissDurationMs: number
  ) {
    this.membershipFeature = membershipFeature;
    this.transientSurfaceCoordinator = transientSurfaceCoordinator;
    this.routeCoordinator = routeCoordinator;
    this.publishSnapshotToShell = publishSnapshotToShell;
    this.revealDelayMs = revealDelayMs;
    this.dismissDurationMs = dismissDurationMs;
  }

  getSnapshot(): FeatureGateSnapshot {
    return this.snapshot;
  }

  async ensureAccess(featureKey: AiraFeatureKey, context: EntitlementContext): Promise<boolean> {
    const decision = await this.evaluateAccess(featureKey, context);
    if (decision.allowed) {
      return true;
    }
    this.presentDecision(decision);
    return false;
  }

  async evaluateAccess(featureKey: AiraFeatureKey, context: EntitlementContext): Promise<EntitlementDecision> {
    return this.membershipFeature.canUse(featureKey, context);
  }

  presentDecision(decision: EntitlementDecision): void {
    if (decision.allowed) {
      this.resetPresentation();
      return;
    }
    const generation = this.presentationGeneration + 1;
    this.presentationGeneration = generation;
    this.publishSnapshot(this.buildSnapshot(decision));
    this.transientSurfaceCoordinator.present({
      id: 'feature_gate',
      revealDelayMs: this.revealDelayMs,
      dismissDurationMs: this.dismissDurationMs,
      shouldReveal: (): boolean => generation === this.presentationGeneration && this.snapshot.visible
    });
  }

  handleAction(action: FeatureGateAction): void {
    this.transientSurfaceCoordinator.dismiss('feature_gate');
    if (action === 'open_pro' || action === 'restore_purchase' || action === 'login') {
      this.routeCoordinator.openAiraProPage();
    }
  }

  handleSurfaceDismissed(): void {
    this.presentationGeneration += 1;
    this.publishSnapshot(createHiddenFeatureGateSnapshot());
  }

  private resetPresentation(): void {
    this.presentationGeneration += 1;
    this.publishSnapshot(createHiddenFeatureGateSnapshot());
    this.transientSurfaceCoordinator.reset('feature_gate');
  }

  private publishSnapshot(snapshot: FeatureGateSnapshot): void {
    this.snapshot = snapshot;
    this.publishSnapshotToShell(snapshot);
  }

  private buildSnapshot(decision: EntitlementDecision): FeatureGateSnapshot {
    return {
      visible: true,
      title: decision.title,
      message: decision.message,
      primaryActionTitle: this.resolvePrimaryActionTitle(decision.primaryAction),
      secondaryActionTitle: '稍后',
      primaryAction: decision.primaryAction,
      secondaryAction: 'dismiss'
    };
  }

  private resolvePrimaryActionTitle(action: EntitlementPrimaryAction): string {
    if (action === 'open_pro') {
      return '升级 Aira Pro';
    }
    if (action === 'restore_purchase') {
      return '恢复购买';
    }
    if (action === 'login') {
      return '登录';
    }
    return '知道了';
  }
}
