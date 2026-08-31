#include "aira_adblock_rust.h"

#include <node_api.h>

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

namespace {

constexpr size_t kMaxPathBytes = 4096;
constexpr size_t kMaxUrlBytes = 64 * 1024;
constexpr size_t kMaxRequestTypeBytes = 32;
constexpr size_t kMaxMethodBytes = 32;
constexpr size_t kMaxCspBytes = 64 * 1024;
constexpr size_t kMaxRedirectDataUrlBytes = 512 * 1024;
constexpr size_t kMaxRewrittenUrlBytes = 64 * 1024;
constexpr size_t kMaxCosmeticJsonBytes = 512 * 1024;
constexpr size_t kMaxInjectedScriptBytes = 512 * 1024;

class EngineHolder {
 public:
  explicit EngineHolder(AiraAdblockEngine* engine) : engine_(engine) {}
  ~EngineHolder() { aira_adblock_engine_destroy(engine_); }

  EngineHolder(const EngineHolder&) = delete;
  EngineHolder& operator=(const EngineHolder&) = delete;

  const AiraAdblockEngine* get() const { return engine_; }

 private:
  AiraAdblockEngine* engine_;
};

class CheckResultHolder {
 public:
  explicit CheckResultHolder(AiraAdblockCheckResult* result) : result_(result) {}
  ~CheckResultHolder() { aira_adblock_check_result_destroy(result_); }

  CheckResultHolder(const CheckResultHolder&) = delete;
  CheckResultHolder& operator=(const CheckResultHolder&) = delete;

  const AiraAdblockCheckResult* get() const { return result_; }

 private:
  AiraAdblockCheckResult* result_;
};

bool ReadResultString(const uint8_t* value, size_t length, size_t maximum, std::string* output) {
  if (length > maximum || (length > 0 && value == nullptr)) {
    return false;
  }
  if (length == 0) {
    output->clear();
    return true;
  }
  output->assign(reinterpret_cast<const char*>(value), length);
  return true;
}

std::mutex g_engines_mutex;
std::unordered_map<int64_t, std::shared_ptr<EngineHolder>> g_engines;
std::atomic<int64_t> g_next_handle{1};

struct BuildEngineWork {
  napi_async_work work = nullptr;
  napi_deferred deferred = nullptr;
  std::string path;
  AiraAdblockEngine* engine = nullptr;
  size_t network_rule_count = 0;
  size_t cosmetic_rule_count = 0;
  size_t rule_count = 0;
  int32_t status = 1;
};

napi_value Undefined(napi_env env) {
  napi_value value = nullptr;
  napi_get_undefined(env, &value);
  return value;
}

bool ReadString(napi_env env, napi_value value, size_t maximum, bool allow_empty, std::string* output) {
  size_t length = 0;
  if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok ||
      length > maximum || (!allow_empty && length == 0)) {
    napi_throw_type_error(env, nullptr, "Invalid native ad-block string argument.");
    return false;
  }
  std::string result(length + 1, '\0');
  size_t written = 0;
  if (napi_get_value_string_utf8(env, value, result.data(), length + 1, &written) != napi_ok ||
      written != length) {
    napi_throw_type_error(env, nullptr, "Failed to read native ad-block string argument.");
    return false;
  }
  result.resize(length);
  *output = std::move(result);
  return true;
}

bool ReadHandle(napi_env env, napi_value value, int64_t* output) {
  int64_t handle = 0;
  if (napi_get_value_int64(env, value, &handle) != napi_ok || handle <= 0) {
    napi_throw_type_error(env, nullptr, "Invalid native ad-block engine handle.");
    return false;
  }
  *output = handle;
  return true;
}

napi_value CreateError(napi_env env, const char* message) {
  napi_value error_message = nullptr;
  napi_value error = nullptr;
  if (napi_create_string_utf8(env, message, NAPI_AUTO_LENGTH, &error_message) != napi_ok ||
      napi_create_error(env, nullptr, error_message, &error) != napi_ok) {
    return nullptr;
  }
  return error;
}

void RejectDeferred(napi_env env, napi_deferred deferred, const char* message) {
  napi_value error = CreateError(env, message);
  if (error != nullptr) {
    napi_reject_deferred(env, deferred, error);
  }
}

