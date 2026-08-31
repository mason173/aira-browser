export type HomeSearchPanelDetent = 'peek' | 'low' | 'middle';

export interface HomeSearchPanelDetentMetrics {
  peekHeight: number;
  lowHeight: number;
  middleHeight: number;
}

export interface HomeSearchPanelReleaseInput {
  currentDetent: HomeSearchPanelDetent;
  startHeight: number;
  currentHeight: number;
  offsetY: number;
  velocityY: number;
  metrics: HomeSearchPanelDetentMetrics;
}

const HOME_SEARCH_PANEL_MIDDLE_HIGH_RATIO: number = 0.56;
const HOME_SEARCH_PANEL_MIDDLE_MIN_HEIGHT: number = 260;
const HOME_SEARCH_PANEL_RELEASE_VELOCITY_THRESHOLD: number = 1000;
const HOME_SEARCH_PANEL_RELEASE_DISTANCE_RATIO: number = 0.5;
const HOME_SEARCH_PANEL_RELEASE_VELOCITY_PROJECTION_SECONDS: number = 0.36;
const HOME_SEARCH_PANEL_RELEASE_DIRECTION_VELOCITY_FLOOR: number = 240;
const HOME_SEARCH_PANEL_RELEASE_PROJECTION_VELOCITY_FLOOR: number = 80;
const HOME_SEARCH_PANEL_RELEASE_MIN_MOVEMENT_DISTANCE: number = 4;

export class HomeSearchPanelDetentViewModel {
  buildMetrics(
    highTargetHeight: number,
    lowHeight: number,
    peekHeight: number = lowHeight,
    middleTargetHeight: number = 0
  ): HomeSearchPanelDetentMetrics {
    const normalizedPeekHeight = Math.max(0, Math.min(peekHeight, lowHeight));
    const maxHeight = Math.max(highTargetHeight, lowHeight);
    const defaultMiddleHeight = Math.min(
      maxHeight,
      Math.max(lowHeight, HOME_SEARCH_PANEL_MIDDLE_MIN_HEIGHT, maxHeight * HOME_SEARCH_PANEL_MIDDLE_HIGH_RATIO)
    );
    const middleHeight = middleTargetHeight > 0 ?
      Math.min(maxHeight, Math.max(lowHeight, middleTargetHeight)) :
      defaultMiddleHeight;
    return {
      peekHeight: normalizedPeekHeight,
      lowHeight,
      middleHeight
    };
  }

  clampHeight(height: number, metrics: HomeSearchPanelDetentMetrics): number {
    return Math.max(metrics.peekHeight, Math.min(height, metrics.middleHeight));
  }

  resolveDetentHeight(detent: HomeSearchPanelDetent, metrics: HomeSearchPanelDetentMetrics): number {
    if (detent === 'peek') {
      return metrics.peekHeight;
    }
    if (detent === 'middle') {
      return metrics.middleHeight;
    }
    return metrics.lowHeight;
  }

  resolveNearestDetent(height: number, metrics: HomeSearchPanelDetentMetrics): HomeSearchPanelDetent {
    if (height < this.getPeekToLowThreshold(metrics)) {
      return 'peek';
    }
    if (height < this.getLowToMiddleThreshold(metrics)) {
      return 'low';
    }
    return 'middle';
  }

  resolveNextHigherDetent(detent: HomeSearchPanelDetent): HomeSearchPanelDetent {
    if (detent === 'peek') {
      return 'low';
    }
    if (detent === 'low') {
      return 'middle';
    }
    return 'middle';
  }

  resolveNextLowerDetent(detent: HomeSearchPanelDetent): HomeSearchPanelDetent {
    if (detent === 'middle') {
      return 'low';
    }
    if (detent === 'low') {
      return 'peek';
    }
    return 'peek';
  }

