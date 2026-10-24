#include "download_core.h"

#include <chrono>
#include <csignal>
#include <cstdlib>
#include <iostream>
#include <sys/resource.h>
#include <thread>

int main(int argc, char** argv) {
  if (const char* limit = std::getenv("AIRA_DOWNLOAD_TEST_FILE_LIMIT")) {
    const auto bytes = static_cast<rlim_t>(std::strtoull(limit, nullptr, 10));
    const rlimit file_limit{bytes, bytes};
    std::signal(SIGXFSZ, SIG_IGN);
    if (setrlimit(RLIMIT_FSIZE, &file_limit) != 0) return 2;
  }
  if (argc < 3) {
    std::cerr << "usage: download_host_test url target [http|hls] [header ...]\n";
    return 2;
  }
  aira::download::TaskOptions options;
  options.url = argv[1];
  options.target_path = argv[2];
  options.hls = argc > 3 && std::string(argv[3]) == "hls";
  int cancel_after_ms = -1, pause_after_ms = -1;
  for (int index = 4; index < argc; ++index) {
    if (std::string(argv[index]) == "--single-attempt") options.http_max_attempts = 1;
    else if (std::string(argv[index]) == "--cancel-retry") cancel_after_ms = 100;
    else if (std::string(argv[index]) == "--pause-retry") pause_after_ms = 100;
    else options.headers.emplace_back(argv[index]);
  }
  aira::download::DownloadTask task(options);
  if (!task.Start()) return 2;
  aira::download::TaskSnapshot snapshot;
  const auto began = std::chrono::steady_clock::now();
  const auto deadline = began + std::chrono::seconds(8);
  while (std::chrono::steady_clock::now() < deadline) {
    snapshot = task.Snapshot();
    if (snapshot.state == aira::download::TaskState::kCompleted ||
        snapshot.state == aira::download::TaskState::kFailed ||
        snapshot.state == aira::download::TaskState::kCanceled ||
        snapshot.state == aira::download::TaskState::kPaused) break;
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - began).count();
    if (cancel_after_ms >= 0 && elapsed >= cancel_after_ms) { task.Cancel(); cancel_after_ms = -1; }
    if (pause_after_ms >= 0 && elapsed >= pause_after_ms) { task.Pause(); pause_after_ms = -1; }
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  std::cout << aira::download::TaskStateName(snapshot.state)
            << " code=" << snapshot.error_code << " phase=" << snapshot.failure_phase
            << " message=" << snapshot.error_message << " diagnostic=" << snapshot.diagnostic_message << '\n';
  return snapshot.state == aira::download::TaskState::kCompleted ? 0 : 1;
}
