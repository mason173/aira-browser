import { UserScriptPackageSuccessResult } from './UserScriptPackageLifecycleCoordinator';

export const USER_SCRIPT_FEATURE_TITLE: string = '用户脚本';

export interface UserScriptPackageSuccessPromptCopy {
  title: string;
  subtitle: string;
}

export function formatOpenUserScriptsPageError(error: Error): string {
  return `打开${USER_SCRIPT_FEATURE_TITLE}失败：${JSON.stringify(error)}`;
}

export function formatUserScriptPackageCommitMessage(result: UserScriptPackageSuccessResult): string {
  const copy = buildUserScriptPackageSuccessPromptCopy(result);
  return `${copy.title}：${copy.subtitle}`;
}

export function buildUserScriptPackageSuccessPromptCopy(
  result: UserScriptPackageSuccessResult
): UserScriptPackageSuccessPromptCopy {
  return {
    title: result.status === 'updated' ? '已更新用户脚本' : '已安装用户脚本',
    subtitle: result.warnings.length > 0
      ? `${result.scriptName}（部分能力暂不支持）`
      : result.scriptName
  };
}
