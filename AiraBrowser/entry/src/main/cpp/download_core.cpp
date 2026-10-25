#include "download_core.h"
#include "download_hls.h"

#include <curl/curl.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cctype>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <limits>
#include <sstream>
#include <unordered_set>
#include <utility>

namespace aira::download {

// Each easy handle owns its cookie engine. Only serialized cookie snapshots
// cross worker threads; libcurl does not support concurrent shared cookie jars.
struct DownloadSession {
  using Cookies = std::unordered_map<std::string, std::string>;
  std::mutex mutex;
  Cookies cookies;
  explicit DownloadSession(const TaskOptions& options);
  Cookies Attach(CURL* handle);
  void Capture(CURL* handle, const Cookies& initial);
};

namespace {

constexpr std::int64_t kMaxResumeBytes = std::numeric_limits<std::int64_t>::max();
constexpr std::uint64_t kFnvOffsetBasis = 14695981039346656037ULL;
constexpr std::uint64_t kFnvPrime = 1099511628211ULL;
constexpr int kHlsTransferMaxAttempts = 6;
constexpr int kHlsRetryInitialDelayMs = 500;
constexpr int kHlsRetryMaxDelayMs = 8000;
constexpr int kHlsRetryPollMs = 25;
constexpr std::int64_t kSpeedSampleWindowMs = 1000;
constexpr std::int64_t kSpeedPreviousWeight = 3;
constexpr std::int64_t kSpeedCurrentWeight = 2;

struct CurlDiagnosticBuffer {
  std::array<char, CURL_ERROR_SIZE> value{};
};

void EnsureCurlInitialized() {
  static const CURLcode result = curl_global_init(CURL_GLOBAL_DEFAULT);
  (void)result;
}

std::int64_t ExistingFileSize(const std::string& path) {
  std::error_code error;
  const std::uintmax_t size = std::filesystem::file_size(path, error);
  if (error || size > static_cast<std::uintmax_t>(kMaxResumeBytes)) {
    return 0;
  }
  return static_cast<std::int64_t>(size);
}

std::string Trim(const std::string& value) {
  const auto first = value.find_first_not_of(" \t\r\n");
  if (first == std::string::npos) {
    return {};
  }
  const auto last = value.find_last_not_of(" \t\r\n");
  return value.substr(first, last - first + 1);
}

std::string CompactDiagnosticText(const char* value) {
  if (value == nullptr) {
    return {};
  }
  std::string result(value);
  for (char& character : result) {
    if (character == '\r' || character == '\n' || character == '\t' || character == '|') {
      character = ' ';
    }
  }
  return Trim(result);
}

std::string UrlHost(const char* value) {
  if (value == nullptr || value[0] == '\0') {
    return {};
  }
  CURLU* url = curl_url();
  if (url == nullptr) {
    return {};
  }
  char* host = nullptr;
  const bool ok = curl_url_set(url, CURLUPART_URL, value, 0) == CURLUE_OK &&
    curl_url_get(url, CURLUPART_HOST, &host, 0) == CURLUE_OK && host != nullptr;
  const std::string result = ok ? host : "";
  curl_free(host);
  curl_url_cleanup(url);
  return result;
}

void AttachCurlDiagnostics(CURL* handle, CurlDiagnosticBuffer* diagnostics) {
  if (handle == nullptr || diagnostics == nullptr) {
    return;
  }
  diagnostics->value.fill('\0');
  curl_easy_setopt(handle, CURLOPT_ERRORBUFFER, diagnostics->value.data());
}

std::string LowerAscii(std::string value) {
  for (char& character : value) {
    character = static_cast<char>(std::tolower(static_cast<unsigned char>(character)));
  }
  return value;
}

bool HostHasNoPeriod(const std::string& url) {
  const std::string host = UrlHost(url.c_str());
  return !host.empty() && host.find('.') == std::string::npos && host.find(':') == std::string::npos;
}

struct DownloadProxyPlan {
  bool configured = false;
  bool suppressed = false;
  std::string scheme;
  std::string host;
  int port = 0;
  std::string url;
};

DownloadProxyPlan BuildDownloadProxyPlan(const TaskOptions& options, const std::string& request_url) {
  DownloadProxyPlan plan;
  const std::string scheme = LowerAscii(Trim(options.proxy_scheme));
  const std::string host = Trim(options.proxy_host);
  if (host.empty() || options.proxy_port <= 0 || options.proxy_port > 65535) {
    return plan;
  }
  if (scheme == "http" || scheme == "https") {
    plan.scheme = scheme;
  } else if (scheme == "socks5" || scheme == "socks") {
    // ArkWeb documents socks:// as SOCKS and resolves the target on the proxy.
    // socks5h is the libcurl scheme with that same remote-DNS behavior.
    plan.scheme = "socks5h";
  } else {
    return plan;
  }
  plan.configured = true;
  plan.host = host;
  plan.port = options.proxy_port;
  if (HostHasNoPeriod(request_url)) {
    plan.suppressed = true;
    return plan;
  }
  std::string formatted_host = host;
  if (formatted_host.find(':') != std::string::npos && formatted_host.front() != '[') {
    formatted_host = "[" + formatted_host + "]";
  }
  plan.url = plan.scheme + "://" + formatted_host + ":" + std::to_string(plan.port);
  return plan;
}

void ApplyDownloadProxy(CURL* handle, const TaskOptions& options, const std::string& request_url) {
  if (handle == nullptr) {
    return;
  }
  const DownloadProxyPlan plan = BuildDownloadProxyPlan(options, request_url);
  if (!plan.configured || plan.suppressed || plan.url.empty()) {
    curl_easy_setopt(handle, CURLOPT_PROXY, "");
    return;
  }
  curl_easy_setopt(handle, CURLOPT_PROXY, plan.url.c_str());
  const std::string username = Trim(options.proxy_username);
  if (!username.empty()) {
    curl_easy_setopt(handle, CURLOPT_PROXYUSERNAME, username.c_str());
    curl_easy_setopt(handle, CURLOPT_PROXYPASSWORD, options.proxy_password.c_str());
    if (plan.scheme == "http" || plan.scheme == "https") {
      // Basic is sent on the first request. ANY waits for a challenge, which drops
      // credentials when a proxy accepts anonymous requests and only rejects bad ones.
      curl_easy_setopt(handle, CURLOPT_PROXYAUTH, CURLAUTH_BASIC);
    }
  }
  const std::string no_proxy = Trim(options.proxy_noproxy);
  if (!no_proxy.empty()) {
    curl_easy_setopt(handle, CURLOPT_NOPROXY, no_proxy.c_str());
  }
}

std::string DescribeCurlTransfer(CURL* handle, CURLcode result, long response_code,
                                 const char* phase, const TaskOptions& options,
                                 const std::string& request_url,
                                 const CurlDiagnosticBuffer& diagnostics) {
  const std::string& ca_path = options.ca_path;
  char* effective_url = nullptr;
  char* primary_ip = nullptr;
  char* local_ip = nullptr;
  long primary_port = 0;
  long local_port = 0;
  long os_errno = 0;
  long ssl_verify_result = 0;
  long http_version = 0;
  curl_off_t name_lookup_us = 0;
  curl_off_t connect_us = 0;
  curl_off_t app_connect_us = 0;
  curl_off_t start_transfer_us = 0;
  curl_off_t total_us = 0;
  curl_easy_getinfo(handle, CURLINFO_EFFECTIVE_URL, &effective_url);
  curl_easy_getinfo(handle, CURLINFO_PRIMARY_IP, &primary_ip);
  curl_easy_getinfo(handle, CURLINFO_LOCAL_IP, &local_ip);
  curl_easy_getinfo(handle, CURLINFO_PRIMARY_PORT, &primary_port);
  curl_easy_getinfo(handle, CURLINFO_LOCAL_PORT, &local_port);
  curl_easy_getinfo(handle, CURLINFO_OS_ERRNO, &os_errno);
  curl_easy_getinfo(handle, CURLINFO_SSL_VERIFYRESULT, &ssl_verify_result);
  curl_easy_getinfo(handle, CURLINFO_HTTP_VERSION, &http_version);
  curl_easy_getinfo(handle, CURLINFO_NAMELOOKUP_TIME_T, &name_lookup_us);
  curl_easy_getinfo(handle, CURLINFO_CONNECT_TIME_T, &connect_us);
  curl_easy_getinfo(handle, CURLINFO_APPCONNECT_TIME_T, &app_connect_us);
  curl_easy_getinfo(handle, CURLINFO_STARTTRANSFER_TIME_T, &start_transfer_us);
  curl_easy_getinfo(handle, CURLINFO_TOTAL_TIME_T, &total_us);

  std::error_code ca_error;
  const bool ca_exists = !ca_path.empty() && std::filesystem::exists(ca_path, ca_error);
  ca_error.clear();
  const bool ca_directory = ca_exists && std::filesystem::is_directory(ca_path, ca_error);
  const DownloadProxyPlan proxy = BuildDownloadProxyPlan(options, request_url);
  long used_proxy = 0;
  if (handle != nullptr) {
    // CURLINFO_USED_PROXY arrived in libcurl 7.86. The vendored 8.7.1 headers define it;
    // older platform headers still link a new enough libcurl, so keep the numeric value.
#ifndef CURLINFO_USED_PROXY
    const CURLcode used_proxy_result = curl_easy_getinfo(
      handle, static_cast<CURLINFO>(CURLINFO_LONG + 66), &used_proxy);
#else
    const CURLcode used_proxy_result = curl_easy_getinfo(handle, CURLINFO_USED_PROXY, &used_proxy);
#endif
    if (used_proxy_result != CURLE_OK) {
      used_proxy = 0;
    }
  }
  std::ostringstream output;
  output << "proxyConfigured=" << (proxy.configured ? 1 : 0)
         << "|proxyUsed=" << used_proxy
         << "|proxySuppressed=" << (proxy.suppressed ? 1 : 0)
         << "|proxyScheme=" << proxy.scheme
         << "|phase=" << (phase == nullptr ? "unknown" : phase)
         << "|curl=" << static_cast<int>(result)
         << "|curlText=" << curl_easy_strerror(result)
         << "|detail=" << CompactDiagnosticText(diagnostics.value.data())
         << "|http=" << response_code
         << "|host=" << UrlHost(effective_url)
         << "|remote=" << CompactDiagnosticText(primary_ip) << ':' << primary_port
         << "|local=" << CompactDiagnosticText(local_ip) << ':' << local_port
         << "|osErrno=" << os_errno
         << "|sslVerify=" << ssl_verify_result
         << "|httpVersion=" << http_version
         << "|dnsUs=" << name_lookup_us
         << "|connectUs=" << connect_us
         << "|tlsUs=" << app_connect_us
         << "|firstByteUs=" << start_transfer_us
         << "|totalUs=" << total_us
         << "|caPath=" << (ca_path.empty() ? "empty" : ca_path)
         << "|caExists=" << (ca_exists ? 1 : 0)
         << "|caDirectory=" << (ca_directory ? 1 : 0);
  return output.str();
}

std::string CurlFailureMessage(CURLcode result, long response_code) {
  if (response_code >= 300) {
    return "下载服务器返回 HTTP " + std::to_string(response_code) + "。";
  }
  if (result == CURLE_COULDNT_RESOLVE_PROXY || result == CURLE_PROXY) {
    return "无法连接下载代理。";
  }
  if (result == CURLE_WRITE_ERROR) {
    return "无法写入下载文件，请检查剩余空间与保存权限。";
  }
  if (result == CURLE_SSL_CONNECT_ERROR) {
    return "SSL 连接失败。";
  }
  if (result == CURLE_PEER_FAILED_VERIFICATION || result == CURLE_SSL_CACERT_BADFILE) {
    return "服务器证书校验失败。";
  }
  return curl_easy_strerror(result);
}

bool IsRetryableHlsTransferFailure(CURLcode result, long response_code) {
  if (response_code == 408 || response_code == 425 || response_code == 429 ||
      (response_code >= 500 && response_code < 600)) {
    return true;
  }
  switch (result) {
    case CURLE_COULDNT_RESOLVE_PROXY:
    case CURLE_COULDNT_RESOLVE_HOST:
    case CURLE_COULDNT_CONNECT:
    case CURLE_PARTIAL_FILE:
    case CURLE_OPERATION_TIMEDOUT:
    case CURLE_SSL_CONNECT_ERROR:
    case CURLE_SEND_ERROR:
    case CURLE_RECV_ERROR:
    case CURLE_GOT_NOTHING:
    case CURLE_HTTP2:
    case CURLE_HTTP2_STREAM:
    case CURLE_AGAIN:
    case CURLE_SSL_SHUTDOWN_FAILED:
      return true;
    default:
      return false;
  }
}

int HlsRetryDelayMsAfterAttempt(int attempt) {
  if (attempt <= 0 || attempt >= kHlsTransferMaxAttempts) {
    return 0;
  }
  int delay_ms = kHlsRetryInitialDelayMs;
  for (int index = 1; index < attempt && delay_ms < kHlsRetryMaxDelayMs; ++index) {
    delay_ms = std::min(delay_ms * 2, kHlsRetryMaxDelayMs);
  }
  return delay_ms;
}

std::string AppendRetryDiagnostic(const std::string& diagnostic, int attempt, bool retryable) {
  return diagnostic + "|attempt=" + std::to_string(attempt) +
    "|maxAttempts=" + std::to_string(kHlsTransferMaxAttempts) +
    "|retryable=" + (retryable ? "1" : "0") +
    "|nextRetryDelayMs=" + std::to_string(retryable ? HlsRetryDelayMsAfterAttempt(attempt) : 0) +
    "|retryDelayCapMs=" + std::to_string(kHlsRetryMaxDelayMs);
}

bool IsTaskTransferInterrupted(DownloadTask* task) {
  if (task == nullptr) {
    return false;
  }
  const TaskState state = task->Snapshot().state;
  return state == TaskState::kCanceled || state == TaskState::kPausing || state == TaskState::kPaused;
}

bool WaitForTransferRetry(DownloadTask* task, int delay_ms) {
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(delay_ms);
  while (std::chrono::steady_clock::now() < deadline) {
    if (IsTaskTransferInterrupted(task)) {
      return false;
    }
    const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(
      deadline - std::chrono::steady_clock::now()).count();
    const auto poll_delay_ms = std::max<std::int64_t>(1, std::min<std::int64_t>(kHlsRetryPollMs, remaining));
    std::this_thread::sleep_for(std::chrono::milliseconds(poll_delay_ms));
  }
  return !IsTaskTransferInterrupted(task);
}

bool WaitForHlsRetry(DownloadTask* task, int failed_attempt, curl_off_t retry_after) {
  if (retry_after > 30) return false;
  const int delay_ms = std::max(HlsRetryDelayMsAfterAttempt(failed_attempt),
    static_cast<int>(std::max<curl_off_t>(0, retry_after)) * 1000);
  return WaitForTransferRetry(task, delay_ms);
}

std::uint64_t StableHash(const std::string& value) {
  std::uint64_t hash = kFnvOffsetBasis;
  for (const unsigned char byte : value) {
    hash ^= byte;
    hash *= kFnvPrime;
  }
  return hash;
}

void CleanupHlsArtifacts(const std::string& target_path) {
  const std::filesystem::path target(target_path);
  const std::filesystem::path directory = target.has_parent_path() ? target.parent_path() : ".";
  const std::string prefix = target.filename().string() + ".aira-hls.";
  std::error_code iterator_error;
  std::filesystem::directory_iterator iterator(directory, iterator_error);
  const std::filesystem::directory_iterator end;
  while (!iterator_error && iterator != end) {
    const std::string file_name = iterator->path().filename().string();
    if (file_name.rfind(prefix, 0) == 0) {
      std::error_code remove_error;
      std::filesystem::remove(iterator->path(), remove_error);
    }
    iterator.increment(iterator_error);
  }
}

struct MemoryContext {
  std::string data;
  DownloadTask* task = nullptr;
  std::size_t max_bytes = 8 * 1024 * 1024;
  bool exceeded_limit = false;
};

std::size_t MemoryWriteCallback(char* data, std::size_t size, std::size_t count, void* user_data) {
  auto* context = static_cast<MemoryContext*>(user_data);
  if (context == nullptr || data == nullptr) {
    return 0;
  }
  if (context->task != nullptr) {
    const TaskState state = context->task->Snapshot().state;
    if (state == TaskState::kCanceled || state == TaskState::kPausing) {
      return 0;
    }
  }
  if (size * count > context->max_bytes - context->data.size()) {
    context->exceeded_limit = true;
    return 0;
  }
  context->data.append(data, size * count);
  return size * count;
}

int MemoryProgressCallback(void* user_data, std::int64_t, std::int64_t, std::int64_t, std::int64_t) {
  auto* context = static_cast<MemoryContext*>(user_data);
  if (context == nullptr || context->task == nullptr) {
    return 0;
  }
  const TaskState state = context->task->Snapshot().state;
  return state == TaskState::kCanceled || state == TaskState::kPausing ? 1 : 0;
}

std::string UrlOrigin(const std::string& value) {
  CURLU* url = curl_url();
  if (url == nullptr) return {};
  char* scheme = nullptr;
  char* host = nullptr;
  char* port = nullptr;
  const bool ok = curl_url_set(url, CURLUPART_URL, value.c_str(), 0) == CURLUE_OK &&
    curl_url_get(url, CURLUPART_SCHEME, &scheme, 0) == CURLUE_OK &&
    curl_url_get(url, CURLUPART_HOST, &host, 0) == CURLUE_OK &&
    curl_url_get(url, CURLUPART_PORT, &port, CURLU_DEFAULT_PORT) == CURLUE_OK;
  const std::string origin = ok ? LowerAscii(std::string(scheme) + "://" + host + ":" + port) : "";
  curl_free(scheme);
  curl_free(host);
  curl_free(port);
  curl_url_cleanup(url);
  return origin;
}

bool AddHeaders(CURL* handle, const TaskOptions& options, const std::string& request_url, curl_slist** output) {
  const std::string source_origin = UrlOrigin(options.url);
  const bool same_origin = !source_origin.empty() && source_origin == UrlOrigin(request_url);
  const auto& values = options.headers;
  for (const std::string& header : values) {
    const std::string name = LowerAscii(Trim(header.substr(0, header.find(':'))));
    if (!header.empty() && name != "cookie" && name != "range" && name != "if-range" &&
        name != "proxy-authorization" && (name != "authorization" || same_origin)) {
      curl_slist* appended = curl_slist_append(*output, header.c_str());
      if (appended == nullptr) {
        return false;
      }
      *output = appended;
    }
  }
  if (*output != nullptr) {
    curl_easy_setopt(handle, CURLOPT_HTTPHEADER, *output);
  }
  return true;
}

bool FetchText(const TaskOptions& options, const std::string& url, std::string* output,
               DownloadTask* task, std::string* error, std::int32_t* error_code,
               std::string* diagnostic_message, std::string* failure_phase,
               const char* phase, DownloadSession* session, std::string* effective_url = nullptr,
               std::size_t max_bytes = 8 * 1024 * 1024) {
  for (int attempt = 1; attempt <= kHlsTransferMaxAttempts; ++attempt) {
    CURL* handle = curl_easy_init();
    if (handle == nullptr) {
      *error = "无法创建 libcurl 清单任务。";
      *failure_phase = phase;
      return false;
    }
    MemoryContext context{{}, task, max_bytes};
    const auto initial_cookies = session->Attach(handle);
    CurlDiagnosticBuffer diagnostics;
    AttachCurlDiagnostics(handle, &diagnostics);
    curl_slist* header_list = nullptr;
    curl_easy_setopt(handle, CURLOPT_URL, url.c_str());
    ApplyDownloadProxy(handle, options, url);
    curl_easy_setopt(handle, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(handle, CURLOPT_MAXREDIRS, 10L);
    curl_easy_setopt(handle, CURLOPT_CONNECTTIMEOUT_MS, 15000L);
    curl_easy_setopt(handle, CURLOPT_LOW_SPEED_LIMIT, 1L);
    curl_easy_setopt(handle, CURLOPT_LOW_SPEED_TIME, 45L);
    curl_easy_setopt(handle, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(handle, CURLOPT_PROTOCOLS_STR, "http,https");
    curl_easy_setopt(handle, CURLOPT_REDIR_PROTOCOLS_STR, "http,https");
    curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, &MemoryWriteCallback);
    curl_easy_setopt(handle, CURLOPT_WRITEDATA, &context);
    curl_easy_setopt(handle, CURLOPT_XFERINFOFUNCTION, &MemoryProgressCallback);
    curl_easy_setopt(handle, CURLOPT_XFERINFODATA, &context);
    curl_easy_setopt(handle, CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(handle, CURLOPT_USERAGENT, "AiraBrowser/DownloadCore");
    curl_easy_setopt(handle, CURLOPT_FAILONERROR, 1L);
    if (!options.ca_path.empty()) {
      curl_easy_setopt(handle, CURLOPT_CAPATH, options.ca_path.c_str());
    }
    if (!AddHeaders(handle, options, url, &header_list)) {
      curl_slist_free_all(header_list);
      curl_easy_cleanup(handle);
      *error = "无法创建下载请求头。";
      *failure_phase = phase;
      return false;
    }
    const CURLcode result = curl_easy_perform(handle);
    long response_code = 0;
    curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE, &response_code);
    curl_off_t retry_after = 0;
    curl_easy_getinfo(handle, CURLINFO_RETRY_AFTER, &retry_after);
    const bool retryable = IsRetryableHlsTransferFailure(result, response_code);
    const std::string transfer_diagnostic = AppendRetryDiagnostic(
      DescribeCurlTransfer(handle, result, response_code, phase, options, url, diagnostics),
      attempt, retryable);
    if (effective_url != nullptr) {
      char* final_url = nullptr;
      curl_easy_getinfo(handle, CURLINFO_EFFECTIVE_URL, &final_url);
      *effective_url = final_url == nullptr ? url : final_url;
    }
    session->Capture(handle, initial_cookies);
    curl_slist_free_all(header_list);
    curl_easy_cleanup(handle);
    if (result == CURLE_OK && response_code >= 200 && response_code < 300) {
      *output = std::move(context.data);
      return true;
    }
    *error = context.exceeded_limit ? "HLS 响应超过允许大小。" : CurlFailureMessage(result, response_code);
    *error_code = static_cast<std::int32_t>(result);
    *diagnostic_message = transfer_diagnostic;
    *failure_phase = phase;
    if (!retryable || attempt >= kHlsTransferMaxAttempts || !WaitForHlsRetry(task, attempt, retry_after)) {
      return false;
    }
  }
  return false;
}

bool ParseHlsPlaylist(const TaskOptions& options, const std::string& playlist,
                      const std::string& effective_url, DownloadTask* task, DownloadSession* session,
                      HlsPlan* plan, std::string* error, std::int32_t* error_code,
                      std::string* diagnostic_message, std::string* failure_phase) {
  std::vector<HlsVariant> variants;
  HlsPlan media;
  if (!ParseHlsMedia(playlist, effective_url, &media, &variants, error)) return false;
  std::string media_playlist = playlist;
  std::string media_url = effective_url;
  if (!variants.empty()) {
    const auto selected = *std::max_element(variants.begin(), variants.end(),
      [](const auto& left, const auto& right) { return left.bandwidth < right.bandwidth; });
    if (selected.external_audio) {
      *error = "此 HLS 视频包含独立音轨，当前无法合并音视频。";
      return false;
    }
    media = {};
    if (!FetchText(options, selected.url, &media_playlist, task, error, error_code,
                   diagnostic_message, failure_phase, "hls_variant_manifest", session, &media_url) ||
        !ParseHlsMedia(media_playlist, media_url, &media, nullptr, error)) {
      if (failure_phase->empty()) *failure_phase = "hls_variant_parse";
      return false;
    }
  }
  // Version the checkpoint layout: parts now include ordered initialization
  // sections and decrypted media, never the old ciphertext/single-map layout.
  media.hash = StableHash("hls-v2\n" + media_url + "\n" + media_playlist);
  for (auto& key : media.keys) {
    std::string bytes;
    if (!FetchText(options, key.url, &bytes, task, error, error_code,
                   diagnostic_message, failure_phase, "hls_key", session, nullptr, 17)) {
      if (*error_code == CURLE_WRITE_ERROR && !IsTaskTransferInterrupted(task)) {
        *error = "HLS AES-128 密钥必须为 16 字节。";
      }
      return false;
    }
    if (bytes.size() != key.bytes.size()) {
      *error = "HLS AES-128 密钥必须为 16 字节。";
      *failure_phase = "hls_key";
      return false;
    }
    std::copy(bytes.begin(), bytes.end(), key.bytes.begin());
    media.hash ^= StableHash(bytes);
    media.hash *= kFnvPrime;
    std::fill(bytes.begin(), bytes.end(), '\0');
  }
  *plan = std::move(media);
  return true;
}

}  // namespace

namespace {
std::string CookieIdentity(const std::string& line) {
  std::vector<std::string> fields;
  std::istringstream input(line);
  std::string field;
  while (std::getline(input, field, '\t')) fields.push_back(field);
  return fields.size() >= 7 ? fields[0] + "\t" + fields[2] + "\t" + fields[5] : "";
}
DownloadSession::Cookies ReadCookies(CURL* handle) {
  DownloadSession::Cookies result;
  curl_slist* cookies = nullptr;
  curl_easy_getinfo(handle, CURLINFO_COOKIELIST, &cookies);
  for (auto* item = cookies; item != nullptr; item = item->next) {
    const std::string line = item->data;
    const std::string key = CookieIdentity(line);
    if (!key.empty()) result[key] = line;
  }
  curl_slist_free_all(cookies);
  return result;
}
}  // namespace

DownloadSession::DownloadSession(const TaskOptions& options) {
  const std::string host = UrlHost(options.url.c_str());
  if (host.empty()) return;
  for (const std::string& header : options.headers) {
    const auto colon = header.find(':');
    if (colon == std::string::npos || LowerAscii(Trim(header.substr(0, colon))) != "cookie") continue;
    std::istringstream values(header.substr(colon + 1));
    std::string pair;
    while (std::getline(values, pair, ';')) {
      const auto equals = pair.find('=');
      if (equals == std::string::npos) continue;
      const std::string name = Trim(pair.substr(0, equals));
      const std::string value = Trim(pair.substr(equals + 1));
      if (name.empty() || name.find_first_of("\r\n\t") != std::string::npos ||
          value.find_first_of("\r\n\t") != std::string::npos) continue;
      // ArkWeb exposes a request Cookie string without scope metadata. Import
      // it as host-only, never as a header forwarded to other HLS origins.
      const std::string line = host + "\tFALSE\t/\t" +
        (options.url.rfind("https:", 0) == 0 ? "TRUE" : "FALSE") + "\t0\t" + name + "\t" + value;
      cookies[CookieIdentity(line)] = line;
    }
  }
}

DownloadSession::Cookies DownloadSession::Attach(CURL* handle) {
  curl_easy_setopt(handle, CURLOPT_COOKIEFILE, "");
  std::lock_guard<std::mutex> lock(mutex);
  for (const auto& cookie : cookies) curl_easy_setopt(handle, CURLOPT_COOKIELIST, cookie.second.c_str());
  return cookies;
}

void DownloadSession::Capture(CURL* handle, const Cookies& initial) {
  const Cookies current = ReadCookies(handle);
  std::lock_guard<std::mutex> lock(mutex);
  // Apply deltas so a slower worker cannot overwrite another worker's fresh
  // cookie with an unchanged copy imported at its start.
  for (const auto& item : current) {
    const auto previous = initial.find(item.first);
    if (previous == initial.end() || previous->second != item.second) cookies[item.first] = item.second;
  }
  for (const auto& item : initial) {
    if (current.find(item.first) == current.end()) {
      const auto latest = cookies.find(item.first);
      if (latest != cookies.end() && latest->second == item.second) cookies.erase(latest);
    }
  }
}

void CleanupHlsTaskArtifacts(const std::string& target_path) {
  CleanupHlsArtifacts(target_path);
}

struct DownloadTask::TransferContext {
  DownloadTask* task = nullptr;
  FILE* file = nullptr;
  std::int64_t initial_offset = 0;
  std::atomic<std::int64_t>* aggregate_received = nullptr;
  std::size_t hls_resource_index = 0;
  std::int64_t last_download_now = 0;
  bool track_progress = true;
  bool saw_content_range = false;
  std::int64_t content_range_start = -1;
  std::int64_t content_range_end = -1;
  std::int64_t content_range_total = -1;
  bool validate_range = false;
  std::int64_t requested_length = 0;
  std::string expected_etag;
  std::string response_etag;
  bool RangeMatches() const {
    return saw_content_range && content_range_start == initial_offset &&
      content_range_end >= content_range_start && content_range_total > content_range_end &&
      (requested_length <= 0 || content_range_end - content_range_start + 1 == requested_length) &&
      (expected_etag.empty() || (response_etag == expected_etag && content_range_end == content_range_total - 1));
  }
};

DownloadTask::DownloadTask(TaskOptions options) : options_(std::move(options)) {
  EnsureCurlInitialized();
  session_ = std::make_unique<DownloadSession>(options_);
}

DownloadTask::~DownloadTask() {
  Shutdown();
}

bool DownloadTask::StartWorkerLocked() {
  if (worker_.joinable()) {
    return false;
  }
  pause_requested_.store(false, std::memory_order_release);
  cancel_requested_.store(false, std::memory_order_release);
  shutdown_requested_.store(false, std::memory_order_release);
  worker_finished_.store(false, std::memory_order_release);
  state_ = TaskState::kRunning;
  speed_bytes_per_second_ = 0;
  speed_sample_bytes_ = received_bytes_;
  speed_sample_time_ms_ = 0;
  error_code_ = 0;
  error_message_.clear();
  diagnostic_message_.clear();
  failure_phase_.clear();
  worker_ = std::thread(&DownloadTask::Run, this);
  return true;
}

void DownloadTask::JoinFinishedWorker() {
  std::thread finished;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (worker_.joinable() && worker_finished_.load(std::memory_order_acquire)) {
      finished = std::move(worker_);
    }
  }
  if (finished.joinable()) {
    finished.join();
  }
}

bool DownloadTask::Start() {
  JoinFinishedWorker();
  std::lock_guard<std::mutex> lock(mutex_);
  if (state_ == TaskState::kRunning || state_ == TaskState::kPausing ||
      state_ == TaskState::kCompleted || state_ == TaskState::kCanceled) {
    return false;
  }
  return StartWorkerLocked();
}

bool DownloadTask::Pause() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (state_ != TaskState::kRunning) {
    return false;
  }
  state_ = TaskState::kPausing;
  pause_requested_.store(true, std::memory_order_release);
  return true;
}

