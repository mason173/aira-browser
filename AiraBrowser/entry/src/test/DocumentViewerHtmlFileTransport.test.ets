import { describe, expect, it } from '@ohos/hypium';
import {
  DOCUMENT_VIEWER_HTML_FILE_TRANSPORT_LIMIT,
  DOCUMENT_VIEWER_HTML_FILE_TRANSPORT_PREFIX,
  DocumentViewerHtmlFileTransport
} from '../main/ets/services/viewer/DocumentViewerHtmlFileTransport';

export default function documentViewerHtmlFileTransportTest(): void {
  describe('DocumentViewerHtmlFileTransport', () => {
    it('round-trips a viewer url without putting the file uri in the transport url', 0, () => {
      const transport = new DocumentViewerHtmlFileTransport();
      const viewerUrl = 'aira://document-viewer?kind=html&uri=file%3A%2F%2Fdocs%2Fmanual.html&name=manual.html';
      const fileUri = 'file://docs/storage/Users/currentUser/manual.html';
      const transportUrl = transport.register(viewerUrl, fileUri);

      expect(transportUrl.startsWith(DOCUMENT_VIEWER_HTML_FILE_TRANSPORT_PREFIX)).assertTrue();
      expect(transportUrl.indexOf('manual.html') < 0).assertTrue();
      expect(transportUrl.indexOf('file') < 0).assertTrue();
      expect(transport.isTransportUrl(transportUrl)).assertTrue();
      expect(transport.resolveVisibleUrl(transportUrl)).assertEqual(viewerUrl);
      expect(transport.resolveFileUri(transportUrl)).assertEqual(fileUri);
    });

    it('does not serve an unregistered or non-transport url', 0, () => {
      const transport = new DocumentViewerHtmlFileTransport();
      const unknown = `${DOCUMENT_VIEWER_HTML_FILE_TRANSPORT_PREFIX}missing-ticket`;

      expect(transport.isTransportUrl(unknown)).assertTrue();
      expect(transport.resolveVisibleUrl(unknown)).assertEqual('');
      expect(transport.resolveFileUri(unknown)).assertEqual('');
      expect(transport.isTransportUrl('https://example.com/html/ticket')).assertFalse();
      expect(transport.isTransportUrl('aira://document-viewer?kind=html')).assertFalse();
      expect(transport.resolveVisibleUrl('https://example.com/')).assertEqual('');
    });

    it('drops the oldest ticket after the retention limit', 0, () => {
      const transport = new DocumentViewerHtmlFileTransport();
      const firstViewerUrl = 'aira://document-viewer?kind=html&uri=file%3A%2F%2Ffirst.html&name=first.html';
      const firstTransportUrl = transport.register(firstViewerUrl, 'file://first.html');
      for (let index = 1; index < DOCUMENT_VIEWER_HTML_FILE_TRANSPORT_LIMIT; index += 1) {
        transport.register(
          `aira://document-viewer?kind=html&uri=file%3A%2F%2F${index}.html&name=${index}.html`,
          `file://${index}.html`
        );
      }

      expect(transport.resolveVisibleUrl(firstTransportUrl)).assertEqual(firstViewerUrl);
      transport.register(
        'aira://document-viewer?kind=html&uri=file%3A%2F%2Foverflow.html&name=overflow.html',
        'file://overflow.html'
      );
      expect(transport.resolveVisibleUrl(firstTransportUrl)).assertEqual('');
      expect(transport.resolveFileUri(firstTransportUrl)).assertEqual('');
    });

    it('rejects an empty viewer url or file uri', 0, () => {
      const transport = new DocumentViewerHtmlFileTransport();
      expect(transport.register('', 'file://manual.html')).assertEqual('');
      expect(transport.register('aira://document-viewer?kind=html', '   ')).assertEqual('');
    });
  });
}
