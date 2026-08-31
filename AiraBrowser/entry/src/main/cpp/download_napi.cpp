#include "download_core.h"

#include <curl/curl.h>
#include <node_api.h>

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace {

using aira::download::DownloadManager;
using aira::download::TaskOptions;
using aira::download::TaskSnapshot;

constexpr size_t kMaxUrlBytes = 64 * 1024;
constexpr size_t kMaxPathBytes = 4096;
constexpr size_t kMaxHeaderBytes = 16 * 1024;

DownloadManager g_manager;

napi_value Undefined(napi_env env) {
  napi_value value = nullptr;
  napi_get_undefined(env, &value);
  return value;
}

bool ReadString(napi_env env, napi_value value, size_t maximum, bool allow_empty, std::string* output) {
  size_t length = 0;
  if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok ||
      length > maximum || (!allow_empty && length == 0)) {
    napi_throw_type_error(env, nullptr, "Invalid native download string argument.");
    return false;
  }
  std::string result(length + 1, '\0');
  size_t written = 0;
  if (napi_get_value_string_utf8(env, value, result.data(), result.size(), &written) != napi_ok ||
      written != length) {
    napi_throw_type_error(env, nullptr, "Failed to read native download string argument.");
    return false;
  }
  result.resize(length);
  *output = std::move(result);
  return true;
}

bool ReadHandle(napi_env env, napi_value value, std::int64_t* output) {
  std::int64_t handle = 0;
  if (napi_get_value_int64(env, value, &handle) != napi_ok || handle <= 0) {
    napi_throw_type_error(env, nullptr, "Invalid native download handle.");
    return false;
  }
  *output = handle;
  return true;
}

bool ReadHlsSegmentConcurrency(napi_env env, napi_value value, std::size_t* output) {
  std::int32_t concurrency = 0;
  if (napi_get_value_int32(env, value, &concurrency) != napi_ok ||
      (concurrency != 4 && concurrency != 8 && concurrency != 16)) {
    napi_throw_range_error(env, nullptr, "Native HLS segment concurrency must be 4, 8 or 16.");
    return false;
  }
  *output = static_cast<std::size_t>(concurrency);
  return true;
}

bool ReadHeaders(napi_env env, napi_value value, std::vector<std::string>* output) {
  bool is_array = false;
  if (napi_is_array(env, value, &is_array) != napi_ok || !is_array) {
    napi_throw_type_error(env, nullptr, "Native download headers must be an array.");
    return false;
  }
  uint32_t length = 0;
  if (napi_get_array_length(env, value, &length) != napi_ok || length > 128) {
    napi_throw_range_error(env, nullptr, "Native download header count is too large.");
    return false;
  }
  for (uint32_t index = 0; index < length; ++index) {
    napi_value item = nullptr;
    if (napi_get_element(env, value, index, &item) != napi_ok) {
      return false;
    }
    std::string header;
    if (!ReadString(env, item, kMaxHeaderBytes, false, &header)) {
      return false;
    }
    output->push_back(std::move(header));
  }
  return true;
}

napi_value CreateTask(napi_env env, napi_callback_info info) {
  size_t argc = 6;
  napi_value argv[6] = {nullptr, nullptr, nullptr, nullptr, nullptr, nullptr};
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc != 6) {
    napi_throw_type_error(
      env,
      nullptr,
      "createTask expects url, targetPath, headers, hls flag, CA path and HLS segment concurrency."
    );
    return Undefined(env);
  }
  TaskOptions options;
  if (!ReadString(env, argv[0], kMaxUrlBytes, false, &options.url) ||
      !ReadString(env, argv[1], kMaxPathBytes, false, &options.target_path) ||
      !ReadHeaders(env, argv[2], &options.headers) ||
      !ReadString(env, argv[4], kMaxPathBytes, true, &options.ca_path) ||
      !ReadHlsSegmentConcurrency(env, argv[5], &options.hls_segment_concurrency)) {
    return Undefined(env);
  }
  if (napi_get_value_bool(env, argv[3], &options.hls) != napi_ok) {
    napi_throw_type_error(env, nullptr, "Native download hls flag must be boolean.");
    return Undefined(env);
  }
  napi_value result = nullptr;
  if (napi_create_int64(env, g_manager.Create(std::move(options)), &result) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create native download task.");
    return Undefined(env);
  }
  return result;
}

