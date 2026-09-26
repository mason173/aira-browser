export const DOCUMENT_VIEWER_HTML_FILE_TRANSPORT_PREFIX: string = 'https://document-viewer.aira.invalid/html/';
export const DOCUMENT_VIEWER_HTML_FILE_TRANSPORT_LIMIT: number = 32;

interface DocumentViewerHtmlFileTransportEntry {
  viewerUrl: string;
  fileUri: string;
}

export class DocumentViewerHtmlFileTransport {
  private entries: Map<string, DocumentViewerHtmlFileTransportEntry> = new Map();
  private order: string[] = [];
  private sequence: number = 0;

  isTransportUrl(url: string): boolean {
    return this.readTicket(url).length > 0;
  }

  register(viewerUrl: string, fileUri: string): string {
    const normalizedViewerUrl = viewerUrl.trim();
    const normalizedFileUri = fileUri.trim();
    if (normalizedViewerUrl.length === 0 || normalizedFileUri.length === 0) {
      return '';
    }
    this.sequence += 1;
    const ticket = this.createTicket(this.sequence);
    this.remember(ticket, {
      viewerUrl: normalizedViewerUrl,
      fileUri: normalizedFileUri
    });
    return `${DOCUMENT_VIEWER_HTML_FILE_TRANSPORT_PREFIX}${ticket}`;
  }

  resolveVisibleUrl(url: string): string {
    const ticket = this.readTicket(url);
    if (ticket.length === 0) {
      return '';
    }
    return this.entries.get(ticket)?.viewerUrl ?? '';
  }

  resolveFileUri(url: string): string {
    const ticket = this.readTicket(url);
    if (ticket.length === 0) {
      return '';
    }
    return this.entries.get(ticket)?.fileUri ?? '';
  }

  private remember(ticket: string, entry: DocumentViewerHtmlFileTransportEntry): void {
    while (this.order.length >= DOCUMENT_VIEWER_HTML_FILE_TRANSPORT_LIMIT) {
      const oldest = this.order.shift();
      if (oldest === undefined) {
        break;
      }
      this.entries.delete(oldest);
    }
    this.order.push(ticket);
    this.entries.set(ticket, entry);
  }

  private createTicket(sequence: number): string {
    const timePart = Date.now().toString(16);
    const sequencePart = sequence.toString(16);
    const randomPartA = Math.floor(Math.random() * 0x100000000).toString(16);
    const randomPartB = Math.floor(Math.random() * 0x100000000).toString(16);
    return `${timePart}${sequencePart}${randomPartA}${randomPartB}`;
  }

  private readTicket(url: string): string {
    const trimmed = url.trim();
    const lower = trimmed.toLowerCase();
    if (!lower.startsWith(DOCUMENT_VIEWER_HTML_FILE_TRANSPORT_PREFIX)) {
      return '';
    }
    const rest = trimmed.substring(DOCUMENT_VIEWER_HTML_FILE_TRANSPORT_PREFIX.length);
    const end = rest.search(/[?#/]/);
    const ticket = (end >= 0 ? rest.substring(0, end) : rest).trim();
    if (ticket.length === 0 || ticket.indexOf('..') >= 0) {
      return '';
    }
    return ticket;
  }
}

export const documentViewerHtmlFileTransport: DocumentViewerHtmlFileTransport = new DocumentViewerHtmlFileTransport();
