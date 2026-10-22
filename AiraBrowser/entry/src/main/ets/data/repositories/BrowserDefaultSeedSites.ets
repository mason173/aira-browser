export interface BrowserDefaultSeedSite {
  idSuffix: string;
  title: string;
  url: string;
}

// A fresh install seeds an empty homepage: the grid starts with the "add" tile and
// nothing else. Seed ids decide what a new install seeds, never what a device
// already holds, so emptying this list touches no existing row - a device that was
// seeded earlier keeps its shortcuts as ordinary user data.
const CORE_BROWSER_SEED_SITES: BrowserDefaultSeedSite[] = [];

export const DEFAULT_BROWSER_SEED_SITES: BrowserDefaultSeedSite[] = CORE_BROWSER_SEED_SITES;
