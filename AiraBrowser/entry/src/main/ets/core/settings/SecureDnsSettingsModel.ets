import urlUtils from '@ohos.url';

export type SecureDnsSelectionId = 'system' | 'auto' | 'alidns' | 'dnspod' | 'cloudflare' | 'google' | 'custom';

export interface SecureDnsCustomProfile {
  id: string;
  name: string;
  endpoint: string;
}

export interface SecureDnsSettings {
  selectionId: SecureDnsSelectionId;
  activeCustomProfileId: string;
  customProfiles: SecureDnsCustomProfile[];
}

export interface SecureDnsSelectProviderCommand {
  kind: 'select_provider';
  selectionId: SecureDnsSelectionId;
}

export interface SecureDnsSelectCustomProfileCommand {
  kind: 'select_custom_profile';
  profileId: string;
}

export interface SecureDnsSaveCustomProfileCommand {
  kind: 'save_custom_profile';
  profileId: string;
  name: string;
  endpoint: string;
  activate: boolean;
}

export interface SecureDnsDeleteCustomProfileCommand {
  kind: 'delete_custom_profile';
  profileId: string;
}

export type SecureDnsSettingsCommand = SecureDnsSelectProviderCommand |
  SecureDnsSelectCustomProfileCommand |
  SecureDnsSaveCustomProfileCommand |
  SecureDnsDeleteCustomProfileCommand;

export interface SecureDnsSettingsMutationResult {
  success: boolean;
  settings: SecureDnsSettings;
  nameError: string;
  endpointError: string;
}

interface SecureDnsEndpointValidation {
  valid: boolean;
  endpoint: string;
  errorMessage: string;
}

interface SecureDnsCustomProfileValidation {
  valid: boolean;
  name: string;
  endpoint: string;
  nameError: string;
  endpointError: string;
}

export const DEFAULT_SECURE_DNS_SETTINGS: SecureDnsSettings = {
  selectionId: 'system',
  activeCustomProfileId: '',
  customProfiles: []
};

const MAX_CUSTOM_DNS_PROFILES: number = 32;

export class SecureDnsSettingsModel {
  normalize(settings: SecureDnsSettings | undefined): SecureDnsSettings {
    if (settings === undefined) {
      return this.copySettings(DEFAULT_SECURE_DNS_SETTINGS);
    }
    const customProfiles = this.normalizeCustomProfiles(settings.customProfiles ?? []);
    const requestedActiveProfileId = (settings.activeCustomProfileId ?? '').trim();
    const activeProfile = this.findProfileInList(customProfiles, requestedActiveProfileId);
    const requestedSelectionId = this.normalizeSelectionId(settings.selectionId);
    return {
      selectionId: requestedSelectionId === 'custom' && activeProfile === undefined ? 'system' : requestedSelectionId,
      activeCustomProfileId: activeProfile?.id ?? '',
      customProfiles: customProfiles
    };
  }

  apply(settings: SecureDnsSettings, command: SecureDnsSettingsCommand): SecureDnsSettingsMutationResult {
    const normalized = this.normalize(settings);
    if (command.kind === 'select_provider') {
      return this.selectProvider(normalized, command.selectionId);
    }
    if (command.kind === 'select_custom_profile') {
      return this.selectCustomProfile(normalized, command.profileId);
    }
    if (command.kind === 'save_custom_profile') {
      return this.saveCustomProfile(
        normalized,
        command.profileId,
        command.name,
        command.endpoint,
        command.activate
      );
    }
    return this.deleteCustomProfile(normalized, command.profileId);
  }

  findProfile(settings: SecureDnsSettings, profileId: string): SecureDnsCustomProfile | undefined {
    const normalized = this.normalize(settings);
    const profile = this.findProfileInList(normalized.customProfiles, profileId);
    return profile === undefined ? undefined : this.copyProfile(profile);
  }

  private selectProvider(
    settings: SecureDnsSettings,
    selectionId: SecureDnsSelectionId
  ): SecureDnsSettingsMutationResult {
    const normalizedSelectionId = this.normalizeSelectionId(selectionId);
    if (normalizedSelectionId === 'custom' && settings.activeCustomProfileId.length === 0) {
      return this.failedMutation(settings);
    }
    return this.successfulMutation({
      selectionId: normalizedSelectionId,
      activeCustomProfileId: settings.activeCustomProfileId,
      customProfiles: settings.customProfiles
    });
  }