void CleanupEngines(void*) {
  std::lock_guard<std::mutex> lock(g_engines_mutex);
  g_engines.clear();
}

std::shared_ptr<EngineHolder> FindEngine(int64_t handle) {
  std::lock_guard<std::mutex> lock(g_engines_mutex);
  const auto found = g_engines.find(handle);
  return found == g_engines.end() ? nullptr : found->second;
}

void ExecuteBuildEngine(napi_env, void* data) {
  auto* work = static_cast<BuildEngineWork*>(data);
  work->status = aira_adblock_engine_create_from_file(
      reinterpret_cast<const uint8_t*>(work->path.data()), work->path.size(), &work->engine);
  if (work->status == 0 && work->engine != nullptr) {
    work->network_rule_count = aira_adblock_engine_network_rule_count(work->engine);
    work->cosmetic_rule_count = aira_adblock_engine_cosmetic_rule_count(work->engine);
    work->rule_count = aira_adblock_engine_rule_count(work->engine);
  }
}

void CompleteBuildEngine(napi_env env, napi_status completion_status, void* data) {
  std::unique_ptr<BuildEngineWork> work(static_cast<BuildEngineWork*>(data));
  if (work->work != nullptr) {
    napi_delete_async_work(env, work->work);
    work->work = nullptr;
  }
  if (completion_status != napi_ok || work->status != 0 || work->engine == nullptr) {
    if (work->engine != nullptr) {
      aira_adblock_engine_destroy(work->engine);
      work->engine = nullptr;
    }
    RejectDeferred(env, work->deferred, "Native ad-block engine build failed.");
    return;
  }
  const int64_t handle = g_next_handle.fetch_add(1, std::memory_order_relaxed);
  if (handle <= 0) {
    aira_adblock_engine_destroy(work->engine);
    work->engine = nullptr;
    RejectDeferred(env, work->deferred, "Native ad-block engine handle space exhausted.");
    return;
  }
  std::shared_ptr<EngineHolder> holder;
  bool inserted = false;
  try {
    holder = std::make_shared<EngineHolder>(work->engine);
    work->engine = nullptr;
    std::lock_guard<std::mutex> lock(g_engines_mutex);
    inserted = g_engines.emplace(handle, holder).second;
  } catch (...) {
    if (work->engine != nullptr) {
      aira_adblock_engine_destroy(work->engine);
      work->engine = nullptr;
    }
    RejectDeferred(env, work->deferred, "Native ad-block engine registration failed.");
    return;
  }
  if (!inserted) {
    RejectDeferred(env, work->deferred, "Native ad-block engine handle collision.");
    return;
  }
  napi_value result = nullptr;
  napi_value handle_value = nullptr;
  napi_value rule_count_value = nullptr;
  napi_value cosmetic_rule_count_value = nullptr;
  napi_value total_rule_count_value = nullptr;
  if (napi_create_object(env, &result) != napi_ok ||
      napi_create_int64(env, handle, &handle_value) != napi_ok ||
      napi_create_int64(env, static_cast<int64_t>(work->network_rule_count), &rule_count_value) != napi_ok ||
      napi_create_int64(env, static_cast<int64_t>(work->cosmetic_rule_count), &cosmetic_rule_count_value) != napi_ok ||
      napi_create_int64(env, static_cast<int64_t>(work->rule_count), &total_rule_count_value) != napi_ok ||
      napi_set_named_property(env, result, "handle", handle_value) != napi_ok ||
      napi_set_named_property(env, result, "networkRuleCount", rule_count_value) != napi_ok ||
      napi_set_named_property(env, result, "cosmeticRuleCount", cosmetic_rule_count_value) != napi_ok ||
      napi_set_named_property(env, result, "ruleCount", total_rule_count_value) != napi_ok) {
    {
      std::lock_guard<std::mutex> lock(g_engines_mutex);
      g_engines.erase(handle);
    }
    RejectDeferred(env, work->deferred, "Native ad-block engine result creation failed.");
    return;
  }
  if (napi_resolve_deferred(env, work->deferred, result) != napi_ok) {
    std::lock_guard<std::mutex> lock(g_engines_mutex);
    g_engines.erase(handle);
  }
}