template <typename Operation>
napi_value ApplyTaskOperation(napi_env env, napi_callback_info info, const char* name, Operation operation) {
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  std::int64_t handle = 0;
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc != 1 ||
      !ReadHandle(env, argv[0], &handle)) {
    return Undefined(env);
  }
  const auto task = g_manager.Find(handle);
  if (task == nullptr) {
    napi_throw_error(env, nullptr, "Native download task was not found.");
    return Undefined(env);
  }
  napi_value result = nullptr;
  if (napi_get_boolean(env, operation(*task), &result) != napi_ok) {
    napi_throw_error(env, nullptr, name);
    return Undefined(env);
  }
  return result;
}

napi_value StartTask(napi_env env, napi_callback_info info) {
  return ApplyTaskOperation(env, info, "Failed to start native download task.",
                            [](aira::download::DownloadTask& task) { return task.Start(); });
}

napi_value PauseTask(napi_env env, napi_callback_info info) {
  return ApplyTaskOperation(env, info, "Failed to pause native download task.",
                            [](aira::download::DownloadTask& task) { return task.Pause(); });
}

napi_value ResumeTask(napi_env env, napi_callback_info info) {
  return ApplyTaskOperation(env, info, "Failed to resume native download task.",
                            [](aira::download::DownloadTask& task) { return task.Resume(); });
}

napi_value CancelTask(napi_env env, napi_callback_info info) {
  return ApplyTaskOperation(env, info, "Failed to cancel native download task.",
                            [](aira::download::DownloadTask& task) { return task.Cancel(); });
}

napi_value ReleaseTask(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  std::int64_t handle = 0;
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc != 1 ||
      !ReadHandle(env, argv[0], &handle)) {
    return Undefined(env);
  }
  g_manager.Release(handle);
  return Undefined(env);
}

napi_value CleanupHlsArtifacts(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  std::string target_path;
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc != 1 ||
      !ReadString(env, argv[0], kMaxPathBytes, false, &target_path)) {
    return Undefined(env);
  }
  aira::download::CleanupHlsTaskArtifacts(target_path);
  return Undefined(env);
}

