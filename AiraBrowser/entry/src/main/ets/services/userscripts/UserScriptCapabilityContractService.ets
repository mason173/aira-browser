import { UserScriptGrant, InstalledUserScriptState } from '../../features/userscripts/UserScriptMetadataModels';
import {
  UserScriptNativeBridgeExecutorKind,
  UserScriptNativeBridgeRequestKind,
  UserScriptNativeBridgeRoute
} from '../../features/userscripts/UserScriptNativeBridgeModels';

interface UserScriptNativeRouteDescriptor {
  requestKind: UserScriptNativeBridgeRequestKind;
  executor: UserScriptNativeBridgeExecutorKind;
}

interface UserScriptCapabilityDescriptor {
  grant: UserScriptGrant;
  flagName: string;
  aliases: string[];
  satisfiedBy: UserScriptGrant[];
  runtimeExposed: boolean;
  managementLabel: string;
  nativeRoute?: UserScriptNativeRouteDescriptor;
}

interface UserScriptCapabilityRuntimeManifest {
  grantFlagsLiteral: string;
  nativeRoutesLiteral: string;
}

interface UserScriptSourceGrantCacheEntry {
  updatedAt: number;
  sourceLength: number;
  grants: UserScriptGrant[];
}

const USER_SCRIPT_CAPABILITIES: UserScriptCapabilityDescriptor[] = [
  capability('none', 'none', [], ['none'], false, ''),
  capability('GM_addStyle', 'addStyle', ['GM.addStyle'], ['GM_addStyle'], true, '修改页面样式'),
  capability('GM_addElement', 'addElement', ['GM.addElement'], ['GM_addElement'], true, '添加页面元素'),
  capability('GM_getValue', 'getValue', ['GM.getValue'], ['GM_getValue'], true, '保存脚本数据', nativeRoute('getValue', 'value_read')),
  capability('GM_getValues', 'getValues', ['GM.getValues'], ['GM_getValues'], true, '保存脚本数据', nativeRoute('getValue', 'value_read')),
  capability('GM_setValue', 'setValue', ['GM.setValue'], ['GM_setValue'], true, '保存脚本数据', nativeRoute('setValue', 'value_set')),
  capability('GM_setValues', 'setValues', ['GM.setValues'], ['GM_setValues'], true, '保存脚本数据', nativeRoute('setValue', 'value_set')),
  capability('GM_deleteValue', 'deleteValue', ['GM.deleteValue'], ['GM_deleteValue'], true, '保存脚本数据', nativeRoute('deleteValue', 'value_delete')),
  capability('GM_deleteValues', 'deleteValues', ['GM.deleteValues'], ['GM_deleteValues'], true, '保存脚本数据', nativeRoute('deleteValues', 'values_delete')),
  capability('GM_listValues', 'listValues', ['GM.listValues'], ['GM_listValues'], true, '保存脚本数据', nativeRoute('listValues', 'value_list')),
  capability('GM_getResourceText', 'getResourceText', ['GM.getResourceText'], ['GM_getResourceText'], true, '读取脚本资源'),
  capability('GM_getResourceURL', 'getResourceURL', ['GM.getResourceUrl', 'GM.getResourceURL'], ['GM_getResourceURL'], true, '读取脚本资源'),
  capability('GM_xmlhttpRequest', 'xmlhttpRequest', ['GM.xmlHttpRequest', 'GM.xmlhttpRequest', 'GM_xmlHttpRequest'], ['GM_xmlhttpRequest'], true, '跨域网络请求', nativeRoute('xmlHttpRequest', 'xml_http_request')),
  capability('GM_fetch', 'fetch', ['GM.fetch'], ['GM_fetch', 'GM_xmlhttpRequest'], true, '跨域网络请求', nativeRoute('xmlHttpRequest', 'xml_http_request')),
  capability('GM_download', 'download', ['GM.download'], ['GM_download'], true, '下载文件', nativeRoute('download', 'download')),
  capability('GM_openInTab', 'openInTab', ['GM.openInTab'], ['GM_openInTab'], true, '打开新标签页', nativeRoute('openInTab', 'open_in_tab')),
  capability('GM_getTab', 'getTab', ['GM.getTab'], ['GM_getTab'], true, '标签页数据', nativeRoute('getTab', 'tab_get')),
  capability('GM_saveTab', 'saveTab', ['GM.saveTab'], ['GM_saveTab'], true, '标签页数据', nativeRoute('saveTab', 'tab_save')),
  capability('GM_getTabs', 'getTabs', ['GM.getTabs'], ['GM_getTabs'], true, '标签页数据', nativeRoute('getTabs', 'tabs_get')),
  capability('GM_setClipboard', 'setClipboard', ['GM.setClipboard'], ['GM_setClipboard'], true, '写入剪贴板', nativeRoute('setClipboard', 'clipboard')),
  capability('GM_log', 'log', ['GM.log'], ['GM_log'], true, '输出调试日志'),
  capability('GM_notification', 'notification', ['GM.notification'], ['GM_notification'], true, '发送通知', nativeRoute('notification', 'notification')),
  capability('GM_info', 'info', ['GM.info'], ['GM_info'], true, '读取脚本信息'),
  capability('GM_registerMenuCommand', 'registerMenuCommand', ['GM.registerMenuCommand'], ['GM_registerMenuCommand'], true, '注册菜单命令'),
  capability('GM_unregisterMenuCommand', 'unregisterMenuCommand', ['GM.unregisterMenuCommand'], ['GM_unregisterMenuCommand'], true, '注册菜单命令'),
  capability('GM_addValueChangeListener', 'addValueChangeListener', ['GM.addValueChangeListener'], ['GM_addValueChangeListener'], true, '监听脚本数据变化'),
  capability('GM_removeValueChangeListener', 'removeValueChangeListener', ['GM.removeValueChangeListener'], ['GM_removeValueChangeListener'], true, '监听脚本数据变化'),
  capability('GM_EX_getSearchEngines', 'exGetSearchEngines', [], ['GM_EX_getSearchEngines'], true, '读取搜索引擎列表'),
  capability('GM_EX_getAppSearchEngineUrl', 'exGetAppSearchEngineUrl', [], ['GM_EX_getAppSearchEngineUrl'], true, '执行应用搜索'),
  capability('GM_EX_TTS', 'exTts', [], ['GM_EX_TTS'], true, '朗读文本'),
  capability('GM_EX_ShareTextToApp', 'exShareTextToApp', [], ['GM_EX_ShareTextToApp'], true, '分享文本到应用'),
  capability('GM_EX_sniffMedia', 'exSniffMedia', [], ['GM_EX_sniffMedia'], true, '检测网页媒体', nativeRoute('sniffMedia', 'media_sniff')),
  capability('window.onurlchange', 'onUrlChange', [], ['window.onurlchange'], true, '监听网页地址变化'),
  capability('window.close', 'windowClose', [], ['window.close'], true, '关闭网页窗口'),
  capability('window.focus', 'windowFocus', [], ['window.focus'], true, '聚焦网页窗口'),
  capability('unsafeWindow', 'unsafeWindow', [], ['unsafeWindow'], true, '访问页面窗口对象')
];