bool DownloadTask::Resume() {
  JoinFinishedWorker();
  std::lock_guard<std::mutex> lock(mutex_);
  if (state_ != TaskState::kPaused) {
    return false;
  }
  return StartWorkerLocked();
}

bool DownloadTask::Cancel() {
  bool cleanup_hls = false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (state_ == TaskState::kCompleted || state_ == TaskState::kCanceled) {
      return false;
    }
    cleanup_hls = options_.hls &&
      (state_ == TaskState::kCreated || state_ == TaskState::kPaused || state_ == TaskState::kFailed);
    cancel_requested_.store(true, std::memory_order_release);
    state_ = TaskState::kCanceled;
  }
  if (cleanup_hls) {
    CleanupHlsArtifacts(options_.target_path);
  }
  if (!options_.hls) {
    std::error_code error;
    std::filesystem::remove(options_.target_path + ".aira-resume", error);
    std::filesystem::remove(options_.target_path + ".aira-resume.tmp", error);
  }
  return true;
}

TaskSnapshot DownloadTask::Snapshot() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return {
    state_,
    received_bytes_,
    total_bytes_,
    speed_bytes_per_second_,
    error_code_,
    error_message_,
    diagnostic_message_,
    failure_phase_,
    file_extension_,
    hls_progress_ == nullptr ? -1 : state_ == TaskState::kCompleted ? 1 : hls_progress_->Fraction(),
    hls_progress_ == nullptr || state_ == TaskState::kCompleted ? 0 :
      (hls_progress_->EstimatedTotalBytes() > 0 ?
        std::max(received_bytes_, hls_progress_->EstimatedTotalBytes()) : 0)
  };
}

