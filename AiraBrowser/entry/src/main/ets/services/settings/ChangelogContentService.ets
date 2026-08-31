import { common } from '@kit.AbilityKit';
import bundleManager from '@ohos.bundle.bundleManager';
import buffer from '@ohos.buffer';
import {
  APP_PREVIEW_VERSION_CODE,
  APP_PREVIEW_VERSION_NAME
} from '../../common/constants/AppVersionInfo';

const CHANGELOG_RAW_FILE_NAME: string = 'changelog.md';

export interface AppVersionIdentity {
  versionName: string;
  versionCode: number;
}

export interface CurrentChangelogSection {
  versionName: string;
  versionCode: number;
  updateDate: string;
  summary: string;
  items: string[];
  markdown: string;
  available: boolean;
}

export class ChangelogContentService {
  buildFullMarkdown(context: common.Context): string {
    return this.readMarkdown(context);
  }

  buildCurrentSection(context: common.Context): CurrentChangelogSection {
    const version = this.resolveCurrentVersion();
    const markdown = this.readMarkdown(context);
    return this.parseCurrentSection(markdown, version);
  }

  resolveCurrentVersion(): AppVersionIdentity {
    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      const versionName = `${bundleInfo.versionName ?? ''}`.trim();
      return {
        versionName: versionName.length > 0 ? versionName : APP_PREVIEW_VERSION_NAME,
        versionCode: this.normalizeVersionCode(bundleInfo.versionCode, APP_PREVIEW_VERSION_CODE)
      };
    } catch (_error) {
      return {
        versionName: APP_PREVIEW_VERSION_NAME,
        versionCode: APP_PREVIEW_VERSION_CODE
      };
    }
  }

  private readMarkdown(context: common.Context): string {
    try {
      const rawFile = context.resourceManager.getRawFileContentSync(CHANGELOG_RAW_FILE_NAME);
      return this.applyRuntimePlaceholders(buffer.from(rawFile.buffer).toString('utf8'));
    } catch (error) {
      return [
        '# 更新日志',
        '',
        `更新日志加载失败：${this.stringifyError(error)}`
      ].join('\n');
    }
  }

  private applyRuntimePlaceholders(markdown: string): string {
    const version = this.resolveCurrentVersion();
    return markdown
      .replace(/\{\{CURRENT_VERSION_NAME\}\}/g, version.versionName)
      .replace(/\{\{CURRENT_VERSION_CODE\}\}/g, `${version.versionCode}`);
  }

  private parseCurrentSection(markdown: string, version: AppVersionIdentity): CurrentChangelogSection {
    const sectionLines = this.extractFirstVersionSectionLines(markdown);
    if (sectionLines.length <= 0) {
      return this.buildFallbackSection(version);
    }
    const bodyLines = sectionLines.slice(1);
    const updateDate = this.extractUpdateDate(bodyLines);
    const summary = this.extractSummary(bodyLines);
    const items = this.extractBulletItems(bodyLines);
    return {
      versionName: version.versionName,
      versionCode: version.versionCode,
      updateDate: updateDate,
      summary: summary.length > 0 ? summary : '这一版带来了一些体验优化和问题修复。',
      items: items,
      markdown: sectionLines.join('\n').trim(),
      available: true
    };
  }

  private extractFirstVersionSectionLines(markdown: string): string[] {
    const lines = markdown.split(/\r?\n/);
    let startIndex = -1;
    let endIndex = lines.length;
    for (let index = 0; index < lines.length; index++) {
      if (/^##\s+/.test(lines[index].trim())) {
        startIndex = index;
        break;
      }
    }
    if (startIndex < 0) {
      return [];
    }
    for (let index = startIndex + 1; index < lines.length; index++) {
      if (/^##\s+/.test(lines[index].trim())) {
        endIndex = index;
        break;
      }
    }
    return lines.slice(startIndex, endIndex);
  }

  private extractUpdateDate(lines: string[]): string {
    for (let index = 0; index < lines.length; index++) {
      const line = lines[index].trim();
      if (/^\d{4}-\d{2}-\d{2}$/.test(line)) {
        return line;
      }
    }
    return '';
  }

  private extractSummary(lines: string[]): string {
    for (let index = 0; index < lines.length; index++) {
      const line = lines[index].trim();
      if (line.length <= 0 || line.startsWith('- ') || /^\d{4}-\d{2}-\d{2}$/.test(line)) {
        continue;
      }
      return line;
    }
    return '';
  }

  private extractBulletItems(lines: string[]): string[] {
    const items: string[] = [];
    lines.forEach((line: string) => {
      const normalizedLine = line.trim();
      if (!normalizedLine.startsWith('- ')) {
        return;
      }
      const item = normalizedLine.substring(2).trim();
      if (item.length > 0) {
        items.push(item);
      }
    });
    return items;
  }

  private buildFallbackSection(version: AppVersionIdentity): CurrentChangelogSection {
    return {
      versionName: version.versionName,
      versionCode: version.versionCode,
      updateDate: '',
      summary: 'Aira 已更新到新版本。',
      items: [],
      markdown: '',
      available: false
    };
  }

  private normalizeVersionCode(value: number | undefined, fallback: number): number {
    const versionCode = Number(value);
    return Number.isFinite(versionCode) && versionCode > 0 ? Math.round(versionCode) : fallback;
  }

  private stringifyError(error: Object | undefined): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return JSON.stringify(error);
  }
}
