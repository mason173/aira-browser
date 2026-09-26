import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { documentViewerHtmlFileTransport } from './DocumentViewerHtmlFileTransport';

const DOCUMENT_VIEWER_HTML_FILE_LOG_DOMAIN: number = 0x0000;
const DOCUMENT_VIEWER_HTML_FILE_LOG_TAG: string = 'DocumentViewer';

export function buildDocumentViewerHtmlFileResponse(
  requestUrl: string,
  isMainFrame: boolean
): WebResourceResponse | null {
  if (!isMainFrame || !documentViewerHtmlFileTransport.isTransportUrl(requestUrl)) {
    return null;
  }
  const fileUri = documentViewerHtmlFileTransport.resolveFileUri(requestUrl);
  if (fileUri.length === 0) {
    return buildReadyHtmlResponse(
      buildMessageHtml('这个文件页面已经失效，请重新打开。'),
      404,
      'Not Found'
    );
  }
  const response = new WebResourceResponse();
  response.setResponseIsReady(false);
  fulfillHtmlFileResponse(response, fileUri);
  return response;
}

async function fulfillHtmlFileResponse(response: WebResourceResponse, fileUri: string): Promise<void> {
  let opened: fileIo.File | undefined = undefined;
  let handedToWeb = false;
  try {
    const stat = await fileIo.stat(fileUri);
    if (stat.isDirectory()) {
      applyHtmlMessage(response, buildMessageHtml('请选择文件。'), 400, 'Bad Request');
      return;
    }
    const sizeBytes = Math.max(0, Math.floor(stat.size));
    if (sizeBytes <= 0) {
      applyHtmlMessage(response, buildMessageHtml('这个 HTML 文件没有内容。'), 200, 'OK');
      return;
    }
    opened = await fileIo.open(fileUri, fileIo.OpenMode.READ_ONLY);
    response.setResponseHeader([
      { headerKey: 'Cache-Control', headerValue: 'no-store' },
      { headerKey: 'Content-Length', headerValue: `${sizeBytes}` }
    ]);
    response.setResponseEncoding('utf-8');
    response.setResponseMimeType(resolveHtmlMimeType(fileUri));
    response.setResponseCode(200);
    response.setReasonMessage('OK');
    response.setResponseData(opened.fd);
    handedToWeb = true;
    hilog.info(
      DOCUMENT_VIEWER_HTML_FILE_LOG_DOMAIN,
      DOCUMENT_VIEWER_HTML_FILE_LOG_TAG,
      'html file handed to web fd bytes=%{public}d',
      sizeBytes
    );
  } catch (error) {
    hilog.error(
      DOCUMENT_VIEWER_HTML_FILE_LOG_DOMAIN,
      DOCUMENT_VIEWER_HTML_FILE_LOG_TAG,
      'html file response failed code=%{public}s',
      readErrorCode(error)
    );
    applyHtmlMessage(response, buildMessageHtml('无法读取这个 HTML 文件。'), 500, 'Error');
  } finally {
    if (opened !== undefined && !handedToWeb) {
      await closeQuietly(opened);
    }
    response.setResponseIsReady(true);
  }
}

function applyHtmlMessage(
  response: WebResourceResponse,
  html: string,
  code: number,
  reason: string
): void {
  response.setResponseHeader([
    { headerKey: 'Cache-Control', headerValue: 'no-store' }
  ]);
  response.setResponseData(html);
  response.setResponseEncoding('utf-8');
  response.setResponseMimeType('text/html');
  response.setResponseCode(code);
  response.setReasonMessage(reason);
}

function buildReadyHtmlResponse(html: string, code: number, reason: string): WebResourceResponse {
  const response = new WebResourceResponse();
  applyHtmlMessage(response, html, code, reason);
  response.setResponseIsReady(true);
  return response;
}

function resolveHtmlMimeType(fileUri: string): string {
  const path = stripQueryAndFragment(fileUri).toLowerCase();
  if (path.endsWith('.xhtml')) {
    return 'application/xhtml+xml';
  }
  return 'text/html';
}

function stripQueryAndFragment(url: string): string {
  const queryIndex = url.indexOf('?');
  const hashIndex = url.indexOf('#');
  let endIndex = url.length;
  if (queryIndex >= 0) {
    endIndex = Math.min(endIndex, queryIndex);
  }
  if (hashIndex >= 0) {
    endIndex = Math.min(endIndex, hashIndex);
  }
  return url.substring(0, endIndex);
}

function buildMessageHtml(message: string): string {
  return `<!doctype html><html><head><meta charset="utf-8">` +
    `<meta name="viewport" content="width=device-width,initial-scale=1"></head>` +
    `<body><p>${message}</p></body></html>`;
}

function readErrorCode(error: Object): string {
  const businessError = error as BusinessError;
  if (businessError.code === undefined) {
    return 'unknown';
  }
  return `${businessError.code}`;
}

async function closeQuietly(file: fileIo.File): Promise<void> {
  try {
    await fileIo.close(file);
  } catch (_error) {
    return;
  }
}