bool DownloadTask::FinishIfInterrupted() {
  if (cancel_requested_.load(std::memory_order_acquire)) {
    if (options_.hls && !shutdown_requested_.load(std::memory_order_acquire)) {
      CleanupHlsArtifacts(options_.target_path);
    }
    SetTerminalState(TaskState::kCanceled, "下载已取消。");
    return true;
  }
  if (pause_requested_.load(std::memory_order_acquire)) {
    SetTerminalState(TaskState::kPaused, "");
    return true;
  }
  return false;
}

void DownloadTask::SetTerminalState(TaskState state, const std::string& error_message,
                                    std::int32_t error_code,
                                    const std::string& diagnostic_message,
                                    const std::string& failure_phase) {
  std::lock_guard<std::mutex> lock(mutex_);
  state_ = state;
  error_code_ = error_code;
  error_message_ = error_message;
  diagnostic_message_ = diagnostic_message;
  failure_phase_ = failure_phase;
  speed_bytes_per_second_ = 0;
}

std::size_t DownloadTask::WriteCallback(char* data, std::size_t size, std::size_t count, void* user_data) {
  auto* context = static_cast<TransferContext*>(user_data);
  if (context == nullptr || context->file == nullptr) {
    return 0;
  }
  if (context->validate_range && !context->RangeMatches()) {
    return 0;
  }
  return std::fwrite(data, size, count, context->file);
}