  private selectCustomProfile(
    settings: SecureDnsSettings,
    profileId: string
  ): SecureDnsSettingsMutationResult {
    const profile = this.findProfileInList(settings.customProfiles, profileId);
    if (profile === undefined) {
      return this.failedMutation(settings);
    }
    return this.successfulMutation({
      selectionId: 'custom',
      activeCustomProfileId: profile.id,
      customProfiles: settings.customProfiles
    });
  }

  private saveCustomProfile(
    settings: SecureDnsSettings,
    profileId: string,
    name: string,
    endpoint: string,
    activate: boolean
  ): SecureDnsSettingsMutationResult {
    const validation = this.validateCustomProfile(name, endpoint, settings.customProfiles, profileId);
    if (!validation.valid) {
      return {
        success: false,
        settings: settings,
        nameError: validation.nameError,
        endpointError: validation.endpointError
      };
    }
    const resolvedProfileId = profileId.trim().length > 0 ?
      profileId.trim() :
      this.buildProfileId(settings.customProfiles);
    const nextProfile: SecureDnsCustomProfile = {
      id: resolvedProfileId,
      name: validation.name,
      endpoint: validation.endpoint
    };
    const nextProfiles: SecureDnsCustomProfile[] = [];
    let replaced = false;
    for (let index = 0; index < settings.customProfiles.length; index += 1) {
      const profile = settings.customProfiles[index];
      if (profile.id === resolvedProfileId) {
        nextProfiles.push(nextProfile);
        replaced = true;
      } else {
        nextProfiles.push(this.copyProfile(profile));
      }
    }
    if (!replaced) {
      nextProfiles.push(nextProfile);
    }
    return this.successfulMutation({
      selectionId: activate ? 'custom' : settings.selectionId,
      activeCustomProfileId: activate ? resolvedProfileId : settings.activeCustomProfileId,
      customProfiles: nextProfiles
    });
  }

  private deleteCustomProfile(
    settings: SecureDnsSettings,
    profileId: string
  ): SecureDnsSettingsMutationResult {
    if (this.findProfileInList(settings.customProfiles, profileId) === undefined) {
      return this.failedMutation(settings);
    }
    const nextProfiles: SecureDnsCustomProfile[] = [];
    for (let index = 0; index < settings.customProfiles.length; index += 1) {
      const profile = settings.customProfiles[index];
      if (profile.id !== profileId) {
        nextProfiles.push(this.copyProfile(profile));
      }
    }
    const removedActiveProfile = settings.activeCustomProfileId === profileId;
    return this.successfulMutation({
      selectionId: removedActiveProfile && settings.selectionId === 'custom' ? 'system' : settings.selectionId,
      activeCustomProfileId: removedActiveProfile ? '' : settings.activeCustomProfileId,
      customProfiles: nextProfiles
    });
  }

  private validateCustomProfile(
    name: string,
    endpoint: string,
    profiles: SecureDnsCustomProfile[],
    editingProfileId: string
  ): SecureDnsCustomProfileValidation {
    const normalizedName = name.trim();
    let nameError = '';
    if (normalizedName.length === 0) {
      nameError = '请输入 DNS 名称。';
    } else if (normalizedName.length > 80) {
      nameError = 'DNS 名称不能超过 80 个字符。';
    } else if (editingProfileId.trim().length === 0 && profiles.length >= MAX_CUSTOM_DNS_PROFILES) {
      nameError = '最多可保存 32 个自定义 DNS。';
    } else if (this.hasDuplicateProfileName(profiles, editingProfileId, normalizedName)) {
      nameError = '已有同名的自定义 DNS。';
    }
    const endpointValidation = this.validateEndpoint(endpoint);
    let endpointError = endpointValidation.errorMessage;
    if (endpointValidation.valid &&
      this.hasDuplicateProfileEndpoint(profiles, editingProfileId, endpointValidation.endpoint)) {
      endpointError = '这个 DoH 地址已经保存。';
    }
    return {
      valid: nameError.length === 0 && endpointError.length === 0,
      name: normalizedName,
      endpoint: endpointValidation.endpoint,
      nameError: nameError,
      endpointError: endpointError
    };
  }

