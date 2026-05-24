export default {
  translation: {    settings: {
      title: "设置",
      newTabMode: {
        label: "新标签页打开",
        description: "快捷方式默认在新标签页中打开"
      },
      preventDuplicateNewTab: {
        label: "避免重复打开 Aira",
        description: "新建标签页时，若当前窗口已有 Aira，则直接切换过去并关闭新开的重复页",
        permissionDenied: "未授予标签页权限，无法启用避免重复打开 Aira。",
        permissionFailed: "申请标签页权限失败，请重试。"
      },
      searchEngineTabSwitch: {
        label: "Tab 切换搜索引擎",
        description: "聚焦搜索框时，按 Tab 在搜索引擎间循环切换"
      },
      searchSettings: {
        label: "搜索设置",
        description: "把搜索功能调成你习惯的方式",
        open: "打开",
        title: "搜索设置",
        items: {
          tabSwitch: {
            label: "Tab 切换搜索引擎",
            description: "搜索框聚焦后按 Tab 切换引擎\n按 Shift+Tab 可切回上一个",
            tooltip: "先点一下搜索框，再按 Tab 切到下一个引擎；按 Shift+Tab 切回上一个。"
          },
          prefix: {
            label: "临时搜索引擎面板",
            description: "输入 ! 打开引擎面板并选择目标\n选中后只影响这一次搜索，不改默认引擎",
            tooltip: "例如先输入 !，再选 Google 或百度，左侧会显示一个主色标签，随后输入关键词即可。"
          },
          siteDirect: {
            label: "@ 目标面板",
            description: "输入 @ 打开目标面板\n可选 GitHub、Bilibili、ChatGPT、Gemini 等，再输入内容",
            tooltip: "站点直达搜索和 AI 目标都统一收进 @ 面板；选中后会在左侧显示一个主色标签，再继续输入内容。"
          },
          siteShortcut: {
            label: "@ 面板站点建议",
            description: "控制 @ 面板里是否显示常用站点目标\n关闭后仅保留 AI 等目标",
            tooltip: "开启后，在 @ 面板中会出现 GitHub、B站、知乎、YouTube 等常用站点目标。"
          },
          anyKeyCapture: {
            label: "任意键直接搜索",
            description: "打开新标签页后直接打字\n自动聚焦搜索框并开始输入",
            tooltip: "不用先点击搜索框，在页面空白处输入字符会自动聚焦并开始输入。"
          },
          calculator: {
            label: "计算器预览",
            description: "输入算式会实时显示结果\n回车可填入并复制计算值",
            tooltip: "例如 12*8、(3+5)/2 会显示计算结果；按回车会把结果填入并复制到剪贴板。"
          },
          rotatingPlaceholder: {
            label: "搜索框提示轮播",
            description: "让搜索框里的能力提示自动轮播\n默认开启，关闭后固定显示单条默认提示",
            tooltip: "会轮播展示 @ 面板、! 引擎面板、/ 范围面板、结果快捷操作等提示。"
          },
          position: {
            label: "搜索框位置",
            description: "选择搜索框显示在快捷方式区域的上方还是下方",
            tooltip: "切换后会立即生效，并记住你当前选择的位置。",
            top: "上面",
            bottom: "下面"
          }
        }
      },
      shortcutGuide: {
        label: "快捷键与操作",
        description: "查看常用快捷方式和对应操作",
        open: "查看",
        title: "快捷键与操作",
        dialogDescription: "Aira 快捷键与操作说明",
        helper: "以下内容只展示当前版本已经支持的快捷操作，方便随时查阅。",
        countSuffix: "项",
        columns: {
          shortcut: "快捷键",
          action: "对应操作"
        },
        sections: {
          search: "搜索",
          results: "结果列表"
        },
        items: {
          focusSearch: "聚焦搜索框并选中当前内容",
          switchEngine: "在搜索框中按 Tab 或 Shift+Tab 切换搜索引擎",
          temporaryEnginePrefix: "输入 ! 打开引擎面板，选中后只对当前这次搜索生效",
          switchScenarioNext: "不在输入状态时，循环切换到下一个情景模式",
          bookmarksMode: "进入书签搜索模式，首次使用时可能会请求书签权限",
          bookmarksModeStore: "进入书签搜索模式，直接搜索浏览器书签",
          tabsMode: "进入标签页搜索模式，首次使用时可能会请求标签页权限",
          tabsModeStore: "进入标签页搜索模式，直接搜索已打开标签页",
          navigateResults: "在结果列表中上下移动选择",
          openResult: "打开当前选中的结果",
          closePanel: "关闭当前结果面板",
          showNumberHints: "在结果列表中显示数字提示",
          openNumberedResult: "按对应数字直接打开结果"
        },
        footer: "提示：数字提示和数字直达只在结果列表打开时生效；输入 ! 可打开引擎面板，输入 @ 可打开目标面板，输入 / 可打开范围与设置面板。"
      },
      timeFormat: {
        label: "24 小时制",
        description: "使用 24 小时制显示时间"
      },
      showSeconds: {
        label: "显示秒数",
        description: "在时间组件中显示秒数"
      },
      showLunar: {
        label: "显示农历",
        description: "在时间下方显示农历日期"
      },
      timeAnimation: {
        label: "动画效果",
        description: "时间切换滚动动画",
        performanceHint: "时间数字动画会增加持续渲染开销，低性能设备建议关闭。",
        followSystemBadge: "跟随系统",
        followSystemAction: "恢复跟随系统",
        followSystemEnabled: "当前跟随系统：已开启",
        followSystemReduced: "当前跟随系统：已关闭",
        overrideOn: "已单独开启，不受系统限制",
        overrideOff: "已单独关闭"
      },
      showTime: {
        label: "显示时间",
        description: "在页面中显示时间组件"
      },
      timeDisplay: {
        title: "时间显示",
        description: "设置时间样式与显示内容"
      },
      autoFocusSearch: {
        label: "自动聚焦搜索框",
        description: "进入页面时自动将光标聚焦在搜索框"
      },
      language: {
        label: "语言",
        description: "选择界面显示语言",
        selectPlaceholder: "选择语言"
      },
      openSyncCenter: "打开同步中心",
      syncCenterMoved: "同步入口已从设置中拆出。现在可以在主页右上角直接打开同步中心，处理手动同步和书签同步状态。",
      syncCenterShortcut: "完整同步状态与书签同步范围，请直接从主页右上角进入同步中心。",
      theme: {
        label: "主题",
        description: "切换浅色/深色主题，或跟随系统自动切换",
        selectPlaceholder: "选择主题",
        system: "跟随系统",
        light: "浅色",
        dark: "深色"
      },
      accentColor: {
        label: "主题色",
        description: "选择应用的主色调"
      },
      accent: {
        dynamic: "动态",
        mono: "黑白",
        green: "绿色",
        blue: "蓝色",
        purple: "紫色",
        orange: "橙色",
        pink: "粉色",
        red: "红色"
      },
      displayMode: {
        title: "布局模式",
        description: "选择页面显示风格",
        blank: "极简",
        blankDesc: "隐藏时间、壁纸与快捷方式",
        rhythm: "标准",
        rhythmDesc: "仅保留搜索与快捷方式"
      },
      shortcutsLayout: {
        label: "快捷方式密度",
        description: "调整每列显示的快捷方式数量",
        set: "设置",
        select: "选择"
      },
      shortcutsStyle: {
        label: "快捷方式布局",
        entryDescription: "设置网格列数与名称显示方式",
        open: "打开",
        title: "快捷方式布局设置",
        description: "设置单页网格的列数与快捷方式名称显示方式",
        rich: "丰富",
        compact: "简约",
        showName: "显示名称",
        showNameDesc: "开启后在图标下显示快捷方式标题",
        columns: "网格列数",
        rows: "基础行数"
      },
      shortcutIconSettings: {
        label: "图标设置",
        entryDescription: "调整快捷方式图标的颜色模式与圆角",
        open: "打开",
        title: "图标设置",
        description: "调整快捷方式图标的颜色模式与圆角形状。",
        modeLabel: "颜色模式",
        colorful: "彩色",
        monochrome: "单色",
        accent: "强调色",
        modeReservedHint: "单色和强调色会统一重绘图标颜色。",
        cornerRadius: "圆角",
        size: "图标大小"
      },
      backup: {
        bookmarksLabel: "书签导入导出",
        bookmarksDescription: "支持 Chrome、Edge 等浏览器的书签 HTML 格式",
        webdavTab: "WebDAV 同步",
        importBookmarks: "导入书签",
        exportBookmarks: "导出书签",
        bookmarkImportSuccess: "已导入 {{count}} 个书签",
        importError: "书签导入失败，请检查文件格式",
        exportSuccess: "书签导出成功",
        exportError: "书签导出失败",
        webdav: {
          entry: "WebDAV 同步",
          entryDesc: "配置 WebDAV 书签同步",
          configure: "配置",
          syncBookmarksLabel: "同步书签",
          syncBookmarksDesc: "WebDAV 只同步浏览器书签，不再同步 Aira 布局、设置或账号数据。",
          bookmarkSyncSafetyReminderTitle: "开启前提醒",
          bookmarkSyncSafetyReminderA11yDescription: "开启书签同步前的提醒说明",
          bookmarkSyncSafetyReminderLine1: "同步用于多设备保持一致，不等同于备份。",
          bookmarkSyncSafetyReminderLine2: "书签同步仍处于测试阶段，少数情况下可能出现延迟或异常。",
          bookmarkSyncSafetyReminderLine3: "建议先导出本地备份，再开启书签同步。",
          bookmarkSyncSafetyReminderCancel: "我先备份",
          bookmarkSyncSafetyReminderConfirm: "继续开启",
          url: "WebDAV 地址",
          username: "用户名",
          password: "密码",
          profileName: "配置名称",
          profileNamePlaceholder: "例如：家庭 NAS",
          usernamePlaceholder: "可选",
          passwordPlaceholder: "可选",
          syncByScheduleLabel: "定时自动同步",
          syncByScheduleDesc: "按固定时间间隔自动同步，适合长期开着页面",
          autoSyncToastLabel: "自动同步成功提示",
          autoSyncToastDesc: "定时自动同步成功后显示提示",
          syncIntervalLabel: "同步间隔",
          syncIntervalMinutes: "{{count}} 分钟",
          enabledLabel: "开启 WebDAV 同步",
          enabledDesc: "关闭后将暂停 WebDAV 自动与手动同步",
          providerCustom: "自定义服务",
          providers: {
            jianguoyun: "坚果云",
          },
          providerLabel: "WebDAV 服务商",
          providerPlaceholder: "选择服务商",
          syncSuccess: "数据同步成功",
          syncError: "同步失败，请检查配置",
          authFailed: "WebDAV 认证失败，请检查账号或密码",
          configSaved: "WebDAV 设置已保存",
          disableConfirmTitle: "关闭 WebDAV 同步",
          disableConfirmDesc: "确定要关闭 WebDAV 同步吗？关闭后仅保留本地数据。",
          clearLocalLabel: "清除本地数据并恢复初始",
          clearLocalDesc: "将本地快捷方式恢复为默认初始配置",
          urlRequired: "请先填写 WebDAV 地址",
          defaultProfileName: "默认配置",
          configured: "已配置，可同步到 WebDAV",
          disabled: "已停用",
          syncOffTitle: "WebDAV 未开启",
          configureAction: "去配置",
          enableSyncAction: "开启同步",
          notConfigured: "未配置，先去配置",
          lastSyncAt: "上次同步时间",
          notSynced: "未同步",
          justSynced: "刚刚已同步",
          minutesAgo: "{{count}} 分钟前同步",
          hoursAgo: "{{count}} 小时前同步",
          lastAttemptFailed: "最近尝试同步失败",
          scheduleRunning: "定时同步运行中",
          nextSyncAtLabel: "下次同步：{{time}}",
          syncDisabled: "请先开启 WebDAV 同步",
          disableFinalSyncFailed: "关闭前最后一次同步失败，已按你的操作关闭同步",
          enableConflictTitle: "检测到同步冲突",
          enableConflictDesc: "WebDAV 与本地数据不一致，请选择处理方式。"
        }
      },
      about: {
        label: "关于 Aira",
        description: "查看应用简介与版本信息",
        open: "查看",
        title: "关于",
        intro: "Aira 是一个专注、轻量的新标签页工具，提供搜索、快捷方式、浏览器书签搜索、WebDAV 书签同步与壁纸外观设置。",
        version: "版本",
        highlights: {
          bookmarks: "以浏览器书签和快捷方式为核心",
          sync: "通过 WebDAV 同步书签，不绑定自建账号体系",
          privacy: "数据优先保存在本地，由用户自己掌控"
        }
      },
      privacyPolicy: "隐私政策",
      copyright: "保留所有权利。",
      specialThanks: "特别感谢测试人员：yanshuai、Horang、Mling",
    },
    languages: {
      zh: "中文",
      en: "English"
    },
    wallpaper: {
      mode: "壁纸设置",
      modeDesc: "设置页面壁纸",
      bing: "bing",
      color: "颜色壁纸",
      custom: "自定义",
      uploadTitle: "上传自定义壁纸",
      upload: "上传图片",
      uploadDesc: "点击上传或者拖动图像到此区域都可以",
      download: "下载",
      setAsWallpaper: "设为壁纸",
      apply: "设为壁纸",
      bingDesc: "每天自动更新来自 Bing 的壁纸。",
      customDesc: "上传您自己的图片作为壁纸。",
      customUploaded: "您上传的壁纸。",
      imageSupport: "支持 JPG, PNG, WEBP 格式",
      maskOpacity: "黑色遮罩",
      autoDimInDarkMode: "深色模式自动调暗壁纸",
      autoDimInDarkModeDesc: "深色模式下自动额外增加黑色遮罩，提升可读性。",
      autoRotate: "自动更换壁纸",
      autoRotateDesc: "只在当前壁纸类型内按系统时间轮换，不会切换到别的类型。",
      autoRotateUnavailableDesc: "当前类型会自行更新，暂不支持自动轮换。",
      rotation: {
        off: "不更换",
        hourly: "每小时",
        sixHours: "每 6 小时",
        daily: "每天"
      },
      colorPresets: {
        "aurora-blush": "极光粉雾",
        "mist-lilac": "晨雾紫",
        "mint-breeze": "薄荷风",
        "peach-cloud": "蜜桃云",
        "glacier-milk": "冰川奶蓝",
        "rose-water": "玫瑰水",
        "sage-cream": "鼠尾奶绿",
        "dawn-sand": "晨砂",
        "lavender-snow": "薰衣雪",
        "ocean-haze": "海雾",
        "camellia-silk": "山茶绢",
        "tea-ivory": "茶米白"
      }
    },
    common: {
      loading: "加载中...",
      cancel: "取消",
      close: "关闭",
      confirm: "确定",
      settings: "设置",
      delete: "删除",
      save: "保存",
      current: "当前使用",
      clear: "清空",
      back: "返回",
      more: "更多"
    },
    lunar: {
      label: "农历"
    },
	    leaftabSync: {
	      provider: {
	        webdav: "WebDAV 同步",
	        generic: "同步"
	      },
	      webdav: {
	        actions: {
	          mkcol: "创建目录",
	          upload: "写入",
	          download: "读取",
	          delete: "删除"
	        },
	        error: {
	          withPath: "WebDAV {{action}}失败（{{status}}）：{{path}}",
	          noPath: "WebDAV {{action}}失败（{{status}}）"
	        }
	      },
	    },
	    leaftabSyncRunner: {
	      progressDetailDefault: "正在后台同步，你可以继续进行其他操作",
	      permissionTitle: "正在检查书签权限",
	      permissionDetail: "需要确认当前浏览器允许访问书签数据",
	      bookmarksPermissionDeniedToast: "未授予书签权限，本次仅同步快捷方式和设置",
	      bookmarksPermissionDeniedToastAlt: "书签权限未授权，当前仅同步快捷方式和设置",
	      successTitle: "同步完成",
	      successToastFallback: "同步完成",
	      successDetailFallback: "本地与云端已经处理完成",
	      webdav: {
	        prepareTitle: "正在准备同步数据",
	        prepareDetail: "正在读取本地与云端状态",
	        disable: {
	          title: "正在停用同步",
	          detail: "正在处理最后一次同步和关闭操作",
	          finalSyncTitle: "正在同步最后的变更",
	          closingTitle: "正在关闭同步",
	          clearingTitle: "正在清理本地数据",
	          doneTitle: "同步已停用"
	        }
	      },
	    },
	    leaftabSyncActions: {
	      dataDetail: {
	        withBookmarks: "正在处理快捷方式和书签数据",
	        shortcutsOnly: "正在处理快捷方式数据"
	      },
	      bookmarksPermissionRequired: "未授予书签权限，无法执行修复同步",
	      webdav: {
	        inProgress: "WebDAV 同步正在进行中，请稍候",
	        syncingTitle: "正在同步到 WebDAV",
	        repair: {
	          pullTitle: "正在用 WebDAV 覆盖本地",
	          pushTitle: "正在用本地覆盖 WebDAV",
	          pullSuccess: "已用 WebDAV 数据覆盖本地",
	          pushSuccess: "已用本地数据覆盖 WebDAV",
	          pullFailed: "WebDAV 覆盖本地失败",
	          pushFailed: "本地覆盖 WebDAV 失败"
	        }
	      },
	    },
	    leaftabSyncCenter: {
      title: "同步中心",
      description: "基于 WebDAV 的同步中心，当前重点支持场景、快捷方式和书签同步。",
      bookmarkScope: "书签同步范围：{{scope}}",
      summary: "{{shortcuts}} 个快捷方式，{{scenarios}} 个场景，{{bookmarks}} 个书签",
      stateLabel: "状态",
      initAction: "初始化同步",
      nav: {
        syncing: "同步中",
        attention: "同步异常"
      },
      status: {
        syncing: "同步中",
        conflict: "需要处理",
        error: "同步失败",
        ready: "就绪"
      },
      state: {
        analyzing: "正在分析同步状态...",
        syncing: "正在后台同步",
        syncingDescription: "Aira 正在后台比对本地与云端差异，并写回需要更新的数据。界面没有卡住，等待完成即可。",
        initRequired: "需要初始化",
        initDescription: "本地和云端都已经有数据，请先选择首次初始化方式，再开启后台同步。",
        ready: "合并同步已就绪",
        readyDescription: "新的同步引擎已经可以对场景、快捷方式，以及浏览器真实书签根执行推送、拉取与合并同步。"
      },
      actions: {
        syncing: "后台同步中..."
      }
    },
    leaftabSyncDialog: {
      description: "这里单独管理 Aira 的同步状态、手动同步与 WebDAV 配置。",
      scopeTitle: "当前纳入同步的数据",
      scopeDescription: "当前重点同步场景、快捷方式，以及浏览器里的书签栏和其他书签。",
      scopeBadge: "新引擎",
      scopeScenarios: "场景 {{count}}",
      scopeShortcuts: "快捷方式 {{count}}",
      scopeBookmarks: "书签 {{count}}",
      bookmarkScopeNote: "书签同步范围：{{scope}}",
      runtimeTitle: "运行状态",
      runtimeBusy: "正在后台执行同步，请等待当前轮次完成。",
      runtimeIdle: "当前界面可随时查看状态、手动触发同步，或调整 WebDAV 配置。",
      runtimeBusyNote: "如果你刚刚点了“立即同步”或“启用同步”，现在不是卡住了，而是在后台读取本地数据、对比云端快照并写回差异。",
      runtimeReadyNote: "建议先完成 WebDAV 配置。之后所有同步都会默认自动合并本地与云端数据。",
      webdavPath: "地址：{{value}}",
      webdavLastSync: "上次同步：{{value}}",
      lastError: "最近一次错误",
      disableSync: "停用同步",
      enableSync: "启用同步",
      scopeDefault: "书签",
      lastSyncEmpty: "暂无记录",
      lastSyncUnavailable: "未同步",
      manualSyncOnly: "当前仅手动同步",
      autoSyncOn: "自动同步已开启",
      repair: "修复同步",
      remoteOverwriteLocal: "WebDAV 覆盖本地",
      localOverwriteRemote: "本地覆盖 WebDAV",
      tabs: {
        webdav: "WebDAV 同步"
      },
      metrics: {
        localShortcuts: "本地快捷方式",
        localBookmarks: "本地书签",
        remoteShortcuts: "云端快捷方式",
        remoteBookmarks: "云端书签"
      },
      details: {
        lastSync: "上次同步",
        nextSync: "下次同步",
        scope: "同步范围"
      },
      webdav: {
        connectedFallback: "WebDAV",
        unconfiguredTitle: "WebDAV 未开启",
        unconfiguredSubtitle: "未配置，先去配置",
        enabledSubtitle: "已配置，可同步到 WebDAV",
        disabledSubtitle: "已配置，尚未启用同步",
        configureToStart: "配置后设置",
        enableToStart: "已配置，待启用",
        scopeWithLabel: "快捷方式、{{scope}}"
      }
    },
    search: {
      placeholder: "想找什么？直接输入就行",
      placeholderDynamic: "可搜标签页、书签、历史、快捷方式，网址也能直接打开",
      placeholderHintTabSwitch: "按 Tab 切换搜索引擎，或输入 ! 打开临时引擎面板",
      placeholderHintCalculator: "输入 12*8 这种算式，可直接计算",
      placeholderHintSiteDirect: "输入 @ 打开目标面板，可选 GitHub、Bilibili、ChatGPT 等",
      placeholderHintPrefix: "输入 ! 打开引擎面板，选中后再输入内容即可临时切换搜索引擎",
      placeholderHintSettings: "输入 / 打开范围与设置面板，也可搜“主题模式”“图标大小”等直达设置",
      placeholderHintActions: "选中结果后按 →，可关闭标签页、复制链接、添加快捷方式",
      aiPromptPlaceholder: "向{{provider}}提问",
      sitePromptPlaceholder: "在{{site}}中搜索",
      enginePromptPlaceholder: "用{{engine}}搜索",
      scopePromptPlaceholder: "继续输入内容以搜索{{scope}}",
      aiSubmitSent: "已将问题发送到{{provider}}",
      aiSubmitFilled: "已打开{{provider}}，并填入问题",
      aiSubmitOpened: "已打开{{provider}}，请手动输入或粘贴",
      aiSubmitCopiedAndOpened: "已复制内容并打开{{provider}}，请手动粘贴发送",
      aiSubmitCopyFailed: "复制内容或打开{{provider}}失败，请重试",
      aiSubmitFailed: "打开{{provider}}失败，请重试",
      aiPasteNotice: "已为{{provider}}复制问题，按{{shortcut}}粘贴后发送",
      atPanelPinned: "已置顶到前面",
      atPanelUnpinned: "已取消置顶",
      aiProvidersEmpty: "没有匹配的目标",
      secondaryAction: {
        pinAtTarget: "置顶到最前",
        unpinAtTarget: "取消置顶",
        copyLink: "复制链接"
      },
      bang: {
        detail: "仅本次搜索使用这个引擎",
        empty: "没有匹配的搜索引擎"
      },
      enterKey: "回车",
      actionOpen: "打开",
      actionClose: "关闭",
      actionSelect: "选择",
      authorizeHistoryPermission: "去授权",
      historyPermissionBanner: "授权后可显示浏览器历史记录",
      historyPermissionPending: "正在等待历史记录权限确认...",
      historyPreparing: "正在加载浏览器历史记录...",
      bookmarksPermissionBanner: "授权后可搜索浏览器书签",
      bookmarksPermissionPending: "正在等待书签权限确认...",
      bookmarksPreparing: "正在整理书签，请稍候...",
      tabsPermissionBanner: "授权后可搜索已打开标签页",
      tabsPermissionPending: "正在等待标签页权限确认...",
      tabsPreparing: "正在整理已打开标签页，请稍候...",
      permissionHistoryDenied: "未授予历史记录权限，你可以在下拉面板顶部再次授权。",
      permissionBookmarksDenied: "未授予书签权限，下次使用 /b 时可以再次申请。",
      permissionTabsDenied: "未授予标签页权限，下次使用 /t 时可以再次申请。",
      permissionRequestFailed: "权限申请失败，请重试。",
      noBookmarks: "没有找到匹配的书签",
      noTabs: "没有找到匹配的标签页",
      currentTabLabel: "当前标签页",
      systemEngine: "系统默认",
      useEngineSearch: "使用{{engine}} 搜索",
      prefixEngineInlineHint: "本次使用{{engine}}搜索",
      historyTitle: "搜索历史",
      clearHistory: "清空",
      noHistory: "暂无搜索记录",
      remoteSuggestionSource: "搜索建议",
      justNow: "刚刚"
    },
    groups: {
      edit: "编辑",
      addShortcut: "新建快捷方式"
    },
    context: {
      open: "打开",
      edit: "编辑",
      copyLink: "复制链接",
      delete: "删除",
      deleteFolder: "删除文件夹",
      addShortcut: "添加快捷方式",
      newShortcut: "新建快捷方式",
      pinToTop: "置顶",
      pinTop: "置顶已选",
      pinBottom: "置底已选",
      select: "选择",
      unselect: "取消选择",
      selectedCount: "已选 {{count}} 项",
      selectAll: "全选",
      deleteSelected: "删除已选",
      moveToScenario: "移动到情景模式",
      movedToScenarioToast: "已将 {{count}} 项移动到“{{scenario}}”",
      noScenarioTarget: "暂无可移动的目标情景模式",
      selectBeforeMove: "请先选择快捷方式",
      multiSelect: "多选",
      cancelMultiSelect: "退出多选"
    },
    sidebar: {
      toggle: "切换侧边栏",
      title: "侧边栏",
      description: "显示移动端侧边栏。"
    },
    shortcutModal: {
      addTitle: "添加快捷方式",
      editTitle: "编辑快捷方式",
      nameLabel: "名称",
      namePlaceholder: "请输入快捷方式标题",
      urlLabel: "网址",
      urlPlaceholder: "请输入网址",
      icon: {
        modeGroup: "图标来源",
        modeFaviconShort: "网络",
        modeLetterShort: "文字",
        modeCustomShort: "自定义",
        modeCustomReplaceShort: "更改",
        modeCustomLoadingShort: "处理中",
        networkHint: "网络图标可能加载失败，失败时会自动回退为文字图标",
        customFileInvalid: "这张图片暂时无法作为图标，请换一张试试"
      },
      errors: {
        fillAll: "请填写完整信息",
        fillAllDesc: "请输入快捷方式标题和链接地址",
        duplicateUrl: "该网站已存在快捷方式",
        duplicateUrlDesc: "同一网站仅保留一个快捷方式，请检查网址后重试"
      }
    },
    popupShortcut: {
      title: "添加当前页面",
      loading: "正在读取当前标签页信息…",
      unsupported: "当前页面不是可直接保存的网站链接，请改成 http 或 https 地址后再保存。",
      targetScenario: "将保存到「{{name}}」场景",
      ready: "已自动填入当前标签页标题和网址。",
      saved: "快捷方式已保存",
      scenarioLabel: "保存到情景模式",
      scenarioPlaceholder: "选择情景模式"
    },
    onboarding: {
      welcome: "欢迎使用 Aira",
      skip: "跳过",
      start: "开始体验",
      next: "下一步",
      layoutTip: "布局稍后可在设置中修改",
      stepAppearanceTitle: "设置主题与语言",
      stepAppearanceDesc: "选择外观与界面语言，稍后可在设置中修改",
      stepLayoutTitle: "选择布局样式",
      stepLayoutDesc: "确定首页展示的排布方式",
      stepPermissionsTitle: "授权访问权限",
      stepPermissionsDesc: "完成历史记录与书签授权后，搜索与直达能力会更完整",
      historyPermissionTitle: "访问历史记录",
      historyPermissionDesc: "授权后可在 Aira 中显示最近浏览与相关搜索建议",
      bookmarksPermissionTitle: "访问书签",
      bookmarksPermissionDesc: "授权后可直接搜索和打开浏览器书签内容",
      tabsPermissionTitle: "访问浏览器标签页",
      tabsPermissionDesc: "授权后可启用标签页搜索，并避免重复打开 Aira 新标签页",
      authorize: "去授权",
      authorizing: "授权中...",
      authorized: "已授权",
      unsupported: "暂不支持",
      permissionTip: "这两项都可以稍后在使用过程中再授权，不会影响先进入主页。",
      enterHome: "进入首页"
    },
    shortcutDelete: {
      confirm: "删除",
      cancel: "取消",
      title: "删除快捷方式",
      description: "确定要删除这个快捷方式吗？",
      folderTitle: "删除文件夹",
      folderDescription: "确定要删除这个文件夹吗？文件夹里的所有内容也会一起删除。"
    },
    scenario: {
      title: "情景模式",
      defaultName: "Working mode",
      unnamed: "未命名",
      createTitle: "新建情景模式",
      createDescription: "设置名称、颜色与图标",
      editTitle: "编辑情景模式",
      editDescription: "修改名称、颜色与图标",
      nameLabel: "模式名称",
      namePlaceholder: "请输入模式名称",
      colorLabel: "颜色",
      iconLabel: "图标",
      actionEdit: "编辑情景模式",
      actionDelete: "删除情景模式",
      colorPicker: "选择颜色",
      iconPicker: "选择图标",
      createButton: "新建情景模式",
      addButton: "添加",
      saveButton: "保存",
      deleteTitle: "删除情景模式",
      deleteConfirm: "确定要删除该情景模式吗？删除后将同时移除该模式下的所有分组和快捷方式，且无法恢复，请谨慎操作。",
      deleteConfirmWithTarget: "确定要删除「{{name}}」吗？删除后将同时移除该模式下的所有分组和快捷方式，且无法恢复，请谨慎操作。",
      deleteButton: "删除",
      toast: {
        created: "已添加情景模式",
        updated: "已更新情景模式",
        deleted: "已删除情景模式",
        switched: "已切换到：{{name}}"
      }
    },
    toast: {
      syncFailed: "同步失败",
      syncLocalApplied: "已使用本地配置",
      linkCopied: "链接已复制",
      linkCopyFailed: "复制链接失败",
      loadedFromCache: "已加载本地缓存（离线模式）",
      shortcutCreateFailed: "无法创建快捷方式",
      alreadyOnPage: "已在当前页"
    },
    pagination: {
      page: "第 {{page}} 页"
    },
    bookmarks: {
      roots: {
        toolbar: "书签栏",
        other: "其他书签",
        mobile: "移动书签"
      },
      scope: {
        rootsLabel: "书签栏、其他书签"
      },
      errors: {
        permissionDenied: "未授予书签权限，已停止同步以保护现有书签数据",
        apiUnsupported: "当前环境不支持书签 API",
        apiCallFailed: "书签 API 调用失败"
      }
    }
  }
};