std::size_t DownloadTask::HeaderCallback(char* data, std::size_t size, std::size_t count, void* user_data) {
  auto* context = static_cast<TransferContext*>(user_data);
  if (context == nullptr || data == nullptr) {
    return 0;
  }
  const std::string line(data, size * count);
  const std::string lower = LowerAscii(line);
  if (lower.rfind("http/", 0) == 0) {
    context->saw_content_range = false;
    context->content_range_start = -1;
    context->content_range_end = -1;
    context->content_range_total = -1;
    context->response_etag.clear();
  } else if (lower.rfind("content-range:", 0) == 0) {
    long long start = -1, end = -1, total = -1;
    if (std::sscanf(lower.c_str(), "content-range: bytes %lld-%lld/%lld", &start, &end, &total) == 3 &&
        start >= 0 && end >= start && total > end) {
      context->saw_content_range = true;
      context->content_range_start = start;
      context->content_range_end = end;
      context->content_range_total = total;
    }
  } else if (lower.rfind("etag:", 0) == 0) {
    context->response_etag = Trim(line.substr(5));
  }
  return size * count;
}

int DownloadTask::ProgressCallback(void* user_data, std::int64_t download_total, std::int64_t download_now,
                                   std::int64_t, std::int64_t) {
  auto* context = static_cast<TransferContext*>(user_data);
  if (context == nullptr || context->task == nullptr) {
    return 1;
  }
  DownloadTask* task = context->task;
  if (task->cancel_requested_.load(std::memory_order_acquire) ||
      task->pause_requested_.load(std::memory_order_acquire)) {
    return 1;
  }
  if (!context->track_progress) {
    return 0;
  }
  const auto now = std::chrono::steady_clock::now().time_since_epoch();
  const std::int64_t now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(now).count();
  std::int64_t received = 0;
  if (context->aggregate_received != nullptr) {
    const std::int64_t normalized_now = std::max<std::int64_t>(0, download_now);
    const std::int64_t delta = std::max<std::int64_t>(0, normalized_now - context->last_download_now);
    if (delta > 0) {
      context->aggregate_received->fetch_add(delta, std::memory_order_relaxed);
    }
    context->last_download_now = normalized_now;
    received = context->aggregate_received->load(std::memory_order_relaxed);
  } else {
    received = context->initial_offset + std::max<std::int64_t>(0, download_now);
  }
  {
    std::lock_guard<std::mutex> lock(task->mutex_);
    task->received_bytes_ = received;
    task->total_bytes_ = context->aggregate_received == nullptr && download_total > 0
      ? context->initial_offset + download_total : 0;
    if (context->aggregate_received != nullptr && task->hls_progress_ != nullptr) {
      task->hls_progress_->Update(context->hls_resource_index, download_now, download_total);
    }
    if (task->speed_sample_time_ms_ <= 0 || received < task->speed_sample_bytes_) {
      task->speed_sample_bytes_ = received;
      task->speed_sample_time_ms_ = now_ms;
    } else {
      const std::int64_t delta_ms = now_ms - task->speed_sample_time_ms_;
      if (delta_ms >= kSpeedSampleWindowMs) {
        const std::int64_t delta_bytes = received - task->speed_sample_bytes_;
        const std::int64_t sampled_speed = (delta_bytes * 1000) / delta_ms;
        task->speed_bytes_per_second_ = task->speed_bytes_per_second_ <= 0
          ? sampled_speed
          : (task->speed_bytes_per_second_ * kSpeedPreviousWeight +
             sampled_speed * kSpeedCurrentWeight) /
              (kSpeedPreviousWeight + kSpeedCurrentWeight);
        task->speed_sample_bytes_ = received;
        task->speed_sample_time_ms_ = now_ms;
      }
    }
  }
  return 0;
}

