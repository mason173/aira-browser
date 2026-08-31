#include "download_core.h"

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

std::string DescribeCurlTransfer(CURL* handle, CURLcode result, long response_code,
                                 const char* phase, const std::string& ca_path,
                                 const CurlDiagnosticBuffer& diagnostics) {
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
  std::ostringstream output;
  output << "phase=" << (phase == nullptr ? "unknown" : phase)
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
  if (response_code >= 400) {
    return "下载服务器返回 HTTP " + std::to_string(response_code) + "。";
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

bool WaitForHlsRetry(DownloadTask* task, int failed_attempt) {
  const int delay_ms = HlsRetryDelayMsAfterAttempt(failed_attempt);
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

std::string ResolveUrl(const std::string& base, const std::string& reference) {
  const std::string ref = Trim(reference);
  if (ref.empty()) {
    return {};
  }
  CURLU* url = curl_url();
  if (url == nullptr) {
    return {};
  }
  char* resolved = nullptr;
  const bool ok = curl_url_set(url, CURLUPART_URL, base.c_str(), 0) == CURLUE_OK &&
    curl_url_set(url, CURLUPART_URL, ref.c_str(), 0) == CURLUE_OK &&
    curl_url_get(url, CURLUPART_URL, &resolved, 0) == CURLUE_OK && resolved != nullptr;
  const std::string result = ok ? resolved : "";
  curl_free(resolved);
  curl_url_cleanup(url);
  return result;
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

bool AddHeaders(CURL* handle, const std::vector<std::string>& values, curl_slist** output) {
  for (const std::string& header : values) {
    if (!header.empty()) {
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
               const char* phase) {
  for (int attempt = 1; attempt <= kHlsTransferMaxAttempts; ++attempt) {
    CURL* handle = curl_easy_init();
    if (handle == nullptr) {
      *error = "无法创建 libcurl 清单任务。";
      *failure_phase = phase;
      return false;
    }
    MemoryContext context{{}, task};
    CurlDiagnosticBuffer diagnostics;
    AttachCurlDiagnostics(handle, &diagnostics);
    curl_slist* header_list = nullptr;
    curl_easy_setopt(handle, CURLOPT_URL, url.c_str());
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
    if (!AddHeaders(handle, options.headers, &header_list)) {
      curl_slist_free_all(header_list);
      curl_easy_cleanup(handle);
      *error = "无法创建下载请求头。";
      *failure_phase = phase;
      return false;
    }
    const CURLcode result = curl_easy_perform(handle);
    long response_code = 0;
    curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE, &response_code);
    const bool retryable = IsRetryableHlsTransferFailure(result, response_code);
    const std::string transfer_diagnostic = AppendRetryDiagnostic(
      DescribeCurlTransfer(handle, result, response_code, phase, options.ca_path, diagnostics),
      attempt, retryable);
    curl_slist_free_all(header_list);
    curl_easy_cleanup(handle);
    if (result == CURLE_OK && response_code >= 200 && response_code < 400) {
      *output = std::move(context.data);
      return true;
    }
    *error = CurlFailureMessage(result, response_code);
    *error_code = static_cast<std::int32_t>(result);
    *diagnostic_message = transfer_diagnostic;
    *failure_phase = phase;
    if (!retryable || attempt >= kHlsTransferMaxAttempts || !WaitForHlsRetry(task, attempt)) {
      return false;
    }
  }
  return false;
}

struct HlsPlan {
  std::string map_url;
  std::vector<std::string> segment_urls;
  std::uint64_t hash = 0;
};

bool ParseHlsMedia(const std::string& playlist, const std::string& base_url, HlsPlan* plan,
                   std::vector<std::pair<long, std::string>>* variants, std::string* error) {
  std::istringstream stream(playlist);
  std::string line;
  bool expect_variant_uri = false;
  long variant_bandwidth = 0;
  bool has_segment = false;
  bool has_end_list = false;
  while (std::getline(stream, line)) {
    const std::string value = Trim(line);
    if (value.empty()) {
      continue;
    }
    if (value.rfind("#EXT-X-STREAM-INF:", 0) == 0) {
      expect_variant_uri = true;
      variant_bandwidth = 0;
      const std::size_t bandwidth = value.find("BANDWIDTH=");
      if (bandwidth != std::string::npos) {
        try {
          variant_bandwidth = std::stol(value.substr(bandwidth + 10));
        } catch (...) {
          variant_bandwidth = 0;
        }
      }
      continue;
    }
    if (value.front() == '#') {
      if (value == "#EXT-X-ENDLIST") {
        has_end_list = true;
      }
      if (value.rfind("#EXT-X-KEY:", 0) == 0 && value.find("METHOD=NONE") == std::string::npos) {
        *error = "当前 HLS 视频使用了不支持的加密方式。";
        return false;
      }
      if (value.rfind("#EXT-X-BYTERANGE:", 0) == 0) {
        *error = "当前 HLS 视频使用了暂不支持的字节范围分片。";
        return false;
      }
      if (value.rfind("#EXT-X-MAP:", 0) == 0) {
        if (value.find("BYTERANGE=") != std::string::npos) {
          *error = "当前 HLS 视频使用了暂不支持的初始化分片字节范围。";
          return false;
        }
        const std::size_t uri_start = value.find("URI=\"");
        if (uri_start != std::string::npos) {
          const std::size_t uri_end = value.find('"', uri_start + 5);
          if (uri_end != std::string::npos) {
            plan->map_url = ResolveUrl(base_url, value.substr(uri_start + 5, uri_end - uri_start - 5));
          }
        }
      }
      continue;
    }
    const std::string resolved = ResolveUrl(base_url, value);
    if (resolved.empty()) {
      continue;
    }
    if (expect_variant_uri && variants != nullptr) {
      variants->emplace_back(variant_bandwidth, resolved);
      expect_variant_uri = false;
      continue;
    }
    plan->segment_urls.push_back(resolved);
    has_segment = true;
  }
  if (variants != nullptr && !variants->empty()) {
    return true;
  }
  if (!has_segment) {
    *error = "HLS 清单中没有可下载的视频分片。";
    return false;
  }
  if (!has_end_list) {
    *error = "当前版本暂不支持直播 HLS 下载。";
    return false;
  }
  plan->hash = StableHash(playlist);
  return true;
}

bool ParseHlsPlaylist(const TaskOptions& options, const std::string& playlist,
                      DownloadTask* task, HlsPlan* plan, std::string* error,
                      std::int32_t* error_code, std::string* diagnostic_message,
                      std::string* failure_phase) {
  std::vector<std::pair<long, std::string>> variants;
  HlsPlan media;
  if (!ParseHlsMedia(playlist, options.url, &media, &variants, error)) {
    return false;
  }
  if (!variants.empty()) {
    const auto selected = *std::max_element(variants.begin(), variants.end(),
      [](const auto& left, const auto& right) { return left.first < right.first; });
    std::string variant_playlist;
    if (!FetchText(options, selected.second, &variant_playlist, task, error, error_code,
                   diagnostic_message, failure_phase, "hls_variant_manifest") ||
        !ParseHlsMedia(variant_playlist, selected.second, &media, nullptr, error)) {
      if (failure_phase->empty()) {
        *failure_phase = "hls_variant_parse";
      }
      return false;
    }
    media.hash = StableHash(variant_playlist);
  }
  *plan = std::move(media);
  return true;
}

}  // namespace

void CleanupHlsTaskArtifacts(const std::string& target_path) {
  CleanupHlsArtifacts(target_path);
}

struct DownloadTask::TransferContext {
  DownloadTask* task = nullptr;
  FILE* file = nullptr;
  std::int64_t initial_offset = 0;
  std::atomic<std::int64_t>* aggregate_received = nullptr;
  std::int64_t last_download_now = 0;
  bool track_progress = true;
  bool saw_content_range = false;
  std::int64_t content_range_start = -1;
};

DownloadTask::DownloadTask(TaskOptions options) : options_(std::move(options)) {
  EnsureCurlInitialized();
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
    file_extension_
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
  if (context->initial_offset > 0 &&
      (!context->saw_content_range || context->content_range_start != context->initial_offset)) {
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
  constexpr char kContentRange[] = "content-range:";
  std::string lower = line;
  std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char value) {
    return static_cast<char>(std::tolower(value));
  });
  if (lower.rfind("http/", 0) == 0) {
    context->saw_content_range = false;
    context->content_range_start = -1;
  }
  if (lower.rfind(kContentRange, 0) == 0) {
    const std::size_t first = lower.find_first_of("0123456789", sizeof(kContentRange) - 1);
    if (first != std::string::npos) {
      const std::size_t dash = lower.find('-', first);
      if (dash != std::string::npos) {
        try {
          context->content_range_start = std::stoll(lower.substr(first, dash - first));
          context->saw_content_range = true;
        } catch (...) {
          context->content_range_start = -1;
          context->saw_content_range = false;
        }
      }
    }
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

bool DownloadTask::TransferHlsFile(const std::string& url, const std::string& path, const std::string& phase,
                                   std::atomic<std::int64_t>* aggregate_received, std::string* error,
                                   std::int32_t* error_code, std::string* diagnostic_message) {
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
    TransferContext context{this, file, 0, aggregate_received, 0, true, false, -1};
    CurlDiagnosticBuffer diagnostics;
    AttachCurlDiagnostics(handle, &diagnostics);
    curl_slist* headers = nullptr;
    if (!AddHeaders(handle, options_.headers, &headers)) {
      curl_slist_free_all(headers);
      curl_easy_cleanup(handle);
      std::fclose(file);
      std::error_code remove_error;
      std::filesystem::remove(path, remove_error);
      *error = "无法创建下载请求头。";
      return false;
    }
    curl_easy_setopt(handle, CURLOPT_URL, url.c_str());
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

    const CURLcode result = curl_easy_perform(handle);
    long response_code = 0;
    curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE, &response_code);
    const bool retryable = IsRetryableHlsTransferFailure(result, response_code);
    const std::string transfer_diagnostic = AppendRetryDiagnostic(
      DescribeCurlTransfer(handle, result, response_code, phase.c_str(), options_.ca_path, diagnostics),
      attempt, retryable);
    curl_slist_free_all(headers);
    curl_easy_cleanup(handle);
    std::fclose(file);

    const bool interrupted = cancel_requested_.load(std::memory_order_acquire) ||
      pause_requested_.load(std::memory_order_acquire);
    const std::int64_t file_size = ExistingFileSize(path);
    const bool succeeded = result == CURLE_OK && response_code >= 200 && response_code < 300 && file_size > 0;
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
    }
    if (interrupted) {
      return false;
    }

    *error = result == CURLE_OK && file_size <= 0 ?
      "下载服务器返回了空分片。" : CurlFailureMessage(result, response_code);
    *error_code = static_cast<std::int32_t>(result);
    *diagnostic_message = transfer_diagnostic;
    if (!retryable || attempt >= kHlsTransferMaxAttempts || !WaitForHlsRetry(this, attempt)) {
      return false;
    }
  }
  return false;
}

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

  for (int attempt = 0; attempt < 2; ++attempt) {
    const bool use_resume = existing_size > 0 && attempt == 0;
    if (!use_resume && existing_size > 0) {
      std::error_code truncate_error;
      std::filesystem::resize_file(options_.target_path, 0, truncate_error);
      if (truncate_error) {
        SetTerminalState(TaskState::kFailed, "无法重置下载临时文件。");
        worker_finished_.store(true, std::memory_order_release);
        return;
      }
      existing_size = 0;
    }
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
    TransferContext context{this, file, existing_size, nullptr, 0, true, false, -1};
    CurlDiagnosticBuffer diagnostics;
    AttachCurlDiagnostics(handle, &diagnostics);
    curl_slist* headers = nullptr;
    for (const std::string& header : options_.headers) {
      if (!header.empty()) {
        headers = curl_slist_append(headers, header.c_str());
      }
    }
    curl_easy_setopt(handle, CURLOPT_URL, options_.url.c_str());
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
    curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE, &response_code);
    failure_phase = use_resume ? "http_resume" : "http_download";
    diagnostic_message = DescribeCurlTransfer(
      handle, result, response_code, failure_phase.c_str(), options_.ca_path, diagnostics);
    const bool resume_valid = !use_resume || (response_code == 206 && context.saw_content_range &&
      context.content_range_start == context.initial_offset);
    curl_slist_free_all(headers);
    curl_easy_cleanup(handle);
    std::fclose(file);

    const bool interrupted = cancel_requested_.load(std::memory_order_acquire) ||
      pause_requested_.load(std::memory_order_acquire);
    const bool resume_rejected = use_resume && !interrupted &&
      (((response_code >= 200 && response_code < 300) && !resume_valid) ||
       response_code == 416 || result == CURLE_RANGE_ERROR);
    if (resume_rejected) {
      continue;
    }
    break;
  }

  if (cancel_requested_.load(std::memory_order_acquire)) {
    SetTerminalState(TaskState::kCanceled, "下载已取消。");
  } else if (pause_requested_.load(std::memory_order_acquire) || result == CURLE_ABORTED_BY_CALLBACK) {
    SetTerminalState(TaskState::kPaused, "");
  } else if (result != CURLE_OK || response_code < 200 || response_code >= 400) {
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
    diagnostic_message_.clear();
    failure_phase_.clear();
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
  std::string error;
  std::int32_t error_code = 0;
  std::string diagnostic_message;
  std::string failure_phase;
  if (!FetchText(options_, options_.url, &playlist, this, &error, &error_code,
                 &diagnostic_message, &failure_phase, "hls_manifest")) {
    if (!FinishIfInterrupted()) {
      SetTerminalState(TaskState::kFailed, error, error_code, diagnostic_message, failure_phase);
    }
    worker_finished_.store(true, std::memory_order_release);
    return;
  }
  HlsPlan plan;
  if (!ParseHlsPlaylist(options_, playlist, this, &plan, &error, &error_code,
                        &diagnostic_message, &failure_phase)) {
    if (!FinishIfInterrupted()) {
      SetTerminalState(TaskState::kFailed, error, error_code, diagnostic_message,
                       failure_phase.empty() ? "hls_parse" : failure_phase);
    }
    worker_finished_.store(true, std::memory_order_release);
    return;
  }
  if (plan.segment_urls.empty()) {
    SetTerminalState(TaskState::kFailed, "HLS 清单中没有可下载的视频分片。");
    worker_finished_.store(true, std::memory_order_release);
    return;
  }
  {
    std::lock_guard<std::mutex> lock(mutex_);
    file_extension_ = plan.map_url.empty() ? ".ts" : ".mp4";
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
              if (index < plan.segment_urls.size() && ExistingFileSize(part_prefix + std::to_string(index)) > 0) {
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
  }
  if (!plan.map_url.empty()) {
    const std::string map_path = options_.target_path + ".aira-hls.map";
    if (ExistingFileSize(map_path) <= 0) {
      std::string map_error;
      std::int32_t map_error_code = 0;
      std::string map_diagnostic;
      if (!TransferHlsFile(plan.map_url, map_path, "hls_map", &received,
                           &map_error, &map_error_code, &map_diagnostic)) {
        if (!FinishIfInterrupted()) {
          SetTerminalState(TaskState::kFailed,
                           map_error.empty() ? "HLS 初始化分片下载失败。" : map_error,
                           map_error_code, map_diagnostic, "hls_map");
        }
        worker_finished_.store(true, std::memory_order_release);
        return;
      }
    } else {
      received.fetch_add(ExistingFileSize(map_path), std::memory_order_relaxed);
    }
    sync_received();
  }

  std::atomic<std::size_t> next_index{0};
  std::atomic<bool> failed{false};
  std::mutex checkpoint_mutex;
  std::mutex error_mutex;
  std::string worker_error;
  std::int32_t worker_error_code = 0;
  std::string worker_diagnostic;
  std::string worker_failure_phase;
  const std::size_t worker_count = std::min(options_.hls_segment_concurrency, plan.segment_urls.size());
  auto download_segment = [&](std::size_t index) {
    const std::string part_path = part_prefix + std::to_string(index);
    {
      std::lock_guard<std::mutex> lock(checkpoint_mutex);
      if (completed.find(index) != completed.end()) {
        return;
      }
    }
    const std::string segment_phase = "hls_segment_" + std::to_string(index);
    std::string segment_error;
    std::int32_t segment_error_code = 0;
    std::string segment_diagnostic;
    if (!TransferHlsFile(plan.segment_urls[index], part_path, segment_phase, &received,
                         &segment_error, &segment_error_code, &segment_diagnostic)) {
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
    }
  };

  std::vector<std::thread> workers;
  workers.reserve(worker_count);
  for (std::size_t worker = 0; worker < worker_count; ++worker) {
    workers.emplace_back([&]() {
      while (!failed.load(std::memory_order_acquire) && !cancel_requested_.load(std::memory_order_acquire) &&
             !pause_requested_.load(std::memory_order_acquire)) {
        const std::size_t index = next_index.fetch_add(1, std::memory_order_relaxed);
        if (index >= plan.segment_urls.size()) {
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
  if (failed.load(std::memory_order_acquire) || completed.size() != plan.segment_urls.size()) {
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
  bool merge_ok = plan.map_url.empty() || append_file(options_.target_path + ".aira-hls.map");
  for (std::size_t index = 0; merge_ok && index < plan.segment_urls.size(); ++index) {
    merge_ok = append_file(part_prefix + std::to_string(index));
  }
  std::fclose(output);
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
  for (std::size_t index = 0; index < plan.segment_urls.size(); ++index) {
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