napi_value BuildEngine(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc != 1) {
    napi_throw_type_error(env, nullptr, "buildEngine expects one ruleset path.");
    return Undefined(env);
  }
  auto work = std::make_unique<BuildEngineWork>();
  if (!ReadString(env, argv[0], kMaxPathBytes, false, &work->path)) {
    return Undefined(env);
  }
  napi_value promise = nullptr;
  napi_value resource_name = nullptr;
  if (napi_create_promise(env, &work->deferred, &promise) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create native ad-block build promise.");
    return Undefined(env);
  }
  if (napi_create_string_utf8(env, "aira-adblock-rust-build", NAPI_AUTO_LENGTH, &resource_name) != napi_ok) {
    RejectDeferred(env, work->deferred, "Native ad-block async build setup failed.");
    return promise;
  }
  if (napi_create_async_work(env, nullptr, resource_name, ExecuteBuildEngine, CompleteBuildEngine,
                             work.get(), &work->work) != napi_ok) {
    if (work->work != nullptr) {
      napi_delete_async_work(env, work->work);
      work->work = nullptr;
    }
    RejectDeferred(env, work->deferred, "Native ad-block async build setup failed.");
    return promise;
  }
  if (napi_queue_async_work(env, work->work) != napi_ok) {
    if (work->work != nullptr) {
      napi_delete_async_work(env, work->work);
      work->work = nullptr;
    }
    RejectDeferred(env, work->deferred, "Native ad-block async build queue failed.");
    return promise;
  }
  work.release();
  return promise;
}

napi_value ReleaseEngine(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  int64_t handle = 0;
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc != 1 ||
      !ReadHandle(env, argv[0], &handle)) {
    return Undefined(env);
  }
  std::lock_guard<std::mutex> lock(g_engines_mutex);
  g_engines.erase(handle);
  return Undefined(env);
}

napi_value CheckRequest(napi_env env, napi_callback_info info) {
  size_t argc = 6;
  napi_value argv[6] = {nullptr, nullptr, nullptr, nullptr, nullptr, nullptr};
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc != 6) {
    napi_throw_type_error(env, nullptr, "checkRequest expects a handle, four request strings, and a CSP flag.");
    return Undefined(env);
  }
  int64_t handle = 0;
  std::string url;
  std::string source_url;
  std::string request_type;
  std::string method;
  bool include_csp = false;
  if (!ReadHandle(env, argv[0], &handle) ||
      !ReadString(env, argv[1], kMaxUrlBytes, false, &url) ||
      !ReadString(env, argv[2], kMaxUrlBytes, true, &source_url) ||
      !ReadString(env, argv[3], kMaxRequestTypeBytes, false, &request_type) ||
      !ReadString(env, argv[4], kMaxMethodBytes, false, &method)) {
    return Undefined(env);
  }
  if (napi_get_value_bool(env, argv[5], &include_csp) != napi_ok) {
    napi_throw_type_error(env, nullptr, "Invalid native ad-block CSP flag.");
    return Undefined(env);
  }
  const std::shared_ptr<EngineHolder> engine = FindEngine(handle);
  if (engine == nullptr) {
    napi_throw_type_error(env, nullptr, "Native ad-block engine handle is not active.");
    return Undefined(env);
  }
  AiraAdblockCheckResult* raw_result = nullptr;
  const int32_t status = aira_adblock_engine_check(
      engine->get(),
      reinterpret_cast<const uint8_t*>(url.data()), url.size(),
      reinterpret_cast<const uint8_t*>(source_url.data()), source_url.size(),
      reinterpret_cast<const uint8_t*>(request_type.data()), request_type.size(),
      reinterpret_cast<const uint8_t*>(method.data()), method.size(),
      include_csp ? 1 : 0,
      &raw_result);
  if (status != 0 || raw_result == nullptr) {
    if (raw_result != nullptr) {
      aira_adblock_check_result_destroy(raw_result);
    }
    napi_throw_type_error(env, nullptr, "Native ad-block request evaluation failed.");
    return Undefined(env);
  }
  CheckResultHolder check_result(raw_result);
  const bool should_block = aira_adblock_check_result_should_block(check_result.get()) != 0;
  size_t csp_length = 0;
  const uint8_t* csp_data = aira_adblock_check_result_csp(check_result.get(), &csp_length);
  size_t redirect_length = 0;
  const uint8_t* redirect_data = aira_adblock_check_result_redirect(check_result.get(), &redirect_length);
  size_t rewritten_length = 0;
  const uint8_t* rewritten_data = aira_adblock_check_result_rewritten_url(check_result.get(), &rewritten_length);
  std::string csp;
  std::string redirect_data_url;
  std::string rewritten_url;
  if (!ReadResultString(csp_data, csp_length, kMaxCspBytes, &csp) ||
      !ReadResultString(redirect_data, redirect_length, kMaxRedirectDataUrlBytes, &redirect_data_url) ||
      !ReadResultString(rewritten_data, rewritten_length, kMaxRewrittenUrlBytes, &rewritten_url)) {
    napi_throw_type_error(env, nullptr, "Native ad-block request result exceeded bridge limits.");
    return Undefined(env);
  }
  napi_value result = nullptr;
  napi_value blocked_value = nullptr;
  napi_value csp_value = nullptr;
  napi_value redirect_value = nullptr;
  napi_value rewritten_value = nullptr;
  if (napi_create_object(env, &result) != napi_ok ||
      napi_get_boolean(env, should_block, &blocked_value) != napi_ok ||
      napi_create_string_utf8(env, csp.data(), csp.size(), &csp_value) != napi_ok ||
      napi_create_string_utf8(env, redirect_data_url.data(), redirect_data_url.size(), &redirect_value) != napi_ok ||
      napi_create_string_utf8(env, rewritten_url.data(), rewritten_url.size(), &rewritten_value) != napi_ok ||
      napi_set_named_property(env, result, "shouldBlock", blocked_value) != napi_ok ||
      napi_set_named_property(env, result, "cspDirectives", csp_value) != napi_ok ||
      napi_set_named_property(env, result, "redirectDataUrl", redirect_value) != napi_ok ||
      napi_set_named_property(env, result, "rewrittenUrl", rewritten_value) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create native ad-block request result.");
    return Undefined(env);
  }
  return result;
}

