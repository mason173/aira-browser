import {
  OfflinePageListItem,
  OfflinePageListState,
  OfflinePageOpenStatus,
  OfflinePageRecord
} from '../../common/models/OfflinePageModels';

const EMPTY_MESSAGE: string = '还没有保存的离线页面';

export class OfflinePageListViewModel {
  buildLoadingState(): OfflinePageListState {
    return {
      loading: true,
      empty: false,
      items: [],
      message: '正在读取已保存页面...'
    };
  }

  buildState(records: OfflinePageRecord[]): OfflinePageListState {
    const items = records.map((record: OfflinePageRecord): OfflinePageListItem => this.buildItem(record));
    return {
      loading: false,
      empty: items.length === 0,
      items: items,
      message: items.length === 0 ? EMPTY_MESSAGE : ''
    };
  }

  buildFailureState(message: string): OfflinePageListState {
    return {
      loading: false,
      empty: true,
      items: [],
      message: message
    };
  }

  private buildItem(record: OfflinePageRecord): OfflinePageListItem {
    const title = record.title.trim().length > 0 ? record.title.trim() : '未命名离线页面';
    const siteName = record.siteName.trim().length > 0 ? record.siteName.trim() :
      (record.host.trim().length > 0 ? record.host.trim() : '未知来源');
    return {
      id: record.id,
      title: title,
      siteName: siteName,
      host: record.host,
      savedAtText: this.formatSavedAt(record.savedAt),
      sizeText: this.formatBytes(record.totalBytes),
      previewImageUri: record.previewImageUri,
      faviconUri: record.faviconUri,
      originalUrl: record.originalUrl,
      canOpen: record.openStatus === 'available',
      openStatusText: this.resolveOpenStatusText(record.openStatus)
    };
  }

  private resolveOpenStatusText(status: OfflinePageOpenStatus): string {
    if (status === 'available') {
      return '可正常打开';
    }
    if (status === 'missing_snapshot') {
      return '正文文件缺失';
    }
    if (status === 'missing_assets') {
      return '部分资源缺失';
    }
    return '离线副本异常';
  }

  private formatSavedAt(value: number): string {
    if (value <= 0) {
      return '';
    }
    const date = new Date(value);
    return `${date.getFullYear()}-${this.pad2(date.getMonth() + 1)}-${this.pad2(date.getDate())} ` +
      `${this.pad2(date.getHours())}:${this.pad2(date.getMinutes())}`;
  }

  private formatBytes(value: number): string {
    const bytes = Math.max(0, Math.floor(value));
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    const kb = bytes / 1024;
    if (kb < 1024) {
      return `${this.formatOneDecimal(kb)} KB`;
    }
    const mb = kb / 1024;
    return `${this.formatOneDecimal(mb)} MB`;
  }

  private formatOneDecimal(value: number): string {
    return (Math.round(value * 10) / 10).toString();
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : value.toString();
  }
}
