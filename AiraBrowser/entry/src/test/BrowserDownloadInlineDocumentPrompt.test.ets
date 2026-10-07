import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserDownloadNavigationStateCoordinator
} from '../main/ets/core/browser/BrowserDownloadNavigationStateCoordinator';
import {
  BrowserNonRestorableNavigationGuardRecord,
  BrowserNonRestorableNavigationGuardStore
} from '../main/ets/data/browser/BrowserNonRestorableNavigationGuardStore';

class StubGuardStore implements BrowserNonRestorableNavigationGuardStore {
  async loadRecords(): Promise<BrowserNonRestorableNavigationGuardRecord[]> {
    return [];
  }

  async saveRecords(_records: BrowserNonRestorableNavigationGuardRecord[]): Promise<void> {
  }
}

export default function browserDownloadInlineDocumentPromptTest(): void {
  describe('BrowserDownload inline-document prompt policy', () => {
    const coordinator = new BrowserDownloadNavigationStateCoordinator(new StubGuardStore());

    // A PDF download the site handed the browser arrives as an ArkWeb WebDownloadItem. That item has
    // no Content-Disposition, so its delegate-derived application/pdf mime alone previously matched
    // the "render this inline" rule and the download was silently dropped with no prompt. A platform
    // download must never be reclassified as an inline document, even when the mime is application/pdf.
    it('never drops a platform download as an inline document', 0, () => {
      expect(coordinator.shouldIgnoreDownloadPromptForInlineDocument(
        'https://doc.example.com/export?format=pdf',
        'application/pdf',
        '',
        true
      )).assertFalse();
      expect(coordinator.resolveInlineDocumentPrompt(
        'https://doc.example.com/export?format=pdf',
        'application/pdf',
        '',
        '',
        true
      ).shouldIgnore).assertFalse();
    });

    // The ordinary browser-navigation case still treats a bare application/pdf as an inline document
    // so a plain PDF link opens in the viewer instead of prompting a download.
    it('still treats a non-download application/pdf as inline', 0, () => {
      expect(coordinator.shouldIgnoreDownloadPromptForInlineDocument(
        'https://example.com/report',
        'application/pdf',
        '',
        false
      )).assertTrue();
    });

    // An attachment disposition (from onDownloadStart, which does carry it) keeps the download.
    it('keeps a PDF that is explicitly an attachment', 0, () => {
      expect(coordinator.shouldIgnoreDownloadPromptForInlineDocument(
        'https://example.com/report',
        'application/pdf',
        'attachment; filename="report.pdf"',
        false
      )).assertFalse();
    });

    // A .pdf URL with no mime is still classified inline for ordinary navigation.
    it('treats a plain .pdf url as inline when not a platform download', 0, () => {
      expect(coordinator.shouldIgnoreDownloadPromptForInlineDocument(
        'https://example.com/files/report.pdf?token=abc',
        '',
        '',
        false
      )).assertTrue();
    });
  });
}
