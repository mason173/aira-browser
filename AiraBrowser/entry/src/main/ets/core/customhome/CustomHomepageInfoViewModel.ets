import {
  CustomHomepageItem,
  CustomHomepageItemKind
} from '../../common/models/CustomHomepageModels';

export interface CustomHomepageInfoRowViewState {
  id: string;
  label: string;
  value: string;
  technical: boolean;
}

export interface CustomHomepageInfoViewState {
  title: string;
  typeLabel: string;
  description: string;
  rows: CustomHomepageInfoRowViewState[];
}

export class CustomHomepageInfoViewModel {
  buildInitialState(): CustomHomepageInfoViewState {
    return {
      title: '',
      typeLabel: '',
      description: '',
      rows: []
    };
  }

  buildState(item: CustomHomepageItem): CustomHomepageInfoViewState {
    const rows: CustomHomepageInfoRowViewState[] = [];
    const title = this.resolveTitle(item);
    const typeLabel = this.resolveTypeLabel(item.kind, item.version);
    this.appendRow(rows, 'author', '作者', item.author, false);
    this.appendRow(rows, 'package_id', '主页包 ID', this.resolveDeclaredPackageId(item), true);
    if (item.kind === 'remote_url') {
      this.appendRow(rows, 'url', '主页网址', item.remoteUrl, true);
    } else if (item.kind === 'single_html') {
      this.appendSizeRow(rows, 'size', '大小', item.byteSize);
    } else {
      this.appendSizeRow(rows, 'size', '大小', item.packageSize);
    }
    return {
      title: title,
      typeLabel: typeLabel,
      description: item.description.trim(),
      rows: rows
    };
  }

  private appendRow(
    rows: CustomHomepageInfoRowViewState[],
    id: string,
    label: string,
    rawValue: string,
    technical: boolean
  ): void {
    const value = rawValue.trim();
    if (value.length <= 0) {
      return;
    }
    rows.push({
      id: id,
      label: label,
      value: value,
      technical: technical
    });
  }

  private appendSizeRow(
    rows: CustomHomepageInfoRowViewState[],
    id: string,
    label: string,
    byteSize: number
  ): void {
    if (byteSize <= 0) {
      return;
    }
    this.appendRow(rows, id, label, this.formatByteSize(byteSize), false);
  }

  private resolveTitle(item: CustomHomepageItem): string {
    const packageName = item.packageName.trim();
    if (packageName.length > 0) {
      return packageName;
    }
    const fileName = item.fileName.trim();
    if (fileName.length > 0) {
      return fileName;
    }
    const remoteUrl = item.remoteUrl.trim();
    return remoteUrl.length > 0 ? remoteUrl : '自定义主页';
  }

  private resolveTypeLabel(kind: CustomHomepageItemKind, rawVersion: string): string {
    let typeLabel = '单文件 HTML';
    if (kind === 'zip_package') {
      typeLabel = '主页包（ZIP）';
    } else if (kind === 'remote_url') {
      typeLabel = '网址主页';
    }
    const version = rawVersion.trim();
    return version.length > 0 ? `${typeLabel} · v${version}` : typeLabel;
  }

  private resolveDeclaredPackageId(item: CustomHomepageItem): string {
    if (item.kind !== 'zip_package') {
      return '';
    }
    const prefix = 'zip_package:id:';
    const identityKey = item.identityKey.trim();
    return identityKey.startsWith(prefix) ? identityKey.substring(prefix.length) : '';
  }

  private formatByteSize(byteSize: number): string {
    if (byteSize < 1024) {
      return `${Math.floor(byteSize)} B`;
    }
    const kilobytes = byteSize / 1024;
    if (kilobytes < 1024) {
      return `${this.formatDecimal(kilobytes)} KB`;
    }
    return `${this.formatDecimal(kilobytes / 1024)} MB`;
  }

  private formatDecimal(value: number): string {
    return `${Math.round(value * 10) / 10}`;
  }
}
