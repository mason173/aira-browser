import {
  SettingsNavigationPathEntry,
  SettingsNavigationSnapshot
} from '../../core/settings/SettingsDestinationNavigationOwner';

export class SettingsHdsNavigationStackProjection {
  pathStack: NavPathStack = new NavPathStack();
  private projectedEntries: SettingsNavigationPathEntry[] = [];

  sync(snapshot: SettingsNavigationSnapshot): void {
    const desiredEntries = snapshot.pathEntries;
    if (!this.doesNativeStackMatchProjection()) {
      this.pathStack.clear(false);
      this.projectedEntries = [];
    }
    if (desiredEntries.length === 0) {
      if (this.projectedEntries.length > 0) {
        this.pathStack.clear(false);
      }
      this.projectedEntries = [];
      return;
    }

    const previousEntries = this.projectedEntries;
    const commonPrefixLength = this.resolveCommonPrefixLength(previousEntries, desiredEntries);
    if (commonPrefixLength === 0 && previousEntries.length > 0) {
      this.pathStack.clear(false);
    } else {
      const animatePop = commonPrefixLength > 0 && desiredEntries.length > 0;
      for (let index = previousEntries.length; index > commonPrefixLength; index -= 1) {
        this.pathStack.pop(animatePop);
      }
    }

    const animatePush = commonPrefixLength > 0 && previousEntries.length > 0;
    for (let index = commonPrefixLength; index < desiredEntries.length; index += 1) {
      const entry = desiredEntries[index];
      this.pathStack.pushPath({
        name: entry.pathName,
        param: entry
      }, animatePush);
    }
    this.projectedEntries = desiredEntries;
  }

  private doesNativeStackMatchProjection(): boolean {
    const nativeNames = this.pathStack.getAllPathName();
    if (nativeNames.length !== this.projectedEntries.length) {
      return false;
    }
    for (let index = 0; index < nativeNames.length; index += 1) {
      if (nativeNames[index] !== this.projectedEntries[index].pathName) {
        return false;
      }
    }
    return true;
  }

  private resolveCommonPrefixLength(
    currentEntries: SettingsNavigationPathEntry[],
    desiredEntries: SettingsNavigationPathEntry[]
  ): number {
    const comparableLength = Math.min(currentEntries.length, desiredEntries.length);
    let index = 0;
    while (index < comparableLength &&
      currentEntries[index].projectionKey() === desiredEntries[index].projectionKey()) {
      index += 1;
    }
    return index;
  }
}