class CosmeticResultHolder {
 public:
  explicit CosmeticResultHolder(AiraAdblockCosmeticResult* result) : result_(result) {}
  ~CosmeticResultHolder() { aira_adblock_cosmetic_result_destroy(result_); }
  const AiraAdblockCosmeticResult* get() const { return result_; }
 private:
  AiraAdblockCosmeticResult* result_;
};

napi_value GetCosmeticResources(napi_env env, napi_callback_info info) {
  size_t argc = 4;
  napi_value argv[4] = {nullptr, nullptr, nullptr, nullptr};
  int64_t handle = 0;
  std::string url;
  std::string classes_json;
  std::string ids_json;
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc != 4 ||
      !ReadHandle(env, argv[0], &handle) ||
      !ReadString(env, argv[1], kMaxUrlBytes, false, &url) ||
      !ReadString(env, argv[2], kMaxCosmeticJsonBytes, false, &classes_json) ||
      !ReadString(env, argv[3], kMaxCosmeticJsonBytes, false, &ids_json)) {
    return Undefined(env);
  }
  const std::shared_ptr<EngineHolder> engine = FindEngine(handle);
  if (engine == nullptr) {
    napi_throw_type_error(env, nullptr, "Native ad-block engine handle is not active.");
    return Undefined(env);
  }
  AiraAdblockCosmeticResult* raw_result = nullptr;
  const int32_t status = aira_adblock_engine_cosmetic_resources(
      engine->get(),
      reinterpret_cast<const uint8_t*>(url.data()), url.size(),
      reinterpret_cast<const uint8_t*>(classes_json.data()), classes_json.size(),
      reinterpret_cast<const uint8_t*>(ids_json.data()), ids_json.size(),
      &raw_result);
  if (status != 0 || raw_result == nullptr) {
    if (raw_result != nullptr) {
      aira_adblock_cosmetic_result_destroy(raw_result);
    }
    napi_throw_type_error(env, nullptr, "Native ad-block cosmetic evaluation failed.");
    return Undefined(env);
  }
  CosmeticResultHolder result(raw_result);
  size_t hide_length = 0;
  size_t action_length = 0;
  size_t exception_length = 0;
  size_t script_length = 0;
  const uint8_t* hide_data = aira_adblock_cosmetic_result_hide_selectors(result.get(), &hide_length);
  const uint8_t* action_data = aira_adblock_cosmetic_result_procedural_actions(result.get(), &action_length);
  const uint8_t* exception_data = aira_adblock_cosmetic_result_exceptions(result.get(), &exception_length);
  const uint8_t* script_data = aira_adblock_cosmetic_result_script(result.get(), &script_length);
  std::string hide;
  std::string actions;
  std::string exceptions;
  std::string script;
  if (!ReadResultString(hide_data, hide_length, kMaxCosmeticJsonBytes, &hide) ||
      !ReadResultString(action_data, action_length, kMaxCosmeticJsonBytes, &actions) ||
      !ReadResultString(exception_data, exception_length, kMaxCosmeticJsonBytes, &exceptions) ||
      !ReadResultString(script_data, script_length, kMaxInjectedScriptBytes, &script)) {
    napi_throw_type_error(env, nullptr, "Native ad-block cosmetic result exceeded bridge limits.");
    return Undefined(env);
  }
  napi_value output = nullptr;
  napi_value hide_value = nullptr;
  napi_value actions_value = nullptr;
  napi_value exceptions_value = nullptr;
  napi_value script_value = nullptr;
  napi_value generichide_value = nullptr;
  if (napi_create_object(env, &output) != napi_ok ||
      napi_create_string_utf8(env, hide.data(), hide.size(), &hide_value) != napi_ok ||
      napi_create_string_utf8(env, actions.data(), actions.size(), &actions_value) != napi_ok ||
      napi_create_string_utf8(env, exceptions.data(), exceptions.size(), &exceptions_value) != napi_ok ||
      napi_create_string_utf8(env, script.data(), script.size(), &script_value) != napi_ok ||
      napi_get_boolean(env, aira_adblock_cosmetic_result_generichide(result.get()) != 0, &generichide_value) != napi_ok ||
      napi_set_named_property(env, output, "hideSelectorsJson", hide_value) != napi_ok ||
      napi_set_named_property(env, output, "proceduralActionsJson", actions_value) != napi_ok ||
      napi_set_named_property(env, output, "exceptionsJson", exceptions_value) != napi_ok ||
      napi_set_named_property(env, output, "injectedScript", script_value) != napi_ok ||
      napi_set_named_property(env, output, "generichide", generichide_value) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create native ad-block cosmetic result.");
    return Undefined(env);
  }
  return output;
}

