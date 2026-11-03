import { UserScriptGrant } from './UserScriptMetadataModels';
import { UserScriptValueMutation } from './UserScriptValueModels';

export const USER_SCRIPT_NATIVE_BRIDGE_NAME: string = '__airaUserScriptNativeBridge';

export type UserScriptNativeBridgeRequestKind =
  'xmlHttpRequest' |
  'download' |
  'notification' |
  'sniffMedia' |
  'getTab' |
  'saveTab' |
  'getTabs' |
  'getValue' |
  'getValues' |
  'listValues' |
  'setValue' |
  'setValues' |
  'deleteValue' |
  'deleteValues' |
  'setClipboard' |
  'openInTab' |
  'cookieList' |
  'cookieSet' |
  'cookieDelete';

export type UserScriptNativeBridgeExecutorKind =
  'xml_http_request' |
  'download' |
  'notification' |
  'media_sniff' |
  'tab_get' |
  'tab_save' |
  'tabs_get' |
  'value_read' |
  'values_read' |
  'value_list' |
  'value_set' |
  'values_set' |
  'value_delete' |
  'values_delete' |
  'clipboard' |
  'open_in_tab' |
  'cookie_list' |
  'cookie_set' |
  'cookie_delete';

export interface UserScriptNativeBridgeRoute {
  requestKind: UserScriptNativeBridgeRequestKind;
  capability: UserScriptGrant;
  executor: UserScriptNativeBridgeExecutorKind;
}

export interface UserScriptNativeBridgeTokenRecord {
  scriptId: string;
  token: string;
}

export interface RawUserScriptNativeBridgePayload {
  kind?: string;
  id?: string;
  scriptId?: string;
  token?: string;
  capability?: string;
  url?: string;
  active?: boolean;
  mutations?: UserScriptValueMutation[];
  headers?: Record<string, string>;
  name?: string;
  responseType?: string;
  key?: string;
  keys?: string[];
  val?: Object | string | number | boolean | null;
  valueJson?: string;
  title?: string;
  text?: string;
  frame?: string;
  requestedCount?: number;
  evaluatedCount?: number;
  reportCount?: number;
  missingReportCount?: number;
  errorCount?: number;
  errorCategory?: string;
  tab?: Record<string, Object | string | number | boolean | null>;
  cookieJson?: string;
}

export interface UserScriptNativeBridgeValidation {
  ok: boolean;
  scriptId: string;
  message: string;
}

export interface UserScriptNativeDownloadRequest {
  url: string;
  name: string;
  headers: Record<string, string>;
  sourcePageUrl: string;
}

export interface UserScriptNativeDownloadTaskUpdate {
  guid: string;
  status: string;
  downloadedSize: number;
  totalSize: number;
  statusText: string;
}
