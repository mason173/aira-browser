export type SiteReportReasonId = 'display_issue' | 'dangerous_site' | 'intrusive_content';

export interface SiteReportReasonOption {
  id: SiteReportReasonId;
  label: string;
}

export class SiteReportDialogViewModel {
  buildReasonOptions(): SiteReportReasonOption[] {
    return [
      {
        id: 'display_issue',
        label: '页面显示不正确'
      },
      {
        id: 'dangerous_site',
        label: '这是危险网站'
      },
      {
        id: 'intrusive_content',
        label: '干扰内容太多'
      }
    ];
  }

  getDefaultReasonId(): SiteReportReasonId {
    return 'display_issue';
  }
}
