#ifndef AIRA_DOWNLOAD_CORE_H
#define AIRA_DOWNLOAD_CORE_H

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace aira::download {

enum class TaskState {
  kCreated,
  kRunning,
  kPausing,
  kPaused,
  kCompleted,
  kFailed,
  kCanceled,
};

struct TaskOptions {
  std::string url;
  std::string target_path;
  std::vector<std::string> headers;
  std::string ca_path;
  bool hls = false;
  std::size_t hls_segment_concurrency = 8;
};

struct TaskSnapshot {
  TaskState state = TaskState::kCreated;
  std::int64_t received_bytes = 0;
  std::int64_t total_bytes = 0;
  std::int64_t speed_bytes_per_second = 0;
  std::int32_t error_code = 0;
  std::string error_message;
  std::string diagnostic_message;
  std::string failure_phase;
  std::string file_extension;
};

class DownloadTask final {
 public:
  explicit DownloadTask(TaskOptions options);
  ~DownloadTask();

  DownloadTask(const DownloadTask&) = delete;
  DownloadTask& operator=(const DownloadTask&) = delete;

  bool Start();
  bool Pause();
  bool Resume();
  bool Cancel();
  TaskSnapshot Snapshot() const;
  void Shutdown();

 private:
  struct TransferContext;

  void Run();
  void RunHttp();
  void RunHls();
  bool StartWorkerLocked();
  void JoinFinishedWorker();
  bool FinishIfInterrupted();
  void SetTerminalState(TaskState state, const std::string& error_message,
                        std::int32_t error_code = 0,
                        const std::string& diagnostic_message = "",
                        const std::string& failure_phase = "");

  static std::size_t WriteCallback(char* data, std::size_t size, std::size_t count, void* user_data);
  static std::size_t HeaderCallback(char* data, std::size_t size, std::size_t count, void* user_data);
  static int ProgressCallback(void* user_data, std::int64_t download_total, std::int64_t download_now,
                              std::int64_t upload_total, std::int64_t upload_now);
  bool TransferHlsFile(const std::string& url, const std::string& path, const std::string& phase,
                       std::atomic<std::int64_t>* aggregate_received, std::string* error,
                       std::int32_t* error_code, std::string* diagnostic_message);

  const TaskOptions options_;
  mutable std::mutex mutex_;
  std::thread worker_;
  TaskState state_ = TaskState::kCreated;
  std::int64_t received_bytes_ = 0;
  std::int64_t total_bytes_ = 0;
  std::int64_t speed_bytes_per_second_ = 0;
  std::int64_t speed_sample_bytes_ = 0;
  std::int64_t speed_sample_time_ms_ = 0;
  std::int32_t error_code_ = 0;
  std::string error_message_;
  std::string diagnostic_message_;
  std::string failure_phase_;
  std::string file_extension_;
  std::atomic<bool> pause_requested_{false};
  std::atomic<bool> cancel_requested_{false};
  std::atomic<bool> shutdown_requested_{false};
  std::atomic<bool> worker_finished_{false};
};

class DownloadManager final {
 public:
  DownloadManager() = default;
  ~DownloadManager();

  DownloadManager(const DownloadManager&) = delete;
  DownloadManager& operator=(const DownloadManager&) = delete;

  std::int64_t Create(TaskOptions options);
  std::shared_ptr<DownloadTask> Find(std::int64_t handle) const;
  bool Release(std::int64_t handle);
  void Shutdown();

 private:
  mutable std::mutex mutex_;
  std::int64_t next_handle_ = 1;
  std::unordered_map<std::int64_t, std::shared_ptr<DownloadTask>> tasks_;
};

const char* TaskStateName(TaskState state);
std::string HlsRetryPolicySummary();
void CleanupHlsTaskArtifacts(const std::string& target_path);

}  // namespace aira::download

#endif  // AIRA_DOWNLOAD_CORE_H