  resolveOfficialSheetReleaseDetent(input: HomeSearchPanelReleaseInput): HomeSearchPanelDetent {
    const currentDetent = input.currentDetent;
    const velocityY = this.normalizeNumber(input.velocityY);
    const direction = this.resolveReleaseDirection(input);
    if (direction === 0) {
      return currentDetent;
    }
    const targetDetent = direction < 0 ? this.resolveNextHigherDetent(currentDetent) :
      this.resolveNextLowerDetent(currentDetent);
    if (Math.abs(velocityY) >= HOME_SEARCH_PANEL_RELEASE_VELOCITY_THRESHOLD) {
      return targetDetent;
    }
    const startHeight = this.resolveReleaseStartHeight(input);
    const targetHeight = this.resolveDetentHeight(targetDetent, input.metrics);
    const targetDistance = Math.abs(targetHeight - startHeight);
    if (targetDistance <= 0) {
      return currentDetent;
    }
    const currentDistance = this.resolveDirectionalReleaseDistance(input, direction, startHeight);
    const projectedDistance = currentDistance + this.resolveProjectedVelocityDistance(input, direction);
    return projectedDistance >= targetDistance * HOME_SEARCH_PANEL_RELEASE_DISTANCE_RATIO ? targetDetent : currentDetent;
  }

  private getPeekToLowThreshold(metrics: HomeSearchPanelDetentMetrics): number {
    return metrics.peekHeight + (metrics.lowHeight - metrics.peekHeight) / 2;
  }

  private getLowToMiddleThreshold(metrics: HomeSearchPanelDetentMetrics): number {
    return metrics.lowHeight + (metrics.middleHeight - metrics.lowHeight) / 2;
  }

  private resolveReleaseDirection(input: HomeSearchPanelReleaseInput): number {
    const velocityY = this.normalizeNumber(input.velocityY);
    if (Math.abs(velocityY) >= HOME_SEARCH_PANEL_RELEASE_DIRECTION_VELOCITY_FLOOR) {
      return velocityY < 0 ? -1 : 1;
    }
    const offsetY = this.normalizeNumber(input.offsetY);
    if (Math.abs(offsetY) >= HOME_SEARCH_PANEL_RELEASE_MIN_MOVEMENT_DISTANCE) {
      return offsetY < 0 ? -1 : 1;
    }
    const startHeight = this.resolveReleaseStartHeight(input);
    const currentHeight = this.normalizeNumber(input.currentHeight);
    if (Math.abs(currentHeight - startHeight) < HOME_SEARCH_PANEL_RELEASE_MIN_MOVEMENT_DISTANCE) {
      return 0;
    }
    return currentHeight > startHeight ? -1 : 1;
  }

  private resolveDirectionalReleaseDistance(
    input: HomeSearchPanelReleaseInput,
    direction: number,
    startHeight: number
  ): number {
    const currentHeight = this.normalizeNumber(input.currentHeight);
    if (direction < 0) {
      return Math.max(0, currentHeight - startHeight);
    }
    return Math.max(0, startHeight - currentHeight);
  }

  private resolveProjectedVelocityDistance(input: HomeSearchPanelReleaseInput, direction: number): number {
    const velocityY = this.normalizeNumber(input.velocityY);
    if (direction === 0 || Math.abs(velocityY) < HOME_SEARCH_PANEL_RELEASE_PROJECTION_VELOCITY_FLOOR) {
      return 0;
    }
    if ((direction < 0 && velocityY > 0) || (direction > 0 && velocityY < 0)) {
      return 0;
    }
    return Math.abs(velocityY) * HOME_SEARCH_PANEL_RELEASE_VELOCITY_PROJECTION_SECONDS;
  }

  private resolveReleaseStartHeight(input: HomeSearchPanelReleaseInput): number {
    const startHeight = this.normalizeNumber(input.startHeight);
    if (startHeight > 0) {
      return startHeight;
    }
    return this.resolveDetentHeight(input.currentDetent, input.metrics);
  }

  private normalizeNumber(value: number): number {
    return Number.isFinite(value) ? value : 0;
  }
}
