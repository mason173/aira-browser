import { TabCrashReason } from '../../common/models/BrowserModels';

export type BrowserFaultCode =
  'WEB_RENDER_CRASH' |
  'WEB_ATTACH_FAIL' |
  'WEB_RESTORE_FAIL' |
  'WEB_NAVIGATION_FAILED' |
  'WEB_DOWNLOAD_FAILED' |
  'WEB_PERMISSION_BLOCKED' |
  'WEB_PERMISSION_DENIED' |
  'WEB_EXTERNAL_NAVIGATION_FAILED' |
  'WEB_FILE_SELECTOR_FAILED';

export interface BrowserFaultDescriptor {
  code: BrowserFaultCode;
  telemetryType: string;
  userMessage: string;
  breadcrumb: string;
  recoverable: boolean;
  crashReason?: TabCrashReason;
}

export class BrowserFaultClassifier {
  classifyMainFrameError(errorMessage: string, shouldFallbackToHome: boolean): BrowserFaultDescriptor {
    return {
      code: shouldFallbackToHome ? 'WEB_RENDER_CRASH' : 'WEB_NAVIGATION_FAILED',
      telemetryType: shouldFallbackToHome ? 'fault_main_frame_error_crashed' : 'fault_main_frame_error',
      userMessage: errorMessage.length > 0 ? errorMessage : '主框架加载失败。',
      breadcrumb: `fault=${shouldFallbackToHome ? 'WEB_RENDER_CRASH' : 'WEB_NAVIGATION_FAILED'}`,
      recoverable: !shouldFallbackToHome,
      crashReason: shouldFallbackToHome ? 'main_frame_error' : undefined
    };
  }

  classifySnapshotRestoreFailure(snapshotPath: string): BrowserFaultDescriptor {
    return {
      code: 'WEB_RESTORE_FAIL',
      telemetryType: 'fault_snapshot_restore_failed',
      userMessage: snapshotPath.length > 0 ? `快照恢复失败，已失效 ${snapshotPath}` : '页面快照恢复失败。',
      breadcrumb: `fault=WEB_RESTORE_FAIL snapshot=${snapshotPath}`,
      recoverable: true,
      crashReason: 'snapshot_restore_failed'
    };
  }

  classifyNavigationRestoreFailure(errorMessage: string): BrowserFaultDescriptor {
    return {
      code: 'WEB_NAVIGATION_FAILED',
      telemetryType: 'fault_navigation_restore_failed',
      userMessage: errorMessage.length > 0 ? errorMessage : '恢复导航失败。',
      breadcrumb: 'fault=WEB_NAVIGATION_FAILED',
      recoverable: true,
      crashReason: 'navigation_failed'
    };
  }

  classifyAttachFailure(message: string): BrowserFaultDescriptor {
    return {
      code: 'WEB_ATTACH_FAIL',
      telemetryType: 'fault_attach_failed',
      userMessage: message.length > 0 ? message : 'Web 控制器附着失败。',
      breadcrumb: 'fault=WEB_ATTACH_FAIL',
      recoverable: true,
      crashReason: 'unknown'
    };
  }

  classifyDownloadError(message: string): BrowserFaultDescriptor {
    return {
      code: 'WEB_DOWNLOAD_FAILED',
      telemetryType: 'fault_download_failed',
      userMessage: message.length > 0 ? message : '下载失败。',
      breadcrumb: 'fault=WEB_DOWNLOAD_FAILED',
      recoverable: true
    };
  }

  classifyPermissionBlocked(label: string): BrowserFaultDescriptor {
    return {
      code: 'WEB_PERMISSION_BLOCKED',
      telemetryType: 'fault_permission_blocked',
      userMessage: `${label}已被阻止。`,
      breadcrumb: 'fault=WEB_PERMISSION_BLOCKED',
      recoverable: true
    };
  }

  classifyPermissionDenied(message: string): BrowserFaultDescriptor {
    return {
      code: 'WEB_PERMISSION_DENIED',
      telemetryType: 'fault_permission_denied',
      userMessage: message.length > 0 ? message : '系统权限未开启，网页请求已拒绝。',
      breadcrumb: 'fault=WEB_PERMISSION_BLOCKED',
      recoverable: true
    };
  }

  classifyExternalNavigationFailure(message: string): BrowserFaultDescriptor {
    return {
      code: 'WEB_EXTERNAL_NAVIGATION_FAILED',
      telemetryType: 'fault_external_navigation_failed',
      userMessage: message.length > 0 ? message : '外部应用打开失败。',
      breadcrumb: 'fault=WEB_EXTERNAL_NAVIGATION_FAILED',
      recoverable: true
    };
  }

  classifyFileSelectorFailure(message: string): BrowserFaultDescriptor {
    return {
      code: 'WEB_FILE_SELECTOR_FAILED',
      telemetryType: 'fault_file_selector_failed',
      userMessage: message.length > 0 ? message : '文件选择失败。',
      breadcrumb: 'fault=WEB_FILE_SELECTOR_FAILED',
      recoverable: true
    };
  }
}