bool DownloadTask::TransferHlsFile(const HlsResource& resource, std::size_t resource_index,
                                   const std::string& path, const std::string& phase,
                                   std::atomic<std::int64_t>* aggregate_received, std::string* error,
                                   std::int32_t* error_code, std::string* diagnostic_message) {
  const std::string& url = resource.url;
  for (int attempt = 1; attempt <= kHlsTransferMaxAttempts; ++attempt) {
    FILE* file = std::fopen(path.c_str(), "wb");
    CURL* handle = file == nullptr ? nullptr : curl_easy_init();
    if (handle == nullptr) {
      if (file != nullptr) {
        std::fclose(file);
      }
      *error = "无法创建 HLS 分片任务。";
      return false;
    }
    const auto initial_cookies = session_->Attach(handle);
    TransferContext context;
    context.task = this;
    context.file = file;
    context.aggregate_received = aggregate_received;
    context.hls_resource_index = resource_index;
    context.validate_range = resource.offset >= 0;
    context.initial_offset = std::max<std::int64_t>(0, resource.offset);
    context.requested_length = resource.length;
    const std::string range = std::to_string(resource.offset) + "-" +
      std::to_string(resource.offset + resource.length - 1);
    if (context.validate_range) curl_easy_setopt(handle, CURLOPT_RANGE, range.c_str());
    curl_easy_setopt(handle, CURLOPT_HEADERFUNCTION, &DownloadTask::HeaderCallback);
    curl_easy_setopt(handle, CURLOPT_HEADERDATA, &context);
    CurlDiagnosticBuffer diagnostics;
    AttachCurlDiagnostics(handle, &diagnostics);
    curl_slist* headers = nullptr;
    if (!AddHeaders(handle, options_, url, &headers)) {
      curl_slist_free_all(headers);
      curl_easy_cleanup(handle);
      std::fclose(file);
      std::error_code remove_error;
      std::filesystem::remove(path, remove_error);
      *error = "无法创建下载请求头。";
      return false;
    }
    curl_easy_setopt(handle, CURLOPT_URL, url.c_str());
    ApplyDownloadProxy(handle, options_, url);
    curl_easy_setopt(handle, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(handle, CURLOPT_MAXREDIRS, 10L);
    curl_easy_setopt(handle, CURLOPT_CONNECTTIMEOUT_MS, 15000L);
    curl_easy_setopt(handle, CURLOPT_LOW_SPEED_LIMIT, 1L);
    curl_easy_setopt(handle, CURLOPT_LOW_SPEED_TIME, 45L);
    curl_easy_setopt(handle, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(handle, CURLOPT_PROTOCOLS_STR, "http,https");
    curl_easy_setopt(handle, CURLOPT_REDIR_PROTOCOLS_STR, "http,https");
    curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, &DownloadTask::WriteCallback);
    curl_easy_setopt(handle, CURLOPT_WRITEDATA, &context);
    curl_easy_setopt(handle, CURLOPT_XFERINFOFUNCTION, &DownloadTask::ProgressCallback);
    curl_easy_setopt(handle, CURLOPT_XFERINFODATA, &context);
    curl_easy_setopt(handle, CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(handle, CURLOPT_FAILONERROR, 1L);
    curl_easy_setopt(handle, CURLOPT_USERAGENT, "AiraBrowser/DownloadCore");
    if (!options_.ca_path.empty()) {
      curl_easy_setopt(handle, CURLOPT_CAPATH, options_.ca_path.c_str());
    }

    CURLcode result = curl_easy_perform(handle);
    const bool write_failed = std::ferror(file) != 0;
    if (std::fclose(file) != 0 || write_failed) result = CURLE_WRITE_ERROR;
    long response_code = 0;
    curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE, &response_code);
    curl_off_t retry_after = 0;
    curl_easy_getinfo(handle, CURLINFO_RETRY_AFTER, &retry_after);
    const bool retryable = IsRetryableHlsTransferFailure(result, response_code);
    const std::string transfer_diagnostic = AppendRetryDiagnostic(
      DescribeCurlTransfer(handle, result, response_code, phase.c_str(), options_, url, diagnostics),
      attempt, retryable);
    session_->Capture(handle, initial_cookies);
    curl_slist_free_all(headers);
    curl_easy_cleanup(handle);

    const bool interrupted = cancel_requested_.load(std::memory_order_acquire) ||
      pause_requested_.load(std::memory_order_acquire);
    const std::int64_t file_size = ExistingFileSize(path);
    const bool range_valid = !context.validate_range ||
      (response_code == 206 && context.RangeMatches() && file_size == resource.length);
    const bool succeeded = result == CURLE_OK && response_code >= 200 && response_code < 300 && file_size > 0 && range_valid;
    if (succeeded) {
      if (file_size > context.last_download_now) {
        aggregate_received->fetch_add(file_size - context.last_download_now, std::memory_order_relaxed);
      } else if (context.last_download_now > file_size) {
        aggregate_received->fetch_sub(context.last_download_now - file_size, std::memory_order_relaxed);
      }
      std::lock_guard<std::mutex> lock(mutex_);
      received_bytes_ = aggregate_received->load(std::memory_order_relaxed);
      total_bytes_ = 0;
      return true;
    }

    if (context.last_download_now > 0) {
      aggregate_received->fetch_sub(context.last_download_now, std::memory_order_relaxed);
    }
    std::error_code remove_error;
    std::filesystem::remove(path, remove_error);
    {
      std::lock_guard<std::mutex> lock(mutex_);
      received_bytes_ = aggregate_received->load(std::memory_order_relaxed);
      total_bytes_ = 0;
      hls_progress_->Update(resource_index, 0, 0);
    }
    if (interrupted) {
      return false;
    }

    *error = !range_valid ? "服务器未返回请求的 HLS 字节范围。" : result == CURLE_OK && file_size <= 0 ?
      "下载服务器返回了空分片。" : CurlFailureMessage(result, response_code);
    *error_code = static_cast<std::int32_t>(result);
    *diagnostic_message = transfer_diagnostic;
    if (!retryable || attempt >= kHlsTransferMaxAttempts || !WaitForHlsRetry(this, attempt, retry_after)) {
      return false;
    }
  }
  return false;
}

namespace {
bool StrongEtag(const std::string& value) {
  return value.size() >= 2 && value.front() == '"' && value.back() == '"' &&
    value.find_first_of("\r\n") == std::string::npos;
}
std::string ResumeEtag(const TaskOptions& options, std::string* effective_url_hash) {
  std::ifstream metadata(options.target_path + ".aira-resume");
  std::string version, url_hash, target_hash, etag;
  if (std::getline(metadata, version) && version == "aira-http-v2" &&
      std::getline(metadata, url_hash) && url_hash == std::to_string(StableHash(options.url)) &&
      std::getline(metadata, target_hash) && !target_hash.empty() &&
      std::getline(metadata, etag) && StrongEtag(etag)) {
    *effective_url_hash = target_hash;
    return etag;
  }
  return {};
}
void RemoveResumeMetadata(const std::string& path) {
  std::error_code error;
  std::filesystem::remove(path + ".aira-resume", error);
  std::filesystem::remove(path + ".aira-resume.tmp", error);
}
void SaveResumeEtag(const TaskOptions& options, const std::string& etag, const std::string& effective_url) {
  if (!StrongEtag(etag)) { RemoveResumeMetadata(options.target_path); return; }
  const std::string path = options.target_path + ".aira-resume";
  std::ofstream metadata(path + ".tmp", std::ios::trunc);
  metadata << "aira-http-v2\n" << StableHash(options.url) << '\n' << StableHash(effective_url) << '\n' << etag << '\n';
  metadata.close();
  std::error_code error;
  if (!metadata.fail()) std::filesystem::rename(path + ".tmp", path, error);
  if (metadata.fail() || error) RemoveResumeMetadata(options.target_path);
}
}  // namespace

void DownloadTask::RunHttp() {
  const std::filesystem::path target(options_.target_path);
  std::error_code directory_error;
  if (target.has_parent_path()) {
    std::filesystem::create_directories(target.parent_path(), directory_error);
    if (directory_error) {
      SetTerminalState(TaskState::kFailed, "无法创建下载目标目录。");
      worker_finished_.store(true, std::memory_order_release);
      return;
    }
  }

  std::int64_t existing_size = ExistingFileSize(options_.target_path);
  CURLcode result = CURLE_FAILED_INIT;
  long response_code = 0;
  std::string diagnostic_message;
  std::string failure_phase = "http_download";

  const auto max_attempts = std::clamp<std::size_t>(options_.http_max_attempts, 1, 5);
  std::size_t failed_attempts = 0;
  bool full_restart_used = false;
  bool force_full_restart = false;
  // Entity mismatch gets one clean restart in addition to the bounded transient
  // retry budget. Each network attempt uses the validator of the bytes on disk.
  for (std::size_t request = 0; request < max_attempts + 1; ++request) {
    existing_size = ExistingFileSize(options_.target_path);
    std::string expected_effective_url_hash;
    const std::string resume_etag = ResumeEtag(options_, &expected_effective_url_hash);
    const bool use_resume = existing_size > 0 && !resume_etag.empty() && !force_full_restart;
    if (!use_resume && existing_size > 0) {
      std::error_code truncate_error;
      std::filesystem::resize_file(options_.target_path, 0, truncate_error);
      if (truncate_error) {
        SetTerminalState(TaskState::kFailed, "无法重置下载临时文件。");
        worker_finished_.store(true, std::memory_order_release);
        return;
      }
      existing_size = 0;
      RemoveResumeMetadata(options_.target_path);
    }
    force_full_restart = false;
    FILE* file = std::fopen(options_.target_path.c_str(), use_resume ? "ab" : "wb");
    if (file == nullptr) {
      SetTerminalState(TaskState::kFailed, "无法打开下载目标文件。");
      worker_finished_.store(true, std::memory_order_release);
      return;
    }
    CURL* handle = curl_easy_init();
    if (handle == nullptr) {
      std::fclose(file);
      SetTerminalState(TaskState::kFailed, "无法创建 libcurl 任务。");
      worker_finished_.store(true, std::memory_order_release);
      return;
    }
    const auto initial_cookies = session_->Attach(handle);
    TransferContext context;
    context.task = this;
    context.file = file;
    context.initial_offset = existing_size;
    context.validate_range = use_resume;
    context.expected_etag = use_resume ? resume_etag : "";
    CurlDiagnosticBuffer diagnostics;
    AttachCurlDiagnostics(handle, &diagnostics);
    curl_slist* headers = nullptr;
    if (!AddHeaders(handle, options_, options_.url, &headers)) {
      curl_slist_free_all(headers);
      curl_easy_cleanup(handle);
      std::fclose(file);
      SetTerminalState(TaskState::kFailed, "无法创建下载请求头。");
      worker_finished_.store(true, std::memory_order_release);
      return;
    }
    if (use_resume) {
      const std::string if_range = "If-Range: " + resume_etag;
      curl_slist* appended = curl_slist_append(headers, if_range.c_str());
      if (appended == nullptr) {
        curl_slist_free_all(headers);
        curl_easy_cleanup(handle);
        std::fclose(file);
        SetTerminalState(TaskState::kFailed, "无法创建续传验证请求头。");
        worker_finished_.store(true, std::memory_order_release);
        return;
      }
      headers = appended;
    }
    curl_easy_setopt(handle, CURLOPT_URL, options_.url.c_str());
    // This is also the compatibility transport after an ArkWeb HTTP/2 interruption.
    // Keep one HTTP/1.1 stream instead of renegotiating the failing h2 path.
    curl_easy_setopt(handle, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_1);
    ApplyDownloadProxy(handle, options_, options_.url);
    curl_easy_setopt(handle, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(handle, CURLOPT_MAXREDIRS, 10L);
    curl_easy_setopt(handle, CURLOPT_CONNECTTIMEOUT_MS, 15000L);
    curl_easy_setopt(handle, CURLOPT_LOW_SPEED_LIMIT, 1L);
    curl_easy_setopt(handle, CURLOPT_LOW_SPEED_TIME, 45L);
    curl_easy_setopt(handle, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(handle, CURLOPT_PROTOCOLS_STR, "http,https");
    curl_easy_setopt(handle, CURLOPT_REDIR_PROTOCOLS_STR, "http,https");
    curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, &DownloadTask::WriteCallback);
    curl_easy_setopt(handle, CURLOPT_WRITEDATA, &context);
    curl_easy_setopt(handle, CURLOPT_HEADERFUNCTION, &DownloadTask::HeaderCallback);
    curl_easy_setopt(handle, CURLOPT_HEADERDATA, &context);
    curl_easy_setopt(handle, CURLOPT_XFERINFOFUNCTION, &DownloadTask::ProgressCallback);
    curl_easy_setopt(handle, CURLOPT_XFERINFODATA, &context);
    curl_easy_setopt(handle, CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(handle, CURLOPT_FAILONERROR, 1L);
    curl_easy_setopt(handle, CURLOPT_USERAGENT, "AiraBrowser/DownloadCore");
    if (!options_.ca_path.empty()) {
      curl_easy_setopt(handle, CURLOPT_CAPATH, options_.ca_path.c_str());
    }
    if (headers != nullptr) {
      curl_easy_setopt(handle, CURLOPT_HTTPHEADER, headers);
    }
    if (use_resume) {
      curl_easy_setopt(handle, CURLOPT_RESUME_FROM_LARGE, static_cast<curl_off_t>(existing_size));
    }
    result = curl_easy_perform(handle);
    const bool write_failed = std::ferror(file) != 0;
    if (std::fclose(file) != 0 || write_failed) {
      result = CURLE_WRITE_ERROR;
    }
    curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE, &response_code);
    curl_off_t retry_after = 0;
    curl_easy_getinfo(handle, CURLINFO_RETRY_AFTER, &retry_after);
    char* final_url = nullptr;
    curl_easy_getinfo(handle, CURLINFO_EFFECTIVE_URL, &final_url);
    const std::string effective_url = final_url == nullptr ? options_.url : final_url;
    failure_phase = use_resume ? "http_resume" : "http_download";
    diagnostic_message = DescribeCurlTransfer(
      handle, result, response_code, failure_phase.c_str(), options_, options_.url, diagnostics);
    session_->Capture(handle, initial_cookies);
    curl_slist_free_all(headers);
    curl_easy_cleanup(handle);

    const auto downloaded_size = ExistingFileSize(options_.target_path);
    // A successful curl transfer only proves its Content-Length was received.
    // A 206 may advertise a longer representation in Content-Range: do not
    // publish a truncated suffix as a complete file.
    const bool resume_valid = !use_resume || (response_code == 206 && context.RangeMatches() &&
      expected_effective_url_hash == std::to_string(StableHash(effective_url)) &&
      (result != CURLE_OK || downloaded_size == context.content_range_total));
    const bool complete_unsolicited_range = context.saw_content_range &&
      context.content_range_start == 0 && context.content_range_end == context.content_range_total - 1 &&
      downloaded_size == context.content_range_total;
    const bool invalid_initial_range = !use_resume && response_code == 206 && !complete_unsolicited_range;
    if (invalid_initial_range) {
      result = CURLE_PARTIAL_FILE;
      diagnostic_message += "|invalidContentRange=1";
      RemoveResumeMetadata(options_.target_path);
    }
    const bool interrupted = cancel_requested_.load(std::memory_order_acquire) ||
      pause_requested_.load(std::memory_order_acquire);
    const bool entity_rejected = use_resume &&
      (((response_code >= 200 && response_code < 300) && !resume_valid) ||
       response_code == 416 || result == CURLE_RANGE_ERROR);
    // A pause must not bind an old prefix (or a partially appended new target)
    // to the replacement entity's validator. Missing metadata forces a safe restart.
    if (entity_rejected) RemoveResumeMetadata(options_.target_path);
    const bool resume_rejected = entity_rejected && !interrupted;
    if (resume_rejected && !full_restart_used) {
      RemoveResumeMetadata(options_.target_path);
      full_restart_used = true;
      force_full_restart = true;
      continue;
    }
    if (resume_rejected) result = CURLE_PARTIAL_FILE;
    if (!entity_rejected && !invalid_initial_range && result != CURLE_WRITE_ERROR &&
        (response_code == 200 || (response_code == 206 && resume_valid)) &&
        ExistingFileSize(options_.target_path) > 0) SaveResumeEtag(options_, context.response_etag, effective_url);
    if (result == CURLE_OK && (response_code < 200 || response_code >= 300)) {
      result = CURLE_HTTP_RETURNED_ERROR;
    }
    if (result == CURLE_OK && !resume_rejected) break;
    ++failed_attempts;
    const bool retryable_status = response_code == 408 || response_code == 429 || response_code == 500 ||
      response_code == 502 || response_code == 503 || response_code == 504;
    const bool retryable = !interrupted && !invalid_initial_range && !resume_rejected &&
      (response_code >= 400 ? retryable_status : IsRetryableHlsTransferFailure(result, response_code));
    diagnostic_message += "|attempt=" + std::to_string(failed_attempts) +
      "|maxAttempts=" + std::to_string(max_attempts) + "|retryAfterSeconds=" + std::to_string(retry_after);
    // Never shorten a server's backoff. Long waits remain explicit failures for
    // the user to retry, rather than tying up a native worker indefinitely.
    if (!retryable || failed_attempts >= max_attempts || retry_after > 30) break;
    const int delay_ms = std::max(HlsRetryDelayMsAfterAttempt(static_cast<int>(failed_attempts)),
      static_cast<int>(std::max<curl_off_t>(0, retry_after)) * 1000);
    if (WaitForTransferRetry(this, delay_ms)) continue;
    break;
  }

  if (cancel_requested_.load(std::memory_order_acquire)) {
    SetTerminalState(TaskState::kCanceled, "下载已取消。");
  } else if (pause_requested_.load(std::memory_order_acquire) || result == CURLE_ABORTED_BY_CALLBACK) {
    SetTerminalState(TaskState::kPaused, "");
  } else if (result != CURLE_OK || response_code < 200 || response_code >= 300) {
    SetTerminalState(TaskState::kFailed, CurlFailureMessage(result, response_code),
                     static_cast<std::int32_t>(result), diagnostic_message, failure_phase);
  } else {
    std::lock_guard<std::mutex> lock(mutex_);
    state_ = TaskState::kCompleted;
    received_bytes_ = std::max(received_bytes_, ExistingFileSize(options_.target_path));
    total_bytes_ = received_bytes_;
    speed_bytes_per_second_ = 0;
    error_code_ = 0;
    error_message_.clear();
    diagnostic_message_ = diagnostic_message;
    failure_phase_ = failure_phase;
  }
  if (cancel_requested_.load(std::memory_order_acquire) || Snapshot().state == TaskState::kCompleted) {
    RemoveResumeMetadata(options_.target_path);
  }
  worker_finished_.store(true, std::memory_order_release);
}

void DownloadTask::RunHls() {
  const std::filesystem::path target(options_.target_path);
  std::error_code directory_error;
  if (target.has_parent_path()) {
    std::filesystem::create_directories(target.parent_path(), directory_error);
    if (directory_error) {
      SetTerminalState(TaskState::kFailed, "无法创建下载目标目录。");
      worker_finished_.store(true, std::memory_order_release);
      return;
    }
  }

  std::string playlist;
  std::string effective_url;
  std::string error;
  std::int32_t error_code = 0;
  std::string diagnostic_message;
  std::string failure_phase;
  if (!FetchText(options_, options_.url, &playlist, this, &error, &error_code,
                 &diagnostic_message, &failure_phase, "hls_manifest", session_.get(), &effective_url)) {
    if (!FinishIfInterrupted()) {
      SetTerminalState(TaskState::kFailed, error, error_code, diagnostic_message, failure_phase);
    }
    worker_finished_.store(true, std::memory_order_release);
    return;
  }
  HlsPlan plan;
  if (!ParseHlsPlaylist(options_, playlist, effective_url, this, session_.get(), &plan, &error, &error_code,
                        &diagnostic_message, &failure_phase)) {
    if (!FinishIfInterrupted()) {
      SetTerminalState(TaskState::kFailed, error, error_code, diagnostic_message,
                       failure_phase.empty() ? "hls_parse" : failure_phase);
    }
    worker_finished_.store(true, std::memory_order_release);
    return;
  }
  if (plan.resources.empty()) {
    SetTerminalState(TaskState::kFailed, "HLS 清单中没有可下载的视频分片。");
    worker_finished_.store(true, std::memory_order_release);
    return;
  }
  {
    std::lock_guard<std::mutex> lock(mutex_);
    file_extension_ = plan.fragmented_mp4 ? ".mp4" : ".ts";
  }

  const std::string checkpoint_path = options_.target_path + ".aira-hls.checkpoint";
  const std::string part_prefix = options_.target_path + ".aira-hls.part.";
  std::unordered_set<std::size_t> completed;
  bool checkpoint_matches = false;
  {
    std::ifstream checkpoint(checkpoint_path);
    std::string line;
    if (checkpoint && std::getline(checkpoint, line)) {
      try {
        const std::uint64_t checkpoint_hash = std::stoull(Trim(line));
        if (checkpoint_hash == plan.hash) {
          checkpoint_matches = true;
          while (std::getline(checkpoint, line)) {
            try {
              const std::size_t index = static_cast<std::size_t>(std::stoull(Trim(line)));
              if (index < plan.resources.size() && ExistingFileSize(part_prefix + std::to_string(index)) > 0) {
                completed.insert(index);
              }
            } catch (...) {
              // Ignore malformed checkpoint entries and redownload that segment.
            }
          }
        }
      } catch (...) {
        // A malformed or stale checkpoint is discarded below.
      }
    }
  }
  if (!checkpoint_matches) {
    CleanupHlsArtifacts(options_.target_path);
    completed.clear();
  }

  auto write_checkpoint = [&]() {
    const std::string temporary = checkpoint_path + ".tmp";
    std::ofstream checkpoint(temporary, std::ios::trunc);
    if (!checkpoint) {
      return;
    }
    checkpoint << plan.hash << '\n';
    for (const std::size_t index : completed) {
      checkpoint << index << '\n';
    }
    checkpoint.close();
    std::error_code rename_error;
    std::filesystem::rename(temporary, checkpoint_path, rename_error);
    if (rename_error) {
      std::filesystem::remove(temporary);
    }
  };
  write_checkpoint();

  std::atomic<std::int64_t> received{0};
  for (const std::size_t index : completed) {
    received.fetch_add(ExistingFileSize(part_prefix + std::to_string(index)), std::memory_order_relaxed);
  }
  auto sync_received = [&]() {
    std::lock_guard<std::mutex> lock(mutex_);
    received_bytes_ = received.load(std::memory_order_relaxed);
    total_bytes_ = 0;
  };
  {
    std::lock_guard<std::mutex> lock(mutex_);
    received_bytes_ = received.load(std::memory_order_relaxed);
    total_bytes_ = 0;
    speed_sample_bytes_ = received_bytes_;
    speed_sample_time_ms_ = 0;
    hls_progress_ = std::make_unique<HlsProgressTracker>(plan.resources);
    for (const std::size_t index : completed) {
      hls_progress_->Complete(index, ExistingFileSize(part_prefix + std::to_string(index)));
    }
  }
  std::atomic<std::size_t> next_index{0};
  std::atomic<bool> failed{false};
  std::mutex checkpoint_mutex;
  std::mutex error_mutex;
  std::string worker_error;
  std::int32_t worker_error_code = 0;
  std::string worker_diagnostic;
  std::string worker_failure_phase;
  const std::size_t worker_count = std::min(options_.hls_segment_concurrency, plan.resources.size());
  auto download_segment = [&](std::size_t index) {
    const std::string part_path = part_prefix + std::to_string(index);
    {
      std::lock_guard<std::mutex> lock(checkpoint_mutex);
      if (completed.find(index) != completed.end()) {
        return;
      }
    }
    const HlsResource& resource = plan.resources[index];
    const std::string segment_phase = (resource.initialization ? "hls_map_" : "hls_segment_") + std::to_string(index);
    std::string segment_error;
    std::int32_t segment_error_code = 0;
    std::string segment_diagnostic;
    bool transferred = TransferHlsFile(resource, index, part_path, segment_phase, &received,
                                       &segment_error, &segment_error_code, &segment_diagnostic);
    if (transferred && resource.key_index >= 0) {
      const auto encrypted_size = ExistingFileSize(part_path);
      transferred = DecryptHlsFile(part_path, plan.keys[resource.key_index], resource.iv,
        [&]() { return IsTaskTransferInterrupted(this); }, &segment_error);
      if (transferred) {
        received.fetch_add(ExistingFileSize(part_path) - encrypted_size, std::memory_order_relaxed);
      } else {
        received.fetch_sub(encrypted_size, std::memory_order_relaxed);
        std::error_code remove_error;
        std::filesystem::remove(part_path, remove_error);
      }
    }
    if (!transferred) {
      {
        std::lock_guard<std::mutex> lock(mutex_);
        hls_progress_->Update(index, 0, 0);
      }
      if (cancel_requested_.load(std::memory_order_acquire) || pause_requested_.load(std::memory_order_acquire)) {
        return;
      }
      std::lock_guard<std::mutex> lock(error_mutex);
      if (worker_error.empty()) {
        worker_error = segment_error.empty() ? "HLS 视频分片下载失败。" : segment_error;
        worker_error_code = segment_error_code;
        worker_diagnostic = segment_diagnostic;
        worker_failure_phase = segment_phase;
      }
      failed.store(true, std::memory_order_release);
      return;
    }
    {
      std::lock_guard<std::mutex> lock(checkpoint_mutex);
      completed.insert(index);
      write_checkpoint();
    }
    {
      std::lock_guard<std::mutex> lock(mutex_);
      received_bytes_ = received.load(std::memory_order_relaxed);
      total_bytes_ = 0;
      hls_progress_->Complete(index, ExistingFileSize(part_path));
    }
  };

  std::vector<std::thread> workers;
  workers.reserve(worker_count);
  for (std::size_t worker = 0; worker < worker_count; ++worker) {
    workers.emplace_back([&]() {
      while (!failed.load(std::memory_order_acquire) && !cancel_requested_.load(std::memory_order_acquire) &&
             !pause_requested_.load(std::memory_order_acquire)) {
        const std::size_t index = next_index.fetch_add(1, std::memory_order_relaxed);
        if (index >= plan.resources.size()) {
          return;
        }
        download_segment(index);
      }
    });
  }
  for (auto& worker : workers) {
    worker.join();
  }
  sync_received();
  if (cancel_requested_.load(std::memory_order_acquire)) {
    if (!shutdown_requested_.load(std::memory_order_acquire)) {
      CleanupHlsArtifacts(options_.target_path);
    }
    SetTerminalState(TaskState::kCanceled, "下载已取消。");
    worker_finished_.store(true, std::memory_order_release);
    return;
  }
  if (pause_requested_.load(std::memory_order_acquire)) {
    SetTerminalState(TaskState::kPaused, "");
    worker_finished_.store(true, std::memory_order_release);
    return;
  }
  if (failed.load(std::memory_order_acquire) || completed.size() != plan.resources.size()) {
    SetTerminalState(TaskState::kFailed, worker_error.empty() ? "HLS 视频分片下载失败。" : worker_error,
                     worker_error_code, worker_diagnostic,
                     worker_failure_phase.empty() ? "hls_segment" : worker_failure_phase);
    worker_finished_.store(true, std::memory_order_release);
    return;
  }

  FILE* output = std::fopen(options_.target_path.c_str(), "wb");
  if (output == nullptr) {
    SetTerminalState(TaskState::kFailed, "无法打开 HLS 合并目标文件。");
    worker_finished_.store(true, std::memory_order_release);
    return;
  }
  auto append_file = [&](const std::string& path) -> bool {
    std::ifstream input(path, std::ios::binary);
    if (!input) {
      return false;
    }
    char buffer[64 * 1024];
    while (input.read(buffer, sizeof(buffer)) || input.gcount() > 0) {
      if (cancel_requested_.load(std::memory_order_acquire) ||
          pause_requested_.load(std::memory_order_acquire)) {
        return false;
      }
      const std::streamsize count = input.gcount();
      if (std::fwrite(buffer, 1, static_cast<std::size_t>(count), output) != static_cast<std::size_t>(count)) {
        return false;
      }
    }
    return input.eof();
  };
  bool merge_ok = true;
  for (std::size_t index = 0; merge_ok && index < plan.resources.size(); ++index) {
    merge_ok = append_file(part_prefix + std::to_string(index));
  }
  if (std::fclose(output) != 0) merge_ok = false;
  if (cancel_requested_.load(std::memory_order_acquire)) {
    std::error_code remove_error;
    std::filesystem::remove(options_.target_path, remove_error);
    if (!shutdown_requested_.load(std::memory_order_acquire)) {
      CleanupHlsArtifacts(options_.target_path);
    }
    SetTerminalState(TaskState::kCanceled, "下载已取消。");
    worker_finished_.store(true, std::memory_order_release);
    return;
  }
  if (pause_requested_.load(std::memory_order_acquire)) {
    std::error_code remove_error;
    std::filesystem::remove(options_.target_path, remove_error);
    SetTerminalState(TaskState::kPaused, "");
    worker_finished_.store(true, std::memory_order_release);
    return;
  }
  if (!merge_ok) {
    SetTerminalState(TaskState::kFailed, "HLS 视频合并失败。");
    worker_finished_.store(true, std::memory_order_release);
    return;
  }
  const std::int64_t final_size = ExistingFileSize(options_.target_path);
  {
    std::lock_guard<std::mutex> lock(mutex_);
    state_ = TaskState::kCompleted;
    received_bytes_ = final_size;
    total_bytes_ = final_size;
    speed_bytes_per_second_ = 0;
    error_code_ = 0;
    error_message_.clear();
    diagnostic_message_.clear();
    failure_phase_.clear();
  }
  std::error_code cleanup_error;
  std::filesystem::remove(checkpoint_path, cleanup_error);
  std::filesystem::remove(options_.target_path + ".aira-hls.map", cleanup_error);
  for (std::size_t index = 0; index < plan.resources.size(); ++index) {
    std::filesystem::remove(part_prefix + std::to_string(index), cleanup_error);
  }
  worker_finished_.store(true, std::memory_order_release);
}

void DownloadTask::Run() {
  if (options_.hls) {
    RunHls();
  } else {
    RunHttp();
  }
}

void DownloadTask::Shutdown() {
  std::thread worker;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    shutdown_requested_.store(true, std::memory_order_release);
    if (state_ == TaskState::kCreated || state_ == TaskState::kRunning ||
        state_ == TaskState::kPausing || state_ == TaskState::kPaused) {
      cancel_requested_.store(true, std::memory_order_release);
      state_ = TaskState::kCanceled;
    }
    if (worker_.joinable()) {
      worker = std::move(worker_);
    }
  }
  if (worker.joinable()) {
    worker.join();
  }
}

DownloadManager::~DownloadManager() {
  Shutdown();
}

std::int64_t DownloadManager::Create(TaskOptions options) {
  std::lock_guard<std::mutex> lock(mutex_);
  const std::int64_t handle = next_handle_++;
  tasks_.emplace(handle, std::make_shared<DownloadTask>(std::move(options)));
  return handle;
}

std::shared_ptr<DownloadTask> DownloadManager::Find(std::int64_t handle) const {
  std::lock_guard<std::mutex> lock(mutex_);
  const auto found = tasks_.find(handle);
  return found == tasks_.end() ? nullptr : found->second;
}

bool DownloadManager::Release(std::int64_t handle) {
  std::shared_ptr<DownloadTask> task;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto found = tasks_.find(handle);
    if (found == tasks_.end()) {
      return false;
    }
    task = found->second;
    tasks_.erase(found);
  }
  task->Shutdown();
  return true;
}

void DownloadManager::Shutdown() {
  std::vector<std::shared_ptr<DownloadTask>> tasks;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    for (const auto& entry : tasks_) {
      tasks.push_back(entry.second);
    }
    tasks_.clear();
  }
  for (const auto& task : tasks) {
    task->Shutdown();
  }
}

const char* TaskStateName(TaskState state) {
  switch (state) {
    case TaskState::kCreated: return "created";
    case TaskState::kRunning: return "running";
    case TaskState::kPausing: return "pausing";
    case TaskState::kPaused: return "paused";
    case TaskState::kCompleted: return "completed";
    case TaskState::kFailed: return "failed";
    case TaskState::kCanceled: return "canceled";
  }
  return "failed";
}

std::string HlsRetryPolicySummary() {
  std::ostringstream output;
  output << "attempts=" << kHlsTransferMaxAttempts << " delaysMs=";
  for (int attempt = 1; attempt < kHlsTransferMaxAttempts; ++attempt) {
    if (attempt > 1) {
      output << ',';
    }
    output << HlsRetryDelayMsAfterAttempt(attempt);
  }
  output << " capMs=" << kHlsRetryMaxDelayMs;
  return output.str();
}

}  // namespace aira::download