function capability(
  grant: UserScriptGrant,
  flagName: string,
  aliases: string[],
  satisfiedBy: UserScriptGrant[],
  runtimeExposed: boolean,
  managementLabel: string,
  route?: UserScriptNativeRouteDescriptor
): UserScriptCapabilityDescriptor {
  return {
    grant: grant,
    flagName: flagName,
    aliases: aliases,
    satisfiedBy: satisfiedBy,
    runtimeExposed: runtimeExposed,
    managementLabel: managementLabel,
    nativeRoute: route
  };
}

function nativeRoute(
  requestKind: UserScriptNativeBridgeRequestKind,
  executor: UserScriptNativeBridgeExecutorKind
): UserScriptNativeRouteDescriptor {
  return {
    requestKind: requestKind,
    executor: executor
  };
}

export class UserScriptCapabilityContractService {
  private sourceGrantCacheByScriptId: Record<string, UserScriptSourceGrantCacheEntry | undefined> = {};

  normalizeGrant(value: string): UserScriptGrant | undefined {
    const normalized = value.trim();
    const descriptor = USER_SCRIPT_CAPABILITIES.find((candidate: UserScriptCapabilityDescriptor): boolean => {
      return candidate.grant === normalized || candidate.aliases.includes(normalized);
    });
    return descriptor?.grant;
  }

  normalizeGrants(values: string[]): UserScriptGrant[] {
    const grants: UserScriptGrant[] = [];
    values.forEach((value: string) => {
      const grant = this.normalizeGrant(value);
      if (grant !== undefined && !grants.includes(grant)) {
        grants.push(grant);
      }
    });
    return grants.length > 0 ? grants : ['none'];
  }

  hasGrant(script: InstalledUserScriptState, grant: UserScriptGrant): boolean {
    const descriptor = this.findDescriptor(grant);
    if (descriptor === undefined) {
      return false;
    }
    const sourceGrants = this.resolveSourceDeclaredGrants(script);
    return descriptor.satisfiedBy.some((candidate: UserScriptGrant): boolean => {
      return script.grants.includes(candidate) || sourceGrants.includes(candidate);
    });
  }