napi_value BackendVersion(napi_env env, napi_callback_info) {
  napi_value result = nullptr;
  if (napi_create_string_utf8(env, aira_adblock_engine_version(), NAPI_AUTO_LENGTH, &result) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create native ad-block version result.");
    return Undefined(env);
  }
  return result;
}

template <napi_value (*Callback)(napi_env, napi_callback_info)>
napi_value GuardedCallback(napi_env env, napi_callback_info info) noexcept {
  try {
    return Callback(env, info);
  } catch (...) {
    napi_throw_error(env, nullptr, "Unexpected native ad-block bridge failure.");
    return Undefined(env);
  }
}

napi_value RegisterModule(napi_env env, napi_value exports) {
  const napi_property_descriptor properties[] = {
      {"buildEngine", nullptr, GuardedCallback<BuildEngine>, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"releaseEngine", nullptr, GuardedCallback<ReleaseEngine>, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"checkRequest", nullptr, GuardedCallback<CheckRequest>, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"getCosmeticResources", nullptr, GuardedCallback<GetCosmeticResources>, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"backendVersion", nullptr, GuardedCallback<BackendVersion>, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  if (napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties) != napi_ok ||
      napi_add_env_cleanup_hook(env, CleanupEngines, nullptr) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to register native ad-block module.");
  }
  return exports;
}

}  // namespace

static napi_module g_aira_adblock_module = {
    1,
    0,
    nullptr,
    RegisterModule,
    "aira_adblock",
    nullptr,
    {nullptr, nullptr, nullptr, nullptr},
};

extern "C" __attribute__((constructor)) void RegisterAiraAdblockModule() {
  napi_module_register(&g_aira_adblock_module);
}
