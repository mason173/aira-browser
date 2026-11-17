import {
  DownloadV2Driver,
  DownloadV2FailureCode
} from './DownloadV2Types';

export type DownloadV2FailureReason =
  'network' |
  'permission' |
  'storage' |
  'server' |
  'certificate' |
  'file_system' |
  'unsupported' |
  'canceled' |
  'unknown';

export interface DownloadV2FailureClassification {
  code: DownloadV2FailureCode;
  reason: DownloadV2FailureReason;
  /** A user may retry after correcting the cause; this never authorizes an automatic retry. */
  retriable: boolean;
  /** Only the ArkWeb network-interruption policy uses this hint. */
  shouldPauseForNetwork: boolean;
}

function classification(
  code: DownloadV2FailureCode,
  reason: DownloadV2FailureReason,
  retriable: boolean = true,
  shouldPauseForNetwork: boolean = false
): DownloadV2FailureClassification {
  return {
    code: code,
    reason: reason,
    retriable: retriable,
    shouldPauseForNetwork: shouldPauseForNetwork
  };
}

/** Values belong to the public ArkWeb WebDownloadErrorCode enum, not CURLcode or HTTP. */
export function classifyArkWebDownloadFailure(sourceCode: number): DownloadV2FailureClassification {
  switch (sourceCode) {
    case 20: // NETWORK_FAILED
    case 21: // NETWORK_TIMEOUT
    case 22: // NETWORK_DISCONNECTED
      return classification('network', 'network', true, true);
    case 23: // NETWORK_SERVER_DOWN
    case 37: // SERVER_UNREACHABLE
      return classification('network', 'network');
    case 2: // FILE_ACCESS_DENIED
      return classification('permission', 'permission');
    case 3: // FILE_NO_SPACE
      return classification('file_system', 'storage');
    case 1: // FILE_FAILED
    case 5: // FILE_NAME_TOO_LONG
    case 6: // FILE_TOO_LARGE
    case 10: // FILE_TRANSIENT_ERROR
    case 13: // FILE_TOO_SHORT
    case 14: // FILE_HASH_MISMATCH
    case 15: // FILE_SAME_AS_SOURCE
      return classification('file_system', 'file_system');
    case 35: // SERVER_CERT_PROBLEM
      return classification('server', 'certificate');
    case 30: // SERVER_FAILED
    case 31: // SERVER_NO_RANGE: a full restart can still succeed.
    case 33: // SERVER_BAD_CONTENT
    case 34: // SERVER_UNAUTHORIZED
    case 36: // SERVER_FORBIDDEN
    case 38: // SERVER_CONTENT_LENGTH_MISMATCH
    case 39: // SERVER_CROSS_ORIGIN_REDIRECT
      return classification('server', 'server');
    case 11: // FILE_BLOCKED
    case 24: // NETWORK_INVALID_REQUEST
      return classification('unsupported', 'unsupported', false);
    case 40: // USER_CANCELED
    case 41: // USER_SHUTDOWN
      return classification('canceled', 'canceled', false);
    default:
      return classification('unknown', 'unknown');
  }
}

/** HTTP is an independent namespace. A response status must never be passed as CURLcode. */
export function classifyHttpDownloadFailure(statusCode: number): DownloadV2FailureClassification {
  if (Number.isInteger(statusCode) && statusCode >= 300 && statusCode < 600) {
    return classification('server', 'server');
  }
  return classification('unknown', 'unknown');
}

/** Values belong to vendored libcurl's CURLcode enum. No ArkWeb pause policy applies here. */
export function classifyLibcurlDownloadFailure(
  sourceCode: number,
  httpStatusCode: number = 0
): DownloadV2FailureClassification {
  if (Number.isInteger(httpStatusCode) && httpStatusCode >= 300 && httpStatusCode < 600) {
    return classifyHttpDownloadFailure(httpStatusCode);
  }
  switch (sourceCode) {
    case 1: // CURLE_UNSUPPORTED_PROTOCOL
    case 3: // CURLE_URL_MALFORMAT
      return classification('unsupported', 'unsupported', false);
    case 5: // CURLE_COULDNT_RESOLVE_PROXY
    case 6: // CURLE_COULDNT_RESOLVE_HOST
    case 7: // CURLE_COULDNT_CONNECT
    case 16: // CURLE_HTTP2
    case 18: // CURLE_PARTIAL_FILE
    case 28: // CURLE_OPERATION_TIMEDOUT
    case 35: // CURLE_SSL_CONNECT_ERROR (not proof of a certificate-validation failure)
    case 52: // CURLE_GOT_NOTHING
    case 55: // CURLE_SEND_ERROR
    case 56: // CURLE_RECV_ERROR
    case 81: // CURLE_AGAIN
    case 89: // CURLE_NO_CONNECTION_AVAILABLE
    case 92: // CURLE_HTTP2_STREAM
    case 95: // CURLE_HTTP3
    case 96: // CURLE_QUIC_CONNECT_ERROR
    case 97: // CURLE_PROXY
      return classification('network', 'network');
    case 23: // CURLE_WRITE_ERROR: may be space or permission; do not guess which.
    case 26: // CURLE_READ_ERROR
    case 63: // CURLE_FILESIZE_EXCEEDED
      return classification('file_system', 'file_system');
    case 58: // CURLE_SSL_CERTPROBLEM
    case 60: // CURLE_PEER_FAILED_VERIFICATION
    case 77: // CURLE_SSL_CACERT_BADFILE
    case 90: // CURLE_SSL_PINNEDPUBKEYNOTMATCH
    case 91: // CURLE_SSL_INVALIDCERTSTATUS
      return classification('server', 'certificate');
    case 9: // CURLE_REMOTE_ACCESS_DENIED
    case 22: // CURLE_HTTP_RETURNED_ERROR (the native snapshot may omit the HTTP status)
    case 33: // CURLE_RANGE_ERROR
    case 47: // CURLE_TOO_MANY_REDIRECTS
    case 67: // CURLE_LOGIN_DENIED
    case 78: // CURLE_REMOTE_FILE_NOT_FOUND
      return classification('server', 'server');
    case 42: // CURLE_ABORTED_BY_CALLBACK
      return classification('canceled', 'canceled', false);
    default:
      return classification('unknown', 'unknown');
  }
}

export function classifyDownloadV2Failure(
  driver: DownloadV2Driver,
  sourceCode: number,
  httpStatusCode: number = 0
): DownloadV2FailureClassification {
  return driver === 'arkweb'
    ? classifyArkWebDownloadFailure(sourceCode)
    : classifyLibcurlDownloadFailure(sourceCode, httpStatusCode);
}
