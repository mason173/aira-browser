export class SettingsColoredTileIconResources {
  static foregroundIcon(destination: string): Resource | undefined {
    switch (destination) {
      case 'sync':
        return $r('app.media.app_settings_sync');
      case 'webdav':
        return $r('app.media.app_settings_webdav');
      case 'general':
        return $r('app.media.app_settings_general');
      case 'custom_homepage':
        return $r('app.media.app_settings_custom_homepage');
      case 'search':
        return $r('app.media.app_settings_search');
      case 'activity_heatmap':
        return $r('app.media.app_membership_invite_record_clock_white');
      case 'bookshelf':
        return $r('app.media.app_shortcut_bookmarks');
      default:
        return undefined;
    }
  }

  static requiredForegroundIcon(destination: string): Resource {
    return SettingsColoredTileIconResources.foregroundIcon(destination) ?? $r('app.media.app_settings_general');
  }

  static foregroundColor(): ResourceColor {
    return '#FFFFFF';
  }
}