  private validateEndpoint(value: string): SecureDnsEndpointValidation {
    const endpoint = value.trim();
    if (endpoint.length === 0) {
      return this.invalidEndpoint('请输入 HTTPS DoH 地址。');
    }
    if (!endpoint.toLowerCase().startsWith('https://')) {
      return this.invalidEndpoint('仅支持 HTTPS 地址。');
    }
    try {
      const parsed = urlUtils.URL.parseURL(endpoint);
      if (parsed.protocol.toLowerCase() !== 'https:' || parsed.hostname.trim().length === 0) {
        return this.invalidEndpoint('请输入有效的 HTTPS DoH 地址。');
      }
      return {
        valid: true,
        endpoint: endpoint,
        errorMessage: ''
      };
    } catch (_error) {
      return this.invalidEndpoint('请输入有效的 HTTPS DoH 地址。');
    }
  }

  private normalizeCustomProfiles(profiles: SecureDnsCustomProfile[]): SecureDnsCustomProfile[] {
    const normalized: SecureDnsCustomProfile[] = [];
    for (let index = 0; index < profiles.length && normalized.length < MAX_CUSTOM_DNS_PROFILES; index += 1) {
      const profile = profiles[index];
      const id = (profile.id ?? '').trim();
      const name = (profile.name ?? '').trim();
      const endpointValidation = this.validateEndpoint(profile.endpoint ?? '');
      if (id.length === 0 || name.length === 0 || name.length > 80 || !endpointValidation.valid ||
        this.findProfileInList(normalized, id) !== undefined ||
        this.hasDuplicateProfileName(normalized, '', name) ||
        this.hasDuplicateProfileEndpoint(normalized, '', endpointValidation.endpoint)) {
        continue;
      }
      normalized.push({
        id: id,
        name: name,
        endpoint: endpointValidation.endpoint
      });
    }
    return normalized;
  }

  private normalizeSelectionId(value: string): SecureDnsSelectionId {
    if (value === 'auto' || value === 'alidns' || value === 'dnspod' || value === 'cloudflare' ||
      value === 'google' || value === 'custom') {
      return value;
    }
    return 'system';
  }

  private findProfileInList(
    profiles: SecureDnsCustomProfile[],
    profileId: string
  ): SecureDnsCustomProfile | undefined {
    for (let index = 0; index < profiles.length; index += 1) {
      if (profiles[index].id === profileId) {
        return profiles[index];
      }
    }
    return undefined;
  }

  private hasDuplicateProfileName(
    profiles: SecureDnsCustomProfile[],
    editingProfileId: string,
    name: string
  ): boolean {
    const normalizedName = name.toLowerCase();
    for (let index = 0; index < profiles.length; index += 1) {
      const profile = profiles[index];
      if (profile.id !== editingProfileId && profile.name.toLowerCase() === normalizedName) {
        return true;
      }
    }
    return false;
  }

  private hasDuplicateProfileEndpoint(
    profiles: SecureDnsCustomProfile[],
    editingProfileId: string,
    endpoint: string
  ): boolean {
    for (let index = 0; index < profiles.length; index += 1) {
      const profile = profiles[index];
      if (profile.id !== editingProfileId && profile.endpoint === endpoint) {
        return true;
      }
    }
    return false;
  }

  private buildProfileId(profiles: SecureDnsCustomProfile[]): string {
    let sequence = Date.now();
    let profileId = 'custom-dns-' + sequence;
    while (this.findProfileInList(profiles, profileId) !== undefined) {
      sequence += 1;
      profileId = 'custom-dns-' + sequence;
    }
    return profileId;
  }

  private copySettings(settings: SecureDnsSettings): SecureDnsSettings {
    return {
      selectionId: settings.selectionId,
      activeCustomProfileId: settings.activeCustomProfileId,
      customProfiles: settings.customProfiles.map((profile: SecureDnsCustomProfile): SecureDnsCustomProfile => {
        return this.copyProfile(profile);
      })
    };
  }

  private copyProfile(profile: SecureDnsCustomProfile): SecureDnsCustomProfile {
    return {
      id: profile.id,
      name: profile.name,
      endpoint: profile.endpoint
    };
  }

  private successfulMutation(settings: SecureDnsSettings): SecureDnsSettingsMutationResult {
    return {
      success: true,
      settings: this.normalize(settings),
      nameError: '',
      endpointError: ''
    };
  }

  private failedMutation(
    settings: SecureDnsSettings,
    nameError: string = '',
    endpointError: string = ''
  ): SecureDnsSettingsMutationResult {
    return {
      success: false,
      settings: this.normalize(settings),
      nameError: nameError,
      endpointError: endpointError
    };
  }

  private invalidEndpoint(message: string): SecureDnsEndpointValidation {
    return {
      valid: false,
      endpoint: '',
      errorMessage: message
    };
  }
}