napi_value GetSnapshot(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  std::int64_t handle = 0;
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc != 1 ||
      !ReadHandle(env, argv[0], &handle)) {
    return Undefined(env);
  }
  const auto task = g_manager.Find(handle);
  if (task == nullptr) {
    napi_throw_error(env, nullptr, "Native download task was not found.");
    return Undefined(env);
  }
  const TaskSnapshot snapshot = task->Snapshot();
  napi_value result = nullptr;
  napi_value state = nullptr;
  napi_value received = nullptr;
  napi_value total = nullptr;
  napi_value speed = nullptr;
  napi_value error_code = nullptr;
  napi_value error = nullptr;
  napi_value diagnostic = nullptr;
  napi_value failure_phase = nullptr;
  napi_value extension = nullptr;
  if (napi_create_object(env, &result) != napi_ok ||
      napi_create_string_utf8(env, aira::download::TaskStateName(snapshot.state), NAPI_AUTO_LENGTH, &state) != napi_ok ||
      napi_create_int64(env, snapshot.received_bytes, &received) != napi_ok ||
      napi_create_int64(env, snapshot.total_bytes, &total) != napi_ok ||
      napi_create_int64(env, snapshot.speed_bytes_per_second, &speed) != napi_ok ||
      napi_create_int32(env, snapshot.error_code, &error_code) != napi_ok ||
      napi_create_string_utf8(env, snapshot.error_message.c_str(), snapshot.error_message.size(), &error) != napi_ok ||
      napi_create_string_utf8(env, snapshot.diagnostic_message.c_str(), snapshot.diagnostic_message.size(),
                              &diagnostic) != napi_ok ||
      napi_create_string_utf8(env, snapshot.failure_phase.c_str(), snapshot.failure_phase.size(),
                              &failure_phase) != napi_ok ||
      napi_create_string_utf8(env, snapshot.file_extension.c_str(), snapshot.file_extension.size(), &extension) != napi_ok ||
      napi_set_named_property(env, result, "state", state) != napi_ok ||
      napi_set_named_property(env, result, "receivedBytes", received) != napi_ok ||
      napi_set_named_property(env, result, "totalBytes", total) != napi_ok ||
      napi_set_named_property(env, result, "speedBytesPerSecond", speed) != napi_ok ||
      napi_set_named_property(env, result, "errorCode", error_code) != napi_ok ||
      napi_set_named_property(env, result, "errorMessage", error) != napi_ok ||
      napi_set_named_property(env, result, "diagnosticMessage", diagnostic) != napi_ok ||
      napi_set_named_property(env, result, "failurePhase", failure_phase) != napi_ok ||
      napi_set_named_property(env, result, "fileExtension", extension) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create native download snapshot.");
    return Undefined(env);
  }
  return result;
}

napi_value BackendVersion(napi_env env, napi_callback_info) {
  napi_value result = nullptr;
  if (napi_create_string_utf8(env, curl_version(), NAPI_AUTO_LENGTH, &result) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create native download version.");
    return Undefined(env);
  }
  return result;
}

napi_value HlsPolicySummary(napi_env env, napi_callback_info) {
  const std::string summary = aira::download::HlsRetryPolicySummary();
  napi_value result = nullptr;
  if (napi_create_string_utf8(env, summary.c_str(), summary.size(), &result) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create native HLS policy summary.");
    return Undefined(env);
  }
  return result;
}

void Cleanup(void*) {
  g_manager.Shutdown();
}

template <napi_value (*Callback)(napi_env, napi_callback_info)>
napi_value GuardedCallback(napi_env env, napi_callback_info info) noexcept {
  try {
    return Callback(env, info);
  } catch (...) {
    napi_throw_error(env, nullptr, "Unexpected native download bridge failure.");
    return Undefined(env);
  }
}

napi_value RegisterModule(napi_env env, napi_value exports) {
  const napi_property_descriptor properties[] = {
    {"createTask", nullptr, GuardedCallback<CreateTask>, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"startTask", nullptr, GuardedCallback<StartTask>, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"pauseTask", nullptr, GuardedCallback<PauseTask>, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"resumeTask", nullptr, GuardedCallback<ResumeTask>, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"cancelTask", nullptr, GuardedCallback<CancelTask>, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"releaseTask", nullptr, GuardedCallback<ReleaseTask>, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"cleanupHlsArtifacts", nullptr, GuardedCallback<CleanupHlsArtifacts>, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"getSnapshot", nullptr, GuardedCallback<GetSnapshot>, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"backendVersion", nullptr, GuardedCallback<BackendVersion>, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"hlsPolicySummary", nullptr, GuardedCallback<HlsPolicySummary>, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  if (napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties) != napi_ok ||
      napi_add_env_cleanup_hook(env, Cleanup, nullptr) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to register native download module.");
  }
  return exports;
}

static napi_module g_aira_download_module = {
  1,
  0,
  nullptr,
  RegisterModule,
  "aira_download",
  nullptr,
  {nullptr, nullptr, nullptr, nullptr},
};

}  // namespace

extern "C" __attribute__((constructor)) void RegisterAiraDownloadModule() {
  napi_module_register(&g_aira_download_module);
}