  buildRuntimeManifest(script: InstalledUserScriptState): UserScriptCapabilityRuntimeManifest {
    const flagEntries = USER_SCRIPT_CAPABILITIES
      .filter((descriptor: UserScriptCapabilityDescriptor): boolean => descriptor.runtimeExposed)
      .map((descriptor: UserScriptCapabilityDescriptor): string => {
        return `${descriptor.flagName}:${this.hasGrant(script, descriptor.grant) ? 'true' : 'false'}`;
      });
    const routes: Record<string, UserScriptNativeBridgeRoute | undefined> = {};
    USER_SCRIPT_CAPABILITIES.forEach((descriptor: UserScriptCapabilityDescriptor) => {
      const route = this.buildNativeRoute(descriptor);
      if (route !== undefined) {
        routes[descriptor.flagName] = route;
      }
    });
    return {
      grantFlagsLiteral: `{${flagEntries.join(',')}}`,
      nativeRoutesLiteral: JSON.stringify(routes)
    };
  }

  resolveNativeRoute(requestKind: string, capabilityName: string): UserScriptNativeBridgeRoute | undefined {
    const normalizedKind = requestKind.trim();
    const normalizedCapability = capabilityName.trim();
    const descriptor = USER_SCRIPT_CAPABILITIES.find((candidate: UserScriptCapabilityDescriptor): boolean => {
      return candidate.grant === normalizedCapability && candidate.nativeRoute?.requestKind === normalizedKind;
    });
    return descriptor === undefined ? undefined : this.buildNativeRoute(descriptor);
  }

  summarizeGrants(grants: UserScriptGrant[]): string {
    if (grants.includes('none')) {
      return '无特殊授权';
    }
    const labels: string[] = [];
    USER_SCRIPT_CAPABILITIES.forEach((descriptor: UserScriptCapabilityDescriptor) => {
      if (!grants.includes(descriptor.grant) || descriptor.managementLabel.length === 0 ||
        labels.includes(descriptor.managementLabel)) {
        return;
      }
      labels.push(descriptor.managementLabel);
    });
    return labels.join('、');
  }

  private resolveSourceDeclaredGrants(script: InstalledUserScriptState): UserScriptGrant[] {
    const cached = this.sourceGrantCacheByScriptId[script.id];
    if (cached !== undefined && cached.updatedAt === script.updatedAt &&
      cached.sourceLength === script.source.length) {
      return cached.grants;
    }
    const grants = this.parseSourceDeclaredGrants(script.source);
    this.sourceGrantCacheByScriptId[script.id] = {
      updatedAt: script.updatedAt,
      sourceLength: script.source.length,
      grants: grants
    };
    return grants;
  }

  private parseSourceDeclaredGrants(source: string): UserScriptGrant[] {
    const grants: UserScriptGrant[] = [];
    const metadataEndMarker = '// ==/UserScript==';
    const metadataEndIndex = source.indexOf(metadataEndMarker);
    const scanEnd = metadataEndIndex >= 0 ? metadataEndIndex : source.length;
    let lineStart = 0;
    let lineCount = 0;
    while (lineStart < scanEnd && lineCount < 160) {
      const newlineIndex = source.indexOf('\n', lineStart);
      const lineEnd = newlineIndex >= 0 && newlineIndex < scanEnd ? newlineIndex : scanEnd;
      const match = /^\s*\/\/\s*@grant\s+(.+?)\s*$/.exec(source.slice(lineStart, lineEnd));
      if (match !== null) {
        const grant = this.normalizeGrant(match[1].trim());
        if (grant !== undefined && !grants.includes(grant)) {
          grants.push(grant);
        }
      }
      lineCount += 1;
      if (newlineIndex < 0 || newlineIndex >= scanEnd) {
        break;
      }
      lineStart = newlineIndex + 1;
    }
    return grants;
  }

  private findDescriptor(grant: UserScriptGrant): UserScriptCapabilityDescriptor | undefined {
    return USER_SCRIPT_CAPABILITIES.find((candidate: UserScriptCapabilityDescriptor): boolean => {
      return candidate.grant === grant;
    });
  }

  private buildNativeRoute(descriptor: UserScriptCapabilityDescriptor): UserScriptNativeBridgeRoute | undefined {
    const route = descriptor.nativeRoute;
    if (route === undefined) {
      return undefined;
    }
    return {
      requestKind: route.requestKind,
      capability: descriptor.grant,
      executor: route.executor
    };
  }
}
