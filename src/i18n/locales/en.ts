export default {
  translation: {    settings: {
      title: "Settings",
      newTabMode: {
        label: "Open in New Tab",
        description: "Shortcuts open in a new tab by default"
      },
      preventDuplicateNewTab: {
        label: "Avoid Duplicate Aira Tabs",
        description: "When opening a new tab, switch to the existing Aira in this window and close the duplicate one",
        permissionDenied: "Tabs permission is required to enable duplicate Aira prevention.",
        permissionFailed: "Failed to request tabs permission. Please try again."
      },
      searchEngineTabSwitch: {
        label: "Tab Engine Switch",
        description: "When the search box is focused, press Tab to cycle search engines"
      },
      searchSettings: {
        label: "Search Settings",
        description: "Manage search behaviors and smart search capabilities",
        open: "Open",
        title: "Search Settings",
        items: {
          tabSwitch: {
            label: "Tab Engine Switch",
            description: "Press Tab in the focused search box to cycle engines",
            tooltip: "Use Tab or Shift+Tab to quickly switch search engines while the search box is focused."
          },
          prefix: {
            label: "Temporary Engine Panel",
            description: "Type `!` to open the engine panel and pick one target\nIt only affects the current query and keeps your default engine unchanged",
            tooltip: "Type `!`, choose Google/Bing/Baidu/DuckDuckGo, then keep typing with a colored token shown on the left."
          },
          siteDirect: {
            label: "@ Target Panel",
            description: "Type `@` to open a target panel\nPick GitHub, Bilibili, ChatGPT, Gemini, and more, then enter your query",
            tooltip: "Site-direct search and AI targets now share the same `@` panel flow with a colored token shown on the left after selection."
          },
          siteShortcut: {
            label: "@ Panel Site Targets",
            description: "Control whether common site targets appear inside the `@` panel",
            tooltip: "When enabled, the `@` panel can suggest GitHub, Bilibili, Zhihu, YouTube, and other built-in sites."
          },
          anyKeyCapture: {
            label: "Any-Key Search Capture",
            description: "Start typing anywhere to focus and fill the search box",
            tooltip: "When enabled, pressing printable keys on a new tab auto-focuses the search input."
          },
          calculator: {
            label: "Calculator Preview",
            description: "Show live math result suggestions while typing expressions",
            tooltip: "Example: `12*8` shows a computed result in the dropdown."
          },
          rotatingPlaceholder: {
            label: "Rotating Search Hints",
            description: "Rotate capability hints in the search box automatically\nEnabled by default; turn it off to keep a single static hint",
            tooltip: "Shows hints for the `@` target panel, the `!` engine panel, the `/` scope panel, and quick result actions."
          },
          position: {
            label: "Search Bar Position",
            description: "Choose whether the search bar appears above or below the shortcuts area",
            tooltip: "The change applies immediately and your selected position will be remembered.",
            top: "Top",
            bottom: "Bottom"
          }
        }
      },
      shortcutGuide: {
        label: "Shortcuts & Actions",
        description: "View common shortcuts and what they do",
        open: "View",
        title: "Shortcuts & Actions",
        dialogDescription: "Aira shortcut and interaction guide",
        helper: "This panel only lists shortcuts that are already supported in the current version.",
        countSuffix: "items",
        columns: {
          shortcut: "Shortcut",
          action: "Action"
        },
        sections: {
          search: "Search",
          results: "Results"
        },
        items: {
          focusSearch: "Focus the search box and select the current text",
          switchEngine: "Press Tab or Shift+Tab in the search box to switch engines",
          temporaryEnginePrefix: "Type `!` to open the engine panel, then pick the engine for just this search",
          switchScenarioNext: "When not typing, cycle to the next scenario mode",
          bookmarksMode: "Enter bookmark search mode; browser permission may be requested on first use",
          bookmarksModeStore: "Enter bookmark search mode and search browser bookmarks directly",
          tabsMode: "Enter tab search mode; browser permission may be requested on first use",
          tabsModeStore: "Enter tab search mode and search open tabs directly",
          navigateResults: "Move selection up or down in the results list",
          openResult: "Open the currently selected result",
          closePanel: "Close the current results panel",
          showNumberHints: "Show number hints in the results list",
          openNumberedResult: "Open the result using its number"
        },
        footer: "Tip: number hints only work while the results list is open; type `!` for the engine panel, `@` for the target panel, and `/` for scope and settings."
      },
      timeFormat: {
        label: "24-Hour Clock",
        description: "Display time in 24-hour format"
      },
      showSeconds: {
        label: "Show Seconds",
        description: "Display seconds in the time component"
      },
      showLunar: {
        label: "Show Lunar",
        description: "Display the lunar date below the time"
      },
      timeAnimation: {
        label: "Animation",
        description: "Rolling time transition",
        performanceHint: "Animated time digits add continuous rendering work. Keep this off on low-performance devices.",
        followSystemBadge: "Follow system",
        followSystemAction: "Follow system again",
        followSystemEnabled: "Following system: currently on",
        followSystemReduced: "Following system: currently off",
        overrideOn: "Individually enabled",
        overrideOff: "Individually disabled"
      },
      showTime: {
        label: "Show Time",
        description: "Display time on the page"
      },
      timeDisplay: {
        title: "Time Display",
        description: "Customize the time style and visible details"
      },
      autoFocusSearch: {
        label: "Auto-focus Search Box",
        description: "Automatically focus the search box when entering the page"
      },
      language: {
        label: "Language",
        description: "Select interface language",
        selectPlaceholder: "Select language"
      },
      theme: {
        label: "Theme",
        description: "Switch light/dark theme or follow system",
        selectPlaceholder: "Select theme",
        system: "System",
        light: "Light",
        dark: "Dark"
      },
      accentColor: {
        label: "Accent Color",
        description: "Choose the primary color for the application"
      },
      accent: {
        dynamic: "Dynamic",
        mono: "Mono",
        green: "Green",
        blue: "Blue",
        purple: "Purple",
        orange: "Orange",
        pink: "Pink",
        red: "Red"
      },
      displayMode: {
        title: "Display Mode",
        description: "Choose the page layout style",
        blank: "Blank",
        blankDesc: "Hide time, wallpaper and shortcuts",
        rhythm: "Rhythm",
        rhythmDesc: "Keep search and shortcuts only"
      },
      shortcutsLayout: {
        label: "Shortcut Density",
        description: "Adjust the number of shortcuts per column",
        set: "Set",
        select: "Select"
      },
      shortcutsStyle: {
        label: "Shortcut Layout",
        entryDescription: "Adjust grid columns and shortcut name display",
        open: "Open",
        title: "Shortcut Layout Settings",
        description: "Adjust single-page grid columns and shortcut name display",
        rich: "Rich",
        compact: "Minimal",
        showName: "Show Name",
        showNameDesc: "Display shortcut title below icon",
        columns: "Grid Columns",
        rows: "Base Rows"
      },
      shortcutIconSettings: {
        label: "Icon Settings",
        entryDescription: "Adjust shortcut icon color mode and corner radius",
        open: "Open",
        title: "Icon Settings",
        description: "Adjust the color mode and corner radius of shortcut icons.",
        modeLabel: "Color Mode",
        colorful: "Colorful",
        monochrome: "Monochrome",
        accent: "Accent",
        modeReservedHint: "Monochrome and accent modes recolor supported icons with a unified palette.",
        cornerRadius: "Corner Radius",
        size: "Icon Size"
      },
      backup: {
        bookmarksLabel: "Bookmark Import & Export",
        bookmarksDescription: "Supports browser bookmark HTML from Chrome, Edge, and compatible browsers",
        webdavTab: "WebDAV Sync",
        importBookmarks: "Import Bookmarks",
        exportBookmarks: "Export Bookmarks",
        bookmarkImportSuccess: "Imported {{count}} bookmarks",
        importError: "Failed to import bookmarks. Please check the file format.",
        exportSuccess: "Bookmarks exported successfully",
        exportError: "Failed to export bookmarks",
        webdav: {
          entry: "WebDAV Sync",
          entryDesc: "Configure WebDAV bookmark sync",
          configure: "Configure",
          syncBookmarksLabel: "Sync bookmarks",
          syncBookmarksDesc: "WebDAV sync only syncs browser bookmarks. Aira layout, settings, and account data are no longer synced.",
          bookmarkSyncSafetyReminderTitle: "Reminder",
          bookmarkSyncSafetyReminderA11yDescription: "Reminder before enabling bookmark sync",
          bookmarkSyncSafetyReminderLine1: "Sync keeps devices consistent; it is not a backup.",
          bookmarkSyncSafetyReminderLine2: "Bookmark sync is still in beta. Delays or unexpected behavior may occur in rare cases.",
          bookmarkSyncSafetyReminderLine3: "We recommend exporting a local backup before enabling bookmark sync.",
          bookmarkSyncSafetyReminderCancel: "Back up first",
          bookmarkSyncSafetyReminderConfirm: "Enable anyway",
          url: "WebDAV URL",
          username: "Username",
          password: "Password",
          profileName: "Config Name",
          profileNamePlaceholder: "e.g. Home NAS",
          usernamePlaceholder: "Optional",
          passwordPlaceholder: "Optional",
          syncByScheduleLabel: "Scheduled auto sync",
          syncByScheduleDesc: "Sync at a fixed interval, good for long sessions",
          autoSyncToastLabel: "Show auto-sync success toast",
          autoSyncToastDesc: "Show a toast notification after scheduled auto sync succeeds",
          syncIntervalLabel: "Sync interval",
          syncIntervalMinutes: "{{count}} minutes",
          enabledLabel: "Enable WebDAV Sync",
          enabledDesc: "Disable to pause WebDAV automatic and manual sync",
          providerCustom: "Custom provider",
          providers: {
            jianguoyun: "Jianguoyun",
          },
          providerLabel: "WebDAV provider",
          providerPlaceholder: "Select provider",
          syncSuccess: "Sync completed",
          syncError: "Sync failed. Check your settings.",
          authFailed: "WebDAV authentication failed. Check username or password.",
          configSaved: "WebDAV settings saved",
          disableConfirmTitle: "Disable WebDAV Sync",
          disableConfirmDesc: "Disable WebDAV sync? Local data will remain on this device.",
          clearLocalLabel: "Clear local data and restore defaults",
          clearLocalDesc: "Restore local shortcuts to the default starter profile",
          urlRequired: "Please enter WebDAV URL first",
          defaultProfileName: "Default Profile",
          configured: "Configured and ready to sync",
          notConfigured: "Not configured yet",
          lastSyncAt: "Last sync",
          notSynced: "Not synced",
          justSynced: "Just synced",
          minutesAgo: "{{count}} minutes ago",
          hoursAgo: "{{count}} hours ago",
          disabled: "Disabled, WebDAV sync paused",
          syncOffTitle: "WebDAV is off",
          configureAction: "Configure",
          enableSyncAction: "Enable Sync",
          lastAttemptFailed: "Last sync attempt failed",
          scheduleRunning: "Scheduled sync running",
          nextSyncAtLabel: "Next sync: {{time}}",
          syncDisabled: "Enable WebDAV sync first",
          disableFinalSyncFailed: "Final sync before disabling failed. Sync has still been disabled.",
          enableConflictTitle: "Sync conflict detected",
          enableConflictDesc: "WebDAV and local data differ. Choose how to resolve."
        }
      },
      about: {
        label: "About Aira",
        description: "View the app intro and version",
        open: "View",
        title: "About",
        intro: "Aira is a focused, lightweight new tab tool with search, shortcuts, browser bookmark search, WebDAV bookmark sync, and wallpaper appearance settings.",
        version: "Version",
        highlights: {
          bookmarks: "Centered on browser bookmarks and shortcuts",
          sync: "Syncs bookmarks through WebDAV without a built-in account system",
          privacy: "Data stays local first and remains under your control"
        }
      },
      privacyPolicy: "Privacy Policy",
      copyright: "All rights reserved.",
      specialThanks: "Special thanks to testers: yanshuai, Horang, Mling",
    },
    languages: {
      zh: "Chinese (Simplified)",
      en: "English"
    },
    wallpaper: {
      mode: "Wallpaper Mode",
      modeDesc: "Customize minimalist mode background",
      bing: "Bing",
      color: "Color",
      custom: "Custom",
      uploadTitle: "Upload Custom Wallpaper",
      upload: "Upload Image",
      uploadDesc: "Click to upload or drag and drop images here",
      download: "Download",
      setAsWallpaper: "Set as Wallpaper",
      apply: "Set as Wallpaper",
      bingDesc: "Updates automatically every day from Bing.",
      customDesc: "Upload your own image to use as wallpaper.",
      customUploaded: "Your uploaded wallpaper.",
      imageSupport: "Supports JPG, PNG, WEBP",
      maskOpacity: "Black Overlay",
      autoDimInDarkMode: "Auto-dim in Dark Mode",
      autoDimInDarkModeDesc: "When dark mode is on, increase wallpaper overlay automatically for readability.",
      autoRotate: "Auto Rotate Wallpaper",
      autoRotateDesc: "Rotate within the current wallpaper type only, based on system time.",
      autoRotateUnavailableDesc: "This wallpaper type updates on its own and does not support rotation.",
      rotation: {
        off: "Do not rotate",
        hourly: "Hourly",
        sixHours: "Every 6 hours",
        daily: "Daily"
      },
      colorPresets: {
        "aurora-blush": "Aurora Blush",
        "mist-lilac": "Mist Lilac",
        "mint-breeze": "Mint Breeze",
        "peach-cloud": "Peach Cloud",
        "glacier-milk": "Glacier Blue",
        "rose-water": "Rose Water",
        "sage-cream": "Sage Cream",
        "dawn-sand": "Dawn Sand",
        "lavender-snow": "Lavender Snow",
        "ocean-haze": "Ocean Haze",
        "camellia-silk": "Camellia Silk",
        "tea-ivory": "Tea Ivory"
      }
    },
    lunar: {
      label: "Lunar"
    },
    common: {
      loading: "Loading...",
      cancel: "Cancel",
      close: "Close",
      confirm: "Confirm",
      delete: "Delete",
      save: "Save",
      current: "Current",
      clear: "Clear",
      back: "Back",
      prev: "Previous",
      next: "Next",
      refresh: "Refresh",
      settings: "Settings",
      more: "More"
    },
    search: {
      placeholder: "Type what you want to find",
      placeholderDynamic: "Search tabs, bookmarks, history, shortcuts, or open a pasted URL",
      placeholderHintTabSwitch: "Press Tab or type ! to open the temporary engine panel",
      placeholderHintCalculator: "Type 12*8 to calculate instantly",
      placeholderHintSiteDirect: "Type @ to open targets like GitHub, Bilibili, ChatGPT, or Gemini",
      placeholderHintPrefix: "Type ! to open the engine panel, then keep typing with that engine for this query",
      placeholderHintSettings: "Type / to open the scope and settings panel, or search theme mode, icon size, and wallpaper mode directly",
      placeholderHintActions: "Press → on a result to close tabs, copy links, or add shortcuts",
      aiPromptPlaceholder: "Ask {{provider}}",
      sitePromptPlaceholder: "Search in {{site}}",
      enginePromptPlaceholder: "Search with {{engine}}",
      scopePromptPlaceholder: "Keep typing to search in {{scope}}",
      aiSubmitSent: "Sent your prompt to {{provider}}",
      aiSubmitFilled: "Opened {{provider}} and filled in your prompt",
      aiSubmitOpened: "Opened {{provider}}. Please type or paste your prompt manually",
      aiSubmitCopiedAndOpened: "Copied your prompt and opened {{provider}}. Please paste and send it manually",
      aiSubmitCopyFailed: "Failed to copy your prompt or open {{provider}}. Please try again",
      aiSubmitFailed: "Failed to open {{provider}}. Please try again",
      aiPasteNotice: "Your prompt for {{provider}} was copied. Press {{shortcut}} to paste and send it",
      atPanelPinned: "Pinned to the front",
      atPanelUnpinned: "Removed from pinned targets",
      aiProvidersEmpty: "No matching targets",
      secondaryAction: {
        pinAtTarget: "Pin to front",
        unpinAtTarget: "Unpin",
        copyLink: "Copy link"
      },
      bang: {
        detail: "Use this engine for the current query only",
        empty: "No matching search engine"
      },
      enterKey: "Enter",
      actionOpen: "Open",
      actionClose: "Close",
      actionSelect: "Select",
      authorizeHistoryPermission: "Authorize",
      historyPermissionBanner: "Authorize to show browser history",
      historyPermissionPending: "Waiting for history permission...",
      historyPreparing: "Loading browser history...",
      bookmarksPermissionBanner: "Authorize to search browser bookmarks",
      bookmarksPermissionPending: "Waiting for bookmarks permission...",
      bookmarksPreparing: "Preparing bookmarks...",
      tabsPermissionBanner: "Authorize to search open tabs",
      tabsPermissionPending: "Waiting for tabs permission...",
      tabsPreparing: "Preparing open tabs...",
      permissionHistoryDenied: "History permission not granted. You can authorize again from the top of the dropdown.",
      permissionBookmarksDenied: "Bookmarks permission not granted. You can request it again next time you use /b.",
      permissionTabsDenied: "Tabs permission not granted. You can request it again next time you use /t.",
      permissionRequestFailed: "Permission request failed. Please try again.",
      noBookmarks: "No matching bookmarks found",
      noTabs: "No matching tabs found",
      currentTabLabel: "Current tab",
      remoteSuggestionSource: "Search suggestion",
      justNow: "Just now",
      calculatorCopied: "Result copied to clipboard",
      calculatorCopyFailed: "Copy failed. Please copy manually.",
      systemEngine: "System default",
      useEngineSearch: "Search with {{engine}}",
      prefixEngineInlineHint: "Use {{engine}} for this query",
      historyTitle: "Recent searches",
      clearHistory: "Clear",
      noHistory: "No recent searches"
    },
    groups: {
      edit: "Edit",
      addShortcut: "New Shortcut"
    },
    sidebar: {
      toggle: "Toggle Sidebar",
      title: "Sidebar",
      description: "Displays the mobile sidebar."
    },
    context: {
      open: "Open",
      edit: "Edit",
      copyLink: "Copy link",
      delete: "Delete",
      deleteFolder: "Delete folder",
      addShortcut: "Add Shortcut",
      newShortcut: "New Shortcut",
      pinToTop: "Pin to top",
      pinTop: "Pin selected to top",
      pinBottom: "Pin selected to bottom",
      select: "Select",
      unselect: "Unselect",
      selectedCount: "{{count}} selected",
      selectAll: "Select all",
      deleteSelected: "Delete selected",
      moveToScenario: "Move to scenario",
      movedToScenarioToast: "Moved {{count}} item(s) to \"{{scenario}}\"",
      noScenarioTarget: "No scenario to move to",
      selectBeforeMove: "Select shortcuts first",
      multiSelect: "Multi-select",
      cancelMultiSelect: "Exit multi-select"
    },
    shortcutModal: {
      addTitle: "Add Shortcut",
      editTitle: "Edit Shortcut",
      nameLabel: "Name",
      namePlaceholder: "Enter shortcut title",
      urlLabel: "URL",
      urlPlaceholder: "Enter URL",
      icon: {
        modeGroup: "Icon source",
        modeFaviconShort: "Online",
        modeLetterShort: "Letter",
        modeCustomShort: "Custom",
        modeCustomReplaceShort: "Change",
        modeCustomLoadingShort: "Processing",
        networkHint: "Online icons may fail to load; if so, it will fall back to a letter icon",
        customFileInvalid: "This image can't be used as an icon right now. Please try another one."
      },
      errors: {
        fillAll: "Please fill in all fields",
        fillAllDesc: "Enter shortcut title and URL",
        duplicateUrl: "A shortcut for this site already exists",
        duplicateUrlDesc: "Only one shortcut per site is allowed. Please use a different URL."
      }
    },
    popupShortcut: {
      title: "Add Current Page",
      loading: "Reading current tab information...",
      unsupported: "This page can't be saved directly. Switch to an http or https page and try again.",
      targetScenario: "Will be saved to \"{{name}}\"",
      ready: "The current tab title and URL were filled automatically.",
      saved: "Shortcut saved",
      scenarioLabel: "Save to scenario",
      scenarioPlaceholder: "Choose a scenario"
    },
    onboarding: {
      welcome: "Welcome to Aira",
      skip: "Skip",
      start: "Start",
      next: "Next",
      layoutTip: "Layout can be changed later in settings",
      stepAppearanceTitle: "Set theme & language",
      stepAppearanceDesc: "Choose appearance and language, you can change later in Settings",
      stepLayoutTitle: "Choose layout style",
      stepLayoutDesc: "Decide how the home page is arranged",
      stepPermissionsTitle: "Grant permissions",
      stepPermissionsDesc: "Enable history and bookmarks access to unlock the full search experience",
      historyPermissionTitle: "Browser history",
      historyPermissionDesc: "Allow Aira to show recent browsing records and related search suggestions",
      bookmarksPermissionTitle: "Bookmarks",
      bookmarksPermissionDesc: "Allow Aira to search and open your browser bookmarks directly",
      tabsPermissionTitle: "Browser tabs",
      tabsPermissionDesc: "Allow Aira to search open tabs and prevent duplicate Aira tabs",
      authorize: "Authorize",
      authorizing: "Requesting...",
      authorized: "Authorized",
      unsupported: "Unavailable",
      permissionTip: "You can skip this step and grant these permissions later from normal use.",
      enterHome: "Enter Aira"
    },
    shortcutDelete: {
      confirm: "Delete",
      cancel: "Cancel",
      title: "Delete Shortcut",
      description: "Are you sure you want to delete this shortcut?",
      folderTitle: "Delete folder",
      folderDescription: "Are you sure you want to delete this folder? Everything inside it will be deleted too.",
      bulkTitle: "Delete shortcuts",
      bulkDescription: "Are you sure you want to delete the selected {{count}} shortcuts?"
    },
    scenario: {
      title: "Scenario Mode",
      defaultName: "Working mode",
      unnamed: "Untitled",
      createTitle: "New Scenario Mode",
      createDescription: "Set name, color and icon",
      editTitle: "Edit Scenario Mode",
      editDescription: "Modify name, color and icon",
      nameLabel: "Mode Name",
      namePlaceholder: "Enter mode name",
      colorLabel: "Color",
      iconLabel: "Icon",
      actionEdit: "Edit scenario mode",
      actionDelete: "Delete scenario mode",
      colorPicker: "Pick a color",
      iconPicker: "Pick an icon",
      createButton: "New Scenario Mode",
      addButton: "Add",
      saveButton: "Save",
      deleteTitle: "Delete Scenario Mode",
      deleteConfirm: "Are you sure you want to delete this scenario mode? This will permanently delete all groups and shortcuts within this mode. Please proceed with caution.",
      deleteConfirmWithTarget: "Are you sure you want to delete \"{{name}}\"? This will permanently delete all groups and shortcuts within this mode. Please proceed with caution.",
      deleteButton: "Delete",
      toast: {
        created: "Scenario mode created",
        updated: "Scenario mode updated",
        deleted: "Scenario mode deleted",
        switched: "Switched to: {{name}}"
      }
    },
    toast: {
      syncFailed: "Sync failed",
      syncLocalApplied: "Local configuration applied",
      linkCopied: "Link copied",
      linkCopyFailed: "Failed to copy link",
      loadedFromCache: "Loaded from local cache (Offline Mode)",
      shortcutCreateFailed: "Unable to create shortcut",
        alreadyOnPage: "Already on the current page"
      },
      leaftabSync: {
        provider: {
          webdav: "WebDAV sync",
          generic: "Sync"
        },
        webdav: {
          actions: {
            mkcol: "Create folder",
            upload: "Write",
            download: "Read",
            delete: "Delete"
          },
          error: {
            withPath: "WebDAV {{action}} failed ({{status}}): {{path}}",
            noPath: "WebDAV {{action}} failed ({{status}})"
          }
        },
      },
      leaftabSyncRunner: {
        progressDetailDefault: "Syncing in background. You can continue using Aira.",
        permissionTitle: "Checking bookmark permission",
        permissionDetail: "Aira needs permission to access bookmarks.",
        bookmarksPermissionDeniedToast: "Bookmark permission not granted. This run will sync shortcuts and settings only.",
        bookmarksPermissionDeniedToastAlt: "Bookmark permission not granted. Only shortcuts and settings will be synced.",
        successTitle: "Sync complete",
        successToastFallback: "Sync complete",
        successDetailFallback: "Local and remote data have been processed.",
        webdav: {
          prepareTitle: "Preparing sync",
          prepareDetail: "Reading local and WebDAV status",
          disable: {
            title: "Disabling sync",
            detail: "Running the final sync and turning off sync",
            finalSyncTitle: "Syncing final changes",
            closingTitle: "Turning off sync",
            clearingTitle: "Clearing local data",
            doneTitle: "Sync disabled"
          }
        },
      },
      leaftabSyncActions: {
        dataDetail: {
          withBookmarks: "Processing shortcuts and bookmarks",
          shortcutsOnly: "Processing shortcuts"
        },
        bookmarksPermissionRequired: "Bookmark permission not granted. Unable to repair sync.",
        webdav: {
          inProgress: "WebDAV sync is in progress. Please wait.",
          syncingTitle: "Syncing to WebDAV",
          repair: {
            pullTitle: "Overwriting local data with WebDAV",
            pushTitle: "Overwriting WebDAV with local data",
            pullSuccess: "Local data overwritten with WebDAV data",
            pushSuccess: "WebDAV overwritten with local data",
            pullFailed: "Failed to overwrite local data with WebDAV",
            pushFailed: "Failed to overwrite WebDAV with local data"
          }
        },
      },
      leaftabSyncCenter: {
      title: "Sync Center",
      description: "A WebDAV-based sync center focused on scenarios, shortcuts, and bookmarks.",
      bookmarkScope: "Bookmark sync scope: {{scope}}",
      summary: "{{shortcuts}} shortcuts, {{scenarios}} scenarios, {{bookmarks}} bookmarks",
      stateLabel: "Status",
      nav: {
        syncing: "Syncing",
        attention: "Needs attention"
      },
      status: {
        syncing: "Syncing",
        conflict: "Action required",
        error: "Failed",
        ready: "Ready"
      },
      state: {
        analyzing: "Analyzing sync status...",
        syncing: "Syncing in background",
        syncingDescription: "Aira is comparing local and remote data and writing back changes. Just wait for it to finish.",
        initRequired: "Initialization required",
        initDescription: "Both local and remote have data. Choose an initialization strategy first, then background sync can start.",
        ready: "Merge sync is ready",
        readyDescription: "The new sync engine can push, pull, and merge scenarios, shortcuts, and your browser bookmarks root."
      },
      actions: {
        syncing: "Syncing..."
      }
    },
    leaftabSyncDialog: {
      description: "Manage Aira sync status, manual sync, and WebDAV configuration here.",
      scopeDefault: "Bookmarks",
      lastSyncEmpty: "No records",
      lastSyncUnavailable: "Not synced",
      manualSyncOnly: "Manual sync only",
      autoSyncOn: "Auto sync is on",
      enableSync: "Enable sync",
      disableSync: "Disable sync",
      repair: "Repair sync",
      remoteOverwriteLocal: "WebDAV overwrites local",
      localOverwriteRemote: "Local overwrites WebDAV",
      tabs: {
        webdav: "WebDAV"
      },
      metrics: {
        localShortcuts: "Local shortcuts",
        localBookmarks: "Local bookmarks",
        remoteShortcuts: "Remote shortcuts",
        remoteBookmarks: "Remote bookmarks"
      },
      details: {
        lastSync: "Last sync",
        nextSync: "Next sync",
        scope: "Scope"
      },
      webdav: {
        connectedFallback: "WebDAV",
        unconfiguredTitle: "WebDAV not enabled",
        unconfiguredSubtitle: "Not configured, set it up first",
        enabledSubtitle: "Configured, syncing to WebDAV",
        disabledSubtitle: "Configured, sync is disabled",
        configureToStart: "Configure",
        enableToStart: "Configured, enable to start",
        scopeWithLabel: "Shortcuts, {{scope}}"
      }
    },
	    leaftabDangerousSync: {
	      title: "Risky Sync Intercepted",
	      description: "A significant change in bookmark counts was detected. Auto-sync has been paused.",
	      riskDescription: "Bookmarks are expected to change from {{from}} to {{to}}, potentially removing about {{loss}} items.",
	      localBookmarks: "Local bookmarks",
	      remoteBookmarks: "{{provider}} bookmarks",
	      continueWithoutBookmarks: "Continue syncing shortcuts and settings",
	      continueWithoutBookmarksHint: "This will not change bookmarks in this run; only shortcuts and settings will be synced.",
	      deferBookmarks: "Handle bookmarks later",
	      advancedActions: "Advanced",
	      useRemotePlain: "Keep {{provider}} bookmarks (local will be replaced)",
	      useLocalPlain: "Keep local bookmarks ({{provider}} will be replaced)",
	      toast: {
	        skipBookmarks: "This run will skip bookmarks and sync shortcuts and settings only.",
	        webdavBookmarksDisabled: "WebDAV sync is enabled, but “Sync bookmarks” is temporarily turned off."
	      }
	    },
    pagination: {
      page: "Page {{page}}"
    },
    bookmarks: {
      roots: {
        toolbar: "Bookmarks bar",
        other: "Other bookmarks",
        mobile: "Mobile bookmarks"
      },
      scope: {
        rootsLabel: "Bookmarks bar, Other bookmarks"
      },
      errors: {
        permissionDenied: "Bookmarks permission not granted. Sync stopped to protect existing bookmarks.",
        apiUnsupported: "Bookmarks API is not available in this environment.",
        apiCallFailed: "Bookmarks API call failed"
      }
    }
  }
};
