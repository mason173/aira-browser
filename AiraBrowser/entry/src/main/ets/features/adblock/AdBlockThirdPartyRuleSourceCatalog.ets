export interface AdBlockThirdPartyRuleSourceDefinition {
  id: string;
  title: string;
  url: string;
  sourceHost: string;
}

const THIRD_PARTY_RULE_SOURCES: AdBlockThirdPartyRuleSourceDefinition[] = [
  {
    id: 'third-party-easylist',
    title: 'EasyList',
    url: 'https://easylist-downloads.adblockplus.org/easylist.txt',
    sourceHost: 'easylist-downloads.adblockplus.org'
  },
  {
    id: 'third-party-easylist-china',
    title: 'EasyList China',
    url: 'https://easylist-downloads.adblockplus.org/easylistchina.txt',
    sourceHost: 'easylist-downloads.adblockplus.org'
  },
  {
    id: 'third-party-cjx-annoyance',
    title: 'CJX Annoyance',
    url: 'https://fastly.jsdelivr.net/gh/cjx82630/cjxlist/cjx-annoyance.txt',
    sourceHost: 'fastly.jsdelivr.net'
  },
  {
    id: 'third-party-easylist-cookie',
    title: 'EasyList Cookie',
    url: 'https://secure.fanboy.co.nz/fanboy-cookiemonster_ubo.txt',
    sourceHost: 'secure.fanboy.co.nz'
  },
  {
    id: 'third-party-easyprivacy',
    title: 'EasyPrivacy',
    url: 'https://easylist-downloads.adblockplus.org/easyprivacy.txt',
    sourceHost: 'easylist-downloads.adblockplus.org'
  },
  {
    id: 'third-party-anti-adblock-filters',
    title: 'Anti-Adblock Filters',
    url: 'https://easylist-downloads.adblockplus.org/antiadblockfilters.txt',
    sourceHost: 'easylist-downloads.adblockplus.org'
  }
];

export function getAdBlockThirdPartyRuleSources(): AdBlockThirdPartyRuleSourceDefinition[] {
  return THIRD_PARTY_RULE_SOURCES.slice();
}

export function findAdBlockThirdPartyRuleSource(
  sourceId: string
): AdBlockThirdPartyRuleSourceDefinition | undefined {
  return THIRD_PARTY_RULE_SOURCES.find((item: AdBlockThirdPartyRuleSourceDefinition) => item.id === sourceId);
}

export function isAdBlockThirdPartyRuleSourceId(sourceId: string): boolean {
  return findAdBlockThirdPartyRuleSource(sourceId) !== undefined;
}
