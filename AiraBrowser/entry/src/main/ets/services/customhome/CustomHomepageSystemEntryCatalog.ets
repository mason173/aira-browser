import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';

export type CustomHomepageSystemEntryTarget =
  'bookmarks' |
  'history' |
  'tabs' |
  'downloads' |
  'saved_pages' |
  'settings' |
  'sync' |
  'aira_pro' |
  'search_settings' |
  'ad_block_settings' |
  'site_settings' |
  'webpage_translation_settings' |
  'password_settings' |
  'user_scripts' |
  'user_agent_settings' |
  'download_settings' |
  'custom_homepage_settings' |
  'general_settings' |
  'appearance_settings' |
  'privacy_security_settings' |
  'experiments_settings' |
  'about_settings' |
  'startup_settings' |
  'private_tabs_settings' |
  'history_retention_settings' |
  'theme_palette_settings' |
  'keyboard_shortcuts_settings' |
  'app_proxy_settings';

interface CustomHomepageSystemEntryDefinition {
  target: CustomHomepageSystemEntryTarget;
  aliases: string[];
  directAction?: string;
}

const CUSTOM_HOMEPAGE_SYSTEM_ENTRY_DEFINITIONS: CustomHomepageSystemEntryDefinition[] = [
  { target: 'bookmarks', aliases: ['bookmarks'], directAction: 'bookmarks' },
  { target: 'history', aliases: ['history'], directAction: 'history' },
  { target: 'tabs', aliases: ['tabs'] },
  { target: 'downloads', aliases: ['downloads'], directAction: 'downloads' },
  { target: 'saved_pages', aliases: ['savedpages', 'offlinepages'] },
  { target: 'settings', aliases: ['settings'], directAction: 'settings' },
  { target: 'sync', aliases: ['sync', 'syncsettings'] },
  {
    target: 'aira_pro',
    aliases: ['airapro', 'pro', 'membership', 'membershipcenter']
  },
  { target: 'search_settings', aliases: ['search', 'searchsettings'] },
  { target: 'ad_block_settings', aliases: ['adblock', 'adblocksettings'] },
  {
    target: 'site_settings',
    aliases: ['sitesettings', 'permissions', 'permissionsitesettings']
  },
  {
    target: 'webpage_translation_settings',
    aliases: ['webpagetranslation', 'webpagetranslationsettings', 'translation', 'translationsettings']
  },
  { target: 'password_settings', aliases: ['passwords', 'passwordsettings'] },
  { target: 'user_scripts', aliases: ['userscripts', 'scripts'] },
  { target: 'user_agent_settings', aliases: ['useragent', 'useragentsettings'] },
  { target: 'download_settings', aliases: ['downloadsettings'] },
  {
    target: 'custom_homepage_settings',
    aliases: ['customhomepage', 'customhomepagesettings']
  },
  { target: 'general_settings', aliases: ['general', 'generalsettings'] },
  { target: 'appearance_settings', aliases: ['appearance', 'appearancesettings'] },
  {
    target: 'privacy_security_settings',
    aliases: ['privacy', 'security', 'privacysecurity', 'privacysecuritysettings']
  },
  { target: 'experiments_settings', aliases: ['experiments', 'experimentssettings'] },
  { target: 'about_settings', aliases: ['about', 'aboutsettings'] },
  { target: 'startup_settings', aliases: ['startup', 'startupsettings'] },
  { target: 'private_tabs_settings', aliases: ['privatetabs', 'privatetabssettings'] },
  {
    target: 'history_retention_settings',
    aliases: ['historyretention', 'historyretentionsettings']
  },
  { target: 'theme_palette_settings', aliases: ['themepalette', 'themepalettesettings'] },
  {
    target: 'keyboard_shortcuts_settings',
    aliases: ['keyboardshortcuts', 'keyboardshortcutssettings']
  },
  { target: 'app_proxy_settings', aliases: ['appproxy', 'appproxysettings'] }
];

export function resolveCustomHomepageSystemEntry(
  rawEntry: string
): CustomHomepageSystemEntryTarget | undefined {
  const key = normalizeCustomHomepageSystemEntryKey(rawEntry);
  const definition = CUSTOM_HOMEPAGE_SYSTEM_ENTRY_DEFINITIONS.find(
    (item: CustomHomepageSystemEntryDefinition): boolean => item.aliases.includes(key)
  );
  return resolveAvailableSystemEntryTarget(definition);
}

export function resolveCustomHomepageDirectSystemAction(
  rawAction: string
): CustomHomepageSystemEntryTarget | undefined {
  const action = rawAction.trim().toLowerCase();
  const definition = CUSTOM_HOMEPAGE_SYSTEM_ENTRY_DEFINITIONS.find(
    (item: CustomHomepageSystemEntryDefinition): boolean => item.directAction === action
  );
  return resolveAvailableSystemEntryTarget(definition);
}

function resolveAvailableSystemEntryTarget(
  definition: CustomHomepageSystemEntryDefinition | undefined
): CustomHomepageSystemEntryTarget | undefined {
  if (definition?.target === 'aira_pro' && !AIRA_DISTRIBUTION_CAPABILITY_OWNER.isOfficial()) {
    return undefined;
  }
  return definition?.target;
}

function normalizeCustomHomepageSystemEntryKey(rawEntry: string): string {
  return rawEntry.trim().replace(/[-_\s]/g, '').toLowerCase();
}
